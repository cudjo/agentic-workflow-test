extends SceneTree
## T-13: генератор placeholder-пайплайна уровней.
##
## Арт отсутствует, поэтому тайлы — программные grayscale-заглушки, а цвет зоны
## задаётся ZonePalette через modulate. Контракт (16×16, source id, atlas-координаты,
## физические слои, Terrain Sets) сохраняется при замене арта.
##
## Запуск (из каталога game/):
##   1) godot --headless -s res://tests/tools/build_level_pipeline.gd -- --atlas
##   2) godot --headless --import
##   3) godot --headless -s res://tests/tools/build_level_pipeline.gd
##
## Шаг 1 создаёт PNG-атлас, шаг 3 — TileSet, ZoneData (.tres) и шаблон сцены зоны.
## Скрипт лежит под tests/ и не попадает в экспортную сборку (exclude_filter T-02).

const ATLAS_PATH := "res://assets/tiles/tileset_placeholder.png"
const TILESET_PATH := "res://world/tilesets/zone_terrain.tres"
const ZONE_DATA_PATH := "res://data/zones/zone_template.tres"
const ZONE_SCENE_PATH := "res://world/zones/zone_template.tscn"

const PHYSICS_SOLID := 0
const PHYSICS_ONE_WAY := 1
const PHYSICS_LADDER := 2
const PHYSICS_HAZARD := 3

const COLLISION_BIT_WORLD := 1
const COLLISION_BIT_INTERACTABLE := 1 << 7
const COLLISION_BIT_HAZARD := 1 << 8

const TERRAIN_GROUND := 0
const TERRAIN_PLATFORMS := 1

const FLOOR_ROW := 15
const LEVEL_LEFT := 0
const LEVEL_RIGHT := 29


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--atlas"):
		_generate_atlas()
		print("T13_ATLAS_OK ", ProjectSettings.globalize_path(ATLAS_PATH))
		quit()
		return

	var built_tileset := _build_tileset()
	if built_tileset == null:
		quit(1)
		return
	ResourceSaver.save(built_tileset, TILESET_PATH)

	# Перечитываем с диска, чтобы ZoneData/сцена ссылались на .tres (ExtResource),
	# а не встраивали TileSet в каждый ресурс.
	var tileset := load(TILESET_PATH) as TileSet
	var zone_data := _build_zone_data(tileset)
	ResourceSaver.save(zone_data, ZONE_DATA_PATH)

	var loaded_zone_data := load(ZONE_DATA_PATH) as ZoneData
	_build_zone_scene(tileset, loaded_zone_data)
	print("T13_PIPELINE_OK ", ProjectSettings.globalize_path(TILESET_PATH), " ", ProjectSettings.globalize_path(ZONE_SCENE_PATH))
	quit()


# --- Атлас-заглушка ---------------------------------------------------------

func _generate_atlas() -> void:
	var img := Image.create(
		TerrainTiles.ATLAS_COLUMNS * TerrainTiles.TILE_SIZE.x,
		TerrainTiles.ATLAS_ROWS * TerrainTiles.TILE_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	for zone in TerrainTiles.ZONE_COUNT:
		for mask in 16:
			_draw_ground_tile(img, TerrainTiles.ground_atlas(zone, mask), mask)
		for part in TerrainTiles.PlatformPart.values():
			_draw_platform_tile(img, TerrainTiles.platform_atlas(zone, part), part)
		_draw_ladder_tile(img, TerrainTiles.ladder_atlas(zone))
		_draw_hazard_tile(img, TerrainTiles.hazard_atlas(zone))

	img.save_png(ATLAS_PATH)


func _tile_rect(atlas_coords: Vector2i) -> Rect2i:
	return Rect2i(atlas_coords * TerrainTiles.TILE_SIZE, TerrainTiles.TILE_SIZE)


func _put(img: Image, rect: Rect2i, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= TerrainTiles.TILE_SIZE.x or y >= TerrainTiles.TILE_SIZE.y:
		return
	img.set_pixel(rect.position.x + x, rect.position.y + y, color)


func _draw_ground_tile(img: Image, atlas_coords: Vector2i, side_mask: int) -> void:
	var rect := _tile_rect(atlas_coords)
	for y in TerrainTiles.TILE_SIZE.y:
		for x in TerrainTiles.TILE_SIZE.x:
			var color := Color(0.70, 0.70, 0.70, 1.0)
			# Кирпичная кладка: горизонтальный шов и смещённые вертикальные.
			if y == 7 or (y < 7 and x == 3) or (y > 7 and x == 11):
				color = Color(0.50, 0.50, 0.50, 1.0)
			if y == 0 and (side_mask & TerrainTiles.Side.TOP) == 0:
				color = Color(0.95, 0.95, 0.95, 1.0)
			if y >= 14 and (side_mask & TerrainTiles.Side.BOTTOM) == 0:
				color = Color(0.38, 0.38, 0.38, 1.0)
			if x == 0 and (side_mask & TerrainTiles.Side.LEFT) == 0:
				color = Color(0.84, 0.84, 0.84, 1.0)
			if x == 15 and (side_mask & TerrainTiles.Side.RIGHT) == 0:
				color = Color(0.44, 0.44, 0.44, 1.0)
			_put(img, rect, x, y, color)


func _draw_platform_tile(img: Image, atlas_coords: Vector2i, part: int) -> void:
	var rect := _tile_rect(atlas_coords)
	for y in TerrainTiles.TILE_SIZE.y:
		for x in TerrainTiles.TILE_SIZE.x:
			if y >= 5:
				continue
			var color := Color(0.88, 0.88, 0.88, 1.0)
			if y == 4:
				color = Color(0.52, 0.52, 0.52, 1.0)
			if part == TerrainTiles.PlatformPart.LEFT_END and x < 2:
				color = Color(0.45, 0.45, 0.45, 1.0)
			if part == TerrainTiles.PlatformPart.RIGHT_END and x > 13:
				color = Color(0.45, 0.45, 0.45, 1.0)
			_put(img, rect, x, y, color)
	# Небольшие опоры-зазубрины снизу, чтобы платформа читалась.
	_put(img, rect, 2, 5, Color(0.45, 0.45, 0.45, 1.0))
	_put(img, rect, 13, 5, Color(0.45, 0.45, 0.45, 1.0))


func _draw_ladder_tile(img: Image, atlas_coords: Vector2i) -> void:
	var rect := _tile_rect(atlas_coords)
	var rail := Color(0.85, 0.85, 0.85, 1.0)
	var rung := Color(0.70, 0.70, 0.70, 1.0)
	for y in TerrainTiles.TILE_SIZE.y:
		for x in [3, 4, 11, 12]:
			_put(img, rect, x, y, rail)
	for y in [2, 6, 10, 14]:
		for x in range(3, 13):
			_put(img, rect, x, y, rung)


func _draw_hazard_tile(img: Image, atlas_coords: Vector2i) -> void:
	var rect := _tile_rect(atlas_coords)
	for y in range(8, TerrainTiles.TILE_SIZE.y):
		for x in TerrainTiles.TILE_SIZE.x:
			_put(img, rect, x, y, Color(0.30, 0.30, 0.30, 1.0))
	# Шипы: пик над поверхностью.
	for spike_x in [2, 6, 10, 14]:
		for i in 7:
			_put(img, rect, spike_x, 2 + i, Color(0.90, 0.90, 0.90, 1.0))
			if i >= 4:
				_put(img, rect, spike_x - 1, 2 + i, Color(0.90, 0.90, 0.90, 1.0))
				_put(img, rect, spike_x + 1, 2 + i, Color(0.90, 0.90, 0.90, 1.0))


# --- TileSet ----------------------------------------------------------------

func _build_tileset() -> TileSet:
	var texture := load(ATLAS_PATH) as Texture2D
	if texture == null:
		push_error("T-13: атлас не импортирован: %s (сначала --atlas и --import)" % ATLAS_PATH)
		return null

	var tileset := TileSet.new()
	tileset.tile_size = TerrainTiles.TILE_SIZE
	tileset.set_meta(&"physics_layer_names", PackedStringArray(["solid", "one_way", "ladder", "hazard"]))

	_add_physics_layer(tileset, COLLISION_BIT_WORLD)
	_add_physics_layer(tileset, COLLISION_BIT_WORLD)
	_add_physics_layer(tileset, COLLISION_BIT_INTERACTABLE)
	_add_physics_layer(tileset, COLLISION_BIT_HAZARD)

	tileset.add_terrain_set()
	tileset.set_terrain_set_mode(TERRAIN_GROUND, TileSet.TERRAIN_MODE_MATCH_SIDES)
	tileset.add_terrain_set()
	tileset.set_terrain_set_mode(TERRAIN_PLATFORMS, TileSet.TERRAIN_MODE_MATCH_SIDES)
	for zone in TerrainTiles.ZONE_COUNT:
		tileset.add_terrain(TERRAIN_GROUND)
		tileset.set_terrain_name(TERRAIN_GROUND, zone, "zone_%d_ground" % (zone + 1))
		tileset.set_terrain_color(TERRAIN_GROUND, zone, _zone_ground_color(zone))
		tileset.add_terrain(TERRAIN_PLATFORMS)
		tileset.set_terrain_name(TERRAIN_PLATFORMS, zone, "zone_%d_platform" % (zone + 1))
		tileset.set_terrain_color(TERRAIN_PLATFORMS, zone, _zone_ground_color(zone).lightened(0.15))

	tileset.add_custom_data_layer()
	tileset.set_custom_data_layer_name(0, "tile_type")
	tileset.set_custom_data_layer_type(0, TYPE_STRING)
	tileset.add_custom_data_layer()
	tileset.set_custom_data_layer_name(1, "zone_index")
	tileset.set_custom_data_layer_type(1, TYPE_INT)

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = TerrainTiles.TILE_SIZE
	tileset.add_source(source, TerrainTiles.SOURCE_ID)

	for zone in TerrainTiles.ZONE_COUNT:
		for mask in 16:
			_create_tile(
				source,
				TerrainTiles.ground_atlas(zone, mask),
				"solid",
				zone,
				TERRAIN_GROUND,
				mask,
				PHYSICS_SOLID,
				_solid_polygon(),
				false
			)
		for part: int in TerrainTiles.PlatformPart.values():
			_create_tile(
				source,
				TerrainTiles.platform_atlas(zone, part),
				"one_way",
				zone,
				TERRAIN_PLATFORMS,
				TerrainTiles.platform_side_mask(part),
				PHYSICS_ONE_WAY,
				_one_way_polygon(),
				true
			)
		_create_tile(
			source,
			TerrainTiles.ladder_atlas(zone),
			"ladder",
			zone,
			-1,
			0,
			PHYSICS_LADDER,
			_solid_polygon(),
			false
		)
		_create_tile(
			source,
			TerrainTiles.hazard_atlas(zone),
			"hazard",
			zone,
			-1,
			0,
			PHYSICS_HAZARD,
			_solid_polygon(),
			false
		)

	return tileset


func _add_physics_layer(tileset: TileSet, collision_layer: int) -> void:
	var index := tileset.get_physics_layers_count()
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(index, collision_layer)
	tileset.set_physics_layer_collision_mask(index, 0)


func _create_tile(
	source: TileSetAtlasSource,
	atlas_coords: Vector2i,
	tile_type: String,
	zone_index: int,
	terrain_set: int,
	side_mask: int,
	physics_layer: int,
	polygon: PackedVector2Array,
	one_way: bool
) -> void:
	source.create_tile(atlas_coords)
	var data := source.get_tile_data(atlas_coords, 0)
	data.set_custom_data("tile_type", tile_type)
	data.set_custom_data("zone_index", zone_index)

	if terrain_set >= 0:
		data.set_terrain_set(terrain_set)
		data.set_terrain(zone_index)
		for side: int in TerrainTiles.PEERING_BIT_BY_SIDE:
			if (side_mask & side) != 0:
				var peering_bit: int = TerrainTiles.PEERING_BIT_BY_SIDE[side]
				data.set_terrain_peering_bit(peering_bit, zone_index)

	data.add_collision_polygon(physics_layer)
	data.set_collision_polygon_points(physics_layer, 0, polygon)
	if one_way:
		data.set_collision_polygon_one_way(physics_layer, 0, true)


func _solid_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
	])


func _one_way_polygon() -> PackedVector2Array:
	# Верхняя плита тайла: сверху блокирует, снизу игрок проходит.
	return PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 0), Vector2(-8, 0),
	])


func _zone_ground_color(zone_index: int) -> Color:
	match zone_index:
		1:
			return Color("1f2a1c")
		2:
			return Color("4f6b7a")
		3:
			return Color("54402f")
		4:
			return Color("303035")
		_:
			return Color("4a4a4f")


# --- ZoneData ---------------------------------------------------------------

func _build_zone_data(tileset: TileSet) -> ZoneData:
	var palette := ZonePalette.new()
	palette.background = Color("1a1f2e")
	palette.ground = Color("4a4a4f")
	palette.accent = Color("c08a3e")
	palette.hazard = Color("7a2a24")

	var start := ZoneEntryPoint.new()
	start.id = &"start"
	start.position = Vector2(48, 220)

	var from_ledge := ZoneEntryPoint.new()
	from_ledge.id = &"from_ledge"
	from_ledge.position = Vector2(248, 180)

	var entries: Array[ZoneEntryPoint] = [start, from_ledge]

	var east_gate := ZoneExit.new()
	east_gate.id = &"east_gate"
	east_gate.position = Vector2(452, 224)
	east_gate.size = Vector2(16, 32)
	east_gate.target_zone_id = &"zone_02_swamp"
	east_gate.target_entry_id = &"west_gate"

	var west_gate := ZoneExit.new()
	west_gate.id = &"west_gate"
	west_gate.position = Vector2(24, 224)
	west_gate.size = Vector2(16, 32)
	west_gate.target_zone_id = &"zone_01_village"
	west_gate.target_entry_id = &"east_gate"

	var exits: Array[ZoneExit] = [east_gate, west_gate]

	var data := ZoneData.new()
	data.id = &"zone_template"
	data.display_name = "Шаблон зоны · Деревня-бастион"
	data.palette = palette
	data.ambient_level = 0.42
	data.tileset = tileset
	data.entry_points = entries
	data.exits = exits
	return data


# --- Шаблон сцены зоны ------------------------------------------------------

func _build_zone_scene(tileset: TileSet, zone_data: ZoneData) -> void:
	var root := Node2D.new()
	root.name = "ZoneTemplate"
	root.set_script(load("res://world/zones/zone_scene.gd"))
	root.set("zone_data", zone_data)

	var background_layer := CanvasLayer.new()
	background_layer.name = "Background"
	background_layer.layer = -10
	_add_owned(root, background_layer, root)

	var sky := ColorRect.new()
	sky.name = "Sky"
	sky.size = Vector2(480, 270)
	sky.color = zone_data.palette.background
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_owned(background_layer, sky, root)
	sky.unique_name_in_owner = true

	var ambient := CanvasModulate.new()
	ambient.name = "Ambient"
	ambient.color = Color(zone_data.ambient_level, zone_data.ambient_level, zone_data.ambient_level, 1.0)
	_add_owned(root, ambient, root)
	ambient.unique_name_in_owner = true

	var ground := _make_layer(root, "Ground", tileset)
	_paint_floor(ground)
	for y in range(10, 15):
		ground.set_cell(Vector2i(LEVEL_LEFT, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(0, TerrainTiles.Side.TOP | TerrainTiles.Side.BOTTOM))
		ground.set_cell(Vector2i(LEVEL_RIGHT, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(0, TerrainTiles.Side.TOP | TerrainTiles.Side.BOTTOM))
	for x in range(8, 12):
		ground.set_cell(Vector2i(x, 11), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(0, TerrainTiles.Side.LEFT | TerrainTiles.Side.RIGHT))

	var platforms := _make_layer(root, "Platforms", tileset)
	for x in range(14, 18):
		var part := TerrainTiles.PlatformPart.MIDDLE
		if x == 14:
			part = TerrainTiles.PlatformPart.LEFT_END
		elif x == 17:
			part = TerrainTiles.PlatformPart.RIGHT_END
		platforms.set_cell(Vector2i(x, 12), TerrainTiles.SOURCE_ID, TerrainTiles.platform_atlas(0, part))

	var ladders := _make_layer(root, "Ladders", tileset)
	for y in range(12, 15):
		ladders.set_cell(Vector2i(20, y), TerrainTiles.SOURCE_ID, TerrainTiles.ladder_atlas(0))

	var hazards := _make_layer(root, "Hazards", tileset)
	for x in range(23, 26):
		hazards.set_cell(Vector2i(x, 14), TerrainTiles.SOURCE_ID, TerrainTiles.hazard_atlas(0))

	var props := Node2D.new()
	props.name = "Props"
	_add_owned(root, props, root)
	_add_prop(props, root, "res://world/props/bonfire.tscn", Vector2(64, 240))
	_add_prop(props, root, "res://world/props/chest.tscn", Vector2(168, 176))
	_add_prop(props, root, "res://world/props/door.tscn", Vector2(436, 240))
	_add_prop(props, root, "res://world/props/rubble.tscn", Vector2(112, 240))

	var entries := Node2D.new()
	entries.name = "Entries"
	_add_owned(root, entries, root)
	entries.unique_name_in_owner = true

	var exits := Node2D.new()
	exits.name = "Exits"
	_add_owned(root, exits, root)
	exits.unique_name_in_owner = true

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		push_error("T-13: не удалось упаковать шаблон зоны: %s" % error_string(pack_error))
		root.free()
		return
	ResourceSaver.save(packed, ZONE_SCENE_PATH)
	root.free()


func _make_layer(root: Node, layer_name: String, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	_add_owned(root, layer, root)
	layer.unique_name_in_owner = true
	return layer


func _paint_floor(ground: TileMapLayer) -> void:
	var mask := TerrainTiles.Side.LEFT | TerrainTiles.Side.RIGHT
	for x in range(LEVEL_LEFT, LEVEL_RIGHT + 1):
		ground.set_cell(Vector2i(x, FLOOR_ROW), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(0, mask))


func _add_prop(parent: Node, owner: Node, scene_path: String, at: Vector2) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("T-13: не найден prop %s" % scene_path)
		return
	var prop := packed.instantiate()
	prop.position = at
	_add_owned(parent, prop, owner)


func _add_owned(parent: Node, child: Node, owner: Node) -> void:
	parent.add_child(child)
	child.owner = owner
