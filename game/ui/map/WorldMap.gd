class_name WorldMap
extends CanvasLayer
## WorldMap — полная карта мира (T-33, PLAN §5: недостающий макет).
##
## Открывается действием InputMap `map` (M / BACK на геймпаде), закрывается
## `map`/`ui_cancel`. Пока карта открыта, игра на паузе (кроме тестов/QA через
## `pause_on_open = false`), ввод не уходит в мир.
##
## Навигация без мыши: ↑/↓ (и ←/→) листают посещённые зоны, фокус на строке
## `AshenMenuItem` виден золотой кареткой/рамкой. Enter/геймпад A подтверждает
## выбор (обновляет детали), крестовина работает через те же `ui_*` действия.
##
## Данные — `WorldMapModel` (ZoneData + посещённые зоны + способности).
## Скрытая информация — один уровень: непосещённые зоны не раскрываются,
## но проходы к ним видны маркерами; закрытый проход показывает замок и
## иконку требуемой способности (AC-04.2).

signal opened
signal closed
signal zone_selected(zone_id: StringName)

const LAYER: int = 20
const VIEW_WIDTH: float = 480.0
const HEADER_RECT := Rect2(8, 8, 300, 18)
const PROMPT_RECT := Rect2(356, 8, 116, 12)
## 164 (а не 160): кнопки зон растягиваются до 160 px, EN «1. BASTION
## VILLAGE» = 144 px при доступных 146 px (a11y §9.6 п.6). Панель занимает
## x=8…180, карта начинается с 184 — зазор 4 px.
const LEFT_RECT := Rect2(8, 30, 164, 232)
const MAP_RECT := Rect2(184, 30, 288, 170)
const DETAIL_RECT := Rect2(184, 206, 288, 56)
const MAP_CELL := Vector2(23, 17)
const LEGEND_LINES: Array[String] = [
	"ui.map.legend_lock",
	"ui.map.legend_bonfire",
	"ui.map.legend_you",
]

## Пауза при открытии. QA/тесты выключают, чтобы не останавливать GUT.
var pause_on_open: bool = true

var _root: Control
var _dim: ColorRect
var _zone_panel: AshenPanel
var _zone_list: VBoxContainer
var _zone_buttons: Array[AshenMenuItem] = []
var _zone_ids: Array[StringName] = []
var _map_panel: AshenPanel
var _renderer: MapRenderer
var _detail_panel: AshenPanel
var _detail_name: Label
var _detail_state: Label
var _detail_gates: Label
var _prompt: AshenPrompt
var _header: Label
var _zones_title: Label
var _legend_box: VBoxContainer
var _model: WorldMapModel
var _data: Dictionary = {}
var _selected_index: int = -1
var _pause_previous: bool = false
var _pause_owned: bool = false


func _init() -> void:
	name = "WorldMap"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if not Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.connect(_on_locale_changed)
	if not Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.connect(_on_ui_scale_changed)
	_connect_event_bus()
	_refresh_data()
	apply_ui_scale()


func _exit_tree() -> void:
	if Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.disconnect(_on_locale_changed)
	if Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.disconnect(_on_ui_scale_changed)
	_disconnect_event_bus()
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false


# ------------------------------------------------------------------------------
# Открытие/закрытие (без мыши)
# ------------------------------------------------------------------------------

func is_open() -> bool:
	return visible


func toggle() -> bool:
	if visible:
		close()
		return false
	return open()


func open() -> bool:
	if visible:
		return false
	if _is_transitioning():
		return false
	_refresh_data()
	visible = true
	_pause_previous = get_tree().paused
	_pause_owned = pause_on_open and not _pause_previous
	if pause_on_open:
		get_tree().paused = true
	_select_index(_index_of_zone(GameState.current_zone_id), true)
	opened.emit()
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false
	if get_viewport() != null:
		get_viewport().gui_release_focus()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed(&"map"):
			toggle()
			_consume()
		return

	if event.is_action_pressed(&"map") or event.is_action_pressed(&"ui_cancel"):
		close()
		_consume()
		return
	if event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"ui_right"):
		navigate(1)
		_consume()
		return
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_left"):
		navigate(-1)
		_consume()
		return
	if event.is_action_pressed(&"ui_accept"):
		# Карта модальна: подтверждение не должно уходить в мир/меню под ней.
		_consume()


func _consume() -> void:
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


func _is_transitioning() -> bool:
	return SceneRouter.has_method(&"is_input_locked") and bool(SceneRouter.is_input_locked())


# ------------------------------------------------------------------------------
# Навигация
# ------------------------------------------------------------------------------

func navigate(step: int) -> void:
	if _zone_buttons.is_empty():
		return
	var current: int = _selected_index if _selected_index >= 0 else 0
	var next: int = wrapi(current + step, 0, _zone_buttons.size())
	_select_index(next, true)


func select_zone(zone_id: StringName) -> bool:
	var index: int = _index_of_zone(zone_id)
	if index < 0:
		return false
	_select_index(index, true)
	return true


func get_selected_zone_id() -> StringName:
	if _selected_index < 0 or _selected_index >= _zone_ids.size():
		return &""
	return _zone_ids[_selected_index]


func get_selected_index() -> int:
	return _selected_index


func get_zone_buttons() -> Array[AshenMenuItem]:
	var copy: Array[AshenMenuItem] = []
	copy.assign(_zone_buttons)
	return copy


func get_map_data() -> Dictionary:
	return _data.duplicate(true)


func get_renderer() -> MapRenderer:
	return _renderer


## Тексты деталей выбранной зоны — для QA/a11y (состояние не только цветом).
func get_detail_texts() -> Dictionary:
	return {
		"name": _detail_name.text if _detail_name != null else "",
		"state": _detail_state.text if _detail_state != null else "",
		"gates": _detail_gates.text if _detail_gates != null else "",
	}


func get_legend_lines() -> Array[String]:
	var copy: Array[String] = []
	for key: String in LEGEND_LINES:
		copy.append(tr(key))
	return copy


func get_zone_button_texts() -> Array[String]:
	var texts: Array[String] = []
	for button: AshenMenuItem in _zone_buttons:
		texts.append(button.text)
	return texts


# ------------------------------------------------------------------------------
# Данные
# ------------------------------------------------------------------------------

func _on_locale_changed(_code: String) -> void:
	if not is_inside_tree():
		return
	_header.text = tr("ui.map.title")
	_zones_title.text = tr("ui.map.visited_zones")
	_prompt.setup(&"map", tr("ui.map.close"))
	var index: int = 0
	for child: Node in _legend_box.get_children():
		if index < LEGEND_LINES.size():
			(child as Label).text = tr(LEGEND_LINES[index])
		index += 1
	_refresh_data()


func _refresh_data() -> void:
	var visited: Array[StringName] = []
	if SceneRouter.has_method(&"get_visited_zone_ids"):
		var stored: Variant = SceneRouter.get_visited_zone_ids()
		if stored is Array:
			for value: Variant in stored:
				visited.append(StringName(str(value)))
	var current_zone: StringName = GameState.current_zone_id
	if current_zone == &"" and SceneRouter.current_zone_id != &"":
		current_zone = SceneRouter.current_zone_id
	_data = _model_instance().build(
		visited,
		current_zone,
		_player_position(current_zone),
		GameState.get_abilities()
	)
	_renderer.set_data(_data)
	_rebuild_zone_list()
	_update_detail()
	apply_ui_scale()


func _model_instance() -> WorldMapModel:
	if _model == null:
		_model = WorldMapModel.new()
		_model.reload()
	return _model


func _player_position(zone_id: StringName) -> Vector2:
	var player: Node2D = null
	if SceneRouter.player != null and is_instance_valid(SceneRouter.player):
		player = SceneRouter.player
	elif get_tree() != null:
		player = get_tree().get_first_node_in_group(&"player") as Node2D
	if player != null:
		return player.global_position

	var data: ZoneData = _model_instance().get_zone(zone_id)
	if data == null:
		return Vector2.ZERO
	var entry_id: StringName = SceneRouter.current_entry_id
	if entry_id != &"":
		var entry_position: Vector2 = WorldMapModel.entry_position(data, entry_id)
		if entry_position != Vector2.ZERO:
			return entry_position
	var room: ZoneRoom = WorldMapModel.first_room(data)
	return room.world_rect.get_center() if room != null else Vector2.ZERO


func _rebuild_zone_list() -> void:
	var previous: StringName = get_selected_zone_id()
	var rooms: Array = _data.get("rooms", [])
	_zone_ids.clear()
	for room: Dictionary in rooms:
		_zone_ids.append(StringName(str(room.get("zone_id", ""))))

	for button: AshenMenuItem in _zone_buttons:
		_zone_list.remove_child(button)
		button.queue_free()
	_zone_buttons.clear()

	for index: int in _zone_ids.size():
		var room: Dictionary = rooms[index]
		var button := AshenMenuItem.new()
		button.text = "%d. %s" % [int(room.get("index", index + 1)), String(room.get("zone_name", "")).to_upper()]
		# Ширина — по доступной области панели; перенос/обрезка текста не нужны,
		# т.к. кнопка растягивается на всю колонку (a11y §9.6 п.6).
		button.custom_minimum_size = Vector2(160, UITokens.ROW_MENU_BODY)
		button.focus_entered.connect(_on_zone_focus.bind(index))
		button.pressed.connect(_on_zone_pressed.bind(index))
		_zone_list.add_child(button)
		_zone_buttons.append(button)

	var keep: int = _index_of_zone(previous)
	if keep < 0:
		keep = _index_of_zone(GameState.current_zone_id)
	if keep < 0 and not _zone_buttons.is_empty():
		keep = 0
	_select_index(keep, false)


func _select_index(index: int, grab: bool) -> void:
	if _zone_buttons.is_empty():
		_selected_index = -1
		_renderer.selected_zone_id = &""
		_update_detail()
		return
	_selected_index = clampi(index, 0, _zone_buttons.size() - 1)
	var zone_id: StringName = _zone_ids[_selected_index]
	_renderer.selected_zone_id = zone_id
	_update_detail()
	if grab and is_inside_tree():
		_zone_buttons[_selected_index].grab_focus()
	zone_selected.emit(zone_id)


func _on_zone_focus(index: int) -> void:
	_select_index(index, false)


func _on_zone_pressed(index: int) -> void:
	_select_index(index, true)


func _index_of_zone(zone_id: StringName) -> int:
	if zone_id == &"":
		return -1
	return _zone_ids.find(zone_id)


func _update_detail() -> void:
	if _detail_name == null:
		return
	var selected: StringName = get_selected_zone_id()
	if selected == &"":
		_detail_name.text = tr("ui.map.no_zones")
		_detail_state.text = tr("ui.map.explore")
		_detail_gates.text = ""
		return

	var room: Dictionary = {}
	for entry: Dictionary in _data.get("rooms", []):
		if StringName(str(entry.get("zone_id", ""))) == selected:
			room = entry
			break
	if room.is_empty():
		return

	_detail_name.text = "%d. %s" % [
		int(room.get("index", 0)),
		String(room.get("zone_name", "")).to_upper(),
	]
	var current: bool = bool(room.get("current", false))
	var has_bonfire: bool = _zone_has_bonfire(selected)
	_detail_state.text = tr("ui.map.state_bonfire") % [
		tr("ui.map.current_zone") if current else tr("ui.map.visited"),
		tr("ui.map.yes") if has_bonfire else tr("ui.map.no"),
	]
	_detail_gates.text = _gate_summary(selected)


func _zone_has_bonfire(zone_id: StringName) -> bool:
	for bonfire: Dictionary in _data.get("bonfires", []):
		if StringName(str(bonfire.get("zone_id", ""))) == zone_id:
			return true
	return false


func _gate_summary(zone_id: StringName) -> String:
	var locked: Array[String] = []
	var unknown_pass: bool = false
	for gate: Dictionary in _data.get("gates", []):
		if StringName(str(gate.get("zone_id", ""))) != zone_id:
			continue
		if bool(gate.get("locked", false)):
			var ability_id: StringName = StringName(str(gate.get("required_ability", "")))
			var label: String = WorldMapModel.ability_label(ability_id)
			if label != "" and not locked.has(label):
				locked.append(label)
		elif not bool(gate.get("target_visited", false)):
			unknown_pass = true
	if not locked.is_empty():
		return tr("ui.map.locked") % ", ".join(locked)
	if unknown_pass:
		return tr("ui.map.unknown_pass")
	return tr("ui.map.no_passes")


# ------------------------------------------------------------------------------
# Построение
# ------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(UITokens.VOID, 0.94)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_dim)

	_header = _make_label(tr("ui.map.title"), UITokens.GOLD_3, UITokens.FONT_H2)
	_add_at(_header, HEADER_RECT)

	_prompt = AshenPrompt.new()
	_prompt.setup(&"map", tr("ui.map.close"))
	_add_at(_prompt, PROMPT_RECT)

	_build_zone_panel()
	_build_map_panel()
	_build_detail_panel()


func _build_zone_panel() -> void:
	_zone_panel = AshenPanel.new()
	_zone_panel.variant = UIStyle.PanelVariant.SOLID
	# 0 (а не SP_1): кнопка зоны 160 px помещается в панель, EN-название
	# «1. BASTION VILLAGE» (144 px) влезает с запасом (a11y §9.6 п.6).
	# Внутренний отступ рамки (6 px) остаётся.
	_zone_panel.padding = 0
	_add_at(_zone_panel, LEFT_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITokens.SP_2)
	_zone_panel.add_child(column)

	_zones_title = _make_label(tr("ui.map.visited_zones"), UITokens.STONE_5, UITokens.FONT_BODY)
	column.add_child(_zones_title)

	_zone_list = VBoxContainer.new()
	_zone_list.add_theme_constant_override("separation", UITokens.SP_1)
	column.add_child(_zone_list)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, UITokens.SP_2)
	column.add_child(spacer)

	_legend_box = VBoxContainer.new()
	_legend_box.add_theme_constant_override("separation", UITokens.SP_1)
	column.add_child(_legend_box)
	for line_text: String in LEGEND_LINES:
		_legend_box.add_child(_make_label(tr(line_text), UITokens.STONE_5, UITokens.FONT_BODY))


func _build_map_panel() -> void:
	_map_panel = AshenPanel.new()
	_map_panel.variant = UIStyle.PanelVariant.INSET
	_map_panel.padding = UITokens.SP_1
	_add_at(_map_panel, MAP_RECT)

	var center := CenterContainer.new()
	_map_panel.add_child(center)

	_renderer = MapRenderer.new()
	_renderer.cell_size = MAP_CELL
	_renderer.show_labels = true
	center.add_child(_renderer)


func _build_detail_panel() -> void:
	_detail_panel = AshenPanel.new()
	_detail_panel.variant = UIStyle.PanelVariant.GLASS
	_detail_panel.padding = UITokens.SP_1
	_add_at(_detail_panel, DETAIL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_detail_panel.add_child(column)

	_detail_name = _make_label("", UITokens.GOLD_3, UITokens.FONT_BODY)
	_detail_state = _make_label("", UITokens.BONE, UITokens.FONT_BODY)
	_detail_gates = _make_label("", UITokens.BLOOD_5, UITokens.FONT_BODY)
	column.add_child(_detail_name)
	column.add_child(_detail_state)
	column.add_child(_detail_gates)


func _add_at(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	control.position = rect.position
	control.size = rect.size
	_root.add_child(control)


func _make_label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIStyle.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


# ------------------------------------------------------------------------------
# Масштаб UI (a11y §9.6 п.6)
# ------------------------------------------------------------------------------

func _on_ui_scale_changed(_scale: int) -> void:
	apply_ui_scale()


## На 150/200 % левая колонка зон расширяется под 12/16-px текст, карта и
## детали сдвигаются вправо; клетка карты пересчитывается, чтобы не выйти
## за панель. На 100 % геометрия возвращается к макету.
func apply_ui_scale() -> void:
	if _root == null:
		return
	UIScale.apply(self)

	# Заголовок «КАРТА МИРА» при 24 px упирается в панели: 20 px оставляет
	# зазор и сохраняет увеличение относительно 16 px.
	if _header != null:
		_header.add_theme_font_size_override(
			"font_size",
			mini(UIScale.font(UITokens.FONT_H2), 20)
		)
		_header.size.y = 22.0 if UIScale.factor() > 1.0 else HEADER_RECT.size.y

	var left_width: float = clampf(
		maxf(LEFT_RECT.size.x, UIScale.px(LEFT_RECT.size.x)),
		LEFT_RECT.size.x,
		250.0
	)
	_zone_panel.size.x = left_width

	var map_x: float = LEFT_RECT.position.x + left_width + 12.0
	var map_width: float = maxf(120.0, VIEW_WIDTH - LEFT_RECT.position.x - map_x)
	_map_panel.position.x = map_x
	_map_panel.size.x = map_width
	_detail_panel.position.x = map_x
	_detail_panel.size.x = map_width

	if _renderer != null:
		var columns: int = maxi(1, WorldMapModel.GRID_SIZE.x)
		var rows: int = maxi(1, WorldMapModel.GRID_SIZE.y)
		_renderer.cell_size = Vector2(
			maxf(1.0, floorf(map_width / float(columns))),
			maxf(1.0, floorf(MAP_RECT.size.y / float(rows)))
		)
		_renderer.queue_redraw()

	# Строки деталей в фиксированной панели: длинный текст переносится.
	for label: Label in [_detail_name, _detail_state, _detail_gates]:
		if label != null:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.vertical_alignment = VERTICAL_ALIGNMENT_TOP


# ------------------------------------------------------------------------------
# Сигналы мира
# ------------------------------------------------------------------------------

func _connect_event_bus() -> void:
	_connect_signal(EventBus.zone_loaded, _on_world_changed)
	_connect_signal(EventBus.ability_acquired, _on_world_changed_ability)
	_connect_signal(EventBus.checkpoint_activated, _on_world_changed_checkpoint)
	_connect_signal(EventBus.save_loaded, _on_world_changed_save)
	_connect_signal(EventBus.player_respawned, _on_world_changed_respawn)


func _disconnect_event_bus() -> void:
	_disconnect_signal(EventBus.zone_loaded, _on_world_changed)
	_disconnect_signal(EventBus.ability_acquired, _on_world_changed_ability)
	_disconnect_signal(EventBus.checkpoint_activated, _on_world_changed_checkpoint)
	_disconnect_signal(EventBus.save_loaded, _on_world_changed_save)
	_disconnect_signal(EventBus.player_respawned, _on_world_changed_respawn)


func _connect_signal(sig: Signal, callback: Callable) -> void:
	if not sig.is_connected(callback):
		sig.connect(callback)


func _disconnect_signal(sig: Signal, callback: Callable) -> void:
	if sig.is_connected(callback):
		sig.disconnect(callback)


func _on_world_changed(_zone_id: StringName, _display_name: String) -> void:
	_refresh_if_open()


func _on_world_changed_ability(_ability_id: StringName) -> void:
	_refresh_if_open()


func _on_world_changed_checkpoint(_zone_id: StringName, _bonfire_id: StringName) -> void:
	_refresh_if_open()


func _on_world_changed_save(_slot: int) -> void:
	_refresh_if_open()


func _on_world_changed_respawn(_zone_id: StringName, _position: Vector2) -> void:
	_refresh_if_open()


func _refresh_if_open() -> void:
	if visible:
		_refresh_data()
