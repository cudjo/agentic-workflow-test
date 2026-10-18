class_name QuestData
extends Resource
## QuestData — данные квеста (T-28). Файлы: `data/quests/*.tres`.
##
## Владелец квеста определяется по `data/factions/*.tres` (`FactionData.quests`),
## поэтому здесь `faction_id` — справочное поле для журнала. Опыт за квест
## берётся из `data/balance/progression.tres` (`quest_xp`), репутация — из
## Δ-таблиц фракций, чтобы не дублировать числа.

@export var id: StringName = &""
@export var title: String = ""
@export var title_en: String = ""
@export_multiline var description: String = ""
@export_multiline var description_en: String = ""
@export var faction_id: StringName = &""


func get_title(language: String = "ru") -> String:
	return DialogueText.pick(title, title_en, language)


func get_description(language: String = "ru") -> String:
	return DialogueText.pick(description, description_en, language)


func is_valid() -> bool:
	return not id.is_empty() and not title.strip_edges().is_empty()
