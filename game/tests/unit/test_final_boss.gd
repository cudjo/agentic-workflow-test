extends GutTest
## T-32 — финальный босс, арена финала и концовка по фракции.
##
## Покрывает: данные трёх фаз с нарастающей сложностью (AC-03.4), смену
## паттернов и уведомление HUD, подключение арены T-16 (спавн в `BossSpawn`,
## барьеры, `gate_on_boss_id`), EC-09 при повторном входе, e2e «вход в арену →
## бой 3 фаз → победа → концовка → титры» и зависимость концовки от фракции
## при заглушке `FactionManager` (T-27).

const BOSS_DATA_PATH: String = "res://data/bosses/zone_05_boss.tres"
const ZONE_SCENE: String = "res://world/zones/zone_05_finale/zone_05_finale.tscn"
const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const FINAL_BOSS_ID: StringName = &"zone_05_sovereign"
const FINAL_ZONE_ID: StringName = &"zone_05_finale"
const BOSS_SPAWN: Vector2 = Vector2(360.0, 224.0)
const FLOOR_TOP: float = 224.0
const WORLD_LAYER: int = 1

var _phase_events: Array[Dictionary] = []


func before_each() -> void:
	GameState.reset_boss_progress()
	GameState.reset_stamina()
	GameState.set_in_combat(false)
	_phase_events.clear()
	if not EventBus.boss_phase_changed.is_connected(_on_phase_changed):
		EventBus.boss_phase_changed.connect(_on_phase_changed)


func after_each() -> void:
	if EventBus.boss_phase_changed.is_connected(_on_phase_changed):
		EventBus.boss_phase_changed.disconnect(_on_phase_changed)
	GameState.reset_boss_progress()
	GameState.set_in_combat(false)


func _on_phase_changed(
	_boss_id: StringName,
	phase_index: int,
	phase_title: String
) -> void:
	_phase_events.append({
		"index": phase_index,
		"title": phase_title,
	})


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _spawn_zone() -> ZoneScene:
	var zone := SceneRouter.instantiate_zone(ZONE_SCENE)
	assert_not_null(zone, "SceneRouter instantiates the finale")
	if zone == null:
		return null
	add_child_autofree(zone)
	await wait_physics_frames(2)
	return zone


func _spawn_player(at: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = at
	add_child_autofree(player)
	return player


func _arena_barriers(arena: Node) -> Array[StaticBody2D]:
	var result: Array[StaticBody2D] = []
	for node: Node in get_tree().get_nodes_in_group(&"arena_barrier"):
		if arena.is_ancestor_of(node) and node is StaticBody2D:
			result.append(node as StaticBody2D)
	return result


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
# Data: три фазы, нарастающая сложность (AC-03.4)
# ------------------------------------------------------------------------------

func test_final_boss_data_has_three_increasing_phases() -> void:
	var data := load(BOSS_DATA_PATH) as BossData
	assert_not_null(data, "final boss data loads")
	if data == null:
		return

	assert_true(data.is_valid(), "final BossData is valid")
	assert_eq(data.id, FINAL_BOSS_ID)
	assert_eq(data.zone_id, FINAL_ZONE_ID)
	assert_eq(data.get_phase_count(), 3, "final boss has three phases")
	assert_almost_eq(data.phases[0].hp_threshold_ratio, 1.0, 0.001)
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
	assert_eq(data.get_phase_thresholds().size(), 2, "HUD receives two phase marks")
	assert_eq(data.get_phase_index_for_ratio(1.0), 0)
	assert_eq(data.get_phase_index_for_ratio(0.66), 1)
	assert_eq(data.get_phase_index_for_ratio(0.33), 2)

	assert_eq(data.phases[0].pattern_id, &"ash_cleave")
	assert_eq(data.phases[1].pattern_id, &"pyre_fan")
	assert_eq(data.phases[2].pattern_id, &"last_rites")

	# Нарастающая сложность: урон/скорость растут, пауза и телеграф — короче.
	for index: int in range(1, 3):
		var previous: BossPhaseData = data.phases[index - 1]
		var current: BossPhaseData = data.phases[index]
		assert_gt(
			current.attack_damage,
			previous.attack_damage,
			"phase %d hits harder" % (index + 1)
		)
		assert_gt(
			current.move_speed,
			previous.move_speed,
			"phase %d moves faster" % (index + 1)
		)
		assert_lt(
			current.attack_cooldown,
			previous.attack_cooldown,
			"phase %d attacks more often" % (index + 1)
		)
		assert_lt(
			current.windup,
			previous.windup,
			"phase %d gives a shorter telegraph" % (index + 1)
		)

	assert_eq(data.phases[0].projectile_count, 0, "phase I is pure melee")
	assert_gt(data.phases[1].projectile_count, 0, "phase II adds projectiles")
	assert_gt(
		data.phases[2].projectile_count,
		data.phases[1].projectile_count,
		"phase III widens the fan"
	)
	assert_eq(data.phases[0].summon_count, 0)
	assert_gt(data.phases[2].summon_count, 0, "phase III summons echoes")
	assert_not_null(data.projectile_scene, "projectile scene is wired")
	assert_not_null(data.summon_scene, "summon scene is wired")


# ------------------------------------------------------------------------------
# Scene wiring and phase patterns
# ------------------------------------------------------------------------------

func test_final_boss_scene_uses_boss_base_and_combat_layers() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var arena := zone.get_node_or_null("Arena")
	assert_not_null(arena)
	if arena == null:
		return
	var boss := arena.get(&"boss") as BossBase
	assert_not_null(boss)
	if boss == null:
		return

	assert_true(boss is Zone05Boss, "final boss extends BossBase via Zone05Boss")
	assert_almost_eq(boss.hp, boss.data.max_hp, 0.001, "HP comes from data")
	assert_eq(boss.phase_index, 0, "boss starts in phase I")
	assert_eq(boss.get_phase_count(), 3)
	assert_eq(boss.get_pattern_id(), &"ash_cleave")
	assert_eq(boss.get_phase_mode(), Zone05Boss.MODE_MELEE)
	assert_false(boss.fight_active, "boss waits for the player trigger")
	assert_eq(boss.collision_layer, CombatLayers.ENEMY_BODY)
	assert_eq(boss.collision_mask, CombatLayers.WORLD)
	assert_eq(boss.hurtbox.collision_layer, CombatLayers.ENEMY_HURTBOX)
	assert_eq(boss.attack_hitbox.collision_layer, CombatLayers.ENEMY_HITBOX)
	assert_eq(boss.attack_hitbox.collision_mask, CombatLayers.PLAYER_HURTBOX)


func test_final_boss_phases_switch_patterns_and_notify_hud() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var arena := zone.get_node("Arena")
	var boss := arena.get(&"boss") as BossBase
	_spawn_player(Vector2(72.0, 210.0))
	await wait_physics_frames(4)

	assert_true(bool(arena.call(&"is_fight_active")), "player entry starts the fight")
	var max_hp: float = boss.data.max_hp
	var transition: float = boss.balance.boss_phase_transition_time

	# 100% -> 60%: фаза II, гибридный паттерн.
	boss.hurtbox.receive_damage(Damage.create(max_hp * 0.40))
	assert_eq(boss.phase_index, 1, "HP below 66% switches to phase II")
	assert_eq(boss.get_pattern_id(), &"pyre_fan")
	assert_eq(boss.get_phase_mode(), Zone05Boss.MODE_HYBRID)
	assert_gt(boss.data.phases[1].projectile_count, 0, "phase II is hybrid")
	assert_eq(_phase_events.size(), 1, "HUD is notified about phase II")
	if _phase_events.size() == 1:
		assert_eq(int(_phase_events[0]["index"]), 1)
		assert_eq(String(_phase_events[0]["title"]), "ФАЗА II")

	await wait_seconds(transition + 0.1)

	# 60% -> 30%: фаза III, апокалипсис.
	boss.hurtbox.receive_damage(Damage.create(max_hp * 0.30))
	assert_eq(boss.phase_index, 2, "HP below 33% switches to phase III")
	assert_eq(boss.get_pattern_id(), &"last_rites")
	assert_eq(boss.get_phase_mode(), Zone05Boss.MODE_APOCALYPSE)
	assert_eq(_phase_events.size(), 2, "HUD is notified about phase III")
	if _phase_events.size() == 2:
		assert_eq(int(_phase_events[1]["index"]), 2)
		assert_eq(String(_phase_events[1]["title"]), "ФАЗА III")

	# Паттерны реально разные: II — веер из 3, III — 5 снарядов + 2 призыва.
	boss.phase_index = 1
	boss._perform_attack()
	assert_true(boss.attack_hitbox.active, "phase II still swings its melee hitbox")
	assert_eq(_count_projectiles(arena), 3, "phase II fires a three-bolt fan")

	boss.phase_index = 2
	boss._perform_attack()
	assert_eq(_count_projectiles(arena), 8, "phase III adds five more bolts")
	await wait_physics_frames(1)
	assert_eq(_count_summons(arena), 2, "phase III summons two echoes")


# ------------------------------------------------------------------------------
# Arena + ending e2e: вход → 3 фазы → победа → концовка → титры
# ------------------------------------------------------------------------------

func test_e2e_arena_fight_to_credits() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return

	var arena := zone.get_node("Arena")
	var hook := zone.get_node("EndingExit") as Area2D
	var sequence := zone.get_node("EndingSequence") as EndingSequence
	var boss := arena.get(&"boss") as BossBase
	assert_not_null(boss)
	if boss == null:
		return

	var player := _spawn_player(Vector2(60.0, 210.0))
	await wait_physics_frames(4)

	# Вход в арену: бой начался, выход закрыт, концовка заперта.
	assert_true(bool(arena.call(&"is_fight_active")), "arena fight starts on entry")
	assert_true(GameState.in_combat, "EC-06: save is blocked during the fight")
	for barrier: StaticBody2D in _arena_barriers(arena):
		assert_eq(barrier.collision_layer, WORLD_LAYER, "barrier closes the arena")
	assert_false(bool(hook.call(&"is_unlocked")), "ending is locked during the fight")
	assert_eq(hook.call(&"request_ending"), &"", "locked ending exit rejects requests")

	# Бой: три фазы с нарастающей сложностью, затем победа.
	var max_hp: float = boss.data.max_hp
	var transition: float = boss.balance.boss_phase_transition_time
	var death_duration: float = boss.balance.boss_death_duration

	boss.hurtbox.receive_damage(Damage.create(max_hp * 0.40))
	assert_eq(boss.phase_index, 1)
	await wait_seconds(transition + 0.1)

	boss.hurtbox.receive_damage(Damage.create(max_hp * 0.30))
	assert_eq(boss.phase_index, 2)
	await wait_seconds(transition + 0.1)

	boss.hurtbox.receive_damage(Damage.create(99999.0))
	assert_true(boss.is_dead, "lethal damage kills the final boss")
	await wait_seconds(death_duration + 0.25)
	await wait_physics_frames(2)

	# Победа: EC-09, награда, арена открыта, выход разблокирован.
	assert_true(GameState.is_boss_defeated(FINAL_BOSS_ID), "defeat flag is stored (EC-09)")
	assert_false(bool(arena.call(&"is_fight_active")), "fight is over")
	assert_false(GameState.in_combat, "combat flag is cleared after victory")
	for barrier: StaticBody2D in _arena_barriers(arena):
		assert_eq(barrier.collision_layer, 0, "barrier opens after victory")
	assert_true(bool(hook.call(&"is_unlocked")), "ending unlocks after victory")

	# Финальная последовательность: игрок доходит до выхода -> концовка.
	sequence.fade_duration = 0.05
	player.global_position = hook.global_position
	await wait_physics_frames(4)
	assert_true(bool(hook.call(&"is_requested")), "ending exit triggers once")
	await wait_seconds(0.12)

	assert_true(sequence.is_ending_visible(), "ending screen is shown")
	assert_eq(sequence.get_ending_id(), &"ending_neutral", "stub faction -> neutral ending")
	var ending_screen := sequence.get_ending_screen()
	assert_eq(ending_screen.get_ending_id(), &"ending_neutral")
	assert_true(
		ending_screen.get_body_text().contains("Пепел"),
		"neutral ending text is rendered"
	)

	# Подтверждение -> титры (полный проход до титров).
	sequence.advance()
	await wait_process_frames(1)
	assert_true(sequence.is_credits_visible(), "credits are visible after the ending")
	assert_gt(sequence.get_credits_screen().get_lines_count(), 0, "credits have content")

	sequence.advance()
	await wait_process_frames(1)
	assert_true(sequence.is_finished(), "credits finish the run")


func test_defeated_final_boss_does_not_respawn_on_reentry() -> void:
	GameState.mark_boss_defeated(FINAL_BOSS_ID)
	GameState.queue_boss_reward(FINAL_BOSS_ID, FINAL_ZONE_ID, &"sovereign_crown", 300)

	var zone := await _spawn_zone()
	if zone == null:
		return
	var arena := zone.get_node("Arena")
	var hook := zone.get_node("EndingExit") as Area2D

	assert_true(bool(arena.call(&"is_empty")), "defeated boss is not respawned (EC-09)")
	assert_null(arena.get(&"boss"))
	assert_eq(GameState.currency, 300, "pending reward is claimed on re-entry")
	assert_true(bool(hook.call(&"is_unlocked")), "ending stays unlocked")
	for barrier: StaticBody2D in _arena_barriers(arena):
		assert_eq(barrier.collision_layer, 0, "arena stays open without a fight")


# ------------------------------------------------------------------------------
# Ending depends on the faction (US-06)
# ------------------------------------------------------------------------------

func test_ending_text_depends_on_faction() -> void:
	var neutral := EndingCatalog.resolve(&"")
	var order := EndingCatalog.resolve(&"order", "Орден Пепла")
	var free := EndingCatalog.resolve(&"free", "Вольные Марки")
	var unknown := EndingCatalog.resolve(&"strange_alliance")

	assert_eq(neutral.id, EndingCatalog.NEUTRAL_ID, "stub faction yields neutral ending")
	assert_eq(order.id, &"ending_order")
	assert_eq(free.id, &"ending_free")
	assert_ne(order.id, free.id, "different factions get different ending ids")
	assert_ne(order.title, free.title, "different factions get different titles")
	assert_ne(order.body, free.body, "different factions get different epilogues")
	assert_ne(unknown.id, neutral.id, "unknown faction still changes the ending")
	assert_true(order.faction_line.contains("Орден Пепла"))
	assert_true(
		neutral.faction_line.contains("не выбрана"),
		"neutral ending explains the missing faction choice"
	)


func test_ending_sequence_shows_faction_ending_and_credits() -> void:
	var sequence := EndingSequence.new()
	sequence.fade_duration = 0.0
	add_child_autofree(sequence)
	await wait_process_frames(1)

	assert_true(sequence.play_ending(&"order", "Орден Пепла"))
	assert_true(sequence.is_ending_visible(), "ending appears immediately with zero fade")
	assert_eq(sequence.get_ending_id(), &"ending_order")
	assert_eq(sequence.get_faction_id(), &"order")
	var screen := sequence.get_ending_screen()
	assert_eq(screen.get_faction_id(), &"order")
	assert_true(screen.get_title_text().contains("ОРДЕН"), "title names the faction")

	sequence.advance()
	await wait_process_frames(1)
	assert_true(sequence.is_credits_visible(), "credits follow the faction ending")
	assert_gt(sequence.get_credits_screen().get_lines_count(), 0)

	sequence.advance()
	await wait_process_frames(1)
	assert_true(sequence.is_finished())
