class_name DialogueRunner
extends RefCounted
## DialogueRunner — движок диалога (T-28, AC-06.1/06.2, EC-11).
##
## Чистая логика без нод: принимает `DialogueData`, отдаёт снимок для UI
## (`get_snapshot()`), применяет последствия ответа и переходит по графу.
##
## Снимок:
##   {dialogue_id, npc_id, node_id, speaker, faction, faction_id, text,
##    page_index, page_count, has_next_page, answers: [{index, id, text, tag,
##    disabled, reason}], ended, ended_reason}
##
## * ответы показываются только на последней странице (текст сначала
##   дочитывается/перелистывается);
## * ответ с невыполненным условием отдаётся `disabled` с причиной (AC-06.2,
##   EC-11) — UI не скрывает ограничение;
## * тег `[Фракция±N]` считается из Δ-таблицы T-27, поэтому совпадает с
##   фактическим изменением репутации;
## * выбор применяет `FactionManager.apply_reputation_event()`, `QuestService`
##   (журнал + опыт + репутация) и `Journal.record_event()`.

const MAX_LINE_CHARS: int = DialogueText.MAX_LINE_CHARS
const MAX_LINES: int = DialogueText.MAX_LINES
const COMPACT_MAX_LINES: int = DialogueText.COMPACT_MAX_LINES

var data: DialogueData = null
var language: String = "ru"

var _node: DialogueNode = null
var _pages: PackedStringArray = PackedStringArray()
var _page_index: int = 0
var _answer_views: Array[Dictionary] = []
var _history: Array[StringName] = []
var _effects: Array[Dictionary] = []
var _ended: bool = true
var _ended_reason: String = ""


func _init(dialogue: DialogueData = null, locale: String = "ru") -> void:
	data = dialogue
	language = DialogueText.normalize_language(locale)


## Начать диалог со стартового узла (с учётом условия входа).
func start() -> Dictionary:
	_history.clear()
	_effects.clear()
	_ended = false
	_ended_reason = ""

	if data == null or not data.is_valid():
		_node = null
		_pages = PackedStringArray([""])
		_page_index = 0
		_answer_views.clear()
		_ended = true
		_ended_reason = "invalid_dialogue"
		return get_snapshot()

	return _enter_node(data.start_node_id)


func set_language(locale: String) -> void:
	var normalized: String = DialogueText.normalize_language(locale)
	if normalized == language:
		return
	language = normalized
	if _node != null:
		_rebuild_page()


func get_snapshot() -> Dictionary:
	var text: String = ""
	if _page_index >= 0 and _page_index < _pages.size():
		text = _pages[_page_index]
	var has_next_page: bool = _page_index < _pages.size() - 1
	var answers: Array = []
	if not has_next_page and _node != null:
		answers = _answer_views.duplicate(true)

	return {
		"dialogue_id": data.id if data != null else &"",
		"npc_id": data.npc_id if data != null else &"",
		"node_id": _node.id if _node != null else &"",
		"speaker": _speaker(),
		"faction": (
			FactionManager.get_faction_name(data.faction_id) if data != null else ""
		),
		"faction_id": data.faction_id if data != null else &"",
		"text": text,
		"page_index": _page_index,
		"page_count": _pages.size(),
		"has_next_page": has_next_page,
		"answers": answers,
		"ended": _ended,
		"ended_reason": _ended_reason,
	}


func get_current_node() -> DialogueNode:
	return _node


func get_current_node_id() -> StringName:
	return _node.id if _node != null else &""


func get_current_page() -> int:
	return _page_index


func get_page_count() -> int:
	return _pages.size()


func has_next_page() -> bool:
	return _page_index < _pages.size() - 1


## Перелистнуть страницу. false — страница последняя.
func next_page() -> bool:
	if not has_next_page():
		return false
	_page_index += 1
	return true


func is_ended() -> bool:
	return _ended


func get_ended_reason() -> String:
	return _ended_reason


func get_history() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(_history)
	return copy


func get_effects() -> Array[Dictionary]:
	return _effects.duplicate(true)


## Выбрать ответ. Ответы доступны только на последней странице.
## Результат: `{ok, answer_id, effects, ended, reason, snapshot}`.
func select_answer(index: int) -> Dictionary:
	if _ended or _node == null:
		return _failure("dialogue_ended")
	if has_next_page():
		return _failure("page_not_finished")
	if index < 0 or index >= _answer_views.size():
		return _failure("unknown_answer")

	var view: Dictionary = _answer_views[index]
	if bool(view.get("disabled", false)):
		return _failure("unavailable", str(view.get("reason", "")))

	var answer: DialogueAnswer = _node.answers[index]
	_history.append(_node.id)
	var answer_effects: Array[Dictionary] = _apply_answer(answer)
	_effects.append_array(answer_effects)

	var next_node_id: StringName = answer.next_node_id
	if next_node_id.is_empty():
		_node = null
		_answer_views.clear()
		_pages = PackedStringArray([""])
		_page_index = 0
		_ended = true
	else:
		_enter_node(next_node_id)

	return {
		"ok": true,
		"answer_id": answer.id,
		"effects": answer_effects,
		"ended": _ended,
		"reason": _ended_reason,
		"snapshot": get_snapshot(),
	}


func _failure(reason: String, detail: String = "") -> Dictionary:
	var empty_effects: Array[Dictionary] = []
	return {
		"ok": false,
		"answer_id": &"",
		"effects": empty_effects,
		"ended": _ended,
		"reason": reason,
		"detail": detail,
		"snapshot": get_snapshot(),
	}


# ------------------------------------------------------------------------------
# Graph
# ------------------------------------------------------------------------------

func _enter_node(node_id: StringName, visited: Array = []) -> Dictionary:
	if visited.has(node_id):
		return _end_with_reason("dialogue_cycle")

	var node: DialogueNode = data.get_node_by_id(node_id)
	if node == null:
		push_warning("DialogueRunner: node '%s' not found in '%s'" % [node_id, data.id])
		return _end_with_reason("missing_node")

	if node.condition != null:
		var check: Dictionary = node.condition.check(data.faction_id, language)
		if not bool(check.get("met", true)):
			if not node.fallback_node_id.is_empty():
				var next_visited: Array = visited.duplicate()
				next_visited.append(node_id)
				return _enter_node(node.fallback_node_id, next_visited)
			return _end_with_reason(str(check.get("reason", "condition_failed")))

	_node = node
	_rebuild_page()

	if node.answers.is_empty():
		_ended_reason = ""
	return get_snapshot()


func _end_with_reason(reason: String) -> Dictionary:
	_node = null
	_answer_views.clear()
	_pages = PackedStringArray([""])
	_page_index = 0
	_ended = true
	_ended_reason = reason
	return get_snapshot()


func _rebuild_page() -> void:
	if _node == null:
		return
	_build_answer_views()
	var max_lines: int = COMPACT_MAX_LINES if _has_disabled_with_reason() else MAX_LINES
	_pages = DialogueText.paginate(_node.get_text(language), MAX_LINE_CHARS, max_lines)
	_page_index = 0


func _build_answer_views() -> void:
	_answer_views.clear()
	if _node == null:
		return
	for index: int in _node.answers.size():
		var answer: DialogueAnswer = _node.answers[index]
		if answer == null:
			continue
		var check: Dictionary = {"met": true, "reason": ""}
		if answer.condition != null:
			check = answer.condition.check(data.faction_id, language)
		_answer_views.append({
			"index": index,
			"id": answer.id,
			"text": answer.get_text(language),
			"tag": _answer_tag(answer),
			"disabled": not bool(check.get("met", true)),
			"reason": str(check.get("reason", "")),
		})


func _has_disabled_with_reason() -> bool:
	for view: Dictionary in _answer_views:
		if bool(view.get("disabled", false)) and not str(view.get("reason", "")).is_empty():
			return true
	return false


func _speaker() -> String:
	if data == null:
		return ""
	if _node != null:
		var override_name: String = _node.get_speaker(language)
		if not override_name.is_empty():
			return override_name
	return data.get_display_name(language)


# ------------------------------------------------------------------------------
# Tags (AC-06.1)
# ------------------------------------------------------------------------------

## Тег последствия из Δ-таблицы T-27: «[Орден+15]», «[Вольные+5]».
## Показывается до выбора, поэтому игрок видит величину заранее.
func _answer_tag(answer: DialogueAnswer) -> String:
	if not answer.tag_override.is_empty():
		return answer.tag_override

	var events: Array[StringName] = answer.get_reputation_events()
	if events.is_empty():
		return ""

	var preferred: StringName = data.faction_id if data != null else &""
	var faction_id: StringName = &""
	var delta: int = 0
	if not preferred.is_empty():
		delta = _event_delta(preferred, events)
		if delta != 0:
			faction_id = preferred
	if faction_id.is_empty():
		for candidate: StringName in FactionManager.get_faction_ids():
			delta = _event_delta(candidate, events)
			if delta != 0:
				faction_id = candidate
				break
	if faction_id.is_empty():
		return ""

	var faction_name: String = FactionManager.get_faction_name(faction_id)
	if faction_name.is_empty():
		faction_name = String(faction_id)
	# Короткая форма как в макете: «Орден», а не «Орден Пепла».
	var space: int = faction_name.find(" ")
	if space > 0:
		faction_name = faction_name.substr(0, space)
	var sign_text: String = "+" if delta > 0 else ""
	return "[%s%s%d]" % [faction_name, sign_text, delta]


func _event_delta(faction_id: StringName, events: Array[StringName]) -> int:
	var total: int = 0
	for event_id: StringName in events:
		total += FactionManager.get_action_delta(faction_id, event_id)
	return total


# ------------------------------------------------------------------------------
# Consequences
# ------------------------------------------------------------------------------

func _apply_answer(answer: DialogueAnswer) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []

	if (
		not answer.reputation_event.is_empty()
		and answer.reputation_event != answer.complete_quest
	):
		effects.append_array(_apply_reputation_event(answer.reputation_event))

	if not answer.start_quest.is_empty():
		var started: Dictionary = QuestService.accept(answer.start_quest, language)
		effects.append({
			"kind": "quest_started",
			"ok": bool(started.get("ok", false)),
			"quest_id": answer.start_quest,
			"reason": str(started.get("reason", "")),
			"message": str(started.get("message", "")),
		})

	if not answer.complete_quest.is_empty():
		var completed: Dictionary = QuestService.complete(answer.complete_quest, language)
		effects.append({
			"kind": "quest_completed",
			"ok": bool(completed.get("ok", false)),
			"quest_id": answer.complete_quest,
			"title": str(completed.get("title", "")),
			"reason": str(completed.get("reason", "")),
			"xp": int((completed.get("xp", {}) as Dictionary).get("amount", 0)),
		})
		for entry: Dictionary in completed.get("reputation", []):
			effects.append({
				"kind": "reputation",
				"event_id": answer.complete_quest,
				"faction_id": entry.get("faction_id", &""),
				"delta": int(entry.get("delta", 0)),
				"value": int(entry.get("value", 0)),
				"reaction": entry.get("reaction", &""),
				"access_granted": bool(entry.get("access_granted", false)),
			})

	if not answer.journal_event.is_empty():
		var recorded: bool = Journal.record_event(
			answer.journal_event,
			answer.journal_text
		)
		effects.append({
			"kind": "journal",
			"ok": recorded,
			"event_id": answer.journal_event,
		})

	return effects


## Применить Δ-таблицу события (AC-06.1) и вернуть эффекты для UI/тестов.
func _apply_reputation_event(event_id: StringName) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	var results: Array[Dictionary] = FactionManager.apply_reputation_event(event_id)
	for entry: Dictionary in results:
		effects.append({
			"kind": "reputation",
			"event_id": event_id,
			"faction_id": entry.get("faction_id", &""),
			"delta": int(entry.get("delta", 0)),
			"value": int(entry.get("value", 0)),
			"reaction": entry.get("reaction", &""),
			"access_granted": bool(entry.get("access_granted", false)),
		})
	return effects
