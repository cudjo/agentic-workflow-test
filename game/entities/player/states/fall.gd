extends PlayerState
## Fall — descending after an apex or walking off an edge. Coyote-time jump
## is allowed here (0.1 s window from InputManager).


func physics_update(_delta: float) -> void:
	if player.is_on_floor():
		machine.force_state(&"land")
		return
	if player.try_coyote_jump():
		return
	player.velocity.x = player.get_move_axis() * player.balance.v_walk
