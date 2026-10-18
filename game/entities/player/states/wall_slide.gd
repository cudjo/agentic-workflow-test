extends PlayerState
## WallSlide — скольжение по стене (T-08, SPEC US-02, AC-02.3).
##
## Вход только из `fall` через `Player.try_wall_slide()`: способность
## `wall_climb` получена, игрок в воздухе, касается вертикальной стены и
## удерживает направление в её сторону. Без способности состояние не
## удерживает игрока — на первом тике выходит в `fall` (defence-in-depth
## для принудительных переходов).
##
## Скорость падения ограничена `V_wall_slide` из `balancing.tres`. Гравитация
## в этом состоянии применяется вручную (`uses_gravity() = false`), иначе
## общий тик `Player._physics_process` обходил бы предел скорости.
## Прыжок от стены — wall kick (`Player.try_wall_kick()` -> `states/wall_kick.gd`).
## Рывок (T-07) доступен как более приоритетное прерывание.

## Направление от игрока к стене; 0 — стена потеряна.
var wall_dir: int = 0


func enter(previous: StringName) -> void:
	super.enter(previous)
	wall_dir = player.get_wall_dir()
	# Если игрок уже разогнался в падении, сразу ограничиваем скорость.
	player.velocity.y = minf(player.velocity.y, player.balance.v_wall_slide)


func physics_update(delta: float) -> void:
	if not player.has_ability(AbilityWallClimb.ID):
		machine.force_state(&"fall")
		return
	if player.is_on_floor():
		machine.force_state(&"land")
		return
	if player.try_dash():
		return
	if player.try_wall_kick():
		return

	wall_dir = player.get_wall_dir()
	if not AbilityWallClimb.is_holding_into_wall(player.get_move_axis(), wall_dir):
		machine.force_state(&"fall")
		return

	player.velocity.x = float(wall_dir) * player.balance.v_walk
	player.velocity.y = minf(
		player.velocity.y + player.balance.get_gravity() * delta,
		player.balance.v_wall_slide
	)


## Предел V_wall_slide задаёт само состояние; общая гравитация отключена.
func uses_gravity() -> bool:
	return false
