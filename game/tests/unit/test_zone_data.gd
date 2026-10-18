extends GutTest
## T-13: контракт ZoneData (.tres) — все поля заполнены и валидны.

const ZONE_DATA_PATH := "res://data/zones/zone_template.tres"

var _data: ZoneData


func before_all() -> void:
	_data = load(ZONE_DATA_PATH) as ZoneData


func test_zone_data_is_typed_resource() -> void:
	assert_not_null(_data, "zone_template.tres must load")
	assert_true(_data is ZoneData, "zone_template.tres must be a ZoneData resource")
	assert_eq(_data.get_script().resource_path, "res://world/zones/zone_data.gd")


func test_identity_fields() -> void:
	assert_eq(_data.id, &"zone_template")
	assert_false(_data.display_name.is_empty(), "display_name must be set")
	assert_true(_data.display_name.contains("Шаблон"), "display_name must be human-readable")


func test_palette_matches_village_palette() -> void:
	assert_not_null(_data.palette, "palette must be set")
	assert_true(_data.palette.background.is_equal_approx(Color("1a1f2e")))
	assert_true(_data.palette.ground.is_equal_approx(Color("4a4a4f")))
	assert_true(_data.palette.accent.is_equal_approx(Color("c08a3e")))
	assert_true(_data.palette.hazard.is_equal_approx(Color("7a2a24")))


func test_ambient_level_is_in_design_range() -> void:
	# DESIGN §8.7: ambient мира 0.36–0.5.
	assert_between(_data.ambient_level, 0.36, 0.5)


func test_tileset_is_assigned_as_external_resource() -> void:
	assert_not_null(_data.tileset, "tileset must be set")
	assert_eq(_data.tileset.tile_size, Vector2i(16, 16))
	assert_eq(_data.tileset.resource_path, "res://world/tilesets/zone_terrain.tres")


func test_entry_points_are_unique_and_positioned() -> void:
	assert_gte(_data.entry_points.size(), 1, "at least one entry point")
	var ids: Array[StringName] = []
	for entry: ZoneEntryPoint in _data.entry_points:
		assert_not_null(entry)
		assert_ne(entry.id, &"", "entry id must be set")
		assert_false(ids.has(entry.id), "entry ids must be unique")
		ids.append(entry.id)
	assert_true(ids.has(&"start"), "template must provide a start entry")


func test_exits_link_to_target_zone_and_entry() -> void:
	assert_gte(_data.exits.size(), 1, "at least one exit")
	for exit_def: ZoneExit in _data.exits:
		assert_not_null(exit_def)
		assert_ne(exit_def.id, &"", "exit id must be set")
		assert_ne(exit_def.target_zone_id, &"", "exit must name target zone")
		assert_ne(exit_def.target_entry_id, &"", "exit must name target entry")
		assert_gt(exit_def.size.x, 0.0)
		assert_gt(exit_def.size.y, 0.0)


func test_validate_accepts_template() -> void:
	assert_eq(_data.validate(), PackedStringArray(), "template ZoneData must be valid")


func test_validate_reports_broken_data() -> void:
	var broken := ZoneData.new()
	broken.id = &""
	var issues := broken.validate()
	assert_gt(issues.size(), 0, "empty ZoneData must be rejected")
	assert_true(issues.has("id is empty"))
	assert_true(issues.has("tileset is not set"))
