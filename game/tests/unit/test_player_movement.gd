extends GutTest
## T-04 — movement/jump physics from balancing.tres (AC-01.1, AC-01.2).
##
## Tests drive real 60 Hz physics frames (await physics_frame) so that
## move_and_slide() uses the same delta as the running game. Calling
## _physics_process() manually from a GUT test uses the idle-frame delta and
## makes jump height meaningless.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]


func before_each() -> void:
	GameState.reset_stamina()
	_reset_input()


func after_each() -> void:
	_reset_input()


func _reset_input() -> void:
	for action: StringName in ACTION_LIST:
		Input.action_release(action)
		InputManager.just_pressed(action)
		InputManager.consume_coyote_time(action)


func _spawn_player() -> Player:
	var floor_body := StaticBody2D.new()
	floor_body.name = "TestFloor"
	floor_body.position = Vector2(0.0, 8.0)
	var floor_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400.0, 16.0)
	floor_shape.shape = rect
	floor_body.add_child(floor_shape)
	add_child_autofree(floor_body)

	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.position = Vector2(0.0, -10.0)
	player.velocity = Vector2.ZERO
	return player


func _settle(player: Player) -> void:
	for _i: int in 15:
		await get_tree().physics_frame
	assert_true(player.is_on_floor(), "test player should settle on the floor")


func test_player_uses_balancing_resource_as_single_source() -> void:
	var player: Player = _spawn_player()
	var resource := load(BALANCE_PATH) as BalancingParams
	assert_not_null(resource, "balancing.tres must load")
	assert_eq(player.balance, resource, "Player must read values from balancing.tres")
	assert_almost_eq(player.balance.v_walk, 90.0, 0.001, "V_walk")
	assert_almost_eq(player.balance.h_jump, 32.0, 0.001, "H_jump")
	assert_almost_eq(player.balance.t_apex, 0.35, 0.001, "t_apex")
	assert_almost_eq(
		player.balance.get_jump_velocity(),
		2.0 * player.balance.h_jump / player.balance.t_apex,
		0.001,
		"vy0 = 2H/t_apex"
	)
	assert_almost_eq(
		player.balance.get_gravity(),
		player.balance.get_jump_velocity() / player.balance.t_apex,
		0.001,
		"g = vy0/t_apex"
	)
	assert_almost_eq(player.balance.get_jump_velocity(), 182.857, 0.01, "vy0 ≈ 183 px/s")
	assert_almost_eq(player.balance.get_gravity(), 522.449, 0.01, "g ≈ 523 px/s²")


func test_movement_starts_within_one_frame_and_uses_v_walk() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	assert_eq(player.get_state_name(), &"idle", "settled player is idle")

	var start_x: float = player.position.x
	Input.action_press(&"move_right")
	await get_tree().physics_frame

	assert_eq(player.get_state_name(), &"run", "run starts on the first frame (AC-01.1)")
	assert_almost_eq(player.velocity.x, player.balance.v_walk, 0.001, "speed is V_walk")
	assert_gt(player.position.x, start_x, "player moves on the first frame")

	Input.action_release(&"move_right")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"idle", "returns to idle when input stops")
	assert_almost_eq(player.velocity.x, 0.0, 0.001, "idle stops horizontal motion")


func test_jump_reaches_h_jump_within_one_pixel() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	assert_eq(player.get_state_name(), &"idle")

	var start_y: float = player.position.y
	var apex_y: float = start_y
	InputManager.press_buffered(&"jump")

	for i: int in 180:
		await get_tree().physics_frame
		apex_y = minf(apex_y, player.position.y)
		if i > 5 and player.is_on_floor():
			break

	var height: float = start_y - apex_y
	assert_almost_eq(
		height,
		player.balance.h_jump,
		1.0,
		"jump height must be H_jump ±1 px (AC-01.2)"
	)
	assert_true(player.is_on_floor(), "player lands back on the floor")


func test_jump_goes_through_jump_fall_land_states() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"jump", "jump state on the first frame")

	var saw_fall: bool = false
	var saw_land: bool = false
	for _i: int in 180:
		await get_tree().physics_frame
		var state_name: StringName = player.get_state_name()
		if state_name == &"fall":
			saw_fall = true
		if state_name == &"land":
			saw_land = true
			break

	assert_true(saw_fall, "Jump -> Fall when vy crosses the apex")
	assert_true(saw_land, "Fall -> Land on floor contact")

	for _i: int in 12:
		await get_tree().physics_frame
	assert_ne(player.get_state_name(), &"land", "Landing does not block input forever")
