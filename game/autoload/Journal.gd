extends Node
## Journal — квесты и события для вкладки «Журнал» (PLAN §2.2, T-24/T-27/T-28).
##
## Состояние:
##   * `_active` — выданные, но не завершённые квесты;
##   * `_completed` — завершённые квесты (в порядке завершения);
##   * `_events` — последние события мира/диалогов (T-24), с дедупликацией.
##
## Контракт для T-24 (UI): `get_active_quests()`, `get_completed_quests()`,
## `get_quest_entries(language)`, `get_events()`, сигнал `journal_changed`.
## Контракт для T-28 (диалоги/квесты): `start_quest()`, `complete_quest()`,
## `record_event()`, `is_active()`, `is_completed()`.
##
## `get_state()`/`restore_state()` — снимок для будущей сериализации сейва
## (T-25). Сейчас SaveManager журнал не пишет: это отдельный integration-шаг,
## чтобы не менять schema_version без миграции.

signal journal_changed
signal quest_started(quest_id: StringName, title: String)
signal quest_completed(quest_id: StringName, title: String)
signal event_recorded(event_id: StringName, text: String)

## Журнал не растёт бесконечно: T-24 показывает последние события.
const MAX_EVENTS: int = 64

var _active: Array[StringName] = []
var _completed: Array[StringName] = []
var _events: Array[Dictionary] = []


# ------------------------------------------------------------------------------
# Quests
# ------------------------------------------------------------------------------

## Выдать квест. Повторная выдача/завершённый квест — false.
func start_quest(quest_id: StringName) -> bool:
	if quest_id.is_empty() or is_completed(quest_id) or is_active(quest_id):
		return false
	_active.append(quest_id)
	journal_changed.emit()
	quest_started.emit(quest_id, QuestService.get_quest_title(quest_id))
	return true


## Завершить квест: убрать из активных, записать в завершённые.
func complete_quest(quest_id: StringName) -> bool:
	if quest_id.is_empty() or is_completed(quest_id):
		return false
	_active.erase(quest_id)
	_completed.append(quest_id)
	journal_changed.emit()
	quest_completed.emit(quest_id, QuestService.get_quest_title(quest_id))
	return true


func is_active(quest_id: StringName) -> bool:
	return _active.has(quest_id)


func is_completed(quest_id: StringName) -> bool:
	return _completed.has(quest_id)


func get_active_quests() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(_active)
	return copy


func get_completed_quests() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(_completed)
	return copy


## `completed`, `active` или `unknown`.
func get_quest_status(quest_id: StringName) -> StringName:
	if is_completed(quest_id):
		return &"completed"
	if is_active(quest_id):
		return &"active"
	return &"unknown"


## Записи для вкладки «Журнал»: активные сверху, затем завершённые.
## `{quest_id, title, status, faction_id, faction_name}`.
func get_quest_entries(language: String = "ru") -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for quest_id: StringName in get_active_quests():
		entries.append(_quest_entry(quest_id, &"active", language))
	for quest_id: StringName in get_completed_quests():
		entries.append(_quest_entry(quest_id, &"completed", language))
	return entries


# ------------------------------------------------------------------------------
# Events
# ------------------------------------------------------------------------------

## Записать событие. Дубликат (`event_id` + `text`) игнорируется.
func record_event(event_id: StringName, text: String = "") -> bool:
	if event_id.is_empty():
		return false
	for entry: Dictionary in _events:
		if entry.get("id") == event_id and str(entry.get("text", "")) == text:
			return false
	_events.append({"id": event_id, "text": text})
	while _events.size() > MAX_EVENTS:
		_events.pop_front()
	journal_changed.emit()
	event_recorded.emit(event_id, text)
	return true


## Копия событий в порядке добавления (старые → новые).
func get_events() -> Array[Dictionary]:
	return _events.duplicate(true)


# ------------------------------------------------------------------------------
# State (задел T-25)
# ------------------------------------------------------------------------------

## Снимок для сериализации: id квестов и события.
func get_state() -> Dictionary:
	var active: Array[String] = []
	for quest_id: StringName in _active:
		active.append(String(quest_id))
	var completed: Array[String] = []
	for quest_id: StringName in _completed:
		completed.append(String(quest_id))
	return {
		"active": active,
		"completed": completed,
		"events": _events.duplicate(true),
	}


## Восстановление снимка; неизвестные значения отбрасываются.
func restore_state(state: Dictionary) -> void:
	_active.clear()
	_completed.clear()
	_events.clear()

	var active_value: Variant = state.get("active", [])
	if active_value is Array:
		for value: Variant in active_value:
			var quest_id: StringName = StringName(str(value))
			if not quest_id.is_empty() and not _active.has(quest_id):
				_active.append(quest_id)

	var completed_value: Variant = state.get("completed", [])
	if completed_value is Array:
		for value: Variant in completed_value:
			var quest_id: StringName = StringName(str(value))
			if quest_id.is_empty() or _completed.has(quest_id):
				continue
			_completed.append(quest_id)
			_active.erase(quest_id)

	var events_value: Variant = state.get("events", [])
	if events_value is Array:
		for value: Variant in events_value:
			if value is not Dictionary:
				continue
			var entry: Dictionary = value
			var event_id: StringName = StringName(str(entry.get("id", "")))
			if event_id.is_empty():
				continue
			_events.append({
				"id": event_id,
				"text": str(entry.get("text", "")),
			})
			if _events.size() >= MAX_EVENTS:
				break
	journal_changed.emit()


## Новая игра/тесты.
func reset_state() -> void:
	_active.clear()
	_completed.clear()
	_events.clear()
	journal_changed.emit()


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _quest_entry(quest_id: StringName, status: StringName, language: String) -> Dictionary:
	var data: QuestData = QuestService.get_quest(quest_id)
	var faction_id: StringName = data.faction_id if data != null else &""
	if faction_id.is_empty():
		faction_id = FactionManager.get_quest_owner(quest_id)
	return {
		"quest_id": quest_id,
		"title": QuestService.get_quest_title(quest_id, language),
		"status": status,
		"faction_id": faction_id,
		"faction_name": FactionManager.get_faction_name(faction_id),
	}
