class_name RemapScreen
extends CanvasLayer
## RemapScreen — экран ремапа управления (T-24, PLAN §5; AC-01.3, данные T-03).
##
## Список действий берётся из `InputMap` (игровые действия, без `ui_*`).
## `Enter`/`A` на строке запускает захват: следующее нажатие клавиши или кнопки
## геймпада заменяет привязки того же типа (клавиатура / геймпад), другая
## половина пары сохраняется. Сохранение — `InputManager.remap_action()`
## (`user://settings.cfg`), сброс — `InputManager.reset_to_defaults()`.
##
## Дубли подсвечиваются явно: знак «!», слово «ДУБЛЬ», имя конфликтующего
## действия в tooltip и цвет — состояние понятно без цвета (a11y §9.1).
##
## Навигация без мыши: `↑`/`↓` — действия, `Enter`/`A` — назначить,
## `Esc`/`B` — отменить захват/закрыть.

signal opened
signal closed

const LAYER: int = 20
const TITLE_TEXT: String = "УПРАВЛЕНИЕ"
const HINT_TEXT: String = "ENTER/A — НАЗНАЧИТЬ · ↑↓ — ВЫБОР"
const CAPTURE_HINT: String = "НАЖМИТЕ КЛАВИШУ ИЛИ КНОПКУ · ESC — ОТМЕНА"
const RESET_TEXT: String = "СБРОС"
const BACK_TEXT: String = "НАЗАД"
const RESET_DONE: String = "СБРОШЕНО К ПОУМОЛЧАНИЮ"
const EMPTY_BINDING: String = "— НЕ НАЗНАЧЕНО —"
const WAITING_TEXT: String = "ЖДЁМ ВВОД…"
const CONFLICT_PREFIX: String = "! ДУБЛЬ: "
const TAB_RESERVED: String = "TAB ЗАРЕЗЕРВИРОВАН ДЛЯ ВКЛАДОК"

## Стабильный порядок игровых действий в списке.
const ACTION_ORDER: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
	&"jump",
	&"attack",
	&"block",
	&"roll",
	&"dash",
	&"interact",
	&"map",
]

const ACTION_LABELS: Dictionary = {
	&"move_left": "ВЛЕВО",
	&"move_right": "ВПРАВО",
	&"move_up": "ВВЕРХ",
	&"move_down": "ВНИЗ",
	&"jump": "ПРЫЖОК",
	&"attack": "АТАКА",
	&"block": "БЛОК",
	&"roll": "ПЕРЕКАТ",
	&"dash": "РЫВОК",
	&"interact": "ДЕЙСТВИЕ",
	&"map": "КАРТА",
}

## Клавиши-модификаторы сами по себе не назначаются.
const MODIFIER_KEYS: Array[int] = [
	KEY_SHIFT,
	KEY_CTRL,
	KEY_ALT,
	KEY_META,
	KEY_CAPSLOCK,
	KEY_NUMLOCK,
	KEY_SCROLLLOCK,
]

const PANEL_RECT := Rect2(8, 8, 464, 254)
const LIST_RECT := Rect2(14, 32, 452, 188)
const STATUS_POSITION := Vector2(14, 224)
const ACTIONS_POSITION := Vector2(14, 240)
const ACTION_HEIGHT: int = 22
const ROW_HEIGHT: int = 16
const FOOTER_HINT: String = "↑↓ — ВЫБОР · ESC — НАЗАД"

## Пауза при открытии. QA/тесты выключают, чтобы не останавливать GUT.
var pause_on_open: bool = true

var _root: Control
var _panel: AshenPanel
var _title: Label
var _hint: Label
var _list_panel: AshenPanel
var _scroll: ScrollContainer
var _list_box: GridContainer
var _status: Label
var _footer_hint: Label
var _reset_button: AshenMenuItem
var _back_button: AshenMenuItem

var _rows: Array[_RemapRow] = []
var _row_by_action: Dictionary = {}
var _selected_action: StringName = &""
var _capturing_action: StringName = &""
var _built: bool = false

var _pause_previous: bool = false
var _pause_owned: bool = false


func _init() -> void:
	name = "Remap"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_ensure_built()
	_refresh_rows()


func _exit_tree() -> void:
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false


# ------------------------------------------------------------------------------
# Открытие/закрытие
# ------------------------------------------------------------------------------

func open() -> void:
	_ensure_built()
	if visible:
		return
	visible = true
	_pause_previous = get_tree().paused
	_pause_owned = pause_on_open and not _pause_previous
	if pause_on_open:
		get_tree().paused = true
	_capturing_action = &""
	_set_status("ВЫБЕРИТЕ ДЕЙСТВИЕ", UITokens.STONE_5)
	_refresh_rows()
	opened.emit()


func close() -> void:
	if not visible:
		return
	_capturing_action = &""
	visible = false
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false
	_release_focus()
	closed.emit()


func is_open() -> bool:
	return visible


func is_capturing() -> bool:
	return _capturing_action != &""


func get_capture_action() -> StringName:
	return _capturing_action


# ------------------------------------------------------------------------------
# Ввод
# ------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if _capturing_action != &"":
		if event.is_action_pressed(&"ui_cancel"):
			cancel_capture()
			_consume()
			return
		if event is InputEventKey:
			var key := event as InputEventKey
			if not key.pressed or key.echo:
				_consume()
				return
			if _is_modifier_only(key):
				_consume()
				return
			if _assign_from_key(_capturing_action, key):
				_consume()
				return
			_consume()
			return
		if event is InputEventJoypadButton:
			var button := event as InputEventJoypadButton
			if button.pressed:
				assign_event(_capturing_action, button)
			_consume()
			return
		return

	if event.is_action_pressed(&"ui_cancel"):
		close()
		_consume()


func _consume() -> void:
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


func _assign_from_key(action: StringName, key: InputEventKey) -> bool:
	var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code == KEY_TAB:
		_set_status(TAB_RESERVED, UITokens.BLOOD_5)
		_capturing_action = &""
		_refresh_rows()
		return false
	return assign_event(action, key)


# ------------------------------------------------------------------------------
# Публичный API ремапа
# ------------------------------------------------------------------------------

## Игровые действия из InputMap в стабильном порядке (без `ui_*`).
func get_actions() -> Array[StringName]:
	var available: Array[StringName] = InputMap.get_actions()
	var result: Array[StringName] = []
	for action: StringName in ACTION_ORDER:
		if available.has(action):
			result.append(action)

	var rest: Array[String] = []
	for action: StringName in available:
		if String(action).begins_with("ui_"):
			continue
		if result.has(action):
			continue
		rest.append(String(action))
	rest.sort()
	for raw_action: String in rest:
		result.append(StringName(raw_action))
	return result


func get_action_label(action: StringName) -> String:
	if ACTION_LABELS.has(action):
		return str(ACTION_LABELS[action])
	return String(action).to_upper()


## Стартует захват события для действия.
func start_capture(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	_capturing_action = action
	_selected_action = action
	_set_status(CAPTURE_HINT, UITokens.GOLD_3)
	_refresh_rows()


func cancel_capture() -> void:
	_capturing_action = &""
	_set_status(HINT_TEXT, UITokens.STONE_5)
	_refresh_rows()


## Заменяет привязки того же типа и сохраняет через InputManager (AC-01.3).
func assign_event(action: StringName, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		return false
	var normalized: InputEvent = _normalize_event(event)
	if normalized == null:
		return false

	var kind: String = _event_kind(normalized)
	var events: Array[InputEvent] = []
	for existing: InputEvent in InputMap.action_get_events(action):
		if _event_kind(existing) != kind:
			events.append(existing)
	events.append(normalized)

	InputManager.remap_action(action, events)
	_capturing_action = &""
	_refresh_rows()

	var conflicts: Dictionary = get_conflicts()
	var has_conflict: bool = false
	for key: Variant in conflicts.keys():
		if (conflicts[key] as Array).has(action):
			has_conflict = true
			break
	var message: String = "СОХРАНЕНО: %s — %s" % [
		get_action_label(action),
		_format_event(normalized),
	]
	if has_conflict:
		message += " · " + CONFLICT_PREFIX.strip_edges().trim_suffix(":")
		_set_status(message, UITokens.BLOOD_5)
	else:
		_set_status(message, UITokens.GOLD_3)
	return true


## Сброс всех действий к дефолтам project.godot.
func reset_bindings() -> void:
	InputManager.reset_to_defaults()
	_capturing_action = &""
	_refresh_rows()
	_set_status(RESET_DONE, UITokens.GOLD_3)


## Дубли: ключ события -> список действий, где он встречается (>1).
func get_conflicts() -> Dictionary:
	var owners: Dictionary = {}
	for action: StringName in get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			var key: String = conflict_key(event)
			if key.is_empty():
				continue
			if not owners.has(key):
				owners[key] = []
			var actions: Array = owners[key]
			if not actions.has(action):
				actions.append(action)

	var conflicts: Dictionary = {}
	for key: Variant in owners.keys():
		var actions: Array = owners[key]
		if actions.size() > 1:
			conflicts[key] = actions
	return conflicts


## Снимок строк для тестов/QA.
func get_action_rows() -> Array[Dictionary]:
	var conflicts: Dictionary = get_conflicts()
	var result: Array[Dictionary] = []
	for action: StringName in get_actions():
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var names: Array[String] = []
		for event: InputEvent in events:
			var key: String = conflict_key(event)
			if key.is_empty() or not conflicts.has(key):
				continue
			for other: Variant in conflicts[key]:
				var other_action: StringName = StringName(str(other))
				if other_action == action:
					continue
				var other_label: String = get_action_label(other_action)
				if not names.has(other_label):
					names.append(other_label)
		result.append({
			"action": action,
			"label": get_action_label(action),
			"bindings": _format_events(events),
			"conflict": not names.is_empty(),
			"conflict_actions": names,
			"capturing": action == _capturing_action,
		})
	return result


func get_status_text() -> String:
	_ensure_built()
	return _status.text


func get_row(action: StringName) -> AshenMenuItem:
	_ensure_built()
	return _row_by_action.get(action, null) as AshenMenuItem


func get_reset_button() -> AshenMenuItem:
	_ensure_built()
	return _reset_button


func get_back_button() -> AshenMenuItem:
	_ensure_built()
	return _back_button


# ------------------------------------------------------------------------------
# Построение UI
# ------------------------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(UITokens.VOID, 0.94)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = AshenPanel.new()
	_panel.name = "Panel"
	_panel.variant = UIStyle.PanelVariant.GLASS
	_panel.padding = 0
	_root.add_child(_panel)
	_panel.position = PANEL_RECT.position
	_panel.size = PANEL_RECT.size

	_title = _make_label(TITLE_TEXT, UITokens.GOLD_3, UITokens.FONT_H2)
	_title.name = "Title"
	_title.position = Vector2(16, 10)
	_title.size = Vector2(200, UITokens.LINE_H2)
	_root.add_child(_title)

	_hint = _make_label("ENTER/A — НАЗНАЧИТЬ", UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_RIGHT)
	_hint.name = "Hint"
	_hint.position = Vector2(290, 14)
	_hint.size = Vector2(176, UITokens.LINE_BODY)
	_root.add_child(_hint)

	_list_panel = AshenPanel.new()
	_list_panel.name = "ListPanel"
	_list_panel.variant = UIStyle.PanelVariant.INSET
	_list_panel.padding = 0
	_root.add_child(_list_panel)
	_list_panel.position = LIST_RECT.position
	_list_panel.size = LIST_RECT.size

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_list_panel.add_child(_scroll)

	_list_box = GridContainer.new()
	_list_box.name = "Rows"
	_list_box.columns = 2
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("h_separation", UITokens.SP_1)
	_list_box.add_theme_constant_override("v_separation", 0)
	_scroll.add_child(_list_box)

	_status = _make_label(HINT_TEXT, UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, true)
	_status.name = "Status"
	_status.position = STATUS_POSITION
	_status.size = Vector2(452, 14)
	_root.add_child(_status)

	_footer_hint = _make_label(FOOTER_HINT, UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_RIGHT)
	_footer_hint.name = "FooterHint"
	_footer_hint.position = Vector2(210, 244)
	_footer_hint.size = Vector2(256, UITokens.LINE_BODY)
	_root.add_child(_footer_hint)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", UITokens.SP_3)
	_root.add_child(actions)
	actions.position = ACTIONS_POSITION

	_reset_button = AshenMenuItem.new()
	_reset_button.name = "Reset"
	_reset_button.text = RESET_TEXT
	_reset_button.font_size = UITokens.FONT_BODY
	_reset_button.custom_minimum_size = Vector2(96, ACTION_HEIGHT)
	_reset_button.pressed.connect(reset_bindings)
	actions.add_child(_reset_button)

	_back_button = AshenMenuItem.new()
	_back_button.name = "Back"
	_back_button.text = BACK_TEXT
	_back_button.font_size = UITokens.FONT_BODY
	_back_button.custom_minimum_size = Vector2(88, ACTION_HEIGHT)
	_back_button.pressed.connect(close)
	actions.add_child(_back_button)


func _make_label(
	text: String,
	color: Color,
	size: int = UITokens.FONT_BODY,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	wrap: bool = false
) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIStyle.font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	)
	return label


# ------------------------------------------------------------------------------
# Перестроение строк
# ------------------------------------------------------------------------------

func _refresh_rows() -> void:
	for child: Node in _list_box.get_children():
		child.free()
	_rows.clear()
	_row_by_action.clear()

	var data_list: Array[Dictionary] = get_action_rows()
	for data: Dictionary in data_list:
		var action: StringName = StringName(str(data.get("action", "")))
		var row := _RemapRow.new()
		row.name = "Action_%s" % String(action)
		row.text = str(data.get("label", ""))
		row.font_size = UITokens.FONT_BODY
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.bindings = str(data.get("bindings", ""))
		row.capturing = bool(data.get("capturing", false))
		var conflict_actions: Array = data.get("conflict_actions", [])
		row.conflict = not conflict_actions.is_empty()
		row.conflict_text = ""
		var tooltip: String = "Enter/A — назначить"
		if row.conflict:
			var names: Array[String] = []
			for name: Variant in conflict_actions:
				names.append(str(name))
			# В строке — короткий маркер, полный список — в tooltip: колонка
			# 210 px, длинные имена не должны перекрывать действие.
			row.conflict_text = "! ДУБЛЬ"
			tooltip = "Конфликт: %s" % ", ".join(names)
		row.set_meta("action", action)
		row.pressed.connect(_on_row_pressed.bind(action))
		row.focus_entered.connect(_on_row_focused.bind(action))
		_list_box.add_child(row)
		# `_ready()` компонента сбрасывает tooltip — ставим после добавления.
		row.tooltip_text = tooltip
		row.custom_minimum_size = Vector2(210, ROW_HEIGHT)
		_rows.append(row)
		_row_by_action[action] = row

	_link_focus_neighbors()

	if visible and not _rows.is_empty():
		var target: _RemapRow = _row_by_action.get(_selected_action, null) as _RemapRow
		if target == null:
			target = _rows[0]
			_selected_action = StringName(target.get_meta("action", &""))
		target.grab_focus()


## Две колонки: ↑/↓ идут по столбцу, ←/→ — в соседний столбец строки.
func _link_focus_neighbors() -> void:
	if _rows.is_empty():
		return
	var count: int = _rows.size()
	for index: int in count:
		var row: _RemapRow = _rows[index]
		var column: int = index % 2
		var top_index: int = index - 2 if index >= 2 else index
		var bottom_index: int = index + 2 if index + 2 < count else index
		var left_index: int = index if column == 0 else index - 1
		var right_index: int = index if column == 1 else mini(index + 1, count - 1)
		row.focus_neighbor_top = _rows[top_index].get_path()
		row.focus_neighbor_bottom = _rows[bottom_index].get_path()
		row.focus_neighbor_left = _rows[left_index].get_path()
		row.focus_neighbor_right = _rows[right_index].get_path()


func _on_row_focused(action: StringName) -> void:
	_selected_action = action


func _on_row_pressed(action: StringName) -> void:
	start_capture(action)


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _release_focus() -> void:
	if get_viewport() == null:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and is_instance_valid(focus) and _root != null and _root.is_ancestor_of(focus):
		focus.release_focus()


# ------------------------------------------------------------------------------
# Форматирование событий
# ------------------------------------------------------------------------------

func _format_events(events: Array[InputEvent]) -> String:
	var parts: Array[String] = []
	for event: InputEvent in events:
		var label: String = _format_event(event)
		if not label.is_empty():
			parts.append(label)
	return " / ".join(parts)


func _format_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return _key_label(event as InputEventKey)
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		match button.button_index:
			JOY_BUTTON_DPAD_UP:
				return "D↑"
			JOY_BUTTON_DPAD_DOWN:
				return "D↓"
			JOY_BUTTON_DPAD_LEFT:
				return "D←"
			JOY_BUTTON_DPAD_RIGHT:
				return "D→"
		return str(AshenKbd.GENERIC_BUTTONS.get(button.button_index, "J%d" % button.button_index))
	if event is InputEventJoypadMotion:
		return _motion_label(event as InputEventJoypadMotion)
	if event is InputEventMouseButton:
		return "МЫШЬ%d" % (event as InputEventMouseButton).button_index
	return ""


func _key_label(event: InputEventKey) -> String:
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code == 0:
		return ""
	if code == KEY_SPACE:
		return "ПРОБЕЛ"
	if AshenKbd.KEY_LABELS.has(code):
		return str(AshenKbd.KEY_LABELS[code])
	var text: String = OS.get_keycode_string(code)
	if text.is_empty():
		return "?"
	text = text.to_upper()
	if text.length() > 4:
		text = text.substr(0, 4)
	return text


func _motion_label(event: InputEventJoypadMotion) -> String:
	if event.axis == JOY_AXIS_LEFT_X:
		return "ST←" if event.axis_value < 0.0 else "ST→"
	if event.axis == JOY_AXIS_LEFT_Y:
		return "ST↑" if event.axis_value < 0.0 else "ST↓"
	return "ОСЬ%d" % event.axis


## Ключ события для поиска дублей («key:<code>» / «joy:<button>»).
static func conflict_key(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			return ""
		return "key:%d" % code
	if event is InputEventJoypadButton:
		return "joy:%d" % (event as InputEventJoypadButton).button_index
	return ""


static func _event_kind(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key"
	if event is InputEventJoypadButton:
		return "joy_button"
	if event is InputEventJoypadMotion:
		return "joy_motion"
	if event is InputEventMouseButton:
		return "mouse_button"
	return "other"


static func _normalize_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key := event as InputEventKey
		var source := key.duplicate() as InputEventKey
		var code: int = source.physical_keycode if source.physical_keycode != 0 else source.keycode
		if code == 0 or MODIFIER_KEYS.has(code):
			return null
		source.pressed = false
		source.echo = false
		return source
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		var source := button.duplicate() as InputEventJoypadButton
		source.pressed = false
		return source
	return null


static func _is_modifier_only(event: InputEventKey) -> bool:
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	return code == 0 or MODIFIER_KEYS.has(code)


# ------------------------------------------------------------------------------
# Строка списка: действие слева, привязки/конфликт справа
# ------------------------------------------------------------------------------

class _RemapRow extends AshenMenuItem:

	var bindings: String = ""
	var conflict: bool = false
	var conflict_text: String = ""
	var capturing: bool = false

	func _draw() -> void:
		super._draw()
		if size.x <= 0.0 or size.y <= 0.0:
			return

		var padding: int = UITokens.PANEL_PADDING
		var right: float = size.x - float(padding)
		var baseline: float = (
			(size.y - UIStyle.text_height(UITokens.FONT_BODY)) * 0.5
			+ UIStyle.baseline_y(UITokens.FONT_BODY)
		)

		var text: String = bindings
		var color: Color = UITokens.BONE
		if capturing:
			text = "ЖДЁМ ВВОД…"
			color = UITokens.GOLD_3
		elif conflict and not conflict_text.is_empty():
			text = conflict_text
			color = UITokens.BLOOD_5
		elif text.is_empty():
			text = "— НЕ НАЗНАЧЕНО —"
			color = UITokens.STONE_5

		var text_width: float = UIStyle.text_width(text, UITokens.FONT_BODY)
		UIStyle.draw_text(
			self,
			Vector2(right - text_width, baseline),
			text,
			color,
			UITokens.FONT_BODY
		)
