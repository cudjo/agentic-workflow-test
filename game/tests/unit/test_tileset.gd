extends GutTest
## T-13: контракт тайлсета 16×16 — Terrain Sets, физические слои, tile data.

const TILESET_PATH := "res://world/tilesets/zone_terrain.tres"

var _tileset: TileSet
var _source: TileSetAtlasSource


func before_all() -> void:
	_tileset = load(TILESET_PATH) as TileSet
	_source = _tileset.get_source(TerrainTiles.SOURCE_ID) as TileSetAtlasSource


func _find_tile(tile_type: String, zone_index: int = 0) -> TileData:
	for index in _source.get_tiles_count():
		var coords := _source.get_tile_id(index)
		var data := _source.get_tile_data(coords, 0)
		if data.get_custom_data("tile_type") == tile_type and data.get_custom_data("zone_index") == zone_index:
			return data
	return null


func test_tileset_imports_with_16px_tiles() -> void:
	assert_not_null(_tileset, "zone_terrain.tres must load")
	assert_not_null(_source, "atlas source 0 must exist")
	assert_not_null(_source.texture, "atlas texture must be imported")
	assert_eq(_tileset.tile_size, Vector2i(16, 16))
	assert_eq(_source.texture_region_size, Vector2i(16, 16))


func test_physics_layers_solid_one_way_ladder_hazard() -> void:
	assert_eq(_tileset.get_physics_layers_count(), 4)
	assert_eq(_tileset.get_meta("physics_layer_names"), PackedStringArray(["solid", "one_way", "ladder", "hazard"]))
	assert_eq(_tileset.get_physics_layer_collision_layer(0), 1, "solid -> world layer")
	assert_eq(_tileset.get_physics_layer_collision_layer(1), 1, "one-way -> world layer")
	assert_eq(_tileset.get_physics_layer_collision_layer(2), 128, "ladder -> interactable layer")
	assert_eq(_tileset.get_physics_layer_collision_layer(3), 256, "hazard -> hazard layer")
	for layer in _tileset.get_physics_layers_count():
		assert_eq(_tileset.get_physics_layer_collision_mask(layer), 0)


func test_terrain_sets_have_zone_palettes() -> void:
	assert_eq(_tileset.get_terrain_sets_count(), 2)
	assert_eq(_tileset.get_terrain_set_mode(0), TileSet.TERRAIN_MODE_MATCH_SIDES)
	assert_eq(_tileset.get_terrain_set_mode(1), TileSet.TERRAIN_MODE_MATCH_SIDES)
	assert_eq(_tileset.get_terrains_count(0), TerrainTiles.ZONE_COUNT)
	assert_eq(_tileset.get_terrains_count(1), TerrainTiles.ZONE_COUNT)
	for zone in TerrainTiles.ZONE_COUNT:
		assert_eq(_tileset.get_terrain_name(0, zone), "zone_%d_ground" % (zone + 1))
		assert_eq(_tileset.get_terrain_name(1, zone), "zone_%d_platform" % (zone + 1))


func test_custom_data_layers_describe_tiles() -> void:
	assert_eq(_tileset.get_custom_data_layers_count(), 2)
	assert_eq(_tileset.get_custom_data_layer_name(0), "tile_type")
	assert_eq(_tileset.get_custom_data_layer_type(0), TYPE_STRING)
	assert_eq(_tileset.get_custom_data_layer_name(1), "zone_index")
	assert_eq(_tileset.get_custom_data_layer_type(1), TYPE_INT)

	for zone in TerrainTiles.ZONE_COUNT:
		for tile_type in ["solid", "one_way", "ladder", "hazard"]:
			assert_not_null(_find_tile(tile_type, zone), "%s tile must exist for zone %d" % [tile_type, zone + 1])


func test_solid_tile_has_solid_polygon() -> void:
	var data := _find_tile("solid")
	assert_not_null(data)
	assert_eq(data.get_collision_polygons_count(0), 1, "solid polygon on physics layer 0")
	assert_eq(data.get_collision_polygon_points(0, 0).size(), 4)
	assert_false(data.is_collision_polygon_one_way(0, 0))
	assert_eq(data.get_terrain_set(), 0, "solid belongs to ground terrain set")
	assert_eq(data.get_terrain(), 0)


func test_one_way_tile_uses_one_way_top_polygon() -> void:
	var data := _find_tile("one_way")
	assert_not_null(data)
	assert_eq(data.get_collision_polygons_count(1), 1, "one-way polygon on physics layer 1")
	assert_true(data.is_collision_polygon_one_way(1, 0), "polygon must be one-way")
	var points := data.get_collision_polygon_points(1, 0)
	assert_eq(points.size(), 4)
	assert_eq(points[0], Vector2(-8, -8))
	assert_eq(points[2], Vector2(8, 0), "one-way slab covers the tile top")
	assert_eq(data.get_terrain_set(), 1, "one-way belongs to platform terrain set")


func test_ladder_tile_has_interactable_polygon() -> void:
	var data := _find_tile("ladder")
	assert_not_null(data)
	assert_eq(data.get_collision_polygons_count(2), 1, "ladder polygon on physics layer 2")
	assert_eq(data.get_collision_polygons_count(0), 0, "ladder must not block as solid")
	assert_eq(data.get_collision_polygons_count(1), 0, "ladder must not block as one-way")


func test_hazard_tile_has_hazard_polygon() -> void:
	var data := _find_tile("hazard")
	assert_not_null(data)
	assert_eq(data.get_collision_polygons_count(3), 1, "hazard polygon on physics layer 3")
	assert_eq(data.get_collision_polygons_count(0), 0, "hazard must not block as solid")


func test_ground_terrain_has_16_side_variants_per_zone() -> void:
	for zone in TerrainTiles.ZONE_COUNT:
		var variants := 0
		for index in _source.get_tiles_count():
			var coords := _source.get_tile_id(index)
			var data := _source.get_tile_data(coords, 0)
			if data.get_custom_data("tile_type") == "solid" and data.get_custom_data("zone_index") == zone:
				variants += 1
				assert_eq(data.get_terrain(), zone)
		assert_eq(variants, 16, "zone %d must provide all side combinations" % (zone + 1))
