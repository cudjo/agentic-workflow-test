extends GutTest

var _buffer: InputBuffer


func before_each() -> void:
	_buffer = InputBuffer.new(["jump", "attack"])


func test_after_press_just_pressed_returns_true() -> void:
	_buffer.press("jump")
	assert_true(_buffer.just_pressed("jump"), "jump should be just pressed")


func test_just_pressed_consumed_after_first_read() -> void:
	_buffer.press("jump")
	_buffer.just_pressed("jump")
	assert_false(_buffer.just_pressed("jump"), "second just_pressed should be false")


func test_buffer_expires_after_window() -> void:
	_buffer.press("jump")
	_buffer.update(0.2)
	assert_false(_buffer.just_pressed("jump"), "buffer should expire after 150 ms")


func test_buffer_valid_within_window() -> void:
	_buffer.press("attack")
	_buffer.update(0.1)
	assert_true(_buffer.just_pressed("attack"), "buffer should still be valid at 100 ms")


func test_is_pressed_not_consumed() -> void:
	_buffer.press("jump")
	_buffer.update(0.05)
	assert_true(_buffer.is_pressed("jump"))
	assert_true(_buffer.is_pressed("jump"), "is_pressed must not consume")


func test_unregistered_action_returns_false() -> void:
	assert_false(_buffer.just_pressed("unknown"))
	assert_false(_buffer.is_pressed("unknown"))
