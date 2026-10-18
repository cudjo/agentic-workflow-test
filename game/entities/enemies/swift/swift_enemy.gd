class_name SwiftEnemy
extends Enemy
## SwiftEnemy — быстрый враг (T-12). Паттерн: стремительный патруль и
## рывок-выпад в активной фазе атаки (`attack_lunge_speed` из данных).
## Низкое HP и короткий windup компенсируют скорость.


func _attack_tick(_delta: float) -> void:
	if data == null:
		return
	var active_start: float = maxf(data.attack_windup, 0.0)
	var active_end: float = active_start + maxf(data.attack_active, 0.0)
	if attack_timer >= active_start and attack_timer < active_end:
		velocity.x = float(facing) * data.attack_lunge_speed
