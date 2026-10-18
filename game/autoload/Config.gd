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

## Режим «Без мигания»: отключает вспышки/мерцание (a11y, DESIGN §9.3).
var no_flash: bool = false


## Переключатель режима «Без мигания» (T-20 вызывает из настроек).
func set_no_flash(enabled: bool) -> void:
	no_flash = enabled
