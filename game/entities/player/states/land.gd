extends PlayerState
## Land — short landing pose (DESIGN §7). Does not block input: jump, run and
## buffered actions are accepted immediately (AC-01.4).


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.x = 0.0
	player.on_landed()


func physics_update(_delta: float) -> void:
	if player.try_ground_jump():
		return
	if player.try_roll():
		return
	if player.try_attack():
		return
	if player.has_move_input():
		machine.force_state(&"run")
		return
	if time_in_state >= player.balance.t_land:
		finish_to_locomotion()
