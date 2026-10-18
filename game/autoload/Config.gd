extends Node
## Config — пользовательские настройки из user://settings.cfg (ConfigFile), PLAN §2.1/§7.
##
## Ключи и их потребители (Zero Dead Config):
##   language                 -> Locale/TranslationServer (T-36), этот файл
##   ui_scale                 -> меню/настройки (font_size/контейнеры, шаг 8 px)
##   window_mode              -> DisplayServer.window_set_mode
##   silhouette_readability   -> silhouette_outline.gdshader + виньетка (T-35)
##   no_flash                 -> мерцание HP/факелов, вспышки урона, тряска (T-35)
##   sound_subtitles          -> AudioManager (тост-субтитры звуков, T-34)
##   master/music/sfx_volume  -> AudioServer шины Master/Music/SFX (T-34)
##
## T-20: значения читаются при старте (`_ready`) и пишутся из экрана настроек
## (`save_settings`). Секция `[settings]` не трогает `[input]` — ремап T-03
## живёт в том же файле и сохраняется при записи (файл перечитывается перед
## сохранением). В тестах путь переопределяется через `settings_path`, чтобы
## не засорять настоящий user://.
##
## Значения применяются сразу: язык — `TranslationServer.set_locale`, режим
## окна — `DisplayServer.window_set_mode`, a11y/аудио — сигналы для T-34/T-35.
## UI-масштаб читает UI (T-20: MainMenu/Settings/SaveSlots) и увеличивает
## шрифты/строки 8/12/16 px для 100/150/200%, а не масштабирует вьюпорт.

const DEFAULT_SETTINGS_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "settings"

const LANGUAGE_RU: String = "ru"
const LANGUAGE_EN: String = "en"
const LANGUAGES: Array[String] = [LANGUAGE_RU, LANGUAGE_EN]

const UI_SCALE_100: int = 100
const UI_SCALE_150: int = 150
const UI_SCALE_200: int = 200
const UI_SCALES: Array[int] = [UI_SCALE_100, UI_SCALE_150, UI_SCALE_200]

const WINDOW_WINDOWED: int = 0
const WINDOW_FULLSCREEN: int = 1
const WINDOW_BORDERLESS: int = 2

## Путь к файлу настроек; тесты подменяют его на временный.
var settings_path: String = DEFAULT_SETTINGS_PATH

## Язык интерфейса: `ru`/`en`. Неизвестное значение нормализуется в `ru`.
var language: String = LANGUAGE_RU:
	set(value):
		var normalized: String = normalize_language(value)
		var changed: bool = language != normalized
		language = normalized
		TranslationServer.set_locale(language)
		if changed:
			language_changed.emit(language)

## Масштаб интерфейса: 100/150/200 (DESIGN §9.1). Другие значения — ближайший шаг.
var ui_scale: int = UI_SCALE_100:
	set(value):
		var normalized: int = normalize_ui_scale(value)
		if ui_scale == normalized:
			return
		ui_scale = normalized
		ui_scale_changed.emit(ui_scale)

## Режим окна: 0 — окно, 1 — полный экран, 2 — без рамки.
var window_mode: int = WINDOW_WINDOWED:
	set(value):
		var normalized: int = clampi(value, WINDOW_WINDOWED, WINDOW_BORDERLESS)
		var changed: bool = window_mode != normalized
		window_mode = normalized
		apply_window_mode()
		if changed:
			window_mode_changed.emit(window_mode)

## Громкость Master-шины, 0…1.
var master_volume: float = 1.0
## Громкость Music-шины, 0…1.
var music_volume: float = 0.8
## Громкость SFX-шины, 0…1.
var sfx_volume: float = 0.8
## «Субтитры звуков» (DESIGN §9.4): тосты ключевых звуков (босс рядом, удар,
## смена фазы). Включены по умолчанию — ключевые события не должны зависеть
## только от слуха (a11y).
var sound_subtitles: bool = true

## Язык изменился (T-20/T-36). Новый код уже применён к TranslationServer.
signal language_changed(language_code: String)
## Масштаб UI изменился (T-20): UI перестраивает шрифты/строки.
signal ui_scale_changed(scale: int)
## Режим окна изменился (T-20); DisplayServer уже переключён.
signal window_mode_changed(mode: int)
## Значение любой из аудионастроек изменилось (T-34 → AudioManager).
signal audio_settings_changed
## Изменилась визуальная a11y-настройка (T-35): контур силуэтов/виньетка,
## режим «Без мигания». Потребители: LightingRig, PlayerAnimation.
signal visual_accessibility_changed

## Режим «Без мигания»: отключает вспышки/мерцание (a11y, DESIGN §9.3).
var no_flash: bool = false:
	set(value):
		if no_flash == value:
			return
		no_flash = value
		visual_accessibility_changed.emit()

## Режим «Читаемость силуэтов» (DESIGN §9.1): 1-px контур героя/врагов,
## усиленный rim-light и отключённая виньетка.
var silhouette_readability: bool = false:
	set(value):
		if silhouette_readability == value:
			return
		silhouette_readability = value
		visual_accessibility_changed.emit()


func _ready() -> void:
	load_settings()
	apply_settings()


# ------------------------------------------------------------------------------
# Загрузка / сохранение user://settings.cfg
# ------------------------------------------------------------------------------

## Читает `[settings]` и применяет значения. false — файла нет/он битый:
## остаются дефолты, игра стартует без ошибки (Zero Dead Config).
func load_settings(path_override: String = "") -> bool:
	var path: String = _resolved_path(path_override)
	if not FileAccess.file_exists(path):
		return false

	var config := ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK:
		push_warning("Config: не удалось прочитать %s (%s) — используются дефолты" % [path, error_string(error)])
		return false
	if not config.has_section(SETTINGS_SECTION):
		return false

	language = str(config.get_value(SETTINGS_SECTION, "language", language))
	ui_scale = int(config.get_value(SETTINGS_SECTION, "ui_scale", ui_scale))
	window_mode = int(config.get_value(SETTINGS_SECTION, "window_mode", window_mode))
	set_silhouette_readability(
		_as_bool(config.get_value(SETTINGS_SECTION, "silhouette_readability", silhouette_readability), silhouette_readability)
	)
	set_no_flash(_as_bool(config.get_value(SETTINGS_SECTION, "no_flash", no_flash), no_flash))
	set_sound_subtitles(
		_as_bool(config.get_value(SETTINGS_SECTION, "sound_subtitles", sound_subtitles), sound_subtitles)
	)
	set_master_volume(_as_float(config.get_value(SETTINGS_SECTION, "master_volume", master_volume), master_volume))
	set_music_volume(_as_float(config.get_value(SETTINGS_SECTION, "music_volume", music_volume), music_volume))
	set_sfx_volume(_as_float(config.get_value(SETTINGS_SECTION, "sfx_volume", sfx_volume), sfx_volume))
	return true


## Пишет текущие значения в `[settings]`. Существующий файл перечитывается,
## чтобы не потерять `[input]` (ремап T-03) и другие секции.
func save_settings(path_override: String = "") -> bool:
	var path: String = _resolved_path(path_override)
	var config := ConfigFile.new()
	if FileAccess.file_exists(path):
		# Битый файл не блокирует сохранение: нужную секцию перезапишем.
		config.load(path)

	config.set_value(SETTINGS_SECTION, "language", language)
	config.set_value(SETTINGS_SECTION, "ui_scale", ui_scale)
	config.set_value(SETTINGS_SECTION, "window_mode", window_mode)
	config.set_value(SETTINGS_SECTION, "silhouette_readability", silhouette_readability)
	config.set_value(SETTINGS_SECTION, "no_flash", no_flash)
	config.set_value(SETTINGS_SECTION, "sound_subtitles", sound_subtitles)
	config.set_value(SETTINGS_SECTION, "master_volume", master_volume)
	config.set_value(SETTINGS_SECTION, "music_volume", music_volume)
	config.set_value(SETTINGS_SECTION, "sfx_volume", sfx_volume)

	var error: Error = config.save(path)
	if error != OK:
		push_warning("Config: не удалось сохранить %s (%s)" % [path, error_string(error)])
		return false
	return true


## Применяет язык и режим окна (для старта и после загрузки файла). Остальные
## значения применяются сеттерами/потребителями по сигналам.
func apply_settings() -> void:
	TranslationServer.set_locale(language)
	apply_window_mode()


# ------------------------------------------------------------------------------
# Язык
# ------------------------------------------------------------------------------

## Переключатель языка (T-20): пишет Config.language и локаль TranslationServer.
func set_language(code: String) -> void:
	language = code


## true — язык интерфейса английский; UI-хелпер для T-20 до данных T-36.
func is_english() -> bool:
	return language == LANGUAGE_EN


static func normalize_language(value: Variant) -> String:
	var text: String = str(value).strip_edges().to_lower()
	if text.begins_with("en"):
		return LANGUAGE_EN
	return LANGUAGE_RU


static func normalize_ui_scale(value: Variant) -> int:
	var numeric: int = int(value)
	if numeric <= UI_SCALE_100:
		return UI_SCALE_100
	if numeric <= UI_SCALE_150:
		return UI_SCALE_150
	return UI_SCALE_200


## Следующий/предыдущий масштаб в списке 100 → 150 → 200 (циклически).
static func next_ui_scale(current: int, step: int) -> int:
	var index: int = UI_SCALES.find(normalize_ui_scale(current))
	if index < 0:
		index = 0
	return UI_SCALES[wrapi(index + step, 0, UI_SCALES.size())]


# ------------------------------------------------------------------------------
# Режим окна
# ------------------------------------------------------------------------------

## DisplayServer-режим для значения `window_mode`.
static func display_mode_for(mode: int) -> int:
	match mode:
		WINDOW_FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		WINDOW_BORDERLESS:
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		_:
			return DisplayServer.WINDOW_MODE_WINDOWED


## Применяет режим окна (no-op в headless — DisplayServer там dummy).
func apply_window_mode() -> void:
	DisplayServer.window_set_mode(display_mode_for(window_mode))


# ------------------------------------------------------------------------------
# Громкости / a11y
# ------------------------------------------------------------------------------

## Переключатель режима «Без мигания» (T-20 вызывает из настроек).
func set_no_flash(enabled: bool) -> void:
	no_flash = enabled


## Переключатель режима «Читаемость силуэтов» (T-20 вызывает из настроек).
func set_silhouette_readability(enabled: bool) -> void:
	silhouette_readability = enabled


## «Субтитры звуков» (T-20).
func set_sound_subtitles(enabled: bool) -> void:
	if sound_subtitles == enabled:
		return
	sound_subtitles = enabled
	audio_settings_changed.emit()


## Громкость Master (T-20). Значение вне 0…1 обрезается.
func set_master_volume(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(master_volume, clamped):
		return
	master_volume = clamped
	audio_settings_changed.emit()


## Громкость музыки (T-20).
func set_music_volume(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(music_volume, clamped):
		return
	music_volume = clamped
	audio_settings_changed.emit()


## Громкость SFX (T-20).
func set_sfx_volume(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(sfx_volume, clamped):
		return
	sfx_volume = clamped
	audio_settings_changed.emit()


# ------------------------------------------------------------------------------
# Хелперы
# ------------------------------------------------------------------------------

func _resolved_path(path_override: String) -> String:
	return settings_path if path_override.is_empty() else path_override


static func _as_bool(value: Variant, fallback: bool) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) != 0.0
	if value is String:
		var text: String = (value as String).strip_edges().to_lower()
		return text in ["true", "1", "yes", "on"]
	return fallback


static func _as_float(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return clampf(float(value), 0.0, 1.0)
	return clampf(fallback, 0.0, 1.0)
