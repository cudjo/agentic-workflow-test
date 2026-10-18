extends GutTest
## T-15: зоны 2 «Болото» и 3 «Горный перевал».
##
## Проверяем: загрузку через SceneRouter, палитры DESIGN §8.6, связность
## входов/выходов с зоной 1 (T-14), туман/параллакс, hazard-воду, вертикальные
## шахты, ability-gate заглушки (dash/wall climb, SPEC §4.1) и бюджет кадра.
##
## Родные зоны способностей: dash — зона 2, wall climb — зона 2 (SPEC §4.1).
## Поэтому в зоне 3 обязаны быть препятствия и под dash, и под wall climb.

const ZONE_02_SCENE := "res://world/zones/zone_02_swamp/zone_02_swamp.tscn"
const ZONE_02_DATA := "res://data/zones/zone_02_swamp.tres"
const ZONE_03_SCENE := "res://world/zones/zone_03_mountains/zone_03_mountains.tscn"
const ZONE_03_DATA := "res://data/zones/zone_03_mountains.tres"
const ZONE_01_DATA := "res://data/zones/zone_01_village.tres"

const FLOOR_TOP := 224.0
const PLAYER_HALF_HEIGHT := 10.0
const PLAYER_LAYER := 1 << 1
const WORLD_LAYER := 1


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


func _has_entry(data: ZoneData, entry_id: StringName) -> bool:
	for entry: ZoneEntryPoint in data.entry_points:
		if entry.id == entry_id:
			return true
	return false


# --- Загрузка и палитры ------------------------------------------------------

func test_both_zones_load_through_scene_router() -> void:
	var swamp := await _spawn(ZONE_02_SCENE)
	var mountains := await _spawn(ZONE_03_SCENE)
	if swamp == null or mountains == null:
		return

	assert_true(swamp is ZoneScene)
	assert_true(mountains is ZoneScene, "mountains root may subclass ZoneScene but must stay compatible")
	assert_eq(swamp.zone_data.id, &"zone_02_swamp")
	assert_eq(swamp.zone_data.display_name, "Болото")
	assert_eq(mountains.zone_data.id, &"zone_03_mountains")
	assert_eq(mountains.zone_data.display_name, "Горный перевал")
	assert_eq(swamp.name, "zone_02_swamp", "root takes ZoneData.id")
	assert_eq(mountains.name, "zone_03_mountains")
	assert_true(swamp.zone_data.validate().is_empty(), "swamp ZoneData must be valid")
	assert_true(mountains.zone_data.validate().is_empty(), "mountains ZoneData must be valid")
	assert_true(ResourceLoader.exists(ZONE_02_DATA))
	assert_true(ResourceLoader.exists(ZONE_03_DATA))

	for zone: ZoneScene in [swamp, mountains]:
		for layer_name in ["Ground", "Platforms", "Ladders", "Hazards"]:
			var layer := zone.get_node_or_null(layer_name) as TileMapLayer
			assert_not_null(layer, "%s/%s exists" % [zone.zone_data.id, layer_name])
			if layer != null:
				assert_eq(layer.tile_set, zone.zone_data.tileset, "%s uses zone tileset" % layer_name)


func test_palettes_match_design_8_6() -> void:
	var swamp := await _spawn(ZONE_02_SCENE)
	var mountains := await _spawn(ZONE_03_SCENE)
	if swamp == null or mountains == null:
		return

	var swamp_palette := swamp.zone_data.palette
	assert_not_null(swamp_palette)
	assert_true(swamp_palette.background.is_equal_approx(UITokens.GREEN_9), "swamp sky = green-9")
	assert_true(swamp_palette.ground.is_equal_approx(UITokens.BROWN), "swamp earth = brown")
	assert_true(swamp_palette.accent.is_equal_approx(UITokens.GOLD_9), "swamp accent = dull gold-9")
	assert_true(swamp_palette.hazard.is_equal_approx(UITokens.STEEL_9), "swamp water = steel-9")

	var mountain_palette := mountains.zone_data.palette
	assert_not_null(mountain_palette)
	assert_true(mountain_palette.background.is_equal_approx(UITokens.NIGHT_9), "mountains sky = night-9")
	assert_true(mountain_palette.ground.is_equal_approx(UITokens.STEEL), "mountains rock = steel")
	assert_true(mountain_palette.accent.is_equal_approx(UITokens.STEEL_3), "mountains accent = cold steel-3")
	assert_true(mountain_palette.hazard.is_equal_approx(UITokens.STONE_5), "mountains hazard = stone-5")

	for zone: ZoneScene in [swamp, mountains]:
		var palette := zone.zone_data.palette
		var sky := zone.get_node("Background/Sky") as ColorRect
		assert_not_null(sky)
		assert_true(sky.color.is_equal_approx(palette.background))
		assert_true((zone.get_node("Ground") as TileMapLayer).modulate.is_equal_approx(palette.ground))
		assert_true((zone.get_node("Platforms") as TileMapLayer).modulate.is_equal_approx(palette.accent))
		assert_true((zone.get_node("Hazards") as TileMapLayer).modulate.is_equal_approx(palette.hazard))
		var ambient := zone.get_node("Ambient") as CanvasModulate
		assert_almost_eq(ambient.color.r, zone.zone_data.ambient_level, 0.001)

	# Костёр — тёплая точка: в болоте тусклое gold-9, в горах — gold-3 (пламя
	# не перекрашивается в холодный accent, см. zone_03_scene.gd).
	var swamp_bonfire := swamp.get_node("Props/Bonfire") as Bonfire
	var mountain_bonfire := mountains.get_node("Props/Bonfire") as Bonfire
	assert_not_null(swamp_bonfire)
	assert_not_null(mountain_bonfire)
	assert_true(swamp_bonfire.flame_color.is_equal_approx(UITokens.GOLD_9))
	assert_true(mountain_bonfire.flame_color.is_equal_approx(UITokens.GOLD_3))

	assert_not_null(swamp.get_node_or_null("Backdrop"), "swamp backdrop exists")
	assert_not_null(swamp.get_node_or_null("Foreground"), "swamp foreground exists")
	assert_not_null(mountains.get_node_or_null("Parallax"), "mountains parallax exists")
	assert_not_null(mountains.get_node_or_null("Foreground"), "mountain snowfall exists")


# --- Связность зон -----------------------------------------------------------

func test_zone_links_are_consistent_with_zone_01() -> void:
	var village := load(ZONE_01_DATA) as ZoneData
	var swamp := load(ZONE_02_DATA) as ZoneData
	var mountains := load(ZONE_03_DATA) as ZoneData
	assert_not_null(village)
	assert_not_null(swamp)
	assert_not_null(mountains)
	if village == null or swamp == null or mountains == null:
		return

	var zones := {
		&"zone_01_village": village,
		&"zone_02_swamp": swamp,
		&"zone_03_mountains": mountains,
	}
	# Каждый выход ведёт в существующую зону и существующую точку входа.
	for data: ZoneData in [village, swamp, mountains]:
		for exit_def: ZoneExit in data.exits:
			var target: ZoneData = zones.get(exit_def.target_zone_id)
			assert_not_null(target, "exit '%s' of %s targets a known zone" % [exit_def.id, data.id])
			if target != null:
				assert_true(_has_entry(target, exit_def.target_entry_id),
					"exit '%s' of %s targets entry '%s'" % [exit_def.id, data.id, exit_def.target_entry_id])

	# Связи из T-14: village.gate → swamp/west_gate, village.ledge → mountains/south_ledge.
	var village_gate := _find_exit(village, &"gate")
	var village_ledge := _find_exit(village, &"ledge")
	assert_not_null(village_gate)
	assert_not_null(village_ledge)
	if village_gate != null:
		assert_eq(village_gate.target_zone_id, &"zone_02_swamp")
		assert_eq(village_gate.target_entry_id, &"west_gate")
	if village_ledge != null:
		assert_eq(village_ledge.target_zone_id, &"zone_03_mountains")
		assert_eq(village_ledge.target_entry_id, &"south_ledge")

	# Обратные пути: болото возвращает в from_gate, горы — на from_ledge.
	var swamp_west := _find_exit(swamp, &"west_gate")
	var mountain_south := _find_exit(mountains, &"south_ledge")
	assert_not_null(swamp_west)
	assert_not_null(mountain_south)
	if swamp_west != null:
		assert_eq(swamp_west.target_zone_id, &"zone_01_village")
		assert_eq(swamp_west.target_entry_id, &"from_gate")
	if mountain_south != null:
		assert_eq(mountain_south.target_zone_id, &"zone_01_village")
		assert_eq(mountain_south.target_entry_id, &"from_ledge")

	# Болото ↔ горы: второй маршрут, согласован в обе стороны.
	var swamp_east := _find_exit(swamp, &"east_gate")
	var mountain_north := _find_exit(mountains, &"north_pass")
	assert_not_null(swamp_east)
	assert_not_null(mountain_north)
	if swamp_east != null:
		assert_eq(swamp_east.target_zone_id, &"zone_03_mountains")
		assert_eq(swamp_east.target_entry_id, &"north_pass")
	if mountain_north != null:
		assert_eq(mountain_north.target_zone_id, &"zone_02_swamp")
		assert_eq(mountain_north.target_entry_id, &"east_gate")

	assert_true(_has_entry(swamp, &"west_gate"))
	assert_true(_has_entry(swamp, &"east_gate"))
	assert_true(_has_entry(mountains, &"south_ledge"))
	assert_true(_has_entry(mountains, &"north_pass"))


# --- Болото: туман и hazard-вода --------------------------------------------

func test_swamp_fog_reduces_visibility_and_drifts() -> void:
	var swamp := await _spawn(ZONE_02_SCENE)
	if swamp == null:
		return

	var fog := swamp.get_node_or_null("Fog") as CanvasLayer
	assert_not_null(fog, "swamp owns a fog CanvasLayer")
	if fog == null:
		return
	assert_eq(fog.layer, 4, "fog sits above the world and below HUD (10)")
	for child in fog.get_children():
		var band := child as ColorRect
		if band != null:
			assert_eq(band.mouse_filter, Control.MOUSE_FILTER_IGNORE, "fog never blocks input")

	var band_count: int = fog.call(&"get_band_count")
	assert_gte(band_count, 5, "fog has several translucent bands")
	var veil_seen := false
	var band_seen := 0
	for child in fog.get_children():
		if child is TextureRect:
			var band := child as TextureRect
			assert_not_null(band.texture, "fog band uses a soft gradient texture")
			assert_gt(band.modulate.a, 0.05, "fog band is translucent but visible")
			band_seen += 1
		elif child is ColorRect:
			var veil := child as ColorRect
			assert_gt(veil.color.a, 0.03, "fog veil is translucent but visible")
			if veil.name.begins_with("Veil"):
				veil_seen = true
	assert_eq(band_seen, band_count, "all fog bands are drawn as soft clouds")
	assert_true(veil_seen, "fog has full-screen veils for low visibility")

	var before: float = fog.call(&"get_band_x", 0)
	await wait_seconds(0.3)
	var after: float = fog.call(&"get_band_x", 0)
	assert_gt(absf(after - before), 0.1, "fog bands drift over time")

	var hazards := swamp.get_node("Hazards") as TileMapLayer
	assert_gt(hazards.get_used_cells().size(), 0, "hazard water tiles are painted")
	assert_true(hazards.modulate.is_equal_approx(swamp.zone_data.palette.hazard))
	var water_on_floor := 0
	for cell in hazards.get_used_cells():
		if cell.y == 13:
			water_on_floor += 1
	assert_gt(water_on_floor, 0, "water pools sit on the swamp floor")


# --- Горы: параллакс и вертикальные шахты ------------------------------------

func test_mountains_parallax_follows_camera_and_wind_animates() -> void:
	var mountains := await _spawn(ZONE_03_SCENE)
	if mountains == null:
		return

	var parallax := mountains.get_node_or_null("Parallax") as ZoneParallax
	assert_not_null(parallax, "mountains own a parallax node")
	if parallax == null:
		return
	assert_eq(parallax.scroll_factors.size(), 3, "three ridge layers")
	assert_gt(parallax.scroll_factors[2], parallax.scroll_factors[0], "near layer moves faster than far")

	var wind_before := parallax.get_wind_time()
	await wait_seconds(0.2)
	assert_gt(parallax.get_wind_time(), wind_before, "wind animation advances")

	var camera := Camera2D.new()
	mountains.add_child(camera)
	camera.position = Vector2.ZERO
	camera.make_current()
	await wait_process_frames(2)
	var offset_before := parallax.layer_offset(2).x
	camera.position.x = 100.0
	await wait_process_frames(2)
	var offset_after := parallax.layer_offset(2).x
	assert_almost_eq(offset_after - offset_before, 100.0 * parallax.scroll_factors[2], 2.0,
		"near ridge shifts by scroll factor when the camera moves")

	var foreground := mountains.get_node_or_null("Foreground")
	assert_not_null(foreground)
	if foreground != null:
		assert_gt(int(foreground.call(&"get_flake_count")), 0, "snowfall is alive")


func test_mountains_have_vertical_shafts_for_wall_climb() -> void:
	var mountains := await _spawn(ZONE_03_SCENE)
	if mountains == null:
		return
	var ground := mountains.get_node("Ground") as TileMapLayer

	# Центральная шахта: стены 11 и 14, свободный проход 12–13 до верхней полки.
	assert_ne(ground.get_cell_source_id(Vector2i(11, 6)), -1, "left shaft wall exists")
	assert_ne(ground.get_cell_source_id(Vector2i(14, 6)), -1, "right shaft wall exists")
	assert_eq(ground.get_cell_source_id(Vector2i(12, 6)), -1, "shaft interior is open")
	assert_eq(ground.get_cell_source_id(Vector2i(13, 6)), -1, "shaft interior is open")
	assert_ne(ground.get_cell_source_id(Vector2i(12, 3)), -1, "shaft leads to a top ledge")

	# Вторая вертикаль (камин) — для читаемости «шахт» во множественном числе.
	assert_ne(ground.get_cell_source_id(Vector2i(20, 8)), -1, "second chimney wall exists")
	assert_ne(ground.get_cell_source_id(Vector2i(24, 8)), -1, "second chimney wall exists")
	assert_eq(ground.get_cell_source_id(Vector2i(22, 8)), -1, "second chimney is open")

	var chest := mountains.get_node_or_null("Props/Chest") as Chest
	assert_not_null(chest, "secret chest rewards the climb")
	if chest != null:
		assert_almost_eq(chest.position.y, 48.0, 0.1, "chest sits on the shaft top ledge")


# --- Ability gates (SPEC §4.1) ----------------------------------------------

func test_ability_gates_cover_foreign_zone_usage() -> void:
	var swamp := await _spawn(ZONE_02_SCENE)
	var mountains := await _spawn(ZONE_03_SCENE)
	if swamp == null or mountains == null:
		return

	var swamp_dash := swamp.get_node_or_null("Props/DashGate") as Rubble
	assert_not_null(swamp_dash, "swamp has a dash gate placeholder")
	if swamp_dash != null:
		assert_true(swamp_dash.blocking, "dash gate physically blocks the ledge")
		assert_eq(swamp_dash.get_meta("ability_gate"), &"dash")
		assert_eq(swamp_dash.get_meta("future_gate"), "T-09")

	# Зона 3 — «чужая» и для dash (родная зона 2), и для wall climb (родная зона 2).
	var wall_gate := mountains.get_node_or_null("Props/WallClimbGate") as Rubble
	var mountain_dash := mountains.get_node_or_null("Props/DashGate") as Rubble
	assert_not_null(wall_gate, "mountains gate the shaft with wall_climb")
	assert_not_null(mountain_dash, "mountains also gate a ledge with dash")
	if wall_gate != null:
		assert_true(wall_gate.blocking)
		assert_eq(wall_gate.get_meta("ability_gate"), &"wall_climb")
		assert_eq(wall_gate.get_meta("future_gate"), "T-09")
	if mountain_dash != null:
		assert_true(mountain_dash.blocking)
		assert_eq(mountain_dash.get_meta("ability_gate"), &"dash")
		assert_eq(mountain_dash.get_meta("future_gate"), "T-09")

	var gates := 0
	for zone: ZoneScene in [swamp, mountains]:
		for prop in zone.get_node("Props").get_children():
			if prop.has_meta(&"ability_gate"):
				gates += 1
	assert_gte(gates, 3, "at least one native and both foreign-zone ability usages exist")


# --- Входы, выходы, чекпоинты и переходы ------------------------------------

func test_entries_exits_bonfires_and_world_bounds() -> void:
	var swamp := await _spawn(ZONE_02_SCENE)
	var mountains := await _spawn(ZONE_03_SCENE)
	if swamp == null or mountains == null:
		return

	for zone: ZoneScene in [swamp, mountains]:
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

		var bonfire := zone.get_node_or_null("Props/Bonfire") as Bonfire
		assert_not_null(bonfire, "checkpoint bonfire is placed")
		if bonfire != null:
			assert_almost_eq(bonfire.position.y, FLOOR_TOP, 0.1, "bonfire stands on the floor")

		var bounds := zone.get_node_or_null("WorldBounds") as StaticBody2D
		assert_not_null(bounds)
		if bounds != null:
			assert_eq(bounds.collision_layer, WORLD_LAYER)

	var swamp_west := swamp.get_node("Exits/Exit_west_gate") as Area2D
	assert_not_null(swamp_west)
	if swamp_west != null:
		assert_eq(swamp_west.get_meta("target_zone_id"), &"zone_01_village")
		assert_eq(swamp_west.get_meta("target_entry_id"), &"from_gate")

	var mountain_north := mountains.get_node("Exits/Exit_north_pass") as Area2D
	assert_not_null(mountain_north)
	if mountain_north != null:
		assert_eq(mountain_north.get_meta("target_zone_id"), &"zone_02_swamp")
		assert_eq(mountain_north.get_meta("target_entry_id"), &"east_gate")


func test_player_at_exit_requests_transition() -> void:
	var swamp := await _spawn(ZONE_02_SCENE)
	if swamp == null:
		return
	watch_signals(swamp)
	_make_player_stub(Vector2(12.0, FLOOR_TOP - PLAYER_HALF_HEIGHT))
	await wait_physics_frames(4)
	assert_signal_emitted_with_parameters(
		swamp,
		"exit_requested",
		[&"west_gate", &"zone_01_village", &"from_gate"]
	)


# --- Бюджет кадра ------------------------------------------------------------

func test_both_zones_hold_sixty_fps_headless() -> void:
	var swamp := await _spawn(ZONE_02_SCENE)
	var mountains := await _spawn(ZONE_03_SCENE)
	if swamp == null or mountains == null:
		return

	# Headless-замер (полноценный перф-пасс — T-37): обе зоны с туманом,
	# снегом и параллаксом живут одновременно; 60 кадров должны уложиться в 1 с.
	var start := Time.get_ticks_msec()
	await wait_process_frames(60)
	var elapsed := Time.get_ticks_msec() - start
	assert_lt(elapsed, 1000, "60 frames under 1 s (>60 FPS headless), got %d ms" % elapsed)
