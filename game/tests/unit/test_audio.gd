extends GutTest
## T-34 — AudioManager: шины, музыка зон с кроссфейдом, SFX и «субтитры звуков»
## (SPEC US-07/AC-07.2, PLAN §2.2/§3.5, DESIGN §9.4).
##
## Кроссфейд проверяется без ожидания реального времени: `AudioManager.advance`
## двигает тот же расчёт, что и `_process`. Субтитры — через сигнал
## `subtitle_requested` и настоящий ToastHost с AshenToast.

const ZONE_A: StringName = &"zone_01_village"
const ZONE_B: StringName = &"zone_02_swamp"

var _saved_master: float = 1.0
var _saved_music: float = 0.8
var _saved_sfx: float = 0.8
var _saved_subtitles: bool = true
var _saved_crossfade: float = AudioManager.CROSSFADE_TIME


func before_each() -> void:
	_saved_master = Config.master_volume
	_saved_music = Config.music_volume
	_saved_sfx = Config.sfx_volume
	_saved_subtitles = Config.sound_subtitles
	_saved_crossfade = AudioManager.crossfade_time

	AudioManager.reset()
	AudioManager.crossfade_time = AudioManager.CROSSFADE_TIME
	Config.set_sound_subtitles(true)
	AudioManager.apply_settings()


func after_each() -> void:
	AudioManager.reset()
	AudioManager.crossfade_time = _saved_crossfade
	Config.set_master_volume(_saved_master)
	Config.set_music_volume(_saved_music)
	Config.set_sfx_volume(_saved_sfx)
	Config.set_sound_subtitles(_saved_subtitles)
	AudioManager.apply_settings()


# ------------------------------------------------------------------------------
# Шины и громкости из Config
# ------------------------------------------------------------------------------

func test_buses_master_music_sfx_exist() -> void:
	assert_gte(AudioServer.get_bus_index(&"Master"), 0, "Master bus exists")
	assert_gte(AudioServer.get_bus_index(&"Music"), 0, "Music bus exists")
	assert_gte(AudioServer.get_bus_index(&"SFX"), 0, "SFX bus exists")
	assert_eq(
		AudioServer.get_bus_send(AudioServer.get_bus_index(&"Music")),
		&"Master",
		"Music is routed to Master"
	)
	assert_eq(
		AudioServer.get_bus_send(AudioServer.get_bus_index(&"SFX")),
		&"Master",
		"SFX is routed to Master"
	)


func test_config_volumes_are_applied_to_buses() -> void:
	Config.set_master_volume(1.0)
	Config.set_music_volume(0.5)
	Config.set_sfx_volume(0.25)
	AudioManager.apply_settings()

	assert_almost_eq(AudioManager.get_bus_linear_volume(&"Master"), 1.0, 0.01)
	assert_almost_eq(AudioManager.get_bus_linear_volume(&"Music"), 0.5, 0.01)
	assert_almost_eq(AudioManager.get_bus_linear_volume(&"SFX"), 0.25, 0.01)


func test_zero_volume_mutes_bus_without_minus_infinity() -> void:
	Config.set_music_volume(0.0)
	AudioManager.apply_settings()

	var index: int = AudioServer.get_bus_index(&"Music")
	assert_almost_eq(AudioServer.get_bus_volume_db(index), AudioManager.SILENCE_DB, 0.01)
	assert_almost_eq(AudioManager.get_bus_linear_volume(&"Music"), 0.0, 0.001)


# ------------------------------------------------------------------------------
# AC-07.2: смена трека зоны ≤ 2 с, кроссфейд ≤ 1 с, без обрыва
# ------------------------------------------------------------------------------

func test_zone_music_crossfade_is_at_most_one_second() -> void:
	var started: bool = AudioManager.request_music(ZONE_A)
	assert_true(started, "first zone track starts")
	assert_true(AudioManager.is_crossfading(), "first track fades in")

	AudioManager.advance(AudioManager.crossfade_time + 0.01)
	assert_false(AudioManager.is_crossfading(), "fade-in completed")
	assert_eq(AudioManager.get_current_track_id(), ZONE_A)
	assert_true(AudioManager.is_music_playing())

	assert_lte(AudioManager.crossfade_time, 1.0, "crossfade fits AC-07.2 (≤ 1 s)")


func test_zone_change_crossfades_without_silence_and_within_two_seconds() -> void:
	AudioManager.request_music(ZONE_A)
	AudioManager.advance(AudioManager.crossfade_time + 0.01)
	assert_eq(AudioManager.get_current_track_id(), ZONE_A)

	var changed: bool = AudioManager.request_music(ZONE_B)
	assert_true(changed, "new zone requests another track")
	assert_true(AudioManager.is_crossfading())
	assert_eq(AudioManager.get_current_track_id(), ZONE_B, "incoming track is current")

	var steps: int = 20
	var step: float = AudioManager.crossfade_time / float(steps)
	var simulated: float = 0.0
	var minimum_sum: float = 999.0
	var both_audible_midway: bool = false

	for index: int in steps:
		AudioManager.advance(step)
		simulated += step
		var levels: Array[float] = AudioManager.get_music_levels()
		minimum_sum = minf(minimum_sum, levels[0] + levels[1])
		if index == steps / 2:
			both_audible_midway = levels[0] > 0.0 and levels[1] > 0.0

	assert_true(both_audible_midway, "both tracks audible in the middle — no hard cut")
	assert_gt(minimum_sum, 0.5, "combined gain never drops to silence")
	assert_lt(simulated, 2.0, "track change fits AC-07.2 (≤ 2 s)")
	assert_false(AudioManager.is_crossfading(), "crossfade finished")
	assert_eq(AudioManager.get_current_track_id(), ZONE_B)
	assert_almost_eq(AudioManager.get_music_levels()[0] + AudioManager.get_music_levels()[1], 1.0, 0.01)


func test_zone_loaded_event_starts_crossfade() -> void:
	EventBus.zone_loaded.emit(ZONE_A, "Деревня-бастион")

	assert_true(AudioManager.is_crossfading(), "zone_loaded triggers music change")
	assert_eq(AudioManager.get_current_track_id(), ZONE_A)


func test_main_scene_mounts_toast_host_on_toasts_layer() -> void:
	var packed: PackedScene = load("res://Main.tscn") as PackedScene
	assert_not_null(packed, "Main.tscn loads")

	var main: Node = packed.instantiate()
	var host: Node = main.get_node_or_null("Toasts/ToastHost")
	assert_not_null(host, "Toasts layer has a ToastHost")
	assert_true(host is ToastHost, "ToastHost script is attached")
	main.free()


func test_repeated_same_track_does_not_restart() -> void:
	AudioManager.request_music(ZONE_A)
	AudioManager.advance(AudioManager.crossfade_time + 0.01)

	assert_false(AudioManager.request_music(ZONE_A), "same track is not restarted")
	assert_false(AudioManager.is_crossfading())


# ------------------------------------------------------------------------------
# SFX удара/парирования/смерти/фазы
# ------------------------------------------------------------------------------

func test_all_key_sfx_are_available_and_play() -> void:
	for sfx_id: StringName in [&"hit", &"parry", &"death", &"phase"]:
		assert_true(AudioManager.has_sfx(sfx_id), "%s is a known SFX" % sfx_id)
		assert_true(AudioManager.play_sfx(sfx_id), "%s plays" % sfx_id)
		assert_eq(AudioManager.last_sfx_id, sfx_id)
		assert_false(AudioManager.last_subtitle.is_empty(), "%s has a subtitle" % sfx_id)

	assert_eq(AudioManager.sfx_count, 4)


func test_hit_sfx_shows_subtitle_when_enabled() -> void:
	Config.set_sound_subtitles(true)
	AudioManager.play_sfx(&"hit")

	assert_eq(AudioManager.last_sfx_id, &"hit")
	assert_eq(AudioManager.last_subtitle, "УДАР")
	assert_eq(AudioManager.subtitle_count, 1)


func test_subtitles_toggle_hides_sound_captions() -> void:
	Config.set_sound_subtitles(false)
	AudioManager.play_sfx(&"hit")

	assert_eq(AudioManager.last_sfx_id, &"hit", "SFX still plays without subtitles")
	assert_eq(AudioManager.subtitle_count, 0)
	assert_eq(AudioManager.last_subtitle, "")

	Config.set_sound_subtitles(true)
	AudioManager.play_sfx(&"parry")
	assert_eq(AudioManager.last_subtitle, "ПАРИРОВАНИЕ")
	assert_eq(AudioManager.subtitle_count, 1)


# ------------------------------------------------------------------------------
# События EventBus: смерть, босс рядом, смена фазы
# ------------------------------------------------------------------------------

func test_player_died_plays_death_and_shows_caption() -> void:
	EventBus.player_died.emit()

	assert_eq(AudioManager.last_sfx_id, &"death")
	assert_eq(AudioManager.last_subtitle, "СМЕРТЬ")


func test_boss_fight_started_shows_boss_near_caption() -> void:
	EventBus.boss_fight_started.emit(&"boss_01", "Пепельный Страж", 120.0, PackedFloat32Array())

	assert_eq(AudioManager.last_sfx_id, &"boss_near")
	assert_string_contains(AudioManager.last_subtitle, "БОСС РЯДОМ")
	assert_string_contains(AudioManager.last_subtitle, "Пепельный Страж")


func test_boss_phase_changed_plays_phase_and_shows_caption() -> void:
	EventBus.boss_phase_changed.emit(&"boss_01", 1, "ФАЗА II")

	assert_eq(AudioManager.last_sfx_id, &"phase")
	assert_string_contains(AudioManager.last_subtitle, "СМЕНА ФАЗЫ")
	assert_string_contains(AudioManager.last_subtitle, "ФАЗА II")


# ------------------------------------------------------------------------------
# Субтитры через настоящий AshenToast (DESIGN §9.4)
# ------------------------------------------------------------------------------

func test_toast_host_renders_subtitle_with_ashen_toast() -> void:
	var host := ToastHost.new()
	add_child_autofree(host)
	await wait_process_frames(1)

	AudioManager.play_sfx(&"hit")
	await wait_process_frames(1)

	assert_not_null(host.get_toast(), "ToastHost builds an AshenToast")
	assert_true(host.is_showing(), "toast is visible")
	assert_eq(host.get_last_message(), "УДАР")
	assert_eq(host.get_toast().get_kind(), AshenToast.Kind.INFO)


func test_toast_host_uses_danger_variant_for_death() -> void:
	var host := ToastHost.new()
	add_child_autofree(host)
	await wait_process_frames(1)

	AudioManager.play_sfx(&"death")
	await wait_process_frames(1)

	assert_eq(host.get_last_message(), "СМЕРТЬ")
	assert_eq(host.get_toast().get_kind(), AshenToast.Kind.DANGER)
