class_name SaveSerializer
extends RefCounted
## SaveSerializer — JSON-формат сейва, SHA-256-целостность и перенос состояния
## `GameState` (T-25, PLAN §3.4; AC-05.1, EC-07).
##
## Файл:
##   {"schema_version":1,"checksum":"<sha256>","body":{...}}
## `checksum` — SHA-256 ровно тех UTF-8 байт, что стоят после `"body":`
## (сырое тело). Поэтому проверка не зависит от того, как JSON парсит/печатает
## числа и в каком порядке лежат ключи: тело сверяется байт в байт.
##
## Тело (schema_version = 6):
##   state: {stats, learning_points, level, xp,
##           stamina, weapon_id, weapon_path,
##           bosses_defeated, boss_rewards_pending, currency,
##           hp, inventory, abilities,
##           death_active, death_corpse_active, death_zone_id, death_position,
##           death_items, death_currency, death_lost,
##           respawn_bonfire, respawn_zone_id, respawn_position,
##           factions, chosen_faction}
##   session: {visited_zones, passed_gates, journal}
##   meta:  {zone_id, zone_name, level, play_time, saved_at_unix} + extras
## `state` — только реально существующие поля `GameState`. T-26 (v3) добавил
## HP, инвентарь, способности, corpse-метку/флаг смерти (EC-04) и чекпоинт
## костра; T-27 (v4) — репутацию фракций (`factions`: id -> int) и выбранную
## фракцию; T-29 (v5) — характеристики (`stats`: id -> int), очки обучения,
## уровень и опыт. Integration-01 (v6) добавил `session` — прогресс мира вне
## GameState: посещённые зоны (T-33), пройденные ability gates (T-09/EC-10)
## и журнал квестов/событий (T-28). Контракт добавления полей и версии описан
## в `save_migrations.gd`.
##
## `meta` — данные для UI (зона, уровень, время) и задел под будущие поля:
## известные ключи нормализуются, незнакомые проходят через `_json_safe()`.

const WEAPONS_DIR: String = "res://data/weapons"
const DEFAULT_WEAPON_PATH: String = "res://data/weapons/one_handed_sword.tres"

const CHECKSUM_LENGTH: int = 64
const BODY_MARKER: String = "\"body\":"

const REASON_OK: String = "ok"
const REASON_CORRUPTED: String = "corrupted"


## SHA-256 через `HashingContext` (требование PLAN §3.4), hex в нижнем регистре.
static func sha256_hex(text: String) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


## Собирает тело сейва из состояния и метаданных вызывающего (костёр T-22,
## зона T-17) — позиция/инвентарь сюда добавятся в своих задачах.
## `session` — прогресс мира (зоны/gates/журнал), см. `serialize_session()`.
static func build_body(state: Node, metadata: Dictionary = {}) -> Dictionary:
	return {
		"state": serialize_state(state),
		"session": serialize_session(),
		"meta": normalize_meta(metadata),
	}


## Сериализует существующие поля GameState: прогрессию, выносливость и
## текущее оружие. Отсутствующий/неинициализированный state даёт пустой
## `state` без вылета.
static func serialize_state(state: Node) -> Dictionary:
	var data: Dictionary = {}
	if state == null:
		return data

	# T-29 (schema v5): характеристики, очки обучения, уровень и опыт.
	data["stats"] = _stat_map(state.get("stats"))
	data["learning_points"] = _as_int(state.get("learning_points"), 0)
	data["level"] = maxi(_as_int(state.get("level"), 1), 1)
	data["xp"] = maxi(_as_int(state.get("xp"), 0), 0)

	var stamina_value: Variant = state.get("stamina")
	if stamina_value is int or stamina_value is float:
		data["stamina"] = float(stamina_value)

	var weapon: WeaponData = state.get("weapon") as WeaponData
	if weapon != null:
		data["weapon_id"] = String(weapon.id)
		data["weapon_path"] = weapon.resource_path
	else:
		data["weapon_id"] = ""
		data["weapon_path"] = ""

	# T-30: прогресс боссов и отложенные награды (EC-09).
	var boss_list: Array[String] = []
	var defeated_value: Variant = state.get("bosses_defeated")
	if defeated_value is Array:
		for value: Variant in defeated_value:
			boss_list.append(String(value))
	data["bosses_defeated"] = boss_list

	var pending_value: Variant = state.get("boss_rewards_pending")
	data["boss_rewards_pending"] = (
		_json_safe(pending_value) if pending_value is Dictionary else {}
	)

	var currency_value: Variant = state.get("currency")
	if currency_value is int or currency_value is float:
		data["currency"] = int(currency_value)
	else:
		data["currency"] = 0

	# T-26 (schema v3): HP, инвентарь и способности (AC-05.1/AC-05.2).
	var hp_value: Variant = state.get("hp")
	if hp_value is int or hp_value is float:
		data["hp"] = float(hp_value)
	data["inventory"] = _string_array(state.get("inventory"))
	data["abilities"] = _string_array(state.get("abilities"))

	# T-26: смерть/corpse run. `death_active` нужен для EC-04 (выход из игры
	# в бюджете смерти = обычная смерть при загрузке), corpse-поля — AC-05.3.
	data["death_active"] = bool(state.get("death_active"))
	data["death_corpse_active"] = bool(state.get("corpse_active"))
	data["death_zone_id"] = String(state.get("corpse_zone_id"))
	data["death_position"] = _vector2_to_dict(state.get("corpse_position"))
	data["death_items"] = _string_array(state.get("corpse_items"))
	var corpse_currency_value: Variant = state.get("corpse_currency")
	if corpse_currency_value is int or corpse_currency_value is float:
		data["death_currency"] = int(corpse_currency_value)
	else:
		data["death_currency"] = 0
	data["death_lost"] = bool(state.get("corpse_lost"))

	# T-26: точка возрождения — id зоны/костра и позиция спавна.
	data["respawn_bonfire"] = String(state.get("respawn_bonfire"))
	data["respawn_zone_id"] = String(state.get("respawn_zone_id"))
	# Поля есть только у GameState T-26+; у старого/чужого state — дефолты.
	data["respawn_position"] = _vector2_to_dict(state.get("respawn_position"))

	# T-27 (schema v4): репутация фракций и выбранная фракция (US-06).
	data["factions"] = _faction_reputation(state.get("factions"))
	data["chosen_faction"] = String(state.get("chosen_faction"))

	return data


## Применяет `state` из сейва к GameState. Незнакомые/отсутствующие ключи
## пропускаются — старые сейвы остаются загружаемыми после миграций.
static func apply_state(state: Node, state_data: Dictionary) -> bool:
	if state == null:
		return false

	# T-29 (v5): прогрессия применяется до HP/выносливости — бонусы здоровья
	# и выносливости уже учтены при восстановлении максимумов. Старые сейвы
	# после миграции содержат дефолты (v4→v5), поэтому загрузка не ломается.
	if state.has_method("restore_progression"):
		var stats_value: Variant = state_data.get("stats", {})
		var stats_data: Dictionary = stats_value if stats_value is Dictionary else {}
		state.call(
			"restore_progression",
			stats_data,
			_as_int(state_data.get("learning_points", 0), 0),
			_as_int(state_data.get("level", 1), 1),
			_as_int(state_data.get("xp", 0), 0)
		)

	if state_data.has("stamina"):
		state.set("stamina", float(state_data["stamina"]))

	if state_data.has("weapon_id") or state_data.has("weapon_path"):
		var weapon_id: String = str(state_data.get("weapon_id", ""))
		var weapon_path: String = str(state_data.get("weapon_path", ""))
		var weapon: WeaponData = resolve_weapon(weapon_id, weapon_path)
		if weapon != null:
			state.set("weapon", weapon)

	# T-30: прогресс боссов и отложенные награды (EC-09). Старые сейвы без
	# этих ключей получают пустой прогресс — загрузка не ломается (v1→v2).
	if state.has_method("restore_boss_progress"):
		var defeated_value: Variant = state_data.get("bosses_defeated", [])
		var defeated: Array = defeated_value if defeated_value is Array else []
		var pending_value: Variant = state_data.get("boss_rewards_pending", {})
		var pending: Dictionary = pending_value if pending_value is Dictionary else {}
		var currency_value: Variant = state_data.get("currency", 0)
		var currency_amount: int = 0
		if currency_value is int or currency_value is float:
			currency_amount = int(currency_value)
		state.call("restore_boss_progress", defeated, pending, currency_amount)

	# T-26 (v3): HP, инвентарь и способности (AC-05.1). У state без этих
	# методов (старые заглушки/тесты) поля просто пропускаются.
	if state_data.has("hp") and state.has_method("restore_hp"):
		var hp_value: Variant = state_data["hp"]
		if hp_value is int or hp_value is float:
			state.call("restore_hp", float(hp_value))

	if state.has_method("restore_inventory"):
		var inventory_value: Variant = state_data.get("inventory", [])
		var inventory_items: Array = inventory_value if inventory_value is Array else []
		state.call("restore_inventory", inventory_items)

	if state.has_method("restore_abilities"):
		var abilities_value: Variant = state_data.get("abilities", [])
		var ability_items: Array = abilities_value if abilities_value is Array else []
		state.call("restore_abilities", ability_items)

	# T-26: смерть/corpse run и чекпоинт костра. Старые сейвы после миграции
	# содержат дефолты (v2→v3), поэтому загрузка не ломается.
	if state.has_method("restore_death_state"):
		var zone_value: Variant = state_data.get("death_zone_id", "")
		var items_value: Variant = state_data.get("death_items", [])
		var death_items: Array = items_value if items_value is Array else []
		var death_currency_value: Variant = state_data.get("death_currency", 0)
		var death_currency_amount: int = 0
		if death_currency_value is int or death_currency_value is float:
			death_currency_amount = int(death_currency_value)
		state.call(
			"restore_death_state",
			bool(state_data.get("death_active", false)),
			bool(state_data.get("death_corpse_active", false)),
			StringName(str(zone_value)),
			_as_vector2(state_data.get("death_position", {})),
			death_items,
			death_currency_amount,
			bool(state_data.get("death_lost", false))
		)

	if state.has_method("restore_respawn_bonfire"):
		var bonfire_value: Variant = state_data.get("respawn_bonfire", "")
		var respawn_zone_value: Variant = state_data.get("respawn_zone_id", "")
		state.call(
			"restore_respawn_bonfire",
			StringName(str(bonfire_value)),
			StringName(str(respawn_zone_value)),
			_as_vector2(state_data.get("respawn_position", {}))
		)

	# T-27 (v4): репутация фракций и выбор. Старые сейвы после миграции
	# содержат дефолты (v3→v4), поэтому загрузка не ломается.
	if state.has_method("restore_factions"):
		var factions_value: Variant = state_data.get("factions", {})
		var factions: Dictionary = factions_value if factions_value is Dictionary else {}
		var chosen_value: Variant = state_data.get("chosen_faction", "")
		state.call("restore_factions", factions, StringName(str(chosen_value)))

	return true


## Снимок прогресса мира сверх GameState (schema v6): посещённые зоны (T-33),
## пройденные ability gates (T-09/EC-10) и журнал квестов/событий (T-28).
## Читает автолоады напрямую; если их нет (юнит-тесты сериализатора) —
## возвращает пустые значения, а не падает.
static func serialize_session() -> Dictionary:
	var visited: Array = []
	var router: Node = _autoload(&"SceneRouter")
	if router != null and router.has_method(&"get_visited_zone_ids"):
		var visited_value: Variant = router.call(&"get_visited_zone_ids")
		if visited_value is Array:
			for zone_value: Variant in visited_value:
				visited.append(String(zone_value))

	var passed_gates: Array = []
	for gate_id: StringName in AbilityGate.get_passed_gate_ids():
		passed_gates.append(String(gate_id))

	var journal_state: Dictionary = {}
	var journal: Node = _autoload(&"Journal")
	if journal != null and journal.has_method(&"get_state"):
		var journal_value: Variant = journal.call(&"get_state")
		if journal_value is Dictionary:
			var safe_value: Variant = _json_safe(journal_value)
			journal_state = safe_value if safe_value is Dictionary else {}

	return {
		"visited_zones": visited,
		"passed_gates": passed_gates,
		"journal": journal_state,
	}


## Применяет `session` из сейва. Идемпотентно: наборы зон/gates заменяются,
## живые gates переоценивают блокировку (EC-10: пройденный проход не блокирует),
## журнал восстанавливается через `Journal.restore_state()`. Отсутствующие
## ключи дают пустой прогресс — старые сейвы после миграции загружаются.
static func apply_session(session_data: Dictionary) -> bool:
	var router: Node = _autoload(&"SceneRouter")
	if router != null and router.has_method(&"restore_visited_zones"):
		var visited_value: Variant = session_data.get("visited_zones", [])
		var visited: Array = visited_value if visited_value is Array else []
		router.call(&"restore_visited_zones", visited)

	var passed_value: Variant = session_data.get("passed_gates", [])
	var passed_gates: Array = passed_value if passed_value is Array else []
	AbilityGate.restore_passed_gates(passed_gates)

	var journal: Node = _autoload(&"Journal")
	if journal != null and journal.has_method(&"restore_state"):
		var journal_value: Variant = session_data.get("journal", {})
		var journal_state: Dictionary = journal_value if journal_value is Dictionary else {}
		journal.call(&"restore_state", journal_state)

	return true


## Ищет оружие по пути (основной способ), затем по id (переносимость между
## сборками), иначе — дефолтное оружие GameState. Никогда не возвращает
## невалидный ресурс.
static func resolve_weapon(weapon_id: String, weapon_path: String) -> WeaponData:
	if not weapon_path.is_empty() and ResourceLoader.exists(weapon_path):
		var by_path: WeaponData = load(weapon_path) as WeaponData
		if by_path != null and (weapon_id.is_empty() or String(by_path.id) == weapon_id):
			return by_path

	if not weapon_id.is_empty():
		var directory: DirAccess = DirAccess.open(WEAPONS_DIR)
		if directory != null:
			for file_name: String in directory.get_files():
				if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
					continue
				var candidate: WeaponData = load(WEAPONS_DIR.path_join(file_name)) as WeaponData
				if candidate != null and String(candidate.id) == weapon_id:
					return candidate

	push_warning("SaveSerializer: weapon '%s' not found, falling back to default" % weapon_id)
	return load(DEFAULT_WEAPON_PATH) as WeaponData


## Нормализует метаданные слота для UI. `saved_at_unix` ставится в момент
## сохранения; известные ключи приводятся к типам, extras сохраняются.
static func normalize_meta(metadata: Dictionary) -> Dictionary:
	var meta: Dictionary = {
		"zone_id": str(metadata.get("zone_id", "")),
		"zone_name": str(metadata.get("zone_name", "")),
		"level": _as_int(metadata.get("level", 0), 0),
		"play_time": _as_float(metadata.get("play_time", 0.0), 0.0),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
	}

	for key: Variant in metadata.keys():
		var text_key: String = String(key)
		if meta.has(text_key):
			continue
		meta[text_key] = _json_safe(metadata[key])

	return meta


## Собирает файл: заголовок + тело, checksum считается по телу.
## `schema_version` параметризован для тестов миграции (по умолчанию — текущая).
static func encode(body: Dictionary, schema_version: int = -1) -> String:
	var version: int = schema_version
	if version < 0:
		version = SaveMigrations.CURRENT_VERSION

	var body_text: String = JSON.stringify(body)
	return "{\"schema_version\":%d,\"checksum\":\"%s\",\"body\":%s}" % [
		version,
		sha256_hex(body_text),
		body_text,
	]


## Разбирает файл и проверяет целостность. Возвращает
## `{ok, reason, schema_version, body}`; при любой проблеме — `ok = false`
## (EC-07: слот не грузится, вызывающий показывает предупреждение).
static func decode(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return _corrupted()

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _corrupted()
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return _corrupted()
	var document: Dictionary = root

	var version_value: Variant = document.get("schema_version")
	if not (version_value is int or version_value is float):
		return _corrupted()
	var schema_version: int = int(version_value)

	var checksum: String = str(document.get("checksum", ""))
	if checksum.length() != CHECKSUM_LENGTH:
		return _corrupted()

	var trimmed: String = text.strip_edges(false, true)
	var marker_index: int = trimmed.find(BODY_MARKER)
	if marker_index < 0 or not trimmed.ends_with("}"):
		return _corrupted()

	var body_start: int = marker_index + BODY_MARKER.length()
	var body_text: String = trimmed.substr(body_start, trimmed.length() - body_start - 1)
	if sha256_hex(body_text) != checksum.to_lower():
		return _corrupted()

	var body_value: Variant = document.get("body")
	if typeof(body_value) != TYPE_DICTIONARY:
		return _corrupted()

	var migration: Dictionary = SaveMigrations.migrate(schema_version, body_value)
	if not bool(migration.get("ok", false)):
		return {
			"ok": false,
			"reason": str(migration.get("reason", REASON_CORRUPTED)),
			"schema_version": schema_version,
			"body": {},
		}

	return {
		"ok": true,
		"reason": REASON_OK,
		"schema_version": schema_version,
		"body": migration["body"],
	}


static func _corrupted() -> Dictionary:
	return {
		"ok": false,
		"reason": REASON_CORRUPTED,
		"schema_version": 0,
		"body": {},
	}


## Автолоад по имени (`/root/<name>`) без жёсткой ссылки на глобальное имя:
## сериализатор остаётся статическим и тестируемым вне дерева сцены.
static func _autoload(autoload_name: StringName) -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	var tree: SceneTree = main_loop as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(String(autoload_name)))


## JSON-совместимое значение для extras: StringName → String, Vector2 → словарь,
## прочие объекты — строкой (сейв не должен падать из-за типа метаданных).
static func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return String(value)
		TYPE_ARRAY:
			var array: Array = []
			for item: Variant in value:
				array.append(_json_safe(item))
			return array
		TYPE_DICTIONARY:
			var dictionary: Dictionary = {}
			for key: Variant in value:
				dictionary[String(key)] = _json_safe(value[key])
			return dictionary
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		_:
			return str(value)


## StringName/строки → JSON-массив строк (способности, инвентарь, corpse).
static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			result.append(String(item))
	return result


## Характеристики: stat_id (StringName/строка) -> int. Нечисловые значения
## и пустые id пропускаются — битый сейв не роняет загрузку.
static func _stat_map(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for key: Variant in (value as Dictionary).keys():
		var stat_id: String = String(key)
		if stat_id.is_empty():
			continue
		var stat_value: Variant = (value as Dictionary)[key]
		if stat_value is int or stat_value is float:
			result[stat_id] = int(stat_value)
	return result


## Репутации фракций: id (StringName/строка) -> int. Нечисловые значения и
## пустые id пропускаются, чтобы битый сейв не ронял загрузку.
static func _faction_reputation(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for key: Variant in value.keys():
		var faction_id: String = String(key)
		if faction_id.is_empty():
			continue
		var reputation: Variant = value[key]
		if reputation is int or reputation is float:
			result[faction_id] = int(reputation)
	return result


static func _vector2_to_dict(value: Variant) -> Dictionary:
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Dictionary:
		return {"x": _as_float(value.get("x", 0.0), 0.0), "y": _as_float(value.get("y", 0.0), 0.0)}
	return {"x": 0.0, "y": 0.0}


## Позиция из сейва: `{x, y}` (основной формат) или строка "x,y" (терпимость
## к старым/ручным сейвам). Испорченное значение даёт Vector2.ZERO.
static func _as_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(
			_as_float(value.get("x", 0.0), 0.0),
			_as_float(value.get("y", 0.0), 0.0)
		)
	if value is String:
		var parts: PackedStringArray = value.split(",")
		if parts.size() == 2 and parts[0].strip_edges().is_valid_float() \
			and parts[1].strip_edges().is_valid_float():
			return Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())
	return Vector2.ZERO


static func _as_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and value.is_valid_int():
		return value.to_int()
	return fallback


static func _as_float(value: Variant, fallback: float) -> float:
	if value is int:
		return float(value)
	if value is float:
		return value
	if value is String and value.is_valid_float():
		return value.to_float()
	return fallback
