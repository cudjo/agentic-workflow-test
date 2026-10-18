class_name Bonfire
extends Node2D
## Костёр — точка возрождения и единственная точка сохранения (T-26,
## AC-05.1/AC-05.2, EC-06). Проп из T-13 (палитра зоны), расширен в T-26.
##
## Чекпоинт: при контакте игрока (Area2D `InteractArea`) костёр становится
## последней точкой возрождения — `GameState.set_respawn_bonfire()`.
## Сохранение: `save_to_slot()` пишет слот через SaveManager; в бою
## (`GameState.in_combat`) запись запрещена и эмитится `EventBus.save_failed`
## с причиной `in_combat` (EC-06). Других точек сохранения в игре нет —
## UI костра (T-23) обязан вызывать этот метод.
##
## `zone_id` обычно выводится из родительской ZoneScene; `bonfire_id` задаётся
## в сцене/инстансе, чтобы сейв знал точку возрождения.

signal checkpoint_activated(bonfire_id: StringName)

const SAVE_REASON_IN_COMBAT: String = "in_combat"
const PLAYER_GROUP: StringName = &"player"

@export var flame_color: Color = Color("c08a3e"):
	set(value):
		flame_color = value
		queue_redraw()

## Id костра в пределах зоны (ключ `zone_id/bonfire_id` в GameState).
@export var bonfire_id: StringName = &"bonfire"
## Id зоны; пусто — берётся из ZoneScene/GameState.
@export var zone_id: StringName = &""
## Смещение точки спавна игрока от origin костра (origin — у земли).
@export var respawn_offset: Vector2 = Vector2(0, -12)

var _area: Area2D


func _ready() -> void:
	add_to_group(&"bonfires")
	if zone_id == &"":
		zone_id = _find_zone_id()
	_area = get_node_or_null("InteractArea") as Area2D
	if _area != null and not _area.body_entered.is_connected(_on_body_entered):
		_area.body_entered.connect(_on_body_entered)


## Активирует костёр как чекпоинт (контакт игрока или сохранение).
func activate_checkpoint() -> void:
	if zone_id == &"":
		zone_id = _find_zone_id()
	if zone_id == &"":
		zone_id = GameState.current_zone_id
	GameState.set_respawn_bonfire(zone_id, bonfire_id, global_position + respawn_offset)
	checkpoint_activated.emit(bonfire_id)


## Сохранение в бою запрещено (Q3, EC-06).
func can_save() -> bool:
	return not GameState.in_combat


## Единственная точка сохранения: слот 1..3. В бою возвращает false и
## эмитит `save_failed(slot, "in_combat")` без записи на диск (EC-06).
func save_to_slot(slot: int, metadata: Dictionary = {}) -> bool:
	activate_checkpoint()
	if not can_save():
		EventBus.save_failed.emit(slot, SAVE_REASON_IN_COMBAT)
		return false

	var slot_metadata: Dictionary = metadata.duplicate(true)
	if str(slot_metadata.get("zone_id", "")).is_empty():
		slot_metadata["zone_id"] = String(zone_id)
	if not slot_metadata.has("zone_name"):
		slot_metadata["zone_name"] = _find_zone_name()
	return SaveManager.save_slot(slot, slot_metadata)


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group(PLAYER_GROUP):
		return
	activate_checkpoint()


func _find_zone_scene() -> ZoneScene:
	var node: Node = get_parent()
	while node != null:
		if node is ZoneScene:
			return node as ZoneScene
		node = node.get_parent()
	return null


func _find_zone_id() -> StringName:
	var zone: ZoneScene = _find_zone_scene()
	if zone != null and zone.zone_data != null:
		return zone.zone_data.id
	return &""


func _find_zone_name() -> String:
	var zone: ZoneScene = _find_zone_scene()
	if zone != null and zone.zone_data != null:
		return zone.zone_data.get_display_name()
	return ""


func _draw() -> void:
	# Камни вокруг основания (ось Y — вниз, origin у земли).
	draw_rect(Rect2(-11, -4, 22, 4), Color("303035"))
	draw_rect(Rect2(-9, -6, 18, 3), Color("3b2e22"))
	# Пламя: три ступени, верхняя светлее.
	draw_rect(Rect2(-5, -14, 10, 8), flame_color)
	draw_rect(Rect2(-3, -18, 6, 5), flame_color.lightened(0.22))
	draw_rect(Rect2(-1, -21, 2, 4), flame_color.lightened(0.45))
