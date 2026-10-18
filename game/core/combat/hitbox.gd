class_name Hitbox
extends Area2D
## Hitbox — Area2D атакующего (T-10). Живёт на слое `*_hitbox` и маскирует
## hurtbox цели (CombatLayers). Урон/отбрасывание задаются из данных оружия
## и `balancing.tres` через `activate()`.
##
## Опрос `get_overlapping_areas()` используется вместо `area_entered`, чтобы
## попадание срабатывало и тогда, когда мониторинг включается уже поверх цели
## (короткое активное окно удара). Каждый hurtbox получает урон не более
## одного раза за шаг комбо (`clear_hits()` между шагами).

signal hit_landed(hurtbox: Hurtbox, damage: Damage)

@export_flags_2d_physics var hit_layer: int = CombatLayers.PLAYER_HITBOX
@export_flags_2d_physics var target_mask: int = CombatLayers.ENEMY_HURTBOX
## Активен сразу после появления (обычно false: включает состояние атаки).
@export var start_active: bool = false

var active: bool = false

var _damage: Damage = null
var _knockback_force: float = 0.0
var _direction: Vector2 = Vector2.RIGHT
var _already_hit: Array[Node] = []


func _ready() -> void:
	collision_layer = hit_layer
	collision_mask = target_mask
	monitorable = false
	monitoring = start_active
	active = start_active


## Включает хитбокс на активную фазу удара.
func activate(damage: Damage, knockback_force: float, direction: Vector2) -> void:
	_damage = damage
	_knockback_force = maxf(knockback_force, 0.0)
	_direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	active = true
	monitoring = true


func deactivate() -> void:
	active = false
	monitoring = false


## Сбрасывает список уже задетых целей (новый шаг комбо / новый взмах).
func clear_hits() -> void:
	_already_hit.clear()


func _physics_process(_delta: float) -> void:
	if not active or _damage == null:
		return
	for area: Area2D in get_overlapping_areas():
		if not area is Hurtbox:
			continue
		if _already_hit.has(area):
			continue
		_already_hit.append(area)
		var hurtbox := area as Hurtbox
		var payload: Damage = _damage.duplicate_damage()
		payload.knockback = _direction * _knockback_force
		payload.source = self
		if hurtbox.receive_damage(payload):
			hit_landed.emit(hurtbox, payload)
