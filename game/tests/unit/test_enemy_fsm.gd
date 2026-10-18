extends GutTest
## T-12 — FSM врага: переходы, приоритеты, патруль/погоня, реакция на урон,
## смерть и границы зоны. Часть тестов — чистая логика EnemyStateMachine,
## часть — реальные сцены на 60 Hz physics (как в игре).

const SWIFT_SCENE: PackedScene = preload("res://entities/enemies/swift/swift_enemy.tscn")
const HEAVY_SCENE: PackedScene = preload("res://entities/enemies/heavy/heavy_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://entities/enemies/ranged/ranged_enemy.tscn")
const UNDEAD_SCENE: PackedScene = preload("res://entities/enemies/undead/undead_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")

const DATA_PATHS: Array[String] = [
	"res://data/enemies/swift_fiend.tres",
	"res://data/enemies/heavy_brute.tres",
	"res://data/enemies/ranged_cultist.tres",
	"res://data/enemies/undead_thrall.tres",
]

const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]

var _death_events: Array[Dictionary] = []


func before_each() -> void:
	GameState.reset_stamina()
	_reset_input()
	_death_events.clear()
	if not EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.connect(_on_enemy_died)


func after_each() -> void:
	if EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.disconnect(_on_enemy_died)
	_reset_input()


func _on_enemy_died(enemy_id: StringName, at_position: Vector2) -> void:
	_death_events.append({"id": enemy_id, "position": at_position})


func _reset_input() -> void:
	for action: StringName in ACTION_LIST:
		Input.action_release(action)
		InputManager.just_pressed(action)
		InputManager.consume_coyote_time(action)


func _make_floor(width: float, center_x: float = 0.0) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "TestFloor"
	body.position = Vector2(center_x, 8.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, 16.0)
	shape.shape = rect
	body.add_child(shape)
	add_child_autofree(body)
	return body


func _spawn_player(x: float) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(x, -10.0)
	player.velocity = Vector2.ZERO
	add_child_autofree(player)
	return player


func _spawn_enemy(scene: PackedScene, x: float) -> Enemy:
	var enemy: Enemy = scene.instantiate() as Enemy
	enemy.position = Vector2(x, -10.0)
	add_child_autofree(enemy)
	return enemy


func _wait_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().physics_frame


# ------------------------------------------------------------------------------
# Pure FSM
# ------------------------------------------------------------------------------

func test_fsm_starts_in_patrol_and_orders_priorities() -> void:
	var fsm := EnemyStateMachine.new()
	assert_eq(fsm.current, EnemyStateMachine.State.PATROL, "initial state is patrol")
	assert_eq(fsm.get_state_name(), &"patrol")
	assert_true(fsm.is_alive_state())
	assert_false(fsm.is_state(EnemyStateMachine.State.CHASE))
	assert_gt(
		fsm.get_priority(EnemyStateMachine.State.DEATH),
		fsm.get_priority(EnemyStateMachine.State.HURT),
		"Death outranks Hurt"
	)
	assert_gt(
		fsm.get_priority(EnemyStateMachine.State.HURT),
		fsm.get_priority(EnemyStateMachine.State.ATTACK),
		"Hurt outranks Attack"
	)
	assert_gt(
		fsm.get_priority(EnemyStateMachine.State.ATTACK),
		fsm.get_priority(EnemyStateMachine.State.CHASE),
		"Attack outranks Chase"
	)


func test_fsm_transition_table_and_priority() -> void:
	var fsm := EnemyStateMachine.new()
	assert_false(
		fsm.request_state(EnemyStateMachine.State.ATTACK),
		"patrol cannot jump straight to attack"
	)

	assert_true(fsm.request_state(EnemyStateMachine.State.CHASE), "patrol -> chase")
	assert_eq(fsm.current, EnemyStateMachine.State.CHASE)
	assert_true(fsm.request_state(EnemyStateMachine.State.ATTACK), "chase -> attack")
	assert_false(
		fsm.request_state(EnemyStateMachine.State.PATROL),
		"lower priority is not requested during attack"
	)
	assert_true(fsm.force_state(EnemyStateMachine.State.CHASE), "attack -> chase (forced)")
	assert_true(fsm.request_state(EnemyStateMachine.State.HURT), "hurt interrupts chase")
	assert_false(
		fsm.request_state(EnemyStateMachine.State.ATTACK),
		"attack cannot interrupt hurt"
	)
	assert_true(fsm.force_state(EnemyStateMachine.State.PATROL), "hurt -> patrol (forced)")


func test_death_is_terminal_and_resets_timer() -> void:
	var fsm := EnemyStateMachine.new()
	fsm.request_state(EnemyStateMachine.State.CHASE)
	fsm.tick(0.4)
	assert_almost_eq(fsm.time_in_state, 0.4, 0.001, "tick accumulates state time")
	assert_true(fsm.request_state(EnemyStateMachine.State.DEATH), "death interrupts chase")
	assert_eq(fsm.time_in_state, 0.0, "transition resets the state timer")
	assert_false(fsm.is_alive_state())
	assert_false(
		fsm.request_state(EnemyStateMachine.State.HURT),
		"death cannot be interrupted"
	)
	assert_false(
		fsm.force_state(EnemyStateMachine.State.PATROL),
		"death has no outgoing transitions"
	)
	assert_eq(fsm.current, EnemyStateMachine.State.DEATH)


# ------------------------------------------------------------------------------
# Data and scene contracts
# ------------------------------------------------------------------------------

func test_enemy_data_files_are_valid_and_distinct() -> void:
	var loaded: Array[EnemyData] = []
	for path: String in DATA_PATHS:
		var data: EnemyData = load(path) as EnemyData
		assert_not_null(data, "data loads: %s" % path)
		if data == null:
			continue
		assert_true(data.is_valid(), "data is valid: %s" % path)
		loaded.append(data)

	assert_eq(loaded.size(), 4, "four enemy types")
	var ids: Array[StringName] = []
	for data: EnemyData in loaded:
		assert_false(ids.has(data.id), "ids are unique")
		ids.append(data.id)

	var swift: EnemyData = load(DATA_PATHS[0]) as EnemyData
	var heavy: EnemyData = load(DATA_PATHS[1]) as EnemyData
	var ranged: EnemyData = load(DATA_PATHS[2]) as EnemyData
	var undead: EnemyData = load(DATA_PATHS[3]) as EnemyData

	assert_gt(swift.chase_speed, heavy.chase_speed, "swift is faster than heavy")
	assert_gt(swift.attack_lunge_speed, 0.0, "swift lunges during its attack")
	assert_gt(heavy.max_hp, swift.max_hp, "heavy has more HP")
	assert_gt(heavy.poise, 0.0, "heavy resists weak-hit stagger")
	assert_gt(heavy.knockback_resistance, 0.0, "heavy resists knockback")
	assert_gt(heavy.get_attack_total_time(), swift.get_attack_total_time(), "heavy telegraph is longer")
	assert_gt(ranged.preferred_distance, 0.0, "ranged keeps distance")
	assert_not_null(ranged.projectile_scene, "ranged has a projectile")
	assert_gt(ranged.detect_radius, swift.detect_radius, "ranged sees farther")
	assert_gt(undead.revive_count, 0, "undead revives")
	assert_gt(undead.revive_hp_ratio, 0.0)


func test_all_enemy_scenes_inherit_base_and_use_combat_layers() -> void:
	_make_floor(800.0)
	var swift: Enemy = _spawn_enemy(SWIFT_SCENE, -60.0)
	var heavy: Enemy = _spawn_enemy(HEAVY_SCENE, -20.0)
	var ranged: Enemy = _spawn_enemy(RANGED_SCENE, 20.0)
	var undead: Enemy = _spawn_enemy(UNDEAD_SCENE, 60.0)

	assert_true(swift is SwiftEnemy)
	assert_true(heavy is HeavyEnemy)
	assert_true(ranged is RangedEnemy)
	assert_true(undead is UndeadEnemy)

	for enemy: Enemy in [swift, heavy, ranged, undead]:
		assert_true(enemy.is_in_group(&"enemies"), "enemy joins the enemies group")
		assert_eq(enemy.get_state_name(), &"patrol", "spawns in patrol")
		assert_almost_eq(enemy.hp, enemy.data.max_hp, 0.001, "HP comes from data")
		assert_eq(enemy.hurtbox.collision_layer, CombatLayers.ENEMY_HURTBOX)
		assert_eq(enemy.hurtbox.collision_mask, 0, "hurtbox does not scan")
		assert_eq(enemy.attack_hitbox.collision_layer, CombatLayers.ENEMY_HITBOX)
		assert_eq(enemy.attack_hitbox.collision_mask, CombatLayers.PLAYER_HURTBOX)
		assert_eq(enemy.collision_layer, CombatLayers.ENEMY_BODY)
		assert_eq(enemy.collision_mask, CombatLayers.WORLD)
		var body_rect := enemy.body_shape.shape as RectangleShape2D
		assert_not_null(body_rect)
		if body_rect != null:
			assert_eq(body_rect.size, enemy.data.body_size, "body shape comes from data")


# ------------------------------------------------------------------------------
# Scene behaviour
# ------------------------------------------------------------------------------

func test_enemy_patrol_turns_at_ledge_and_stays_on_platform() -> void:
	# Платформа заканчивается на x = +100.
	_make_floor(200.0)
	var enemy: Enemy = _spawn_enemy(SWIFT_SCENE, 90.0)
	enemy.facing = 1
	await get_tree().physics_frame

	assert_eq(enemy.get_state_name(), &"patrol", "no player -> patrol")
	await _wait_frames(60)

	assert_eq(enemy.facing, -1, "turned away from the ledge")
	assert_lt(enemy.global_position.x, 99.0, "never walks off the platform")
	assert_true(enemy.is_on_floor(), "stays on the floor")
	assert_lt(enemy.fsm.transition_count, 2, "no state thrash while patrolling")


func test_enemy_chases_then_returns_to_patrol_outside_detection() -> void:
	_make_floor(800.0)
	var player: Player = _spawn_player(0.0)
	var enemy: Enemy = _spawn_enemy(SWIFT_SCENE, 60.0)
	await _wait_frames(3)
	assert_eq(enemy.get_state_name(), &"chase", "patrol -> chase on detection")

	player.global_position.x = 350.0
	await _wait_frames(3)
	assert_eq(enemy.get_state_name(), &"patrol", "chase -> patrol when target is lost")


func test_enemy_never_leaves_leash() -> void:
	_make_floor(1600.0)
	var player: Player = _spawn_player(80.0)
	var enemy: Enemy = _spawn_enemy(SWIFT_SCENE, 0.0)
	var data: EnemyData = enemy.data.duplicate(true) as EnemyData
	data.attack_radius = 1.0
	data.detect_radius = 400.0
	data.vertical_detect_radius = 100.0
	data.leash_radius = 96.0
	enemy.data = data

	await _wait_frames(3)
	assert_eq(enemy.get_state_name(), &"chase")
	while enemy.global_position.x < 40.0:
		await get_tree().physics_frame
	player.global_position.x = 300.0

	var max_offset: float = 0.0
	for _i: int in 180:
		await get_tree().physics_frame
		max_offset = maxf(
			max_offset,
			absf(enemy.global_position.x - enemy.home_position.x)
		)
	assert_lte(max_offset, data.leash_radius + 0.5, "AI stays inside its leash")
	assert_ne(enemy.get_state_name(), &"death", "leash clamp does not kill the enemy")


func test_stuck_watchdog_turns_enemy_after_timeout() -> void:
	_make_floor(800.0)
	var enemy: Enemy = _spawn_enemy(SWIFT_SCENE, 0.0)
	enemy.set_physics_process(false)
	enemy.facing = 1
	enemy._last_position = enemy.global_position

	var turned: bool = false
	for _i: int in 100:
		enemy._update_stuck(0.02)
		if enemy.facing == -1:
			turned = true
			break
	assert_true(turned, "watchdog prevents a permanently stuck enemy")
	assert_gt(enemy.patrol_wait_left, 0.0, "watchdog adds a patrol pause")


func test_scene_fsm_patrol_chase_hurt_death() -> void:
	_make_floor(800.0)
	_spawn_player(0.0)
	var enemy: Enemy = _spawn_enemy(SWIFT_SCENE, 60.0)
	await _wait_frames(3)
	assert_eq(enemy.get_state_name(), &"chase", "patrol -> chase")

	enemy.hurtbox.receive_damage(Damage.create(2.0))
	assert_eq(enemy.get_state_name(), &"hurt", "damage interrupts chase")
	assert_eq(
		enemy.visual.modulate,
		Damage.FLASH_COLOR,
		"hit flash starts in the same physics frame (<= 100 ms)"
	)
	assert_almost_eq(enemy.hp, enemy.data.max_hp - 2.0, 0.001)

	await _wait_frames(12)
	assert_eq(enemy.get_state_name(), &"chase", "hurt -> chase after t_hurt")

	enemy.hurtbox.receive_damage(Damage.create(999.0))
	assert_eq(enemy.get_state_name(), &"death", "lethal damage -> death")
	assert_true(enemy.is_dead, "enemy is marked dead")
	assert_false(enemy.attack_hitbox.active, "no attacks after death")

	var alpha_at_death: float = enemy.visual.modulate.a
	await _wait_frames(8)
	assert_lt(enemy.visual.modulate.a, alpha_at_death, "death animation fades the sprite")
	assert_eq(enemy.get_state_name(), &"death", "death is terminal")

	await get_tree().create_timer(enemy.balance.enemy_death_duration + 0.2).timeout
	assert_false(is_instance_valid(enemy), "enemy is freed after the death animation")
	assert_eq(_death_events.size(), 1, "EventBus.enemy_died is emitted once")
	if _death_events.size() == 1:
		assert_eq(_death_events[0]["id"], &"swift_fiend")
