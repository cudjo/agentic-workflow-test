extends Node
## InputManager — unified input API, buffering, remapping, device detection.
##
## Replaces the T-01 stub. Reads actions from InputMap, never hard-codes keys.
## Features:
##   - is_pressed / just_pressed that also honor the input buffer
##   - 150 ms input buffer (game/core/input/input_buffer.gd)
##   - coyote-time helpers (0.1 s window after leaving an edge)
##   - save/load remaps to user://settings.cfg with reset to defaults
##   - active-device detection (keyboard / xbox / playstation / generic gamepad)
##     and device_changed signal.

const CONFIG_PATH: String = "user://settings.cfg"
const COYOTE_TIME_WINDOW: float = 0.1
const BUFFER_WINDOW: float = 0.15

const DEVICE_KEYBOARD: String = "keyboard"
const DEVICE_XBOX: String = "xbox"
const DEVICE_PLAYSTATION: String = "playstation"
const DEVICE_GENERIC: String = "gamepad"

signal device_changed(device: String, device_id: int)

var active_device: String = DEVICE_KEYBOARD
var last_active_device_id: int = -1

var _input_buffer: InputBuffer
var _coyote_timers: Dictionary = {}
var _default_events: Dictionary = {}


func _ready() -> void:
	_store_default_events()
	_input_buffer = InputBuffer.new(InputMap.get_actions())
	_load_remaps()


func _process(delta: float) -> void:
	_input_buffer.update(delta)
	_update_coyote_timers(delta)


func _input(event: InputEvent) -> void:
	_track_active_device(event)


# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

## Returns true if the action is currently held or buffered.
func is_pressed(action: StringName) -> bool:
	return Input.is_action_pressed(action) or _input_buffer.is_pressed(action)


## Returns true on the first frame the action is triggered (engine or buffer).
func just_pressed(action: StringName) -> bool:
	return Input.is_action_just_pressed(action) or _input_buffer.just_pressed(action)


## Returns true on the first frame the action is released.
func just_released(action: StringName) -> bool:
	return Input.is_action_just_released(action)


## Raw InputMap strength, useful for analog movement.
func get_action_strength(action: StringName) -> float:
	return Input.get_action_strength(action)


## Registers a press in the input buffer. Used by gameplay code that wants to
## make a digital action forgivable (e.g. jump just before landing).
func press_buffered(action: StringName) -> void:
	_input_buffer.press(action)


## Starts the coyote-time window for an action. Call when the entity leaves an
## edge where the action would have been valid (e.g. ground for a jump).
func start_coyote_time(action: StringName) -> void:
	_coyote_timers[action] = COYOTE_TIME_WINDOW


## True if coyote time is currently active for the action.
func is_coyote_time_available(action: StringName) -> bool:
	return _coyote_timers.get(action, 0.0) > 0.0


## Consumes coyote time and returns whether it was available.
func consume_coyote_time(action: StringName) -> bool:
	var available: bool = is_coyote_time_available(action)
	_coyote_timers[action] = 0.0
	return available


## Returns true if the action was just pressed or if coyote time is still active.
func just_pressed_or_coyote(action: StringName) -> bool:
	if just_pressed(action):
		return true
	if is_coyote_time_available(action):
		_coyote_timers[action] = 0.0
		return true
	return false


## Replaces all events for an action and persists the new mapping.
func remap_action(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for ev in events:
		InputMap.action_add_event(action, ev)
	_save_remaps()


## Restores every action to its default project.godot mapping.
func reset_to_defaults() -> void:
	for action in _default_events.keys():
		InputMap.action_erase_events(action)
		for ev in _default_events[action]:
			InputMap.action_add_event(action, ev.duplicate())
	_save_remaps()


## Returns the default events captured at startup.
func get_default_events(action: StringName) -> Array[InputEvent]:
	return _default_events.get(action, [] as Array[InputEvent])


# ------------------------------------------------------------------------------
# Device detection
# ------------------------------------------------------------------------------

func _track_active_device(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_set_active_device(DEVICE_KEYBOARD, -1)
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var device_id: int = event.device
		var device_name: String = ""
		if device_id >= 0:
			device_name = Input.get_joy_name(device_id)
		else:
			var pads: PackedInt32Array = Input.get_connected_joypads()
			if pads.size() > 0:
				device_id = pads[0]
				device_name = Input.get_joy_name(device_id)
		_set_active_device(_detect_gamepad_type(device_name), device_id)


func _set_active_device(device: String, device_id: int) -> void:
	if active_device != device or last_active_device_id != device_id:
		active_device = device
		last_active_device_id = device_id
		device_changed.emit(device, device_id)


func _detect_gamepad_type(device_name: String) -> String:
	var lower: String = device_name.to_lower()
	if "xbox" in lower:
		return DEVICE_XBOX
	if "playstation" in lower or "dualshock" in lower or "dualsense" in lower:
		return DEVICE_PLAYSTATION
	return DEVICE_GENERIC


# ------------------------------------------------------------------------------
# Coyote time
# ------------------------------------------------------------------------------

func _update_coyote_timers(delta: float) -> void:
	for action in _coyote_timers.keys():
		var time_left: float = _coyote_timers[action]
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
		_coyote_timers[action] = time_left


# ------------------------------------------------------------------------------
# Remap persistence
# ------------------------------------------------------------------------------

func _store_default_events() -> void:
	for action in InputMap.get_actions():
		_default_events[action] = InputMap.action_get_events(action).duplicate()


func _save_remaps() -> void:
	var config := ConfigFile.new()
	if FileAccess.file_exists(CONFIG_PATH):
		config.load(CONFIG_PATH)

	for action in InputMap.get_actions():
		var event_dicts: Array = []
		for ev in InputMap.action_get_events(action):
			event_dicts.append(_serialize_event(ev))
		config.set_value("input", action, JSON.stringify(event_dicts))

	var temp_path: String = CONFIG_PATH + ".tmp"
	var err: Error = config.save(temp_path)
	if err != OK:
		push_error("InputManager: failed to save remaps to temp file %s (error %d)" % [temp_path, err])
		return

	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("InputManager: failed to open user:// for remap save")
		return
	err = dir.rename(temp_path.get_file(), CONFIG_PATH.get_file())
	if err != OK:
		push_error("InputManager: failed to rename remaps file (error %d)" % err)


func _load_remaps() -> void:
	var config := ConfigFile.new()
	var err: Error = config.load(CONFIG_PATH)
	if err != OK:
		return

	for action in InputMap.get_actions():
		var raw: Variant = config.get_value("input", action, "")
		if raw == "":
			continue
		var parsed: Variant = JSON.parse_string(raw)
		if parsed == null or not parsed is Array:
			continue
		var events: Array[InputEvent] = []
		for data in parsed:
			if data is Dictionary:
				var ev: InputEvent = _deserialize_event(data)
				if ev != null:
					events.append(ev)
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for ev in events:
			InputMap.action_add_event(action, ev)


func _serialize_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var keycode: int = event.keycode
		var physical: bool = false
		if event.physical_keycode != 0:
			physical = true
			keycode = event.physical_keycode
		return {
			"type": "Key",
			"physical": physical,
			"keycode": keycode,
			"shift_pressed": event.shift_pressed,
			"ctrl_pressed": event.ctrl_pressed,
			"alt_pressed": event.alt_pressed,
			"meta_pressed": event.meta_pressed,
		}
	if event is InputEventMouseButton:
		return {"type": "MouseButton", "button_index": event.button_index}
	if event is InputEventJoypadButton:
		return {"type": "JoypadButton", "button_index": event.button_index}
	if event is InputEventJoypadMotion:
		return {"type": "JoypadMotion", "axis": event.axis, "axis_value": event.axis_value}
	return {}


func _deserialize_event(data: Dictionary) -> InputEvent:
	var type: String = data.get("type", "")
	match type:
		"Key":
			var ev := InputEventKey.new()
			if data.get("physical", false):
				ev.physical_keycode = data.get("keycode", 0) as int
			else:
				ev.keycode = data.get("keycode", 0) as int
			ev.shift_pressed = data.get("shift_pressed", false)
			ev.ctrl_pressed = data.get("ctrl_pressed", false)
			ev.alt_pressed = data.get("alt_pressed", false)
			ev.meta_pressed = data.get("meta_pressed", false)
			return ev
		"MouseButton":
			var ev := InputEventMouseButton.new()
			ev.button_index = data.get("button_index", MOUSE_BUTTON_LEFT) as int
			return ev
		"JoypadButton":
			var ev := InputEventJoypadButton.new()
			ev.button_index = data.get("button_index", 0) as int
			return ev
		"JoypadMotion":
			var ev := InputEventJoypadMotion.new()
			ev.axis = data.get("axis", 0) as int
			ev.axis_value = data.get("axis_value", 0.0)
			return ev
	return null
