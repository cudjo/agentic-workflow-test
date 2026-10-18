extends GutTest
## T-16: зоны 4 «Руины-храм» и 5 «Финал».
##
## Проверяем: загрузку через SceneRouter, палитры DESIGN §8.6, тёплый ambient
## и два источника света руин (жёлто-красный отсвет, гнетущая тишина),
## почти монохром финала с редкими blood-3, загадку-проход (3 рычага + дверь),
## пустую арену босса с точкой спавна для T-32, хук концовки с чтением фракции
## (FactionManager — заглушка T-27), связность графа зон 1–5 и бюджет кадра.
##
## Финальная последовательность/концовка — T-32: здесь проверяется только
## контракт арены и хука, сама концовка не реализуется.

const ZONE_01_DATA := "res://data/zones/zone_01_village.tres"
const ZONE_02_DATA := "res://data/zones/zone_02_swamp.tres"
const ZONE_03_DATA := "res://data/zones/zone_03_mountains.tres"
const ZONE_04_SCENE := "res://world/zones/zone_04_ruins/zone_04_ruins.tscn"
const ZONE_04_DATA := "res://data/zones/zone_04_ruins.tres"
const ZONE_05_SCENE := "res://world/zones/zone_05_finale/zone_05_finale.tscn"
const ZONE_05_DATA := "res://data/zones/zone_05_finale.tres"

const FLOOR_TOP := 224.0
const PLAYER_HALF_HEIGHT := 10.0
const PLAYER_LAYER := 1 << 1
const WORLD_LAYER := 1
const BOSS_SPAWN := Vector2(360.0, 224.0)


func _spawn(scene_path: String) -> ZoneScene:
	var zone := SceneRouter.instantiate_zone(scene_path)
	assert_not_null(zone, "SceneRouter must instantiate %s" % scene_path)
	if zone == null:
		return null
	add_child_autofree(zone)
	await wait_physics_frames(2)
	return zone


func _make_player_stub(at: Vector2) -> CharacterBody2D:
	var player := CharacterBody2D.new()
	player.position = at
	player.collision_layer = PLAYER_LAYER
	player.collision_mask = 0
	player.add_to_group("player")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 20)
	shape.shape = rect
	player.add_child(shape)
	add_child_autofree(player)
	return player


func _find_exit(data: ZoneData, exit_id: StringName) -> ZoneExit:
	for exit_def: ZoneExit in data.exits:
		if exit_def.id == exit_id:
			return exit_def
	return null


func _find_entry(data: ZoneData, entry_id: StringName) -> ZoneEntryPoint:
	for entry: ZoneEntryPoint in data.entry_points:
		if entry.id == entry_id:
			return entry
	return null


func _has_entry(data: ZoneData, entry_id: StringName) -> bool:
	return _find_entry(data, entry_id) != null


func _is_gray(color: Color) -> bool:
	var max_channel := maxf(color.r, maxf(color.g, color.b))
	var min_channel := minf(color.r, minf(color.g, color.b))
	return max_channel - min_channel <= 0.03


func _lights(zone: ZoneScene) -> Array[PointLight2D]:
	var result: Array[PointLight2D] = []
	for child: Node in zone.get_node("Lights").get_children():
		var light := child as PointLight2D
		if light != null:
			result.append(light)
	return result


# --- Загрузка и палитры ------------------------------------------------------

func test_both_zones_load_through_scene_router() -> void:
	var ruins := await _spawn(ZONE_04_SCENE)
	var finale := await _spawn(ZONE_05_SCENE)
	if ruins == null or finale == null:
		return

	assert_true(ruins is ZoneScene)
	assert_true(finale is ZoneScene)
	assert_eq(ruins.zone_data.id, &"zone_04_ruins")
	assert_eq(ruins.zone_data.display_name, "Руины-храм")
	assert_eq(finale.zone_data.id, &"zone_05_finale")
	assert_eq(finale.zone_data.display_name, "Финал")
	assert_eq(ruins.name, "zone_04_ruins", "root takes ZoneData.id")
	assert_eq(finale.name, "zone_05_finale")
	assert_true(ruins.zone_data.validate().is_empty(), "ruins ZoneData must be valid")
	assert_true(finale.zone_data.validate().is_empty(), "finale ZoneData must be valid")
	assert_true(ResourceLoader.exists(ZONE_04_DATA))
	assert_true(ResourceLoader.exists(ZONE_05_DATA))

	for zone: ZoneScene in [ruins, finale]:
		for layer_name in ["Ground", "Platforms", "Ladders", "Hazards"]:
			var layer := zone.get_node_or_null(layer_name) as TileMapLayer
			assert_not_null(layer, "%s/%s exists" % [zone.zone_data.id, layer_name])
			if layer != null:
				assert_eq(layer.tile_set, zone.zone_data.tileset, "%s uses zone tileset" % layer_name)


func test_palettes_match_design_8_6() -> void:
	var ruins := await _spawn(ZONE_04_SCENE)
	var finale := await _spawn(ZONE_05_SCENE)
	if ruins == null or finale == null:
		return

	var ruins_palette := ruins.zone_data.palette
	assert_not_null(ruins_palette)
	assert_true(ruins_palette.background.is_equal_approx(UITokens.BROWN_3), "ruins sky = brown-3")
	assert_true(ruins_palette.ground.is_equal_approx(UITokens.BROWN), "ruins stone = brown")
	assert_true(ruins_palette.accent.is_equal_approx(UITokens.GOLD), "ruins accent = gold")
	assert_true(ruins_palette.hazard.is_equal_approx(UITokens.BLOOD), "ruins hazard = blood")

	var finale_palette := finale.zone_data.palette
	assert_not_null(finale_palette)
	assert_true(finale_palette.background.is_equal_approx(UITokens.VOID), "finale sky = void")
	assert_true(finale_palette.ground.is_equal_approx(UITokens.STONE_9), "finale floor = stone-9")
	assert_true(finale_palette.accent.is_equal_approx(UITokens.STONE_5), "finale accent = stone-5")
	assert_true(finale_palette.hazard.is_equal_approx(UITokens.BLOOD_3), "finale rare accent = blood-3")

	# Финал почти монохромен: базовые цвета — серая шкала, blood-3 только акцент.
	assert_true(_is_gray(finale_palette.background), "finale background is gray")
	assert_true(_is_gray(finale_palette.ground), "finale ground is gray")
	assert_true(_is_gray(finale_palette.accent), "finale accent is gray")
	assert_false(_is_gray(finale_palette.hazard), "blood-3 is the rare chromatic accent")

	for zone: ZoneScene in [ruins, finale]:
		var palette := zone.zone_data.palette
		var sky := zone.get_node("Background/Sky") as ColorRect
		assert_not_null(sky)
		assert_true(sky.color.is_equal_approx(palette.background))
		assert_true((zone.get_node("Ground") as TileMapLayer).modulate.is_equal_approx(palette.ground))
		assert_true((zone.get_node("Platforms") as TileMapLayer).modulate.is_equal_approx(palette.accent))
		assert_true((zone.get_node("Hazards") as TileMapLayer).modulate.is_equal_approx(palette.hazard))

	assert_not_null(ruins.get_node_or_null("Backdrop"), "ruins backdrop exists")
	assert_not_null(ruins.get_node_or_null("Foreground"), "ruins dust/embers exist")
	assert_not_null(finale.get_node_or_null("Backdrop"), "finale backdrop exists")
	assert_not_null(finale.get_node_or_null("Foreground"), "finale ash exists")


# --- Освещение ---------------------------------------------------------------

func test_ruins_lighting_is_warm_and_sparse() -> void:
	var ruins := await _spawn(ZONE_04_SCENE)
	if ruins == null:
		return

	# DESIGN §8.7: руины у костра — до 0.26; тёплый сдвиг R > G > B.
	var ambient := ruins.get_node("Ambient") as CanvasModulate
	assert_not_null(ambient)
	assert_true(ambient.color.r > ambient.color.g, "ruins ambient is warm (R > G)")
	assert_true(ambient.color.g > ambient.color.b, "ruins ambient is warm (G > B)")
	assert_between(ambient.color.r, 0.26, 0.5, "ambient stays in the DESIGN §8.7 range")
	assert_lt(ambient.color.b, 0.26, "ruins ambient is dark enough near the bonfire")
	assert_almost_eq(ruins.zone_data.ambient_level, 0.26, 0.001)

	# Гнетущая тишина: ровно два источника — жёлтый костёр и красный алтарь.
	var lights := _lights(ruins)
	assert_eq(lights.size(), 2, "ruins keep exactly two light sources")
	var gold_seen := false
	var blood_seen := false
	for light: PointLight2D in lights:
		assert_gt(light.energy, 0.5, "ruins lights are visible")
		assert_not_null(light.texture)
		assert_gt(float(light.get_meta(&"radius_px", 0.0)), 30.0)
		if light.color.is_equal_approx(UITokens.GOLD_9):
			gold_seen = true
			assert_lt(light.position.x, 368.0, "bonfire glow stays in the temple hall")
		if light.color.is_equal_approx(UITokens.BLOOD_3):
			blood_seen = true
			assert_gt(light.position.x, 368.0, "red altar glow sits behind the sealed door")
	assert_true(gold_seen, "yellow-gold glow (gold-9) is present")
	assert_true(blood_seen, "red glow (blood-3) is present")

	# Костёр — внутри храма, на полу.
	var bonfire := ruins.get_node_or_null("Props/Bonfire") as Bonfire
	assert_not_null(bonfire)
	if bonfire != null:
		assert_almost_eq(bonfire.position.y, FLOOR_TOP, 0.1)
		assert_between(bonfire.position.x, 64.0, 352.0, "bonfire stands inside the temple hall")


func test_finale_is_monochrome_with_rare_blood_accents() -> void:
	var finale := await _spawn(ZONE_05_SCENE)
	if finale == null:
		return

	var ambient := finale.get_node("Ambient") as CanvasModulate
	assert_not_null(ambient)
	assert_true(_is_gray(ambient.color), "finale ambient is neutral gray")
	assert_almost_eq(ambient.color.r, finale.zone_data.ambient_level, 0.001)

	var lights := _lights(finale)
	assert_lte(lights.size(), 3, "finale does not turn into a light show")
	var blood_lights := 0
	for light: PointLight2D in lights:
		assert_true(_is_gray(light.color) or light.color.is_equal_approx(UITokens.BLOOD_3),
			"finale lights are gray or the rare blood-3 accent")
		if light.color.is_equal_approx(UITokens.BLOOD_3):
			blood_lights += 1
	assert_eq(blood_lights, 1, "exactly one blood-3 accent light")

	var foreground := finale.get_node_or_null("Foreground")
	assert_not_null(foreground)
	if foreground != null:
		assert_eq(int(foreground.call(&"get_spark_count")), 2, "only two blood sparks")


# --- Загадка-проход руин -----------------------------------------------------

func test_ruins_puzzle_opens_the_sealed_passage() -> void:
	var ruins := await _spawn(ZONE_04_SCENE)
	if ruins == null:
		return

	var puzzle := ruins.get_node_or_null("Puzzle")
	assert_not_null(puzzle, "ruins own the lever puzzle")
	if puzzle == null:
		return
	var gate := puzzle.get_node_or_null("Gate") as SealedGate
	var levers := puzzle.get_node_or_null("Levers")
	assert_not_null(gate, "sealed gate is part of the puzzle")
	assert_not_null(levers, "lever bank is part of the puzzle")
	if gate == null or levers == null:
		return

	assert_true(gate.blocking, "the passage starts sealed")
	assert_false(gate.get_node("CollisionShape2D").disabled, "the sealed door has a physical collider")
	assert_eq(int(puzzle.call(&"get_lever_count")), 3, "three levers form the puzzle")
	assert_false(bool(puzzle.call(&"is_solved")), "the puzzle is not solved on entry")

	# Решение: [вкл, выкл, вкл]; начальное состояние — все выключены.
	var lever_left := levers.get_node("Lever_left") as RuinLever
	var lever_middle := levers.get_node("Lever_middle") as RuinLever
	var lever_right := levers.get_node("Lever_right") as RuinLever
	assert_not_null(lever_left)
	assert_not_null(lever_middle)
	assert_not_null(lever_right)
	if lever_left == null or lever_middle == null or lever_right == null:
		return
	assert_true(lever_left.solution_state)
	assert_false(lever_middle.solution_state)
	assert_true(lever_right.solution_state)

	# Выход в финал — за дверью: загадка действительно «проход», а не декор.
	var to_finale := _find_exit(ruins.zone_data, &"to_finale")
	assert_not_null(to_finale)
	if to_finale != null:
		assert_gt(to_finale.position.x, gate.position.x + 32.0, "finale exit is behind the sealed door")

	var solved_before := int(puzzle.call(&"get_lever_count"))
	watch_signals(puzzle)
	lever_left.set_active(true)
	lever_middle.set_active(false)
	lever_right.set_active(true)
	await wait_physics_frames(2)

	assert_true(bool(puzzle.call(&"is_solved")), "all levers in their target states open the door")
	assert_signal_emitted(puzzle, "solved")
	assert_false(gate.blocking, "gate is open after the puzzle")
	assert_true(gate.get_node("CollisionShape2D").disabled, "gate collider is disabled after opening")
	assert_gte(solved_before, 3)

	# Повторный вход/тесты: сброс возвращает дверь и загадку.
	puzzle.call(&"reset_puzzle")
	await wait_physics_frames(2)
	assert_false(bool(puzzle.call(&"is_solved")))
	assert_true(gate.blocking, "reset seals the passage again")
	assert_false(gate.get_node("CollisionShape2D").disabled)


# --- Арена финального босса (T-32) ------------------------------------------

func test_finale_has_empty_boss_arena_and_spawn_point() -> void:
	var finale := await _spawn(ZONE_05_SCENE)
	if finale == null:
		return

	var arena := finale.get_node_or_null("Arena")
	assert_not_null(arena, "finale owns a boss arena")
	if arena == null:
		return
	var spawn := arena.get_node_or_null("BossSpawn") as Marker2D
	assert_not_null(spawn, "T-32 spawn marker exists")
	if spawn != null:
		assert_eq(spawn.position, BOSS_SPAWN, "boss spawns on the arena floor")
	assert_eq(arena.get_child_count(), 1, "arena is empty until T-32 (only the spawn marker)")

	var spawn_position: Vector2 = arena.call(&"get_boss_spawn_position")
	assert_eq(spawn_position, BOSS_SPAWN)
	var bounds: Rect2 = arena.call(&"get_arena_bounds")
	assert_eq(bounds.size, Vector2(432.0, 184.0))
	assert_almost_eq(bounds.position.x + bounds.size.x, 456.0, 0.1)
	assert_almost_eq(bounds.position.y + bounds.size.y, FLOOR_TOP, 0.1)
	assert_true(bool(arena.call(&"is_empty")), "no boss or barriers before T-32")
	assert_eq(get_tree().get_nodes_in_group(&"arena_barrier").size(), 0, "no arena barriers yet")

	# Декор финала — обломки монолитов, без коллизий (арена свободна для T-32).
	var props := finale.get_node_or_null("Props")
	assert_not_null(props, "finale has decorative props")
	if props != null:
		assert_eq(props.get_child_count(), 2, "two fallen monoliths")
		for child: Node in props.get_children():
			var rubble := child as Rubble
			assert_not_null(rubble, "finale prop is a rubble instance")
			if rubble != null:
				assert_false(rubble.blocking, "decor never blocks the arena")


# --- Хук концовки и фракция (T-27/T-32) -------------------------------------

func test_ending_exit_is_a_faction_aware_hook() -> void:
	var finale := await _spawn(ZONE_05_SCENE)
	if finale == null:
		return

	var hook := finale.get_node_or_null("EndingExit")
	assert_not_null(hook, "ending exit hook exists")
	if hook == null:
		return
	var marker := hook.get_node_or_null("ending_exit") as Marker2D
	assert_not_null(marker, "Marker2D 'ending_exit' is the exit point for T-32")
	assert_eq((hook as Area2D).collision_mask, PLAYER_LAYER, "hook listens to the player only")
	assert_true(EventBus != null)
	assert_true(hook.has_signal(&"ending_requested"))

	# FactionManager пока заглушка (T-27): хук не падает и отдаёт пустую фракцию.
	assert_eq(hook.get(&"gate_on_boss_id"), &"", "boss gating is wired later by T-32")
	assert_true(bool(hook.call(&"is_unlocked")))
	watch_signals(hook)
	var faction: StringName = hook.call(&"request_ending")
	assert_eq(faction, &"", "stub FactionManager yields no faction")
	assert_signal_emitted_with_parameters(
		hook,
		"ending_requested",
		[&"", &"zone_05_finale", &"ending"]
	)
	assert_eq(hook.call(&"request_ending"), &"", "one ending request per entry")
	assert_signal_emit_count(hook, "ending_requested", 1)

	# Вход игрока в Area2D тоже поднимает запрос (после сброса хука).
	hook.call(&"reset_hook")
	_make_player_stub((hook as Area2D).global_position)
	await wait_physics_frames(4)
	assert_signal_emit_count(hook, "ending_requested", 2)


# --- Связность графа мира ----------------------------------------------------

func test_zone_graph_connects_ruins_and_finale() -> void:
	var village := load(ZONE_01_DATA) as ZoneData
	var swamp := load(ZONE_02_DATA) as ZoneData
	var mountains := load(ZONE_03_DATA) as ZoneData
	var ruins := load(ZONE_04_DATA) as ZoneData
	var finale := load(ZONE_05_DATA) as ZoneData
	assert_not_null(village)
	assert_not_null(swamp)
	assert_not_null(mountains)
	assert_not_null(ruins)
	assert_not_null(finale)
	if village == null or swamp == null or mountains == null or ruins == null or finale == null:
		return

	var zones: Dictionary = {
		&"zone_01_village": village,
		&"zone_02_swamp": swamp,
		&"zone_03_mountains": mountains,
		&"zone_04_ruins": ruins,
		&"zone_05_finale": finale,
	}
	# Каждый выход ведёт в существующую зону и существующую точку входа.
	for data: ZoneData in zones.values():
		assert_true(data.validate().is_empty(), "%s ZoneData is valid" % data.id)
		for exit_def: ZoneExit in data.exits:
			var target: ZoneData = zones.get(exit_def.target_zone_id)
			assert_not_null(target, "exit '%s' of %s targets a known zone" % [exit_def.id, data.id])
			if target != null:
				assert_true(_has_entry(target, exit_def.target_entry_id),
					"exit '%s' of %s targets entry '%s'" % [exit_def.id, data.id, exit_def.target_entry_id])

	# Руины связаны с зонами 2 и 3 (и обе ведут обратно), финал — с руинами.
	var ruins_to_swamp := _find_exit(ruins, &"to_swamp")
	var ruins_to_mountains := _find_exit(ruins, &"to_mountains")
	var ruins_to_finale := _find_exit(ruins, &"to_finale")
	assert_not_null(ruins_to_swamp)
	assert_not_null(ruins_to_mountains)
	assert_not_null(ruins_to_finale)
	if ruins_to_swamp != null:
		assert_eq(ruins_to_swamp.target_zone_id, &"zone_02_swamp")
		assert_eq(ruins_to_swamp.target_entry_id, &"from_ruins")
	if ruins_to_mountains != null:
		assert_eq(ruins_to_mountains.target_zone_id, &"zone_03_mountains")
		assert_eq(ruins_to_mountains.target_entry_id, &"from_ruins")
	if ruins_to_finale != null:
		assert_eq(ruins_to_finale.target_zone_id, &"zone_05_finale")
		assert_eq(ruins_to_finale.target_entry_id, &"from_ruins")

	var swamp_to_ruins := _find_exit(swamp, &"to_ruins")
	var mountains_to_ruins := _find_exit(mountains, &"to_ruins")
	var finale_to_ruins := _find_exit(finale, &"to_ruins")
	assert_not_null(swamp_to_ruins, "ruins are reachable from the swamp")
	assert_not_null(mountains_to_ruins, "ruins are reachable from the mountains")
	assert_not_null(finale_to_ruins, "finale returns to the ruins")
	if swamp_to_ruins != null:
		assert_eq(swamp_to_ruins.target_zone_id, &"zone_04_ruins")
		assert_eq(swamp_to_ruins.target_entry_id, &"from_swamp")
	if mountains_to_ruins != null:
		assert_eq(mountains_to_ruins.target_zone_id, &"zone_04_ruins")
		assert_eq(mountains_to_ruins.target_entry_id, &"from_mountains")
	if finale_to_ruins != null:
		assert_eq(finale_to_ruins.target_zone_id, &"zone_04_ruins")
		assert_eq(finale_to_ruins.target_entry_id, &"from_finale")

	assert_true(_has_entry(ruins, &"from_swamp"))
	assert_true(_has_entry(ruins, &"from_mountains"))
	assert_true(_has_entry(ruins, &"from_finale"))
	assert_true(_has_entry(finale, &"from_ruins"))

	# Обход графа: из хаба достижимы и руины, и финал.
	var seen: Dictionary = {}
	var queue: Array[StringName] = [&"zone_01_village"]
	while not queue.is_empty():
		var current: StringName = queue.pop_back()
		if seen.has(current):
			continue
		seen[current] = true
		var data: ZoneData = zones.get(current)
		if data == null:
			continue
		for exit_def: ZoneExit in data.exits:
			if not seen.has(exit_def.target_zone_id):
				queue.append(exit_def.target_zone_id)
	assert_true(seen.has(&"zone_04_ruins"), "ruins are connected to the hub graph")
	assert_true(seen.has(&"zone_05_finale"), "finale is connected through the ruins")


# --- Входы/выходы, чекпоинт, физика -----------------------------------------

func test_entries_exits_bounds_and_bonfire() -> void:
	var ruins := await _spawn(ZONE_04_SCENE)
	var finale := await _spawn(ZONE_05_SCENE)
	if ruins == null or finale == null:
		return

	for zone: ZoneScene in [ruins, finale]:
		var data := zone.zone_data
		var entries := zone.get_node("Entries") as Node2D
		assert_eq(entries.get_child_count(), data.entry_points.size())
		for entry: ZoneEntryPoint in data.entry_points:
			var marker := entries.get_node_or_null("Entry_%s" % entry.id) as Marker2D
			assert_not_null(marker, "entry '%s' becomes a Marker2D" % entry.id)
			if marker != null:
				assert_eq(marker.position, entry.position)

		var exits := zone.get_node("Exits") as Node2D
		assert_eq(exits.get_child_count(), data.exits.size())
		for exit_def: ZoneExit in data.exits:
			var area := exits.get_node_or_null("Exit_%s" % exit_def.id) as Area2D
			assert_not_null(area)
			if area != null:
				assert_eq(area.collision_mask, PLAYER_LAYER, "exit listens to the player layer only")
				assert_eq(area.get_meta("target_entry_id"), exit_def.target_entry_id)

		var bounds := zone.get_node_or_null("WorldBounds") as StaticBody2D
		assert_not_null(bounds)
		if bounds != null:
			assert_eq(bounds.collision_layer, WORLD_LAYER)

	# В руинах есть костёр-чекпоинт; в финале — только арена (босс-чекпоинт T-32).
	var ruins_bonfire := ruins.get_node_or_null("Props/Bonfire") as Bonfire
	assert_not_null(ruins_bonfire, "ruins keep a bonfire checkpoint")
	if ruins_bonfire != null:
		assert_eq(ruins_bonfire.position, Vector2(288.0, FLOOR_TOP))
	assert_null(finale.get_node_or_null("Props/Bonfire"), "finale is an arena, not a camp")


func test_player_at_exit_requests_transition() -> void:
	var ruins := await _spawn(ZONE_04_SCENE)
	if ruins == null:
		return
	watch_signals(ruins)
	_make_player_stub(Vector2(12.0, FLOOR_TOP - PLAYER_HALF_HEIGHT))
	await wait_physics_frames(4)
	assert_signal_emitted_with_parameters(
		ruins,
		"exit_requested",
		[&"to_swamp", &"zone_02_swamp", &"from_ruins"]
	)


# --- Бюджет кадра ------------------------------------------------------------

func test_both_zones_hold_sixty_fps_headless() -> void:
	var ruins := await _spawn(ZONE_04_SCENE)
	var finale := await _spawn(ZONE_05_SCENE)
	if ruins == null or finale == null:
		return

	# Headless-замер (полноценный перф-пасс — T-37): обе зоны с углями,
	# пеплом и светом живут одновременно; 60 кадров — в пределах 1 с.
	var start := Time.get_ticks_msec()
	await wait_process_frames(60)
	var elapsed := Time.get_ticks_msec() - start
	assert_lt(elapsed, 1000, "60 frames under 1 s (>60 FPS headless), got %d ms" % elapsed)
