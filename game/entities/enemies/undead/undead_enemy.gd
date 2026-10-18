class_name UndeadEnemy
extends Enemy
## UndeadEnemy — нежить (T-12). Паттерн: после смерти поднимается
## `revive_count` раз с долей HP `revive_hp_ratio`; смерть проигрывает
## анимацию и лишь затем (с `revive_delay`) начинается новая «жизнь».
## Окончательная смерть — только когда возрождения исчерпаны.

var revives_left: int = 0


func _ready() -> void:
	revives_left = data.revive_count if data != null else 0
	super()


func _get_death_duration() -> float:
	if revives_left > 0:
		return maxf(balance.enemy_death_duration, 0.0) + maxf(data.revive_delay, 0.0)
	return maxf(balance.enemy_death_duration, 0.0)


func _try_revive() -> bool:
	if revives_left <= 0:
		return false
	revives_left -= 1
	hp = maxf(data.max_hp * data.revive_hp_ratio, 1.0)
	is_dead = false
	_death_elapsed = 0.0
	_flash_time_left = 0.0
	visual.modulate = data.get_body_color()
	visual.scale = Vector2.ONE
	collision_layer = CombatLayers.ENEMY_BODY
	collision_mask = CombatLayers.WORLD
	hurtbox.invulnerable = false
	hurtbox.monitorable = true
	fsm = _new_state_machine()
	_connect_state_machine()
	_last_position = global_position
	_stuck_time = 0.0
	patrol_wait_left = 0.0
	return true
