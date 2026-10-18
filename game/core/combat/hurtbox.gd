class_name Hurtbox
extends Area2D
## Hurtbox — Area2D цели (T-10). Выставляет только свой слой
## (`collision_mask = 0`), получает урон от `Hitbox` и применяет реакцию:
## отбрасывание к родительскому телу и вспышку к спрайту (≤ 0.1 s, AC-03.1).
##
## Пути реакции можно переопределить в сцене; по умолчанию отбрасывание
## получает родительский узел, а вспышку — его первый CanvasItem-потомок.

signal damaged(damage: Damage)

@export_flags_2d_physics var hurt_layer: int = CombatLayers.ENEMY_HURTBOX
## Неуязвимость (i-frames переката/рывка, смерть) — урон не принимается.
@export var invulnerable: bool = false
## Применять отбрасывание/вспышку автоматически.
@export var apply_reactions: bool = true
## Переопределение цели отбрасывания (по умолчанию — родитель).
@export var knockback_target_path: NodePath
## Переопределение визуала для вспышки (по умолчанию — первый CanvasItem).
@export var flash_target_path: NodePath

var hit_count: int = 0
var last_damage: Damage = null
## Сколько вспышек реально показано (T-35: не более 3/с, DESIGN §4.5).
var flash_applied_count: int = 0

var _knockback_target: Node = null
var _flash_target: CanvasItem = null
var _flash_governor := FlashGovernor.new()


func _ready() -> void:
	collision_layer = hurt_layer
	collision_mask = 0
	monitoring = false
	monitorable = true
	_resolve_reaction_targets()


## Принимает попадание; возвращает false, если урон не прошёл (i-frames).
func receive_damage(damage: Damage) -> bool:
	if invulnerable or damage == null:
		return false
	last_damage = damage
	hit_count += 1
	damaged.emit(damage)
	if apply_reactions:
		damage.apply_knockback(_knockback_target)
		# T-35/DESIGN §9.3: до 3 вспышек/с; в режиме «Без мигания» — ни одной.
		if not _is_no_flash() and _flash_governor.try_flash(_now_sec()):
			flash_applied_count += 1
			damage.flash(_flash_target)
	return true


func set_invulnerable(value: bool) -> void:
	invulnerable = value


func _resolve_reaction_targets() -> void:
	if knockback_target_path.is_empty():
		_knockback_target = get_parent()
	else:
		_knockback_target = get_node_or_null(knockback_target_path)
	if flash_target_path.is_empty():
		_flash_target = _find_visual()
	else:
		_flash_target = get_node_or_null(flash_target_path) as CanvasItem


func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _is_no_flash() -> bool:
	var config := get_node_or_null("/root/Config")
	return config != null and bool(config.get("no_flash"))


func _find_visual() -> CanvasItem:
	var parent: Node = get_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		if child != self and child is CanvasItem:
			return child as CanvasItem
	return null
