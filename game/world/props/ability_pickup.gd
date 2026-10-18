class_name AbilityPickup
extends Area2D
## AbilityPickup — точка получения способности по контакту (T-06, SPEC US-02).
##
## Поток: игрок входит в Area2D -> id способности из `AbilityRegistry`
## добавляется в `GameState.abilities` -> `GameState` эмитит
## `EventBus.ability_acquired` -> `Player` разблокирует поведение
## (`AbilityBase.activate()` ставит флаг `double_jump`).
##
## Точка одноразовая: после подбора скрывается и не выдаёт способность
## повторно (повторная загрузка сейва — забота T-25). Сцена:
## `world/props/ability_pickup.tscn`; `ability_id` задаётся в инспекторе.

signal collected(ability_id: StringName)

## Id способности из AbilityRegistry; по умолчанию — двойной прыжок.
@export var ability_id: StringName = AbilityDoubleJump.ID:
	set(value):
		ability_id = value
		queue_redraw()

## Одноразовая точка (по умолчанию): после подбора исчезает.
@export var one_shot: bool = true

var _collected: bool = false:
	set(value):
		_collected = value
		visible = not value
		# monitoring нельзя менять внутри сигнала physics-колбэка — отложенно.
		set_deferred(&"monitoring", not value)
		set_deferred(&"monitorable", not value)
		queue_redraw()


func _ready() -> void:
	if ability_id == &"":
		ability_id = AbilityDoubleJump.ID
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Подбор способности. Возвращает true, только если способность реально
## добавлена в GameState (первое получение).
func collect() -> bool:
	if _collected:
		return false
	var ability: AbilityBase = AbilityRegistry.get_ability(ability_id)
	if ability == null:
		push_warning("AbilityPickup: unknown ability '%s'" % ability_id)
		return false
	if one_shot:
		_collected = true
	var granted: bool = GameState.add_ability(ability.id)
	if granted:
		collected.emit(ability.id)
	return granted


## Точка уже подобрана (для тестов/сейвов).
func is_collected() -> bool:
	return _collected


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if not body.is_in_group(&"player"):
		return
	collect()


## Заглушка арта (до ассетов): тёмная оправа + золотое ядро способности.
func _draw() -> void:
	if _collected:
		return
	draw_rect(Rect2(-6.0, -7.0, 12.0, 14.0), Color("1a1f2e"))
	draw_rect(Rect2(-6.0, -7.0, 12.0, 1.0), Color("4a4a4f"))
	draw_rect(Rect2(-3.0, -3.0, 6.0, 6.0), Color("c08a3e"))
	draw_rect(Rect2(-1.0, -5.0, 2.0, 2.0), Color("e0b96a"))
