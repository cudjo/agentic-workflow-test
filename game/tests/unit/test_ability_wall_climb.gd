extends GutTest
## T-08 — способность «Карабканье по стенам» (PLAN §3.1/§3.3, SPEC US-02, AC-02.3).
##
## Проверяем контракт (`AbilityBase`/`AbilityRegistry`/`GameState`), данные
## `balancing.tres` (`V_wall_slide`, `V_wall_kick`) и поведение в FSM на
## реальных 60 Hz physics-кадрах: удержание на стене со скоростью не выше
## `V_wall_slide`, недоступность удержания без способности и wall kick с
## горизонтальным импульсом в сторону, противоположную стене.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]


func before_each() -> void:
	GameState.reset_stamina()
	GameState.reset_hp()
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


## Мир для теста: пол и вертикальная стена с указанной стороны.
## `side = 1` — стена справа (держим move_right), `side = -1` — слева.
func _spawn_world(side: int = 1) -> Player:
	var floor_body := StaticBody2D.new()
	floor_body.name = "TestFloor"
	floor_body.position = Vector2(0.0, 8.0)
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(800.0, 16.0)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	add_child_autofree(floor_body)

	var wall := StaticBody2D.new()
	wall.name = "TestWall"
	wall.position = Vector2(float(side) * 10.0, -100.0)
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(8.0, 240.0)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	add_child_autofree(wall)

	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.position = Vector2(0.0, -100.0)
	player.velocity = Vector2.ZERO
	return player


func _hold_into_wall(side: int) -> void:
	Input.action_press(&"move_right" if side > 0 else &"move_left")


## Держит направление в стену до входа в wall_slide (или до guard-лимита).
func _cling_to_wall(player: Player, side: int = 1) -> void:
	_hold_into_wall(side)
	var guard: int = 0
	while player.get_state_name() != &"wall_slide" and guard < 30:
		await get_tree().physics_frame
		guard += 1
	assert_eq(player.get_state_name(), &"wall_slide", "player clings to the wall")


# ------------------------------------------------------------------------------
# Контракт способности и данные
# ------------------------------------------------------------------------------

func test_registry_exposes_wall_climb_contract() -> void:
	var ability: AbilityBase = AbilityRegistry.get_ability(AbilityWallClimb.ID)
	assert_not_null(ability, "wall climb is registered in AbilityRegistry")
	assert_eq(ability.id, &"wall_climb", "id matches GameState key")
	assert_eq(
		ability.display_name,
		"Карабканье по стенам",
		"RU name for gates (T-09) and HUD (T-19)"
	)
	assert_true(AbilityRegistry.has_ability(&"wall_climb"), "has_ability")
	assert_true(AbilityRegistry.all_ids().has(&"wall_climb"), "all_ids contains wall_climb")

	var player: Player = _spawn_world()
	assert_true(ability.activate(player), "activate succeeds on a real player")
	assert_true(player.has_ability_flag(&"wall_climb"), "activate sets the runtime flag")
	ability.deactivate(player)
	assert_false(
		player.has_ability_flag(&"wall_climb"),
		"deactivate clears the runtime flag"
	)


func test_wall_climb_values_come_from_balancing() -> void:
	var balance: BalancingParams = load(BALANCE_PATH) as BalancingParams
	assert_not_null(balance, "balancing.tres is loadable")
	assert_gt(balance.v_wall_slide, 0.0, "V_wall_slide is defined")
	assert_true(
		balance.v_wall_slide < balance.v_walk,
		"wall slide is slower than walking"
	)
	assert_gt(
		balance.v_wall_kick,
		balance.v_walk,
		"wall kick impulse is strong enough to leave the wall (AC-02.3)"
	)
	assert_gt(balance.t_wall_kick_lock, 0.0, "wall kick impulse has a lock time")


func test_wall_dir_helpers_follow_collision_normal() -> void:
	assert_eq(
		AbilityWallClimb.wall_dir_from_normal(Vector2(-1.0, 0.0)),
		1,
		"normal pointing left means the wall is on the right"
	)
	assert_eq(
		AbilityWallClimb.wall_dir_from_normal(Vector2(1.0, 0.0)),
		-1,
		"normal pointing right means the wall is on the left"
	)
	assert_eq(
		AbilityWallClimb.wall_dir_from_normal(Vector2(0.0, -1.0)),
		0,
		"floor/ceiling is not a wall"
	)
	assert_true(
		AbilityWallClimb.is_holding_into_wall(1.0, 1),
		"holding right against a right wall counts"
	)
	assert_false(
		AbilityWallClimb.is_holding_into_wall(-1.0, 1),
		"holding away from the wall does not count"
	)
	assert_false(
		AbilityWallClimb.is_holding_into_wall(0.0, 1),
		"no direction input does not count"
	)


# ------------------------------------------------------------------------------
# Гейт способности (AC-02.3)
# ------------------------------------------------------------------------------

func test_wall_slide_is_unavailable_without_ability() -> void:
	var player: Player = _spawn_world()
	_hold_into_wall(1)

	for _i: int in 20:
		await get_tree().physics_frame

	assert_ne(player.get_state_name(), &"wall_slide", "without the ability no wall hold")
	assert_gt(
		player.velocity.y,
		player.balance.v_wall_slide,
		"without the ability the player keeps falling at full gravity"
	)


func test_forced_wall_slide_without_ability_exits_immediately() -> void:
	var player: Player = _spawn_world()
	player.state_machine.force_state(&"wall_slide")
	# Гейт в enter()/physics_update() срабатывает на первом physics-тике;
	# ждём его завершения (сигнал physics_frame приходит до _physics_process).
	var guard: int = 0
	while player.get_state_name() == &"wall_slide" and guard < 5:
		await get_tree().physics_frame
		guard += 1
	assert_ne(
		player.get_state_name(),
		&"wall_slide",
		"wall_slide exits when the ability is missing (defence-in-depth)"
	)
	assert_lte(guard, 2, "exit happens on the first physics tick")


# ------------------------------------------------------------------------------
# Скольжение по стене (AC-02.3)
# ------------------------------------------------------------------------------

func test_wall_slide_caps_fall_speed_at_v_wall_slide() -> void:
	GameState.add_ability(AbilityWallClimb.ID)
	var player: Player = _spawn_world()
	await _cling_to_wall(player)

	for _i: int in 10:
		await get_tree().physics_frame

	assert_eq(player.get_state_name(), &"wall_slide", "player is still on the wall")
	assert_true(player.velocity.y > 0.0, "player slides down")
	assert_lte(
		player.velocity.y,
		player.balance.v_wall_slide + 0.001,
		"AC-02.3: slide speed is limited by V_wall_slide"
	)
	assert_almost_eq(
		player.velocity.y,
		player.balance.v_wall_slide,
		0.5,
		"slide reaches V_wall_slide instead of free fall"
	)


func test_wall_slide_frame_displacement_does_not_exceed_v_wall_slide() -> void:
	GameState.add_ability(AbilityWallClimb.ID)
	var player: Player = _spawn_world()
	await _cling_to_wall(player)

	for _i: int in 5:
		await get_tree().physics_frame

	var max_step: float = player.balance.v_wall_slide / 60.0
	for _i: int in 10:
		var before_y: float = player.position.y
		await get_tree().physics_frame
		assert_lte(
			player.position.y - before_y,
			max_step + 0.05,
			"per-frame fall is limited by V_wall_slide"
		)
	assert_eq(player.get_state_name(), &"wall_slide", "still sliding at the end")


func test_wall_slide_stops_when_direction_is_released() -> void:
	GameState.add_ability(AbilityWallClimb.ID)
	var player: Player = _spawn_world()
	await _cling_to_wall(player)

	Input.action_release(&"move_right")
	await get_tree().physics_frame
	assert_ne(
		player.get_state_name(),
		&"wall_slide",
		"releasing the direction drops off the wall"
	)


# ------------------------------------------------------------------------------
# Wall kick (AC-02.3)
# ------------------------------------------------------------------------------

func test_wall_kick_pushes_away_from_the_right_wall() -> void:
	GameState.add_ability(AbilityWallClimb.ID)
	var player: Player = _spawn_world(1)
	await _cling_to_wall(player, 1)

	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame

	assert_eq(player.get_state_name(), &"wall_kick", "jump at the wall starts a wall kick")
	assert_almost_eq(
		player.velocity.x,
		-player.balance.v_wall_kick,
		0.001,
		"right wall: horizontal impulse points left"
	)
	assert_lt(player.velocity.y, 0.0, "wall kick also lifts the player")

	var x_before: float = player.position.x
	for _i: int in 4:
		await get_tree().physics_frame
	assert_lt(player.position.x, x_before - 1.0, "player actually moves away from the wall")


func test_wall_kick_pushes_away_from_the_left_wall() -> void:
	GameState.add_ability(AbilityWallClimb.ID)
	var player: Player = _spawn_world(-1)
	await _cling_to_wall(player, -1)

	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame

	assert_eq(player.get_state_name(), &"wall_kick", "wall kick works on the left wall too")
	assert_almost_eq(
		player.velocity.x,
		player.balance.v_wall_kick,
		0.001,
		"left wall: horizontal impulse points right"
	)
	assert_lt(player.velocity.y, 0.0, "wall kick lifts the player")

	var x_before: float = player.position.x
	for _i: int in 4:
		await get_tree().physics_frame
	assert_gt(player.position.x, x_before + 1.0, "player actually moves away from the wall")


func test_wall_kick_keeps_impulse_for_the_lock_time() -> void:
	GameState.add_ability(AbilityWallClimb.ID)
	var player: Player = _spawn_world(1)
	await _cling_to_wall(player, 1)

	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"wall_kick")

	# Игрок продолжает держать направление в стену, но лок не даёт импульсу
	# погаснуть раньше t_wall_kick_lock (проверяем первую половину окна).
	var lock_frames: int = maxi(int(floor(player.balance.t_wall_kick_lock * 60.0)) - 1, 1)
	for _i: int in lock_frames:
		assert_lte(player.velocity.x, 0.0, "away impulse is kept while locked")
		await get_tree().physics_frame
	assert_lte(player.velocity.x, 0.0, "impulse still points away just before the lock ends")

	# После локка обычное управление возвращается: удержание в стену снова
	# задаёт горизонтальную скорость в сторону стены.
	for _i: int in 30:
		await get_tree().physics_frame
		if player.velocity.x > 0.0:
			break
	assert_gt(player.velocity.x, 0.0, "normal movement control returns after the lock")


func test_wall_kick_returns_to_fall_after_apex() -> void:
	GameState.add_ability(AbilityWallClimb.ID)
	var player: Player = _spawn_world(1)
	await _cling_to_wall(player, 1)

	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"wall_kick")

	for _i: int in 180:
		if player.get_state_name() != &"wall_kick":
			break
		await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"fall", "wall kick ends at the apex")
