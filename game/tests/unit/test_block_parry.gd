extends GutTest
## T-11 — блок, парирование и передняя дуга (AC-03.2/AC-03.3).
##
## Часть тестов проверяет чистую логику `Block` (окно T_parry внутри/вне,
## снижение на P_block %, дуга), часть — интеграцию с реальным Player на
## 60 Hz physics-кадрах: удержание блока, парирование, контратака, SFX,
## искра и отказ при нулевой выносливости.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]


func before_each() -> void:
	GameState.reset_stamina()
	GameState.reset_hp()
	GameState.set_weapon(load("res://data/weapons/one_handed_sword.tres") as WeaponData)
	AudioManager.reset()
	_reset_input()


func after_each() -> void:
	_reset_input()
	GameState.reset_hp()


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
	assert_true(player.is_on_floor(), "test player settles on the floor")
	assert_eq(player.get_state_name(), &"idle", "settled player is idle")


## Источник удара для проверки передней дуги (`Damage.source`).
func _source_at(x: float) -> Node2D:
	var source := Node2D.new()
	add_child_autofree(source)
	source.global_position = Vector2(x, -10.0)
	return source


func _hurt(amount: float, from_x: float) -> Damage:
	var damage: Damage = Damage.create(amount)
	damage.source = _source_at(from_x)
	return damage


func _enter_block(player: Player) -> void:
	Input.action_press(&"block")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"block", "block starts while held")


## Ожидание выхода окна парирования: T_parry = 0.18 s ≈ 11 кадров.
func _wait_past_parry(player: Player) -> void:
	var frames: int = 0
	while player.is_parry_window_open() and frames < 30:
		await get_tree().physics_frame
		frames += 1
	assert_false(player.is_parry_window_open(), "parry window is closed after T_parry")


# ------------------------------------------------------------------------------
# Block logic (pure)
# ------------------------------------------------------------------------------

func test_ordinary_block_reduces_damage_by_p_block_percent() -> void:
	var block := Block.new()
	block.setup(0.18, 80.0, 120.0)
	block.begin()
	block.update(0.5)

	var result: Dictionary = block.resolve_incoming(
		20.0, Vector2(10.0, 0.0), Vector2.ZERO, 1
	)

	assert_true(result["blocked"], "front hit is blocked")
	assert_false(result["parried"], "outside T_parry it is an ordinary block")
	assert_almost_eq(float(result["amount"]), 4.0, 0.001, "80% of damage absorbed")
	assert_almost_eq(float(result["absorbed"]), 16.0, 0.001, "absorbed amount")
	assert_eq(block.blocked_count, 1, "blocked hits are counted")
	assert_eq(block.parry_count, 0, "no parry outside the window")


func test_parry_window_inside_and_outside() -> void:
	var block := Block.new()
	block.setup(0.18, 80.0, 120.0)
	block.begin()
	assert_true(block.is_parry_window_open(), "window opens on block entry")

	var inside: Dictionary = block.resolve_incoming(
		20.0, Vector2(10.0, 0.0), Vector2.ZERO, 1
	)
	assert_true(inside["parried"], "hit inside T_parry is parried")
	assert_eq(float(inside["amount"]), 0.0, "parry negates all damage")
	assert_almost_eq(float(inside["absorbed"]), 20.0, 0.001, "parry absorbs the hit")
	assert_eq(block.parry_count, 1, "parry is counted")
	assert_false(block.is_parry_window_open(), "one parry per block activation")

	var same_hold: Dictionary = block.resolve_incoming(
		20.0, Vector2(10.0, 0.0), Vector2.ZERO, 1
	)
	assert_false(same_hold["parried"], "second hit in the same hold is a normal block")
	assert_almost_eq(float(same_hold["amount"]), 4.0, 0.001, "P_block applies")

	block.begin()
	block.update(0.18)
	assert_false(block.is_parry_window_open(), "window closes after exactly T_parry")
	var outside: Dictionary = block.resolve_incoming(
		20.0, Vector2(10.0, 0.0), Vector2.ZERO, 1
	)
	assert_true(outside["blocked"], "late hit is still blocked")
	assert_false(outside["parried"], "late hit is not parried")
	assert_almost_eq(float(outside["amount"]), 4.0, 0.001, "ordinary block damage")


func test_block_arc_is_front_only() -> void:
	var block := Block.new()
	block.setup(0.18, 80.0, 120.0)
	block.begin()

	var front: Dictionary = block.resolve_incoming(
		10.0, Vector2(10.0, 0.0), Vector2.ZERO, 1
	)
	assert_true(front["blocked"], "hit in front of the facing is blocked")

	var behind: Dictionary = block.resolve_incoming(
		10.0, Vector2(-10.0, 0.0), Vector2.ZERO, 1
	)
	assert_false(behind["blocked"], "hit from behind bypasses the block")
	assert_almost_eq(float(behind["amount"]), 10.0, 0.001, "rear hit deals full damage")

	var above: Dictionary = block.resolve_incoming(
		10.0, Vector2(0.0, -10.0), Vector2.ZERO, 1
	)
	assert_false(above["blocked"], "120-degree arc does not cover the side/top")


func test_block_activation_requires_e_block_stamina() -> void:
	var block := Block.new()
	block.setup(0.18, 80.0, 120.0, 8.0)

	assert_eq(block.stamina_cost, 8.0, "E_block comes from balancing data")
	assert_false(block.can_activate(0.0), "no stamina -> block is unavailable (AC-03.3)")
	assert_false(block.can_activate(7.9), "less than E_block -> unavailable")
	assert_true(block.can_activate(8.0), "exactly E_block is enough")
	assert_true(block.can_activate(50.0), "enough stamina -> block is available")


# ------------------------------------------------------------------------------
# Player integration (real 60 Hz frames)
# ------------------------------------------------------------------------------

func test_block_spends_e_block_and_opens_parry_window() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	var stamina_before: float = GameState.stamina

	await _enter_block(player)

	assert_almost_eq(
		GameState.stamina,
		stamina_before - player.balance.e_block,
		0.001,
		"block spends E_block (AC-03.2)"
	)
	assert_true(player.is_blocking(), "block logic is active")
	assert_true(player.is_parry_window_open(), "T_parry window is open on entry")
	Input.action_release(&"block")
	await get_tree().physics_frame
	assert_false(player.is_blocking(), "releasing block ends the guard")


func test_blocked_hit_is_reduced_and_guard_holds() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	await _enter_block(player)
	await _wait_past_parry(player)

	GameState.set_hp(100.0)
	var damage: Damage = _hurt(20.0, 20.0)
	var result: Dictionary = player.receive_hit(damage)
	var expected: float = Block.reduced_amount(20.0, player.balance.p_block)

	assert_true(result["blocked"], "front hit hits the guard")
	assert_false(result["parried"], "outside T_parry it is an ordinary block")
	assert_almost_eq(float(result["amount"]), expected, 0.001, "P_block reduction")
	assert_almost_eq(damage.amount, expected, 0.001, "payload is reduced for the target")
	assert_almost_eq(GameState.hp, 100.0 - expected, 0.001, "reduced damage reaches HP")
	assert_eq(player.get_state_name(), &"block", "guard is not interrupted by a blocked hit")
	assert_eq(player.block.blocked_count, 1, "blocked hit is counted")


func test_parry_negates_damage_opens_counter_and_plays_sfx() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	await _enter_block(player)
	assert_true(player.is_parry_window_open(), "window is open right after entry")

	var animation: PlayerAnimation = player.get_node("Animation") as PlayerAnimation
	var hp_before: float = GameState.hp
	var damage: Damage = _hurt(25.0, 20.0)
	var result: Dictionary = player.receive_hit(damage)

	assert_true(result["blocked"], "parry is a blocked outcome")
	assert_true(result["parried"], "hit inside T_parry is parried")
	assert_almost_eq(GameState.hp, hp_before, 0.001, "parry negates damage")
	assert_true(player.is_parry_counter_open(), "parry opens the counter-attack window")
	assert_eq(player.block.parry_count, 1, "parry is counted")
	assert_eq(AudioManager.last_sfx_id, &"parry", "parry plays SFX 'parry' (T-34)")
	assert_eq(animation.parry_spark_count, 1, "parry shows the spark flash (DESIGN §7)")

	var stamina_before: float = GameState.stamina
	InputManager.press_buffered(&"attack")
	await get_tree().physics_frame

	assert_eq(player.get_state_name(), &"attack", "counter-attack starts from block")
	assert_almost_eq(
		GameState.stamina,
		stamina_before,
		0.001,
		"counter-attack is free (reward for the parry)"
	)
	assert_false(player.is_parry_counter_open(), "counter window is consumed")


func test_attack_from_behind_is_not_blocked() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	await _enter_block(player)
	await _wait_past_parry(player)

	GameState.set_hp(100.0)
	var damage: Damage = _hurt(20.0, -20.0)
	var result: Dictionary = player.receive_hit(damage)

	assert_false(result["blocked"], "rear attack bypasses the front arc")
	assert_almost_eq(float(result["amount"]), 20.0, 0.001, "full damage from behind")
	assert_almost_eq(GameState.hp, 80.0, 0.001, "full damage reaches HP")
	assert_ne(player.get_state_name(), &"block", "rear hit interrupts the guard")


func test_block_is_unavailable_at_zero_stamina() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	GameState.stamina = 0.0
	assert_true(GameState.is_stamina_exhausted(), "HUD flag is raised (AC-03.3)")

	Input.action_press(&"block")
	await get_tree().physics_frame

	assert_ne(player.get_state_name(), &"block", "0 stamina -> block is not performed")
	assert_false(player.is_blocking(), "block logic never starts")
	assert_almost_eq(GameState.stamina, 0.0, 0.001, "failed block spends nothing")
