class_name SaveMigrations
extends RefCounted
## SaveMigrations — версионирование и миграция тела сейва (T-25, PLAN §3.4).
##
## Формат файла и сериализация полей — в `save_serializer.gd`. Здесь живёт
## только контракт версий: сейв новее `CURRENT_VERSION` не грузится
## (`schema_too_new`), чтобы старый билд не потерял незнакомые поля молча.
##
## Контракт расширения для будущих задач (T-26 HP/corpse, T-27 фракции,
## T-29 прогрессия и т.д.):
## 1. Новое поле GameState добавляется в `SaveSerializer.serialize_state()` и
##    `SaveSerializer.apply_state()`; новый прогресс мира (зоны/gates/журнал) —
##    в `SaveSerializer.serialize_session()`/`apply_session()` (только реально
##    существующие поля владельца; отсутствующие в сейве ключи не должны
##    ломать загрузку).
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
## Версия 3 — T-26: HP, инвентарь, способности, смерть/corpse run (EC-04) и
## чекпоинт костра.
## Версия 4 — T-27: репутация фракций (`factions`) и выбранная фракция
## (`chosen_faction`).
## Версия 5 — T-29: характеристики (`stats`), очки обучения
## (`learning_points`), уровень (`level`) и опыт (`xp`).
## Версия 6 — Integration-01: прогресс мира (`session`): посещённые зоны
## (`visited_zones`, T-33), пройденные ability gates (`passed_gates`, T-09/EC-10)
## и журнал квестов/событий (`journal`, T-28).

const CURRENT_VERSION: int = 6
const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const PROGRESSION_PATH: String = "res://data/balance/progression.tres"
const FALLBACK_MAX_HP: float = 100.0
## Стартовые характеристики, если `progression.tres` недоступен (совпадают
## с данными игры; нужны только для чтения совсем старого сейва).
const FALLBACK_STATS: Dictionary = {
	"strength": 5,
	"dexterity": 5,
	"endurance": 5,
	"health": 5,
}

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

	if version == 2:
		migrated = _v2_to_v3(migrated)
		version = 3

	if version == 3:
		migrated = _v3_to_v4(migrated)
		version = 4

	if version == 4:
		migrated = _v4_to_v5(migrated)
		version = 5

	if version == 5:
		migrated = _v5_to_v6(migrated)
		version = 6

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


## v2 → v3: T-26 (HP, инвентарь, способности, смерть/corpse, чекпоинт).
## Старые сейвы получают дефолты: полное HP, пустой инвентарь/способности,
## отсутствие смерти и метки, пустой чекпоинт. Существующие поля не меняются.
static func _v2_to_v3(body: Dictionary) -> Dictionary:
	var migrated: Dictionary = body.duplicate(true)
	var state_value: Variant = migrated.get("state", {})
	var state: Dictionary = state_value if state_value is Dictionary else {}

	if not state.has("hp"):
		state["hp"] = _default_max_hp()
	if not state.has("inventory"):
		state["inventory"] = []
	if not state.has("abilities"):
		state["abilities"] = []
	if not state.has("death_active"):
		state["death_active"] = false
	if not state.has("death_corpse_active"):
		state["death_corpse_active"] = false
	if not state.has("death_zone_id"):
		state["death_zone_id"] = ""
	if not state.has("death_position"):
		state["death_position"] = {"x": 0.0, "y": 0.0}
	if not state.has("death_items"):
		state["death_items"] = []
	if not state.has("death_currency"):
		state["death_currency"] = 0
	if not state.has("death_lost"):
		state["death_lost"] = false
	if not state.has("respawn_bonfire"):
		state["respawn_bonfire"] = ""
	if not state.has("respawn_zone_id"):
		state["respawn_zone_id"] = ""
	if not state.has("respawn_position"):
		state["respawn_position"] = {"x": 0.0, "y": 0.0}

	migrated["state"] = state
	return migrated


## v3 → v4: T-27 — репутация фракций и выбранный союз. Старые сейвы
## получают нейтральные репутации (пустой словарь) и «фракция не выбрана».
## Существующие поля не меняются.
static func _v3_to_v4(body: Dictionary) -> Dictionary:
	var migrated: Dictionary = body.duplicate(true)
	var state_value: Variant = migrated.get("state", {})
	var state: Dictionary = state_value if state_value is Dictionary else {}

	if not state.has("factions"):
		state["factions"] = {}
	if not state.has("chosen_faction"):
		state["chosen_faction"] = ""

	migrated["state"] = state
	return migrated


## v4 → v5: T-29 — характеристики, очки обучения, уровень и опыт.
## Старые сейвы получают стартовые характеристики из `progression.tres`
## (fallback — совпадающие константы), 0 очков, уровень 1 и 0 XP.
## Существующие поля не меняются.
static func _v4_to_v5(body: Dictionary) -> Dictionary:
	var migrated: Dictionary = body.duplicate(true)
	var state_value: Variant = migrated.get("state", {})
	var state: Dictionary = state_value if state_value is Dictionary else {}

	if not state.has("stats"):
		state["stats"] = _default_progression_stats()
	if not state.has("learning_points"):
		state["learning_points"] = 0
	if not state.has("level"):
		state["level"] = 1
	if not state.has("xp"):
		state["xp"] = 0

	migrated["state"] = state
	return migrated


## v5 → v6: Integration-01 — прогресс мира вне GameState: посещённые зоны
## (T-33), пройденные ability gates (T-09/EC-10) и журнал квестов/событий
## (T-28). Старые сейвы получают пустые наборы (мир ещё не исследован),
## существующие поля состояния и метаданные не меняются.
static func _v5_to_v6(body: Dictionary) -> Dictionary:
	var migrated: Dictionary = body.duplicate(true)
	var session_value: Variant = migrated.get("session", {})
	var session: Dictionary = session_value if session_value is Dictionary else {}

	var visited_value: Variant = session.get("visited_zones")
	if not visited_value is Array:
		session["visited_zones"] = []
	var passed_value: Variant = session.get("passed_gates")
	if not passed_value is Array:
		session["passed_gates"] = []

	var journal_value: Variant = session.get("journal")
	var journal: Dictionary = journal_value if journal_value is Dictionary else {}
	var active_value: Variant = journal.get("active")
	if not active_value is Array:
		journal["active"] = []
	var completed_value: Variant = journal.get("completed")
	if not completed_value is Array:
		journal["completed"] = []
	var events_value: Variant = journal.get("events")
	if not events_value is Array:
		journal["events"] = []
	session["journal"] = journal

	migrated["session"] = session
	return migrated


## Стартовые характеристики для старых сейвов — из того же
## `progression.tres`, что и игра. Недоступный ресурс → безопасный fallback.
static func _default_progression_stats() -> Dictionary:
	var result: Dictionary = FALLBACK_STATS.duplicate(true)
	if not ResourceLoader.exists(PROGRESSION_PATH):
		return result
	var data: ProgressionData = load(PROGRESSION_PATH) as ProgressionData
	if data == null or not data.is_valid():
		return result
	var stats: Dictionary = {}
	for stat_id: StringName in data.stat_ids:
		stats[String(stat_id)] = data.get_start_value(stat_id)
	return stats


## Дефолтное HP для старых сейвов — из того же `balancing.tres`, что и игра
## (единый источник данных, PLAN §3.1). Ресурс недоступен → безопасный fallback.
static func _default_max_hp() -> float:
	if not ResourceLoader.exists(BALANCE_PATH):
		return FALLBACK_MAX_HP
	var balance: BalancingParams = load(BALANCE_PATH) as BalancingParams
	if balance == null or balance.max_hp <= 0.0:
		return FALLBACK_MAX_HP
	return balance.max_hp
