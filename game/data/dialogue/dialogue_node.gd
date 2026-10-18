class_name DialogueNode
extends Resource
## DialogueNode — узел диалога (T-28): реплика, условие входа, ответы.
##
## Узел с невыполненным условием не показывается: движок уходит в
## `fallback_node_id` (например, вежливый отказ при низкой репутации) либо
## завершает диалог с причиной. Ответы 2×2 задаются данными; порядок ответов
## в массиве — порядок ячеек сетки.

@export var id: StringName = &""
@export_multiline var text: String = ""
@export_multiline var text_en: String = ""
## Имя говорящего, если отличается от имени NPC (пусто — имя NPC).
@export var speaker: String = ""
@export var speaker_en: String = ""
## Условие входа в узел; пусто — узел доступен всегда.
@export var condition: DialogueCondition = null
## Куда уйти, если условие не выполнено (пусто — диалог завершается).
@export var fallback_node_id: StringName = &""
@export var answers: Array[DialogueAnswer] = []


func get_text(language: String = "ru") -> String:
	return DialogueText.pick(text, text_en, language)


func get_speaker(language: String = "ru") -> String:
	return DialogueText.pick(speaker, speaker_en, language)


func is_terminal() -> bool:
	return answers.is_empty()
