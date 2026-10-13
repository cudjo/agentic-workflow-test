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
## Реализация чтения/записи — задача T-20 (экран настроек); API не добавлять раньше времени.
