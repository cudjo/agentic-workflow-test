class_name JournalScreen
extends CanvasLayer
## JournalScreen — вкладка «Журнал» (T-24, PLAN §5; данные T-28).
##
## Показывает:
##   * квесты из `Journal.get_quest_entries()` — активные и завершённые
##     (разделы, статус словом, «!»/маркер формы, не только цвет);
##   * события из `Journal.get_events()` — последние записи мира/диалогов.
##
## Вкладки «КВЕСТЫ» / «СОБЫТИЯ» переключаются `Tab`/`Shift+Tab` или `LB`/`RB`
## (a11y §9.2), список — `↑`/`↓` (родная навигация фокуса `AshenMenuItem`).
## `Esc`/`B` закрывает экран. Пока экран открыт, игра на паузе
## (`pause_on_open`, QA/тесты выключают).
##
## Экран реактивен: `Journal.journal_changed` перестраивает список, сохраняя
## выбранную запись. Состояние дублируется текстом («АКТИВЕН»/«ЗАВЕРШЁН»),
## пустые состояния — по DESIGN §6.6.

signal opened
signal closed

const LAYER: int = 20
const TITLE_TEXT: String = "ui.journal.title"
const TAB_QUESTS: int = 0
const TAB_EVENTS: int = 1
const TAB_TITLES: Array[String] = ["ui.journal.tab_quests", "ui.journal.tab_events"]

const QUEST_STATUS_ACTIVE: String = "ui.journal.status_active"
const QUEST_STATUS_COMPLETED: String = "ui.journal.status_completed"
const EVENT_STATUS_PREFIX: String = "ui.journal.event_status"
const EMPTY_ACTIVE: String = "ui.journal.empty_active"
const EMPTY_COMPLETED: String = "ui.journal.empty_completed"
const EMPTY_EVENTS: String = "ui.journal.empty_events"
const EMPTY_JOURNAL: String = "ui.journal.empty_journal"
const EMPTY_SELECTION: String = "ui.journal.empty_selection"
const EMPTY_DESCRIPTION: String = "ui.journal.empty_description"
const HINT_TEXT: String = "ui.journal.hint"
const CLOSE_TEXT: String = "ui.common.close"

const PANEL_RECT := Rect2(8, 8, 464, 254)
const TAB_POSITION := Vector2(150, 10)
const LIST_RECT := Rect2(14, 34, 452, 156)
const DETAIL_RECT := Rect2(14, 194, 452, 52)
const FOOTER_Y: int = 250
const ROW_HEIGHT: int = UITokens.ROW_MENU_BODY
const SECTION_HEIGHT: int = UITokens.LINE_BODY

## Пауза при открытии. QA/тесты выключают, чтобы не останавливать GUT.
var pause_on_open: bool = true

var _root: Control
var _panel: AshenPanel
var _title: Label
var _hint: Label
var _tab_bar: AshenTabBar
var _list_panel: AshenPanel
var _scroll: ScrollContainer
var _list_box: VBoxContainer
var _detail_panel: AshenPanel
var _detail_status: Label
var _detail_text: Label
var _prompt: AshenPrompt

var _rows: Array[AshenMenuItem] = []
var _quest_entries: Array[Dictionary] = []
var _event_entries: Array[Dictionary] = []
var _selected_key: String = ""
var _selected_entry: Dictionary = {}
var _tab_index: int = TAB_QUESTS
var _built: bool = false

var _pause_previous: bool = false
var _pause_owned: bool = false


func _init() -> void:
	name = "Journal"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_ensure_built()
	if not Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.connect(_on_locale_changed)
	if not Journal.journal_changed.is_connected(_on_journal_changed):
		Journal.journal_changed.connect(_on_journal_changed)
	if not Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.connect(_on_ui_scale_changed)
	_refresh()
	apply_ui_scale()


func _exit_tree() -> void:
	if Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.disconnect(_on_locale_changed)
	if Journal.journal_changed.is_connected(_on_journal_changed):
		Journal.journal_changed.disconnect(_on_journal_changed)
	if Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.disconnect(_on_ui_scale_changed)
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false


# ------------------------------------------------------------------------------
# Открытие/закрытие
# ------------------------------------------------------------------------------

func open(tab_index: int = TAB_QUESTS) -> void:
	_ensure_built()
	if visible:
		set_tab(tab_index)
		return

	_tab_index = clampi(tab_index, 0, TAB_TITLES.size() - 1)
	_tab_bar.select(_tab_index, false)
	visible = true
	_pause_previous = get_tree().paused
	_pause_owned = pause_on_open and not _pause_previous
	if pause_on_open:
		get_tree().paused = true
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


func set_tab(index: int, focus: bool = true) -> void:
	var clamped: int = clampi(index, 0, TAB_TITLES.size() - 1)
	_tab_index = clamped
	_tab_bar.select(clamped, false)
	_selected_key = ""
	_refresh()
	if focus and visible:
		_tab_bar.focus_selected()
		_focus_first_row()


func get_tab_index() -> int:
	return _tab_index


func _input(event: InputEvent) -> void:
	if not visible:
		# Вход в игре: `journal` (N / L3). Не открываемся поверх другой
		# модальной паузы/диалога — иначе экраны наложатся.
		if event.is_action_pressed(&"journal") and not _other_modal_open():
			open()
			_consume()
		return
	if event.is_action_pressed(&"journal"):
		close()
		_consume()
		return
	if _tab_bar.handle_tab_input(event):
		_consume()
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		_consume()


func _other_modal_open() -> bool:
	if get_tree().paused:
		return true
	for group: StringName in [&"dialogue_ui", &"campfire_ui"]:
		var node: Node = get_tree().get_first_node_in_group(group)
		if node is CanvasItem and (node as CanvasItem).visible:
			return true
	return false


func _consume() -> void:
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------
# Данные
# ------------------------------------------------------------------------------

## Снимок для тестов/QA: что реально показано на вкладках.
func get_view_data() -> Dictionary:
	var active: Array[String] = []
	var completed: Array[String] = []
	for entry: Dictionary in _quest_entries:
		var title: String = str(entry.get("title", ""))
		if StringName(entry.get("status", &"")) == &"completed":
			completed.append(title)
		else:
			active.append(title)

	var events: Array[String] = []
	for entry: Dictionary in _event_entries:
		events.append(str(entry.get("text", "")))

	var rows: Array[String] = []
	for row: AshenMenuItem in _rows:
		rows.append(row.text)

	return {
		"tab": _tab_index,
		"tabs": TAB_TITLES.duplicate(),
		"active": active,
		"completed": completed,
		"events": events,
		"rows": rows,
		"selected": _selected_key,
		"empty": _rows.is_empty(),
		"detail_status": _detail_status.text if _detail_status != null else "",
		"detail_text": _detail_text.text if _detail_text != null else "",
	}


func get_tab_bar() -> AshenTabBar:
	_ensure_built()
	return _tab_bar


func get_list_rows() -> Array[AshenMenuItem]:
	return _rows.duplicate()


func get_detail_status_label() -> Label:
	_ensure_built()
	return _detail_status


func get_detail_text_label() -> Label:
	_ensure_built()
	return _detail_text


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

	_title = _make_label(tr(TITLE_TEXT), UITokens.GOLD_3, UITokens.FONT_H2)
	_title.name = "Title"
	_title.position = Vector2(16, 10)
	_title.size = Vector2(128, UITokens.LINE_H2)
	_root.add_child(_title)

	_tab_bar = AshenTabBar.new()
	_tab_bar.name = "Tabs"
	_tab_bar.min_tab_width = 92
	_tab_bar.set_tabs(_localized_tabs())
	_root.add_child(_tab_bar)
	_tab_bar.position = TAB_POSITION
	_tab_bar.size = Vector2(300, UITokens.TAB_HEIGHT)
	_tab_bar.tab_changed.connect(_on_tab_changed)

	_hint = _make_label(tr(HINT_TEXT), UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_RIGHT)
	_hint.name = "Hint"
	_hint.position = Vector2(140, FOOTER_Y)
	_hint.size = Vector2(326, UITokens.LINE_BODY)
	_root.add_child(_hint)

	_list_panel = AshenPanel.new()
	_list_panel.name = "ListPanel"
	_list_panel.variant = UIStyle.PanelVariant.INSET
	_list_panel.padding = 4
	_root.add_child(_list_panel)
	_list_panel.position = LIST_RECT.position
	_list_panel.size = LIST_RECT.size

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_list_panel.add_child(_scroll)

	_list_box = VBoxContainer.new()
	_list_box.name = "Rows"
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", UITokens.SP_1)
	_scroll.add_child(_list_box)

	_detail_panel = AshenPanel.new()
	_detail_panel.name = "DetailPanel"
	_detail_panel.variant = UIStyle.PanelVariant.SOLID
	_detail_panel.padding = 4
	_root.add_child(_detail_panel)
	_detail_panel.position = DETAIL_RECT.position
	_detail_panel.size = DETAIL_RECT.size

	_detail_status = _make_label("", UITokens.GOLD_3, UITokens.FONT_BODY)
	_detail_status.name = "DetailStatus"
	_detail_status.position = DETAIL_RECT.position + Vector2(10, 4)
	_detail_status.size = Vector2(DETAIL_RECT.size.x - 20, UITokens.LINE_BODY)
	_root.add_child(_detail_status)

	_detail_text = _make_label("", UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, true)
	_detail_text.name = "DetailText"
	_detail_text.position = DETAIL_RECT.position + Vector2(10, 18)
	_detail_text.size = Vector2(DETAIL_RECT.size.x - 20, 30)
	_root.add_child(_detail_text)

	_prompt = AshenPrompt.new()
	_prompt.name = "ClosePrompt"
	_root.add_child(_prompt)
	_prompt.position = Vector2(14, FOOTER_Y)
	_prompt.setup(&"ui_cancel", tr(CLOSE_TEXT))


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


func _make_section(text: String, color: Color = UITokens.STEEL_3) -> Label:
	var label := _make_label(text, color, UITokens.FONT_BODY)
	label.custom_minimum_size = Vector2(0, SECTION_HEIGHT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


# ------------------------------------------------------------------------------
# Масштаб UI (a11y §9.6 п.6): 8 → 12 px при 150 %, 8 → 16 px при 200 %
# ------------------------------------------------------------------------------

func _on_ui_scale_changed(_scale: int) -> void:
	apply_ui_scale()


## Пересчитывает шрифты, строки и геометрию списка/деталей так, чтобы текст
## не обрезался на 150/200 %.
func apply_ui_scale() -> void:
	if not _built or _root == null:
		return
	UIScale.apply(self)

	var detail_bottom: float = DETAIL_RECT.end.y
	var detail_height: float = maxf(DETAIL_RECT.size.y, UIScale.px(DETAIL_RECT.size.y))
	var detail_y: float = detail_bottom - detail_height
	_detail_panel.position.y = detail_y
	_detail_panel.size.y = detail_height

	var list_y: float = LIST_RECT.position.y
	_list_panel.size.y = maxf(60.0, detail_y - list_y - 4.0)

	var font: int = UIScale.font(UITokens.FONT_BODY)
	_detail_status.position.y = detail_y + 4.0
	_detail_status.size.y = float(font) + 2.0
	var text_y: float = detail_y + maxf(18.0, float(font) + 6.0)
	_detail_text.position.y = text_y
	_detail_text.size.y = maxf(30.0, detail_bottom - text_y - 4.0)

	# На 150/200 % заголовок «ЖУРНАЛ» шире 128 px и наезжает на вкладки.
	_tab_bar.position.x = 172.0 if UIScale.factor() > 1.0 else TAB_POSITION.x
	# На 150/200 % строка EN-квеста (420 px при 12 px) не влезает в 452 px
	# из-за полосы прокрутки: используем всю ширину экрана.
	if UIScale.factor() > 1.0:
		_list_panel.position.x = 8.0
		_list_panel.size.x = 464.0
		_detail_panel.position.x = 8.0
		_detail_panel.size.x = 464.0
		_detail_status.position.x = 18.0
		_detail_status.size.x = 444.0
		_detail_text.position.x = 18.0
		_detail_text.size.x = 444.0
	else:
		_list_panel.position.x = LIST_RECT.position.x
		_list_panel.size.x = LIST_RECT.size.x
		_detail_panel.position.x = DETAIL_RECT.position.x
		_detail_panel.size.x = DETAIL_RECT.size.x
		_detail_status.position.x = DETAIL_RECT.position.x + 10.0
		_detail_status.size.x = DETAIL_RECT.size.x - 20.0
		_detail_text.position.x = DETAIL_RECT.position.x + 10.0
		_detail_text.size.x = DETAIL_RECT.size.x - 20.0


# ------------------------------------------------------------------------------
# Перестроение списка
# ------------------------------------------------------------------------------

func _localized_tabs() -> PackedStringArray:
	var tabs := PackedStringArray()
	for key: String in TAB_TITLES:
		tabs.append(tr(key))
	return tabs


func _on_locale_changed(_code: String) -> void:
	_retranslate()


func _retranslate() -> void:
	if not _built:
		return
	_title.text = tr(TITLE_TEXT)
	_tab_bar.set_tabs(_localized_tabs())
	_hint.text = tr(HINT_TEXT)
	_prompt.setup(&"ui_cancel", tr(CLOSE_TEXT))
	_refresh()


func _refresh() -> void:
	_quest_entries.clear()
	for entry: Dictionary in Journal.get_quest_entries(Config.language):
		var copy: Dictionary = entry.duplicate(true)
		copy["kind"] = "quest"
		_quest_entries.append(copy)

	_event_entries.clear()
	var events: Array[Dictionary] = Journal.get_events()
	for index: int in events.size():
		var event: Dictionary = events[index]
		_event_entries.append({
			"kind": "event",
			"id": StringName(str(event.get("id", ""))),
			"text": str(event.get("text", "")),
			"index": index,
		})

	_rebuild_list()
	apply_ui_scale()

	if _rows.is_empty():
		_selected_key = ""
		_selected_entry = {}
		_set_empty_detail(tr(EMPTY_SELECTION) if _has_any_entry() else tr(EMPTY_JOURNAL))
		apply_ui_scale()
		return

	var target: AshenMenuItem = _find_row(_selected_key)
	if target == null:
		target = _rows[0]
	_selected_key = _row_key(target)
	_set_detail(target.get_meta("entry") as Dictionary)
	apply_ui_scale()
	if visible:
		target.grab_focus()


func _has_any_entry() -> bool:
	if _tab_index == TAB_EVENTS:
		return not _event_entries.is_empty()
	return not _quest_entries.is_empty()


func _rebuild_list() -> void:
	for child: Node in _list_box.get_children():
		child.free()
	_rows.clear()

	if _tab_index == TAB_QUESTS:
		_build_quest_rows()
	else:
		_build_event_rows()

	_link_focus_neighbors()


func _build_quest_rows() -> void:
	var active: Array[Dictionary] = []
	var completed: Array[Dictionary] = []
	for entry: Dictionary in _quest_entries:
		if StringName(entry.get("status", &"active")) == &"completed":
			completed.append(entry)
		else:
			active.append(entry)

	_list_box.add_child(_make_section(tr("ui.journal.section_active") % active.size(), UITokens.GOLD_3))
	if active.is_empty():
		_list_box.add_child(_make_section(tr(EMPTY_ACTIVE), UITokens.STONE_5))
	for entry: Dictionary in active:
		_add_quest_row(entry)

	_list_box.add_child(_make_section(tr("ui.journal.section_completed") % completed.size()))
	if completed.is_empty():
		_list_box.add_child(_make_section(tr(EMPTY_COMPLETED), UITokens.STONE_5))
	for entry: Dictionary in completed:
		_add_quest_row(entry)


func _build_event_rows() -> void:
	if _event_entries.is_empty():
		_list_box.add_child(_make_section(tr(EMPTY_EVENTS), UITokens.STONE_5))
		return

	for index: int in _event_entries.size():
		var entry: Dictionary = _event_entries[index]
		var row := AshenMenuItem.new()
		row.name = "Event%d" % index
		var text: String = str(entry.get("text", ""))
		if text.is_empty():
			text = String(entry.get("id", ""))
		row.text = text
		row.prefix_tag = "%02d " % (index + 1)
		row.font_size = UITokens.FONT_BODY
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.set_meta("entry", entry)
		row.set_meta("key", _event_key(index))
		row.focus_entered.connect(_on_row_focused.bind(row))
		_list_box.add_child(row)
		# `_ready()` компонента сбрасывает tooltip — ставим после добавления.
		row.tooltip_text = "%s: %s" % [String(entry.get("id", "")), text]
		_rows.append(row)


func _add_quest_row(entry: Dictionary) -> void:
	var completed: bool = StringName(entry.get("status", &"active")) == &"completed"
	var row := AshenMenuItem.new()
	var quest_id: StringName = StringName(str(entry.get("quest_id", "")))
	row.name = "Quest_%s" % String(quest_id)
	row.text = str(entry.get("title", String(quest_id)))
	row.prefix_tag = (
		(tr(QUEST_STATUS_COMPLETED) + " ") if completed else (tr(QUEST_STATUS_ACTIVE) + " ")
	)
	row.font_size = UITokens.FONT_BODY
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("entry", entry)
	row.set_meta("key", _quest_key(quest_id))
	row.focus_entered.connect(_on_row_focused.bind(row))
	_list_box.add_child(row)
	# `_ready()` компонента сбрасывает tooltip — ставим после добавления.
	row.tooltip_text = _quest_description(entry)
	_rows.append(row)


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


func _find_row(key: String) -> AshenMenuItem:
	if key.is_empty():
		return null
	for row: AshenMenuItem in _rows:
		if str(row.get_meta("key", "")) == key:
			return row
	return null


func _focus_first_row() -> void:
	if not visible or _rows.is_empty():
		return
	var target: AshenMenuItem = _find_row(_selected_key)
	if target == null:
		target = _rows[0]
	target.grab_focus()


func _release_focus() -> void:
	if get_viewport() == null:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and is_instance_valid(focus) and _root != null and _root.is_ancestor_of(focus):
		focus.release_focus()


func _on_tab_changed(index: int) -> void:
	_tab_index = clampi(index, 0, TAB_TITLES.size() - 1)
	_selected_key = ""
	_refresh()
	if visible:
		_focus_first_row()


func _on_journal_changed() -> void:
	_refresh()


func _on_row_focused(row: AshenMenuItem) -> void:
	_selected_key = str(row.get_meta("key", ""))
	_set_detail(row.get_meta("entry") as Dictionary)


# ------------------------------------------------------------------------------
# Детали записи
# ------------------------------------------------------------------------------

func _set_detail(entry: Dictionary) -> void:
	_selected_entry = entry.duplicate(true)
	if String(entry.get("kind", "")) == "event":
		var event_id: String = str(entry.get("id", ""))
		_detail_status.text = tr("ui.journal.event_prefix") % [
			tr(EVENT_STATUS_PREFIX),
			event_id if not event_id.is_empty() else "—",
		]
		_detail_status.add_theme_color_override("font_color", UITokens.STEEL_3)
		var event_text: String = str(entry.get("text", ""))
		_detail_text.text = event_text if not event_text.is_empty() else tr(EMPTY_DESCRIPTION)
		_detail_text.add_theme_color_override("font_color", UITokens.BONE)
		return

	var completed: bool = StringName(entry.get("status", &"active")) == &"completed"
	var faction: String = str(entry.get("faction_name", ""))
	var status: String = tr(QUEST_STATUS_COMPLETED) if completed else tr(QUEST_STATUS_ACTIVE)
	if not faction.is_empty():
		status += " · " + faction
	_detail_status.text = status
	_detail_status.add_theme_color_override(
		"font_color",
		UITokens.STEEL_3 if completed else UITokens.GOLD_3
	)
	var description: String = _quest_description(entry)
	_detail_text.text = description if not description.is_empty() else tr(EMPTY_DESCRIPTION)
	_detail_text.add_theme_color_override("font_color", UITokens.BONE)


func _set_empty_detail(message: String) -> void:
	_detail_status.text = "—"
	_detail_status.add_theme_color_override("font_color", UITokens.STONE_5)
	_detail_text.text = message
	_detail_text.add_theme_color_override("font_color", UITokens.STONE_5)


func _quest_description(entry: Dictionary) -> String:
	var quest_id: StringName = StringName(str(entry.get("quest_id", "")))
	if quest_id == &"":
		return ""
	var data: QuestData = QuestService.get_quest(quest_id)
	if data == null:
		return ""
	return data.get_description(Config.language)


func _quest_key(quest_id: StringName) -> String:
	return "quest:%s" % String(quest_id)


func _event_key(index: int) -> String:
	return "event:%d" % index


func _row_key(row: AshenMenuItem) -> String:
	return str(row.get_meta("key", ""))
