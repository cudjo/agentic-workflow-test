extends GutTest
## T-07 — способность «Рывок» (PLAN §3.1/§3.3, SPEC US-02, AC-02.2).
##
## Проверяем контракт (`AbilityBase`/`AbilityRegistry`/`GameState`), рывок в
## FSM на реальных 60 Hz physics-кадрах: D_dash за T_dash, i-frames на всё
## время, кулдаун C_dash ≤ 1 с и сигнал `EventBus.ability_cooldown_changed`
## для HUD (T-19). Отдельно — движение сквозь ловушку без урона в i-frames и
## недоступность рывка без способности.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const TRAP_DAMAGE: float = 10.0
const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]

## Перехват сигнала кулдауна: [ability_id, remaining, duration].
var _cooldown_events: Array = []


func before_each() -> void:
	GameState.reset_stamina()
	GameState.reset_hp()
	GameState.clear_abilities()
	_reset_input()
	_cooldown_events.clear()
	if not EventBus.ability_cooldown_changed.is_connected(_on_ability_cooldown_changed):
		EventBus.ability_cooldown_changed.connect(_on_ability_cooldown_changed)


func after_each() -> void:
	if EventBus.ability_cooldown_changed.is_connected(_on_ability_cooldown_changed):
		EventBus.ability_cooldown_changed.disconnect(_on_ability_cooldown_changed)
	GameState.clear_abilities()
	_cooldown_events.clear()
	_reset_input()


func _on_ability_cooldown_changed(
	ability_id: StringName,
	remaining: float,
	duration: float
) -> void:
	_cooldown_events.append([ability_id, remaining, duration])


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


## Ловушка-ловушка: Area2D на слое enemy_hitbox, маскирует player_hurtbox.
func _spawn_trap(at: Vector2) -> Hitbox:
	var trap := Hitbox.new()
	trap.name = "TestTrap"
	trap.hit_layer = CombatLayers.ENEMY_HITBOX
	trap.target_mask = CombatLayers.PLAYER_HURTBOX
	trap.position = at
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8.0, 40.0)
	shape.shape = rect
	trap.add_child(shape)
	add_child_autofree(trap)
	trap.activate(Damage.create(TRAP_DAMAGE), 0.0, Vector2.LEFT)
	return trap


func _start_dash() -> void:
	InputManager.press_buffered(&"dash")
	await get_tree().physics_frame


# ------------------------------------------------------------------------------
# Контракт способности и данные
# ------------------------------------------------------------------------------

func test_registry_exposes_dash_contract() -> void:
	var ability: AbilityBase = AbilityRegistry.get_ability(AbilityDash.ID)
	assert_not_null(ability, "dash is registered in AbilityRegistry")
	assert_eq(ability.id, &"dash", "id matches GameState key")
	assert_eq(ability.display_name, "Рывок", "RU name for gates (T-09) and HUD (T-19)")
	assert_true(AbilityRegistry.has_ability(&"dash"), "has_ability")
	assert_true(AbilityRegistry.all_ids().has(&"dash"), "all_ids contains dash")

	var player: Player = _spawn_player(false)
	assert_true(ability.activate(player), "activate succeeds on a real player")
	assert_true(player.has_ability_flag(&"dash"), "activate sets the runtime flag")
	ability.deactivate(player)
	assert_false(player.has_ability_flag(&"dash"), "deactivate clears the runtime flag")


func test_dash_values_come_from_balancing_and_fit_ac_02_2() -> void:
	var balance: BalancingParams = load(BALANCE_PATH) as BalancingParams
	assert_not_null(balance, "balancing.tres is loadable")
	assert_gt(balance.d_dash, 0.0, "D_dash is defined")
	assert_gt(balance.t_dash, 0.0, "T_dash is defined")
	assert_true(
		balance.c_dash <= AbilityDash.MAX_COOLDOWN_SEC,
		"AC-02.2: C_dash does not exceed 1 s"
	)


# ------------------------------------------------------------------------------
# Гейт способности
# ------------------------------------------------------------------------------

func test_dash_is_unavailable_without_ability() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	var stamina_before: float = GameState.stamina

	await _start_dash()

	assert_ne(player.get_state_name(), &"dash", "without the ability dash is refused")
	assert_almost_eq(GameState.stamina, stamina_before, 0.001, "refused dash spends no stamina")
	assert_almost_eq(player.get_dash_cooldown_left(), 0.0, 0.001, "no cooldown is started")
	assert_eq(_cooldown_events.size(), 0, "no HUD cooldown signal without the ability")


func test_forced_dash_without_ability_does_not_grant_iframes() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	player.state_machine.force_state(&"dash")
	assert_false(player.is_invulnerable(), "no i-frames without the ability")
	await get_tree().physics_frame
	assert_ne(player.get_state_name(), &"dash", "dash state exits when the ability is missing")


# ------------------------------------------------------------------------------
# Дистанция / тайминг / i-frames (AC-02.2)
# ------------------------------------------------------------------------------

func test_dash_covers_d_dash_in_t_dash() -> void:
	GameState.add_ability(AbilityDash.ID)
	var player: Player = _spawn_player()
	await _settle(player)
	var start_x: float = player.position.x

	await _start_dash()
	assert_eq(player.get_state_name(), &"dash", "dash starts on the first frame")
	assert_true(player.is_invulnerable(), "i-frames are active from the first dash frame")

	var frames: int = 0
	while player.get_state_name() == &"dash" and frames < 30:
		await get_tree().physics_frame
		frames += 1

	assert_almost_eq(
		absf(player.position.x - start_x),
		player.balance.d_dash,
		1.0,
		"dash travels D_dash"
	)
	assert_eq(
		frames,
		int(round(player.balance.t_dash * 60.0)),
		"dash lasts T_dash (physics ticks at 60 Hz)"
	)
	assert_false(player.is_invulnerable(), "i-frames end with the dash")


func test_dash_iframes_cover_the_whole_dash() -> void:
	GameState.add_ability(AbilityDash.ID)
	var player: Player = _spawn_player()
	await _settle(player)

	await _start_dash()
	assert_true(player.is_invulnerable(), "start of the dash")

	for _i: int in 4:
		await get_tree().physics_frame
	assert_true(player.is_invulnerable(), "middle of the dash")

	while player.get_state_name() == &"dash":
		assert_true(player.is_invulnerable(), "every dash frame has i-frames")
		await get_tree().physics_frame
	assert_false(player.is_invulnerable(), "after the dash i-frames are gone")


func test_dash_through_trap_takes_no_damage() -> void:
	GameState.add_ability(AbilityDash.ID)
	var player: Player = _spawn_player()
	await _settle(player)
	var hp_before: float = GameState.hp

	_spawn_trap(player.global_position + Vector2(24.0, 0.0))
	await get_tree().physics_frame
	assert_almost_eq(GameState.hp, hp_before, 0.001, "trap is not touched before the dash")

	await _start_dash()
	assert_eq(player.get_state_name(), &"dash", "dash crosses the trap")
	while player.get_state_name() == &"dash":
		await get_tree().physics_frame

	assert_almost_eq(GameState.hp, hp_before, 0.001, "i-frames: no damage crossing the trap")
	assert_ne(player.get_state_name(), &"hurt", "trap damage did not interrupt the dash")


func test_trap_damages_player_outside_iframes() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	var hp_before: float = GameState.hp

	_spawn_trap(player.global_position)
	await wait_physics_frames(3)

	assert_lt(GameState.hp, hp_before, "the same trap deals damage when not dashing")


# ------------------------------------------------------------------------------
# Кулдаун C_dash и сигнал для HUD
# ------------------------------------------------------------------------------

func test_dash_cooldown_blocks_second_dash_and_is_emitted_for_hud() -> void:
	GameState.add_ability(AbilityDash.ID)
	var player: Player = _spawn_player()
	await _settle(player)
	var stamina_before: float = GameState.stamina
	var duration: float = player.balance.c_dash

	await _start_dash()
	assert_eq(player.get_state_name(), &"dash")
	assert_almost_eq(
		player.get_dash_cooldown_left(),
		duration,
		0.001,
		"cooldown starts at C_dash"
	)
	assert_almost_eq(
		GameState.stamina,
		stamina_before - player.balance.e_dash,
		0.001,
		"dash spends E_dash exactly once"
	)
	assert_gte(_cooldown_events.size(), 1, "HUD receives the cooldown start")
	assert_eq(_cooldown_events[0][0], &"dash", "signal carries the ability id")
	assert_almost_eq(float(_cooldown_events[0][1]), duration, 0.001, "remaining = C_dash")
	assert_almost_eq(float(_cooldown_events[0][2]), duration, 0.001, "duration = C_dash")

	while player.get_state_name() == &"dash":
		await get_tree().physics_frame
	var stamina_after_dash: float = GameState.stamina

	await _start_dash()
	assert_ne(player.get_state_name(), &"dash", "cooldown blocks an immediate second dash")
	assert_almost_eq(
		GameState.stamina,
		stamina_after_dash,
		0.001,
		"refused dash spends no stamina"
	)

	var guard: int = 0
	while not player.is_dash_ready() and guard < 120:
		await get_tree().physics_frame
		guard += 1
	assert_true(player.is_dash_ready(), "C_dash elapses")
	assert_true(
		player.balance.c_dash <= AbilityDash.MAX_COOLDOWN_SEC,
		"AC-02.2: cooldown is at most 1 s"
	)
	assert_almost_eq(
		float(_cooldown_events[-1][1]),
		0.0,
		0.001,
		"HUD receives remaining = 0 when ready"
	)
	assert_almost_eq(
		float(_cooldown_events[-1][2]),
		duration,
		0.001,
		"completion keeps the full duration"
	)

	await _start_dash()
	assert_eq(player.get_state_name(), &"dash", "dash is available again after the cooldown")


# ------------------------------------------------------------------------------
# Земля / воздух (AC-02.2)
# ------------------------------------------------------------------------------

func test_dash_is_available_in_the_air_from_jump() -> void:
	GameState.add_ability(AbilityDash.ID)
	var player: Player = _spawn_player()
	await _settle(player)

	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"jump", "ascending before the air dash")
	for _i: int in 3:
		await get_tree().physics_frame

	await _start_dash()
	assert_eq(player.get_state_name(), &"dash", "dash works in the air (Jump)")
	assert_false(player.is_on_floor(), "air dash keeps the player airborne")


func test_dash_is_available_while_falling() -> void:
	GameState.add_ability(AbilityDash.ID)
	var player: Player = _spawn_player()
	await _settle(player)

	InputManager.press_buffered(&"jump")
	await get_tree().physics_frame
	for _i: int in 120:
		await get_tree().physics_frame
		if player.get_state_name() == &"fall":
			break
	assert_eq(player.get_state_name(), &"fall", "descending before the air dash")

	await _start_dash()
	assert_eq(player.get_state_name(), &"dash", "dash works while falling")
