extends PlayerState
## Jump — ascending part of the jump (DESIGN §7: while vy < 0).


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.y = -player.balance.get_jump_velocity()
	player.velocity.x = player.get_move_axis() * player.balance.v_walk


func physics_update(_delta: float) -> void:
	if player.velocity.y >= 0.0:
		machine.force_state(&"fall")
		return
	player.velocity.x = player.get_move_axis() * player.balance.v_walk
