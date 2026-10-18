extends PlayerState
## DoubleJump — второй прыжок в воздухе (T-06, SPEC AC-02.1).
##
## Вход только через `Player.try_double_jump()`: способность разблокирована,
## воздушный прыжок ещё не потрачен. Импульс — `get_double_jump_velocity()`
## (высота `h_double_factor * H_jump` ≥ 0.8·H_jump из balancing.tres).
## Счётчик сбрасывается при приземлении (`states/land.gd`), поэтому здесь
## повторного двойного прыжка нет.


func enter(previous: StringName) -> void:
	super.enter(previous)
	player.velocity.y = -player.balance.get_double_jump_velocity()
	player.velocity.x = player.get_move_axis() * player.balance.v_walk
	player.play_double_jump_animation()


func physics_update(_delta: float) -> void:
	if player.try_dash():
		return
	if player.velocity.y >= 0.0:
		machine.force_state(&"fall")
		return
	player.velocity.x = player.get_move_axis() * player.balance.v_walk
