extends GutTest
## T-06 — AbilitySystem и двойной прыжок (PLAN §3.3, SPEC US-02/AC-02.1).
##
## Проверяем контракт способностей (`AbilityBase`/`AbilityRegistry`/
## `GameState.abilities`), точку получения (`ability_pickup.tscn`) и поведение
## в FSM: второй прыжок ровно один раз до приземления, высота ≥ 0.8·H_jump,
## сброс счётчика при приземлении, без способности двойной прыжок невозможен.
##
## Как и T-04-тесты, гоняем реальные 60 Hz physics-кадры: тайминги прыжка
## должны совпадать с игрой (move_and_slide + ручная гравитация).

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const PICKUP_SCENE: PackedScene = preload("res://world/props/ability_pickup.tscn")
const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]


func before_each() -> void:
	GameState.reset_stamina()
	GameState.clear_abilities()
	_reset_input()


func after_each() -> void:
	GameState.clear_abilities()
	_reset_input()


func _reset_input() -> void:
	for action: StringName in ACTION_LIST:
		Input.action_release(action)
		InputManager.just_pressed(action)
		InputManager.consume_coyote_time(action)


func _spawn_player(with_floor: bool = true) -> Player:
	if with_floor:
		var floor_body := StaticBody2D.new()
		floor_body.name = "TestFloor"
		floor_body.position = Vector2(0.0, 8.0)
		var floor_shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(800.0, 16.0)
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
	assert_true(player.is_on_floor(), "test player settles on the floor")
	assert_eq(player.get_state_name(), &"idle", "settled player is idle")


func _ground_jump() -> void:
	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame


# ------------------------------------------------------------------------------
# Контракт способностей и GameState
# ------------------------------------------------------------------------------

func test_registry_exposes_double_jump_contract() -> void:
	var ability: AbilityBase = AbilityRegistry.get_ability(AbilityDoubleJump.ID)
	assert_not_null(ability, "double jump is registered in AbilityRegistry")
	assert_eq(ability.id, &"double_jump", "id matches GameState key")
	assert_eq(
		ability.display_name,
		AbilityDoubleJump.DISPLAY_NAME,
		"display name for gates/HUD (T-09/T-19)"
	)
	assert_true(AbilityRegistry.has_ability(&"double_jump"), "has_ability")
	assert_true(AbilityRegistry.all_ids().has(&"double_jump"), "all_ids contains double jump")
	assert_eq(AbilityDoubleJump.AIR_JUMPS, 1, "exactly one air jump (AC-02.1)")
	assert_almost_eq(
		AbilityDoubleJump.MIN_HEIGHT_FACTOR,
		0.8,
		0.0001,
		"AC-02.1: second jump is at least 0.8·H_jump"
	)


func test_game_state_keeps_abilities_typed_once_and_emits_signal() -> void:
	watch_signals(EventBus)
	assert_true(GameState.add_ability(&"double_jump"), "first acquisition succeeds")
	assert_false(GameState.add_ability(&"double_jump"), "duplicate acquisition is ignored")
	assert_true(GameState.has_ability(&"double_jump"), "ability is stored")
	assert_eq(GameState.get_abilities().size(), 1, "typed set has one entry")
	assert_signal_emit_count(EventBus, "ability_acquired", 1)

	var copy: Array[StringName] = GameState.get_abilities()
	copy.append(&"dash")
	assert_eq(
		GameState.get_abilities().size(),
		1,
		"get_abilities() returns a copy, not the live set"
	)

	GameState.clear_abilities()
	assert_false(GameState.has_ability(&"double_jump"), "clear_abilities resets the run")


func test_ability_activate_and_deactivate_toggle_player_flags() -> void:
	var player: Player = _spawn_player(false)
	var ability: AbilityBase = AbilityRegistry.get_ability(AbilityDoubleJump.ID)
	assert_not_null(ability, "double jump ability is registered")
	assert_eq(
		ability.player_flags(),
		{AbilityDoubleJump.ID: true},
		"ability declares its player flag"
	)

	assert_true(ability.activate(player), "activate succeeds on a real player")
	assert_true(player.has_ability_flag(&"double_jump"), "activate sets the runtime flag")
	ability.deactivate(player)
	assert_false(player.has_ability_flag(&"double_jump"), "deactivate clears the runtime flag")


# ------------------------------------------------------------------------------
# Точка получения способности
# ------------------------------------------------------------------------------

func test_pickup_by_contact_grants_ability_and_unlocks_double_jump() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	assert_false(
		player.has_ability_flag(&"double_jump"),
		"behaviour is locked before the pickup"
	)

	var pickup: AbilityPickup = PICKUP_SCENE.instantiate() as AbilityPickup
	add_child_autofree(pickup)
	pickup.global_position = player.global_position
	for _i: int in 3:
		await get_tree().physics_frame

	assert_true(pickup.is_collected(), "player contact collects the pickup")
	assert_true(GameState.has_ability(&"double_jump"), "pickup adds the ability to GameState")
	assert_true(
		player.has_ability_flag(&"double_jump"),
		"live player unlocks the behaviour via EventBus.ability_acquired"
	)

	# Поведение действительно разблокировано, а не только флаг.
	await _ground_jump()
	for _i: int in 4:
		await get_tree().physics_frame
	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_eq(
		player.get_state_name(),
		&"double_jump",
		"pickup unlocks the second air jump (AC-02.1)"
	)


func test_pickup_is_one_shot_and_does_not_grant_twice() -> void:
	var pickup: AbilityPickup = PICKUP_SCENE.instantiate() as AbilityPickup
	add_child_autofree(pickup)
	watch_signals(EventBus)

	assert_true(pickup.collect(), "first collect grants the ability")
	assert_false(pickup.collect(), "second collect is ignored")
	assert_signal_emit_count(EventBus, "ability_acquired", 1)
	assert_eq(GameState.get_abilities().size(), 1, "ability is stored once")


# ------------------------------------------------------------------------------
# Поведение в FSM (AC-02.1)
# ------------------------------------------------------------------------------

func test_player_without_ability_cannot_double_jump() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	await _ground_jump()
	assert_eq(player.get_state_name(), &"jump", "ground jump started")

	for _i: int in 4:
		await get_tree().physics_frame
	assert_false(player.can_double_jump(), "ability is locked")
	assert_false(player.has_ability_flag(&"double_jump"), "no ability flag")

	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_ne(
		player.get_state_name(),
		&"double_jump",
		"without the ability the second jump is refused"
	)
	assert_eq(player.double_jumps_used, 0, "counter is untouched without the ability")


func test_double_jump_once_height_and_reset_on_landing() -> void:
	GameState.add_ability(AbilityDoubleJump.ID)
	var player: Player = _spawn_player()
	await _settle(player)
	assert_true(
		player.has_ability_flag(&"double_jump"),
		"player binds GameState abilities on spawn"
	)

	await _ground_jump()
	for _i: int in 4:
		await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"jump", "still ascending after the ground jump")

	var takeoff_y: float = player.position.y
	var apex_y: float = takeoff_y
	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"double_jump", "second air jump (AC-02.1)")
	assert_eq(player.double_jumps_used, 1, "one air jump spent")

	for _i: int in 120:
		await get_tree().physics_frame
		apex_y = minf(apex_y, player.position.y)
		if player.velocity.y >= 0.0:
			break

	var height: float = takeoff_y - apex_y
	var required: float = player.balance.h_jump * player.balance.h_double_factor
	assert_gte(height, required - 0.5, "second jump height is ≥ 0.8·H_jump (AC-02.1)")
	assert_almost_eq(
		height,
		required,
		4.0,
		"height comes from get_double_jump_velocity() in balancing.tres"
	)

	# Повтор в воздухе невозможен — ровно один прыжок до приземления.
	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_ne(player.get_state_name(), &"double_jump", "exactly one air jump before landing")
	assert_eq(player.double_jumps_used, 1, "counter does not grow in the air")

	for _i: int in 240:
		await get_tree().physics_frame
		if player.is_on_floor():
			break
	# is_on_floor() взводится в move_and_slide; Fall -> Land случается на
	# следующем тике — даём FSM обработать приземление.
	await get_tree().physics_frame
	assert_true(player.is_on_floor(), "player lands")
	assert_eq(player.get_state_name(), &"land", "Fall -> Land on floor contact")
	assert_eq(player.double_jumps_used, 0, "landing resets the air-jump counter (AC-02.1)")

	# После приземления второй прыжок снова доступен.
	await _ground_jump()
	for _i: int in 4:
		await get_tree().physics_frame
	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_eq(
		player.get_state_name(),
		&"double_jump",
		"after landing the double jump is available again"
	)


func test_double_jump_is_also_available_while_falling() -> void:
	GameState.add_ability(AbilityDoubleJump.ID)
	var player: Player = _spawn_player()
	await _settle(player)

	await _ground_jump()
	for _i: int in 120:
		await get_tree().physics_frame
		if player.get_state_name() == &"fall":
			break
	assert_eq(player.get_state_name(), &"fall", "descending before the second jump")

	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_eq(
		player.get_state_name(),
		&"double_jump",
		"second jump works from Fall as well (AC-02.1)"
	)
