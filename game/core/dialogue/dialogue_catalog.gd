class_name DialogueCatalog
extends RefCounted
## DialogueCatalog — загрузка диалогов из `data/dialogue/*.tres` (T-28).
##
## Кэш на время сессии: диалоги неизменяемы. Некорректный ресурс не попадает
## в кэш и возвращает null — NPC остаётся без диалога, но игра не падает.
## Поиск: сначала `<id>.tres`, затем перебор файлов по полю `id`.

const DIALOGUE_DIR: String = "res://data/dialogue"

static var _cache: Dictionary = {}


## Диалог по id или null. Ошибки данных логируются один раз на загрузку.
static func load_dialogue(dialogue_id: StringName) -> DialogueData:
	if dialogue_id.is_empty():
		return null
	if _cache.has(dialogue_id):
		return _cache[dialogue_id] as DialogueData

	var direct_path: String = DIALOGUE_DIR.path_join("%s.tres" % String(dialogue_id))
	if ResourceLoader.exists(direct_path):
		var direct: DialogueData = load(direct_path) as DialogueData
		if direct != null and direct.is_valid() and direct.id == dialogue_id:
			_cache[dialogue_id] = direct
			return direct

	var directory: DirAccess = DirAccess.open(DIALOGUE_DIR)
	if directory == null:
		push_warning("DialogueCatalog: cannot open %s" % DIALOGUE_DIR)
		return null

	var file_names: PackedStringArray = directory.get_files()
	file_names.sort()
	for file_name: String in file_names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = DIALOGUE_DIR.path_join(file_name)
		var candidate: DialogueData = load(path) as DialogueData
		if candidate == null:
			continue
		if candidate.id == dialogue_id and candidate.is_valid():
			_cache[dialogue_id] = candidate
			return candidate
	push_warning("DialogueCatalog: dialogue '%s' not found" % dialogue_id)
	return null


## Все валидные диалоги, отсортированные по id (для тестов/инструментов).
static func get_dialogue_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var directory: DirAccess = DirAccess.open(DIALOGUE_DIR)
	if directory == null:
		return ids

	var file_names: PackedStringArray = directory.get_files()
	file_names.sort()
	for file_name: String in file_names:
		if not file_name.ends_with(".tres"):
			continue
		var dialogue: DialogueData = load(
			DIALOGUE_DIR.path_join(file_name)
		) as DialogueData
		if dialogue != null and dialogue.is_valid():
			ids.append(dialogue.id)
	ids.sort()
	return ids


static func clear_cache() -> void:
	_cache.clear()
