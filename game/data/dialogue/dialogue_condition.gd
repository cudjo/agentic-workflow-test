class_name DialogueCondition
extends Resource
## DialogueCondition — условие узла/ответа диалога (T-28, AC-06.1, AC-06.2, EC-11).
##
## Данные (`data/dialogue/*.tres`) описывают условие декларативно, движок
## (`core/dialogue/dialogue_runner.gd`) только спрашивает `check()`.
## Поддерживаются:
##   * репутация фракции в диапазоне `min_reputation…max_reputation`;
##   * минимальная реакция NPC (`hostile < wary < neutral < friendly < trusted`);
##   * завершённые (`required_quests`) и активные (`active_quests`) квесты;
##   * доступ торговца (`require_trade_access`) — причина берётся из
##     `FactionManager.get_access_info(..., TRADER)`, поэтому текст отказа
##     совпадает с AC-06.2 в диалоге и в лавке.
##
## `check()` возвращает `{met, reason, faction_id, reputation}`, где `reason`
## локализован (RU/EN) и пригоден для отключённого ответа.

const MIN_SCALE: int = -100
const MAX_SCALE: int = 100

const REACTION_RANKS: Dictionary = {
	&"hostile": 0,
	&"wary": 1,
	&"neutral": 2,
	&"friendly": 3,
	&"trusted": 4,
}

const REACTION_NAMES_RU: Dictionary = {
	&"hostile": "вражда",
	&"wary": "настороженность",
	&"neutral": "нейтралитет",
	&"friendly": "дружба",
	&"trusted": "доверие",
}

const REACTION_NAMES_EN: Dictionary = {
	&"hostile": "hostility",
	&"wary": "wariness",
	&"neutral": "neutrality",
	&"friendly": "friendship",
	&"trusted": "trust",
}

## Фракция условия; пусто — фракция говорящего NPC.
@export var faction_id: StringName = &""
@export_range(MIN_SCALE, MAX_SCALE, 1) var min_reputation: int = MIN_SCALE
@export_range(MIN_SCALE, MAX_SCALE, 1) var max_reputation: int = MAX_SCALE
## Минимальная реакция NPC (пусто — без ограничения).
@export var min_reaction: StringName = &""
## Квесты, которые должны быть завершены.
@export var required_quests: Array[StringName] = []
## Квесты, которые должны быть активны.
@export var active_quests: Array[StringName] = []
## Требуется доступ к торговцу фракции (AC-06.2).
@export var require_trade_access: bool = false


## Условие ничего не ограничивает.
func is_empty() -> bool:
	return (
		min_reputation <= MIN_SCALE
		and max_reputation >= MAX_SCALE
		and min_reaction == &""
		and required_quests.is_empty()
		and active_quests.is_empty()
		and not require_trade_access
	)


## Проверка условия. `default_faction` — фракция NPC, если `faction_id` пуст.
func check(default_faction: StringName = &"", language: String = "ru") -> Dictionary:
	var target: StringName = faction_id if faction_id != &"" else default_faction
	var reputation: int = FactionManager.get_reputation(target)
	var result: Dictionary = {
		"met": true,
		"reason": "",
		"faction_id": target,
		"reputation": reputation,
	}
	if is_empty():
		return result

	if not target.is_empty() or min_reputation > MIN_SCALE or max_reputation < MAX_SCALE:
		if reputation < min_reputation:
			return _fail(
				result,
				_reason_reputation(target, reputation, language, true)
			)
		if reputation > max_reputation:
			return _fail(
				result,
				_reason_reputation(target, reputation, language, false)
			)

	if not min_reaction.is_empty():
		var required_rank: int = int(REACTION_RANKS.get(min_reaction, -1))
		if required_rank >= 0:
			var reaction: StringName = FactionManager.get_npc_reaction(target)
			var current_rank: int = int(REACTION_RANKS.get(reaction, 0))
			if current_rank < required_rank:
				return _fail(
					result,
					_reason_reaction(reaction, min_reaction, language)
				)

	for quest_id: StringName in required_quests:
		if not Journal.is_completed(quest_id):
			return _fail(
				result,
				_reason_quest(quest_id, language, false)
			)

	for quest_id: StringName in active_quests:
		if not Journal.is_active(quest_id):
			return _fail(
				result,
				_reason_quest(quest_id, language, true)
			)

	if require_trade_access:
		var access: Dictionary = FactionManager.get_access_info(
			target,
			FactionManager.AccessKind.TRADER
		)
		if not bool(access.get("allowed", false)):
			return _fail(result, _reason_trade(target, access, language))

	return result


func _fail(result: Dictionary, reason: String) -> Dictionary:
	result["met"] = false
	result["reason"] = reason
	return result


func _reason_reputation(
	_faction_id: StringName,
	_reputation: int,
	language: String,
	minimum: bool
) -> String:
	# Причина рисуется в ячейке ответа 2×2 (~173 px = ~21 символ), поэтому
	# она короткая; полное объяснение с фракцией даёт FactionManager/лавка.
	if DialogueText.is_english(language):
		if minimum:
			return "Requires reputation %d" % min_reputation
		return "Reputation at most %d" % max_reputation
	if minimum:
		return "Нужна репутация %d" % min_reputation
	return "Репутация не выше %d" % max_reputation


func _reason_reaction(
	_current: StringName,
	required: StringName,
	language: String
) -> String:
	var names: Dictionary = REACTION_NAMES_EN if DialogueText.is_english(language) else REACTION_NAMES_RU
	var required_text: String = str(names.get(required, String(required)))
	if DialogueText.is_english(language):
		return "Requires %s" % required_text
	return "Нужна %s" % required_text


func _reason_quest(_quest_id: StringName, language: String, active: bool) -> String:
	if DialogueText.is_english(language):
		return "Quest is not active" if active else "Quest not completed"
	return "Нужен активный квест" if active else "Квест не завершён"


func _reason_trade(
	faction_id: StringName,
	access: Dictionary,
	language: String
) -> String:
	if not FactionManager.has_faction(faction_id):
		return "Access denied" if DialogueText.is_english(language) else "Доступ закрыт"
	var threshold: int = int(access.get("threshold", 0))
	if DialogueText.is_english(language):
		return "Requires reputation %d" % threshold
	return "Нужна репутация %d" % threshold
