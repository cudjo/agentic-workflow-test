extends GutTest

const CONFIG_PATH: String = "user://settings.cfg"
# Автозагружаемый InputManager не объявляет class_name (конфликт "hides an autoload
# singleton"), поэтому ссылка на скрипт — через preload.
const InputManagerScript := preload("res://autoload/InputManager.gd")

var _manager: InputManagerScript
var _original_events: Dictionary = {}


func before_all() -> void:
	_original_events.clear()
	for action in InputMap.get_actions():
		_original_events[action] = InputMap.action_get_events(action).duplicate()


func before_each() -> void:
	_restore_input_map()
	_cleanup_config()
	_manager = InputManagerScript.new()
	get_tree().root.add_child(_manager)
	_manager._ready()


func after_each() -> void:
	_manager.queue_free()
	_restore_input_map()
	_cleanup_config()


func _restore_input_map() -> void:
	for action in _original_events.keys():
		InputMap.action_erase_events(action)
		for ev in _original_events[action]:
			InputMap.action_add_event(action, ev.duplicate())


func _cleanup_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		DirAccess.remove_absolute(CONFIG_PATH)


func test_remap_persists_after_reload() -> void:
	var new_jump := InputEventKey.new()
	new_jump.keycode = KEY_F
	_manager.remap_action("jump", [new_jump])

	assert_eq(InputMap.action_get_events("jump").size(), 1, "remap should replace jump events")

	_manager.queue_free()
	_manager = InputManagerScript.new()
	get_tree().root.add_child(_manager)
	_manager._ready()

	var loaded_events := InputMap.action_get_events("jump")
	assert_eq(loaded_events.size(), 1, "saved remap should load one event")
	var loaded_key: InputEventKey = loaded_events[0]
	assert_eq(loaded_key.keycode, KEY_F, "loaded remap should use F key")


func test_reset_restores_defaults() -> void:
	var new_jump := InputEventKey.new()
	new_jump.keycode = KEY_F
	_manager.remap_action("jump", [new_jump])
	assert_eq(InputMap.action_get_events("jump").size(), 1)

	_manager.reset_to_defaults()
	var default_count: int = _original_events["jump"].size()
	assert_eq(InputMap.action_get_events("jump").size(), default_count, "reset should restore defaults")


func test_coyote_time_window() -> void:
	assert_false(_manager.is_coyote_time_available("jump"))
	_manager.start_coyote_time("jump")
	assert_true(_manager.is_coyote_time_available("jump"))
	_manager._process(0.05)
	assert_true(_manager.is_coyote_time_available("jump"))
	_manager._process(0.06)
	assert_false(_manager.is_coyote_time_available("jump"))


func test_just_pressed_or_coyote_consumes_window() -> void:
	_manager.start_coyote_time("jump")
	assert_true(_manager.just_pressed_or_coyote("jump"))
	assert_false(_manager.is_coyote_time_available("jump"))
	assert_false(_manager.just_pressed_or_coyote("jump"))


func test_device_changed_keyboard_event() -> void:
	watch_signals(_manager)
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_A
	_manager._input(key_event)
	assert_signal_emitted_with_parameters(_manager, "device_changed", [InputManager.DEVICE_KEYBOARD, -1])


func test_device_changed_gamepad_event() -> void:
	watch_signals(_manager)
	var pad_event := InputEventJoypadButton.new()
	pad_event.button_index = JOY_BUTTON_A
	_manager._input(pad_event)
	assert_signal_emitted(_manager, "device_changed")
	assert_eq(_manager.active_device, InputManager.DEVICE_GENERIC)
