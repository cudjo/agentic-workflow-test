extends PlayerState
## Block — held while the block action is pressed (T-11).
##
## AC-03.2: the state pays E_block on entry (`Player.try_block()`), opens the
## T_parry window (`Block.begin()`), then keeps an ordinary block that reduces
## damage by P_block % inside the front arc. A hit inside T_parry is parried:
## no damage, parry spark + SFX `parry`, and a counter-attack window opens.
##
## Higher priority than Jump/Fall/Run/Idle, so jumping requires releasing block.
## Death/Hurt/Roll/Dash still interrupt it.


func enter(previous: StringName) -> void:
	super.enter(previous)
	player.velocity.x = 0.0
	player.begin_block()


func exit(_next: StringName) -> void:
	player.end_block()


func physics_update(_delta: float) -> void:
	if not player.is_block_held():
		finish_to_locomotion()
		return
	if not player.is_on_floor():
		machine.force_state(&"fall")
		return
	# Парирование открыло контратаку: attack превращается в бесплатный удар.
	if player.try_parry_counter():
		return
	if player.try_roll():
		return
	if player.try_dash():
		return
	player.velocity.x = 0.0
