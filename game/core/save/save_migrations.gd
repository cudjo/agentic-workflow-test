class_name SaveMigrations
extends RefCounted
## SaveMigrations — версионирование и миграция тела сейва (T-25, PLAN §3.4).
##
## Формат файла и сериализация полей — в `save_serializer.gd`. Здесь живёт
## только контракт версий: сейв новее `CURRENT_VERSION` не грузится
## (`schema_too_new`), чтобы старый билд не потерял незнакомые поля молча.
##
## Контракт расширения для будущих задач (T-26 HP/corpse, T-27 фракции,
## T-29 квесты и т.д.):
## 1. Новое поле добавляется в `SaveSerializer.serialize_state()` и
##    `SaveSerializer.apply_state()` (только реально существующие поля
##    `GameState`; отсутствующие в сейве ключи не должны ломать загрузку).
## 2. `CURRENT_VERSION` увеличивается на 1.
## 3. В `migrate()` добавляется следующий шаг (`_v1_to_v2`, ...): в тело
##    версии N вставляется дефолт нового поля (значение из GameState/данных),
##    все существующие ключи сохраняются без изменений.
## 4. GUT: тело версии N → `migrate()` → поле присутствует; файл старой
##    версии загружается и восстанавливает состояние.
##
## Версия 0 — прототип до T-25: поля состояния лежали на верхнем уровне тела
## (`{"stamina": ..., "weapon_id": ...}`). Версия 1 — T-25 (stamina/weapon).
## Версия 2 — T-30: прогресс боссов, отложенные награды и валюта.

const CURRENT_VERSION: int = 2

const REASON_OK: String = "ok"
const REASON_SCHEMA_TOO_NEW: String = "schema_too_new"
const REASON_SCHEMA_UNSUPPORTED: String = "schema_unsupported"


## Приводит тело сейва версии `schema_version` к `CURRENT_VERSION`.
## Возвращает `{ok: bool, reason: String, body: Dictionary}`.
## При ошибке тело пустое — вызывающий код обязан отказать в загрузке (EC-07).
static func migrate(schema_version: int, body: Dictionary) -> Dictionary:
	if schema_version > CURRENT_VERSION:
		return {
			"ok": false,
			"reason": REASON_SCHEMA_TOO_NEW,
			"body": {},
		}
	if schema_version < 0:
		return {
			"ok": false,
			"reason": REASON_SCHEMA_UNSUPPORTED,
			"body": {},
		}

	var migrated: Dictionary = body.duplicate(true)
	var version: int = schema_version

	if version == 0:
		# Защита от повреждённой версии в заголовке: v1-тело, помеченное как v0,
		# не должно молча потерять вложенное состояние (checksum покрывает только
		# body, поэтому версию проверяем по форме).
		if body.has("state"):
			return {
				"ok": false,
				"reason": REASON_SCHEMA_UNSUPPORTED,
				"body": {},
			}
		migrated = _v0_to_v1(migrated)
		version = 1

	if version == 1:
		migrated = _v1_to_v2(migrated)
		version = 2

	if version != CURRENT_VERSION:
		return {
			"ok": false,
			"reason": REASON_SCHEMA_UNSUPPORTED,
			"body": {},
		}

	return {
		"ok": true,
		"reason": REASON_OK,
		"body": migrated,
	}


## v0 → v1: плоские поля состояния переносятся в `state`, метаданные остаются.
static func _v0_to_v1(body: Dictionary) -> Dictionary:
	var state: Dictionary = {}
	for key: String in ["stamina", "weapon_id", "weapon_path"]:
		if body.has(key):
			state[key] = body[key]

	var meta: Variant = body.get("meta", {})
	if typeof(meta) != TYPE_DICTIONARY:
		meta = {}

	return {
		"state": state,
		"meta": meta,
	}


## v1 → v2: прогресс боссов T-30 (EC-09). Старые сейвы получают пустые
## значения; существующие поля состояния не меняются.
static func _v1_to_v2(body: Dictionary) -> Dictionary:
	var migrated: Dictionary = body.duplicate(true)
	var state_value: Variant = migrated.get("state", {})
	var state: Dictionary = state_value if state_value is Dictionary else {}
	if not state.has("bosses_defeated"):
		state["bosses_defeated"] = []
	if not state.has("boss_rewards_pending"):
		state["boss_rewards_pending"] = {}
	if not state.has("currency"):
		state["currency"] = 0
	migrated["state"] = state
	return migrated
