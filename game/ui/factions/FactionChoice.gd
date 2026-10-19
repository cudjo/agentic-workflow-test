class_name FactionChoice
extends CanvasLayer
## FactionChoice — экран выбора фракции (T-24, PLAN §5; US-06, данные T-27).
##
## По сюжету экран открывается сигналом `EventBus.faction_choice_requested`
## (причина — текст под заголовком) либо публичным `open()`. Выбор фиксируется
## через `FactionManager.choose_faction()` и сразу попадает в `GameState`
## (`chosen_faction`) — его пишет сейв и использует концовка (T-32/T-16).
##
## Навигация без мыши: `↑`/`↓` — фракции, `←`/`→` — список ↔ действия,
## `Enter`/`A` дважды — подтверждение («выбрать» → «присягнуть»), `Esc`/`B` —
## закрыть без выбора. Статус доступа и репутация продублированы словами и
## знаком, не только цветом (a11y §9.1).

signal opened
signal closed
signal choice_made(faction_id: StringName)

const LAYER: int = 20
const TITLE_TEXT: String = "ui.choice.title"
const DEFAULT_REASON: String = "ui.choice.default_reason"
const CONFIRM_TEXT: String = "ui.choice.confirm"
const CANCEL_TEXT: String = "ui.choice.cancel"
const ACCESS_OPEN: String = "ui.factions.access_open_short"
const ACCESS_CLOSED: String = "ui.factions.access_closed_short"
const ACCESS_OPEN_LONG: String = "ui.factions.access_open"
const ACCESS_CLOSED_LONG: String = "ui.factions.access_closed"
const CHOSEN_MARK: String = "*"
const EMPTY_FACTIONS: String = "ui.factions.empty"
const IMPACT_TEXT: String = "ui.choice.impact"
const CONFIRM_HINT: String = "ui.choice.confirm_hint"
const HINT_TEXT: String = "ui.choice.hint"

const PANEL_RECT := Rect2(8, 8, 464, 254)
const LIST_RECT := Rect2(14, 54, 220, 168)
const DETAIL_RECT := Rect2(242, 54, 224, 168)
const ACTIONS_POSITION := Vector2(14, 226)
const ACTION_HEIGHT: int = 22
const STATUS_POSITION := Vector2(280, 226)
const ROW_HEIGHT: int = 24

## Пауза при открытии. QA/тесты выключают, чтобы не останавливать GUT.
var pause_on_open: bool = true

var _root: Control
var _panel: AshenPanel
var _title: Label
var _subtitle: Label
var _list_panel: AshenPanel
var _list_box: VBoxContainer
var _detail_panel: AshenPanel
var _detail_scroll: ScrollContainer
var _detail_box: VBoxContainer
var _confirm_button: AshenMenuItem
var _cancel_button: AshenMenuItem
var _status: Label
var _hint: Label

var _rows: Array[AshenMenuItem] = []
var _selected_id: StringName = &""
var _last_choice: StringName = &""
var _reason: String = ""
var _built: bool = false

var _pause_previous: bool = false
var _pause_owned: bool = false


func _init() -> void:
	name = "FactionChoice"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_ensure_built()
	if not Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.connect(_on_locale_changed)
	if not EventBus.faction_choice_requested.is_connected(_on_choice_requested):
		EventBus.faction_choice_requested.connect(_on_choice_requested)
	if not Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.connect(_on_ui_scale_changed)
	_refresh()
	apply_ui_scale()


func _exit_tree() -> void:
	if Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.disconnect(_on_locale_changed)
	if EventBus.faction_choice_requested.is_connected(_on_choice_requested):
		EventBus.faction_choice_requested.disconnect(_on_choice_requested)
	if Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.disconnect(_on_ui_scale_changed)
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false


# ------------------------------------------------------------------------------
# Открытие/закрытие
# ------------------------------------------------------------------------------

func open(reason: String = "") -> void:
	_ensure_built()
	_reason = reason
	_subtitle.text = reason if not reason.is_empty() else tr(DEFAULT_REASON)
	if visible:
		return

	visible = true
	_pause_previous = get_tree().paused
	_pause_owned = pause_on_open and not _pause_previous
	if pause_on_open:
		get_tree().paused = true
	_status.text = ""
	_refresh()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false
	_release_focus()
	closed.emit()


func is_open() -> bool:
	return visible


func get_selected_faction() -> StringName:
	return _selected_id


func get_last_choice() -> StringName:
	return _last_choice


## Выбор из списка с фокусом строки (мышь/тесты/внешние вызовы).
func select_faction(faction_id: StringName, focus: bool = true) -> void:
	if faction_id == &"" or FactionManager.get_faction(faction_id) == null:
		return
	_selected_id = faction_id
	_rebuild_detail()
	if focus and visible:
		var row: AshenMenuItem = _find_row(faction_id)
		if row != null:
			row.grab_focus()


## Фиксирует выбор через FactionManager; true — выбор принят.
func confirm_choice() -> bool:
	if _selected_id == &"":
		return false
	if not FactionManager.choose_faction(_selected_id):
		return false
	_last_choice = _selected_id
	choice_made.emit(_selected_id)
	close()
	return true


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed(&"ui_cancel"):
		close()
		_consume()
		return

	if event.is_action_pressed(&"ui_up"):
		_move_selection(-1)
		_consume()
		return
	if event.is_action_pressed(&"ui_down"):
		_move_selection(1)
		_consume()
		return
	if event.is_action_pressed(&"ui_left"):
		_move_action_focus(-1)
		_consume()
		return
	if event.is_action_pressed(&"ui_right"):
		_move_action_focus(1)
		_consume()
		return
	if event.is_action_pressed(&"ui_accept"):
		_on_accept()
		_consume()


func _consume() -> void:
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------
# Данные
# ------------------------------------------------------------------------------

func get_view_data() -> Dictionary:
	var factions: Array[Dictionary] = []
	for faction_id: StringName in FactionManager.get_faction_ids():
		var info: Dictionary = FactionManager.get_access_info(
			faction_id,
			FactionManager.AccessKind.TERRITORY
		)
		factions.append({
			"id": faction_id,
			"name": FactionManager.get_faction_name(faction_id),
			"reputation": int(info.get("reputation", 0)),
			"threshold": int(info.get("threshold", 0)),
			"allowed": bool(info.get("allowed", false)),
			"reason": str(info.get("reason", "")),
			"chosen": FactionManager.get_selected_faction() == faction_id,
		})

	var rows: Array[String] = []
	for row: AshenMenuItem in _rows:
		rows.append("%s %s" % [row.prefix_tag, row.text])

	return {
		"open": visible,
		"reason": _reason,
		"factions": factions,
		"rows": rows,
		"selected": _selected_id,
		"chosen": FactionManager.get_selected_faction(),
		"last_choice": _last_choice,
		"detail": _detail_text(),
	}


func get_confirm_button() -> AshenMenuItem:
	_ensure_built()
	return _confirm_button


func get_cancel_button() -> AshenMenuItem:
	_ensure_built()
	return _cancel_button


func get_list_rows() -> Array[AshenMenuItem]:
	return _rows.duplicate()


func get_status_label() -> Label:
	_ensure_built()
	return _status


func get_detail_text() -> String:
	_ensure_built()
	return _detail_text()


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
	dim.color = Color(UITokens.VOID, 0.96)
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

	_title = _make_label(tr(TITLE_TEXT), UITokens.GOLD_3, UITokens.FONT_H2)
	_title.name = "Title"
	_title.position = Vector2(16, 10)
	_title.size = Vector2(360, UITokens.LINE_H2)
	_root.add_child(_title)

	_subtitle = _make_label(tr(DEFAULT_REASON), UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, true)
	_subtitle.name = "Subtitle"
	_subtitle.position = Vector2(16, 30)
	_subtitle.size = Vector2(448, 20)
	_root.add_child(_subtitle)

	_list_panel = AshenPanel.new()
	_list_panel.name = "ListPanel"
	_list_panel.variant = UIStyle.PanelVariant.INSET
	_list_panel.padding = 4
	_root.add_child(_list_panel)
	_list_panel.position = LIST_RECT.position
	_list_panel.size = LIST_RECT.size

	_list_box = VBoxContainer.new()
	_list_box.name = "Rows"
	_list_box.add_theme_constant_override("separation", UITokens.SP_2)
	_list_panel.add_child(_list_box)

	_detail_panel = AshenPanel.new()
	_detail_panel.name = "DetailPanel"
	_detail_panel.variant = UIStyle.PanelVariant.SOLID
	_detail_panel.padding = 4
	_root.add_child(_detail_panel)
	_detail_panel.position = DETAIL_RECT.position
	_detail_panel.size = DETAIL_RECT.size

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "DetailScroll"
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_detail_panel.add_child(_detail_scroll)

	_detail_box = VBoxContainer.new()
	_detail_box.name = "DetailRows"
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", UITokens.SP_2)
	_detail_scroll.add_child(_detail_box)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", UITokens.SP_3)
	_root.add_child(actions)
	actions.position = ACTIONS_POSITION

	_confirm_button = AshenMenuItem.new()
	_confirm_button.name = "Confirm"
	_confirm_button.text = tr(CONFIRM_TEXT)
	_confirm_button.font_size = UITokens.FONT_BODY
	_confirm_button.custom_minimum_size = Vector2(152, ACTION_HEIGHT)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	actions.add_child(_confirm_button)

	_cancel_button = AshenMenuItem.new()
	_cancel_button.name = "Cancel"
	_cancel_button.text = tr(CANCEL_TEXT)
	_cancel_button.font_size = UITokens.FONT_BODY
	_cancel_button.custom_minimum_size = Vector2(88, ACTION_HEIGHT)
	_cancel_button.pressed.connect(close)
	actions.add_child(_cancel_button)

	_status = _make_label("", UITokens.GOLD_3, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, true)
	_status.name = "Status"
	_status.position = STATUS_POSITION
	_status.size = Vector2(186, ACTION_HEIGHT)
	_root.add_child(_status)

	_hint = _make_label(tr(HINT_TEXT), UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, false)
	_hint.name = "Hint"
	_hint.position = Vector2(14, 250)
	_hint.size = Vector2(452, UITokens.LINE_BODY)
	_root.add_child(_hint)


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
# Масштаб UI (a11y §9.6 п.6)
# ------------------------------------------------------------------------------

func _on_ui_scale_changed(_scale: int) -> void:
	apply_ui_scale()


func apply_ui_scale() -> void:
	if not _built or _root == null:
		return
	UIScale.apply(self)

	# Строка фракции «ЗАКРЫТ … +2» при 12 px = 192 px: расширяем список,
	# детали сдвигаем вправо (a11y §9.6 п.6).
	var list_width: float = clampf(
		maxf(LIST_RECT.size.x, UIScale.px(LIST_RECT.size.x)),
		LIST_RECT.size.x,
		244.0
	)
	_list_panel.size.x = list_width
	var detail_x: float = LIST_RECT.position.x + list_width + 8.0
	_detail_panel.position.x = detail_x
	_detail_panel.size.x = maxf(120.0, PANEL_RECT.end.x - 14.0 - detail_x + 8.0)
	if _subtitle != null:
		_subtitle.position.y = 38.0 if UIScale.factor() > 1.0 else 30.0
	# Кнопки действий и подсказка делят нижнюю полосу: держим их в 22 px,
	# чтобы на 150/200 % подсказка не наезжала на кнопки.
	for button: AshenMenuItem in [_confirm_button, _cancel_button]:
		if button == null:
			continue
		var base_min: Vector2 = button.get_meta(UIScale.META_MIN, button.custom_minimum_size)
		var base_width: float = base_min.x
		button.custom_minimum_size.y = float(ACTION_HEIGHT)
		if button.get_parent() is HBoxContainer:
			button.custom_minimum_size.x = maxf(
				base_width,
				UIStyle.text_width(button.text, button.font_size) + float(button.font_size) + 8.0
			)


# ------------------------------------------------------------------------------
# Список и детали
# ------------------------------------------------------------------------------

func _on_locale_changed(_code: String) -> void:
	_retranslate()


func _retranslate() -> void:
	if not _built:
		return
	_title.text = tr(TITLE_TEXT)
	if _reason.is_empty():
		_subtitle.text = tr(DEFAULT_REASON)
	_confirm_button.text = tr(CONFIRM_TEXT)
	_cancel_button.text = tr(CANCEL_TEXT)
	_hint.text = tr(HINT_TEXT)
	if _confirm_button.has_focus():
		_status.text = tr(CONFIRM_HINT)
	_refresh()


func _refresh() -> void:
	var ids: Array[StringName] = FactionManager.get_faction_ids()
	if _selected_id == &"" or not ids.has(_selected_id):
		_selected_id = FactionManager.get_selected_faction()
	if _selected_id == &"" or not ids.has(_selected_id):
		_selected_id = ids[0] if not ids.is_empty() else &""
	_rebuild_rows()
	_rebuild_detail()
	apply_ui_scale()
	if visible:
		_focus_selected()


func _rebuild_rows() -> void:
	for child: Node in _list_box.get_children():
		child.free()
	_rows.clear()

	var ids: Array[StringName] = FactionManager.get_faction_ids()
	if ids.is_empty():
		_list_box.add_child(_make_label(tr(EMPTY_FACTIONS), UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, true))
		return

	var chosen: StringName = FactionManager.get_selected_faction()
	for faction_id: StringName in ids:
		var info: Dictionary = FactionManager.get_access_info(
			faction_id,
			FactionManager.AccessKind.TERRITORY
		)
		var allowed: bool = bool(info.get("allowed", false))
		var row := AshenMenuItem.new()
		row.name = "Faction_%s" % String(faction_id)
		row.prefix_tag = (tr(ACCESS_OPEN) + " ") if allowed else (tr(ACCESS_CLOSED) + " ")
		var name_text: String = FactionManager.get_faction_name(faction_id)
		if chosen == faction_id:
			name_text = "%s %s" % [CHOSEN_MARK, name_text]
		row.text = "%s %s" % [name_text, _format_reputation(int(info.get("reputation", 0)))]
		row.font_size = UITokens.FONT_BODY
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tooltip: String = (
			str(info.get("reason", "")) if not allowed else tr(ACCESS_OPEN_LONG)
		)
		row.set_meta("faction_id", faction_id)
		row.focus_entered.connect(_on_row_focused.bind(row))
		row.pressed.connect(_on_row_pressed.bind(faction_id))
		_list_box.add_child(row)
		# `_ready()` компонента сбрасывает tooltip — ставим после добавления.
		row.tooltip_text = tooltip
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		_rows.append(row)

	_link_focus_neighbors()


func _link_focus_neighbors() -> void:
	if _rows.is_empty():
		return
	for index: int in _rows.size():
		var row: AshenMenuItem = _rows[index]
		var top: AshenMenuItem = _rows[index - 1] if index > 0 else _rows[_rows.size() - 1]
		var bottom: AshenMenuItem = (
			_rows[index + 1] if index < _rows.size() - 1 else _rows[0]
		)
		row.focus_neighbor_top = top.get_path()
		row.focus_neighbor_bottom = bottom.get_path()


func _find_row(faction_id: StringName) -> AshenMenuItem:
	for row: AshenMenuItem in _rows:
		if StringName(row.get_meta("faction_id", &"")) == faction_id:
			return row
	return null


func _focus_selected() -> void:
	if not visible:
		return
	var row: AshenMenuItem = _find_row(_selected_id)
	if row == null and not _rows.is_empty():
		row = _rows[0]
	if row != null:
		row.grab_focus()


func _rebuild_detail() -> void:
	for child: Node in _detail_box.get_children():
		child.free()

	if _selected_id == &"":
		_detail_box.add_child(_make_label(EMPTY_FACTIONS, UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, true))
		return

	var faction_id: StringName = _selected_id
	var info: Dictionary = FactionManager.get_access_info(
		faction_id,
		FactionManager.AccessKind.TERRITORY
	)
	var allowed: bool = bool(info.get("allowed", false))

	_detail_box.add_child(
		_make_label(FactionManager.get_faction_name(faction_id), UITokens.GOLD_3, UITokens.FONT_H2)
	)
	var rule := ColorRect.new()
	rule.color = UITokens.STONE_9
	rule.custom_minimum_size = Vector2(0, UITokens.BORDER_INNER)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_box.add_child(rule)

	# Лор и полная причина отказа живут на вкладке «Фракции»; экран присяги
	# показывает только то, что нужно для решения (имя, репутация, доступ).
	_detail_box.add_child(
		_make_label(tr("ui.choice.reputation") % int(info.get("reputation", 0)), UITokens.BONE)
	)
	_detail_box.add_child(
		_make_label(tr("ui.choice.threshold") % int(info.get("threshold", 0)), UITokens.STONE_5)
	)
	_detail_box.add_child(
		_make_label(
			tr(ACCESS_OPEN_LONG) if allowed else tr(ACCESS_CLOSED_LONG),
			UITokens.STEEL_3 if allowed else UITokens.BLOOD_5
		)
	)
	_detail_box.add_child(_make_label(tr(IMPACT_TEXT), UITokens.STEEL_3, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, true))

	if FactionManager.get_selected_faction() == faction_id:
		_detail_box.add_child(
			_make_label(tr("ui.choice.chosen") % CHOSEN_MARK, UITokens.GOLD_3)
		)


func _detail_text() -> String:
	var parts: Array[String] = []
	for child: Node in _detail_box.get_children():
		if child is Label:
			parts.append((child as Label).text)
	return "\n".join(parts)


func _release_focus() -> void:
	if get_viewport() == null:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and is_instance_valid(focus) and _root != null and _root.is_ancestor_of(focus):
		focus.release_focus()


# ------------------------------------------------------------------------------
# Навигация
# ------------------------------------------------------------------------------

func _move_selection(step: int) -> void:
	if _rows.is_empty():
		return
	var index: int = 0
	for row_index: int in _rows.size():
		if StringName(_rows[row_index].get_meta("faction_id", &"")) == _selected_id:
			index = row_index
			break
	index = wrapi(index + step, 0, _rows.size())
	_selected_id = StringName(_rows[index].get_meta("faction_id", &""))
	_rebuild_detail()
	_rows[index].grab_focus()
	_status.text = ""


func _move_action_focus(step: int) -> void:
	if _confirm_button.has_focus():
		if step > 0:
			_cancel_button.grab_focus()
		else:
			_focus_selected()
		return
	if _cancel_button.has_focus():
		if step > 0:
			_focus_selected()
		else:
			_confirm_button.grab_focus()
		return
	if step > 0:
		_confirm_button.grab_focus()
	else:
		_cancel_button.grab_focus()


func _on_accept() -> void:
	if _confirm_button.has_focus():
		confirm_choice()
		return
	if _cancel_button.has_focus():
		close()
		return
	if _rows.is_empty():
		return
	# Первый Enter/A выбирает строку и переводит фокус на «Присягнуть» —
	# выбор фракции необратим, случайное нажатие не должно его фиксировать.
	_rebuild_detail()
	_confirm_button.grab_focus()
	_status.text = tr(CONFIRM_HINT)


func _on_row_focused(row: AshenMenuItem) -> void:
	var faction_id: StringName = StringName(row.get_meta("faction_id", &""))
	if faction_id == &"" or faction_id == _selected_id:
		return
	_selected_id = faction_id
	_rebuild_detail()
	_status.text = ""


func _on_row_pressed(faction_id: StringName) -> void:
	select_faction(faction_id, false)
	_confirm_button.grab_focus()
	_on_accept_pressed_hint()


func _on_accept_pressed_hint() -> void:
	_status.text = CONFIRM_HINT


func _on_confirm_pressed() -> void:
	confirm_choice()


func _on_choice_requested(reason: String) -> void:
	open(reason)


static func _format_reputation(value: int) -> String:
	return "%+d" % value
