extends PlayerState
## Hurt — short stagger after taking damage (DESIGN §7, 120 ms).
## Interrupts Roll/Dash and everything below; cannot be interrupted by gameplay
## actions, only by Death.


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.x = 0.0


func physics_update(_delta: float) -> void:
	if time_in_state >= player.balance.t_hurt:
		finish_to_locomotion()
		return
	player.velocity.x = 0.0
