extends PlayerState
## WallKick — прыжок от стены (T-08, SPEC US-02, AC-02.3).
##
## Вход только через `Player.try_wall_kick()` из `wall_slide`: при нажатии
## прыжка у стены игрок получает горизонтальный импульс `V_wall_kick` в
## сторону, противоположную стене, и обычный вертикальный импульс прыжка.
## Импульс удерживается `t_wall_kick_lock` секунд — иначе удержание
## направления в стену сразу погасило бы отталкивание. После локка
## возвращается обычное управление, на апексе состояние уступает `fall`.

## Направление отталкивания (противоположное стене); 0 — запасной вариант.
var away_dir: int = 0


func enter(previous: StringName) -> void:
	super.enter(previous)
	away_dir = player.wall_kick_dir
	if away_dir == 0:
		away_dir = -player.facing
	player.wall_kick_dir = 0
	player.velocity.x = float(away_dir) * player.balance.v_wall_kick
	player.velocity.y = -player.balance.get_jump_velocity()


func physics_update(_delta: float) -> void:
	if player.is_on_floor():
		machine.force_state(&"land")
		return
	if player.try_dash():
		return
	if player.try_double_jump():
		return
	if time_in_state >= player.balance.t_wall_kick_lock:
		player.velocity.x = player.get_move_axis() * player.balance.v_walk
	if player.velocity.y >= 0.0:
		machine.force_state(&"fall")
