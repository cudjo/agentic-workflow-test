class_name DialogueNpc
extends Node2D
## DialogueNpc — NPC с диалогом, именем и портретом 52×52 (T-28, US-06).
##
## Данные — `DialogueData` из `data/dialogue/*.tres`: имя RU/EN, фракция,
## портрет, граф реплик. NPC не рисует UI: он отдаёт `DialogueRunner` и
## `get_interact_info()` диалоговому экрану (`ui/dialogue/DialogueScreen`),
## который переиспользует `AshenDialog` (T-18).
##
## Реакция NPC (`hostile`…`trusted`) читается из `FactionManager`, поэтому
## диалог и доступ торговца всегда согласованы с репутацией (T-27).

@export var dialogue_id: StringName = &""
## Можно назначить ресурс напрямую в сцене; иначе загружается по `dialogue_id`.
@export var dialogue: DialogueData = null
## Переопределение имени (пусто — имя из данных диалога).
@export var display_name_override: String = ""
## Переопределение портрета (пусто — портрет из данных/заглушка AshenDialog).
@export var portrait_override: Texture2D = null
## Радиус взаимодействия для контроллера мира (px).
@export var interaction_radius: float = 16.0
## Цвет силуэта-заглушки в мире до арта NPC.
@export var placeholder_color: Color = Color(0.29, 0.32, 0.36, 1.0)

## Группа для interact-системы игрока (Integration-02): `DialogueNpc` и
## `TraderNpc` находятся одним запросом, без обхода дерева зоны.
const GROUP: StringName = &"dialogue_npcs"


func _ready() -> void:
	add_to_group(GROUP)


func get_data() -> DialogueData:
	if dialogue == null and not dialogue_id.is_empty():
		dialogue = DialogueCatalog.load_dialogue(dialogue_id)
	return dialogue


func get_dialogue_id() -> StringName:
	var data: DialogueData = get_data()
	if data != null:
		return data.id
	return dialogue_id


func get_npc_id() -> StringName:
	var data: DialogueData = get_data()
	if data != null:
		if not data.npc_id.is_empty():
			return data.npc_id
		return data.id
	return StringName(name)


func get_display_name(language: String = "ru") -> String:
	if not display_name_override.is_empty():
		return display_name_override
	var data: DialogueData = get_data()
	if data != null:
		return data.get_display_name(language)
	return name


func get_faction_id() -> StringName:
	var data: DialogueData = get_data()
	return data.faction_id if data != null else &""


func get_faction_name() -> String:
	return FactionManager.get_faction_name(get_faction_id())


func get_portrait() -> Texture2D:
	if portrait_override != null:
		return portrait_override
	var data: DialogueData = get_data()
	return data.portrait if data != null else null


## Размер рамки портрета в диалоговом боксе (52×52, DESIGN §6.4).
func get_portrait_frame_size() -> Vector2i:
	return Vector2i(UITokens.PORTRAIT_DIALOG, UITokens.PORTRAIT_DIALOG)


## Отношение NPC по текущей репутации (T-27): hostile/wary/neutral/friendly/
## trusted. `neutral` для NPC без фракции.
func get_reaction() -> StringName:
	var faction_id: StringName = get_faction_id()
	if faction_id.is_empty():
		return FactionManager.REACTION_NEUTRAL
	return FactionManager.get_npc_reaction(faction_id)


## Снимок для диалогового экрана/тестов:
## `{npc_id, display_name, portrait, portrait_size, faction_id, faction_name,
##   reaction, dialogue_id, interaction_radius, can_interact, reason}`.
func get_interact_info(language: String = "ru") -> Dictionary:
	var data: DialogueData = get_data()
	var can_interact: bool = data != null and data.is_valid()
	var reason: String = ""
	if not can_interact:
		reason = LocaleText.translate_for(language, "npc.dialogue.missing")
	return {
		"npc_id": get_npc_id(),
		"display_name": get_display_name(language),
		"portrait": get_portrait(),
		"portrait_size": get_portrait_frame_size(),
		"faction_id": get_faction_id(),
		"faction_name": get_faction_name(),
		"reaction": get_reaction(),
		"dialogue_id": get_dialogue_id(),
		"interaction_radius": interaction_radius,
		"can_interact": can_interact,
		"reason": reason,
	}


## Готовый движок диалога (null — диалог не настроен).
func create_runner(language: String = "ru") -> DialogueRunner:
	var data: DialogueData = get_data()
	if data == null or not data.is_valid():
		return null
	var runner := DialogueRunner.new(data, language)
	runner.start()
	return runner


## Взаимодействие из мира: `{ok, runner, info}`. UI открывает диалог сам.
func interact(language: String = "ru") -> Dictionary:
	var info: Dictionary = get_interact_info(language)
	var runner: DialogueRunner = create_runner(language)
	return {
		"ok": runner != null,
		"runner": runner,
		"info": info,
	}


# Заглушка до арта: капюшон и плащ 12×20 px в палитре stone/steel.
func _draw() -> void:
	draw_rect(Rect2(-6, -20, 12, 4), placeholder_color.lightened(0.15))
	draw_rect(Rect2(-5, -16, 10, 3), placeholder_color.lightened(0.15))
	draw_rect(Rect2(-3, -16, 6, 5), UITokens.STONE_5)
	draw_rect(Rect2(-7, -11, 14, 11), placeholder_color)
	draw_rect(Rect2(-1, -9, 2, 9), placeholder_color.darkened(0.2))
