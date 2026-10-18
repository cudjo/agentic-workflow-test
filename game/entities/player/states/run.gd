extends PlayerState
## Run — horizontal input on the ground. Movement starts on the first frame
## (AC-01.1): `enter()` already applies V_walk.


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.x = player.get_move_axis() * player.balance.v_walk


func physics_update(_delta: float) -> void:
	if player.try_roll():
		return
	if player.try_dash():
		return
	if player.try_attack():
		return
	if player.is_block_held() and player.try_block():
		return
	if player.try_ground_jump():
		return
	if not player.is_on_floor() and player.velocity.y >= 0.0:
		player.begin_coyote_time()
		machine.force_state(&"fall")
		return
	var axis: float = player.get_move_axis()
	if is_zero_approx(axis):
		machine.force_state(&"idle")
		return
	player.velocity.x = axis * player.balance.v_walk
