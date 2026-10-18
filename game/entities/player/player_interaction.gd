class_name PlayerInteraction
extends Node
## Interact-система игрока (сборка T-01 + T-23 + T-28, Integration-02).
##
## По действию `interact` открывает ближайший интерактив в мире:
##   * `Bonfire` из группы `bonfires` → `Campfire.open(bonfire)` — единственная
##     точка сохранения (T-23/T-26);
##   * `DialogueNpc` (включая `TraderNpc`) из группы `dialogue_npcs` →
##     `DialogueScreen.open_npc(npc)` (T-28).
##
## Радиус: у костра — `BONFIRE_RADIUS` (у пропа нет своего радиуса), у NPC —
## `DialogueNpc.interaction_radius`. Из нескольких целей выбирается ближайшая.
##
## Блокировки: в бою (`GameState.in_combat`, EC-06) и во время перехода зоны
## (`SceneRouter.is_input_locked`, EC-12) не-боевые интерактивы не открываются;
## повторный `interact` при уже открытом костре/диалоге игнорируется.
##
## Узел живёт в `Player.tscn`; UI-экраны находятся по группам `campfire_ui` /
## `dialogue_ui`, которые выставляются при монтаже в `Main.tscn`.

const BONFIRE_GROUP: StringName = &"bonfires"
const NPC_GROUP: StringName = &"dialogue_npcs"
const CAMPFIRE_UI_GROUP: StringName = &"campfire_ui"
const DIALOGUE_UI_GROUP: StringName = &"dialogue_ui"

## Радиус взаимодействия с костром (px): проп рисуется 22×~21 px.
const BONFIRE_RADIUS: float = 24.0

var _owner: Node2D


func _ready() -> void:
	_owner = get_parent() as Node2D


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"interact"):
		return
	if try_interact():
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------
# Public API (интеграция + GUT)
# ------------------------------------------------------------------------------

## Открывает ближайший интерактив. true — экран открыт.
func try_interact() -> bool:
	if not can_interact():
		return false
	var target: Node2D = get_nearest_interactable()
	if target == null:
		return false

	if target is Bonfire:
		var campfire := _find_ui(CAMPFIRE_UI_GROUP) as Campfire
		if campfire == null:
			push_warning("PlayerInteraction: Campfire UI is not mounted (group 'campfire_ui')")
			return false
		return campfire.open(target as Bonfire)

	var npc := target as DialogueNpc
	if npc == null:
		return false
	var dialogue := _find_ui(DIALOGUE_UI_GROUP) as DialogueScreen
	if dialogue == null:
		push_warning("PlayerInteraction: DialogueScreen is not mounted (group 'dialogue_ui')")
		return false
	return dialogue.open_npc(npc)


## Ближайший интерактив в радиусе (без учёта блокировок боя/UI).
## Публичный: HUD-подсказки и GUT используют один и тот же выбор цели.
func get_nearest_interactable() -> Node2D:
	if _owner == null or not is_instance_valid(_owner):
		return null
	var tree := get_tree()
	if tree == null:
		return null

	var best: Node2D = null
	var best_distance: float = INF

	for node: Node in tree.get_nodes_in_group(BONFIRE_GROUP):
		var bonfire := node as Bonfire
		if bonfire == null or not is_instance_valid(bonfire):
			continue
		var distance: float = _distance_to(bonfire)
		if distance <= BONFIRE_RADIUS and distance < best_distance:
			best = bonfire
			best_distance = distance

	for node: Node in tree.get_nodes_in_group(NPC_GROUP):
		var npc := node as DialogueNpc
		if npc == null or not is_instance_valid(npc):
			continue
		var info: Dictionary = npc.get_interact_info()
		if not bool(info.get("can_interact", false)):
			continue
		var distance: float = _distance_to(npc)
		if distance <= npc.interaction_radius and distance < best_distance:
			best = npc
			best_distance = distance

	return best


## Разрешено ли взаимодействие в текущем состоянии игры.
func can_interact() -> bool:
	if _owner == null or not is_instance_valid(_owner):
		return false
	if _owner is Player and (_owner as Player).is_dead:
		return false
	if GameState.in_combat:
		return false
	if SceneRouter.has_method(&"is_input_locked") and SceneRouter.is_input_locked():
		return false
	if _is_ui_open(CAMPFIRE_UI_GROUP) or _is_ui_open(DIALOGUE_UI_GROUP):
		return false
	return true


# ------------------------------------------------------------------------------
# Внутреннее
# ------------------------------------------------------------------------------

func _distance_to(target: Node2D) -> float:
	return _owner.global_position.distance_to(target.global_position)


func _find_ui(group: StringName) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(group)


func _is_ui_open(group: StringName) -> bool:
	var ui: Node = _find_ui(group)
	if ui == null:
		return false
	return ui.has_method(&"is_open") and bool(ui.call(&"is_open"))
