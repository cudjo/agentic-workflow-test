extends PlayerState
## Dash — placeholder for the dash ability (T-07). Uses D_dash/T_dash from
## balancing.tres and grants i-frames for its whole duration.


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.x = float(player.facing) * (player.balance.d_dash / player.balance.t_dash)


func physics_update(_delta: float) -> void:
	player.velocity.x = float(player.facing) * (player.balance.d_dash / player.balance.t_dash)
	if time_in_state >= player.balance.t_dash:
		finish_to_locomotion()


func is_invulnerable() -> bool:
	return true
