class_name UIScale
extends RefCounted
## UIScale — общий хелпер масштаба интерфейса (Config.ui_scale, DESIGN §9.6 п.6).
##
## Экраны инвентаря/журнала/фракций/карты/костра/ремапа/смерти пересчитывают
## шрифты и минимальные размеры по сигналу `Config.ui_scale_changed` так же,
## как HUD: 8 px → 12 px при 150 %, 8 px → 16 px при 200 %.
##
## Базовые (100 %) значения запоминаются в метаданных узла при первом вызове
## `apply()`. Повторные вызовы идемпотентны и возвращают экран к базовой
## геометрии при переключении обратно на 100 %, поэтому экран можно
## масштабировать многократно без накопления ошибки округления.

const META_FONT := &"ui_scale_base_font"
const META_RECT := &"ui_scale_base_rect"
const META_MIN := &"ui_scale_base_min"
const META_ROW := &"ui_scale_base_row"
const META_WRAP := &"ui_scale_base_wrap"


## Множитель текущего масштаба: 1.0 / 1.5 / 2.0.
static func factor() -> float:
	return float(Config.ui_scale) / 100.0


## Размер шрифта с учётом масштаба (8 → 12 при 150 %, 8 → 16 при 200 %).
static func font(base: int) -> int:
	return maxi(1, int(round(float(base) * factor())))


## Пиксельный размер с учётом масштаба (для отступов/высот строк).
static func px(value: float) -> float:
	return roundf(value * factor())


## Пересчитывает все текстовые узлы поддерева и запоминает базовые размеры.
## Вызывается экраном при старте, смене масштаба и после перестроения списков.
static func apply(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	_apply_node(root)
	for node: Node in root.find_children("*", "", true, false):
		_apply_node(node)


static func _apply_node(node: Node) -> void:
	if node is AshenMenuItem:
		_apply_menu_item(node as AshenMenuItem)
	elif node is AshenTab:
		_apply_tab(node as AshenTab)
	elif node is AshenTabBar:
		_apply_tab_bar(node as AshenTabBar)
	elif node is Label:
		_apply_label(node as Label)
	elif node is RichTextLabel:
		_apply_rich_text(node as RichTextLabel)


## Label: шрифт + размер под текст без обрезки. Позиция правого/центрального
# выравнивания сохраняется — растёт/сжимается только нужная сторона.
static func _apply_label(label: Label) -> void:
	var base: int = int(label.get_meta(META_FONT, label.get_theme_font_size(&"font_size")))
	if base <= 0:
		base = UITokens.FONT_BODY
	label.set_meta(META_FONT, base)
	var size: int = font(base)
	label.add_theme_font_size_override("font_size", size)

	var parent: Node = label.get_parent()
	var in_container: bool = parent is Container
	if in_container:
		if not label.has_meta(META_MIN):
			label.set_meta(META_MIN, label.custom_minimum_size)
		var base_min: Vector2 = label.get_meta(META_MIN)
		label.custom_minimum_size = Vector2(
			base_min.x,
			maxf(base_min.y, float(size) + 2.0)
		)
		return

	if not label.has_meta(META_RECT):
		label.set_meta(META_RECT, Rect2(label.position, label.size))
	var base_rect: Rect2 = label.get_meta(META_RECT)
	var needed_width: float = 0.0
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		needed_width = UIStyle.text_width(label.text, size) + 2.0
	var width: float = maxf(base_rect.size.x, needed_width)
	var height: float = maxf(base_rect.size.y, float(size) + 2.0)
	label.size = Vector2(width, height)

	var x: float = base_rect.position.x
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		match label.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_RIGHT:
				x = base_rect.position.x + base_rect.size.x - width
			HORIZONTAL_ALIGNMENT_CENTER:
				x = base_rect.position.x + (base_rect.size.x - width) * 0.5
			_:
				pass
	label.position = Vector2(x, base_rect.position.y)


## AshenMenuItem: шрифт/высота строки; ширина растёт только у кнопок HBox,
# чтобы список не выходил за панель.
static func _apply_menu_item(item: AshenMenuItem) -> void:
	var base: int = int(item.get_meta(META_FONT, item.font_size))
	if base <= 0:
		base = UITokens.FONT_BODY
	item.set_meta(META_FONT, base)
	if not item.has_meta(META_ROW):
		item.set_meta(META_ROW, item.custom_minimum_size.y)
	var base_row: float = item.get_meta(META_ROW)
	if not item.has_meta(META_MIN):
		item.set_meta(META_MIN, item.custom_minimum_size)
	var base_min: Vector2 = item.get_meta(META_MIN)
	var size: int = font(base)
	item.font_size = size
	var row: float = maxf(base_row, float(size) + 6.0)
	var width: float = base_min.x
	if item.get_parent() is HBoxContainer:
		width = maxf(base_min.x, UIStyle.text_width(item.text, size) + float(size) + 8.0)
	item.custom_minimum_size = Vector2(width, row)


## AshenTab: шрифт + минимальная ширина по тексту, высота не ломает полосу.
static func _apply_tab(tab: AshenTab) -> void:
	var base: int = int(tab.get_meta(META_FONT, tab.font_size))
	if base <= 0:
		base = UITokens.FONT_BODY
	tab.set_meta(META_FONT, base)
	if not tab.has_meta(META_MIN):
		tab.set_meta(META_MIN, tab.custom_minimum_size)
	var base_min: Vector2 = tab.get_meta(META_MIN)
	var size: int = font(base)
	tab.font_size = size
	tab.custom_minimum_size = Vector2(
		maxf(base_min.x, UIStyle.text_width(tab.text, size) + float(UITokens.SP_3 * 2)),
		maxf(base_min.y, float(size) + 6.0)
	)


static func _apply_tab_bar(bar: AshenTabBar) -> void:
	if not bar.has_meta(META_MIN):
		bar.set_meta(META_MIN, bar.custom_minimum_size)
	var base_min: Vector2 = bar.get_meta(META_MIN)
	var tabs: Array[AshenTab] = bar.get_tabs()
	var height: float = base_min.y
	for tab: AshenTab in tabs:
		height = maxf(height, tab.custom_minimum_size.y)
	bar.custom_minimum_size = Vector2(base_min.x, height)
	if not bar.has_meta(META_ROW):
		bar.set_meta(META_ROW, bar.min_tab_width)
	bar.min_tab_width = int(px(float(bar.get_meta(META_ROW))))


static func _apply_rich_text(label: RichTextLabel) -> void:
	var base: int = int(label.get_meta(META_FONT, label.get_theme_font_size(&"normal_font_size")))
	if base <= 0:
		base = UITokens.FONT_BODY
	label.set_meta(META_FONT, base)
	label.add_theme_font_size_override("normal_font_size", font(base))
	label.add_theme_font_size_override("bold_font_size", font(base))
	label.add_theme_font_size_override("italics_font_size", font(base))
	label.add_theme_font_size_override("mono_font_size", font(base))
