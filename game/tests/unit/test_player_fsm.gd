extends GutTest
## T-04 — FSM transitions, interrupt priorities and roll i-frames/stamina
## (DESIGN §7, AC-01.4 groundwork, AC-03.3 groundwork).
##
## Real 60 Hz physics frames are used so state timers match the game.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
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
	assert_eq(player.get_state_name(), &"idle", "settled player is idle")


func _start_roll(player: Player) -> void:
	InputManager.press_buffered(&"roll")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"roll", "roll starts on the first frame")


func test_idle_run_idle_transitions() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	Input.action_press(&"move_right")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"run", "idle -> run")

	Input.action_release(&"move_right")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"idle", "run -> idle")


func test_attack_returns_to_locomotion_after_t_attack() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	InputManager.press_buffered(&"attack")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"attack", "idle -> attack")

	for _i: int in 30:
		await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"idle", "attack finishes after t_attack")


func test_block_held_then_released() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	Input.action_press(&"block")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"block", "idle -> block while held")

	Input.action_release(&"block")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"idle", "block -> idle when released")


func test_hurt_priority_blocks_locomotion_and_jump() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	player.apply_hurt()
	assert_eq(player.get_state_name(), &"hurt", "idle -> hurt")

	assert_false(
		player.state_machine.request_state(&"run"),
		"Hurt (90) must not be interrupted by Run (10)"
	)
	assert_false(
		player.state_machine.request_state(&"jump"),
		"Hurt (90) must not be interrupted by Jump (50)"
	)
	assert_eq(player.get_state_name(), &"hurt", "still hurt")

	for _i: int in 12:
		await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"idle", "hurt ends after t_hurt")


func test_death_interrupts_everything_and_is_terminal() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	await _start_roll(player)
	player.kill()
	assert_eq(player.get_state_name(), &"death", "Death (100) interrupts Roll (80)")
	assert_false(player.is_invulnerable(), "death is not invulnerable")

	assert_false(
		player.state_machine.request_state(&"hurt"),
		"Death cannot be interrupted by Hurt"
	)
	player.apply_hurt()
	assert_eq(player.get_state_name(), &"death", "death stays terminal")


func test_roll_cannot_be_interrupted_by_attack_or_block() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	await _start_roll(player)

	assert_false(
		player.state_machine.request_state(&"attack"),
		"Roll (80) must not be interrupted by Attack (60)"
	)
	assert_false(
		player.state_machine.request_state(&"block"),
		"Roll (80) must not be interrupted by Block (60)"
	)
	assert_eq(player.get_state_name(), &"roll", "still rolling")


func test_roll_spends_e_roll_once_and_has_iframes_on_frames_2_to_5() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	var stamina_before: float = GameState.stamina

	await _start_roll(player)
	assert_almost_eq(
		GameState.stamina,
		stamina_before - player.balance.e_roll,
		0.001,
		"roll spends E_roll stamina"
	)
	assert_false(player.is_invulnerable(), "frame 1 has no i-frames")

	for _i: int in 4:
		await get_tree().physics_frame
	assert_false(player.is_invulnerable(), "i-frames have not started before frame 2")

	await get_tree().physics_frame
	assert_true(player.is_invulnerable(), "i-frames start on frame 2")

	while player.state_machine.current_state.time_in_state < 0.30:
		await get_tree().physics_frame
	assert_true(player.is_invulnerable(), "i-frames last through frame 5")

	while (
		player.get_state_name() == &"roll"
		and player.state_machine.current_state.time_in_state < 0.41
	):
		await get_tree().physics_frame
	assert_false(player.is_invulnerable(), "frame 6 has no i-frames")

	for _i: int in 6:
		await get_tree().physics_frame
	assert_ne(player.get_state_name(), &"roll", "roll ends after t_roll")
	assert_almost_eq(
		GameState.stamina,
		stamina_before - player.balance.e_roll,
		0.001,
		"roll spends stamina exactly once"
	)


func test_roll_is_not_available_without_stamina() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	GameState.stamina = player.balance.e_roll - 1.0

	InputManager.press_buffered(&"roll")
	await get_tree().physics_frame

	assert_ne(player.get_state_name(), &"roll", "no stamina -> no roll")
	assert_almost_eq(
		GameState.stamina,
		player.balance.e_roll - 1.0,
		0.001,
		"failed roll does not spend stamina"
	)
