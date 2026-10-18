extends Node
## FactionManager — репутация, доступ, квесты и концовка по фракциям (T-27).
##
## Данные — `data/factions/*.tres` (`FactionData`): имена/лор, шкала,
## порог доступа, причины отказа (AC-06.2), таблица `Δ` за действия/квесты
## (AC-06.1), список квестов и союзная фракция (EC-11). В коде нет ни имён
## фракций, ни чисел репутации.
##
## Состояние — `GameState.factions` (id → репутация) и
## `GameState.chosen_faction`; сейв пишет их как `state.factions` и
## `state.chosen_faction` (schema v4, T-27/T-25). Менеджер не дублирует
## состояние: геттеры читают GameState, поэтому загрузка сейва сразу
## согласована с доступом и концовкой.
##
## События — через `EventBus`:
##   * `faction_reputation_changed(faction_id, value)` — для UI (T-24);
##   * `faction_access_changed(faction_id, granted)` — порог пересечён;
##   * `faction_quest_completed(quest_id, faction_id, delta, reaction)` —
##     квест повлиял на фракцию (AC-06.1), NPC-реакция — `reaction`;
##   * `faction_chosen(faction_id, display_name)` — выбор для концовки.
##
## Контракт для T-28 (NPC/квесты): завершение квеста вызывает
## `complete_quest(quest_id)`; перед выдачей — `get_quest_access(quest_id)`
## (`available`, `reason`, `alternative_quest_id` для EC-11). Торговец/территория
## проверяются `can_trade()` / `can_enter_territory()`, объяснение —
## `get_access_info(faction_id, kind).reason`.
##
## Контракт для T-32 (концовка): `get_selected_faction()` — явный выбор или
## `&""`; `get_ending_faction_id()` — выбор, иначе лучшая фракция с
## положительной репутацией (пусто — нейтральная концовка).

const FACTIONS_DIR: String = "res://data/factions"
const REQUIRED_FACTION_COUNT: int = 3
const REPUTATION_MIN: int = -100
const REPUTATION_MAX: int = 100

const REACTION_HOSTILE: StringName = &"hostile"
const REACTION_WARY: StringName = &"wary"
const REACTION_NEUTRAL: StringName = &"neutral"
const REACTION_FRIENDLY: StringName = &"friendly"
const REACTION_TRUSTED: StringName = &"trusted"

## Отношение NPC считается по смещению репутации от порога доступа:
## ниже порога на 20+ — hostile; ниже порога — wary; 0..19 — neutral;
## 20..49 — friendly; 50+ — trusted. Так доступ и реакция не расходятся.
const REACTION_HOSTILE_MARGIN: int = 20
const REACTION_FRIENDLY_MARGIN: int = 20
const REACTION_TRUSTED_MARGIN: int = 50

const DEFAULT_DENIED_REASON: String = (
	"Доступ закрыт: репутация с фракцией «{faction}» {reputation} "
	+ "ниже порога {threshold}."
)

## Вид доступа: у территории и торговца разные причины отказа (AC-06.2).
enum AccessKind { TERRITORY, TRADER, QUEST }

## Реестр данных: id -> FactionData. Порядок id детерминирован (сортировка).
var _factions: Dictionary = {}
var _ordered_ids: Array[StringName] = []


func _ready() -> void:
	_load_factions()


# ------------------------------------------------------------------------------
# Registry
# ------------------------------------------------------------------------------

## Идентификаторы фракций в стабильном порядке (детерминированный tie-break).
func get_faction_ids() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(_ordered_ids)
	return copy


func get_faction(faction_id: StringName) -> FactionData:
	return _factions.get(faction_id) as FactionData


func has_faction(faction_id: StringName) -> bool:
	return _factions.has(faction_id)


func get_faction_count() -> int:
	return _factions.size()


## Читаемое имя для UI/концовки (T-32 `EndingCatalog`).
func get_faction_name(faction_id: StringName) -> String:
	var data: FactionData = get_faction(faction_id)
	return data.display_name if data != null else ""


## Алиас для безопасного чтения имени из UI (`get_display_name`).
func get_display_name(faction_id: StringName) -> String:
	return get_faction_name(faction_id)


func get_faction_lore(faction_id: StringName) -> String:
	var data: FactionData = get_faction(faction_id)
	return data.lore if data != null else ""


func get_faction_color(faction_id: StringName) -> Color:
	var data: FactionData = get_faction(faction_id)
	return data.color if data != null else Color.WHITE


func get_access_threshold(faction_id: StringName) -> int:
	var data: FactionData = get_faction(faction_id)
	return data.access_threshold if data != null else 0


# ------------------------------------------------------------------------------
# Reputation (AC-06.1)
# ------------------------------------------------------------------------------

## Текущая репутация; 0 для неизвестной/невыбранной фракции.
func get_reputation(faction_id: StringName) -> int:
	if faction_id == &"":
		return 0
	return GameState.get_faction_reputation(faction_id)


## Копия всех репутаций (id -> int) для UI/сейва.
func get_reputations() -> Dictionary:
	return GameState.get_all_faction_reputation()


## Таблица `Δ` фракции (event_id -> int) для журнала/подсказок T-24.
func get_reputation_table(faction_id: StringName) -> Dictionary:
	var data: FactionData = get_faction(faction_id)
	return data.reputation_events.duplicate(true) if data != null else {}


## Δ конкретного события для фракции (0 — не влияет).
func get_action_delta(faction_id: StringName, event_id: StringName) -> int:
	var data: FactionData = get_faction(faction_id)
	return data.get_reputation_delta(event_id) if data != null else 0


## Устанавливает репутацию с ограничением шкалой данных. Эмитит
## `faction_reputation_changed` и, при пересечении порога, `faction_access_changed`.
## Возвращает фактическое значение.
func set_reputation(faction_id: StringName, value: int) -> int:
	var data: FactionData = get_faction(faction_id)
	if data == null:
		push_warning("FactionManager.set_reputation: unknown faction '%s'" % faction_id)
		return get_reputation(faction_id)

	var previous: int = get_reputation(faction_id)
	var clamped: int = data.clamp_reputation(value)
	if clamped == previous:
		return previous

	GameState.set_faction_reputation(faction_id, clamped)
	EventBus.faction_reputation_changed.emit(faction_id, clamped)

	var was_granted: bool = data.grants_access(previous)
	var is_granted: bool = data.grants_access(clamped)
	if was_granted != is_granted:
		EventBus.faction_access_changed.emit(faction_id, is_granted)
	return clamped


## Прибавляет `delta` к репутации; возвращает новое значение.
func add_reputation(faction_id: StringName, delta: int) -> int:
	if delta == 0:
		return get_reputation(faction_id)
	return set_reputation(faction_id, get_reputation(faction_id) + delta)


## Применяет таблицу `Δ` ко всем фракциям для события/квеста (AC-06.1).
## Возвращает список `{faction_id, delta, value, reaction, access_granted}`
## (только фракции, на которые событие влияет).
func apply_reputation_event(event_id: StringName) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if event_id == &"":
		return results

	for faction_id: StringName in _ordered_ids:
		var data: FactionData = get_faction(faction_id)
		if data == null:
			continue
		var configured_delta: int = data.get_reputation_delta(event_id)
		if configured_delta == 0:
			continue
		var previous: int = get_reputation(faction_id)
		var value: int = set_reputation(faction_id, previous + configured_delta)
		var applied_delta: int = value - previous
		var reaction: StringName = get_npc_reaction(faction_id)
		results.append({
			"faction_id": faction_id,
			"delta": applied_delta,
			"value": value,
			"reaction": reaction,
			"access_granted": data.grants_access(value),
		})
		EventBus.faction_quest_completed.emit(
			event_id,
			faction_id,
			applied_delta,
			reaction
		)
	return results


## Завершение квеста (T-28): репутация меняется по `Δ`-таблице, NPC получает
## новую реакцию/доступ. Это же событие можно вызвать для действия (`action_*`).
func complete_quest(quest_id: StringName) -> Array[Dictionary]:
	return apply_reputation_event(quest_id)


## Реакция NPC по текущей репутации (AC-06.1): hostile/wary/neutral/friendly/
## trusted. T-28 выбирает по ней строку диалога, T-32 — тон эпилога.
func get_npc_reaction(faction_id: StringName) -> StringName:
	var data: FactionData = get_faction(faction_id)
	if data == null:
		return REACTION_NEUTRAL
	var offset: int = get_reputation(faction_id) - data.access_threshold
	if offset < -REACTION_HOSTILE_MARGIN:
		return REACTION_HOSTILE
	if offset < 0:
		return REACTION_WARY
	if offset < REACTION_FRIENDLY_MARGIN:
		return REACTION_NEUTRAL
	if offset < REACTION_TRUSTED_MARGIN:
		return REACTION_FRIENDLY
	return REACTION_TRUSTED


# ------------------------------------------------------------------------------
# Access (AC-06.2, EC-11)
# ------------------------------------------------------------------------------

## Доступ к территории фракции.
func can_access(faction_id: StringName) -> bool:
	return can_enter_territory(faction_id)


func can_enter_territory(faction_id: StringName) -> bool:
	return bool(get_access_info(faction_id, AccessKind.TERRITORY).get("allowed", false))


## Доступ к торговцу фракции (AC-06.2).
func can_trade(faction_id: StringName) -> bool:
	return bool(get_access_info(faction_id, AccessKind.TRADER).get("allowed", false))


## Полное объяснение доступа для UI/NPC (AC-06.2, EC-11):
## `{allowed, reason, reputation, threshold, alternative_faction_id,
##   alternative_allowed, territory_name}`.
func get_access_info(
	faction_id: StringName,
	kind: AccessKind = AccessKind.TERRITORY
) -> Dictionary:
	var data: FactionData = get_faction(faction_id)
	if data == null:
		return {
			"faction_id": faction_id,
			"kind": kind,
			"allowed": false,
			"reputation": get_reputation(faction_id),
			"threshold": 0,
			"territory_name": "",
			"reason": "Неизвестная фракция: %s" % String(faction_id),
			"alternative_faction_id": &"",
			"alternative_allowed": false,
		}

	var reputation: int = get_reputation(faction_id)
	var allowed: bool = data.grants_access(reputation)
	var alternative_id: StringName = data.alternative_faction_id
	var alternative_allowed: bool = false
	if alternative_id != &"" and alternative_id != faction_id:
		var alternative: FactionData = get_faction(alternative_id)
		if alternative != null:
			alternative_allowed = alternative.grants_access(get_reputation(alternative_id))

	var reason: String = ""
	if not allowed:
		reason = _format_denial(data, kind, reputation)

	return {
		"faction_id": faction_id,
		"kind": kind,
		"allowed": allowed,
		"reputation": reputation,
		"threshold": data.access_threshold,
		"territory_name": data.territory_name,
		"reason": reason,
		"alternative_faction_id": alternative_id,
		"alternative_allowed": alternative_allowed,
	}


# ------------------------------------------------------------------------------
# Quests (T-28, EC-11)
# ------------------------------------------------------------------------------

func get_faction_quests(faction_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var data: FactionData = get_faction(faction_id)
	if data != null:
		result.assign(data.quests)
	return result


## Владелец квеста — фракция, в чьём списке он лежит (пусто — не найден).
func get_quest_owner(quest_id: StringName) -> StringName:
	if quest_id == &"":
		return &""
	for faction_id: StringName in _ordered_ids:
		var data: FactionData = get_faction(faction_id)
		if data != null and data.has_quest(quest_id):
			return faction_id
	return &""


## Доступность квеста с объяснением и альтернативой (EC-11):
## `{quest_id, faction_id, available, reason, alternative_faction_id,
##   alternative_allowed, alternative_quest_id}`.
func get_quest_access(quest_id: StringName) -> Dictionary:
	var owner: StringName = get_quest_owner(quest_id)
	if owner == &"":
		return {
			"quest_id": quest_id,
			"faction_id": &"",
			"available": false,
			"allowed": false,
			"reason": "Квест «%s» не принадлежит ни одной фракции." % String(quest_id),
			"reputation": 0,
			"threshold": 0,
			"alternative_faction_id": &"",
			"alternative_allowed": false,
			"alternative_quest_id": &"",
		}

	var info: Dictionary = get_access_info(owner, AccessKind.QUEST)
	info["quest_id"] = quest_id
	info["available"] = bool(info.get("allowed", false))

	var alternative_id: StringName = StringName(
		str(info.get("alternative_faction_id", ""))
	)
	var alternative_quest: StringName = &""
	var alternative_allowed: bool = bool(info.get("alternative_allowed", false))
	if alternative_allowed and alternative_id != &"":
		var alternative_quests: Array[StringName] = get_faction_quests(alternative_id)
		if alternative_quests.is_empty():
			alternative_allowed = false
		else:
			alternative_quest = alternative_quests[0]
	info["alternative_allowed"] = alternative_allowed
	info["alternative_quest_id"] = alternative_quest
	return info


func is_quest_available(quest_id: StringName) -> bool:
	return bool(get_quest_access(quest_id).get("available", false))


## Первый квест союзной фракции как альтернатива недоступному (EC-11).
func get_alternative_quest(quest_id: StringName) -> StringName:
	return StringName(str(get_quest_access(quest_id).get("alternative_quest_id", "")))


# ------------------------------------------------------------------------------
# Choice and ending (US-06, T-32)
# ------------------------------------------------------------------------------

## Явный выбор игрока; `&""` — выбор не сделан (нейтральная концовка T-32).
func get_selected_faction() -> StringName:
	return GameState.chosen_faction


## Алиасы для совместимости с безопасным чтением из T-32/T-16
## (`get_current_faction`, `get_faction_id`).
func get_current_faction() -> StringName:
	return get_selected_faction()


func get_faction_id() -> StringName:
	return get_selected_faction()


func is_faction_chosen() -> bool:
	return get_selected_faction() != &""


## Выбирает фракцию для концовки. Возвращает false для неизвестного id.
func choose_faction(faction_id: StringName) -> bool:
	if get_faction(faction_id) == null:
		push_warning("FactionManager.choose_faction: unknown faction '%s'" % faction_id)
		return false
	if GameState.chosen_faction == faction_id:
		return true
	GameState.chosen_faction = faction_id
	EventBus.faction_chosen.emit(faction_id, get_faction_name(faction_id))
	return true


func clear_faction_choice() -> void:
	GameState.chosen_faction = &""


## Фракция с максимальной положительной репутацией (tie-break — порядок id).
## Пусто, если никто не в плюсе: концовка остаётся нейтральной.
func get_best_faction() -> StringName:
	var best_id: StringName = &""
	var best_value: int = 0
	for faction_id: StringName in _ordered_ids:
		var value: int = get_reputation(faction_id)
		if value > best_value:
			best_value = value
			best_id = faction_id
	return best_id


## Стабильный id для концовки T-32: явный выбор, иначе лучшая фракция.
func get_ending_faction_id() -> StringName:
	var selected: StringName = get_selected_faction()
	if selected != &"":
		return selected
	return get_best_faction()


# ------------------------------------------------------------------------------
# State / persistence (T-25, schema v4)
# ------------------------------------------------------------------------------

## Сброс репутаций и выбора (новая игра/тесты). Сигналы не эмитятся.
func reset_state() -> void:
	GameState.reset_factions()


## Восстановление состояния из сейва вручную (SaveSerializer делает это через
## GameState). Валидные id проверяются при чтении, значения уже прошли clamp.
func restore_state(factions: Dictionary, chosen_faction: StringName) -> void:
	GameState.restore_factions(factions, chosen_faction)


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _load_factions() -> void:
	_factions.clear()
	_ordered_ids.clear()

	var directory: DirAccess = DirAccess.open(FACTIONS_DIR)
	if directory == null:
		push_error("FactionManager: cannot open %s" % FACTIONS_DIR)
		return

	var file_names: PackedStringArray = directory.get_files()
	file_names.sort()
	var ids: Array[String] = []
	for file_name: String in file_names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = FACTIONS_DIR.path_join(file_name)
		var data: FactionData = load(path) as FactionData
		if data == null:
			push_error("FactionManager: %s is not FactionData" % path)
			continue
		if not data.is_valid():
			push_error("FactionManager: invalid faction data at %s" % path)
			continue
		if _factions.has(data.id):
			push_error("FactionManager: duplicate faction id '%s'" % data.id)
			continue
		_factions[data.id] = data
		ids.append(String(data.id))

	ids.sort()
	for id: String in ids:
		_ordered_ids.append(StringName(id))

	if _factions.size() != REQUIRED_FACTION_COUNT:
		push_warning(
			"FactionManager: expected %d factions, loaded %d"
			% [REQUIRED_FACTION_COUNT, _factions.size()]
		)


func _format_denial(data: FactionData, kind: AccessKind, reputation: int) -> String:
	var template: String = DEFAULT_DENIED_REASON
	match kind:
		AccessKind.TRADER:
			if not data.trade_denied_reason.is_empty():
				template = data.trade_denied_reason
		AccessKind.QUEST:
			if not data.quest_denied_reason.is_empty():
				template = data.quest_denied_reason
		_:
			if not data.territory_denied_reason.is_empty():
				template = data.territory_denied_reason
	return template.format({
		"faction": data.display_name,
		"reputation": reputation,
		"threshold": data.access_threshold,
		"territory": data.territory_name,
	})
