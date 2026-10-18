extends GutTest
## T-13: физическая проверка тайлов — игрок стоит на solid, проходит сквозь one-way
## снизу, падает сквозь ladder/hazard, а hazard/ladder доступны соответствующим слоям.
## Используется тестовый CharacterBody2D 10×20 (hitbox по DESIGN §7) и гравитация проекта.

const TILESET_PATH := "res://world/tilesets/zone_terrain.tres"
const GRAVITY := 523.0
const PLAYER_LAYER := 1 << 1
const WORLD_LAYER := 1
const LADDER_LAYER := 128
const HAZARD_LAYER := 256

var _tileset: TileSet
var _source: TileSetAtlasSource


class GravityBody extends CharacterBody2D:
	var gravity: float = 523.0
	var use_gravity: bool = true
	var constant_velocity: Vector2 = Vector2.ZERO

	func _physics_process(delta: float) -> void:
		if use_gravity:
			velocity.y += gravity * delta
		else:
			velocity = constant_velocity
		move_and_slide()


func before_all() -> void:
	_tileset = load(TILESET_PATH) as TileSet
	_source = _tileset.get_source(TerrainTiles.SOURCE_ID) as TileSetAtlasSource


func _atlas_for(tile_type: String, zone_index: int = 0) -> Vector2i:
	for index in _source.get_tiles_count():
		var coords := _source.get_tile_id(index)
		var data := _source.get_tile_data(coords, 0)
		if data.get_custom_data("tile_type") == tile_type and data.get_custom_data("zone_index") == zone_index:
			return coords
	return Vector2i(-1, -1)


func _make_layer(scale_factor: Vector2 = Vector2.ONE) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = _tileset
	layer.scale = scale_factor
	add_child_autofree(layer)
	return layer


func _make_body(at: Vector2) -> GravityBody:
	var body := GravityBody.new()
	body.gravity = GRAVITY
	body.position = at
	body.collision_layer = PLAYER_LAYER
	body.collision_mask = WORLD_LAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 20)
	shape.shape = rect
	body.add_child(shape)
	add_child_autofree(body)
	return body


func _query_hits(center: Vector2, collision_mask: int) -> int:
	await wait_physics_frames(2)
	var params := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 8)
	params.shape = shape
	params.transform = Transform2D(0.0, center)
	params.collision_mask = collision_mask
	return get_tree().root.world_2d.direct_space_state.intersect_shape(params, 8).size()


func test_player_stands_on_solid_tile() -> void:
	var layer := _make_layer()
	layer.set_cell(Vector2i(0, 0), TerrainTiles.SOURCE_ID, _atlas_for("solid"))
	var body := _make_body(Vector2(8, -48))
	await wait_physics_frames(90)
	assert_almost_eq(body.position.y, -10.0, 1.5, "player must land on top of the solid tile")
	assert_true(body.is_on_floor(), "player must be on floor after landing")


func test_player_passes_one_way_tile_from_below() -> void:
	var layer := _make_layer()
	layer.set_cell(Vector2i(0, 0), TerrainTiles.SOURCE_ID, _atlas_for("one_way"))
	var body := _make_body(Vector2(8, 40))
	body.use_gravity = false
	body.constant_velocity = Vector2(0, -120)
	await wait_physics_frames(40)
	assert_lt(body.position.y, -10.0, "one-way tile must not block upward movement")


func test_player_lands_on_one_way_tile_from_above() -> void:
	var layer := _make_layer()
	layer.set_cell(Vector2i(0, 0), TerrainTiles.SOURCE_ID, _atlas_for("one_way"))
	var body := _make_body(Vector2(8, -48))
	await wait_physics_frames(90)
	assert_almost_eq(body.position.y, -10.0, 1.5, "player must stand on the one-way platform")
	assert_true(body.is_on_floor())


func test_player_falls_through_hazard_and_hazard_layer_is_queryable() -> void:
	var layer := _make_layer()
	layer.set_cell(Vector2i(0, 0), TerrainTiles.SOURCE_ID, _atlas_for("hazard"))
	var body := _make_body(Vector2(8, -48))
	await wait_physics_frames(90)
	assert_gt(body.position.y, 40.0, "hazard must not act as a solid floor")
	var hits := await _query_hits(Vector2(8, 8), HAZARD_LAYER)
	assert_gt(hits, 0, "hazard physics layer must be detectable by damage areas")


func test_player_falls_through_ladder_and_ladder_layer_is_queryable() -> void:
	var layer := _make_layer()
	layer.set_cell(Vector2i(0, 0), TerrainTiles.SOURCE_ID, _atlas_for("ladder"))
	var body := _make_body(Vector2(8, -48))
	await wait_physics_frames(90)
	assert_gt(body.position.y, 40.0, "ladder must not act as a solid floor")
	var hits := await _query_hits(Vector2(8, 8), LADDER_LAYER)
	assert_gt(hits, 0, "ladder physics layer must be detectable by climb sensors")


func test_tile_collisions_scale_by_integer_factor() -> void:
	# Тайл (0,1) при scale=2 занимает y=32..64; игрок должен встать на y=22.
	var layer := _make_layer(Vector2(2, 2))
	layer.set_cell(Vector2i(0, 1), TerrainTiles.SOURCE_ID, _atlas_for("solid"))
	var body := _make_body(Vector2(16, -48))
	await wait_physics_frames(120)
	assert_almost_eq(body.position.y, 22.0, 1.5, "integer-scaled tile collision must line up with visuals")
	assert_true(body.is_on_floor())
