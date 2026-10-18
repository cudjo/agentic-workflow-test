class_name EnemyProjectile
extends Area2D
## EnemyProjectile — снаряд дальнего врага (T-12). Летит по прямой,
## наносит урон через `Hitbox` из T-10 (слой enemy_hitbox → player_hurtbox),
## исчезает при попадании, столкновении с миром или по `lifetime` из данных.

@export var speed: float = 90.0
@export var lifetime: float = 1.5

var direction: Vector2 = Vector2.RIGHT

var _payload: Damage = null
var _knockback_force: float = 0.0
var _elapsed: float = 0.0
var _armed: bool = false

@onready var hitbox: Hitbox = $Hitbox
@onready var visual: Sprite2D = $Visual


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.WORLD
	monitoring = true
	monitorable = false
	hitbox.hit_layer = CombatLayers.ENEMY_HITBOX
	hitbox.target_mask = CombatLayers.PLAYER_HURTBOX
	hitbox.collision_layer = CombatLayers.ENEMY_HITBOX
	hitbox.collision_mask = CombatLayers.PLAYER_HURTBOX
	hitbox.start_active = false
	hitbox.deactivate()
	hitbox.hit_landed.connect(_on_hit_landed)
	body_entered.connect(_on_body_entered)
	if _payload != null:
		_arm()


## Настройка после добавления в дерево (позиция/направление/урон).
func setup(
	payload: Damage,
	knockback_force: float,
	flight_direction: Vector2,
	speed_value: float,
	lifetime_value: float
) -> void:
	_payload = payload
	_knockback_force = maxf(knockback_force, 0.0)
	direction = (
		flight_direction.normalized()
		if not flight_direction.is_zero_approx()
		else Vector2.RIGHT
	)
	speed = maxf(speed_value, 0.0)
	lifetime = maxf(lifetime_value, 0.0)
	if visual != null:
		visual.flip_h = direction.x < 0.0
	if is_node_ready():
		_arm()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if lifetime > 0.0 and _elapsed >= lifetime:
		queue_free()
		return
	position += direction * speed * delta


func _arm() -> void:
	if _armed or _payload == null:
		return
	_armed = true
	hitbox.clear_hits()
	hitbox.activate(_payload, _knockback_force, direction)


func _on_hit_landed(_hurtbox: Hurtbox, _damage: Damage) -> void:
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is StaticBody2D:
		queue_free()
