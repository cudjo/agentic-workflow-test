extends GutTest
## T-14: зона 1 «Деревня-бастион» — загрузка через SceneRouter, палитра/раскладка,
## баннер при первом входе, входы/выходы, недостижимость секрет-уступа без
## способности и границы мира.

const ZONE_PATH := "res://world/zones/zone_01_village/zone_01_village.tscn"
const DATA_PATH := "res://data/zones/zone_01_village.tres"
const BALANCE_PATH := "res://data/balance/balancing.tres"

const FLOOR_TOP := 224.0
const LEDGE_TOP := 176.0
const PLAYER_HALF_HEIGHT := 10.0
const PLAYER_LAYER := 1 << 1
const WORLD_LAYER := 1


class TestBody extends CharacterBody2D:
	var gravity: float = 523.0
	var use_gravity: bool = true
	var constant_velocity: Vector2 = Vector2.ZERO

	func _physics_process(delta: float) -> void:
		if use_gravity:
			velocity.y += gravity * delta
		else:
			velocity = constant_velocity
		move_and_slide()


func _spawn_zone() -> ZoneScene:
	var zone := SceneRouter.instantiate_zone(ZONE_PATH)
	assert_not_null(zone, "SceneRouter must instantiate zone 1")
	if zone == null:
		return null
	add_child_autofree(zone)
	await wait_physics_frames(2)
	return zone


func _make_body(at: Vector2, use_gravity: bool = true) -> TestBody:
	var body := TestBody.new()
	body.position = at
	body.use_gravity = use_gravity
	body.collision_layer = PLAYER_LAYER
	body.collision_mask = WORLD_LAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 20)
	shape.shape = rect
	body.add_child(shape)
	add_child_autofree(body)
	return body


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


func test_zone_loads_through_scene_router() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	assert_true(zone is ZoneScene)
	assert_not_null(zone.zone_data)
	assert_eq(zone.zone_data.id, &"zone_01_village")
	assert_eq(zone.zone_data.display_name, "Деревня-бастион")
	assert_eq(zone.name, "zone_01_village", "root takes ZoneData.id")
	assert_true(zone.zone_data.validate().is_empty(), "ZoneData must be valid")
	assert_true(ResourceLoader.exists(DATA_PATH), "zone data .tres is committed")

	for layer_name in ["Ground", "Platforms", "Ladders", "Hazards"]:
		var layer := zone.get_node_or_null(layer_name) as TileMapLayer
		assert_not_null(layer, "%s layer exists" % layer_name)
		if layer != null:
			assert_eq(layer.tile_set, zone.zone_data.tileset, "%s uses zone tileset" % layer_name)

	var ambient := zone.get_node("Ambient") as CanvasModulate
	assert_not_null(ambient)
	assert_almost_eq(ambient.color.r, zone.zone_data.ambient_level, 0.001, "ambient_level applied")


func test_palette_matches_zone_1_design() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var palette := zone.zone_data.palette
	assert_not_null(palette)
	assert_true(palette.background.is_equal_approx(UITokens.NIGHT), "background = night")
	assert_true(palette.ground.is_equal_approx(UITokens.BROWN), "ground = wet brown earth")
	assert_true(palette.accent.is_equal_approx(UITokens.GOLD), "accent = torch gold")
	assert_true(palette.hazard.is_equal_approx(UITokens.BLOOD), "hazard = blood")

	var sky := zone.get_node("Background/Sky") as ColorRect
	assert_not_null(sky)
	assert_true(sky.color.is_equal_approx(palette.background))
	assert_true((zone.get_node("Ground") as TileMapLayer).modulate.is_equal_approx(palette.ground))
	assert_true((zone.get_node("Platforms") as TileMapLayer).modulate.is_equal_approx(palette.accent))

	assert_not_null(zone.get_node_or_null("Backdrop"), "stone bastion backdrop is present")
	assert_not_null(zone.get_node_or_null("Foreground"), "wet ground foreground is present")


func test_torches_follow_ninety_pixel_contract() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var lights := zone.get_node_or_null("Lights") as Node2D
	assert_not_null(lights)
	var torches := 0
	for child in lights.get_children():
		if child is PointLight2D and String(child.name).begins_with("Torch"):
			torches += 1
			var light := child as PointLight2D
			assert_not_null(light.texture, "torch uses a radial texture")
			if light.texture != null:
				var radius := float(light.texture.get_width()) * 0.5 * light.texture_scale
				assert_almost_eq(radius, 90.0, 1.0, "torch light radius is ~90 px")
			assert_false(light.shadow_enabled)
	assert_eq(torches, 2, "two torches flank the gate")


func test_hub_props_npc_markers_and_secret_chest() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return

	var bonfire := zone.get_node_or_null("Props/Bonfire") as Bonfire
	assert_not_null(bonfire, "bonfire checkpoint prop is placed")
	if bonfire != null:
		assert_eq(bonfire.position, Vector2(112.0, FLOOR_TOP), "bonfire stands on the floor")
		assert_true(bonfire.flame_color.is_equal_approx(zone.zone_data.palette.accent), "flame uses zone accent")

	var chest := zone.get_node_or_null("Props/Chest") as Chest
	assert_not_null(chest, "secret chest is placed")
	if chest != null:
		assert_eq(chest.position, Vector2(356.0, LEDGE_TOP), "chest sits on the high ledge")

	var rubble := zone.get_node_or_null("Props/Rubble") as Rubble
	assert_not_null(rubble, "rubble placeholder for the future ability gate")
	if rubble != null:
		assert_true(rubble.blocking, "rubble blocks the passage")
		assert_eq(rubble.get_meta("ability_gate"), &"double_jump", "T-09 will require double jump")
		assert_eq(rubble.get_meta("future_gate"), "T-09")

	var keeper := zone.get_node_or_null("NPCs/NPC_Keeper") as Marker2D
	var trader := zone.get_node_or_null("NPCs/Trader") as Marker2D
	assert_not_null(keeper, "NPC point exists")
	assert_not_null(trader, "trader point exists")
	if keeper != null:
		assert_eq(keeper.position.y, FLOOR_TOP - PLAYER_HALF_HEIGHT, "NPC stands on the floor")
	if trader != null:
		assert_eq(trader.position.y, FLOOR_TOP - PLAYER_HALF_HEIGHT, "trader stands on the floor")


func test_zone_banner_shows_on_first_entry() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var banner := zone.get_node_or_null("ZoneBanner") as ZoneBanner
	assert_not_null(banner, "banner CanvasLayer is part of the zone")
	if banner == null:
		return
	assert_true(banner.visible, "banner is shown on first entry")
	assert_not_null(banner.title_label)
	assert_eq(banner.title_label.text, "ДЕРЕВНЯ-БАСТИОН")
	assert_eq(banner.subtitle_label.text, "Зона 1 · Хаб")
	await wait_seconds(0.3)
	assert_true(banner.is_banner_visible(), "banner fades in")

	# Первый вход — единственный: повторный сигнал не перезапускает баннер.
	EventBus.zone_entered.emit(&"zone_01_village", "Другое имя")
	assert_eq(banner.title_label.text, "ДЕРЕВНЯ-БАСТИОН")
	banner.hide_now()
	EventBus.zone_entered.emit(&"zone_01_village", "Деревня-бастион")
	assert_false(banner.visible, "banner is not shown twice in one zone visit")


func test_entries_and_exits_are_data_driven() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var data := zone.zone_data
	assert_eq(data.entry_points.size(), 3)
	assert_eq(data.exits.size(), 2, "hub has two exits (SPEC §5)")

	var entries := zone.get_node("Entries") as Node2D
	assert_eq(entries.get_child_count(), data.entry_points.size())
	for entry: ZoneEntryPoint in data.entry_points:
		var marker := entries.get_node_or_null("Entry_%s" % entry.id) as Marker2D
		assert_not_null(marker)
		if marker != null:
			assert_eq(marker.position, entry.position)

	var exits := zone.get_node("Exits") as Node2D
	assert_eq(exits.get_child_count(), data.exits.size())
	var gate := exits.get_node_or_null("Exit_gate") as Area2D
	assert_not_null(gate, "normal gate exit exists")
	if gate != null:
		assert_eq(gate.get_meta("target_zone_id"), &"zone_02_swamp")
		assert_almost_eq(gate.position.y, FLOOR_TOP - PLAYER_HALF_HEIGHT, 0.1, "gate exit is on the floor")

	var ledge := exits.get_node_or_null("Exit_ledge") as Area2D
	assert_not_null(ledge, "ability-gated ledge exit exists")
	if ledge != null:
		assert_eq(ledge.get_meta("target_zone_id"), &"zone_03_mountains")
		assert_lt(ledge.position.y, LEDGE_TOP, "ledge exit sits above the secret ledge")


func test_secret_ledge_requires_double_jump() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var balance := load(BALANCE_PATH) as BalancingParams
	assert_not_null(balance)

	var platforms := zone.get_node("Platforms") as TileMapLayer
	assert_ne(platforms.get_cell_source_id(Vector2i(19, 11)), -1, "ledge starts at column 19")
	assert_ne(platforms.get_cell_source_id(Vector2i(25, 11)), -1, "ledge ends at column 25")
	assert_eq(platforms.get_used_cells().size(), 7, "ledge is a single 7-tile platform")

	var gap := FLOOR_TOP - LEDGE_TOP
	var single_jump := balance.h_jump
	var double_jump := balance.h_jump + balance.h_jump * balance.h_double_factor
	assert_gt(gap, single_jump, "single jump must not reach the secret ledge")
	assert_true(gap <= double_jump + 0.01, "double jump must reach the secret ledge")

	# Никаких промежуточных платформ ниже уступа — иначе секрет не был бы секретом.
	for cell in platforms.get_used_cells():
		assert_lte(cell.y, 11, "no lower platform can shortcut the ledge")

	# Область выхода на уступе не задевается одиночным прыжком.
	var ledge_exit := zone.zone_data.exits[1]
	var single_jump_top := FLOOR_TOP - balance.h_jump - PLAYER_HALF_HEIGHT * 2.0
	assert_lt(ledge_exit.position.y + ledge_exit.size.y * 0.5, single_jump_top,
		"single jump cannot touch the ledge exit area")


func test_double_jump_physics_lands_on_secret_ledge() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var balance := load(BALANCE_PATH) as BalancingParams
	assert_not_null(balance)

	var body := _make_body(Vector2(360.0, FLOOR_TOP - PLAYER_HALF_HEIGHT))
	await wait_physics_frames(3)
	assert_true(body.is_on_floor(), "test body starts on the hub floor")

	body.velocity.y = -balance.get_jump_velocity()
	await wait_physics_frames(21)
	body.velocity.y = -balance.get_double_jump_velocity()
	await wait_physics_frames(60)
	assert_almost_eq(body.position.y, LEDGE_TOP - PLAYER_HALF_HEIGHT, 2.0,
		"double jump lands on the secret ledge")
	assert_true(body.is_on_floor())


func test_single_jump_cannot_land_on_secret_ledge() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var balance := load(BALANCE_PATH) as BalancingParams
	assert_not_null(balance)

	var body := _make_body(Vector2(360.0, FLOOR_TOP - PLAYER_HALF_HEIGHT))
	await wait_physics_frames(3)
	body.velocity.y = -balance.get_jump_velocity()
	await wait_physics_frames(90)
	assert_almost_eq(body.position.y, FLOOR_TOP - PLAYER_HALF_HEIGHT, 2.0,
		"single jump falls back to the hub floor")
	assert_true(body.is_on_floor())


func test_player_cannot_leave_world_bounds() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var bounds := zone.get_node_or_null("WorldBounds") as StaticBody2D
	assert_not_null(bounds, "world bounds body exists")
	if bounds != null:
		assert_eq(bounds.collision_layer, WORLD_LAYER)

	var left := _make_body(Vector2(30.0, FLOOR_TOP - PLAYER_HALF_HEIGHT), false)
	left.constant_velocity = Vector2(-200.0, 0.0)
	await wait_physics_frames(60)
	assert_gt(left.position.x, 4.0, "left wall stops the player")

	var right := _make_body(Vector2(450.0, FLOOR_TOP - PLAYER_HALF_HEIGHT), false)
	right.constant_velocity = Vector2(200.0, 0.0)
	await wait_physics_frames(60)
	assert_lt(right.position.x, 476.0, "right wall stops the player")

	var faller := _make_body(Vector2(240.0, 180.0))
	await wait_physics_frames(120)
	assert_almost_eq(faller.position.y, FLOOR_TOP - PLAYER_HALF_HEIGHT, 2.0,
		"floor prevents falling out of the zone")
	assert_true(faller.is_on_floor())


func test_normal_gate_requests_transition() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	watch_signals(zone)
	_make_player_stub(Vector2(212.0, FLOOR_TOP - PLAYER_HALF_HEIGHT))
	await wait_physics_frames(4)
	assert_signal_emitted_with_parameters(
		zone,
		"exit_requested",
		[&"gate", &"zone_02_swamp", &"west_gate"]
	)
