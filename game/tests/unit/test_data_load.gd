extends GutTest
## Экспорт-контракт загрузки данных.
##
## В экспортированном билде Godot упаковывает `*.tres` как `*.tres.remap`,
## поэтому загрузчики, перебирающие каталог через `DirAccess.get_files()`,
## находят 0 ресурсов. Все загрузчики данных используют явные манифесты путей
## (`*_PATHS`); эти тесты проверяют, что манифесты:
##   * полны — покрывают ровно все `.tres` в каталоге (editor);
##   * грузятся одинаково и не зависят от перебора каталога;
##   * идемпотентны — повторная загрузка не дублирует записи.

const FACTIONS_DIR: String = "res://data/factions"
const DIALOGUE_DIR: String = "res://data/dialogue"
const QUESTS_DIR: String = "res://data/quests"
const ZONES_DIR: String = "res://data/zones"
const WEAPONS_DIR: String = "res://data/weapons"
const TEACHERS_DIR: String = "res://data/balance/teachers"

const ZONE_TEMPLATE: String = "res://data/zones/zone_template.tres"

const FACTION_IDS: Array[StringName] = [&"ash", &"free", &"order"]
const DIALOGUE_IDS: Array[StringName] = [&"elder_lira", &"order_guard", &"quartermaster_helga"]
const QUEST_IDS: Array[StringName] = [
	&"quest_ash_ritual",
	&"quest_clear_swamp",
	&"quest_free_smuggle",
	&"quest_guard_patrol",
]
const WEAPON_IDS: Array[String] = ["light_dagger", "one_handed_sword", "two_handed_axe"]
const TEACHER_IDS: Array[StringName] = [&"elder", &"huntress", &"quartermaster"]


# ------------------------------------------------------------------------------
# Манифесты полны и валидны
# ------------------------------------------------------------------------------

func test_manifests_match_data_directories_in_editor() -> void:
	if not OS.has_feature("editor"):
		pass_test("каталог данных доступен только в editor-сборке")
		return

	_assert_manifest_complete(FactionManager.FACTION_PATHS, FACTIONS_DIR, [])
	_assert_manifest_complete(DialogueCatalog.DIALOGUE_PATHS, DIALOGUE_DIR, [])
	_assert_manifest_complete(QuestService.QUEST_PATHS, QUESTS_DIR, [])
	_assert_manifest_complete(WorldMapModel.ZONE_PATHS, ZONES_DIR, [ZONE_TEMPLATE])
	_assert_manifest_complete(SaveSerializer.WEAPON_PATHS, WEAPONS_DIR, [])
	_assert_manifest_complete(Teacher.TEACHER_PATHS, TEACHERS_DIR, [])


func test_manifest_paths_are_unique_and_loadable() -> void:
	for path: String in _all_manifest_paths():
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		assert_not_null(load(path), "%s loads" % path)

	for manifest: Array in [
		FactionManager.FACTION_PATHS,
		DialogueCatalog.DIALOGUE_PATHS,
		QuestService.QUEST_PATHS,
		WorldMapModel.ZONE_PATHS,
		SaveSerializer.WEAPON_PATHS,
		Teacher.TEACHER_PATHS,
	]:
		var paths: Array = manifest
		var unique: Dictionary = {}
		for path: String in paths:
			assert_false(unique.has(path), "%s is listed once" % path)
			unique[path] = true


# ------------------------------------------------------------------------------
# Загрузка идёт по путям (не по перебору каталога)
# ------------------------------------------------------------------------------

func test_factions_load_by_explicit_paths() -> void:
	assert_eq(FactionManager.FACTION_PATHS.size(), 3, "манифест фракций")
	assert_eq(FactionManager.get_faction_count(), 3, "3 фракции загружены")
	for faction_id: StringName in FACTION_IDS:
		assert_not_null(FactionManager.get_faction(faction_id), "%s загружена" % faction_id)


func test_faction_reload_is_idempotent() -> void:
	var before: Array[StringName] = FactionManager.get_faction_ids()
	# Повторная загрузка — тот же состав, без дублей.
	FactionManager._load_factions()
	FactionManager._load_factions()
	assert_eq(FactionManager.get_faction_count(), 3, "повторная загрузка не дублирует")
	assert_eq(FactionManager.get_faction_ids(), before, "порядок id стабилен")


func test_dialogues_and_quests_load_by_explicit_paths() -> void:
	DialogueCatalog.clear_cache()
	QuestService.clear_cache()

	var dialogue_ids: Array[StringName] = DialogueCatalog.get_dialogue_ids()
	var quest_ids: Array[StringName] = QuestService.get_quest_ids()
	assert_eq(dialogue_ids.size(), 3, "3 диалога загружены")
	assert_eq(quest_ids.size(), 4, "4 квеста загружены")

	for dialogue_id: StringName in DIALOGUE_IDS:
		assert_not_null(DialogueCatalog.load_dialogue(dialogue_id), "%s загружается" % dialogue_id)
	for quest_id: StringName in QUEST_IDS:
		assert_not_null(QuestService.get_quest(quest_id), "%s загружается" % quest_id)

	# Повтор после сброса кэша — тот же результат.
	DialogueCatalog.clear_cache()
	QuestService.clear_cache()
	assert_eq(DialogueCatalog.get_dialogue_ids(), dialogue_ids, "повторный вызов не дублирует")
	assert_eq(QuestService.get_quest_ids(), quest_ids, "повторный вызов не дублирует")


func test_zones_load_by_explicit_paths() -> void:
	var model: WorldMapModel = WorldMapModel.new()
	model.reload()
	var first_ids: Array[StringName] = model.get_zone_ids()
	assert_eq(model.zones.size(), 5, "5 зон загружены")
	assert_eq(first_ids.size(), 5, "id зон уникальны")
	assert_false(first_ids.has(&"zone_template"), "шаблон не является зоной")

	model.reload()
	assert_eq(model.zones.size(), 5, "повторная загрузка не дублирует")
	assert_eq(model.get_zone_ids(), first_ids, "порядок зон стабилен")


func test_weapons_resolve_by_path_without_directory_scan() -> void:
	for weapon_id: String in WEAPON_IDS:
		var weapon: WeaponData = SaveSerializer.resolve_weapon(weapon_id, "")
		assert_not_null(weapon, "%s найден по id" % weapon_id)
		if weapon != null:
			assert_eq(String(weapon.id), weapon_id, "%s: id совпадает" % weapon_id)


func test_teachers_load_by_explicit_paths() -> void:
	for teacher_id: StringName in TEACHER_IDS:
		var teacher: Teacher = Teacher.new()
		teacher.teacher_id = teacher_id
		var data: TeacherData = teacher.get_data()
		assert_not_null(data, "%s загружается по id" % teacher_id)
		if data != null:
			assert_eq(data.id, teacher_id, "%s: id совпадает" % teacher_id)
		teacher.free()


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _all_manifest_paths() -> Array[String]:
	var paths: Array[String] = []
	for manifest: Array in [
		FactionManager.FACTION_PATHS,
		DialogueCatalog.DIALOGUE_PATHS,
		QuestService.QUEST_PATHS,
		WorldMapModel.ZONE_PATHS,
		SaveSerializer.WEAPON_PATHS,
		Teacher.TEACHER_PATHS,
	]:
		for path: String in manifest:
			paths.append(path)
	return paths


func _assert_manifest_complete(
	manifest: Array[String], dir_path: String, excluded: Array
) -> void:
	var manifest_sorted: Array[String] = manifest.duplicate()
	manifest_sorted.sort()
	assert_eq(
		manifest_sorted,
		_resources_in_dir(dir_path, excluded),
		"манифест покрывает ровно все .tres в %s" % dir_path
	)


func _resources_in_dir(dir_path: String, excluded: Array) -> Array[String]:
	var paths: Array[String] = []
	var directory: DirAccess = DirAccess.open(dir_path)
	if directory == null:
		return paths
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var path: String = dir_path.path_join(file_name)
		if excluded.has(path):
			continue
		paths.append(path)
	paths.sort()
	return paths
