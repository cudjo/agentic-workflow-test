class_name PlayerStateMachine
extends Node
## PlayerStateMachine — priority-aware FSM for the player (T-04, DESIGN §7).
##
## Interrupt order: Death > Hurt > Roll/Dash > Attack/Block > Jump/Fall >
## Land > Run > Idle.
##   * `request_state()` is used for input-driven transitions and only lets a
##     strictly higher priority interrupt the current state.
##   * `force_state()` is used for natural lifecycle transitions inside one tier
##     (Jump -> Fall, Fall -> Land, timed state -> Idle/Run).

const PRIORITIES: Dictionary = {
	&"death": 100,
	&"hurt": 90,
	&"roll": 80,
	&"dash": 80,
	&"attack": 60,
	&"block": 60,
	&"jump": 50,
	&"double_jump": 50,
	&"fall": 50,
	&"land": 30,
	&"run": 10,
	&"idle": 0,
}

const STATE_SCRIPTS: Dictionary = {
	&"idle": preload("res://entities/player/states/idle.gd"),
	&"run": preload("res://entities/player/states/run.gd"),
	&"jump": preload("res://entities/player/states/jump.gd"),
	&"double_jump": preload("res://entities/player/states/double_jump.gd"),
	&"fall": preload("res://entities/player/states/fall.gd"),
	&"land": preload("res://entities/player/states/land.gd"),
	&"attack": preload("res://entities/player/states/attack.gd"),
	&"block": preload("res://entities/player/states/block.gd"),
	&"roll": preload("res://entities/player/states/roll.gd"),
	&"dash": preload("res://entities/player/states/dash.gd"),
	&"hurt": preload("res://entities/player/states/hurt.gd"),
	&"death": preload("res://entities/player/states/death.gd"),
}

var player: Player
var current_state: PlayerState
var current_state_name: StringName = &""

var _states: Dictionary = {}


## Creates every state instance and enters the initial idle state.
func setup(p: Player) -> void:
	player = p
	_states.clear()
	for state_name: StringName in STATE_SCRIPTS.keys():
		var script: Script = STATE_SCRIPTS[state_name]
		var state: PlayerState = script.new() as PlayerState
		state.setup(player, self, state_name, int(PRIORITIES[state_name]))
		_states[state_name] = state
	force_state(&"idle")


func physics_update(delta: float) -> void:
	if current_state == null:
		return
	current_state.time_in_state += delta
	current_state.physics_update(delta)


func uses_gravity() -> bool:
	return current_state != null and current_state.uses_gravity()


func get_state(state_name: StringName) -> PlayerState:
	return _states.get(state_name, null)


## True when `state_name` exists and would be allowed to interrupt now.
func can_request(state_name: StringName) -> bool:
	if not _states.has(state_name):
		return false
	if current_state == null:
		return true
	if state_name == current_state_name:
		return false
	return int(PRIORITIES[state_name]) > current_state.priority


## Input-driven transition: only a strictly higher priority may interrupt.
func request_state(state_name: StringName) -> bool:
	if not can_request(state_name):
		return false
	return force_state(state_name)


## Lifecycle transition (same tier or completion); bypasses priority checks.
func force_state(state_name: StringName) -> bool:
	if not _states.has(state_name):
		return false
	var previous: StringName = current_state_name
	if current_state != null:
		current_state.exit(state_name)
	current_state = _states[state_name]
	current_state_name = state_name
	current_state.enter(previous)
	EventBus.player_state_changed.emit(state_name)
	return true
