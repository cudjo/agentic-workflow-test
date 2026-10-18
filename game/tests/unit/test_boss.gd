extends GutTest
## T-30 — boss framework и боссы зон 1–2.
##
## Покрывает: данные и пороги фаз 66/33 (AC-03.4), смену паттерна с
## уведомлением HUD, различимые паттерны ближнего/дальнего боссов, арену с
## барьерами, EC-09 (босс остаётся мёртвым, награда — при следующем входе),
## персистентность через SaveManager и бюджет 60 FPS в длительном бою.

const ARENA_ZONE_01: PackedScene = preload(
	"res://entities/bosses/zone_01/boss_arena_zone_01.tscn"
)
const ARENA_ZONE_02: PackedScene = preload(
	"res://entities/bosses/zone_02/boss_arena_zone_02.tscn"
)
const BOSS_ZONE_01: PackedScene = preload(
	"res://entities/bosses/zone_01/zone_01_boss.tscn"
)
const BOSS_ZONE_02: PackedScene = preload(
	"res://entities/bosses/zone_02/zone_02_boss.tscn"
)
const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const DATA_ZONE_01: String = "res://data/bosses/zone_01_boss.tres"
const DATA_ZONE_02: String = "res://data/bosses/zone_02_boss.tres"
const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const SAVE_DIR: String = "user://test_saves_t30"
const PLAYER_LAYER: int = 1 << 1
const WORLD_LAYER: int = 1
const FLOOR_TOP: float = 0.0


class TestBody extends CharacterBody2D:
	var use_gravity: bool = true
	var constant_velocity: Vector2 = Vector2.ZERO
	var gravity: float = 523.0

	func _physics_process(delta: float) -> void:
		if use_gravity:
			velocity.y += gravity * delta
		else:
			velocity = constant_velocity
		move_and_slide()


var _phase_events: Array[Dictionary] = []
var _defeat_events: Array[Dictionary] = []
var _reward_events: Array[Dictionary] = []
var _fight_events: Array[Dictionary] = []
var _saves_dir_original: String = ""


func before_all() -> void:
	_saves_dir_original = SaveManager.saves_dir


func after_all() -> void:
	SaveManager.saves_dir = _saves_dir_original
	_cleanup_save_dir()


func before_each() -> void:
	GameState.reset_boss_progress()
	GameState.reset_stamina()
	_phase_events.clear()
	_defeat_events.clear()
	_reward_events.clear()
	_fight_events.clear()
	_connect_events()
	SaveManager.saves_dir = SAVE_DIR
	_cleanup_save_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func after_each() -> void:
	_disconnect_events()
	GameState.reset_boss_progress()
	SaveManager.saves_dir = _saves_dir_original
	_cleanup_save_dir()


func _connect_events() -> void:
	if not EventBus.boss_phase_changed.is_connected(_on_phase_changed):
		EventBus.boss_phase_changed.connect(_on_phase_changed)
	if not EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.connect(_on_boss_defeated)
	if not EventBus.boss_reward_granted.is_connected(_on_boss_reward):
		EventBus.boss_reward_granted.connect(_on_boss_reward)
	if not EventBus.boss_fight_started.is_connected(_on_fight_started):
		EventBus.boss_fight_started.connect(_on_fight_started)


func _disconnect_events() -> void:
	if EventBus.boss_phase_changed.is_connected(_on_phase_changed):
		EventBus.boss_phase_changed.disconnect(_on_phase_changed)
	if EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.disconnect(_on_boss_defeated)
	if EventBus.boss_reward_granted.is_connected(_on_boss_reward):
		EventBus.boss_reward_granted.disconnect(_on_boss_reward)
	if EventBus.boss_fight_started.is_connected(_on_fight_started):
		EventBus.boss_fight_started.disconnect(_on_fight_started)


func _on_phase_changed(boss_id: StringName, phase_index: int, title: String) -> void:
	_phase_events.append({
		"boss_id": boss_id,
		"index": phase_index,
		"title": title,
	})


func _on_boss_defeated(
	boss_id: StringName,
	zone_id: StringName,
	at_position: Vector2
) -> void:
	_defeat_events.append({
		"boss_id": boss_id,
		"zone_id": zone_id,
		"position": at_position,
	})


func _on_boss_reward(boss_id: StringName, reward_id: StringName, gold: int) -> void:
	_reward_events.append({
		"boss_id": boss_id,
		"reward_id": reward_id,
		"gold": gold,
	})


func _on_fight_started(
	boss_id: StringName,
	display_name: String,
	max_hp: float,
	thresholds: PackedFloat32Array
) -> void:
	_fight_events.append({
		"boss_id": boss_id,
		"display_name": display_name,
		"max_hp": max_hp,
		"thresholds": thresholds,
	})


func _make_floor(width: float, center_x: float = 0.0) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "TestFloor"
	body.position = Vector2(center_x, FLOOR_TOP + 8.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, 16.0)
	shape.shape = rect
	body.add_child(shape)
	add_child_autofree(body)
	return body


func _spawn_boss(scene: PackedScene, x: float, parent: Node = null) -> BossBase:
	var boss: BossBase = scene.instantiate() as BossBase
	boss.position = Vector2(x, -30.0)
	if parent == null:
		add_child_autofree(boss)
	else:
		parent.add_child(boss)
	return boss


func _spawn_player(x: float, y: float = -10.0) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(x, y)
	add_child_autofree(player)
	return player


func _spawn_arena(scene: PackedScene) -> BossArena:
	var arena: BossArena = scene.instantiate() as BossArena
	add_child_autofree(arena)
	return arena


func _wait_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().physics_frame


func _cleanup_save_dir() -> void:
	var directory: DirAccess = DirAccess.open(SAVE_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for directory_name: String in directory.get_directories():
		directory.remove(directory_name)


# ------------------------------------------------------------------------------
# Data / phase contract
# ------------------------------------------------------------------------------

func test_boss_data_is_valid_and_uses_design_phase_thresholds() -> void:
	var zone_01: BossData = load(DATA_ZONE_01) as BossData
	var zone_02: BossData = load(DATA_ZONE_02) as BossData
	assert_not_null(zone_01, "zone 1 boss data loads")
	assert_not_null(zone_02, "zone 2 boss data loads")
	if zone_01 == null or zone_02 == null:
		return

	assert_true(zone_01.is_valid(), "zone 1 BossData is valid")
	assert_true(zone_02.is_valid(), "zone 2 BossData is valid")
	assert_ne(zone_01.id, zone_02.id, "boss ids are unique")
	assert_ne(zone_01.zone_id, zone_02.zone_id, "bosses belong to different zones")
	assert_ne(zone_01.reward.id, zone_02.reward.id, "rewards are distinct")

	for data: BossData in [zone_01, zone_02]:
		assert_eq(data.get_phase_count(), 3, "%s has 3 phases" % data.id)
		assert_almost_eq(
			data.phases[0].hp_threshold_ratio,
			1.0,
			0.001,
			"phase I starts at 100%"
		)
		assert_almost_eq(
			data.phases[1].hp_threshold_ratio,
			BossData.PHASE_TWO_THRESHOLD,
			0.001,
			"phase II threshold is 66%"
		)
		assert_almost_eq(
			data.phases[2].hp_threshold_ratio,
			BossData.PHASE_THREE_THRESHOLD,
			0.001,
			"phase III threshold is 33%"
		)
		assert_eq(data.get_phase_index_for_ratio(1.0), 0)
		assert_eq(data.get_phase_index_for_ratio(0.67), 0, "above 66% is phase I")
		assert_eq(data.get_phase_index_for_ratio(0.66), 1, "66% switches to phase II")
		assert_eq(data.get_phase_index_for_ratio(0.34), 1, "above 33% is phase II")
		assert_eq(data.get_phase_index_for_ratio(0.33), 2, "33% switches to phase III")
		assert_eq(data.get_phase_index_for_ratio(0.0), 2)
		assert_eq(data.get_phase_thresholds().size(), 2, "HUD gets two phase marks")

		var patterns: Array[StringName] = []
		for phase: BossPhaseData in data.phases:
			assert_false(patterns.has(phase.pattern_id), "patterns are unique within a boss")
			patterns.append(phase.pattern_id)
		assert_false(patterns[0].is_empty())
		assert_false(patterns[1].is_empty())
		assert_false(patterns[2].is_empty())

	# Ближний босс — только melee; дальний — снаряды и вызовы.
	assert_null(zone_01.projectile_scene, "zone 1 boss has no projectile scene")
	for phase: BossPhaseData in zone_01.phases:
		assert_eq(phase.projectile_count, 0, "zone 1 stays melee in every phase")
		assert_eq(phase.summon_count, 0)
	assert_ne(zone_02.projectile_scene, null, "zone 2 boss fires projectiles")
	assert_ne(zone_02.summon_scene, null, "zone 2 boss can summon")
	assert_gt(zone_02.phases[0].preferred_distance, 0.0, "ranged boss keeps distance")
	assert_gt(zone_02.phases[2].summon_count, 0, "last phase summons minions")
	assert_ne(zone_01.phases[0].pattern_id, zone_02.phases[0].pattern_id)


func test_boss_scenes_use_data_and_combat_layers() -> void:
	_make_floor(800.0)
	var zone_01: BossBase = _spawn_boss(BOSS_ZONE_01, -80.0)
	var zone_02: BossBase = _spawn_boss(BOSS_ZONE_02, 80.0)
	await _wait_frames(2)

	assert_true(zone_01 is Zone01Boss)
	assert_true(zone_02 is Zone02Boss)
	for boss: BossBase in [zone_01, zone_02]:
		assert_not_null(boss.data)
		assert_almost_eq(boss.hp, boss.data.max_hp, 0.001, "HP comes from data")
		assert_eq(boss.phase_index, 0, "boss starts in phase I")
		assert_eq(boss.get_phase_count(), 3)
		assert_false(boss.fight_active, "boss waits for the arena/trigger")
		assert_true(boss.is_in_group(&"bosses"))
		assert_eq(boss.collision_layer, CombatLayers.ENEMY_BODY)
		assert_eq(boss.collision_mask, CombatLayers.WORLD)
		assert_eq(boss.hurtbox.collision_layer, CombatLayers.ENEMY_HURTBOX)
		assert_eq(boss.hurtbox.collision_mask, 0, "hurtbox does not scan")
		assert_eq(boss.attack_hitbox.collision_layer, CombatLayers.ENEMY_HITBOX)
		assert_eq(boss.attack_hitbox.collision_mask, CombatLayers.PLAYER_HURTBOX)
		assert_eq(boss.get_pattern_id(), boss.data.phases[0].pattern_id)


# ------------------------------------------------------------------------------
# Phase switching (AC-03.4)
# ------------------------------------------------------------------------------

func test_phase_switch_notifies_hud_and_changes_pattern() -> void:
	_make_floor(800.0)
	var player: Player = _spawn_player(100.0)
	var boss: BossBase = _spawn_boss(BOSS_ZONE_01, 0.0)
	await _wait_frames(2)
	assert_true(boss.activate_fight(), "fight starts")
	assert_true(player.is_inside_tree())

	assert_eq(_fight_events.size(), 1, "HUD receives boss_fight_started")
	if _fight_events.size() == 1:
		assert_eq(_fight_events[0]["boss_id"], &"zone_01_warden")
		assert_eq(_fight_events[0]["display_name"], "Пепельный Страж")
		assert_almost_eq(float(_fight_events[0]["max_hp"]), boss.data.max_hp, 0.001)
		var thresholds: PackedFloat32Array = PackedFloat32Array(
			_fight_events[0]["thresholds"]
		)
		assert_eq(thresholds.size(), 2)

	var first_pattern: StringName = boss.get_pattern_id()
	# 260 → 170 HP = 65.4%: пересекаем порог 66%.
	boss.hurtbox.receive_damage(Damage.create(boss.data.max_hp * 0.35))
	assert_almost_eq(boss.hp, 169.0, 0.001)
	assert_eq(boss.phase_index, 1, "HP below 66% switches to phase II")
	assert_ne(boss.get_pattern_id(), first_pattern, "phase II switches the pattern")
	assert_eq(boss.get_pattern_id(), &"lunge")
	assert_eq(boss.get_phase_title(), "ФАЗА II")
	assert_eq(_phase_events.size(), 1, "HUD is notified about the phase change")
	if _phase_events.size() == 1:
		assert_eq(_phase_events[0]["boss_id"], &"zone_01_warden")
		assert_eq(_phase_events[0]["index"], 1)
		assert_eq(_phase_events[0]["title"], "ФАЗА II")
	assert_true(boss.hurtbox.invulnerable, "phase transition has a short i-frame window")
	assert_eq(
		boss.visual.modulate,
		Damage.FLASH_COLOR,
		"hit flash starts in the same frame (AC-03.1)"
	)

	# Урон во время перехода фазы не проходит — паттерн успевает смениться.
	var hp_before: float = boss.hp
	assert_false(
		boss.hurtbox.receive_damage(Damage.create(5.0)),
		"phase transition ignores damage"
	)
	assert_almost_eq(boss.hp, hp_before, 0.001)

	var balance := load(BALANCE_PATH) as BalancingParams
	await wait_seconds(balance.boss_phase_transition_time + 0.1)
	assert_false(boss.hurtbox.invulnerable, "i-frames end after the transition")

	# 170 → 70 HP = 26.9%: пересекаем порог 33%.
	boss.hurtbox.receive_damage(Damage.create(100.0))
	assert_eq(boss.phase_index, 2, "HP below 33% switches to phase III")
	assert_eq(boss.get_pattern_id(), &"frenzy")
	assert_eq(boss.get_phase_title(), "ФАЗА III")
	assert_eq(_phase_events.size(), 2)
	if _phase_events.size() == 2:
		assert_eq(_phase_events[1]["index"], 2)
		assert_eq(_phase_events[1]["title"], "ФАЗА III")


# ------------------------------------------------------------------------------
# Distinct patterns
# ------------------------------------------------------------------------------

func test_zone_01_and_zone_02_patterns_are_distinct() -> void:
	_make_floor(1200.0)
	_spawn_player(200.0)

	var zone_01: BossBase = _spawn_boss(BOSS_ZONE_01, 0.0)
	await _wait_frames(2)
	zone_01.activate_fight()
	await _wait_frames(1)
	zone_01.phase_index = 1
	zone_01._perform_attack()
	assert_true(zone_01.attack_hitbox.active, "zone 1 phase II attacks with the melee hitbox")
	assert_eq(zone_01.attack_hitbox.collision_layer, CombatLayers.ENEMY_HITBOX)

	var container := Node2D.new()
	container.name = "Zone02Root"
	add_child_autofree(container)
	var zone_02: BossBase = _spawn_boss(BOSS_ZONE_02, 0.0, container)
	await _wait_frames(2)
	zone_02.activate_fight()
	await _wait_frames(1)

	zone_02.phase_index = 0
	zone_02._perform_attack()
	assert_eq(_count_projectiles(container), 1, "phase I fires a single bolt")
	assert_eq(_count_summons(container), 0)

	zone_02.phase_index = 1
	zone_02._perform_attack()
	assert_eq(_count_projectiles(container), 4, "phase II fires a 3-projectile volley")
	assert_eq(_count_summons(container), 0)

	zone_02.phase_index = 2
	zone_02._perform_attack()
	assert_eq(_count_projectiles(container), 6, "phase III adds a 2-projectile fan")
	await _wait_frames(1)
	assert_eq(_count_summons(container), 2, "phase III summons two minions")
	assert_false(zone_02.attack_hitbox.active, "ranged boss does not use the melee hitbox")


func _count_projectiles(parent: Node) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child is EnemyProjectile:
			count += 1
	return count


func _count_summons(parent: Node) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child is Enemy and not child is BossBase:
			count += 1
	return count


# ------------------------------------------------------------------------------
# Boss damage reaches the player (real combat core)
# ------------------------------------------------------------------------------

func test_melee_boss_hits_player_with_phase_damage() -> void:
	_make_floor(800.0)
	var player: Player = _spawn_player(0.0)
	var boss: BossBase = _spawn_boss(BOSS_ZONE_01, 28.0)
	await _wait_frames(2)
	boss.activate_fight()
	var player_hurtbox: Hurtbox = player.get_node("Hurtbox") as Hurtbox

	var frames: int = 0
	while player_hurtbox.hit_count == 0 and frames < 180:
		await get_tree().physics_frame
		frames += 1

	assert_gt(player_hurtbox.hit_count, 0, "melee boss lands its telegraphed cleave")
	assert_not_null(player_hurtbox.last_damage)
	if player_hurtbox.last_damage != null:
		assert_almost_eq(
			player_hurtbox.last_damage.amount,
			boss.data.phases[0].attack_damage,
			0.001,
			"attack damage comes from the phase data"
		)
		assert_gt(
			player_hurtbox.last_damage.knockback.length(),
			0.0,
			"boss hit carries knockback"
		)
	assert_eq(
		player.visual.modulate,
		Damage.FLASH_COLOR,
		"player hit flash starts in the same physics frame (<= 100 ms)"
	)


func test_ranged_boss_projectile_hits_player() -> void:
	_make_floor(800.0)
	var player: Player = _spawn_player(120.0)
	var boss: BossBase = _spawn_boss(BOSS_ZONE_02, 0.0)
	await _wait_frames(2)
	boss.activate_fight()
	var player_hurtbox: Hurtbox = player.get_node("Hurtbox") as Hurtbox

	var frames: int = 0
	while player_hurtbox.hit_count == 0 and frames < 240:
		await get_tree().physics_frame
		frames += 1

	assert_gt(player_hurtbox.hit_count, 0, "ranged boss projectile reaches the player")
	assert_not_null(player_hurtbox.last_damage)
	if player_hurtbox.last_damage != null:
		assert_almost_eq(
			player_hurtbox.last_damage.amount,
			boss.data.phases[0].attack_damage,
			0.001,
			"projectile damage comes from the phase data"
		)
	assert_false(boss.attack_hitbox.active, "ranged boss fires projectiles, not melee")


# ------------------------------------------------------------------------------
# Arena barriers
# ------------------------------------------------------------------------------

func test_arena_closes_exits_during_fight_and_opens_after_victory() -> void:
	var arena: BossArena = _spawn_arena(ARENA_ZONE_01)
	await _wait_frames(2)
	_spawn_player(100.0, 204.0)
	await _wait_frames(4)

	assert_true(arena.is_fight_active(), "entering the arena starts the fight")
	var boss: BossBase = arena.get_boss()
	assert_not_null(boss)
	if boss == null:
		return
	assert_true(boss.fight_active)
	var reward_gold: int = boss.data.reward.gold
	var death_duration: float = boss.balance.boss_death_duration

	var left: StaticBody2D = arena.get_node("BarrierLeft") as StaticBody2D
	var right: StaticBody2D = arena.get_node("BarrierRight") as StaticBody2D
	assert_eq(left.collision_layer, WORLD_LAYER, "left barrier blocks the exit")
	assert_eq(right.collision_layer, WORLD_LAYER, "right barrier blocks the exit")

	# Физическая проверка: тело не может выйти за правый барьер.
	var runner := TestBody.new()
	runner.position = Vector2(430.0, 214.0)
	runner.use_gravity = false
	runner.constant_velocity = Vector2(220.0, 0.0)
	runner.collision_layer = PLAYER_LAYER
	runner.collision_mask = WORLD_LAYER
	var runner_shape := CollisionShape2D.new()
	var runner_rect := RectangleShape2D.new()
	runner_rect.size = Vector2(10.0, 20.0)
	runner_shape.shape = runner_rect
	runner.add_child(runner_shape)
	add_child_autofree(runner)
	await _wait_frames(60)
	assert_lt(runner.position.x, 472.0, "arena barrier physically stops the player")

	boss.hurtbox.receive_damage(Damage.create(99999.0))
	assert_true(boss.is_dead, "lethal damage kills the boss")
	await wait_seconds(death_duration + 0.25)
	await _wait_frames(2)

	assert_true(GameState.is_boss_defeated(&"zone_01_warden"), "defeat flag is stored")
	assert_false(arena.is_fight_active(), "fight ends after death")
	assert_eq(left.collision_layer, 0, "left barrier opens after victory")
	assert_eq(right.collision_layer, 0, "right barrier opens after victory")
	assert_eq(_defeat_events.size(), 1, "boss_defeated is emitted once")
	if _defeat_events.size() == 1:
		assert_eq(_defeat_events[0]["boss_id"], &"zone_01_warden")
		assert_eq(_defeat_events[0]["zone_id"], &"zone_01_village")
	assert_eq(GameState.currency, reward_gold, "reward is granted immediately")
	assert_eq(_reward_events.size(), 1, "reward event reaches HUD/journal")
	if _reward_events.size() == 1:
		assert_eq(_reward_events[0]["reward_id"], &"warden_ember")


# ------------------------------------------------------------------------------
# EC-09: dead boss stays dead, reward on next zone entry
# ------------------------------------------------------------------------------

func test_ec09_boss_stays_dead_and_reward_waits_for_next_entry() -> void:
	var arena: BossArena = _spawn_arena(ARENA_ZONE_01)
	await _wait_frames(2)
	var player: Player = _spawn_player(100.0, 204.0)
	await _wait_frames(4)
	assert_true(arena.is_fight_active())
	var boss: BossBase = arena.get_boss()
	assert_not_null(boss)
	if boss == null:
		return
	var reward_gold: int = boss.data.reward.gold
	var death_duration: float = boss.balance.boss_death_duration

	# Игрок погиб до получения награды.
	player.is_dead = true
	boss.hurtbox.receive_damage(Damage.create(99999.0))
	await wait_seconds(death_duration + 0.25)
	await _wait_frames(2)

	assert_true(GameState.is_boss_defeated(&"zone_01_warden"), "boss remains dead (EC-09)")
	assert_eq(GameState.currency, 0, "reward is not lost, but not granted yet")
	assert_eq(_reward_events.size(), 0, "no reward event while the player is dead")
	var pending: Dictionary = GameState.get_pending_boss_rewards()
	assert_true(pending.has(&"zone_01_warden"), "reward is queued for the zone")
	if pending.has(&"zone_01_warden"):
		var entry: Dictionary = pending[&"zone_01_warden"]
		assert_eq(String(entry["zone_id"]), "zone_01_village")
		assert_eq(int(entry["gold"]), reward_gold)

	# Следующий вход в зону: босс не появляется, награда выдаётся.
	var next_arena: BossArena = _spawn_arena(ARENA_ZONE_01)
	await _wait_frames(2)
	assert_null(next_arena.get_boss(), "defeated boss is not respawned (EC-09)")
	assert_eq(GameState.currency, reward_gold, "reward is granted on the next entry")
	assert_eq(_reward_events.size(), 1, "reward event is emitted on entry")
	assert_true(GameState.get_pending_boss_rewards().is_empty(), "queue is cleared")
	var next_left: StaticBody2D = next_arena.get_node("BarrierLeft") as StaticBody2D
	assert_eq(next_left.collision_layer, 0, "arena is open when the boss is dead")


func test_boss_progress_round_trips_through_save_manager() -> void:
	GameState.mark_boss_defeated(&"zone_01_warden")
	GameState.queue_boss_reward(
		&"zone_02_witch",
		&"zone_02_swamp",
		&"witch_tide",
		160
	)
	GameState.currency = 55

	assert_true(SaveManager.save_slot(1), "slot with boss progress is written")
	var raw_file: FileAccess = FileAccess.open(SaveManager.get_slot_path(1), FileAccess.READ)
	assert_not_null(raw_file)
	if raw_file != null:
		var raw: String = raw_file.get_as_text()
		raw_file.close()
		assert_true(
			raw.begins_with(
				"{\"schema_version\":%d" % SaveMigrations.CURRENT_VERSION
			),
			"boss progress is written with the current schema"
		)

	GameState.reset_boss_progress()
	assert_true(SaveManager.load_slot(1), "slot loads")
	assert_true(
		GameState.is_boss_defeated(&"zone_01_warden"),
		"defeated boss survives a save/load round-trip (EC-09)"
	)
	assert_eq(GameState.currency, 55, "currency is restored")
	var pending: Dictionary = GameState.get_pending_boss_rewards()
	assert_true(pending.has(&"zone_02_witch"), "pending reward survives the round-trip")
	if pending.has(&"zone_02_witch"):
		assert_eq(int(pending[&"zone_02_witch"]["gold"]), 160)


func test_v1_save_is_migrated_with_empty_boss_progress() -> void:
	var migrated: Dictionary = SaveMigrations.migrate(1, {
		"state": {"stamina": 42.0, "weapon_id": "", "weapon_path": ""},
		"meta": {"zone_id": "zone_01_village"},
	})
	assert_true(migrated["ok"], "v1 save is accepted")
	var state: Dictionary = migrated["body"]["state"]
	assert_true(state.has("bosses_defeated"), "v1→v2 adds bosses_defeated")
	assert_true(state.has("boss_rewards_pending"), "v1→v2 adds boss_rewards_pending")
	assert_true(state.has("currency"), "v1→v2 adds currency")
	assert_almost_eq(float(state["stamina"]), 42.0, 0.001, "existing fields are preserved")


# ------------------------------------------------------------------------------
# 60 FPS budget in a long fight
# ------------------------------------------------------------------------------

func test_long_boss_fight_stays_within_60hz_physics_budget() -> void:
	var arena: BossArena = _spawn_arena(ARENA_ZONE_02)
	await _wait_frames(2)
	var player_stub: Player = _spawn_player(100.0, 204.0)
	await _wait_frames(4)
	assert_true(arena.is_fight_active(), "arena starts the ranged boss fight")
	var boss: BossBase = arena.get_boss()
	assert_not_null(boss)
	if boss == null:
		return

	# Длительный бой: несколько фаз и циклов снарядов/вызовов.
	boss.phase_index = 2
	const FRAMES: int = 600
	var samples: Array[float] = []
	samples.resize(FRAMES)
	for index: int in FRAMES:
		await get_tree().physics_frame
		samples[index] = float(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		)

	assert_true(is_instance_valid(boss), "boss survives the long fight")
	assert_true(player_stub.is_inside_tree(), "player survives the long fight")
	var sorted_samples: Array[float] = []
	sorted_samples.assign(samples)
	sorted_samples.sort()
	var p95_index: int = clampi(int(float(FRAMES) * 0.95), 0, FRAMES - 1)
	var p95: float = sorted_samples[p95_index]
	var first_avg: float = _average(samples, 0, 100)
	var last_avg: float = _average(samples, FRAMES - 100, FRAMES)
	print(
		"T-30 e2e FPS budget: p95=%.5f s, first100=%.5f s, last100=%.5f s over %d frames" % [
			p95,
			first_avg,
			last_avg,
			FRAMES,
		]
	)
	assert_lt(
		p95,
		1.0 / 60.0,
		"95th percentile physics time fits the 60 FPS budget (got %.5f s)" % p95
	)
	assert_lt(
		last_avg,
		first_avg * 2.0 + 0.001,
		"no progressive degradation in a long fight (first %.5f, last %.5f)" % [
			first_avg,
			last_avg,
		]
	)


func _average(values: Array[float], from_index: int, to_index: int) -> float:
	var total: float = 0.0
	var count: int = 0
	for index: int in range(from_index, to_index):
		total += values[index]
		count += 1
	return total / float(maxi(count, 1))
