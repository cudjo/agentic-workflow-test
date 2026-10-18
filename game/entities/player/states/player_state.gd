class_name PlayerState
extends RefCounted
## Base class for player FSM states (T-04, DESIGN §7).
##
## A state owns one behaviour: it sets `player.velocity` and decides when to
## leave. Priority-based interrupts are enforced by `PlayerStateMachine`:
## Death > Hurt > Roll/Dash > Attack/Block > Jump/Fall > Run > Idle.

var player: Player
## Typed as Variant on purpose: PlayerStateMachine preloads every state script,
## so a `PlayerStateMachine` type here would create a cyclic class reference.
var machine
var state_name: StringName = &""
var priority: int = 0
var time_in_state: float = 0.0


func setup(p: Player, m, name: StringName, prio: int) -> void:
	player = p
	machine = m
	state_name = name
	priority = prio


func enter(_previous: StringName) -> void:
	time_in_state = 0.0


func exit(_next: StringName) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


## Whether Player applies manual gravity while this state is active.
func uses_gravity() -> bool:
	return true


## Dash/roll override this; hurtboxes (T-10) will query it.
func is_invulnerable() -> bool:
	return false


## Common exit back to locomotion after a timed state (attack/land/hurt/dash/roll).
func finish_to_locomotion() -> void:
	if not player.is_on_floor():
		machine.force_state(&"fall")
	elif player.has_move_input():
		machine.force_state(&"run")
	else:
		machine.force_state(&"idle")
