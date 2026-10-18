class_name DialogueAnswer
extends Resource
## DialogueAnswer — вариант ответа в узле диалога (T-28).
##
## Ответ может быть недоступен (условие по репутации/квестам/торговле),
## вести в следующий узел и нести последствия:
##   * `reputation_event` — id из Δ-таблицы `FactionData.reputation_events`,
##     применяется через `FactionManager.apply_reputation_event()` (AC-06.1);
##   * `start_quest` / `complete_quest` — жизненный цикл квеста через
##     `QuestService` (журнал + опыт + репутация);
##   * `journal_event` / `journal_text` — запись события в `Journal` (T-24).
##
## Тег `[Фракция±N]` не хранится в данных: движок считает его из Δ-таблицы
## фракций, поэтому число в теге всегда совпадает с фактическим изменением.

@export var id: StringName = &""
@export_multiline var text: String = ""
@export_multiline var text_en: String = ""
## Ручной тег, если последствие нельзя вывести из Δ-таблицы (редко).
@export var tag_override: String = ""
@export var condition: DialogueCondition = null
## Следующий узел; пусто — диалог завершается после ответа.
@export var next_node_id: StringName = &""
## Событие репутации (`action_*`/`quest_*`) из данных T-27.
@export var reputation_event: StringName = &""
## Выдать квест (проверка доступа — `FactionManager.get_quest_access`).
@export var start_quest: StringName = &""
## Завершить квест (репутация + опыт + журнал).
@export var complete_quest: StringName = &""
## Записать событие в журнал (T-24).
@export var journal_event: StringName = &""
@export_multiline var journal_text: String = ""


func get_text(language: String = "ru") -> String:
	return DialogueText.pick(text, text_en, language)


func has_consequence() -> bool:
	return (
		not reputation_event.is_empty()
		or not start_quest.is_empty()
		or not complete_quest.is_empty()
		or not journal_event.is_empty()
	)


## События, по которым считается тег последствия (без дублей).
func get_reputation_events() -> Array[StringName]:
	var events: Array[StringName] = []
	if not reputation_event.is_empty() and reputation_event != complete_quest:
		events.append(reputation_event)
	if not complete_quest.is_empty() and not events.has(complete_quest):
		events.append(complete_quest)
	return events
