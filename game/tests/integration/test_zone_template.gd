extends GutTest
## T-13: шаблон зоны загружается SceneRouter'ом и применяет все поля ZoneData.

const ZONE_SCENE_PATH := "res://world/zones/zone_template.tscn"


func _instantiate_zone() -> ZoneScene:
	var zone := SceneRouter.instantiate_zone(ZONE_SCENE_PATH)
	assert_not_null(zone, "SceneRouter must instantiate the zone template")
	if zone == null:
		return null
	add_child_autofree(zone)
	return zone


func test_scene_router_loads_zone_template() -> void:
	var zone := SceneRouter.instantiate_zone(ZONE_SCENE_PATH)
	assert_not_null(zone)
	assert_true(zone is ZoneScene)
	assert_not_null(zone.zone_data)
	assert_eq(zone.zone_data.id, &"zone_template")
	zone.free()


func test_zone_scene_applies_palette_ambient_and_tileset() -> void:
	var zone := _instantiate_zone()
	if zone == null:
		return
	await wait_physics_frames(1)
	var data := zone.zone_data

	assert_eq(zone.name, String(data.id), "root takes ZoneData.id")

	var sky := zone.get_node("Background/Sky") as ColorRect
	assert_not_null(sky)
	assert_true(sky.color.is_equal_approx(data.palette.background), "background uses palette")

	var ambient := zone.get_node("Ambient") as CanvasModulate
	assert_not_null(ambient)
	var level := data.ambient_level
	assert_true(ambient.color.is_equal_approx(Color(level, level, level, 1.0)), "CanvasModulate uses ambient_level")

	for layer_name in ["Ground", "Platforms", "Ladders", "Hazards"]:
		var layer := zone.get_node(layer_name) as TileMapLayer
		assert_not_null(layer)
		assert_eq(layer.tile_set, data.tileset, "%s uses ZoneData.tileset" % layer_name)

	assert_true((zone.get_node("Ground") as TileMapLayer).modulate.is_equal_approx(data.palette.ground))
	assert_true((zone.get_node("Platforms") as TileMapLayer).modulate.is_equal_approx(data.palette.accent))
	assert_true((zone.get_node("Ladders") as TileMapLayer).modulate.is_equal_approx(data.palette.accent))
	assert_true((zone.get_node("Hazards") as TileMapLayer).modulate.is_equal_approx(data.palette.hazard))

	var bonfire := zone.get_node("Props/Bonfire") as Bonfire
	assert_not_null(bonfire, "bonfire prop is part of the template")
	assert_true(bonfire.flame_color.is_equal_approx(data.palette.accent), "bonfire flame uses palette accent")


func test_zone_scene_spawns_entries_and_exits_from_data() -> void:
	var zone := _instantiate_zone()
	if zone == null:
		return
	await wait_physics_frames(1)
	var data := zone.zone_data

	var entries := zone.get_node("Entries") as Node2D
	assert_eq(entries.get_child_count(), data.entry_points.size())
	for entry: ZoneEntryPoint in data.entry_points:
		var marker := entries.get_node_or_null("Entry_%s" % entry.id) as Marker2D
		assert_not_null(marker, "entry '%s' must become a Marker2D" % entry.id)
		assert_eq(marker.position, entry.position)

	var exits := zone.get_node("Exits") as Node2D
	assert_eq(exits.get_child_count(), data.exits.size())
	for exit_def: ZoneExit in data.exits:
		var area := exits.get_node_or_null("Exit_%s" % exit_def.id) as Area2D
		assert_not_null(area, "exit '%s' must become an Area2D" % exit_def.id)
		assert_eq(area.position, exit_def.position)
		assert_eq(area.collision_mask, 1 << 1, "exit triggers only the player layer")
		assert_eq(area.get_meta("exit_id"), exit_def.id)
		assert_eq(area.get_meta("target_zone_id"), exit_def.target_zone_id)
		assert_eq(area.get_meta("target_entry_id"), exit_def.target_entry_id)


func test_zone_entered_signal_reports_id_and_name() -> void:
	watch_signals(EventBus)
	var zone := _instantiate_zone()
	if zone == null:
		return
	await wait_physics_frames(1)
	assert_signal_emitted_with_parameters(
		EventBus,
		"zone_entered",
		[zone.zone_data.id, zone.zone_data.display_name]
	)


func test_player_entering_exit_emits_exit_requested() -> void:
	var zone := _instantiate_zone()
	if zone == null:
		return
	await wait_physics_frames(1)
	watch_signals(zone)

	var exit_def: ZoneExit = zone.zone_data.exits[0]
	var player := CharacterBody2D.new()
	player.name = "PlayerStub"
	player.add_to_group("player")
	player.collision_layer = 1 << 1
	player.collision_mask = 0
	player.position = exit_def.position
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 20)
	shape.shape = rect
	player.add_child(shape)
	add_child_autofree(player)

	await wait_physics_frames(4)
	assert_signal_emitted(zone, "exit_requested", "player overlap must request a zone transition")
