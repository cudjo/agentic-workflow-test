extends GutTest
## T-31 — боссы зон 3 «Горный перевал» и 4 «Руины-храм».
##
## Покрывает: данные трёх фаз с порогами 66/33 (AC-03.4), различимые паттерны
## с telegraph, использование механики зон (камнепад в вертикальных шахтах /
## руны-ловушки на полу), реальный урон через боевое ядро, арены с барьерами,
## награды и EC-09 (босс остаётся мёртвым, отложенная награда — при следующем
## входе), а также бюджет 55 FPS (95-й перцентиль) в длительных боях.

const BOSS_ZONE_03: PackedScene = preload(
	"res://entities/bosses/zone_03/zone_03_boss.tscn"
)
const BOSS_ZONE_04: PackedScene = preload(
	"res://entities/bosses/zone_04/zone_04_boss.tscn"
)
const ARENA_ZONE_03: PackedScene = preload(
	"res://entities/bosses/zone_03/boss_arena_zone_03.tscn"
)
const ARENA_ZONE_04: PackedScene = preload(
	"res://entities/bosses/zone_04/boss_arena_zone_04.tscn"
)
const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const DATA_ZONE_03: String = "res://data/bosses/zone_03_boss.tres"
const DATA_ZONE_04: String = "res://data/bosses/zone_04_boss.tres"
const BOSS_03_ID: StringName = &"zone_03_avalanche"
const BOSS_04_ID: StringName = &"zone_04_seal_warden"
const ZONE_03_ID: StringName = &"zone_03_mountains"
const ZONE_04_ID: StringName = &"zone_04_ruins"
const FLOOR_TOP: float = 0.0
const PLAYER_LAYER: int = 1 << 1
const WORLD_LAYER: int = 1

var _phase_events: Array[Dictionary] = []
var _defeat_events: Array[Dictionary] = []
var _reward_events: Array[Dictionary] = []


class TestBody extends CharacterBody2D:
	var gravity: float = 523.0

	func _physics_process(delta: float) -> void:
		velocity.y += gravity * delta
		move_and_slide()


func before_each() -> void:
	GameState.reset_boss_progress()
	GameState.reset_stamina()
	GameState.set_in_combat(false)
	_phase_events.clear()
	_defeat_events.clear()
	_reward_events.clear()
	_connect_events()


func after_each() -> void:
	_disconnect_events()
	# Зоны опасности — обычные дети арены/теста, GUT их не автофридит:
	# без явной очистки они переживают тест и «догоняют» игрока следующего.
	for child: Node in get_children():
		if child is BossHazard and is_instance_valid(child):
			child.free()
	GameState.reset_boss_progress()
	GameState.set_in_combat(false)


func _connect_events() -> void:
	if not EventBus.boss_phase_changed.is_connected(_on_phase_changed):
		EventBus.boss_phase_changed.connect(_on_phase_changed)
	if not EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.connect(_on_boss_defeated)
	if not EventBus.boss_reward_granted.is_connected(_on_boss_reward):
		EventBus.boss_reward_granted.connect(_on_boss_reward)


func _disconnect_events() -> void:
	if EventBus.boss_phase_changed.is_connected(_on_phase_changed):
		EventBus.boss_phase_changed.disconnect(_on_phase_changed)
	if EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.disconnect(_on_boss_defeated)
	if EventBus.boss_reward_granted.is_connected(_on_boss_reward):
		EventBus.boss_reward_granted.disconnect(_on_boss_reward)


func _on_phase_changed(
	boss_id: StringName,
	phase_index: int,
	phase_title: String
) -> void:
	_phase_events.append({
		"boss_id": boss_id,
		"index": phase_index,
		"title": phase_title,
	})


func _on_boss_defeated(
	boss_id: StringName,
	zone_id: StringName,
	_at_position: Vector2
) -> void:
	_defeat_events.append({"boss_id": boss_id, "zone_id": zone_id})


func _on_boss_reward(boss_id: StringName, reward_id: StringName, gold: int) -> void:
	_reward_events.append({
		"boss_id": boss_id,
		"reward_id": reward_id,
		"gold": gold,
	})


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

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


func _spawn_player_stub(x: float, y: float) -> CharacterBody2D:
	var body := TestBody.new()
	body.name = "PlayerStub"
	body.position = Vector2(x, y)
	body.collision_layer = PLAYER_LAYER
	body.collision_mask = WORLD_LAYER
	body.add_to_group(&"player")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10.0, 20.0)
	shape.shape = rect
	body.add_child(shape)
	add_child_autofree(body)
	return body


func _spawn_arena(scene: PackedScene) -> BossArena:
	var arena: BossArena = scene.instantiate() as BossArena
	add_child_autofree(arena)
	return arena


func _wait_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().physics_frame


func _hazards(parent: Node, kind: int = -1) -> Array[BossHazard]:
	var result: Array[BossHazard] = []
	for child: Node in parent.get_children():
		if child is BossHazard and is_instance_valid(child):
			var hazard := child as BossHazard
			if kind < 0 or int(hazard.kind) == kind:
				result.append(hazard)
	return result


func _count_enemies(parent: Node) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child is Enemy and not child is BossBase and is_instance_valid(child):
			count += 1
	return count


func _p95(samples: Array[float]) -> float:
	var sorted_samples: Array[float] = []
	sorted_samples.assign(samples)
	sorted_samples.sort()
	var index: int = clampi(int(float(samples.size()) * 0.95), 0, samples.size() - 1)
	return sorted_samples[index]


# ------------------------------------------------------------------------------
# Data: 2–3 фазы, пороги, различимые паттерны, telegraph
# ------------------------------------------------------------------------------

func test_boss_data_uses_design_thresholds_and_readable_patterns() -> void:
	var zone_03: BossData = load(DATA_ZONE_03) as BossData
	var zone_04: BossData = load(DATA_ZONE_04) as BossData
	assert_not_null(zone_03, "zone 3 boss data loads")
	assert_not_null(zone_04, "zone 4 boss data loads")
	if zone_03 == null or zone_04 == null:
		return

	assert_true(zone_03.is_valid(), "zone 3 BossData is valid")
	assert_true(zone_04.is_valid(), "zone 4 BossData is valid")
	assert_eq(zone_03.id, BOSS_03_ID)
	assert_eq(zone_04.id, BOSS_04_ID)
	assert_eq(zone_03.zone_id, ZONE_03_ID, "zone 3 boss belongs to the mountain pass")
	assert_eq(zone_04.zone_id, ZONE_04_ID, "zone 4 boss belongs to the ruins")
	assert_ne(zone_03.reward.id, zone_04.reward.id, "rewards are distinct")
	assert_true(zone_03.reward.is_valid())
	assert_true(zone_04.reward.is_valid())

	for data: BossData in [zone_03, zone_04]:
		assert_eq(data.get_phase_count(), 3, "%s has three phases" % data.id)
		assert_almost_eq(data.phases[0].hp_threshold_ratio, 1.0, 0.001)
		assert_almost_eq(
			data.phases[1].hp_threshold_ratio,
			BossData.PHASE_TWO_THRESHOLD,
			0.001,
			"phase II starts at 66%"
		)
		assert_almost_eq(
			data.phases[2].hp_threshold_ratio,
			BossData.PHASE_THREE_THRESHOLD,
			0.001,
			"phase III starts at 33%"
		)
		assert_eq(data.get_phase_index_for_ratio(0.67), 0)
		assert_eq(data.get_phase_index_for_ratio(0.66), 1)
		assert_eq(data.get_phase_index_for_ratio(0.34), 1)
		assert_eq(data.get_phase_index_for_ratio(0.33), 2)
		assert_eq(data.get_phase_thresholds().size(), 2, "HUD receives two marks")

		var patterns: Array[StringName] = []
		for phase: BossPhaseData in data.phases:
			assert_false(patterns.has(phase.pattern_id), "patterns are unique")
			patterns.append(phase.pattern_id)
			# Читаемый telegraph: у замаха всегда есть окно предупреждения.
			assert_gte(phase.windup, 0.3, "%s gives the player time to react" % phase.pattern_id)
		assert_false(patterns[0].is_empty())
		assert_false(patterns[1].is_empty())
		assert_false(patterns[2].is_empty())

		# Фаза I — чистый ближний бой; окружение включается со II фазы.
		assert_eq(data.phases[0].hazard_count, 0)
		assert_gt(data.phases[1].hazard_count, 0, "phase II uses the zone mechanic")
		assert_gt(
			data.phases[2].hazard_count,
			data.phases[1].hazard_count,
			"phase III covers more of the zone"
		)
		for index: int in range(1, 3):
			var phase: BossPhaseData = data.phases[index]
			assert_gte(
				phase.hazard_telegraph,
				0.3,
				"hazard telegraph is readable (>= 0.3 s)"
			)
			assert_gt(phase.hazard_active, 0.0)
			assert_gt(phase.hazard_damage, 0.0, "hazard deals damage")
			assert_gt(phase.attack_damage, data.phases[index - 1].attack_damage)
			assert_gt(phase.move_speed, data.phases[index - 1].move_speed)
			assert_lt(phase.attack_cooldown, data.phases[index - 1].attack_cooldown)

	assert_eq(zone_03.phases[0].pattern_id, &"glacier_cleave")
	assert_eq(zone_03.phases[1].pattern_id, &"rockslide")
	assert_eq(zone_03.phases[2].pattern_id, &"avalanche")
	assert_eq(zone_04.phases[0].pattern_id, &"seal_cleave")
	assert_eq(zone_04.phases[1].pattern_id, &"trap_ritual")
	assert_eq(zone_04.phases[2].pattern_id, &"seal_break")
	assert_not_null(zone_04.summon_scene, "phase III summons temple echoes")
	assert_null(zone_03.projectile_scene, "mountain boss uses the environment, not projectiles")


func test_boss_scenes_use_base_and_combat_layers() -> void:
	_make_floor(1200.0)
	var boss_03: BossBase = _spawn_boss(BOSS_ZONE_03, -100.0)
	var boss_04: BossBase = _spawn_boss(BOSS_ZONE_04, 100.0)
	await _wait_frames(2)

	assert_true(boss_03 is Zone03Boss)
	assert_true(boss_04 is Zone04Boss)
	for boss: BossBase in [boss_03, boss_04]:
		assert_not_null(boss.data)
		assert_almost_eq(boss.hp, boss.data.max_hp, 0.001, "HP comes from data")
		assert_eq(boss.phase_index, 0, "boss starts in phase I")
		assert_eq(boss.get_phase_count(), 3)
		assert_false(boss.fight_active, "boss waits for the arena trigger")
		assert_true(boss.is_in_group(&"bosses"))
		assert_eq(boss.collision_layer, CombatLayers.ENEMY_BODY)
		assert_eq(boss.collision_mask, CombatLayers.WORLD)
		assert_eq(boss.hurtbox.collision_layer, CombatLayers.ENEMY_HURTBOX)
		assert_eq(boss.hurtbox.collision_mask, 0)
		assert_eq(boss.attack_hitbox.collision_layer, CombatLayers.ENEMY_HITBOX)
		assert_eq(boss.attack_hitbox.collision_mask, CombatLayers.PLAYER_HURTBOX)
		assert_eq(boss.get_pattern_id(), boss.data.phases[0].pattern_id)

	assert_eq((boss_03 as Zone03Boss).get_phase_mode(), Zone03Boss.MODE_GLACIER)
	assert_eq((boss_04 as Zone04Boss).get_phase_mode(), Zone04Boss.MODE_SEAL)


# ------------------------------------------------------------------------------
# Phase switch (AC-03.4)
# ------------------------------------------------------------------------------

func test_phase_switch_notifies_hud_and_changes_pattern() -> void:
	_make_floor(900.0)
	var players: Array[Player] = [_spawn_player(100.0), _spawn_player(-100.0)]
	var bosses: Array[BossBase] = [
		_spawn_boss(BOSS_ZONE_03, 0.0),
		_spawn_boss(BOSS_ZONE_04, -250.0),
	]
	await _wait_frames(2)
	assert_eq(players.size(), 2)
	for boss: BossBase in bosses:
		assert_true(boss.activate_fight())

	var boss_03: BossBase = bosses[0]
	var boss_04: BossBase = bosses[1]
	var first_pattern_03: StringName = boss_03.get_pattern_id()
	var first_pattern_04: StringName = boss_04.get_pattern_id()
	var transition: float = boss_03.balance.boss_phase_transition_time

	boss_03.hurtbox.receive_damage(Damage.create(boss_03.data.max_hp * 0.4))
	boss_04.hurtbox.receive_damage(Damage.create(boss_04.data.max_hp * 0.4))
	assert_eq(boss_03.phase_index, 1, "zone 3 switches to phase II below 66%")
	assert_eq(boss_04.phase_index, 1, "zone 4 switches to phase II below 66%")
	assert_ne(boss_03.get_pattern_id(), first_pattern_03, "zone 3 changes pattern")
	assert_ne(boss_04.get_pattern_id(), first_pattern_04, "zone 4 changes pattern")
	assert_eq((boss_03 as Zone03Boss).get_phase_mode(), Zone03Boss.MODE_ROCKSLIDE)
	assert_eq((boss_04 as Zone04Boss).get_phase_mode(), Zone04Boss.MODE_TRAPS)
	assert_eq(_phase_events.size(), 2, "HUD is notified for both bosses")
	var notified: Array[StringName] = []
	for event: Dictionary in _phase_events:
		notified.append(StringName(event["boss_id"]))
		assert_eq(int(event["index"]), 1)
		assert_eq(String(event["title"]), "ФАЗА II")
	assert_true(notified.has(BOSS_03_ID))
	assert_true(notified.has(BOSS_04_ID))
	assert_true(boss_03.hurtbox.invulnerable, "phase transition gives i-frames")
	assert_true(boss_04.hurtbox.invulnerable)

	await wait_seconds(transition + 0.1)
	boss_03.hurtbox.receive_damage(Damage.create(boss_03.data.max_hp * 0.3))
	boss_04.hurtbox.receive_damage(Damage.create(boss_04.data.max_hp * 0.3))
	assert_eq(boss_03.phase_index, 2, "zone 3 switches to phase III below 33%")
	assert_eq(boss_04.phase_index, 2, "zone 4 switches to phase III below 33%")
	assert_eq((boss_03 as Zone03Boss).get_phase_mode(), Zone03Boss.MODE_AVALANCHE)
	assert_eq((boss_04 as Zone04Boss).get_phase_mode(), Zone04Boss.MODE_BREAK)
	assert_eq(_phase_events.size(), 4, "each phase change reaches the HUD")


# ------------------------------------------------------------------------------
# Zone 3: rockfall in the vertical shafts
# ------------------------------------------------------------------------------

func test_zone_03_rockslide_uses_vertical_shafts_with_telegraph() -> void:
	_make_floor(900.0)
	var player: Player = _spawn_player(144.0)
	var boss: Zone03Boss = _spawn_boss(BOSS_ZONE_03, 0.0) as Zone03Boss
	await _wait_frames(2)
	assert_true(boss.activate_fight())
	# Даём боссу встать на пол: иначе колонны/пол «плывут» вместе с падением.
	await _wait_frames(20)
	var expected_floor: float = boss._arena_floor_y()
	var phase: BossPhaseData = boss.data.phases[1]
	boss.phase_index = 1
	boss._perform_attack()
	await _wait_frames(1)

	var hazards: Array[BossHazard] = _hazards(boss.get_parent(), BossHazard.Kind.FALLING_ROCK)
	assert_eq(hazards.size(), phase.hazard_count, "rockslide spawns one rock per shaft")
	var expected_columns: Array[float] = boss.get_hazard_columns(phase.hazard_count)
	assert_eq(expected_columns.size(), phase.hazard_count)
	var seen_columns: Array[float] = []
	for hazard: BossHazard in hazards:
		assert_eq(hazard.kind, BossHazard.Kind.FALLING_ROCK)
		assert_true(hazard.is_telegraphing(), "rock shows a warning before falling")
		assert_false(hazard.is_dangerous(), "no damage during the telegraph")
		assert_gt(hazard.get_fall_distance(), 40.0, "rock falls down a vertical shaft")
		assert_almost_eq(hazard.target_y, expected_floor, 0.01, "rock targets the floor")
		seen_columns.append(hazard.global_position.x)
	for column: float in expected_columns:
		assert_true(
			_has_close_value(seen_columns, column),
			"rock column %.1f matches a shaft column" % column
		)
	assert_true(boss.attack_hitbox.active, "the melee swing still happens during the rockfall")

	# Игрок встаёт в колонну шахты — так проверяем именно урон камнепада.
	if not hazards.is_empty():
		player.global_position = Vector2(hazards[0].global_position.x, -10.0)
	var player_hurtbox: Hurtbox = player.get_node("Hurtbox") as Hurtbox
	await wait_seconds(0.25)
	assert_eq(player_hurtbox.hit_count, 0, "warning is not a hit")
	for hazard: BossHazard in hazards:
		if is_instance_valid(hazard):
			assert_true(hazard.is_telegraphing() or hazard.is_dangerous())

	# Камень падает ~0.7 s после telegraph — ждём полного пролёта шахты.
	await wait_seconds(phase.hazard_telegraph + 0.85)
	assert_gt(player_hurtbox.hit_count, 0, "falling rock hits the player in the shaft")
	assert_not_null(player_hurtbox.last_damage)
	if player_hurtbox.last_damage != null:
		assert_almost_eq(
			player_hurtbox.last_damage.amount,
			phase.hazard_damage,
			0.01,
			"rock damage comes from the phase data"
		)
		assert_gt(
			player_hurtbox.last_damage.knockback.y,
			0.0,
			"falling rock knocks the player down"
		)

	boss.hurtbox.receive_damage(Damage.create(99999.0))
	await _wait_frames(2)
	assert_true(boss.is_dead)
	assert_true(
		_hazards(boss.get_parent(), BossHazard.Kind.FALLING_ROCK).is_empty(),
		"hazards are cleared when the boss dies"
	)


func test_zone_03_avalanche_covers_all_shafts() -> void:
	_make_floor(900.0)
	var boss: Zone03Boss = _spawn_boss(BOSS_ZONE_03, 0.0) as Zone03Boss
	await _wait_frames(2)
	boss.activate_fight()
	boss.phase_index = 2
	boss._perform_attack()
	await _wait_frames(1)

	var phase: BossPhaseData = boss.data.phases[2]
	var hazards: Array[BossHazard] = _hazards(boss.get_parent(), BossHazard.Kind.FALLING_ROCK)
	assert_eq(hazards.size(), phase.hazard_count, "avalanche fills the whole pass")
	assert_eq(hazards.size(), boss.shaft_offsets.size(), "every shaft column is used")
	assert_lt(
		phase.hazard_telegraph,
		boss.data.phases[1].hazard_telegraph,
		"phase III gives a tighter but still readable window"
	)
	var xs: Array[float] = []
	for hazard: BossHazard in hazards:
		assert_true(hazard.is_telegraphing())
		xs.append(hazard.global_position.x)
	xs.sort()
	for index: int in range(1, xs.size()):
		assert_gt(xs[index] - xs[index - 1], 1.0, "rocks fall in separate columns")


func test_hazard_telegraph_respects_no_flash_mode() -> void:
	_make_floor(900.0)
	var boss: Zone03Boss = _spawn_boss(BOSS_ZONE_03, 0.0) as Zone03Boss
	await _wait_frames(2)
	boss.activate_fight()
	await _wait_frames(20)
	boss.phase_index = 1
	boss._perform_attack()
	await _wait_frames(1)

	var hazards: Array[BossHazard] = _hazards(boss.get_parent())
	assert_gt(hazards.size(), 0, "hazards exist for the accessibility check")
	var original_no_flash: bool = Config.no_flash
	Config.no_flash = true
	await _wait_frames(2)
	for hazard: BossHazard in hazards:
		if is_instance_valid(hazard):
			assert_almost_eq(
				hazard.get_warning_alpha(),
				0.7,
				0.001,
				"no-flash mode keeps the telegraph steady, not blinking"
			)
	Config.no_flash = original_no_flash


# ------------------------------------------------------------------------------
# Zone 4: rune traps and the seal break
# ------------------------------------------------------------------------------

func test_zone_04_trap_ritual_burns_runes_on_the_floor() -> void:
	_make_floor(900.0)
	var player: Player = _spawn_player(156.0)
	var boss: Zone04Boss = _spawn_boss(BOSS_ZONE_04, 0.0) as Zone04Boss
	await _wait_frames(2)
	assert_true(boss.activate_fight())
	await _wait_frames(20)
	var phase: BossPhaseData = boss.data.phases[1]
	boss.phase_index = 1
	boss._perform_attack()
	await _wait_frames(1)

	var hazards: Array[BossHazard] = _hazards(boss.get_parent(), BossHazard.Kind.SPIKE_TRAP)
	assert_eq(hazards.size(), phase.hazard_count, "ritual lights one rune per trap")
	var expected_columns: Array[float] = boss.get_trap_columns(phase.hazard_count)
	for hazard: BossHazard in hazards:
		assert_eq(hazard.kind, BossHazard.Kind.SPIKE_TRAP)
		assert_true(hazard.is_telegraphing(), "rune warns before the spikes")
		assert_false(hazard.is_dangerous(), "no damage during the telegraph")
		assert_almost_eq(
			hazard.global_position.y + hazard.hazard_size.y * 0.5,
			hazard.target_y,
			0.01,
			"rune sits on the floor"
		)
	var seen_columns: Array[float] = []
	for hazard: BossHazard in hazards:
		seen_columns.append(hazard.global_position.x)
	for column: float in expected_columns:
		assert_true(_has_close_value(seen_columns, column), "trap column %.1f" % column)

	# Игрок встаёт на руну — проверяем урон ловушки, а не случайное попадание.
	if not hazards.is_empty():
		player.global_position = Vector2(hazards[0].global_position.x, -10.0)
	var player_hurtbox: Hurtbox = player.get_node("Hurtbox") as Hurtbox
	await wait_seconds(0.25)
	assert_eq(player_hurtbox.hit_count, 0, "telegraph does not damage the player")
	await wait_seconds(phase.hazard_telegraph + 0.1)
	assert_gt(player_hurtbox.hit_count, 0, "spikes hit the player standing on the rune")
	assert_not_null(player_hurtbox.last_damage)
	if player_hurtbox.last_damage != null:
		assert_almost_eq(
			player_hurtbox.last_damage.amount,
			phase.hazard_damage,
			0.01,
			"trap damage comes from the phase data"
		)
		assert_lt(
			player_hurtbox.last_damage.knockback.y,
			0.0,
			"floor trap knocks the player upwards"
		)
	await wait_seconds(phase.hazard_active + 0.15)
	assert_true(boss.get_active_hazards().is_empty(), "spent runes disappear")


func test_zone_04_seal_break_adds_traps_and_summons() -> void:
	_make_floor(900.0)
	var container := Node2D.new()
	container.name = "RuinsArenaRoot"
	add_child_autofree(container)
	_spawn_player(100.0)
	var boss: Zone04Boss = _spawn_boss(BOSS_ZONE_04, 0.0, container) as Zone04Boss
	await _wait_frames(2)
	boss.activate_fight()
	boss.phase_index = 2
	boss._perform_attack()
	await _wait_frames(1)

	var phase: BossPhaseData = boss.data.phases[2]
	var traps: Array[BossHazard] = _hazards(container, BossHazard.Kind.SPIKE_TRAP)
	assert_eq(traps.size(), phase.hazard_count, "phase III floods the hall with runes")
	for trap: BossHazard in traps:
		assert_true(trap.is_telegraphing(), "runes remain readable on the last phase")
	assert_eq(
		_count_enemies(container),
		phase.summon_count,
		"seal break summons temple echoes"
	)
	assert_true(boss.attack_hitbox.active, "the warden still swings while the seal breaks")


# ------------------------------------------------------------------------------
# Arenas: barriers, reward, EC-09
# ------------------------------------------------------------------------------

func test_zone_03_arena_closes_exits_rewards_and_keeps_boss_dead() -> void:
	var arena: BossArena = _spawn_arena(ARENA_ZONE_03)
	await _wait_frames(2)
	var player: Player = _spawn_player(100.0, 204.0)
	await _wait_frames(4)

	assert_true(arena.is_fight_active(), "entering the mountain arena starts the fight")
	var boss: BossBase = arena.get_boss()
	assert_not_null(boss)
	if boss == null or player == null:
		return
	assert_true(boss.fight_active)
	var reward_gold: int = boss.data.reward.gold
	var death_duration: float = boss.balance.boss_death_duration
	var left: StaticBody2D = arena.get_node("BarrierLeft") as StaticBody2D
	var right: StaticBody2D = arena.get_node("BarrierRight") as StaticBody2D
	assert_eq(left.collision_layer, WORLD_LAYER)
	assert_eq(right.collision_layer, WORLD_LAYER)

	boss.hurtbox.receive_damage(Damage.create(99999.0))
	await wait_seconds(death_duration + 0.25)
	await _wait_frames(2)

	assert_true(GameState.is_boss_defeated(BOSS_03_ID), "defeat flag is stored (EC-09)")
	assert_false(arena.is_fight_active())
	assert_eq(left.collision_layer, 0, "arena opens after victory")
	assert_eq(right.collision_layer, 0)
	assert_eq(GameState.currency, reward_gold, "reward is granted immediately")
	assert_eq(_defeat_events.size(), 1)
	if _defeat_events.size() == 1:
		assert_eq(_defeat_events[0]["boss_id"], BOSS_03_ID)
		assert_eq(_defeat_events[0]["zone_id"], ZONE_03_ID)
	assert_eq(_reward_events.size(), 1)
	if _reward_events.size() == 1:
		assert_eq(_reward_events[0]["reward_id"], &"avalanche_core")

	var next_arena: BossArena = _spawn_arena(ARENA_ZONE_03)
	await _wait_frames(2)
	assert_null(next_arena.get_boss(), "defeated boss does not respawn (EC-09)")
	assert_eq(GameState.currency, reward_gold, "reward is not granted twice")
	var next_left: StaticBody2D = next_arena.get_node("BarrierLeft") as StaticBody2D
	assert_eq(next_left.collision_layer, 0, "arena stays open without a boss")


func test_zone_04_reward_waits_for_next_entry_after_death() -> void:
	var arena: BossArena = _spawn_arena(ARENA_ZONE_04)
	await _wait_frames(2)
	var player: Player = _spawn_player(100.0, 204.0)
	await _wait_frames(4)
	assert_true(arena.is_fight_active(), "entering the ruins arena starts the fight")
	var boss: BossBase = arena.get_boss()
	assert_not_null(boss)
	if boss == null:
		return
	var reward_gold: int = boss.data.reward.gold
	var death_duration: float = boss.balance.boss_death_duration

	# Игрок погиб до получения награды (EC-09).
	player.is_dead = true
	boss.hurtbox.receive_damage(Damage.create(99999.0))
	await wait_seconds(death_duration + 0.25)
	await _wait_frames(2)

	assert_true(GameState.is_boss_defeated(BOSS_04_ID), "boss remains dead")
	assert_eq(GameState.currency, 0, "reward is not lost, but not granted yet")
	assert_eq(_reward_events.size(), 0, "no reward while the player is dead")
	var pending: Dictionary = GameState.get_pending_boss_rewards()
	assert_true(pending.has(BOSS_04_ID), "reward waits in the queue")
	if pending.has(BOSS_04_ID):
		assert_eq(String(pending[BOSS_04_ID]["zone_id"]), "zone_04_ruins")
		assert_eq(int(pending[BOSS_04_ID]["gold"]), reward_gold)

	var next_arena: BossArena = _spawn_arena(ARENA_ZONE_04)
	await _wait_frames(2)
	assert_null(next_arena.get_boss(), "the seal warden is not respawned")
	assert_eq(GameState.currency, reward_gold, "reward is granted on the next entry")
	assert_eq(_reward_events.size(), 1)
	if _reward_events.size() == 1:
		assert_eq(_reward_events[0]["reward_id"], &"seal_shard")
	assert_true(GameState.get_pending_boss_rewards().is_empty())
	var next_left: StaticBody2D = next_arena.get_node("BarrierLeft") as StaticBody2D
	assert_eq(next_left.collision_layer, 0, "ruins arena opens after victory")


# ------------------------------------------------------------------------------
# e2e performance: 95th percentile above 55 FPS
# ------------------------------------------------------------------------------

func test_zone_03_fight_holds_55fps_p95() -> void:
	var arena: BossArena = _spawn_arena(ARENA_ZONE_03)
	await _wait_frames(2)
	_spawn_player_stub(100.0, 204.0)
	await _wait_frames(4)
	assert_true(arena.is_fight_active(), "arena is live for the performance run")
	var boss: BossBase = arena.get_boss()
	assert_not_null(boss)
	if boss == null:
		return
	boss.phase_index = 2

	const FRAMES: int = 360
	var samples: Array[float] = []
	samples.resize(FRAMES)
	for index: int in FRAMES:
		if index % 40 == 0:
			boss._perform_attack()
		await get_tree().physics_frame
		samples[index] = float(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		)

	var p95: float = _p95(samples)
	print("T-31 zone 3 e2e: p95=%.5f s over %d frames" % [p95, FRAMES])
	assert_true(is_instance_valid(boss), "mountain boss survives the long fight")
	assert_lt(
		p95,
		1.0 / 55.0,
		"zone 3 p95 stays above 55 FPS (got %.5f s)" % p95
	)


func test_zone_04_fight_holds_55fps_p95() -> void:
	var arena: BossArena = _spawn_arena(ARENA_ZONE_04)
	await _wait_frames(2)
	_spawn_player_stub(100.0, 204.0)
	await _wait_frames(4)
	assert_true(arena.is_fight_active(), "arena is live for the performance run")
	var boss: BossBase = arena.get_boss()
	assert_not_null(boss)
	if boss == null:
		return
	boss.phase_index = 2

	const FRAMES: int = 360
	var samples: Array[float] = []
	samples.resize(FRAMES)
	for index: int in FRAMES:
		if index % 60 == 0:
			boss._perform_attack()
		await get_tree().physics_frame
		samples[index] = float(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		)

	var p95: float = _p95(samples)
	print("T-31 zone 4 e2e: p95=%.5f s over %d frames" % [p95, FRAMES])
	assert_true(is_instance_valid(boss), "ruins boss survives the long fight")
	assert_lt(
		p95,
		1.0 / 55.0,
		"zone 4 p95 stays above 55 FPS (got %.5f s)" % p95
	)


func _has_close_value(values: Array[float], target: float) -> bool:
	# Босс продолжает сближаться с игроком, поэтому колонна могла сместиться
	# на доли пикселя между спавном камней и проверкой.
	for value: float in values:
		if absf(value - target) <= 2.0:
			return true
	return false
