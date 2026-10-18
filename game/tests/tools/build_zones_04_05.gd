extends Node
## T-16: генератор зон 4 «Руины-храм» и 5 «Финал».
##
## Строит ZoneData (.tres) и сцены (ZoneScene .tscn) на пайплайне T-13 по
## образцу T-14/T-15: тайлсет `zone_terrain.tres` (строки зон 4/5 — индексы
## 3 и 4), props bonfire/chest, точки входа/выходов из ZoneData, WorldBounds.
## Специфика T-16:
##   * руины — тёплый ambient (zone_04_scene.gd), 2 источника света (костёр +
##     кровавый алтарь), загадка-проход (3 рычага + SealedGate);
##   * финал — пустая арена с `BossSpawn` (T-32) и хук `EndingExit`
##     (Marker2D `ending_exit` + чтение FactionManager).
##
## Запуск (из каталога game/), сцена-раннер нужна, чтобы autoload-имена
## (GameState в bonfire.gd) были доступны при компиляции — `-s` их не видит:
##   godot --headless --path game res://tests/tools/build_zones_04_05.tscn
##   godot --headless --import
##
## Скрипт лежит под tests/ и не попадает в экспортную сборку (exclude_filter T-02).

const TILESET_PATH := "res://world/tilesets/zone_terrain.tres"
const ZONE_SCENE_SCRIPT := "res://world/zones/zone_scene.gd"
const BANNER_SCENE_PATH := "res://world/zones/zone_banner.tscn"

const ZONE_04_DATA_PATH := "res://data/zones/zone_04_ruins.tres"
const ZONE_04_SCENE_PATH := "res://world/zones/zone_04_ruins/zone_04_ruins.tscn"
const ZONE_04_SCENE_SCRIPT := "res://world/zones/zone_04_ruins/zone_04_scene.gd"
const ZONE_04_BACKDROP := "res://world/zones/zone_04_ruins/zone_04_backdrop.gd"
const ZONE_04_FOREGROUND := "res://world/zones/zone_04_ruins/zone_04_foreground.gd"
const ZONE_04_GLOW := "res://world/zones/zone_04_ruins/zone_04_glow.gd"
const ZONE_04_PUZZLE := "res://world/zones/zone_04_ruins/zone_04_puzzle.gd"

const ZONE_05_DATA_PATH := "res://data/zones/zone_05_finale.tres"
const ZONE_05_SCENE_PATH := "res://world/zones/zone_05_finale/zone_05_finale.tscn"
const ZONE_05_BACKDROP := "res://world/zones/zone_05_finale/zone_05_backdrop.gd"
const ZONE_05_FOREGROUND := "res://world/zones/zone_05_finale/zone_05_foreground.gd"
const ZONE_05_ARENA := "res://world/zones/zone_05_finale/zone_05_arena.gd"
const ZONE_05_ENDING := "res://world/zones/zone_05_finale/zone_05_ending_hook.gd"

const BONFIRE_SCENE := "res://world/props/bonfire.tscn"
const CHEST_SCENE := "res://world/props/chest.tscn"
const LEVER_SCENE := "res://world/props/lever.tscn"
const SEALED_GATE_SCENE := "res://world/props/sealed_gate.tscn"
const RUBBLE_SCENE := "res://world/props/rubble.tscn"

const FLOOR_TOP := 224.0
const FLOOR_ROW_TOP := 14
const FLOOR_ROW_BOTTOM := 15
const LEVEL_COLS := 30

const WALL_LAYER := 1
const LIGHT_TEXTURE_SIZE := 180
const BASE_LIGHT_RADIUS := 90.0

## Индексы строк тайлсета: зона 4 = 3, зона 5 = 4 (TerrainTiles.GROUND_ROW_START).
const RUINS_TILESET_ZONE := 3
const FINALE_TILESET_ZONE := 4

## Бонус/подсказки загадки: целевые положения рычагов (вкл, выкл, вкл).
const LEVER_IDS: Array[StringName] = [&"left", &"middle", &"right"]
const LEVER_SOLUTION: Array[bool] = [true, false, true]
const LEVER_X: Array[float] = [120.0, 168.0, 216.0]


func build() -> bool:
	var tileset := load(TILESET_PATH) as TileSet
	if tileset == null:
		push_error("T-16: не найден тайлсет %s" % TILESET_PATH)
		return false

	if not _build_ruins(tileset):
		return false
	if not _build_finale(tileset):
		return false

	print("T16_ZONES_OK ", ProjectSettings.globalize_path(ZONE_04_DATA_PATH), " ", ProjectSettings.globalize_path(ZONE_05_DATA_PATH))
	return true


# --- Зона 4 «Руины-храм» -----------------------------------------------------

func _build_ruins(tileset: TileSet) -> bool:
	var data := _build_ruins_data(tileset)
	if ResourceSaver.save(data, ZONE_04_DATA_PATH) != OK:
		push_error("T-16: не удалось сохранить ZoneData руин")
		return false
	var loaded := load(ZONE_04_DATA_PATH) as ZoneData
	if loaded == null:
		push_error("T-16: ZoneData руин не читается после сохранения")
		return false
	return _build_ruins_scene(tileset, loaded)


func _build_ruins_data(tileset: TileSet) -> ZoneData:
	var palette := ZonePalette.new()
	palette.background = UITokens.BROWN_3
	palette.ground = UITokens.BROWN
	palette.accent = UITokens.GOLD
	palette.hazard = UITokens.BLOOD

	var entries: Array[ZoneEntryPoint] = [
		_entry(&"from_swamp", Vector2(32.0, FLOOR_TOP - 10.0)),
		_entry(&"from_mountains", Vector2(48.0, 150.0)),
		# Возврат из финала — до запечатанной двери: повторная загрузка зоны
		# не запирает игрока в восточном зале с закрытой загадкой.
		_entry(&"from_finale", Vector2(320.0, FLOOR_TOP - 10.0)),
	]
	var exits: Array[ZoneExit] = [
		_exit(&"to_swamp", Vector2(12.0, FLOOR_TOP - 10.0), &"zone_02_swamp", &"from_ruins"),
		_exit(&"to_mountains", Vector2(12.0, 144.0), &"zone_03_mountains", &"from_ruins"),
		_exit(&"to_finale", Vector2(468.0, FLOOR_TOP - 10.0), &"zone_05_finale", &"from_ruins"),
	]

	var data := ZoneData.new()
	data.id = &"zone_04_ruins"
	data.display_name = "Руины-храм"
	data.palette = palette
	# DESIGN §8.7: «до 0.26 внутри руин у костра».
	data.ambient_level = 0.26
	data.tileset = tileset
	data.entry_points = entries
	data.exits = exits
	return data


func _build_ruins_scene(tileset: TileSet, zone_data: ZoneData) -> bool:
	var root := _make_root("Zone04Ruins", ZONE_04_SCENE_SCRIPT, zone_data)
	var light_texture := _make_light_texture()

	_add_background(root, zone_data)
	_add_scripted(root, "Backdrop", ZONE_04_BACKDROP)

	var ground := _make_layer(root, "Ground", tileset)
	_paint_ruins_ground(ground)
	var platforms := _make_layer(root, "Platforms", tileset)
	_paint_ruins_platforms(platforms)
	_make_layer(root, "Ladders", tileset)
	var hazards := _make_layer(root, "Hazards", tileset)
	_paint_ruins_hazards(hazards)

	# Гнетущая тишина: ровно два источника — костёр (жёлтый) и кровавый алтарь.
	var lights := Node2D.new()
	lights.name = "Lights"
	_add_owned(root, lights, root)
	_add_light(lights, root, "Bonfire", Vector2(288.0, 206.0), light_texture, 78.0 / BASE_LIGHT_RADIUS, UITokens.GOLD_9, 1.35)
	_add_light(lights, root, "AltarGlow", Vector2(424.0, 198.0), light_texture, 58.0 / BASE_LIGHT_RADIUS, UITokens.BLOOD_3, 1.2)

	var props := Node2D.new()
	props.name = "Props"
	_add_owned(root, props, root)
	_add_prop(props, root, BONFIRE_SCENE, "Bonfire", Vector2(288.0, FLOOR_TOP))
	_add_prop(props, root, CHEST_SCENE, "Chest", Vector2(432.0, FLOOR_TOP))

	_add_ruins_puzzle(root)
	_add_scripted(root, "Foreground", ZONE_04_FOREGROUND)
	_add_ruins_glow(root)

	_add_transition_roots(root)
	_add_world_bounds(root)
	_add_banner(root, &"zone_04_ruins", "Зона 4 · Руины-храм")
	return _save_scene(root, ZONE_04_SCENE_PATH)


func _paint_ruins_ground(ground: TileMapLayer) -> void:
	var horizontal := TerrainTiles.Side.LEFT | TerrainTiles.Side.RIGHT
	var vertical := TerrainTiles.Side.TOP | TerrainTiles.Side.BOTTOM
	for y in range(FLOOR_ROW_TOP, FLOOR_ROW_BOTTOM + 1):
		for x in range(LEVEL_COLS):
			ground.set_cell(Vector2i(x, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(RUINS_TILESET_ZONE, horizontal))

	# Крыша храма.
	for x in range(2, 28):
		ground.set_cell(Vector2i(x, 2), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(RUINS_TILESET_ZONE, horizontal))

	# Свисающие с крыши обломки колонн (выше прыжка — не мешают проходу).
	for x: int in [4, 9, 15, 21]:
		for y in range(3, 8):
			ground.set_cell(Vector2i(x, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(RUINS_TILESET_ZONE, vertical))

	# Стена, разделяющая зал и алтарь. Проём (ряды 12–13) закрыт SealedGate.
	for y in range(3, 12):
		ground.set_cell(Vector2i(23, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(RUINS_TILESET_ZONE, vertical))


func _paint_ruins_platforms(platforms: TileMapLayer) -> void:
	# Ступени к верхнему входу из гор (ряд 10): шаги по 16 px — h_jump = 32 px.
	_paint_platform_run(platforms, 13, 1, 4, RUINS_TILESET_ZONE)
	_paint_platform_run(platforms, 12, 1, 5, RUINS_TILESET_ZONE)
	_paint_platform_run(platforms, 11, 1, 5, RUINS_TILESET_ZONE)
	_paint_platform_run(platforms, 10, 1, 5, RUINS_TILESET_ZONE)


func _paint_ruins_hazards(hazards: TileMapLayer) -> void:
	# Кровавая лужа у алтаря за запечатанной дверью (hazard, не solid).
	for x in range(26, 28):
		hazards.set_cell(Vector2i(x, 13), TerrainTiles.SOURCE_ID, TerrainTiles.hazard_atlas(RUINS_TILESET_ZONE))


func _add_ruins_puzzle(root: Node2D) -> void:
	var puzzle := Node2D.new()
	puzzle.name = "Puzzle"
	puzzle.set_script(load(ZONE_04_PUZZLE))
	_add_owned(root, puzzle, root)

	var gate := _instantiate(SEALED_GATE_SCENE, "Gate", Vector2(376.0, FLOOR_TOP))
	if gate != null:
		_add_owned(puzzle, gate, root)

	var levers := Node2D.new()
	levers.name = "Levers"
	_add_owned(puzzle, levers, root)
	for index in LEVER_IDS.size():
		var lever := _instantiate(LEVER_SCENE, "Lever_%s" % LEVER_IDS[index], Vector2(LEVER_X[index], FLOOR_TOP))
		if lever == null:
			continue
		lever.set("lever_id", LEVER_IDS[index])
		lever.set("active", false)
		lever.set("solution_state", LEVER_SOLUTION[index])
		_add_owned(levers, lever, root)


func _add_ruins_glow(root: Node2D) -> void:
	# Отдельный CanvasLayer: эмиссивный отсвет не затемняется CanvasModulate.
	var layer := CanvasLayer.new()
	layer.name = "Glow"
	layer.layer = 1
	_add_owned(root, layer, root)

	var shafts := Node2D.new()
	shafts.name = "Shafts"
	shafts.set_script(load(ZONE_04_GLOW))
	_add_owned(layer, shafts, root)


# --- Зона 5 «Финал» ----------------------------------------------------------

func _build_finale(tileset: TileSet) -> bool:
	var data := _build_finale_data(tileset)
	if ResourceSaver.save(data, ZONE_05_DATA_PATH) != OK:
		push_error("T-16: не удалось сохранить ZoneData финала")
		return false
	var loaded := load(ZONE_05_DATA_PATH) as ZoneData
	if loaded == null:
		push_error("T-16: ZoneData финала не читается после сохранения")
		return false
	return _build_finale_scene(tileset, loaded)


func _build_finale_data(tileset: TileSet) -> ZoneData:
	var palette := ZonePalette.new()
	palette.background = UITokens.VOID
	palette.ground = UITokens.STONE_9
	palette.accent = UITokens.STONE_5
	palette.hazard = UITokens.BLOOD_3

	var entries: Array[ZoneEntryPoint] = [
		_entry(&"from_ruins", Vector2(32.0, FLOOR_TOP - 10.0)),
	]
	var exits: Array[ZoneExit] = [
		_exit(&"to_ruins", Vector2(12.0, FLOOR_TOP - 10.0), &"zone_04_ruins", &"from_finale"),
	]

	var data := ZoneData.new()
	data.id = &"zone_05_finale"
	data.display_name = "Финал"
	data.palette = palette
	data.ambient_level = 0.38
	data.tileset = tileset
	data.entry_points = entries
	data.exits = exits
	return data


func _build_finale_scene(tileset: TileSet, zone_data: ZoneData) -> bool:
	var root := _make_root("Zone05Finale", ZONE_SCENE_SCRIPT, zone_data)
	var light_texture := _make_light_texture()

	_add_background(root, zone_data)
	_add_scripted(root, "Backdrop", ZONE_05_BACKDROP)

	var ground := _make_layer(root, "Ground", tileset)
	_paint_finale_ground(ground)
	_make_layer(root, "Platforms", tileset)
	_make_layer(root, "Ladders", tileset)
	_make_layer(root, "Hazards", tileset)

	var lights := Node2D.new()
	lights.name = "Lights"
	_add_owned(root, lights, root)
	_add_light(lights, root, "Moon", Vector2(240.0, 40.0), light_texture, 150.0 / BASE_LIGHT_RADIUS, UITokens.STONE_5, 0.3)
	_add_light(lights, root, "BloodRune", Vector2(360.0, 208.0), light_texture, 34.0 / BASE_LIGHT_RADIUS, UITokens.BLOOD_3, 0.25)

	_add_finale_arena(root)
	_add_finale_ending(root)

	var props := Node2D.new()
	props.name = "Props"
	_add_owned(root, props, root)
	# Обломки монолитов: декор без коллизий (арена T-32 должна оставаться свободной).
	for spec: Array in [[&"FallenMonolithWest", 80.0], [&"FallenMonolithEast", 424.0]]:
		var rubble := _add_prop(props, root, RUBBLE_SCENE, String(spec[0]), Vector2(float(spec[1]), FLOOR_TOP))
		if rubble != null:
			rubble.scale = Vector2(1.5, 1.5)
			rubble.set("blocking", false)
			rubble.modulate = Color(0.72, 0.72, 0.75, 1.0)

	_add_scripted(root, "Foreground", ZONE_05_FOREGROUND)

	_add_transition_roots(root)
	_add_world_bounds(root)
	_add_banner(root, &"zone_05_finale", "Зона 5 · Финал")
	return _save_scene(root, ZONE_05_SCENE_PATH)


func _paint_finale_ground(ground: TileMapLayer) -> void:
	var horizontal := TerrainTiles.Side.LEFT | TerrainTiles.Side.RIGHT
	var vertical := TerrainTiles.Side.TOP | TerrainTiles.Side.BOTTOM
	for y in range(FLOOR_ROW_TOP, FLOOR_ROW_BOTTOM + 1):
		for x in range(LEVEL_COLS):
			ground.set_cell(Vector2i(x, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(FINALE_TILESET_ZONE, horizontal))
	# Свисающие монолиты над ареной — декор, выше прыжка.
	for x: int in [5, 11, 19, 25]:
		for y in range(3, 7):
			ground.set_cell(Vector2i(x, y), TerrainTiles.SOURCE_ID, TerrainTiles.ground_atlas(FINALE_TILESET_ZONE, vertical))


func _add_finale_arena(root: Node2D) -> void:
	var arena := Node2D.new()
	arena.name = "Arena"
	arena.set_script(load(ZONE_05_ARENA))
	_add_owned(root, arena, root)

	var spawn := Marker2D.new()
	spawn.name = "BossSpawn"
	spawn.position = Vector2(360.0, FLOOR_TOP)
	_add_owned(arena, spawn, root)


func _add_finale_ending(root: Node2D) -> void:
	var ending := Area2D.new()
	ending.name = "EndingExit"
	ending.position = Vector2(452.0, FLOOR_TOP - 10.0)
	ending.collision_layer = 0
	ending.collision_mask = CombatLayers.PLAYER_BODY
	ending.monitorable = false
	ending.set_script(load(ZONE_05_ENDING))
	_add_owned(root, ending, root)

	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24.0, 32.0)
	shape.shape = rect
	_add_owned(ending, shape, root)

	var marker := Marker2D.new()
	marker.name = "ending_exit"
	marker.position = Vector2.ZERO
	_add_owned(ending, marker, root)


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
	# Порядок в дереве задаёт слои: Backdrop → тайлы → Foreground.
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


func _instantiate(scene_path: String, node_name: String, at: Vector2) -> Node2D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("T-16: не найден prop %s" % scene_path)
		return null
	var prop := packed.instantiate() as Node2D
	if prop == null:
		push_error("T-16: prop %s не Node2D" % scene_path)
		return null
	prop.name = node_name
	prop.position = at
	return prop


func _add_prop(
	parent: Node,
	owner_node: Node,
	scene_path: String,
	prop_name: String,
	at: Vector2
) -> Node2D:
	var prop := _instantiate(scene_path, prop_name, at)
	if prop == null:
		return null
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
		push_error("T-16: не удалось упаковать сцену %s: %s" % [scene_path, error_string(pack_error)])
		root.free()
		return false
	var save_error := ResourceSaver.save(packed, scene_path)
	root.free()
	if save_error != OK:
		push_error("T-16: не удалось сохранить сцену %s: %s" % [scene_path, error_string(save_error)])
		return false
	return true


func _add_owned(parent: Node, child: Node, owner_node: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
