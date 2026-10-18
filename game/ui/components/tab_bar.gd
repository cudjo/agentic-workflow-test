class_name AshenTabBar
extends HBoxContainer
## AshenTabBar — строка вкладок (DESIGN §5/§6.1, a11y §9.2).
##
## Переключение без мыши: `Tab` / `Shift+Tab`, а также `LB`/`RB` геймпада
## (raw JoyButton 9/10 — в InputMap они заняты `block`/`dash`, поэтому экраны
## перехватывают их до игрового мира и помечают событие обработанным).
##
## Визуал вкладки даёт `AshenTab`: выбранная отличается фоном, рамкой и
## маркером у верхней кромки (состояние не только цветом).

signal tab_changed(index: int)

const JOYPAD_PREV_BUTTON: int = 9
const JOYPAD_NEXT_BUTTON: int = 10

## Минимальная ширина вкладки: короткие подписи не «схлопываются».
@export var min_tab_width: int = 88

var _tabs: Array[AshenTab] = []
var _titles: PackedStringArray = []
var _selected_index: int = -1


func _init() -> void:
	add_theme_constant_override("separation", UITokens.SP_1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, UITokens.TAB_HEIGHT)


func _ready() -> void:
	custom_minimum_size.y = UITokens.TAB_HEIGHT


# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

func set_tabs(titles: PackedStringArray) -> void:
	for tab: AshenTab in _tabs:
		if is_instance_valid(tab):
			tab.free()
	_tabs.clear()
	_titles = titles.duplicate()

	for index: int in _titles.size():
		var tab := AshenTab.new()
		tab.name = "Tab%d" % index
		tab.text = _titles[index]
		tab.font_size = UITokens.FONT_BODY
		tab.custom_minimum_size = Vector2(
			maxi(
				min_tab_width,
				int(UIStyle.text_width(_titles[index], UITokens.FONT_BODY))
				+ UITokens.SP_3 * 2
			),
			UITokens.TAB_HEIGHT
		)
		add_child(tab)
		tab.pressed.connect(_on_tab_pressed.bind(index))
		_tabs.append(tab)

	_selected_index = -1
	if not _tabs.is_empty():
		select(0, false)


func select(index: int, notify: bool = true) -> void:
	if _tabs.is_empty():
		return
	var clamped: int = clampi(index, 0, _tabs.size() - 1)
	var changed: bool = clamped != _selected_index
	_selected_index = clamped
	for tab_index: int in _tabs.size():
		_tabs[tab_index].selected = tab_index == clamped
	if changed and notify:
		tab_changed.emit(clamped)


func next() -> void:
	select(wrapi(_selected_index + 1, 0, _tabs.size()))


func prev() -> void:
	select(wrapi(_selected_index - 1, 0, _tabs.size()))


func get_selected_index() -> int:
	return _selected_index


func get_tab_count() -> int:
	return _tabs.size()


func get_tab_title(index: int) -> String:
	if index < 0 or index >= _titles.size():
		return ""
	return _titles[index]


func get_tabs() -> Array[AshenTab]:
	return _tabs.duplicate()


func focus_selected() -> void:
	if _selected_index >= 0 and _selected_index < _tabs.size():
		_tabs[_selected_index].grab_focus()


## LB/RB или Tab/Shift+Tab. Возвращает true, если событие было вкладкой
## (экран обязан пометить его обработанным, чтобы фокус не уехал в список).
func handle_tab_input(event: InputEvent) -> bool:
	if _tabs.size() < 2:
		return false

	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return false
		if button.button_index == JOYPAD_PREV_BUTTON:
			prev()
			return true
		if button.button_index == JOYPAD_NEXT_BUTTON:
			next()
			return true
		return false

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		if key.keycode == KEY_TAB or key.physical_keycode == KEY_TAB:
			if key.shift_pressed:
				prev()
			else:
				next()
			return true

	return false


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _on_tab_pressed(index: int) -> void:
	select(index)
