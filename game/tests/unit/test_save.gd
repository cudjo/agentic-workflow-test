extends GutTest
## T-25 — сохранения: round-trip, checksum, миграции, атомарность
## (PLAN §3.4, AC-05.1, EC-07/EC-14).
##
## Тесты работают в отдельном каталоге `user://test_saves_t25`, чтобы не
## трогать реальные слоты игрока; `SaveManager.saves_dir` переопределяется
## только на время прогона.

const TEST_DIR: String = "user://test_saves_t25"
const SWORD_PATH: String = "res://data/weapons/one_handed_sword.tres"
const DAGGER_PATH: String = "res://data/weapons/light_dagger.tres"
const AXE_PATH: String = "res://data/weapons/two_handed_axe.tres"

var _original_saves_dir: String = SaveManager.DEFAULT_SAVES_DIR
var _original_stamina: float = 0.0
var _original_weapon: WeaponData = null


func before_all() -> void:
	_original_saves_dir = SaveManager.saves_dir
	SaveManager.saves_dir = TEST_DIR


func after_all() -> void:
	SaveManager.saves_dir = _original_saves_dir
	_cleanup_dir()
	var parent: DirAccess = DirAccess.open(TEST_DIR.get_base_dir())
	if parent != null and parent.dir_exists(TEST_DIR.get_file()):
		parent.remove(TEST_DIR.get_file())


func before_each() -> void:
	_original_stamina = GameState.stamina
	_original_weapon = GameState.weapon
	_cleanup_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))


func after_each() -> void:
	GameState.stamina = _original_stamina
	if _original_weapon != null:
		GameState.set_weapon(_original_weapon)
	_cleanup_dir()


func test_round_trip_restores_state_and_slot_metadata() -> void:
	GameState.stamina = 42.5
	GameState.set_weapon(load(DAGGER_PATH) as WeaponData)
	watch_signals(EventBus)

	assert_true(
		SaveManager.save_slot(1, {
			"zone_id": "zone_02_swamp",
			"zone_name": "Гнилая топь",
			"level": 3,
			"play_time": 321.5,
		}),
		"save to slot 1 succeeds"
	)
	assert_true(FileAccess.file_exists(SaveManager.get_slot_path(1)), "slot file exists")
	assert_signal_emitted_with_parameters(EventBus, "save_completed", [1])

	var raw: String = _read_text(SaveManager.get_slot_path(1))
	assert_true(
		raw.begins_with("{\"schema_version\":%d,\"checksum\":\"" % SaveMigrations.CURRENT_VERSION),
		"file starts with the {schema_version, checksum} header"
	)
	assert_gt(raw.find("\"body\":{"), 0, "header is followed by the body object")
	assert_gt(raw.find("\"state\":{"), 0, "body contains the serialized state")

	# Ломаем состояние, чтобы загрузка была заметна.
	GameState.stamina = 100.0
	GameState.set_weapon(load(SWORD_PATH) as WeaponData)

	assert_true(SaveManager.load_slot(1), "slot 1 loads")
	assert_almost_eq(GameState.stamina, 42.5, 0.001, "stamina is restored (AC-05.1)")
	assert_eq(String(GameState.weapon.id), "light_dagger", "weapon is restored")

	var meta: Dictionary = SaveManager.get_slot_metadata(1)
	assert_true(meta["exists"], "slot metadata: exists")
	assert_true(meta["valid"], "slot metadata: valid")
	assert_false(meta["corrupted"], "slot metadata: not corrupted")
	assert_eq(meta["zone_id"], "zone_02_swamp", "metadata carries zone id for UI")
	assert_eq(meta["zone_name"], "Гнилая топь", "metadata carries zone name for UI")
	assert_eq(meta["level"], 3, "metadata carries level for UI")
	assert_almost_eq(float(meta["play_time"]), 321.5, 0.001, "metadata carries play time")
	assert_gt(int(meta["saved_at_unix"]), 0, "metadata carries save timestamp")


func test_slots_are_isolated_and_missing_slot_is_empty() -> void:
	assert_false(SaveManager.has_slot(1), "fresh test dir has no slot")

	GameState.stamina = 11.0
	assert_true(SaveManager.save_slot(1))
	GameState.stamina = 22.0
	assert_true(SaveManager.save_slot(3))

	GameState.stamina = 90.0
	assert_true(SaveManager.load_slot(3))
	assert_almost_eq(GameState.stamina, 22.0, 0.001, "slot 3 keeps its own state")

	assert_false(SaveManager.load_slot(2), "empty slot is not loaded")
	assert_eq(
		String(SaveManager.get_slot_metadata(2)["reason"]),
		SaveManager.LOAD_EMPTY,
		"missing slot reports empty"
	)


func test_tampered_checksum_is_rejected_without_crashing() -> void:
	GameState.stamina = 55.0
	assert_true(SaveManager.save_slot(2))

	var path: String = SaveManager.get_slot_path(2)
	var text: String = _read_text(path)
	var marker: String = "\"checksum\":\""
	var index: int = text.find(marker) + marker.length()
	assert_gt(index, marker.length(), "checksum header is present")
	var original_char: String = text.substr(index, 1)
	var replacement: String = "0" if original_char != "0" else "1"
	_write_text(path, text.substr(0, index) + replacement + text.substr(index + 1))

	GameState.stamina = 100.0
	watch_signals(EventBus)

	assert_false(SaveManager.load_slot(2), "bad checksum -> slot is not loaded (EC-07)")
	assert_almost_eq(GameState.stamina, 100.0, 0.001, "GameState is untouched on corruption")
	assert_signal_emitted_with_parameters(
		EventBus,
		"slot_corrupted",
		[2, SaveManager.LOAD_CORRUPTED]
	)

	var meta: Dictionary = SaveManager.get_slot_metadata(2)
	assert_true(meta["exists"], "damaged slot still exists on disk")
	assert_false(meta["valid"], "damaged slot is not valid")
	assert_true(meta["corrupted"], "UI can show that the slot is corrupted")


func test_tampered_body_without_checksum_update_is_rejected() -> void:
	GameState.stamina = 55.0
	assert_true(SaveManager.save_slot(1))

	var path: String = SaveManager.get_slot_path(1)
	var text: String = _read_text(path)
	# Добавляем ключ в тело, не пересчитывая checksum.
	_write_text(path, text.substr(0, text.length() - 1) + ",\"injected\":true}")

	watch_signals(EventBus)
	assert_false(SaveManager.load_slot(1), "body changed -> checksum mismatch")
	assert_signal_emitted(EventBus, "slot_corrupted")


func test_truncated_file_is_detected_as_corrupted() -> void:
	GameState.stamina = 77.0
	assert_true(SaveManager.save_slot(3))

	var path: String = SaveManager.get_slot_path(3)
	var text: String = _read_text(path)
	_write_text(path, text.substr(0, int(text.length() / 2)))

	watch_signals(EventBus)
	assert_false(SaveManager.load_slot(3), "truncated slot is not loaded (EC-07)")
	assert_signal_emitted_with_parameters(
		EventBus,
		"slot_corrupted",
		[3, SaveManager.LOAD_CORRUPTED]
	)

	var meta: Dictionary = SaveManager.get_slot_metadata(3)
	assert_true(meta["corrupted"], "truncated slot is reported as corrupted")


func test_overwrite_replaces_existing_slot_atomically() -> void:
	GameState.stamina = 10.0
	assert_true(SaveManager.save_slot(1), "first save creates the slot")

	GameState.stamina = 20.0
	assert_true(SaveManager.save_slot(1), "second save overwrites the slot via rename")
	assert_false(
		FileAccess.file_exists(SaveManager.get_slot_path(1) + SaveManager.TEMP_SUFFIX),
		"tmp file is gone after a successful save"
	)

	GameState.stamina = 0.0
	assert_true(SaveManager.load_slot(1))
	assert_almost_eq(GameState.stamina, 20.0, 0.001, "the new state replaced the old one")


func test_failed_write_keeps_previous_slot_intact() -> void:
	GameState.stamina = 12.5
	assert_true(SaveManager.save_slot(1), "initial save")

	# Блокируем tmp-путь каталогом: FileAccess не сможет открыть его на запись.
	var directory: DirAccess = DirAccess.open(SaveManager.saves_dir)
	var temp_name: String = SaveManager.SLOT_FILE_TEMPLATE % 1 + SaveManager.TEMP_SUFFIX
	assert_eq(directory.make_dir(temp_name), OK, "tmp path is blocked for the failure case")

	GameState.stamina = 99.0
	watch_signals(EventBus)
	assert_false(SaveManager.save_slot(1), "write failure is reported, not raised (EC-14)")
	assert_signal_emitted_with_parameters(
		EventBus,
		"save_failed",
		[1, SaveManager.LOAD_IO_ERROR]
	)

	# Старый слот должен остаться прежним.
	GameState.stamina = 0.0
	assert_true(SaveManager.load_slot(1), "previous slot is still loadable")
	assert_almost_eq(GameState.stamina, 12.5, 0.001, "old slot was not overwritten (EC-14)")


func test_v0_save_is_migrated_on_load() -> void:
	var legacy_body: Dictionary = {
		"stamina": 33.5,
		"weapon_id": "two_handed_axe",
		"weapon_path": AXE_PATH,
		"meta": {
			"zone_id": "zone_01_village",
			"level": 1,
		},
	}
	_write_text(
		SaveManager.get_slot_path(2),
		SaveSerializer.encode(legacy_body, 0)
	)

	var meta: Dictionary = SaveManager.get_slot_metadata(2)
	assert_true(meta["valid"], "v0 slot is readable after migration")
	assert_eq(int(meta["schema_version"]), 0, "file version is reported as v0")
	assert_eq(meta["zone_id"], "zone_01_village", "meta survives migration")

	GameState.stamina = 100.0
	GameState.set_weapon(load(SWORD_PATH) as WeaponData)
	assert_true(SaveManager.load_slot(2), "v0 slot loads (schema migration)")
	assert_almost_eq(GameState.stamina, 33.5, 0.001, "v0 stamina is restored")
	assert_eq(String(GameState.weapon.id), "two_handed_axe", "v0 weapon is restored")


func test_migration_wraps_v0_state_and_rejects_newer_schema() -> void:
	var migrated: Dictionary = SaveMigrations.migrate(0, {
		"stamina": 10.25,
		"weapon_id": "one_handed_sword",
		"meta": {"level": 2},
	})
	assert_true(migrated["ok"], "v0 is mappable to current schema")
	var body: Dictionary = migrated["body"]
	assert_true(body.has("state"), "v0 flat fields are wrapped into state")
	assert_almost_eq(float(body["state"]["stamina"]), 10.25, 0.001)
	assert_eq(int(body["meta"]["level"]), 2)

	var newer: Dictionary = SaveMigrations.migrate(
		SaveMigrations.CURRENT_VERSION + 1,
		{"state": {}}
	)
	assert_false(newer["ok"], "save from a newer build is not silently loaded")
	assert_eq(
		String(newer["reason"]),
		SaveMigrations.REASON_SCHEMA_TOO_NEW,
		"reason: schema_too_new"
	)

	var mislabelled: Dictionary = SaveMigrations.migrate(0, {"state": {"stamina": 1.0}})
	assert_false(mislabelled["ok"], "nested body marked as v0 is rejected, not emptied")


func test_newer_schema_file_is_not_loaded() -> void:
	var body: Dictionary = SaveSerializer.build_body(GameState, {})
	_write_text(
		SaveManager.get_slot_path(1),
		SaveSerializer.encode(body, SaveMigrations.CURRENT_VERSION + 1)
	)

	watch_signals(EventBus)
	assert_false(SaveManager.load_slot(1), "newer schema is refused")
	assert_signal_emitted_with_parameters(
		EventBus,
		"slot_corrupted",
		[1, SaveManager.LOAD_SCHEMA_TOO_NEW]
	)


func test_checksum_uses_sha256_hashing_context() -> void:
	assert_eq(
		SaveSerializer.sha256_hex("abc"),
		"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
		"known SHA-256 vector via HashingContext"
	)


func test_invalid_slot_number_is_rejected() -> void:
	watch_signals(EventBus)
	assert_false(SaveManager.save_slot(0), "slot 0 is invalid")
	assert_false(SaveManager.save_slot(4), "slot 4 is invalid")
	assert_false(SaveManager.load_slot(4), "invalid slot is not loaded")
	assert_signal_emitted(EventBus, "save_failed")


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "test helper can read %s" % path)
	return file.get_as_text()


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "test helper can write %s" % path)
	file.store_string(text)
	file.close()


func _cleanup_dir() -> void:
	var directory: DirAccess = DirAccess.open(TEST_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for directory_name: String in directory.get_directories():
		directory.remove(directory_name)
