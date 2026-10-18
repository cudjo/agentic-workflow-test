extends PlayerState
## Attack — placeholder melee swing (T-10 adds hitboxes/combo). Timed by
## `t_attack`; can be cancelled by Roll/Dash (higher priority).


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.x = 0.0


func physics_update(_delta: float) -> void:
	if player.try_roll():
		return
	if player.try_dash():
		return
	if time_in_state >= player.balance.t_attack:
		finish_to_locomotion()
