class_name InputBuffer
extends RefCounted
## InputBuffer — time-based input buffering for digital actions.
##
## Tracks a short window (150 ms) after a virtual press so that callers can
## ask "was this pressed recently?" independently of the engine frame rate.

const BUFFER_WINDOW: float = 0.15

var _buffers: Dictionary = {}
var _pressed_flags: Dictionary = {}


func _init(actions: PackedStringArray = []) -> void:
	for action in actions:
		_register(action)


func register_action(action: StringName) -> void:
	_register(action)


func _register(action: StringName) -> void:
	if not _buffers.has(action):
		_buffers[action] = 0.0
		_pressed_flags[action] = false


## Advances all active buffers by `delta` seconds.
func update(delta: float) -> void:
	for action in _buffers.keys():
		var time_left: float = _buffers[action]
		if time_left > 0.0:
			time_left -= delta
			if time_left <= 0.0:
				time_left = 0.0
				_pressed_flags[action] = false
			_buffers[action] = time_left


## Record a virtual press for the action, restarting the buffer window.
func press(action: StringName) -> void:
	_register(action)
	_buffers[action] = BUFFER_WINDOW
	_pressed_flags[action] = true


## Returns true while the buffered press is still active (not consumed).
func is_pressed(action: StringName) -> bool:
	return _pressed_flags.get(action, false)


## Returns true once per buffered press and consumes it.
func just_pressed(action: StringName) -> bool:
	var was_pressed: bool = is_pressed(action)
	_pressed_flags[action] = false
	return was_pressed


## Remaining buffered time for the action, in seconds.
func get_buffer_time(action: StringName) -> float:
	return _buffers.get(action, 0.0)


## Clears every buffered press. T-17 uses it so an attack pressed just before
## a zone transition cannot fire after loading (EC-12).
func clear() -> void:
	for action in _buffers.keys():
		_buffers[action] = 0.0
		_pressed_flags[action] = false
