class_name FactionsScreen
extends CanvasLayer
## FactionsScreen — вкладка «Фракции» (T-24, PLAN §5; данные T-27).
##
## Левая колонка — три фракции со знаком репутации и статусом доступа словом
## («ДОСТУП» / «ЗАКРЫТ»). Правая — детали выбранной фракции:
##   * вкладка «СПИСОК» — лор, репутация, порог и причина отказа (AC-06.2);
##   * вкладка «ДОСТУП» — территория/торговец/квесты с причиной и
##     альтернативной фракцией (EC-11).
##
## Навигация без мыши: `↑`/`↓` — фракции, `Tab`/`Shift+Tab` или `LB`/`RB` —
## вкладки, `Esc`/`B` — закрыть (a11y §9.2). Состояние дублируется знаком
## «+»/«−», числом, словами и «!» — не только цветом.

signal opened
signal closed

const LAYER: int = 20
const TITLE_TEXT: String = "ui.factions.title"
const TAB_REPUTATION: int = 0
const TAB_ACCESS: int = 1
const TAB_TITLES: Array[String] = ["ui.factions.tab_list", "ui.factions.tab_access"]

const ACCESS_OPEN: String = "ui.factions.access_open_short"
const ACCESS_CLOSED: String = "ui.factions.access_closed_short"
const ACCESS_OPEN_LONG: String = "ui.factions.access_open"
const ACCESS_CLOSED_LONG: String = "ui.factions.access_closed"
const CHOSEN_MARK: String = "*"
const EMPTY_FACTIONS: String = "ui.factions.empty"
const HINT_TEXT: String = "ui.factions.hint"
const CLOSE_TEXT: String = "ui.common.close"
const KIND_TERRITORY: String = "ui.factions.kind_territory"
const KIND_TRADER: String = "ui.factions.kind_trader"
const KIND_QUEST: String = "ui.factions.kind_quest"

const PANEL_RECT := Rect2(8, 8, 464, 254)
const TAB_POSITION := Vector2(190, 10)
const LIST_RECT := Rect2(14, 34, 220, 214)
const DETAIL_RECT := Rect2(242, 34, 224, 214)
const FOOTER_Y: int = 250
const ROW_HEIGHT: int = 22

## Пауза при открытии. QA/тесты выключают, чтобы не останавливать GUT.
var pause_on_open: bool = true

var _root: Control
var _panel: AshenPanel
var _title: Label
var _tab_bar: AshenTabBar
var _hint: Label
var _list_panel: AshenPanel
var _list_box: VBoxContainer
var _detail_panel: AshenPanel
var _detail_scroll: ScrollContainer
var _detail_box: VBoxContainer
var _prompt: AshenPrompt

var _rows: Array[AshenMenuItem] = []
var _access_rows: Array[AshenMenuItem] = []
var _access_infos: Array[Dictionary] = []
var _access_reason: Label
var _selected_access_kind: int = 0
var _selected_id: StringName = &""
var _tab_index: int = TAB_REPUTATION
var _built: bool = false

var _pause_previous: bool = false
var _pause_owned: bool = false


func _init() -> void:
	name = "Factions"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_ensure_built()
	if not Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.connect(_on_locale_changed)
	if not EventBus.faction_reputation_changed.is_connected(_on_reputation_changed):
		EventBus.faction_reputation_changed.connect(_on_reputation_changed)
	if not EventBus.faction_access_changed.is_connected(_on_access_changed):
		EventBus.faction_access_changed.connect(_on_access_changed)
	if not EventBus.faction_chosen.is_connected(_on_faction_chosen):
		EventBus.faction_chosen.connect(_on_faction_chosen)
	_refresh()


func _exit_tree() -> void:
	if Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.disconnect(_on_locale_changed)
	if EventBus.faction_reputation_changed.is_connected(_on_reputation_changed):
		EventBus.faction_reputation_changed.disconnect(_on_reputation_changed)
	if EventBus.faction_access_changed.is_connected(_on_access_changed):
		EventBus.faction_access_changed.disconnect(_on_access_changed)
	if EventBus.faction_chosen.is_connected(_on_faction_chosen):
		EventBus.faction_chosen.disconnect(_on_faction_chosen)
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false


# ------------------------------------------------------------------------------
# Открытие/закрытие
# ------------------------------------------------------------------------------

func open(faction_id: StringName = &"") -> void:
	_ensure_built()
	if visible:
		select_faction(faction_id)
		return

	var target: StringName = faction_id
	if target == &"" or FactionManager.get_faction(target) == null:
		target = FactionManager.get_selected_faction()
	if target == &"" or FactionManager.get_faction(target) == null:
		var ids: Array[StringName] = FactionManager.get_faction_ids()
		target = ids[0] if not ids.is_empty() else &""
	_selected_id = target

	visible = true
	_pause_previous = get_tree().paused
	_pause_owned = pause_on_open and not _pause_previous
	if pause_on_open:
		get_tree().paused = true
	_tab_bar.select(_tab_index, false)
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


func select_faction(faction_id: StringName, focus: bool = true) -> void:
	if faction_id == &"" or FactionManager.get_faction(faction_id) == null:
		return
	_selected_id = faction_id
	_rebuild_detail()
	if focus and visible:
		var row: AshenMenuItem = _find_row(faction_id)
		if row != null:
			row.grab_focus()


func set_tab(index: int, focus: bool = true) -> void:
	_tab_index = clampi(index, 0, TAB_TITLES.size() - 1)
	_tab_bar.select(_tab_index, false)
	_rebuild_detail()
	if focus and visible:
		_focus_selected()


func get_tab_index() -> int:
	return _tab_index


func get_selected_faction() -> StringName:
	return _selected_id


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _tab_bar.handle_tab_input(event):
		_consume()
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		_consume()


func _consume() -> void:
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------
# Данные
# ------------------------------------------------------------------------------

## Снимок для тестов/QA.
func get_view_data() -> Dictionary:
	var factions: Array[Dictionary] = []
	for faction_id: StringName in FactionManager.get_faction_ids():
		var info: Dictionary = FactionManager.get_access_info(
			faction_id,
			FactionManager.AccessKind.TERRITORY
		)
		var alternative_id: StringName = StringName(str(info.get("alternative_faction_id", "")))
		factions.append({
			"id": faction_id,
			"name": FactionManager.get_faction_name(faction_id),
			"lore": FactionManager.get_faction_lore(faction_id),
			"reputation": int(info.get("reputation", 0)),
			"threshold": int(info.get("threshold", 0)),
			"allowed": bool(info.get("allowed", false)),
			"reason": str(info.get("reason", "")),
			"alternative_id": alternative_id,
			"alternative_name": FactionManager.get_faction_name(alternative_id),
			"alternative_allowed": bool(info.get("alternative_allowed", false)),
			"chosen": FactionManager.get_selected_faction() == faction_id,
		})

	var rows: Array[String] = []
	for row: AshenMenuItem in _rows:
		rows.append("%s %s" % [row.prefix_tag, row.text])

	return {
		"tab": _tab_index,
		"tabs": TAB_TITLES.duplicate(),
		"factions": factions,
		"rows": rows,
		"selected": _selected_id,
		"detail": _detail_text(),
	}


func get_tab_bar() -> AshenTabBar:
	_ensure_built()
	return _tab_bar


func get_list_rows() -> Array[AshenMenuItem]:
	return _rows.duplicate()


## Текст правой панели — для тестов/QA (причина отказа, альтернатива).
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
	_title.size = Vector2(168, UITokens.LINE_H2)
	_root.add_child(_title)

	_tab_bar = AshenTabBar.new()
	_tab_bar.name = "Tabs"
	_tab_bar.min_tab_width = 88
	_tab_bar.set_tabs(_localized_tabs())
	_root.add_child(_tab_bar)
	_tab_bar.position = TAB_POSITION
	_tab_bar.size = Vector2(200, UITokens.TAB_HEIGHT)
	_tab_bar.tab_changed.connect(_on_tab_changed)

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

	_hint = _make_label(tr(HINT_TEXT), UITokens.STONE_5, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_RIGHT)
	_hint.name = "Hint"
	_hint.position = Vector2(120, FOOTER_Y)
	_hint.size = Vector2(346, UITokens.LINE_BODY)
	_root.add_child(_hint)

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
	wrap: bool = true
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
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


# ------------------------------------------------------------------------------
# Список и детали
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
	var ids: Array[StringName] = FactionManager.get_faction_ids()
	if _selected_id == &"" or not ids.has(_selected_id):
		_selected_id = FactionManager.get_selected_faction()
	if _selected_id == &"" or not ids.has(_selected_id):
		_selected_id = ids[0] if not ids.is_empty() else &""
	_rebuild_rows()
	_rebuild_detail()
	if visible:
		_focus_selected()


func _rebuild_rows() -> void:
	for child: Node in _list_box.get_children():
		child.free()
	_rows.clear()

	var ids: Array[StringName] = FactionManager.get_faction_ids()
	if ids.is_empty():
		var empty := _make_label(tr(EMPTY_FACTIONS), UITokens.STONE_5)
		_list_box.add_child(empty)
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
		row.prefix_tag = (tr(ACCESS_CLOSED) + " ") if not allowed else (tr(ACCESS_OPEN) + " ")
		var name_text: String = FactionManager.get_faction_name(faction_id)
		if chosen == faction_id:
			name_text = "%s %s" % [CHOSEN_MARK, name_text]
		row.text = "%s %s" % [name_text, _format_reputation(int(info.get("reputation", 0)))]
		row.font_size = UITokens.FONT_BODY
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tooltip: String = (
			str(info.get("reason", ""))
			if not allowed
			else "%s: %s" % [tr(ACCESS_OPEN_LONG), FactionManager.get_faction_name(faction_id)]
		)
		row.set_meta("faction_id", faction_id)
		row.focus_entered.connect(_on_row_focused.bind(row))
		_list_box.add_child(row)
		# `_ready()` компонента выставляет базовую строку 16 px и сбрасывает
		# tooltip — фиксируем оба значения после добавления.
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
	_access_rows.clear()
	_access_infos.clear()
	_access_reason = null

	if _selected_id == &"":
		_detail_box.add_child(_make_label(tr(EMPTY_FACTIONS), UITokens.STONE_5))
		return

	if _tab_index == TAB_ACCESS:
		_build_access_detail()
	else:
		_clear_detail_focus_links()
		_build_reputation_detail()


func _build_reputation_detail() -> void:
	var faction_id: StringName = _selected_id
	var info: Dictionary = FactionManager.get_access_info(
		faction_id,
		FactionManager.AccessKind.TERRITORY
	)
	var allowed: bool = bool(info.get("allowed", false))
	var reputation: int = int(info.get("reputation", 0))
	var threshold: int = int(info.get("threshold", 0))

	_detail_box.add_child(
		_make_label(FactionManager.get_faction_name(faction_id), UITokens.GOLD_3, UITokens.FONT_H2, HORIZONTAL_ALIGNMENT_LEFT, false)
	)
	_detail_box.add_child(_make_rule())

	var lore: String = FactionManager.get_faction_lore(faction_id)
	if not lore.is_empty():
		_detail_box.add_child(_make_label(lore, UITokens.STONE_5))

	_detail_box.add_child(
		_make_label(tr("ui.factions.reputation") % _format_reputation(reputation), UITokens.BONE)
	)
	_detail_box.add_child(
		_make_label(tr("ui.factions.threshold") % _format_reputation(threshold, false), UITokens.STONE_5)
	)
	_detail_box.add_child(
		_make_label(_access_line(allowed), UITokens.STEEL_3 if allowed else UITokens.BLOOD_5)
	)
	if not allowed:
		_detail_box.add_child(_make_label(str(info.get("reason", "")), UITokens.BONE))
	_detail_box.add_child(_alternative_line(info))

	if FactionManager.get_selected_faction() == faction_id:
		_detail_box.add_child(
			_make_label(
				tr("ui.factions.chosen_for_ending") % CHOSEN_MARK,
				UITokens.GOLD_3
			)
		)


func _build_access_detail() -> void:
	var faction_id: StringName = _selected_id
	# Имя фракции уже видно в левом списке; здесь — только доступ и причина,
	# чтобы полный текст ограничения помещался в панель без обрезки.
	var kinds: Array[Dictionary] = [
		{
			"kind": FactionManager.AccessKind.TERRITORY,
			"label": KIND_TERRITORY,
		},
		{
			"kind": FactionManager.AccessKind.TRADER,
			"label": KIND_TRADER,
		},
		{
			"kind": FactionManager.AccessKind.QUEST,
			"label": KIND_QUEST,
		},
	]
	for entry: Dictionary in kinds:
		var info: Dictionary = FactionManager.get_access_info(
			faction_id,
			int(entry["kind"])
		)
		var allowed: bool = bool(info.get("allowed", false))
		var row := AshenMenuItem.new()
		row.name = "Access_%d" % _access_infos.size()
		row.text = tr(str(entry["label"]))
		row.prefix_tag = (tr(ACCESS_CLOSED_LONG) + " ") if not allowed else (tr(ACCESS_OPEN) + " ")
		row.font_size = UITokens.FONT_BODY
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.tooltip_text = str(info.get("reason", "")) if not allowed else _access_line(true)
		var index: int = _access_infos.size()
		row.focus_entered.connect(_on_access_focused.bind(index))
		_detail_box.add_child(row)
		row.tooltip_text = str(info.get("reason", "")) if not allowed else _access_line(true)
		row.custom_minimum_size = Vector2(0, UITokens.ROW_MENU_BODY)
		_access_rows.append(row)
		_access_infos.append(info)

	_access_reason = _make_label("", UITokens.BONE, UITokens.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT, true)
	_access_reason.name = "AccessReason"
	_detail_box.add_child(_access_reason)

	_link_access_focus()
	_on_access_focused(clampi(_selected_access_kind, 0, maxi(_access_infos.size() - 1, 0)))


func _on_access_focused(index: int) -> void:
	if index < 0 or index >= _access_infos.size():
		return
	_selected_access_kind = index
	var info: Dictionary = _access_infos[index]
	var allowed: bool = bool(info.get("allowed", false))
	var reputation: int = int(info.get("reputation", 0))
	var threshold: int = int(info.get("threshold", 0))
	var status: String = _access_line(allowed)
	var reason: String = str(info.get("reason", ""))
	if _access_reason != null:
		var lines: Array[String] = [
			tr("ui.factions.threshold_rep") % [threshold, reputation],
		]
		if allowed:
			lines.append(status)
		elif not reason.is_empty():
			# «ЗАКРЫТ !» уже стоит в строке вида доступа; здесь — причина.
			lines.append(reason)
		lines.append(_alternative_text(info))
		_access_reason.text = "\n".join(lines)
		_access_reason.add_theme_color_override(
			"font_color",
			UITokens.BONE if not allowed else UITokens.STEEL_3
		)


func _link_access_focus() -> void:
	if _access_rows.is_empty():
		return
	var first_access: AshenMenuItem = _access_rows[0]
	var faction_row: AshenMenuItem = _find_row(_selected_id)
	for row: AshenMenuItem in _rows:
		row.focus_neighbor_right = first_access.get_path()
	for index: int in _access_rows.size():
		var row: AshenMenuItem = _access_rows[index]
		row.focus_neighbor_left = faction_row.get_path() if faction_row != null else NodePath()
		row.focus_neighbor_top = _access_rows[maxi(index - 1, 0)].get_path()
		row.focus_neighbor_bottom = (
			_access_rows[mini(index + 1, _access_rows.size() - 1)].get_path()
		)


func _clear_detail_focus_links() -> void:
	for row: AshenMenuItem in _rows:
		row.focus_neighbor_right = NodePath()
		row.focus_neighbor_left = NodePath()


func _make_rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = UITokens.STONE_9
	rule.custom_minimum_size = Vector2(0, UITokens.BORDER_INNER)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _access_line(allowed: bool) -> String:
	return tr(ACCESS_OPEN_LONG) if allowed else tr(ACCESS_CLOSED_LONG)


func _alternative_text(info: Dictionary) -> String:
	var alternative_id: StringName = StringName(str(info.get("alternative_faction_id", "")))
	if alternative_id == &"":
		return tr("ui.factions.alternative_none")
	var alternative_name: String = FactionManager.get_faction_name(alternative_id)
	var alternative_allowed: bool = bool(info.get("alternative_allowed", false))
	return tr("ui.factions.alternative") % [
		alternative_name,
		tr(ACCESS_OPEN_LONG) if alternative_allowed else tr(ACCESS_CLOSED_LONG),
	]


func _alternative_line(info: Dictionary) -> Label:
	var alternative_id: StringName = StringName(str(info.get("alternative_faction_id", "")))
	var alternative_allowed: bool = bool(info.get("alternative_allowed", false))
	return _make_label(
		_alternative_text(info),
		UITokens.STEEL_3 if alternative_allowed else UITokens.STONE_5
	)


func _detail_text() -> String:
	var parts: Array[String] = []
	for child: Node in _detail_box.get_children():
		if child is Label:
			parts.append((child as Label).text)
		elif child is AshenMenuItem:
			var row := child as AshenMenuItem
			parts.append("%s%s" % [row.prefix_tag, row.text])
	return "\n".join(parts)


func _release_focus() -> void:
	if get_viewport() == null:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and is_instance_valid(focus) and _root != null and _root.is_ancestor_of(focus):
		focus.release_focus()


func _on_row_focused(row: AshenMenuItem) -> void:
	var faction_id: StringName = StringName(row.get_meta("faction_id", &""))
	if faction_id == &"" or faction_id == _selected_id:
		return
	_selected_id = faction_id
	_rebuild_detail()


func _on_tab_changed(index: int) -> void:
	_tab_index = clampi(index, 0, TAB_TITLES.size() - 1)
	_rebuild_detail()
	if visible:
		_focus_selected()


func _on_reputation_changed(_faction_id: StringName, _value: int) -> void:
	_refresh()


func _on_access_changed(_faction_id: StringName, _granted: bool) -> void:
	_refresh()


func _on_faction_chosen(_faction_id: StringName, _display_name: String) -> void:
	_refresh()


static func _format_reputation(value: int, with_sign: bool = true) -> String:
	if with_sign:
		return "%+d" % value
	return str(value)
