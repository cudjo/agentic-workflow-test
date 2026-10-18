extends PlayerState
## Block — held while the block action is pressed (T-11 adds damage reduction
## and parry window using `t_parry`). Higher priority than Jump/Fall/Run/Idle,
## so jumping requires releasing block.


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.x = 0.0


func physics_update(_delta: float) -> void:
	if not player.is_block_held():
		finish_to_locomotion()
		return
	if not player.is_on_floor():
		machine.force_state(&"fall")
		return
	if player.try_roll():
		return
	if player.try_dash():
		return
	player.velocity.x = 0.0
