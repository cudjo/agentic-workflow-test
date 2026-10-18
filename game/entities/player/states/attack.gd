extends PlayerState
## Attack — melee swing driven by weapon data and the combo tracker (T-10).
##
## Timing: each step lasts `t_attack * weapon.attack_speed` (balancing.tres);
## the Hitbox is active during `combo_hit_start_ratio..combo_hit_end_ratio` of
## the step. Pressing attack inside the link window chains the next hit and
## spends E_attack again. Roll/Dash (higher priority) still cancel the swing.

func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity.x = 0.0
	player.sync_attack_hitbox()


func exit(_next: StringName) -> void:
	player.stop_attack_hitbox()


func physics_update(_delta: float) -> void:
	if player.try_roll():
		return
	if player.try_dash():
		return
	if InputManager.just_pressed(&"attack") and player.try_link_attack():
		player.sync_attack_hitbox()
	if player.advance_combo(_delta):
		player.stop_attack_hitbox()
		finish_to_locomotion()
		return
	player.sync_attack_hitbox()
