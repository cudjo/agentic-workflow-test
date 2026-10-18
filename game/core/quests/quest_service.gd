class_name QuestService
extends RefCounted
## QuestService — выдача и завершение квестов (T-28, AC-06.1, EC-11).
##
## Единая точка жизненного цикла:
##   * `accept()` проверяет доступ фракции через
##     `FactionManager.get_quest_access()`; при отказе возвращает причину и
##     альтернативный квест союзной фракции (EC-11);
##   * `complete()` фиксирует квест в `Journal`, меняет репутацию
##     (`FactionManager.complete_quest()` → Δ-таблица T-27), начисляет опыт
##     (`GameState.award_quest_xp()`) и эмитит `EventBus.quest_completed`.
## Повторное завершение идемпотентно: ни репутация, ни опыт не начисляются
## дважды.

const QUESTS_DIR: String = "res://data/quests"

static var _cache: Dictionary = {}


## Данные квеста или null (некорректный ресурс не кэшируется).
static func get_quest(quest_id: StringName) -> QuestData:
	if quest_id.is_empty():
		return null
	if _cache.has(quest_id):
		return _cache[quest_id] as QuestData

	var direct_path: String = QUESTS_DIR.path_join("%s.tres" % String(quest_id))
	if ResourceLoader.exists(direct_path):
		var direct: QuestData = load(direct_path) as QuestData
		if direct != null and direct.is_valid() and direct.id == quest_id:
			_cache[quest_id] = direct
			return direct

	var directory: DirAccess = DirAccess.open(QUESTS_DIR)
	if directory == null:
		return null
	var file_names: PackedStringArray = directory.get_files()
	file_names.sort()
	for file_name: String in file_names:
		if not file_name.ends_with(".tres"):
			continue
		var candidate: QuestData = load(
			QUESTS_DIR.path_join(file_name)
		) as QuestData
		if candidate != null and candidate.id == quest_id and candidate.is_valid():
			_cache[quest_id] = candidate
			return candidate
	return null


## Название для журнала/диалогов; неизвестный квест показывает свой id,
## чтобы запись не теряла смысл.
static func get_quest_title(quest_id: StringName, language: String = "ru") -> String:
	var data: QuestData = get_quest(quest_id)
	if data == null:
		return String(quest_id)
	return data.get_title(language)


static func get_quest_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var directory: DirAccess = DirAccess.open(QUESTS_DIR)
	if directory == null:
		return ids
	var file_names: PackedStringArray = directory.get_files()
	file_names.sort()
	for file_name: String in file_names:
		if not file_name.ends_with(".tres"):
			continue
		var data: QuestData = load(QUESTS_DIR.path_join(file_name)) as QuestData
		if data != null and data.is_valid():
			ids.append(data.id)
	ids.sort()
	return ids


## Статус: `completed`, `active`, `available` (доступен к выдаче) или
## `unavailable` (низкая репутация/неизвестная фракция).
static func get_status(quest_id: StringName) -> StringName:
	if Journal.is_completed(quest_id):
		return &"completed"
	if Journal.is_active(quest_id):
		return &"active"
	return &"available" if can_accept(quest_id) else &"unavailable"


static func can_accept(quest_id: StringName) -> bool:
	if quest_id.is_empty():
		return false
	if Journal.is_active(quest_id) or Journal.is_completed(quest_id):
		return false
	return bool(FactionManager.get_quest_access(quest_id).get("available", false))


## Выдать квест. Результат:
## `{ok, quest_id, title, reason, message, faction_id,
##   alternative_faction_id, alternative_quest_id}`.
static func accept(quest_id: StringName, language: String = "ru") -> Dictionary:
	var title: String = get_quest_title(quest_id, language)
	var result: Dictionary = {
		"ok": false,
		"quest_id": quest_id,
		"title": title,
		"reason": "",
		"message": "",
		"faction_id": &"",
		"alternative_faction_id": &"",
		"alternative_quest_id": &"",
	}

	if quest_id.is_empty():
		result["reason"] = "unknown_quest"
		result["message"] = (
			"Unknown quest." if DialogueText.is_english(language) else "Неизвестный квест."
		)
		return result
	if Journal.is_completed(quest_id):
		result["reason"] = "already_completed"
		result["message"] = (
			"The quest is already complete."
			if DialogueText.is_english(language)
			else "Квест уже завершён."
		)
		return result
	if Journal.is_active(quest_id):
		result["reason"] = "already_active"
		result["message"] = (
			"The quest is already active."
			if DialogueText.is_english(language)
			else "Квест уже активен."
		)
		return result

	var access: Dictionary = FactionManager.get_quest_access(quest_id)
	result["faction_id"] = access.get("faction_id", &"")
	result["alternative_faction_id"] = access.get("alternative_faction_id", &"")
	result["alternative_quest_id"] = access.get("alternative_quest_id", &"")
	if not bool(access.get("available", false)):
		result["reason"] = "unavailable"
		result["message"] = str(access.get("reason", ""))
		return result

	Journal.start_quest(quest_id)
	result["ok"] = true
	EventBus.quest_started.emit(quest_id, title)
	return result


## Завершить квест. Результат:
## `{ok, quest_id, title, reason, reputation: Array[Dictionary], xp: Dictionary}`.
static func complete(quest_id: StringName, language: String = "ru") -> Dictionary:
	var title: String = get_quest_title(quest_id, language)
	var empty_reputation: Array[Dictionary] = []
	var result: Dictionary = {
		"ok": false,
		"quest_id": quest_id,
		"title": title,
		"reason": "",
		"reputation": empty_reputation,
		"xp": {},
	}

	if quest_id.is_empty():
		result["reason"] = "unknown_quest"
		return result
	if Journal.is_completed(quest_id):
		result["reason"] = "already_completed"
		return result

	# Журнал фиксирует завершение до внешних систем: T-24 увидит запись, даже
	# если у фракции нет Δ-строки или таблицы опыта.
	Journal.complete_quest(quest_id)
	var reputation: Array[Dictionary] = FactionManager.complete_quest(quest_id)
	var xp_result: Dictionary = GameState.award_quest_xp(quest_id)

	result["ok"] = true
	result["reputation"] = reputation
	result["xp"] = xp_result
	EventBus.quest_completed.emit(quest_id, title)
	return result


static func clear_cache() -> void:
	_cache.clear()
