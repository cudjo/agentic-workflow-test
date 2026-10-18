extends GutTest
## T-12 — e2e-проверка боя: игрок ↔ враги, 4 паттерна, 5 врагов через
## EnemySpawner, реакция на урон <= 100 мс, анимация смерти и очистка зоны.
## Работает на реальных 60 Hz physics-кадрах и настоящих сценах Player/Enemy.

const SWIFT_SCENE: PackedScene = preload("res://entities/enemies/swift/swift_enemy.tscn")
const HEAVY_SCENE: PackedScene = preload("res://entities/enemies/heavy/heavy_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://entities/enemies/ranged/ranged_enemy.tscn")
const UNDEAD_SCENE: PackedScene = preload("res://entities/enemies/undead/undead_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const DEFAULT_WEAPON_PATH: String = "res://data/weapons/one_handed_sword.tres"

const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]

var _death_events: Array[Dictionary] = []
var _all_defeated: bool = false
var _projectile_seen: bool = false
var _last_shot_distance: float = -1.0
var _watched_player: Player = null


func before_each() -> void:
	GameState.reset_stamina()
	GameState.set_weapon(load(DEFAULT_WEAPON_PATH) as WeaponData)
	_reset_input()
	_death_events.clear()
	_all_defeated = false
	_projectile_seen = false
	_last_shot_distance = -1.0
	_watched_player = null
	if not EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.connect(_on_enemy_died)


func after_each() -> void:
	if EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.disconnect(_on_enemy_died)
	GameState.set_weapon(load(DEFAULT_WEAPON_PATH) as WeaponData)
	_reset_input()


func _on_enemy_died(enemy_id: StringName, at_position: Vector2) -> void:
	_death_events.append({"id": enemy_id, "position": at_position})


func _on_all_defeated() -> void:
	_all_defeated = true


func _on_enemy_attack(enemy: Enemy) -> void:
	if _watched_player != null and is_instance_valid(_watched_player):
		_last_shot_distance = enemy.global_position.distance_to(_watched_player.global_position)
	for child: Node in enemy.get_parent().get_children():
		if child is EnemyProjectile:
			_projectile_seen = true


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


func _settle(player: Player) -> void:
	for _i: int in 15:
		await get_tree().physics_frame
	assert_true(player.is_on_floor(), "player settles on the floor")
	assert_eq(player.get_state_name(), &"idle", "settled player is idle")


func _wait_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().physics_frame


func _make_passive(enemy: Enemy) -> void:
	var data: EnemyData = enemy.data.duplicate(true) as EnemyData
	data.detect_radius = 0.0
	data.patrol_speed = 0.0
	enemy.data = data


func _new_entry(scene: PackedScene, count: int, offset: Vector2, spacing: float) -> EnemySpawnEntry:
	var entry := EnemySpawnEntry.new()
	entry.enemy_scene = scene
	entry.count = count
	entry.offset = offset
	entry.spacing = spacing
	return entry


# ------------------------------------------------------------------------------
# Player -> enemy
# ------------------------------------------------------------------------------

func test_player_hit_damages_enemy_with_flash_hurt_knockback_and_death_animation() -> void:
	_make_floor(800.0)
	var player: Player = _spawn_player(0.0)
	var enemy: Enemy = _spawn_enemy(SWIFT_SCENE, 16.0)
	_make_passive(enemy)
	await _settle(player)

	var hp_before: float = enemy.hp
	InputManager.press_buffered(&"attack")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"attack", "player attack starts")

	var frames: int = 0
	while enemy.hp >= hp_before and frames < 40:
		await get_tree().physics_frame
		frames += 1

	assert_lt(enemy.hp, hp_before, "enemy receives formula damage from the player hitbox")
	assert_almost_eq(
		enemy.hp,
		hp_before - player.get_weapon().damage,
		0.001,
		"damage comes from the T-10 formula/weapon data"
	)
	assert_eq(
		enemy.visual.modulate,
		Damage.FLASH_COLOR,
		"hit flash is visible in the same physics frame (reaction <= 100 ms)"
	)
	assert_eq(enemy.get_state_name(), &"hurt", "enemy reacts with Hurt")
	assert_gt(enemy.velocity.x, 0.0, "player knockback pushes the enemy away")

	enemy.hurtbox.receive_damage(Damage.create(999.0))
	assert_eq(enemy.get_state_name(), &"death", "lethal hit enters Death")
	assert_true(enemy.is_dead)
	var alpha_at_death: float = enemy.visual.modulate.a
	await _wait_frames(8)
	assert_lt(enemy.visual.modulate.a, alpha_at_death, "death animation plays (fade/squash)")
	assert_true(is_instance_valid(enemy), "enemy is not freed before the animation ends")

	await get_tree().create_timer(enemy.balance.enemy_death_duration + 0.2).timeout
	assert_false(is_instance_valid(enemy), "enemy is freed after the death animation")
	assert_eq(_death_events.size(), 1, "permanent death is broadcast once")
	if _death_events.size() == 1:
		assert_eq(_death_events[0]["id"], &"swift_fiend")


# ------------------------------------------------------------------------------
# Enemy -> player
# ------------------------------------------------------------------------------

func test_heavy_enemy_attack_damages_player_hurtbox() -> void:
	_make_floor(1000.0)
	var player: Player = _spawn_player(0.0)
	await _settle(player)
	var player_hurtbox: Hurtbox = player.get_node("Hurtbox") as Hurtbox
	var heavy: Enemy = _spawn_enemy(HEAVY_SCENE, 30.0)

	var frames: int = 0
	while player_hurtbox.hit_count == 0 and frames < 240:
		await get_tree().physics_frame
		frames += 1

	assert_gt(player_hurtbox.hit_count, 0, "heavy lands its telegraphed slam")
	assert_not_null(player_hurtbox.last_damage)
	if player_hurtbox.last_damage != null:
		assert_almost_eq(
			player_hurtbox.last_damage.amount,
			heavy.data.attack_damage,
			0.001,
			"enemy damage comes from data"
		)
		assert_gt(
			player_hurtbox.last_damage.knockback.length(),
			0.0,
			"enemy hit carries knockback"
		)
	assert_eq(
		player.visual.modulate,
		Damage.FLASH_COLOR,
		"player hit flash starts in the same physics frame (<= 100 ms)"
	)
	var second_frames: int = 0
	while player_hurtbox.hit_count < 2 and second_frames < 300:
		await get_tree().physics_frame
		second_frames += 1

	assert_gte(player_hurtbox.hit_count, 2, "heavy can hit again on the next swing")
	assert_gt(heavy.fsm.transition_count, 1, "heavy went chase -> attack")


func test_ranged_enemy_keeps_distance_and_fires_projectile() -> void:
	_make_floor(1400.0)
	var player: Player = _spawn_player(0.0)
	await _settle(player)
	_watched_player = player
	var player_hurtbox: Hurtbox = player.get_node("Hurtbox") as Hurtbox
	var ranged: Enemy = _spawn_enemy(RANGED_SCENE, 40.0)
	ranged.attack_performed.connect(_on_enemy_attack)

	var frames: int = 0
	while player_hurtbox.hit_count == 0 and frames < 300:
		await get_tree().physics_frame
		frames += 1

	assert_gt(player_hurtbox.hit_count, 0, "projectile reaches the player hurtbox")
	assert_true(_projectile_seen, "ranged attack spawns an EnemyProjectile")
	assert_gt(_last_shot_distance, 48.0, "ranged enemy shoots from a distance")
	if player_hurtbox.last_damage != null:
		assert_almost_eq(
			player_hurtbox.last_damage.amount,
			ranged.data.attack_damage,
			0.001
		)
	assert_false(ranged.attack_hitbox.active, "ranged enemy does not use the melee hitbox")


func test_heavy_poise_ignores_weak_hits_but_not_strong_ones() -> void:
	_make_floor(800.0)
	_spawn_player(400.0)
	var heavy: Enemy = _spawn_enemy(HEAVY_SCENE, 0.0)
	await _wait_frames(2)
	assert_eq(heavy.get_state_name(), &"patrol", "target is out of range")

	heavy.hurtbox.receive_damage(Damage.create(6.0))
	assert_almost_eq(heavy.hp, heavy.data.max_hp - 6.0, 0.001, "weak hit still deals damage")
	assert_ne(heavy.get_state_name(), &"hurt", "weak hit does not break poise")

	heavy.hurtbox.receive_damage(Damage.create(10.0))
	assert_almost_eq(heavy.hp, heavy.data.max_hp - 16.0, 0.001)
	assert_eq(heavy.get_state_name(), &"hurt", "strong hit breaks poise")

	while heavy.get_state_name() == &"hurt":
		await get_tree().physics_frame
	assert_true(heavy.fsm.request_state(EnemyStateMachine.State.CHASE))
	assert_true(heavy.fsm.request_state(EnemyStateMachine.State.ATTACK))
	var velocity_before: float = heavy.velocity.x
	heavy._apply_incoming_knockback(Damage.create(1.0, Vector2(100.0, 0.0)))
	assert_almost_eq(
		heavy.velocity.x,
		velocity_before,
		0.001,
		"heavy has super armor against knockback during the slam"
	)


func test_undead_revives_once_after_death_animation() -> void:
	_make_floor(1200.0)
	_spawn_player(500.0)
	var undead: Enemy = _spawn_enemy(UNDEAD_SCENE, 0.0)
	await _wait_frames(2)

	undead.hurtbox.receive_damage(Damage.create(999.0))
	assert_eq(undead.get_state_name(), &"death")
	assert_true(undead.is_dead)
	await get_tree().create_timer(
		undead.balance.enemy_death_duration + undead.data.revive_delay + 0.25
	).timeout

	assert_true(is_instance_valid(undead), "undead is not freed after the first death")
	if is_instance_valid(undead):
		assert_false(undead.is_dead, "undead revives")
		assert_almost_eq(
			undead.hp,
			undead.data.max_hp * undead.data.revive_hp_ratio,
			0.01,
			"revive HP comes from data"
		)
		assert_ne(undead.get_state_name(), &"death")
	assert_eq(_death_events.size(), 0, "first death of undead is not permanent")

	if is_instance_valid(undead):
		undead.hurtbox.receive_damage(Damage.create(999.0))
		await get_tree().create_timer(undead.balance.enemy_death_duration + 0.25).timeout
	assert_false(is_instance_valid(undead), "second death is permanent")
	assert_eq(_death_events.size(), 1, "final death is broadcast once")


# ------------------------------------------------------------------------------
# 5-enemy encounter through EnemySpawner
# ------------------------------------------------------------------------------

func test_five_enemy_encounter_spawns_fights_and_can_be_cleared() -> void:
	_make_floor(1600.0)
	var player: Player = _spawn_player(0.0)
	await _settle(player)
	_watched_player = player
	var player_hurtbox: Hurtbox = player.get_node("Hurtbox") as Hurtbox

	var spawner := EnemySpawner.new()
	spawner.auto_spawn = false
	spawner.position = Vector2(0.0, -10.0)
	add_child_autofree(spawner)
	spawner.all_defeated.connect(_on_all_defeated)
	spawner.entries.append(_new_entry(SWIFT_SCENE, 2, Vector2(60.0, 0.0), 15.0))
	spawner.entries.append(_new_entry(HEAVY_SCENE, 1, Vector2(70.0, 0.0), 0.0))
	spawner.entries.append(_new_entry(RANGED_SCENE, 1, Vector2(100.0, 0.0), 0.0))
	spawner.entries.append(_new_entry(UNDEAD_SCENE, 1, Vector2(85.0, 0.0), 0.0))

	var spawned: Array[Enemy] = spawner.spawn_all()
	assert_eq(spawned.size(), 5, "spawner creates 5 enemies")
	assert_eq(spawner.remaining_count(), 5)
	assert_true(spawned[0] is SwiftEnemy)
	assert_true(spawned[1] is SwiftEnemy)
	assert_true(spawned[2] is HeavyEnemy)
	assert_true(spawned[3] is RangedEnemy)
	assert_true(spawned[4] is UndeadEnemy)

	for enemy: Enemy in spawned:
		enemy.attack_performed.connect(_on_enemy_attack)

	await _wait_frames(150)

	assert_gt(player_hurtbox.hit_count, 0, "5 enemies deal damage to the player")
	assert_true(_projectile_seen, "ranged enemy joins the fight with a projectile")
	for enemy: Enemy in spawned:
		assert_true(is_instance_valid(enemy), "enemy survives the engagement")
		if not is_instance_valid(enemy):
			continue
		assert_false(enemy.is_dead, "no accidental friendly-fire deaths")
		assert_gt(enemy.fsm.transition_count, 0, "AI does not stick in patrol")
		assert_lte(
			absf(enemy.global_position.x - enemy.home_position.x),
			enemy.data.leash_radius + 0.5,
			"enemy stays inside its zone during the fight"
		)

	# Игрок добивает всех: обычные умирают, нежить возрождается один раз.
	for enemy: Enemy in spawned:
		if is_instance_valid(enemy) and not enemy.is_dead:
			enemy.hurtbox.receive_damage(Damage.create(999.0))
	await get_tree().create_timer(
		player.balance.enemy_death_duration + 0.35 + 0.3
	).timeout

	for enemy: Enemy in spawned:
		if is_instance_valid(enemy) and not enemy.is_dead:
			enemy.hurtbox.receive_damage(Damage.create(999.0))
	await get_tree().create_timer(player.balance.enemy_death_duration + 0.3).timeout

	assert_eq(spawner.remaining_count(), 0, "all 5 enemies are permanently defeated")
	assert_eq(spawner.spawned_count, 5)
	assert_eq(spawner.defeated_count, 5)
	assert_true(_all_defeated, "spawner reports the encounter as cleared")
	assert_eq(_death_events.size(), 5, "each enemy emits exactly one permanent death")
