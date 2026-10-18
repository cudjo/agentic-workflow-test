class_name DialogueData
extends Resource
## DialogueData — диалог NPC целиком (T-28). Файлы: `data/dialogue/*.tres`.
##
## Содержит личность NPC (id, имя RU/EN, фракция, портрет) и граф узлов.
## Логика проигрывания — `core/dialogue/dialogue_runner.gd`, загрузка —
## `DialogueCatalog`. Данные проходят `is_valid()`: стартовый узел существует,
## id узлов уникальны, все переходы/fallback ведут в существующие узлы.

@export_group("Identity")
@export var id: StringName = &""
@export var npc_id: StringName = &""
@export var display_name: String = ""
@export var display_name_en: String = ""
## Фракция NPC: используется для проверок условий и реакции (T-27).
@export var faction_id: StringName = &""
## Портрет 52×52 для диалогового бокса (`UITokens.PORTRAIT_DIALOG`).
@export var portrait: Texture2D = null

@export_group("Graph")
@export var start_node_id: StringName = &""
@export var nodes: Array[DialogueNode] = []


func get_display_name(language: String = "ru") -> String:
	return DialogueText.pick(display_name, display_name_en, language)


func get_node_by_id(node_id: StringName) -> DialogueNode:
	if node_id.is_empty():
		return null
	for node: DialogueNode in nodes:
		if node != null and node.id == node_id:
			return node
	return null


func get_start_node() -> DialogueNode:
	return get_node_by_id(start_node_id)


func get_node_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for node: DialogueNode in nodes:
		if node != null and not node.id.is_empty():
			result.append(node.id)
	return result


## Данные пригодны для проигрывания: есть личность, стартовый узел и
## корректные ссылки. Ошибки не «лечатся» молча — вызывающий решает.
func is_valid() -> bool:
	if id.is_empty() or display_name.strip_edges().is_empty():
		return false
	if nodes.is_empty() or get_start_node() == null:
		return false

	var seen: Dictionary = {}
	for node: DialogueNode in nodes:
		if node == null or node.id.is_empty():
			return false
		if seen.has(node.id):
			return false
		seen[node.id] = true

	for node: DialogueNode in nodes:
		if not node.fallback_node_id.is_empty() and get_node_by_id(node.fallback_node_id) == null:
			return false
		for answer: DialogueAnswer in node.answers:
			if answer == null:
				return false
			if (
				not answer.next_node_id.is_empty()
				and get_node_by_id(answer.next_node_id) == null
			):
				return false
	return true
