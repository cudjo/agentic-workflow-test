extends Node
## AudioManager — шины Master/Music/SFX, музыка зон с кроссфейдом, SFX,
## «субтитры звуков» (T-34, PLAN §2.2/§3.5, SPEC US-07, AC-07.2, DESIGN §9.4).
##
## Контракт звукового контента (замена без изменения логики):
##   музыка зоны  -> res://assets/audio/music/<zone_id>.ogg|.wav
##   SFX           -> res://assets/audio/sfx/<sfx_id>.wav|.ogg
## Если файла нет — используется программная заглушка (AudioStreamWAV),
## сгенерированная детерминированно. Логика, тайминги и субтитры от этого
## не зависят: положив CC0-ассет с тем же именем, его получит тот же вызов.
##
## Музыка: два AudioStreamPlayer (A/B) на шине Music. `zone_loaded` (T-17)
## запускает кроссфейд ≤ CROSSFADE_TIME (0.8 с ≤ 1 с), поэтому смена трека
## укладывается в AC-07.2 (≤ 2 с) и не даёт провала в тишину: суммарная
## громкость во время фейда не падает до нуля.
##
## Громкости читаются из Config (master/music/sfx_volume) и переприменяются
## по сигналу `Config.audio_settings_changed` (сеттеры T-20).
##
## Субтитры: значимые SFX (удар, парирование, смерть, смена фазы, босс рядом)
## дополнительно отдаются сигналом `subtitle_requested`, который показывает
## ToastHost (ui/components/toast_host.gd) через AshenToast. Тумблер —
## `Config.sound_subtitles`; UI-автолоады не рисуют напрямую.

## Субтитр для показа (ToastHost → AshenToast). `danger` — красный тост.
signal subtitle_requested(text: String, danger: bool)
## Начался переход к новому треку (кроссфейд).
signal music_track_changed(track_id: StringName)
## Кроссфейд завершён: новый трек играет один.
signal crossfade_finished(track_id: StringName)

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"

## AC-07.2: кроссфейд ≤ 1 с (смена трека ≤ 2 с).
const CROSSFADE_TIME: float = 0.8
## Нижняя граница громкости шины; -80 dB вместо -inf, чтобы значение было
## предсказуемым в тестах и настройках.
const SILENCE_DB: float = -80.0
## Минимальный интервал повторного показа одинакового субтитра (анти-спам
## при серии ударов).
const SUBTITLE_REPEAT_MS: int = 500

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_EXTENSIONS: Array[String] = [".ogg", ".wav"]
const SFX_EXTENSIONS: Array[String] = [".wav", ".ogg"]

const MUSIC_SAMPLE_RATE: int = 16000
const SFX_SAMPLE_RATE: int = 22050
const MUSIC_LOOP_SECONDS: float = 4.0

const SFX_POOL_SIZE: int = 8

## Описание публичных SFX: субтитр (DESIGN §9.4) и «опасность» для тоста.
## Идентификаторы — стабильный контракт для боевых систем (T-10/T-11/T-26).
const SFX_SPECS: Dictionary = {
	&"hit": {"subtitle": "ui.audio.hit", "danger": false},
	&"parry": {"subtitle": "ui.audio.parry", "danger": false},
	&"death": {"subtitle": "ui.audio.death", "danger": true},
	&"phase": {"subtitle": "ui.audio.phase", "danger": true},
	&"boss_near": {"subtitle": "ui.audio.boss_near", "danger": true},
}

## Длительность кроссфейда текущего перехода; тесты могут уменьшать, но не
## больше 1 с (AC-07.2).
var crossfade_time: float = CROSSFADE_TIME

## Последний показанный субтитр (для логов/QA и smoke-проверок).
var last_subtitle: String = ""
## Сколько субтитров показано с последнего `reset()`.
var subtitle_count: int = 0
## Последний проигранный SFX и их количество (QA/smoke).
var last_sfx_id: StringName = &""
var sfx_count: int = 0

var _music_players: Array[AudioStreamPlayer] = []
var _music_track_ids: Array[StringName] = [&"", &""]
var _music_levels: Array[float] = [0.0, 0.0]
var _active_music: int = -1
var _fading: bool = false
var _fade_elapsed: float = 0.0
var _fade_from: int = -1
var _fade_to: int = -1
var _fade_from_level: float = 0.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0

var _stream_cache: Dictionary = {}
var _subtitle_last_ms: Dictionary = {}


func _ready() -> void:
	_ensure_buses()
	_ensure_music_players()
	_ensure_sfx_pool()
	apply_settings()
	set_process(false)

	if Config.has_signal(&"audio_settings_changed"):
		if not Config.audio_settings_changed.is_connected(apply_settings):
			Config.audio_settings_changed.connect(apply_settings)

	if not EventBus.zone_loaded.is_connected(_on_zone_loaded):
		EventBus.zone_loaded.connect(_on_zone_loaded)
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)
	if not EventBus.boss_fight_started.is_connected(_on_boss_fight_started):
		EventBus.boss_fight_started.connect(_on_boss_fight_started)
	if not EventBus.boss_phase_changed.is_connected(_on_boss_phase_changed):
		EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	if not EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.connect(_on_boss_defeated)


func _process(delta: float) -> void:
	advance(delta)


func _exit_tree() -> void:
	# Останавливаем плейбеки и отпускаем потоки до завершения AudioServer.
	AudioServer.lock()
	reset()
	_stream_cache.clear()
	AudioServer.unlock()


# ------------------------------------------------------------------------------
# Шины и настройки (AC: громкости Master/Music/SFX из Config)
# ------------------------------------------------------------------------------

## Создаёт шины Music/SFX при первом запуске (идемпотентно). Master в Godot
## существует всегда (индекс 0) и служит выходом для обеих шин.
func _ensure_buses() -> void:
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)


func _ensure_bus(bus_name: StringName) -> int:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	AudioServer.add_bus()
	index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, BUS_MASTER)
	AudioServer.set_bus_volume_db(index, 0.0)
	return index


## Применяет значения Config к шинам. Вызывается при старте и по сигналу
## `Config.audio_settings_changed` (слайдеры T-20).
func apply_settings() -> void:
	_ensure_buses()
	_set_bus_volume(BUS_MASTER, Config.master_volume)
	_set_bus_volume(BUS_MUSIC, Config.music_volume)
	_set_bus_volume(BUS_SFX, Config.sfx_volume)


func _set_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var value: float = clampf(linear_volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, SILENCE_DB if value <= 0.0001 else linear_to_db(value))


## Линейная громкость шины (0…1) — для настроек/тестов.
func get_bus_linear_volume(bus_name: StringName) -> float:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.0, 1.0)


# ------------------------------------------------------------------------------
# Музыка: смена трека зоны с кроссфейдом (AC-07.2)
# ------------------------------------------------------------------------------

func _ensure_music_players() -> void:
	if _music_players.size() == 2:
		return
	for index: int in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % index
		player.bus = BUS_MUSIC
		player.volume_db = SILENCE_DB
		add_child(player)
		_music_players.append(player)


## Запускает трек; при уже играющей музыке — кроссфейд. `stream` позволяет
## подставить поток явно (тесты/катсцены), иначе ищется файл зоны, затем
## программная заглушка. `fade_duration < 0` — CROSSFADE_TIME.
func request_music(track_id: StringName, stream: AudioStream = null, fade_duration: float = -1.0) -> bool:
	_ensure_music_players()
	if track_id == &"":
		return false

	if not _fading and _active_music >= 0 and _music_track_ids[_active_music] == track_id:
		return false
	if _fading and _fade_to >= 0 and _music_track_ids[_fade_to] == track_id:
		return false

	var resolved: AudioStream = stream
	if resolved == null:
		resolved = _music_stream(track_id)
	if resolved == null:
		push_warning("AudioManager: нет музыкального потока для '%s'" % track_id)
		return false

	_start_crossfade(track_id, resolved, fade_duration)
	return true


func _start_crossfade(track_id: StringName, stream: AudioStream, fade_duration: float) -> void:
	# Прерываем текущий фейд без щелчка: доводим его до текущего состояния,
	# гасим проигравшего и считаем звучащим только целевой трек.
	if _fading:
		var previous_target: int = _fade_to
		for index: int in 2:
			if index != previous_target:
				_stop_music_player(index)
		_active_music = previous_target
		_fading = false
		_fade_from = -1
		_fade_to = -1

	var from_index: int = _active_music
	var to_index: int = 0 if from_index != 0 else 1
	if from_index < 0:
		from_index = -1
		to_index = 0

	_stop_music_player(to_index)
	_music_track_ids[to_index] = track_id
	_music_levels[to_index] = 0.0

	var incoming: AudioStreamPlayer = _music_players[to_index]
	incoming.stream = stream
	incoming.volume_db = SILENCE_DB
	incoming.play()

	_fade_from = from_index
	_fade_to = to_index
	_fade_from_level = _music_levels[from_index] if from_index >= 0 else 0.0
	_fade_elapsed = 0.0
	crossfade_time = clampf(CROSSFADE_TIME if fade_duration < 0.0 else fade_duration, 0.0, 1.0)

	music_track_changed.emit(track_id)

	if crossfade_time <= 0.0:
		_music_levels[to_index] = 1.0
		if from_index >= 0:
			_music_levels[from_index] = 0.0
		_apply_music_levels()
		_finish_crossfade()
		return

	_fading = true
	_update_fade(0.0)
	set_process(true)


## Продвигает кроссфейд вручную. `_process` вызывает это каждый кадр; тесты
## могут «промотать» время без ожидания реальных секунд.
func advance(delta: float) -> void:
	if not _fading:
		return
	_fade_elapsed += maxf(delta, 0.0)
	var duration: float = maxf(crossfade_time, 0.0001)
	var progress: float = clampf(_fade_elapsed / duration, 0.0, 1.0)
	_update_fade(progress)
	if progress >= 1.0:
		_finish_crossfade()


func _update_fade(progress: float) -> void:
	var shaped: float = smoothstep(0.0, 1.0, progress)
	_music_levels[_fade_to] = shaped
	if _fade_from >= 0:
		_music_levels[_fade_from] = _fade_from_level * (1.0 - shaped)
	_apply_music_levels()


func _apply_music_levels() -> void:
	for index: int in _music_players.size():
		var player: AudioStreamPlayer = _music_players[index]
		var level: float = _music_levels[index]
		player.volume_db = SILENCE_DB if level <= 0.0001 else linear_to_db(level)


func _finish_crossfade() -> void:
	var finished_index: int = _fade_to
	var finished_track: StringName = _music_track_ids[finished_index]
	if _fade_from >= 0:
		_stop_music_player(_fade_from)
		_music_track_ids[_fade_from] = &""
	_music_levels[finished_index] = 1.0
	_apply_music_levels()
	_active_music = finished_index
	_fading = false
	_fade_from = -1
	_fade_to = -1
	set_process(false)
	crossfade_finished.emit(finished_track)


func _stop_music_player(index: int) -> void:
	if index < 0 or index >= _music_players.size():
		return
	var player: AudioStreamPlayer = _music_players[index]
	player.stop()
	player.stream = null
	player.volume_db = SILENCE_DB
	_music_levels[index] = 0.0


## Текущий/целевой трек (во время кроссфейда — входящий).
func get_current_track_id() -> StringName:
	if _fading and _fade_to >= 0:
		return _music_track_ids[_fade_to]
	if _active_music >= 0:
		return _music_track_ids[_active_music]
	return &""


func is_crossfading() -> bool:
	return _fading


func get_crossfade_progress() -> float:
	if not _fading:
		return 1.0
	return clampf(_fade_elapsed / maxf(crossfade_time, 0.0001), 0.0, 1.0)


## Линейные уровни обоих плееров (A/B) — для проверки «без обрыва».
func get_music_levels() -> Array[float]:
	return [_music_levels[0], _music_levels[1]]


func is_music_playing() -> bool:
	if _active_music >= 0 and _music_players[_active_music].playing:
		return true
	return _fading and _fade_to >= 0 and _music_players[_fade_to].playing


## Останавливает музыку и сбрасывает состояние (новый забег/тесты).
func reset() -> void:
	for index: int in _music_players.size():
		_stop_music_player(index)
	for index: int in _sfx_players.size():
		_sfx_players[index].stop()
		_sfx_players[index].stream = null
	_music_track_ids = [&"", &""]
	_music_levels = [0.0, 0.0]
	_active_music = -1
	_fading = false
	_fade_elapsed = 0.0
	_fade_from = -1
	_fade_to = -1
	_fade_from_level = 0.0
	last_subtitle = ""
	subtitle_count = 0
	last_sfx_id = &""
	sfx_count = 0
	_subtitle_last_ms.clear()
	set_process(false)


func _music_stream(track_id: StringName) -> AudioStream:
	var cache_key: String = "music:" + String(track_id)
	if _stream_cache.has(cache_key):
		return _stream_cache[cache_key] as AudioStream

	var stream: AudioStream = _load_audio_file(MUSIC_DIR, String(track_id), MUSIC_EXTENSIONS)
	if stream == null:
		stream = _make_music_placeholder(track_id)
	_stream_cache[cache_key] = stream
	return stream


func _load_audio_file(directory: String, file_id: String, extensions: Array[String]) -> AudioStream:
	for extension: String in extensions:
		var path: String = directory + file_id + extension
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path) as AudioStream
			if stream != null:
				return stream
	return null


# ------------------------------------------------------------------------------
# SFX (удар/парирование/смерть/смена фазы/босс рядом)
# ------------------------------------------------------------------------------

func _ensure_sfx_pool() -> void:
	if not _sfx_players.is_empty():
		return
	for index: int in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % index
		player.bus = BUS_SFX
		add_child(player)
		_sfx_players.append(player)


## Проигрывает SFX по стабильному id. Для значимых звуков дополнительно
## показывает субтитр (если Config.sound_subtitles включён). Возвращает false
## для неизвестного id.
func play_sfx(sfx_id: StringName, with_subtitle: bool = true) -> bool:
	_ensure_sfx_pool()
	var stream: AudioStream = _sfx_stream(sfx_id)
	if stream == null:
		return false

	var player: AudioStreamPlayer = _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = 0.0
	player.play()

	last_sfx_id = sfx_id
	sfx_count += 1

	if with_subtitle:
		var spec: Dictionary = SFX_SPECS.get(sfx_id, {})
		var text: String = str(spec.get("subtitle", ""))
		if not text.is_empty():
			_emit_subtitle(text, bool(spec.get("danger", false)))
	return true


func has_sfx(sfx_id: StringName) -> bool:
	return SFX_SPECS.has(sfx_id)


func _sfx_stream(sfx_id: StringName) -> AudioStream:
	var cache_key: String = "sfx:" + String(sfx_id)
	if _stream_cache.has(cache_key):
		return _stream_cache[cache_key] as AudioStream
	if not SFX_SPECS.has(sfx_id):
		return null

	var stream: AudioStream = _load_audio_file(SFX_DIR, String(sfx_id), SFX_EXTENSIONS)
	if stream == null:
		stream = _make_sfx_placeholder(sfx_id)
	_stream_cache[cache_key] = stream
	return stream


# ------------------------------------------------------------------------------
# Субтитры звуков (DESIGN §9.4, a11y)
# ------------------------------------------------------------------------------

## Показать субтитр значимого звука. `force` обходит анти-спам (смена фазы,
## смерть). Сигнал потребляет ToastHost → AshenToast.
func _emit_subtitle(text: String, danger: bool = false, force: bool = false) -> void:
	if not Config.sound_subtitles:
		return
	var message: String = tr(text)
	var now_ms: int = Time.get_ticks_msec()
	if not force and _subtitle_last_ms.has(message):
		var previous_ms: int = int(_subtitle_last_ms[message])
		if now_ms - previous_ms < SUBTITLE_REPEAT_MS:
			return
	_subtitle_last_ms[message] = now_ms
	last_subtitle = message
	subtitle_count += 1
	subtitle_requested.emit(message, danger)


# ------------------------------------------------------------------------------
# События EventBus
# ------------------------------------------------------------------------------

func _on_zone_loaded(zone_id: StringName, _display_name: String) -> void:
	request_music(zone_id)


func _on_player_died() -> void:
	play_sfx(&"death")


func _on_boss_fight_started(
	_boss_id: StringName,
	display_name: String,
	_max_hp: float,
	_thresholds: PackedFloat32Array
) -> void:
	play_sfx(&"boss_near", false)
	_emit_subtitle(tr("ui.audio.boss_near_named") % display_name, true, true)


func _on_boss_phase_changed(
	_boss_id: StringName,
	_phase_index: int,
	phase_title: String
) -> void:
	play_sfx(&"phase", false)
	_emit_subtitle(tr("ui.audio.phase_named") % tr(phase_title), true, true)


func _on_boss_defeated(
	_boss_id: StringName,
	_zone_id: StringName,
	_at_position: Vector2
) -> void:
	_emit_subtitle(tr("ui.audio.boss_defeated"), false, true)


# ------------------------------------------------------------------------------
# Программные заглушки (CC0: генерируются в рантайме, внешних файлов нет)
# ------------------------------------------------------------------------------

## Зацикленный эмбиент зоны: дрон из основного тона, квинты и октавы с медленным
## тремоло. Частоты квантованы по длительности петли, поэтому шва на стыке нет.
func _make_music_placeholder(track_id: StringName) -> AudioStreamWAV:
	var roots: Array[float] = [82.41, 87.31, 98.0, 110.0, 123.47]
	var seed_value: int = absi(String(track_id).hash())
	var root: float = roots[seed_value % roots.size()]
	var duration: float = MUSIC_LOOP_SECONDS
	var sample_count: int = int(duration * MUSIC_SAMPLE_RATE)

	var base: float = _loop_frequency(root, duration)
	var fifth: float = _loop_frequency(root * 1.5, duration)
	var octave: float = _loop_frequency(root * 2.0, duration)
	var tremolo: float = _loop_frequency(0.5, duration)

	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index: int in sample_count:
		var time: float = float(index) / float(MUSIC_SAMPLE_RATE)
		var envelope: float = 0.75 + 0.25 * sin(TAU * tremolo * time)
		var sample: float = (
			0.14 * sin(TAU * base * time)
			+ 0.07 * sin(TAU * fifth * time)
			+ 0.035 * sin(TAU * octave * time)
		) * envelope
		data.encode_s16(index * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MUSIC_SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	stream.data = data
	return stream


func _loop_frequency(frequency: float, loop_seconds: float) -> float:
	var cycles: int = maxi(1, int(round(frequency * loop_seconds)))
	return float(cycles) / loop_seconds


func _make_sfx_placeholder(sfx_id: StringName) -> AudioStreamWAV:
	match sfx_id:
		&"hit":
			return _build_sfx(0.12, 0.35, _sample_hit)
		&"parry":
			return _build_sfx(0.18, 0.3, _sample_parry)
		&"death":
			return _build_sfx(0.9, 0.32, _sample_death)
		&"phase":
			return _build_sfx(0.7, 0.34, _sample_phase)
		&"boss_near":
			return _build_sfx(0.8, 0.36, _sample_boss_near)
		_:
			return _build_sfx(0.08, 0.25, _sample_hit)
	return null


func _build_sfx(duration: float, amplitude: float, sampler: Callable) -> AudioStreamWAV:
	var sample_count: int = int(duration * SFX_SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var state: int = 0x13579BDF
	for index: int in sample_count:
		var time: float = float(index) / float(SFX_SAMPLE_RATE)
		var progress: float = clampf(time / duration, 0.0, 1.0)
		var attack: float = clampf(time / 0.004, 0.0, 1.0)
		var value: float = float(sampler.call(time, progress, state)) * attack * amplitude
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		data.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SFX_SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream


func _sample_hit(time: float, progress: float, state: int) -> float:
	var noise: float = float((state >> 8) & 0xFF) / 127.5 - 1.0
	var decay: float = exp(-progress * 9.0)
	var thump: float = sin(TAU * 150.0 * time) * exp(-progress * 6.0)
	return (noise * 0.7 + thump * 0.5) * decay


func _sample_parry(time: float, progress: float, state: int) -> float:
	var decay: float = exp(-progress * 7.0)
	var ping: float = sin(TAU * 1320.0 * time) + 0.6 * sin(TAU * 1980.0 * time)
	var spark: float = float((state >> 10) & 0xFF) / 127.5 - 1.0
	return (ping * 0.35 + spark * 0.15) * decay


func _sample_death(time: float, progress: float, _state: int) -> float:
	var frequency: float = lerpf(220.0, 55.0, progress)
	var tone: float = sin(TAU * frequency * time)
	var overtone: float = 0.4 * sin(TAU * frequency * 2.02 * time)
	return (tone + overtone) * exp(-progress * 2.4)


func _sample_phase(time: float, progress: float, _state: int) -> float:
	var frequency: float = lerpf(70.0, 210.0, progress)
	var rise: float = sin(TAU * frequency * time)
	var pulse: float = sin(TAU * 5.0 * time) * 0.15
	return (rise * 0.7 + pulse) * exp(-progress * 1.2)


func _sample_boss_near(time: float, progress: float, _state: int) -> float:
	var rumble: float = sin(TAU * 55.0 * time) + 0.5 * sin(TAU * 82.5 * time)
	var pulse: float = 0.6 + 0.4 * sin(TAU * 2.5 * time)
	return rumble * pulse * exp(-progress * 1.1)
