extends SceneTree
## T-14: генератор зоны 1 «Деревня-бастион» (хаб).
##
## Строит данные зоны (ZoneData .tres) и сцену (ZoneScene .tscn) на пайплайне T-13:
## тайлсет zone_terrain.tres, props bonfire/chest/door/rubble, точки входа/выхода
## из ZoneData. Арт — программные заглушки (backdrop/foreground) в палитре зоны 1.
##
## Запуск (из каталога game/):
##   godot --headless -s res://tests/tools/build_zone_01.gd
##   godot --headless --import
##
## Скрипт лежит под tests/ и не попадает в экспортную сборку (exclude_filter T-02).

const TILESET_PATH := "res://world/tilesets/zone_terrain.tres"
const ZONE_DATA_PATH := "res://data/zones/zone_01_village.tres"
const ZONE_SCENE_PATH := "res://world/zones/zone_01_village/zone_01_village.tscn"
const BANNER_SCENE_PATH := "res://world/zones/zone_banner.tscn"
const BACKDROP_SCRIPT := "res://world/zones/zone_01_village/zone_01_backdrop.gd"
const FOREGROUND_SCRIPT := "res://world/zones/zone_01_village/zone_01_foreground.gd"

const BONFIRE_SCENE := "res://world/props/bonfire.tscn"
const CHEST_SCENE := "res://world/props/chest.tscn"
const DOOR_SCENE := "res://world/props/door.tscn"
const ABILITY_GATE_SCENE := "res://world/props/ability_gate.tscn"

const FLOOR_TOP := 224.0
const FLOOR_ROW_TOP := 14
const FLOOR_ROW_BOTTOM := 15
const LEDGE_ROW := 11
const LEDGE_FIRST_COL := 19
const LEDGE_LAST_COL := 25
const LEVEL_COLS := 30

const WALL_LAYER := 1
const PLAYER_LAYER := 1 << 1

const LIGHT_TEXTURE_SIZE := 180
const TORCH_RADIUS := 90.0


func _init() -> void:
	var tileset := load(TILESET_PATH) as TileSet
	if tileset == null:
		push_error("T-14: не найден тайлсет %s" % TILESET_PATH)
		quit(1)
		return

	var zone_data := _build_zone_data(tileset)
	var data_error := ResourceSaver.save(zone_data, ZONE_DATA_PATH)
	if data_error != OK:
		push_error("T-14: не удалось сохранить ZoneData: %s" % error_string(data_error))
		quit(1)
		return

	var loaded_data := load(ZONE_DATA_PATH) as ZoneData
	if loaded_data == null:
		push_error("T-14: ZoneData не читается после сохранения")
		quit(1)
		return

	if not _build_zone_scene(tileset, loaded_data):
		quit(1)
		return

	print("T14_ZONE_OK ", ProjectSettings.globalize_path(ZONE_DATA_PATH), " ", ProjectSettings.globalize_path(ZONE_SCENE_PATH))
	quit()


# --- Данные зоны -------------------------------------------------------------

func _build_zone_data(tileset: TileSet) -> ZoneData:
	var palette := ZonePalette.new()
	palette.background = UITokens.NIGHT
	palette.ground = UITokens.BROWN
	palette.accent = UITokens.GOLD
	palette.hazard = UITokens.BLOOD

	var start := ZoneEntryPoint.new()
	start.id = &"start"
	start.position = Vector2(100.0, FLOOR_TOP - 10.0)

	var from_gate := ZoneEntryPoint.new()
	from_gate.id = &"from_gate"
	from_gate.position = Vector2(245.0, FLOOR_TOP - 10.0)

	var from_ledge := ZoneEntryPoint.new()
	from_ledge.id = &"from_ledge"
	from_ledge.position = Vector2(380.0, 166.0)

	var gate := ZoneExit.new()
	gate.id = &"gate"
	gate.position = Vector2(212.0, FLOOR_TOP - 10.0)
	gate.size = Vector2(32.0, 32.0)
	gate.target_zone_id = &"zone_02_swamp"
	gate.target_entry_id = &"west_gate"

	# Высокий уступ: единственный путь к нему — двойной прыжок (SPEC §5).
	var ledge := ZoneExit.new()
	ledge.id = &"ledge"
	ledge.position = Vector2(408.0, 160.0)
	ledge.size = Vector2(12.0, 20.0)
	ledge.target_zone_id = &"zone_03_mountains"
	ledge.target_entry_id = &"south_ledge"

	var entries: Array[ZoneEntryPoint] = [start, from_gate, from_ledge]
	var exits: Array[ZoneExit] = [gate, ledge]

	var data := ZoneData.new()
	data.id = &"zone_01_village"
	data.display_name = "Деревня-бастион"
	data.palette = palette
	data.ambient_level = 0.42
	data.tileset = tileset
	data.entry_points = entries
	data.exits = exits
	return data


# --- Сцена зоны --------------------------------------------------------------

func _build_zone_scene(tileset: TileSet, zone_data: ZoneData) -> bool:
	var root := Node2D.new()
	root.name = "Zone01Village"
	root.set_script(load("res://world/zones/zone_scene.gd"))
	root.set("zone_data", zone_data)

	var background_layer := CanvasLayer.new()
	background_layer.name = "Background"
	background_layer.layer = -10
	_add_owned(root, background_layer, root)

	var sky := ColorRect.new()
	sky.name = "Sky"
	sky.size = Vector2(480.0, 270.0)
	sky.color = zone_data.palette.background
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_owned(background_layer, sky, root)
	sky.unique_name_in_owner = true

	var ambient := CanvasModulate.new()
	ambient.name = "Ambient"
	ambient.color = Color(zone_data.ambient_level, zone_data.ambient_level, zone_data.ambient_level, 1.0)
	_add_owned(root, ambient, root)
	ambient.unique_name_in_owner = true

	var backdrop := Node2D.new()
	backdrop.name = "Backdrop"
	backdrop.set_script(load(BACKDROP_SCRIPT))
	_add_owned(root, backdrop, root)

	var ground := _make_layer(root, "Ground", tileset)
	_paint_floor(ground)

	var platforms := _make_layer(root, "Platforms", tileset)
	_paint_ledge(platforms)

	var ladders := _make_layer(root, "Ladders", tileset)
	ladders.name = "Ladders"
	var hazards := _make_layer(root, "Hazards", tileset)
	hazards.name = "Hazards"

	var foreground := Node2D.new()
	foreground.name = "Foreground"
	foreground.set_script(load(FOREGROUND_SCRIPT))

	var lights := Node2D.new()
	lights.name = "Lights"
	_add_owned(root, lights, root)
	var light_texture := _make_light_texture()
	_add_light(lights, root, "TorchWest", Vector2(171.0, 164.0), light_texture, 1.0, UITokens.GOLD_3, 1.4)
	_add_light(lights, root, "TorchEast", Vector2(257.0, 164.0), light_texture, 1.0, UITokens.GOLD_3, 1.4)
	_add_light(lights, root, "HutWindow", Vector2(66.0, 174.0), light_texture, 46.0 / TORCH_RADIUS, UITokens.GOLD, 0.6)
	_add_light(lights, root, "Bonfire", Vector2(112.0, 216.0), light_texture, 46.0 / TORCH_RADIUS, UITokens.GOLD, 0.7)
	_add_light(lights, root, "Moon", Vector2(250.0, 46.0), light_texture, 130.0 / TORCH_RADIUS, UITokens.STEEL_3, 0.15)

	var props := Node2D.new()
	props.name = "Props"
	_add_owned(root, props, root)
	_add_prop(props, root, BONFIRE_SCENE, "Bonfire", Vector2(112.0, FLOOR_TOP))
	_add_prop(props, root, CHEST_SCENE, "Chest", Vector2(356.0, 176.0))
	_add_prop(props, root, DOOR_SCENE, "Door", Vector2(408.0, 176.0))
	var rubble := _add_prop(props, root, ABILITY_GATE_SCENE, "Rubble", Vector2(448.0, FLOOR_TOP))
	rubble.scale = Vector2(1.5, 2.5)
	rubble.set(&"gate_id", &"village_ledge")
	rubble.set_meta(&"ability_gate", &"double_jump")
	rubble.set_meta(&"future_gate", "T-09")

	_add_owned(root, foreground, root)

	var npcs := Node2D.new()
	npcs.name = "NPCs"
	_add_owned(root, npcs, root)
	_add_marker(npcs, root, "NPC_Keeper", Vector2(150.0, FLOOR_TOP - 10.0), &"npc")
	_add_marker(npcs, root, "Trader", Vector2(292.0, FLOOR_TOP - 10.0), &"trader")

	var entries := Node2D.new()
	entries.name = "Entries"
	_add_owned(root, entries, root)
	entries.unique_name_in_owner = true

	var exits := Node2D.new()
	exits.name = "Exits"
	_add_owned(root, exits, root)
	exits.unique_name_in_owner = true

	_add_world_bounds(root)

	var banner := (load(BANNER_SCENE_PATH) as PackedScene).instantiate()
	banner.name = "ZoneBanner"
	banner.set("zone_id", &"zone_01_village")
	banner.set("subtitle", "Зона 1 · Хаб")
	_add_owned(root, banner, root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		push_error("T-14: не удалось упаковать сцену зоны: %s" % error_string(pack_error))
		root.free()
		return false
	var save_error := ResourceSaver.save(packed, ZONE_SCENE_PATH)
	root.free()
	if save_error != OK:
		push_error("T-14: не удалось сохранить сцену зоны: %s" % error_string(save_error))
		return false
	return true


func _make_layer(root: Node, layer_name: String, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	_add_owned(root, layer, root)
	layer.unique_name_in_owner = true
	return layer


func _paint_floor(ground: TileMapLayer) -> void:
	var mask := TerrainTiles.Side.LEFT | TerrainTiles.Side.RIGHT
	for y in range(FLOOR_ROW_TOP, FLOOR_ROW_BOTTOM + 1):
		for x in range(LEVEL_COLS):
			ground.set_cell(
				Vector2i(x, y),
				TerrainTiles.SOURCE_ID,
				TerrainTiles.ground_atlas(0, mask)
			)


func _paint_ledge(platforms: TileMapLayer) -> void:
	for x in range(LEDGE_FIRST_COL, LEDGE_LAST_COL + 1):
		var part := TerrainTiles.PlatformPart.MIDDLE
		if x == LEDGE_FIRST_COL:
			part = TerrainTiles.PlatformPart.LEFT_END
		elif x == LEDGE_LAST_COL:
			part = TerrainTiles.PlatformPart.RIGHT_END
		platforms.set_cell(
			Vector2i(x, LEDGE_ROW),
			TerrainTiles.SOURCE_ID,
			TerrainTiles.platform_atlas(0, part)
		)


func _make_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.width = LIGHT_TEXTURE_SIZE
	texture.height = LIGHT_TEXTURE_SIZE
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _add_light(
	parent: Node,
	owner_node: Node,
	light_name: String,
	at: Vector2,
	texture: Texture2D,
	radius_scale: float,
	color: Color,
	energy: float
) -> void:
	var light := PointLight2D.new()
	light.name = light_name
	light.position = at
	light.texture = texture
	light.texture_scale = radius_scale
	light.color = color
	light.energy = energy
	light.shadow_enabled = false
	_add_owned(parent, light, owner_node)
	light.set_meta(&"radius_px", TORCH_RADIUS * radius_scale)


func _add_prop(
	parent: Node,
	owner_node: Node,
	scene_path: String,
	prop_name: String,
	at: Vector2
) -> Node2D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("T-14: не найден prop %s" % scene_path)
		return null
	var prop := packed.instantiate() as Node2D
	prop.name = prop_name
	prop.position = at
	_add_owned(parent, prop, owner_node)
	return prop


func _add_marker(parent: Node, owner_node: Node, marker_name: String, at: Vector2, role: StringName) -> void:
	var marker := Marker2D.new()
	marker.name = marker_name
	marker.position = at
	marker.set_meta(&"role", role)
	_add_owned(parent, marker, owner_node)


func _add_world_bounds(root: Node) -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "WorldBounds"
	bounds.collision_layer = WALL_LAYER
	bounds.collision_mask = 0
	_add_owned(root, bounds, root)
	_add_bound_shape(bounds, root, "Left", Vector2(2.0, 135.0), Vector2(4.0, 270.0))
	_add_bound_shape(bounds, root, "Right", Vector2(478.0, 135.0), Vector2(4.0, 270.0))
	_add_bound_shape(bounds, root, "Floor", Vector2(240.0, 267.0), Vector2(480.0, 6.0))
	_add_bound_shape(bounds, root, "Ceiling", Vector2(240.0, 1.0), Vector2(480.0, 2.0))


func _add_bound_shape(parent: Node, owner_node: Node, shape_name: String, at: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.name = shape_name
	collision.position = at
	collision.shape = shape
	_add_owned(parent, collision, owner_node)


func _add_owned(parent: Node, child: Node, owner_node: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
