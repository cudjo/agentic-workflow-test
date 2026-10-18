extends GutTest
## T-25 — сохранения: round-trip, checksum, миграции, атомарность
## (PLAN §3.4, AC-05.1, EC-07/EC-14). T-26 — schema v3: HP, инвентарь,
## способности, смерть/corpse run и чекпоинт костра. T-27 — schema v4:
## репутация фракций и выбранная фракция (US-06). T-29 — schema v5:
## характеристики, очки обучения, уровень и опыт (US-08).
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
var _original_hp: float = 0.0
var _original_currency: int = 0
var _original_inventory: Array[StringName] = []
var _original_abilities: Array[StringName] = []
var _original_death_active: bool = false
var _original_corpse: Dictionary = {}
var _original_respawn: Dictionary = {}
var _original_active_slot: int = 0
var _original_in_combat: bool = false
var _original_factions: Dictionary = {}
var _original_chosen_faction: StringName = &""
var _original_stats: Dictionary = {}
var _original_learning_points: int = 0
var _original_level: int = 1
var _original_xp: int = 0


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
	_original_hp = GameState.hp
	_original_currency = GameState.currency
	_original_inventory = GameState.get_inventory()
	_original_abilities = GameState.get_abilities()
	_original_death_active = GameState.death_active
	_original_corpse = GameState.get_corpse_info()
	_original_respawn = {
		"bonfire": GameState.respawn_bonfire,
		"zone_id": GameState.respawn_zone_id,
		"position": GameState.respawn_position,
	}
	_original_active_slot = GameState.active_slot
	_original_in_combat = GameState.in_combat
	_original_factions = GameState.get_all_faction_reputation()
	_original_chosen_faction = GameState.chosen_faction
	_original_stats = GameState.get_stats()
	_original_learning_points = GameState.learning_points
	_original_level = GameState.level
	_original_xp = GameState.xp

	# Каждый тест начинает с чистого состояния смерти/HP, чтобы не наследовать
	# corpse-метку предыдущего теста.
	GameState.clear_corpse()
	GameState.death_active = false
	GameState.set_in_combat(false)
	_cleanup_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))


func after_each() -> void:
	GameState.restore_progression(
		_original_stats,
		_original_learning_points,
		_original_level,
		_original_xp
	)
	GameState.stamina = _original_stamina
	if _original_weapon != null:
		GameState.set_weapon(_original_weapon)
	GameState.set_hp(_original_hp)
	GameState.currency = _original_currency
	GameState.restore_inventory(_original_inventory)
	GameState.restore_abilities(_original_abilities)
	GameState.restore_death_state(
		_original_death_active,
		bool(_original_corpse.get("active", false)),
		StringName(str(_original_corpse.get("zone_id", ""))),
		_original_corpse.get("position", Vector2.ZERO),
		_original_corpse.get("items", []),
		int(_original_corpse.get("currency", 0)),
		bool(_original_corpse.get("lost", false))
	)
	GameState.restore_respawn_bonfire(
		StringName(str(_original_respawn.get("bonfire", ""))),
		StringName(str(_original_respawn.get("zone_id", ""))),
		_original_respawn.get("position", Vector2.ZERO)
	)
	GameState.active_slot = _original_active_slot
	GameState.set_in_combat(_original_in_combat)
	GameState.restore_factions(_original_factions, _original_chosen_faction)
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


func test_round_trip_restores_hp_inventory_abilities_and_death_state() -> void:
	# T-26 (schema v3): всё, что нужно corpse run и EC-04.
	GameState.clear_abilities()
	GameState.set_hp(37.5)
	GameState.restore_inventory([&"ash_shard"])
	GameState.currency = 12
	GameState.death_active = true
	GameState.drop_corpse(&"zone_02_swamp", Vector2(64.0, -32.0))
	GameState.restore_inventory([&"bone_charm"])
	GameState.add_ability(&"double_jump")
	GameState.set_respawn_bonfire(
		&"zone_01_village",
		&"hub",
		Vector2(112.0, 212.0)
	)

	assert_true(SaveManager.save_slot(1, {"zone_id": "zone_02_swamp"}), "death state saves")

	# Ломаем всё, чтобы загрузка была заметна.
	GameState.set_hp(100.0)
	GameState.clear_inventory()
	GameState.clear_abilities()
	GameState.clear_corpse()
	GameState.death_active = false
	GameState.restore_respawn_bonfire(&"", &"", Vector2.ZERO)

	assert_true(SaveManager.load_slot(1), "schema v3 slot loads")
	assert_almost_eq(GameState.hp, 37.5, 0.001, "HP is restored (AC-05.1)")
	assert_eq(GameState.get_inventory(), [&"bone_charm"], "inventory is restored")
	assert_true(
		GameState.has_ability(&"double_jump"),
		"abilities are restored (contract T-06/T-26)"
	)

	assert_true(GameState.death_active, "pending death is persisted (EC-04)")
	assert_true(GameState.has_corpse(), "corpse marker is persisted")
	assert_eq(GameState.corpse_zone_id, &"zone_02_swamp", "corpse zone is restored")
	assert_eq(GameState.corpse_position, Vector2(64.0, -32.0), "corpse position is restored")
	assert_eq(GameState.corpse_items, [&"ash_shard"], "corpse items are restored")
	assert_eq(GameState.corpse_currency, 12, "corpse currency is restored")
	assert_false(GameState.corpse_lost, "corpse is still recoverable")

	assert_eq(GameState.respawn_bonfire, &"zone_01_village/hub", "respawn bonfire id")
	assert_eq(GameState.respawn_zone_id, &"zone_01_village", "respawn zone id")
	assert_eq(GameState.respawn_position, Vector2(112.0, 212.0), "respawn position")
	assert_eq(GameState.active_slot, 1, "SaveManager remembers the active slot")


func test_v2_save_is_migrated_to_current_with_defaults() -> void:
	var v2_body: Dictionary = {
		"state": {
			"stamina": 33.5,
			"weapon_id": "one_handed_sword",
			"weapon_path": SWORD_PATH,
			"bosses_defeated": ["zone_01_boss"],
			"boss_rewards_pending": {},
			"currency": 7,
		},
		"meta": {"zone_id": "zone_01_village", "level": 2},
	}

	var migrated: Dictionary = SaveMigrations.migrate(2, v2_body)
	assert_true(migrated["ok"], "v2 is mappable to the current schema")
	var state: Dictionary = migrated["body"]["state"]
	assert_almost_eq(float(state["hp"]), GameState.hp_max, 0.001, "hp defaults to max HP")
	assert_eq(state["inventory"], [], "inventory defaults to empty")
	assert_eq(state["abilities"], [], "abilities default to empty")
	assert_false(bool(state["death_active"]), "no pending death in an old save")
	assert_false(bool(state["death_corpse_active"]), "no corpse in an old save")
	assert_eq(state["death_items"], [], "no corpse items")
	assert_eq(int(state["death_currency"]), 0, "no corpse currency")
	assert_eq(str(state["respawn_bonfire"]), "", "no checkpoint")
	assert_eq(state["factions"], {}, "factions default to neutral (T-27, v4)")
	assert_eq(str(state["chosen_faction"]), "", "no chosen faction in an old save")
	assert_eq(int(state["stats"]["strength"]), 5, "stats default to start values (T-29, v5)")
	assert_eq(int(state["learning_points"]), 0, "learning points default to 0")
	assert_eq(int(state["level"]), 1, "level defaults to 1")
	assert_eq(int(state["xp"]), 0, "XP defaults to 0")
	assert_almost_eq(float(state["stamina"]), 33.5, 0.001, "existing fields survive")
	assert_eq(state["currency"], 7, "v2 currency survives")

	# Файл версии 2 реально загружается и не ломает GameState.
	_write_text(SaveManager.get_slot_path(1), SaveSerializer.encode(v2_body, 2))
	GameState.set_hp(1.0)
	GameState.clear_inventory()
	GameState.clear_abilities()
	GameState.clear_corpse()
	GameState.restore_factions({"order": 40}, &"order")
	assert_true(SaveManager.load_slot(1), "v2 slot loads through migration")
	assert_almost_eq(GameState.hp, GameState.hp_max, 0.001, "migrated save has full HP")
	assert_eq(GameState.get_inventory(), [], "migrated save has empty inventory")
	assert_eq(GameState.get_abilities(), [], "migrated save has no abilities")
	assert_false(GameState.death_active, "migrated save has no pending death")
	assert_almost_eq(GameState.stamina, 33.5, 0.001, "v2 stamina is restored")
	assert_eq(GameState.currency, 7, "v2 currency is restored")
	assert_eq(
		GameState.get_all_faction_reputation(),
		{},
		"migrated old save resets faction reputation to neutral"
	)
	assert_eq(GameState.chosen_faction, &"", "migrated old save has no faction choice")
	assert_eq(GameState.get_stat(&"strength"), 5, "migrated old save has start stats")
	assert_eq(GameState.learning_points, 0, "migrated old save has no learning points")
	assert_eq(GameState.level, 1, "migrated old save starts at level 1")
	assert_eq(GameState.xp, 0, "migrated old save has no XP")


func test_v3_save_is_migrated_to_current_with_faction_defaults() -> void:
	var v3_body: Dictionary = {
		"state": {
			"stamina": 12.0,
			"weapon_id": "light_dagger",
			"weapon_path": DAGGER_PATH,
			"bosses_defeated": [],
			"boss_rewards_pending": {},
			"currency": 3,
			"hp": 41.0,
			"inventory": ["ash_shard"],
			"abilities": ["double_jump"],
			"death_active": false,
			"death_corpse_active": false,
			"death_zone_id": "",
			"death_position": {"x": 0.0, "y": 0.0},
			"death_items": [],
			"death_currency": 0,
			"death_lost": false,
			"respawn_bonfire": "",
			"respawn_zone_id": "",
			"respawn_position": {"x": 0.0, "y": 0.0},
		},
		"meta": {"zone_id": "zone_02_swamp", "level": 3},
	}

	var migrated: Dictionary = SaveMigrations.migrate(3, v3_body)
	assert_true(migrated["ok"], "v3 is mappable to the current schema")
	var state: Dictionary = migrated["body"]["state"]
	assert_eq(state["factions"], {}, "factions default to empty")
	assert_eq(str(state["chosen_faction"]), "", "chosen faction defaults to empty")
	assert_eq(int(state["stats"]["endurance"]), 5, "stats default to start values (v5)")
	assert_eq(int(state["learning_points"]), 0, "learning points default to 0")
	assert_eq(int(state["level"]), 1, "level defaults to 1")
	assert_eq(int(state["xp"]), 0, "XP defaults to 0")
	assert_almost_eq(float(state["hp"]), 41.0, 0.001, "v3 HP survives")
	assert_eq(state["abilities"], ["double_jump"], "v3 abilities survive")
	assert_eq(int(state["currency"]), 3, "v3 currency survives")

	_write_text(SaveManager.get_slot_path(2), SaveSerializer.encode(v3_body, 3))
	GameState.restore_factions({"free": 25}, &"free")
	assert_true(SaveManager.load_slot(2), "v3 slot loads through v4 migration")
	assert_eq(
		GameState.get_all_faction_reputation(),
		{},
		"migrated v3 save has neutral faction reputation"
	)
	assert_eq(GameState.chosen_faction, &"", "migrated v3 save has no chosen faction")
	assert_almost_eq(GameState.hp, 41.0, 0.001, "migrated v3 HP is restored")


func test_round_trip_restores_faction_reputation_and_choice() -> void:
	GameState.restore_factions({
		&"order": 15,
		&"free": -5,
		&"ash": 30,
	}, &"ash")

	assert_true(SaveManager.save_slot(1, {"zone_id": "zone_04_ruins"}), "factions save")

	GameState.reset_factions()
	assert_eq(GameState.get_faction_reputation(&"order"), 0, "state is cleared before load")

	assert_true(SaveManager.load_slot(1), "schema v4 slot loads")
	assert_eq(GameState.get_faction_reputation(&"order"), 15, "order reputation is restored")
	assert_eq(GameState.get_faction_reputation(&"free"), -5, "free reputation is restored")
	assert_eq(GameState.get_faction_reputation(&"ash"), 30, "ash reputation is restored")
	assert_eq(GameState.chosen_faction, &"ash", "chosen faction is restored (US-06)")

	var raw: String = _read_text(SaveManager.get_slot_path(1))
	assert_true(raw.contains("\"factions\":{"), "save body carries the factions map")
	assert_true(raw.contains("\"chosen_faction\":\"ash\""), "save body carries chosen_faction")


func test_v4_save_is_migrated_to_v5_with_progression_defaults() -> void:
	var v4_body: Dictionary = {
		"state": {
			"stamina": 21.0,
			"weapon_id": "one_handed_sword",
			"weapon_path": SWORD_PATH,
			"bosses_defeated": [],
			"boss_rewards_pending": {},
			"currency": 4,
			"hp": 55.0,
			"inventory": [],
			"abilities": [],
			"death_active": false,
			"death_corpse_active": false,
			"death_zone_id": "",
			"death_position": {"x": 0.0, "y": 0.0},
			"death_items": [],
			"death_currency": 0,
			"death_lost": false,
			"respawn_bonfire": "",
			"respawn_zone_id": "",
			"respawn_position": {"x": 0.0, "y": 0.0},
			"factions": {},
			"chosen_faction": "",
		},
		"meta": {"zone_id": "zone_01_village", "level": 2},
	}

	var migrated: Dictionary = SaveMigrations.migrate(4, v4_body)
	assert_true(migrated["ok"], "v4 is mappable to v5")
	var state: Dictionary = migrated["body"]["state"]
	assert_almost_eq(float(state["stats"]["strength"]), 5.0, 0.001, "strength default")
	assert_almost_eq(float(state["stats"]["dexterity"]), 5.0, 0.001, "dexterity default")
	assert_almost_eq(float(state["stats"]["endurance"]), 5.0, 0.001, "endurance default")
	assert_almost_eq(float(state["stats"]["health"]), 5.0, 0.001, "health default")
	assert_eq(int(state["learning_points"]), 0, "learning points default to 0")
	assert_eq(int(state["level"]), 1, "level defaults to 1")
	assert_eq(int(state["xp"]), 0, "XP defaults to 0")
	assert_almost_eq(float(state["hp"]), 55.0, 0.001, "v4 HP survives")
	assert_eq(int(state["currency"]), 4, "v4 currency survives")

	# Реальный файл v4 загружается и даёт стартовую прогрессию.
	_write_text(SaveManager.get_slot_path(1), SaveSerializer.encode(v4_body, 4))
	GameState.restore_progression({"strength": 12, "health": 9}, 9, 5, 900)
	assert_true(SaveManager.load_slot(1), "v4 slot loads through v5 migration")
	assert_eq(GameState.get_stat(&"strength"), 5, "migrated save resets to start stats")
	assert_eq(GameState.get_stat(&"health"), 5, "all stats are at their start values")
	assert_eq(GameState.learning_points, 0, "migrated save has no learning points")
	assert_eq(GameState.level, 1, "migrated save starts at level 1")
	assert_eq(GameState.xp, 0, "migrated save has no XP")
	assert_almost_eq(GameState.hp, 55.0, 0.001, "v4 HP is restored")


func test_round_trip_restores_progression() -> void:
	GameState.restore_progression(
		{"strength": 9, "dexterity": 7, "endurance": 6, "health": 8},
		5,
		3,
		300
	)

	assert_true(SaveManager.save_slot(1, {"zone_id": "zone_03_mountains"}), "progression saves")
	assert_eq(
		int(SaveManager.get_slot_metadata(1)["level"]),
		3,
		"slot metadata picks the level from GameState"
	)

	GameState.reset_progression()
	assert_eq(GameState.get_stat(&"strength"), 5, "state is cleared before load")
	assert_eq(GameState.learning_points, 0, "learning points are cleared")
	assert_eq(GameState.level, 1, "level is cleared")

	assert_true(SaveManager.load_slot(1), "schema v5 slot loads")
	assert_eq(GameState.get_stat(&"strength"), 9, "strength is restored (US-08)")
	assert_eq(GameState.get_stat(&"dexterity"), 7, "dexterity is restored")
	assert_eq(GameState.get_stat(&"endurance"), 6, "endurance is restored")
	assert_eq(GameState.get_stat(&"health"), 8, "health is restored")
	assert_eq(GameState.learning_points, 5, "learning points are restored")
	assert_eq(GameState.level, 3, "level is restored")
	assert_eq(GameState.xp, 300, "XP is restored")
	assert_almost_eq(GameState.hp_max, 115.0, 0.001, "health bonus applies after load")

	var raw: String = _read_text(SaveManager.get_slot_path(1))
	assert_true(raw.contains("\"stats\":{"), "save body carries stats")
	assert_true(raw.contains("\"learning_points\":5"), "save body carries learning points")
	assert_true(raw.contains("\"level\":3"), "save body carries level")
	assert_true(raw.contains("\"xp\":300"), "save body carries XP")


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
