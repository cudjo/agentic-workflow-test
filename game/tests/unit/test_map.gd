extends GutTest
## T-33: полная карта мира и миникарта (AC-04.2).
##
## Проверяем:
##   * данные комнат/костров/проходов берутся из ZoneData (.tres);
##   * невидимая зона не раскрывается, но проход к ней виден маркером
##     (один уровень скрытой информации);
##   * закрытый проход показывает требуемую способность и её состояние;
##   * текущая зона/позиция игрока/костры читаемы в модели;
##   * миникарта HUD и полная карта строят одинаковый снимок;
##   * карта открывается/закрывается и навигируется без мыши;
##   * посещённые зоны трекаются через zone_loaded/mark_zone_visited.

const HUD_SCENE := preload("res://ui/hud/HUD.tscn")
const MAP_SCENE := preload("res://ui/map/WorldMap.tscn")
const ZONE_01 := &"zone_01_village"
const ZONE_02 := &"zone_02_swamp"
const ZONE_03 := &"zone_03_mountains"
const ZONE_04 := &"zone_04_ruins"
const ZONE_05 := &"zone_05_finale"
const ALL_ZONES: Array[StringName] = [ZONE_01, ZONE_02, ZONE_03, ZONE_04, ZONE_05]
## Порядок карты: сверху вниз, слева направо (координаты комнат).
const MAP_ORDER: Array[StringName] = [ZONE_04, ZONE_05, ZONE_01, ZONE_02, ZONE_03]

var model: WorldMapModel
var _saved_visited: Array[StringName] = []
var _saved_zone: StringName = &""
var _saved_entry: StringName = &""
var _saved_abilities: Array[StringName] = []


func before_each() -> void:
	model = WorldMapModel.new()
	model.reload()

	_saved_visited = SceneRouter.get_visited_zone_ids()
	_saved_zone = GameState.current_zone_id
	_saved_entry = SceneRouter.current_entry_id
	_saved_abilities = GameState.get_abilities()
	SceneRouter.reset_visited_zones()
	GameState.current_zone_id = &""
	SceneRouter.current_entry_id = &""
	GameState.clear_abilities()


func after_each() -> void:
	SceneRouter.restore_visited_zones(_saved_visited)
	GameState.current_zone_id = _saved_zone
	SceneRouter.current_entry_id = _saved_entry
	GameState.clear_abilities()
	for ability_id: StringName in _saved_abilities:
		GameState.add_ability(ability_id)


# ------------------------------------------------------------------------------
# Данные ZoneData (T-33)
# ------------------------------------------------------------------------------

func test_model_discovers_five_zones_and_excludes_template() -> void:
	assert_eq(model.zones.size(), 5, "5 зон из data/zones, шаблон исключён")
	assert_eq(model.get_zone_ids(), MAP_ORDER, "стабильный порядок зон (география карты)")
	assert_eq(model.get_zone(&"zone_template"), null, "zone_template — не комната карты")


func test_every_zone_has_map_room_bonfires_and_valid_data() -> void:
	var cells: Dictionary = {}
	for zone_id: StringName in ALL_ZONES:
		var data: ZoneData = model.get_zone(zone_id)
		assert_not_null(data, "ZoneData %s" % zone_id)
		assert_false(data.map_rooms.is_empty(), "%s: map_rooms заданы" % zone_id)
		var room: ZoneRoom = data.map_rooms[0]
		assert_not_null(room)
		assert_false(cells.has(room.grid_position), "%s: клетка карты уникальна" % zone_id)
		cells[room.grid_position] = true
		assert_true(
			room.grid_position.x >= 0
			and room.grid_position.y >= 0
			and room.grid_position.x < WorldMapModel.GRID_SIZE.x
			and room.grid_position.y < WorldMapModel.GRID_SIZE.y,
			"%s: клетка внутри 12x9" % zone_id
		)
		assert_true(room.world_rect.has_point(data.entry_points[0].position), "%s: вход в комнате" % zone_id)
		for exit_def: ZoneExit in data.exits:
			assert_true(
				room.world_rect.has_point(exit_def.position),
				"%s/%s: выход в комнате" % [zone_id, exit_def.id]
			)
		for bonfire_position: Vector2 in data.map_bonfires:
			assert_true(
				room.world_rect.has_point(bonfire_position),
				"%s: костёр в комнате" % zone_id
			)
		var issues: PackedStringArray = data.validate()
		assert_eq(issues, PackedStringArray(), "%s: ZoneData валиден (%s)" % [zone_id, str(issues)])


func test_ability_gates_are_data_not_hardcoded() -> void:
	var village: ZoneData = model.get_zone(ZONE_01)
	var ledge: ZoneExit = _find_exit(village, &"ledge")
	assert_not_null(ledge, "village/ledge существует")
	assert_eq(ledge.required_ability, &"double_jump", "уступ требует двойной прыжок")

	var swamp: ZoneData = model.get_zone(ZONE_02)
	var to_ruins: ZoneExit = _find_exit(swamp, &"to_ruins")
	assert_not_null(to_ruins)
	assert_eq(to_ruins.required_ability, &"dash", "болото→руины требует рывок")

	var mountains: ZoneData = model.get_zone(ZONE_03)
	var mountain_ruins: ZoneExit = _find_exit(mountains, &"to_ruins")
	assert_not_null(mountain_ruins)
	assert_eq(mountain_ruins.required_ability, &"wall_climb", "горы→руины требуют карабканье")


# ------------------------------------------------------------------------------
# Видимость: только посещённые зоны (AC-04.2)
# ------------------------------------------------------------------------------

func test_unvisited_zone_is_hidden_but_its_pass_is_marked() -> void:
	var snapshot: Dictionary = model.build([ZONE_01], ZONE_01, Vector2(100, 214), [])
	var rooms: Array = snapshot["rooms"]
	assert_eq(rooms.size(), 1, "видна только посещённая зона")
	assert_eq(rooms[0]["zone_id"], ZONE_01)

	var gates: Array = snapshot["gates"]
	var ledge_gate: Dictionary = _find_gate(gates, ZONE_01, &"ledge")
	assert_false(ledge_gate.is_empty(), "проход к непосещённой зоне виден")
	assert_eq(ledge_gate["required_ability"], &"double_jump", "маркер несёт способность")
	assert_true(ledge_gate["locked"], "способность не получена — замок")
	assert_false(ledge_gate["target_visited"], "цель не посещена")
	assert_eq(ledge_gate["to_zone_id"], &"", "имя непосещённой зоны не раскрывается")

	for room: Dictionary in rooms:
		assert_ne(room["zone_id"], ZONE_03, "зона 3 не раскрыта")


func test_current_zone_is_always_visible_and_player_cell_is_set() -> void:
	var snapshot: Dictionary = model.build([], ZONE_02, Vector2(80, 214), [])
	var rooms: Array = snapshot["rooms"]
	assert_eq(rooms.size(), 1, "текущая зона видима без трекера")
	assert_eq(rooms[0]["zone_id"], ZONE_02)
	assert_true(rooms[0]["current"], "текущая комната помечена")
	assert_eq(snapshot["player_room"], Vector2i(4, 6), "клетка игрока совпадает с комнатой")
	var player: Dictionary = snapshot["player"]
	assert_true(player["valid"], "позиция игрока внутри комнаты")
	var local: Vector2 = player["local"]
	assert_almost_eq(local.x, 80.0 / 480.0, 0.01)


func test_bonfires_come_from_zone_data() -> void:
	var snapshot: Dictionary = model.build([ZONE_01, ZONE_02], ZONE_01, Vector2(112, 224), [])
	var bonfires: Array = snapshot["bonfires"]
	assert_eq(bonfires.size(), 2, "по костру в деревне и болоте")
	var by_zone: Dictionary = {}
	for bonfire: Dictionary in bonfires:
		by_zone[bonfire["zone_id"]] = bonfire
	assert_true(by_zone.has(ZONE_01))
	assert_eq(by_zone[ZONE_01]["cell"], Vector2i(1, 6))
	assert_false(by_zone.has(ZONE_05), "в финале костра нет")


# ------------------------------------------------------------------------------
# Проходы и связи
# ------------------------------------------------------------------------------

func test_links_only_between_visited_zones_and_are_deduplicated() -> void:
	var snapshot: Dictionary = model.build(
		[ZONE_01, ZONE_02, ZONE_03],
		ZONE_02,
		Vector2(80, 214),
		[]
	)
	var links: Array = snapshot["links"]
	assert_eq(links.size(), 3, "деревня↔болото, болото↔горы, деревня↔горы")
	for link: Dictionary in links:
		assert_true(
			ALL_ZONES.has(link["from_zone"]) and ALL_ZONES.has(link["to_zone"]),
			"связь между известными зонами"
		)
		assert_false(link["to_zone"] == ZONE_04, "руины не раскрыты связью")
	var village_mountains: Dictionary = _find_link(links, ZONE_01, ZONE_03)
	assert_false(village_mountains.is_empty(), "связь деревня↔горы существует")
	assert_true(village_mountains["locked"], "уступ закрыт без двойного прыжка")


func test_acquiring_ability_opens_locked_pass() -> void:
	var locked: Dictionary = model.build([ZONE_01, ZONE_03], ZONE_01, Vector2(100, 214), [])
	var locked_gate: Dictionary = _find_gate(locked["gates"], ZONE_01, &"ledge")
	assert_true(locked_gate["locked"])
	assert_false(locked_gate["owned"])

	var opened: Dictionary = model.build(
		[ZONE_01, ZONE_03],
		ZONE_01,
		Vector2(100, 214),
		[&"double_jump"]
	)
	var opened_gate: Dictionary = _find_gate(opened["gates"], ZONE_01, &"ledge")
	assert_true(opened_gate.is_empty(), "открытый проход не показывается замком")
	var opened_link: Dictionary = _find_link(opened["links"], ZONE_01, ZONE_03)
	assert_false(opened_link["locked"], "связь открыта после получения способности")


func test_swamp_and_mountains_ruins_passes_carry_their_abilities() -> void:
	var snapshot: Dictionary = model.build(
		[ZONE_02, ZONE_03],
		ZONE_02,
		Vector2(80, 214),
		[]
	)
	var to_ruins_dash: Dictionary = _find_gate(snapshot["gates"], ZONE_02, &"to_ruins")
	assert_eq(to_ruins_dash["required_ability"], &"dash")
	assert_true(to_ruins_dash["locked"])
	var to_ruins_climb: Dictionary = _find_gate(snapshot["gates"], ZONE_03, &"to_ruins")
	assert_eq(to_ruins_climb["required_ability"], &"wall_climb")
	assert_true(to_ruins_climb["locked"])


# ------------------------------------------------------------------------------
# Миникарта HUD ↔ полная карта
# ------------------------------------------------------------------------------

func test_minimap_geometry_is_96x54_with_8x6_rooms() -> void:
	var hud: AshenHUD = HUD_SCENE.instantiate() as AshenHUD
	add_child_autofree(hud)
	await wait_process_frames(1)

	var minimap := hud.get_minimap() as AshenMinimap
	assert_not_null(minimap, "HUD использует AshenMinimap (T-33)")
	assert_eq(minimap.custom_minimum_size, UITokens.MINIMAP_SIZE)
	assert_eq(UITokens.MINIMAP_SIZE, Vector2(96, 54))
	assert_eq(minimap.get_renderer().cell_size, Vector2(8, 6))
	assert_eq(
		Vector2i(WorldMapModel.GRID_SIZE.x * 8, WorldMapModel.GRID_SIZE.y * 6),
		Vector2i(96, 54),
		"сетка 12x9 комнат 8x6"
	)


func test_minimap_matches_full_map_snapshot() -> void:
	SceneRouter.restore_visited_zones([ZONE_01, ZONE_02])
	GameState.current_zone_id = ZONE_02

	var hud: AshenHUD = HUD_SCENE.instantiate() as AshenHUD
	add_child_autofree(hud)
	await wait_process_frames(1)
	hud.set_minimap_data({})
	hud.sync_from_game_state()

	var world_map: WorldMap = MAP_SCENE.instantiate() as WorldMap
	world_map.pause_on_open = false
	add_child_autofree(world_map)
	await wait_process_frames(1)
	assert_true(world_map.open())
	await wait_process_frames(1)

	var minimap_data: Dictionary = hud.get_minimap_data()
	var full_data: Dictionary = world_map.get_map_data()
	assert_false(minimap_data.is_empty(), "HUD получил реальный снимок карты")
	assert_eq(
		_room_signature(minimap_data),
		_room_signature(full_data),
		"комнаты миникарты совпадают с полной картой"
	)
	assert_eq(
		_link_signature(minimap_data),
		_link_signature(full_data),
		"связи совпадают"
	)
	assert_eq(
		_gate_signature(minimap_data),
		_gate_signature(full_data),
		"маркеры проходов совпадают"
	)
	assert_eq(
		minimap_data["player_room"],
		full_data["player_room"],
		"метка игрока совпадает"
	)


func test_hud_minimap_api_from_t19_is_preserved() -> void:
	var hud: AshenHUD = HUD_SCENE.instantiate() as AshenHUD
	add_child_autofree(hud)
	await wait_process_frames(1)

	hud.set_minimap_data({"player_room": Vector2i(3, 2)})
	var minimap := hud.get_minimap() as AshenMinimap
	assert_eq(minimap.player_room, Vector2i(3, 2))
	assert_eq(hud.get_minimap_data()["player_room"], Vector2i(3, 2))
	hud.set_minimap_data({})
	assert_true(hud.get_minimap_data().is_empty(), "пустые данные не роняют HUD")


# ------------------------------------------------------------------------------
# Открытие/закрытие/навигация без мыши
# ------------------------------------------------------------------------------

func test_map_opens_and_closes_with_map_and_cancel_actions() -> void:
	assert_true(InputMap.has_action(&"map"), "действие map зарегистрировано")
	assert_false(InputMap.action_get_events(&"map").is_empty(), "map имеет клавишу/геймпад")

	SceneRouter.restore_visited_zones([ZONE_01, ZONE_02])
	GameState.current_zone_id = ZONE_02
	var world_map: WorldMap = MAP_SCENE.instantiate() as WorldMap
	world_map.pause_on_open = false
	add_child_autofree(world_map)
	await wait_process_frames(1)
	assert_false(world_map.is_open())

	world_map._input(_action_event(&"map"))
	assert_true(world_map.is_open(), "M/геймпад открывает карту")
	world_map._input(_action_event(&"map"))
	assert_false(world_map.is_open(), "повторное map закрывает карту")

	world_map._input(_action_event(&"map"))
	assert_true(world_map.is_open())
	world_map._input(_action_event(&"ui_cancel"))
	assert_false(world_map.is_open(), "ui_cancel закрывает карту")


func test_map_navigation_without_mouse_changes_selection_and_focus() -> void:
	SceneRouter.restore_visited_zones([ZONE_01, ZONE_02, ZONE_03])
	GameState.current_zone_id = ZONE_02
	var world_map: WorldMap = MAP_SCENE.instantiate() as WorldMap
	world_map.pause_on_open = false
	add_child_autofree(world_map)
	await wait_process_frames(1)
	world_map.open()
	await wait_process_frames(1)

	assert_eq(world_map.get_zone_buttons().size(), 3, "три посещённые зоны")
	assert_eq(world_map.get_selected_zone_id(), ZONE_02, "фокус на текущей зоне")
	assert_true(world_map.get_zone_buttons()[1].has_focus(), "фокус виден на строке")

	world_map._input(_action_event(&"ui_down"))
	assert_eq(world_map.get_selected_zone_id(), ZONE_03, "вниз — следующая зона")
	assert_true(world_map.get_zone_buttons()[2].has_focus(), "фокус переехал")

	world_map._input(_action_event(&"ui_up"))
	assert_eq(world_map.get_selected_zone_id(), ZONE_02, "вверх — предыдущая зона")

	world_map.select_zone(ZONE_01)
	assert_eq(world_map.get_selected_zone_id(), ZONE_01)


func test_locked_pass_state_is_not_only_color() -> void:
	SceneRouter.restore_visited_zones([ZONE_01, ZONE_03])
	GameState.current_zone_id = ZONE_01
	var world_map: WorldMap = MAP_SCENE.instantiate() as WorldMap
	world_map.pause_on_open = false
	add_child_autofree(world_map)
	await wait_process_frames(1)
	world_map.open()
	await wait_process_frames(1)
	world_map.select_zone(ZONE_01)

	var details: Dictionary = world_map.get_detail_texts()
	assert_string_contains(details["gates"], "ЗАКРЫТО", "подпись закрытого прохода")
	assert_string_contains(details["gates"], "ДВОЙНОЙ ПРЫЖОК", "название способности текстом")
	assert_true(world_map.get_legend_lines().has("ЗАМОК = СПОСОБН."), "легенда объясняет замок")

	var specs: Array[Dictionary] = world_map.get_renderer().get_marker_specs()
	var locked_found: bool = false
	for spec: Dictionary in specs:
		if spec["kind"] == "locked_gate" and spec["required_ability"] == &"double_jump":
			locked_found = true
	assert_true(locked_found, "маркер закрытого прохода с иконкой способности")

	GameState.add_ability(&"double_jump")
	world_map._refresh_if_open()
	await wait_process_frames(1)
	details = world_map.get_detail_texts()
	assert_false(
		String(details["gates"]).contains("ЗАКРЫТО"),
		"после получения способности проход больше не закрыт"
	)


# ------------------------------------------------------------------------------
# Трекинг посещённых зон
# ------------------------------------------------------------------------------

func test_visited_zones_are_tracked_from_zone_loaded() -> void:
	SceneRouter.reset_visited_zones()
	EventBus.zone_loaded.emit(ZONE_03, "Горный перевал")
	assert_true(SceneRouter.is_zone_visited(ZONE_03), "zone_loaded отмечает зону")
	EventBus.zone_loaded.emit(ZONE_03, "Горный перевал")
	assert_eq(SceneRouter.get_visited_zone_ids().size(), 1, "повторный вход не дублирует")
	assert_true(SceneRouter.mark_zone_visited(ZONE_04), "mark_zone_visited добавляет новую")
	assert_false(SceneRouter.mark_zone_visited(ZONE_04), "идемпотентно")
	assert_eq(SceneRouter.get_visited_zone_ids().size(), 2)


func test_restore_visited_zones_skips_empty_values() -> void:
	SceneRouter.restore_visited_zones([ZONE_01, "", ZONE_05, ZONE_01])
	assert_eq(SceneRouter.get_visited_zone_ids().size(), 2)
	assert_true(SceneRouter.is_zone_visited(ZONE_01))
	assert_true(SceneRouter.is_zone_visited(ZONE_05))


# ------------------------------------------------------------------------------
# Помощники
# ------------------------------------------------------------------------------

func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _find_exit(data: ZoneData, exit_id: StringName) -> ZoneExit:
	for exit_def: ZoneExit in data.exits:
		if exit_def != null and exit_def.id == exit_id:
			return exit_def
	return null


func _find_gate(gates: Array, zone_id: StringName, exit_id: StringName) -> Dictionary:
	for gate: Dictionary in gates:
		if gate["zone_id"] == zone_id and String(gate["exit_id"]) == String(exit_id):
			return gate
	return {}


func _find_link(links: Array, a: StringName, b: StringName) -> Dictionary:
	for link: Dictionary in links:
		var from_zone: StringName = StringName(str(link["from_zone"]))
		var to_zone: StringName = StringName(str(link["to_zone"]))
		if (from_zone == a and to_zone == b) or (from_zone == b and to_zone == a):
			return link
	return {}


func _room_signature(snapshot: Dictionary) -> String:
	var rooms: Array = snapshot.get("rooms", [])
	var parts := PackedStringArray()
	for room: Dictionary in rooms:
		parts.append("%s:%s:%s:%s" % [
			room.get("zone_id", ""),
			room.get("cell", Vector2i(-1, -1)),
			room.get("current", false),
			room.get("index", 0),
		])
	return "|".join(parts)


func _link_signature(snapshot: Dictionary) -> String:
	var links: Array = snapshot.get("links", [])
	var parts := PackedStringArray()
	for link: Dictionary in links:
		parts.append("%s>%s:%s:%s" % [
			link.get("from_zone", ""),
			link.get("to_zone", ""),
			link.get("required_ability", ""),
			link.get("locked", false),
		])
	return "|".join(parts)


func _gate_signature(snapshot: Dictionary) -> String:
	var gates: Array = snapshot.get("gates", [])
	var parts := PackedStringArray()
	for gate: Dictionary in gates:
		parts.append("%s/%s:%s:%s:%s" % [
			gate.get("zone_id", ""),
			gate.get("exit_id", ""),
			gate.get("required_ability", ""),
			gate.get("locked", false),
			gate.get("target_visited", false),
		])
	return "|".join(parts)
