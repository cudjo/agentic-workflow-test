class_name DialogueText
extends RefCounted
## DialogueText — перенос и постраничная разбивка реплик (T-28).
##
## Диалоговый бокс `AshenDialog` фиксирован (464×96, текст 380 px), поэтому
## длинная RU/EN-реплика не должна вылезать за рамку: текст переносится по
## словам и режется на страницы, каждая из которых гарантированно помещается
## в бокс. Ширина символа Press Start 2P при 8 px — 8 px, значит 380/8 = 47
## символов в строке; высота текстовой области — 3 строки по 12 px.
##
## Логика не зависит от UI-нод: тесты проверяют инварианты (длина строки,
## число строк на страницу) без рендера.

## 380 px / 8 px на символ (Press Start 2P, FONT_BODY = 8).
const MAX_LINE_CHARS: int = 47
## Три строки по 12 px помещаются в тело 464×96 при 2×2 ответах.
const MAX_LINES: int = 3
## С отключённым ответом появляется строка причины (+12 px): 2 строки текста.
const COMPACT_MAX_LINES: int = 2


## Нормализованный код языка данных: "en" или "ru".
static func normalize_language(language: String) -> String:
	var value: String = language.strip_edges().to_lower()
	if value.begins_with("en"):
		return "en"
	return "ru"


static func is_english(language: String) -> bool:
	return normalize_language(language) == "en"


## Выбор RU/EN-варианта с откатом на русский, если перевод пуст.
static func pick(ru_text: String, en_text: String, language: String) -> String:
	if is_english(language) and not en_text.strip_edges().is_empty():
		return en_text
	return ru_text


## Перенос по словам. Явные `\n` сохраняются как границы абзацев, слишком
## длинное слово режется по символам (иначе оно вылезло бы за бокс).
static func wrap_text(text: String, max_chars: int = MAX_LINE_CHARS) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var limit: int = maxi(max_chars, 1)
	var paragraphs: PackedStringArray = text.replace("\r\n", "\n").split("\n", true)
	for paragraph: String in paragraphs:
		var words: PackedStringArray = paragraph.split(" ", false)
		var current: String = ""
		for word: String in words:
			var remaining: String = word
			while remaining.length() > limit:
				if not current.is_empty():
					lines.append(current)
					current = ""
				lines.append(remaining.substr(0, limit))
				remaining = remaining.substr(limit)
			if remaining.is_empty():
				continue
			if current.is_empty():
				current = remaining
			elif current.length() + 1 + remaining.length() <= limit:
				current += " " + remaining
			else:
				lines.append(current)
				current = remaining
		lines.append(current)
	if lines.is_empty():
		lines.append("")
	return lines


## Режет текст на страницы по `max_lines` строк. Каждая страница — готовая
## строка с `\n`; пустая реплика даёт одну пустую страницу.
static func paginate(
	text: String,
	max_chars: int = MAX_LINE_CHARS,
	max_lines: int = MAX_LINES
) -> PackedStringArray:
	var lines: PackedStringArray = wrap_text(text, max_chars)
	var lines_per_page: int = maxi(max_lines, 1)
	var pages: PackedStringArray = PackedStringArray()
	var index: int = 0
	while index < lines.size():
		var page_lines: PackedStringArray = PackedStringArray()
		var stop: int = mini(index + lines_per_page, lines.size())
		for line_index: int in range(index, stop):
			page_lines.append(lines[line_index])
		pages.append("\n".join(page_lines))
		index = stop
	if pages.is_empty():
		pages.append("")
	return pages


## true, если страница гарантированно помещается в бокс: строк ≤ max_lines,
## каждая строка ≤ max_chars. Используется тестами RU/EN на переполнение.
static func fits(
	page: String,
	max_chars: int = MAX_LINE_CHARS,
	max_lines: int = MAX_LINES
) -> bool:
	var lines: PackedStringArray = page.split("\n", true)
	if lines.size() > max_lines:
		return false
	for line: String in lines:
		if line.length() > max_chars:
			return false
	return true
