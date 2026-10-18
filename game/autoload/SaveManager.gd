extends Node
## SaveManager — 3 слота в `user://saves/slot_{1..3}.json` (T-25, PLAN §3.4).
##
## Формат, checksum и перенос полей GameState — `core/save/save_serializer.gd`;
## версии/миграции — `core/save/save_migrations.gd`.
##
## Атомарность (EC-14): тело сначала пишется в `slot_N.json.tmp`, затем
## `DirAccess.rename` заменяет слот. Любая ошибка диска оставляет старый слот
## нетронутым, tmp удаляется, исключений наружу нет.
##
## Целостность (EC-07): SHA-256 не совпал / файл обрезан / JSON битый /
## схема новее поддерживаемой — слот не применяется к GameState, менеджер
## возвращает false и эмитит `EventBus.slot_corrupted(slot, reason)`.
##
## Ограничения места сохранения (только костёр, запрет в бою — T-22/EC-06)
## проверяет вызывающий UI; GameState.in_combat появится в T-26.
##
## `saves_dir` — публичный только для тестов; игровой код использует дефолт.

const SLOT_MIN: int = 1
const SLOT_MAX: int = 3
const DEFAULT_SAVES_DIR: String = "user://saves"
const SLOT_FILE_TEMPLATE: String = "slot_%d.json"
const TEMP_SUFFIX: String = ".tmp"

const LOAD_OK: String = "ok"
const LOAD_EMPTY: String = "empty"
const LOAD_CORRUPTED: String = "corrupted"
const LOAD_SCHEMA_TOO_NEW: String = "schema_too_new"
const LOAD_SCHEMA_UNSUPPORTED: String = "schema_unsupported"
const LOAD_IO_ERROR: String = "io_error"
const LOAD_INVALID_SLOT: String = "invalid_slot"

## Каталог слотов; переопределяется GUT-тестами на `user://...`.
var saves_dir: String = DEFAULT_SAVES_DIR


func _ready() -> void:
	_ensure_saves_dir()


## Сохраняет текущее состояние GameState в слот 1..3.
## `metadata` — зона/уровень/время для UI (см. `SaveSerializer.normalize_meta`).
func save_slot(slot: int, metadata: Dictionary = {}) -> bool:
	if not is_valid_slot(slot):
		_emit_save_failed(slot, LOAD_INVALID_SLOT)
		return false

	if not _ensure_saves_dir():
		_emit_save_failed(slot, LOAD_IO_ERROR)
		return false

	var state: Node = _game_state()
	if state == null:
		_emit_save_failed(slot, LOAD_IO_ERROR)
		return false

	var body: Dictionary = SaveSerializer.build_body(state, metadata)
	var text: String = SaveSerializer.encode(body)
	if not _write_atomic(get_slot_path(slot), text):
		_emit_save_failed(slot, LOAD_IO_ERROR)
		return false

	var bus: Node = _event_bus()
	if bus != null:
		bus.emit_signal("save_completed", slot)
	return true


## Загружает слот в GameState. Возвращает false для пустого/повреждённого/
## несовместимого слота, не меняя GameState (EC-07).
func load_slot(slot: int) -> bool:
	var result: Dictionary = read_slot(slot)
	if not bool(result.get("ok", false)):
		var reason: String = str(result.get("reason", LOAD_CORRUPTED))
		if _is_corruption_reason(reason):
			var bus: Node = _event_bus()
			if bus != null:
				bus.emit_signal("slot_corrupted", slot, reason)
		return false

	var state: Node = _game_state()
	if state == null:
		return false

	var body: Dictionary = result.get("body", {})
	var state_data: Dictionary = body.get("state", {})
	return SaveSerializer.apply_state(state, state_data)


## Читает и проверяет слот без применения к GameState.
## Возвращает `{ok, reason, schema_version, body}`; `body` уже мигрирован.
func read_slot(slot: int) -> Dictionary:
	if not is_valid_slot(slot):
		return {
			"ok": false,
			"reason": LOAD_INVALID_SLOT,
			"schema_version": 0,
			"body": {},
		}

	var path: String = get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"reason": LOAD_EMPTY,
			"schema_version": 0,
			"body": {},
		}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"reason": LOAD_IO_ERROR,
			"schema_version": 0,
			"body": {},
		}

	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return {
			"ok": false,
			"reason": LOAD_IO_ERROR,
			"schema_version": 0,
			"body": {},
		}

	return SaveSerializer.decode(text)


## Метаданные слота для меню сохранений (T-23): зона, уровень, время,
## признак повреждения. Никогда не грузит и не меняет GameState.
func get_slot_metadata(slot: int) -> Dictionary:
	var info: Dictionary = {
		"slot": slot,
		"exists": false,
		"valid": false,
		"corrupted": false,
		"reason": LOAD_EMPTY,
		"schema_version": 0,
		"zone_id": "",
		"zone_name": "",
		"level": 0,
		"play_time": 0.0,
		"saved_at_unix": 0,
	}

	if not is_valid_slot(slot):
		info["reason"] = LOAD_INVALID_SLOT
		return info

	var path: String = get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return info

	info["exists"] = true
	var result: Dictionary = read_slot(slot)
	if not bool(result.get("ok", false)):
		var reason: String = str(result.get("reason", LOAD_CORRUPTED))
		info["reason"] = reason
		info["corrupted"] = reason == LOAD_CORRUPTED
		info["schema_version"] = int(result.get("schema_version", 0))
		return info

	info["valid"] = true
	info["reason"] = LOAD_OK
	info["schema_version"] = int(result.get("schema_version", 0))
	var body: Dictionary = result.get("body", {})
	var meta: Dictionary = body.get("meta", {})
	info["zone_id"] = str(meta.get("zone_id", ""))
	info["zone_name"] = str(meta.get("zone_name", ""))
	info["level"] = int(meta.get("level", 0))
	info["play_time"] = float(meta.get("play_time", 0.0))
	info["saved_at_unix"] = int(meta.get("saved_at_unix", 0))
	return info


func has_slot(slot: int) -> bool:
	return is_valid_slot(slot) and FileAccess.file_exists(get_slot_path(slot))


## Удаляет слот и возможный tmp-файл. Возвращает true, если слот исчез.
func delete_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		return false

	var directory: DirAccess = DirAccess.open(saves_dir)
	if directory == null:
		return false

	var file_name: String = SLOT_FILE_TEMPLATE % slot
	if directory.file_exists(file_name):
		directory.remove(file_name)
	# Остаток неудачной записи не должен переживать удаление слота.
	if directory.file_exists(file_name + TEMP_SUFFIX):
		directory.remove(file_name + TEMP_SUFFIX)

	return not FileAccess.file_exists(get_slot_path(slot))


func get_slot_path(slot: int) -> String:
	return saves_dir.path_join(SLOT_FILE_TEMPLATE % slot)


static func is_valid_slot(slot: int) -> bool:
	return slot >= SLOT_MIN and slot <= SLOT_MAX


## Единственное место записи на диск: tmp → rename поверх (EC-14).
func _write_atomic(path: String, text: String) -> bool:
	var temp_path: String = path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file(temp_path)
		return false

	var directory: DirAccess = DirAccess.open(saves_dir)
	if directory == null:
		_remove_file(temp_path)
		return false

	# rename поверх: старый слот заменяется только целиком и только здесь.
	var rename_error: Error = directory.rename(temp_path.get_file(), path.get_file())
	if rename_error != OK:
		_remove_file(temp_path)
		return false

	return true


func _ensure_saves_dir() -> bool:
	var absolute: String = ProjectSettings.globalize_path(saves_dir)
	if DirAccess.dir_exists_absolute(absolute):
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute)
	return error == OK or DirAccess.dir_exists_absolute(absolute)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _game_state() -> Node:
	return get_node_or_null("/root/GameState")


func _event_bus() -> Node:
	return get_node_or_null("/root/EventBus")


func _emit_save_failed(slot: int, reason: String) -> void:
	var bus: Node = _event_bus()
	if bus != null:
		bus.emit_signal("save_failed", slot, reason)


static func _is_corruption_reason(reason: String) -> bool:
	return reason == LOAD_CORRUPTED \
		or reason == LOAD_SCHEMA_TOO_NEW \
		or reason == LOAD_SCHEMA_UNSUPPORTED
