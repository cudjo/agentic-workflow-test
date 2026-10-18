extends SceneTree
## T-15: генератор зон 2 «Болото» и 3 «Горный перевал».
##
## Строит ZoneData (.tres) и сцены (ZoneScene .tscn) на пайплайне T-13:
## тайлсет zone_terrain.tres (строки зон 1/2 — индексы 1 и 2), props
## bonfire/chest/rubble, точки входа/выходов из ZoneData. Туман и параллакс —
## лёгкие программные скрипты зон (без шейдеров).
##
## Запуск (из каталога game/):
##   godot --headless -s res://tests/tools/build_zones_02_03.gd
##   godot --headless --import
##
## Скрипт лежит под tests/ и не попадает в экспортную сборку (exclude_filter T-02).

const TILESET_PATH := "res://world/tilesets/zone_terrain.tres"
const ZONE_SCENE_SCRIPT := "res://world/zones/zone_scene.gd"
const BANNER_SCENE_PATH := "res://world/zones/zone_banner.tscn"

const ZONE_02_DATA_PATH := "res://data/zones/zone_02_swamp.tres"
const ZONE_02_SCENE_PATH := "res://world/zones/zone_02_swamp/zone_02_swamp.tscn"
const ZONE_02_BACKDROP := "res://world/zones/zone_02_swamp/zone_02_backdrop.gd"
const ZONE_02_FOREGROUND := "res://world/zones/zone_02_swamp/zone_02_foreground.gd"
const ZONE_02_FOG := "res://world/zones/zone_02_swamp/zone_02_fog.gd"

const ZONE_03_DATA_PATH := "res://data/zones/zone_03_mountains.tres"
const ZONE_03_SCENE_PATH := "res://world/zones/zone_03_mountains/zone_03_mountains.tscn"
const ZONE_03_SCENE_SCRIPT := "res://world/zones/zone_03_mountains/zone_03_scene.gd"
const ZONE_03_PARALLAX := "res://world/zones/zone_03_mountains/zone_03_parallax.gd"
const ZONE_03_BACKDROP := "res://world/zones/zone_03_mountains/zone_03_backdrop.gd"
const ZONE_03_FOREGROUND := "res://world/zones/zone_03_mountains/zone_03_foreground.gd"

const BONFIRE_SCENE := "res://world/props/bonfire.tscn"
const CHEST_SCENE := "res://world/props/chest.tscn"
const RUBBLE_SCENE := "res://world/props/rubble.tscn"

const FLOOR_TOP := 224.0
const FLOOR_ROW_TOP := 14
const FLOOR_ROW_BOTTOM := 15
const LEVEL_COLS := 30

const WALL_LAYER := 1
const LIGHT_TEXTURE_SIZE := 180
const BASE_LIGHT_RADIUS := 90.0

## Индекс строки тайлсета: зона 2 = 1, зона 3 = 2 (TerrainTiles.GROUND_ROW_START).
const SWAMP_TILESET_ZONE := 1
const MOUNTAIN_TILESET_ZONE := 2


func _init() -> void:
	var tileset := load(TILESET_PATH) as TileSet
	if tileset == null:
		push_error("T-15: не найден тайлсет %s" % TILESET_PATH)
		quit(1)
		return

	if not _build_swamp(tileset):
		quit(1)
		return
	if not _build_mountains(tileset):
		quit(1)
		return

	print("T15_ZONES_OK ", ProjectSettings.globalize_path(ZONE_02_DATA_PATH), " ", ProjectSettings.globalize_path(ZONE_03_DATA_PATH))
	quit()


# --- Зона 2 «Болото» ---------------------------------------------------------

func _build_swamp(tileset: TileSet) -> bool:
	var data := _build_swamp_data(tileset)
	if ResourceSaver.save(data, ZONE_02_DATA_PATH) != OK:
		push_error("T-15: не удалось сохранить ZoneData болота")
		return false
	var loaded := load(ZONE_02_DATA_PATH) as ZoneData
	if loaded == null:
		push_error("T-15: ZoneData болота не читается после сохранения")
		return false
	return _build_swamp_scene(tileset, loaded)


func _build_swamp_data(tileset: TileSet) -> ZoneData:
	var palette := ZonePalette.new()
	palette.background = UITokens.GREEN_9
	palette.ground = UITokens.BROWN
	palette.accent = UITokens.GOLD_9
	palette.hazard = UITokens.STEEL_9

	var entries: Array[ZoneEntryPoint] = [
		_entry(&"start", Vector2(80.0, FLOOR_TOP - 10.0)),
		_entry(&"west_gate", Vector2(32.0, FLOOR_TOP - 10.0)),
		_entry(&"east_gate", Vector2(448.0, FLOOR_TOP - 10.0)),
	]
	var exits: Array[ZoneExit] = [
		_exit(&"west_gate", Vector2(12.0, FLOOR_TOP - 10.0), &"zone_01_village", &"from_gate"),
		_exit(&"east_gate", Vector2(468.0, FLOOR_TOP - 10.0), &"zone_03_mountains", &"north_pass"),
	]

	var data := ZoneData.new()
	data.id = &"zone_02_swamp"
	data.display_name = "Болото"
	data.palette = palette
	data.ambient_level = 0.36
	data.tileset = tileset
	data.entry_points = entries
	data.exits = exits
	return data


func _build_swamp_scene(tileset: TileSet, zone_data: ZoneData) -> bool:
	var root := _make_root("Zone02Swamp", ZONE_SCENE_SCRIPT, zone_data)
	var light_texture := _make_light_texture()

	_add_background(root, zone_data)
	_add_scripted(root, "Backdrop", ZONE_02_BACKDROP)

	var ground := _make_layer(root, "Ground", tileset)
	_paint_swamp_ground(ground)
	var platforms := _make_layer(root, "Platforms", tileset)
	_paint_swamp_platforms(platforms)
	_make_layer(root, "Ladders", tileset)
	var hazards := _make_layer(root, "Hazards", tileset)
	_paint_swamp_hazards(hazards)

	var lights := Node2D.new()
	lights.name = "Lights"
	_add_owned(root, lights, root)
	_add_light(lights, root, "Bonfire", Vector2(96.0, 208.0), light_texture, 46.0 / BASE_LIGHT_RADIUS, UITokens.GOLD_9, 0.65)
	_add_light(lights, root, "WispWest", Vector2(132.0, 150.0), light_texture, 50.0 / BASE_LIGHT_RADIUS, UITokens.GOLD_9, 0.25)
	_add_light(lights, root, "WispEast", Vector2(388.0, 146.0), light_texture, 50.0 / BASE_LIGHT_RADIUS, UITokens.GOLD_9, 0.25)

	var props := Node2D.new()
	props.name = "Props"
	_add_owned(root, props, root)
	_add_prop(props, root, BONFIRE_SCENE, "Bonfire", Vector2(96.0, FLOOR_TOP))
	_add_prop(props, root, CHEST_SCENE, "Chest", Vector2(432.0, 160.0))
	var dash_gate := _add_prop(props, root, RUBBLE_SCENE, "DashGate", Vector2(352.0, 160.0))
	dash_gate.scale = Vector2(2.0, 2.0)
	dash_gate.set_meta(&"ability_gate", &"dash")
	dash_gate.set_meta(&"future_gate", "T-09")

	_add_scripted(root, "Foreground", ZONE_02_FOREGROUND)

	var fog := CanvasLayer.new()
	fog.name = "Fog"
	fog.layer = 4
	fog.set_script(load(ZONE_02_FOG))
	_add_owned(root, fog, root)

	_add_transition_roots(root)
	_add_world_bounds(root)
	_add_banner(root, &"zone_02_swamp", "Зона 2 · Болото")
	return _save_scene(root, ZONE_02_SCENE_PATH)


func _paint_swamp_ground(ground: TileMapLayer) -> void:
	var mask := TerrainTiles.Side.LEFT | TerrainTiles.Side.RIGHT
	for y in range(FLOOR_ROW_TOP, FLOOR_ROW_BOTTOM + 1):
		for x in range(LEVEL_COLS):
			ground.set_cell(Vector2i(x, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(SWAMP_TILESET_ZONE, mask))
	# Нависающая скала над карнизом с dash-gate: прыжком препятствие не обойти.
	for x in range(20, 29):
		ground.set_cell(Vector2i(x, 7), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(SWAMP_TILESET_ZONE, mask))


func _paint_swamp_platforms(platforms: TileMapLayer) -> void:
	# Ступень к тайной платформе: пол → ряд 12 → ряд 10.
	_paint_platform_run(platforms, 12, 17, 19, SWAMP_TILESET_ZONE)
	_paint_platform_run(platforms, 10, 20, 28, SWAMP_TILESET_ZONE)


func _paint_swamp_hazards(hazards: TileMapLayer) -> void:
	# Болотная вода на поверхности пола: два плёса.
	for x in range(8, 13):
		hazards.set_cell(Vector2i(x, 13), TerrainTiles.SOURCE_ID, TerrainTiles.hazard_atlas(SWAMP_TILESET_ZONE))
	for x in range(16, 19):
		hazards.set_cell(Vector2i(x, 13), TerrainTiles.SOURCE_ID, TerrainTiles.hazard_atlas(SWAMP_TILESET_ZONE))


# --- Зона 3 «Горный перевал» -------------------------------------------------

func _build_mountains(tileset: TileSet) -> bool:
	var data := _build_mountains_data(tileset)
	if ResourceSaver.save(data, ZONE_03_DATA_PATH) != OK:
		push_error("T-15: не удалось сохранить ZoneData гор")
		return false
	var loaded := load(ZONE_03_DATA_PATH) as ZoneData
	if loaded == null:
		push_error("T-15: ZoneData гор не читается после сохранения")
		return false
	return _build_mountains_scene(tileset, loaded)


func _build_mountains_data(tileset: TileSet) -> ZoneData:
	var palette := ZonePalette.new()
	palette.background = UITokens.NIGHT_9
	palette.ground = UITokens.STEEL
	palette.accent = UITokens.STEEL_3
	palette.hazard = UITokens.STONE_5

	var entries: Array[ZoneEntryPoint] = [
		_entry(&"start", Vector2(80.0, FLOOR_TOP - 10.0)),
		_entry(&"south_ledge", Vector2(32.0, FLOOR_TOP - 10.0)),
		_entry(&"north_pass", Vector2(448.0, FLOOR_TOP - 10.0)),
	]
	var exits: Array[ZoneExit] = [
		_exit(&"south_ledge", Vector2(12.0, FLOOR_TOP - 10.0), &"zone_01_village", &"from_ledge"),
		_exit(&"north_pass", Vector2(468.0, FLOOR_TOP - 10.0), &"zone_02_swamp", &"east_gate"),
	]

	var data := ZoneData.new()
	data.id = &"zone_03_mountains"
	data.display_name = "Горный перевал"
	data.palette = palette
	data.ambient_level = 0.36
	data.tileset = tileset
	data.entry_points = entries
	data.exits = exits
	return data


func _build_mountains_scene(tileset: TileSet, zone_data: ZoneData) -> bool:
	var root := _make_root("Zone03Mountains", ZONE_03_SCENE_SCRIPT, zone_data)
	var light_texture := _make_light_texture()

	_add_background(root, zone_data)
	_add_scripted(root, "Parallax", ZONE_03_PARALLAX)
	_add_scripted(root, "Backdrop", ZONE_03_BACKDROP)

	var ground := _make_layer(root, "Ground", tileset)
	_paint_mountain_ground(ground)
	var platforms := _make_layer(root, "Platforms", tileset)
	_paint_mountain_platforms(platforms)
	_make_layer(root, "Ladders", tileset)
	var hazards := _make_layer(root, "Hazards", tileset)
	_paint_mountain_hazards(hazards)

	var lights := Node2D.new()
	lights.name = "Lights"
	_add_owned(root, lights, root)
	_add_light(lights, root, "Bonfire", Vector2(96.0, 208.0), light_texture, 46.0 / BASE_LIGHT_RADIUS, UITokens.GOLD_3, 0.7)
	_add_light(lights, root, "Moon", Vector2(388.0, 44.0), light_texture, 130.0 / BASE_LIGHT_RADIUS, UITokens.STEEL_3, 0.2)
	_add_light(lights, root, "IceGlow", Vector2(192.0, 128.0), light_texture, 60.0 / BASE_LIGHT_RADIUS, UITokens.STEEL_3, 0.3)

	var props := Node2D.new()
	props.name = "Props"
	_add_owned(root, props, root)
	_add_prop(props, root, BONFIRE_SCENE, "Bonfire", Vector2(96.0, FLOOR_TOP))
	_add_prop(props, root, CHEST_SCENE, "Chest", Vector2(192.0, 48.0))
	_add_prop(props, root, CHEST_SCENE, "ChestDash", Vector2(96.0, 160.0))
	var wall_gate := _add_prop(props, root, RUBBLE_SCENE, "WallClimbGate", Vector2(192.0, FLOOR_TOP))
	wall_gate.scale = Vector2(2.0, 2.5)
	wall_gate.set_meta(&"ability_gate", &"wall_climb")
	wall_gate.set_meta(&"future_gate", "T-09")
	var dash_gate := _add_prop(props, root, RUBBLE_SCENE, "DashGate", Vector2(64.0, 160.0))
	dash_gate.scale = Vector2(1.0, 2.0)
	dash_gate.set_meta(&"ability_gate", &"dash")
	dash_gate.set_meta(&"future_gate", "T-09")

	_add_scripted(root, "Foreground", ZONE_03_FOREGROUND)

	_add_transition_roots(root)
	_add_world_bounds(root)
	_add_banner(root, &"zone_03_mountains", "Зона 3 · Перевал")
	return _save_scene(root, ZONE_03_SCENE_PATH)


func _paint_mountain_ground(ground: TileMapLayer) -> void:
	var horizontal := TerrainTiles.Side.LEFT | TerrainTiles.Side.RIGHT
	var vertical := TerrainTiles.Side.TOP | TerrainTiles.Side.BOTTOM
	for y in range(FLOOR_ROW_TOP, FLOOR_ROW_BOTTOM + 1):
		for x in range(LEVEL_COLS):
			ground.set_cell(Vector2i(x, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(MOUNTAIN_TILESET_ZONE, horizontal))

	# Центральная шахта под wall climb: стены 11 и 14, проход 12–13.
	for y in range(4, FLOOR_ROW_TOP):
		ground.set_cell(Vector2i(11, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(MOUNTAIN_TILESET_ZONE, vertical))
		ground.set_cell(Vector2i(14, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(MOUNTAIN_TILESET_ZONE, vertical))

	# Вторая шахта-камин (декоративная вертикаль): стены 20 и 24, проход 21–23.
	for y in range(5, FLOOR_ROW_TOP):
		ground.set_cell(Vector2i(20, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(MOUNTAIN_TILESET_ZONE, vertical))
		ground.set_cell(Vector2i(24, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(MOUNTAIN_TILESET_ZONE, vertical))

	# Ледяной козырёк над карнизом с dash-gate: обойти прыжком нельзя.
	for x in range(3, 7):
		ground.set_cell(Vector2i(x, 7), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(MOUNTAIN_TILESET_ZONE, horizontal))


func _paint_mountain_platforms(platforms: TileMapLayer) -> void:
	# Ступени к карнизу с dash-gate.
	_paint_platform_run(platforms, 12, 2, 4, MOUNTAIN_TILESET_ZONE)
	_paint_platform_run(platforms, 10, 3, 6, MOUNTAIN_TILESET_ZONE)
	# Верхние полки шахт — one-way: карабкающийся проходит снизу и встаёт сверху,
	# шахта не «запечатана» сплошным тайлом (иначе wall climb ведёт в тупик).
	_paint_platform_run(platforms, 3, 10, 16, MOUNTAIN_TILESET_ZONE)
	_paint_platform_run(platforms, 4, 20, 24, MOUNTAIN_TILESET_ZONE)


func _paint_mountain_hazards(hazards: TileMapLayer) -> void:
	# Ледяные шипы на полу между шахтами.
	for x in range(17, 19):
		hazards.set_cell(Vector2i(x, 13), TerrainTiles.SOURCE_ID, TerrainTiles.hazard_atlas(MOUNTAIN_TILESET_ZONE))


# --- Общие помощники ---------------------------------------------------------

func _entry(id: StringName, at: Vector2) -> ZoneEntryPoint:
	var entry := ZoneEntryPoint.new()
	entry.id = id
	entry.position = at
	return entry


func _exit(id: StringName, at: Vector2, target_zone: StringName, target_entry: StringName) -> ZoneExit:
	var exit_def := ZoneExit.new()
	exit_def.id = id
	exit_def.position = at
	exit_def.size = Vector2(16.0, 32.0)
	exit_def.target_zone_id = target_zone
	exit_def.target_entry_id = target_entry
	return exit_def


func _make_root(root_name: String, script_path: String, zone_data: ZoneData) -> Node2D:
	var root := Node2D.new()
	root.name = root_name
	root.set_script(load(script_path))
	root.set("zone_data", zone_data)
	return root


func _add_background(root: Node2D, zone_data: ZoneData) -> void:
	var background := CanvasLayer.new()
	background.name = "Background"
	background.layer = -10
	_add_owned(root, background, root)

	var sky := ColorRect.new()
	sky.name = "Sky"
	sky.size = Vector2(480.0, 270.0)
	sky.color = zone_data.palette.background
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.unique_name_in_owner = true
	_add_owned(background, sky, root)

	var ambient := CanvasModulate.new()
	ambient.name = "Ambient"
	ambient.color = Color(zone_data.ambient_level, zone_data.ambient_level, zone_data.ambient_level, 1.0)
	ambient.unique_name_in_owner = true
	_add_owned(root, ambient, root)


func _add_scripted(parent: Node, node_name: String, script_path: String) -> Node2D:
	# Порядок в дереве задаёт слои: Parallax → Backdrop → тайлы → Foreground.
	var node := Node2D.new()
	node.name = node_name
	node.set_script(load(script_path))
	_add_owned(parent, node, parent)
	return node


func _make_layer(root: Node, layer_name: String, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	layer.unique_name_in_owner = true
	_add_owned(root, layer, root)
	return layer


func _paint_platform_run(platforms: TileMapLayer, row: int, first_col: int, last_col: int, zone_index: int) -> void:
	for x in range(first_col, last_col + 1):
		var part := TerrainTiles.PlatformPart.MIDDLE
		if x == first_col:
			part = TerrainTiles.PlatformPart.LEFT_END
		elif x == last_col:
			part = TerrainTiles.PlatformPart.RIGHT_END
		platforms.set_cell(
			Vector2i(x, row),
			TerrainTiles.SOURCE_ID,
			TerrainTiles.platform_atlas(zone_index, part)
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
	light.set_meta(&"radius_px", BASE_LIGHT_RADIUS * radius_scale)
	_add_owned(parent, light, owner_node)


func _add_prop(
	parent: Node,
	owner_node: Node,
	scene_path: String,
	prop_name: String,
	at: Vector2
) -> Node2D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("T-15: не найден prop %s" % scene_path)
		return null
	var prop := packed.instantiate() as Node2D
	prop.name = prop_name
	prop.position = at
	_add_owned(parent, prop, owner_node)
	return prop


func _add_transition_roots(root: Node) -> void:
	var entries := Node2D.new()
	entries.name = "Entries"
	entries.unique_name_in_owner = true
	_add_owned(root, entries, root)

	var exits := Node2D.new()
	exits.name = "Exits"
	exits.unique_name_in_owner = true
	_add_owned(root, exits, root)


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


func _add_banner(root: Node, zone_id: StringName, subtitle: String) -> void:
	var banner := (load(BANNER_SCENE_PATH) as PackedScene).instantiate()
	banner.name = "ZoneBanner"
	banner.set("zone_id", zone_id)
	banner.set("subtitle", subtitle)
	_add_owned(root, banner, root)


func _save_scene(root: Node2D, scene_path: String) -> bool:
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		push_error("T-15: не удалось упаковать сцену %s: %s" % [scene_path, error_string(pack_error)])
		root.free()
		return false
	var save_error := ResourceSaver.save(packed, scene_path)
	root.free()
	if save_error != OK:
		push_error("T-15: не удалось сохранить сцену %s: %s" % [scene_path, error_string(save_error)])
		return false
	return true


func _add_owned(parent: Node, child: Node, owner_node: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
