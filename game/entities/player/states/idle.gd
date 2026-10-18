extends PlayerState
## Idle — no horizontal input on the ground (DESIGN §7).


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.x = 0.0


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
	if player.has_move_input():
		machine.request_state(&"run")
