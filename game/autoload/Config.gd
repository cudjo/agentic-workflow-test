extends Node
## Config — настройки пользователя из user://settings.cfg (ConfigFile), PLAN §2.1/§7.
## Заглушка каркаса (T-01). Ключи и их потребители (Zero Dead Config):
##   language                 -> Locale (TranslationServer)
##   ui_scale                 -> Theme (font_size/контейнеры)
##   window_mode              -> DisplayServer.window_set_mode
##   silhouette_readability   -> silhouette_outline.gdshader + виньетка
##   no_flash                 -> мерцание HP/факелов, вспышки урона, тряска
##   sound_subtitles          -> AudioManager (тост-субтитры звуков)
##   master/music/sfx_volume  -> AudioServer шины Master/Music/SFX
## Реализация чтения/записи — задача T-20 (экран настроек).
##
## T-05: минимальный флаг «Без мигания» нужен визуалу игрока уже сейчас
## (вспышка урона, DESIGN §7/§9.3). Загрузка/сохранение значения из
## `user://settings.cfg` и UI-тумблер — T-20.
##
## T-34: громкости шин и «субтитры звуков». AudioManager читает значения при
## старте и переприменяет их по сигналу `audio_settings_changed`; сами
## значения 0…1 (0 — тишина), UI-слайдеры T-20 вызывают сеттеры.

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


## Переключатель режима «Без мигания» (T-20 вызывает из настроек).
func set_no_flash(enabled: bool) -> void:
	no_flash = enabled


## Переключатель режима «Читаемость силуэтов» (T-20 вызывает из настроек).
func set_silhouette_readability(enabled: bool) -> void:
	silhouette_readability = enabled


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


## «Субтитры звуков» (T-20).
func set_sound_subtitles(enabled: bool) -> void:
	if sound_subtitles == enabled:
		return
	sound_subtitles = enabled
	audio_settings_changed.emit()
