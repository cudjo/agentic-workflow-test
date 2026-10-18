class_name EndingText
extends Resource
## EndingText — один финальный текст (T-32).
##
## Экран концовки не хранит строки в коде сцены: каталог
## (`EndingCatalog`) собирает `EndingText` под выбранную фракцию.
## Нейтральная концовка используется, пока `FactionManager` — заглушка T-27.

@export var id: StringName = &""
@export var kicker: String = ""
@export var title: String = ""
## Основной текст; переносы строк — авторские (экран не «переливает» абзац).
@export var body: String = ""
## Строка статуса фракции: «Фракция: …» или «Фракция не выбрана».
@export var faction_line: String = ""
@export var accent: Color = Color("#e0b56a")


static func create(
	ending_id: StringName,
	ending_kicker: String,
	ending_title: String,
	ending_body: String,
	ending_faction_line: String,
	ending_accent: Color = Color("#e0b56a")
) -> EndingText:
	var text := EndingText.new()
	text.id = ending_id
	text.kicker = ending_kicker
	text.title = ending_title
	text.body = ending_body
	text.faction_line = ending_faction_line
	text.accent = ending_accent
	return text
