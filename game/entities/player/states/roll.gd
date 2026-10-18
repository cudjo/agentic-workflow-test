extends PlayerState
## Roll — dodge with i-frames on animation frames 2–5 (DESIGN §7).
## Costs E_roll stamina (paid by Player.try_roll before entering).
## Priority: Roll/Dash tier (80), so Attack/Block cannot cancel it.


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.x = float(player.facing) * player.balance.v_roll


func physics_update(_delta: float) -> void:
	player.velocity.x = float(player.facing) * player.balance.v_roll
	if time_in_state >= player.balance.t_roll:
		finish_to_locomotion()


func is_invulnerable() -> bool:
	return (
		time_in_state >= player.balance.roll_iframe_start
		and time_in_state < player.balance.roll_iframe_end
	)
