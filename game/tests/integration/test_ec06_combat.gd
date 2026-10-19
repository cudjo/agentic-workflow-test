extends GutTest
## Fix-4b — блокеры финального ревью Guardian:
##   * B-03: producer `GameState.in_combat` от обычных врагов (агро/бой,
##     refcount на нескольких врагов) и сброс после смерти на арене;
##     EC-06 реально блокирует сохранение у костра и интерактивы;
##   * MINOR-06: i-frames переката/рывка гасят knockback и вспышку.
##
## Сценарии — на настоящих сценах Player/Enemy/Zone05Arena при 60 Hz physics.

const SWIFT_SCENE: PackedScene = preload("res://entities/enemies/swift/swift_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const ZONE_SCENE: String = "res://world/zones/zone_05_finale/zone_05_finale.tscn"
const TEST_DIR: String = "user://test_ec06_fix4b"
const WORLD_LAYER: int = 1
const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]

var _saves_dir: String = SaveManager.DEFAULT_SAVES_DIR
var _save_failures: Array[Dictionary] = []


func before_all() -> void:
	_saves_dir = SaveManager.saves_dir
	SaveManager.saves_dir = TEST_DIR


func after_all() -> void:
	SaveManager.saves_dir = _saves_dir
	_cleanup_dir()


func before_each() -> void:
	GameState.reset_combat_state()
	GameState.reset_boss_progress()
	GameState.reset_stamina()
	GameState.set_hp(GameState.hp_max)
	_reset_input()
	_save_failures.clear()
	if not EventBus.save_failed.is_connected(_on_save_failed):
		EventBus.save_failed.connect(_on_save_failed)


func after_each() -> void:
	if EventBus.save_failed.is_connected(_on_save_failed):
		EventBus.save_failed.disconnect(_on_save_failed)
	GameState.reset_combat_state()
	GameState.reset_boss_progress()
	_reset_input()


func _on_save_failed(slot: int, reason: String) -> void:
	_save_failures.append({"slot": slot, "reason": reason})


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


func _spawn_enemy(x: float) -> Enemy:
	var enemy: Enemy = SWIFT_SCENE.instantiate() as Enemy
	enemy.position = Vector2(x, -10.0)
	add_child_autofree(enemy)
	return enemy


func _spawn_bonfire() -> Bonfire:
	var bonfire := Bonfire.new()
	bonfire.name = "TestBonfire"
	bonfire.bonfire_id = &"test_bonfire"
	bonfire.zone_id = &"zone_test"
	add_child_autofree(bonfire)
	return bonfire


func _wait_for_state(enemy: Enemy, expected: StringName, frames: int = 60) -> bool:
	for _i: int in frames:
		if enemy.get_state_name() == expected:
			return true
		await get_tree().physics_frame
	return enemy.get_state_name() == expected


func _spawn_zone() -> ZoneScene:
	var zone := SceneRouter.instantiate_zone(ZONE_SCENE)
	assert_not_null(zone, "SceneRouter instantiates the finale")
	if zone == null:
		return null
	add_child_autofree(zone)
	await wait_physics_frames(2)
	return zone


func _spawn_arena_player(zone: ZoneScene) -> Player:
	var player := _spawn_player(60.0)
	player.global_position = Vector2(60.0, 210.0)
	return player


func _wait_for_fight(arena: Node, frames: int = 30) -> bool:
	for _i: int in frames:
		if bool(arena.call(&"is_fight_active")):
			return true
		await get_tree().physics_frame
	return bool(arena.call(&"is_fight_active"))


func _arena_barriers(arena: Node) -> Array[StaticBody2D]:
	var result: Array[StaticBody2D] = []
	for node: Node in get_tree().get_nodes_in_group(&"arena_barrier"):
		if arena.is_ancestor_of(node) and node is StaticBody2D:
			result.append(node as StaticBody2D)
	return result


func _cleanup_dir() -> void:
	var directory: DirAccess = DirAccess.open(TEST_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for dir_name: String in directory.get_directories():
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(TEST_DIR.path_join(dir_name))
		)


# ------------------------------------------------------------------------------
# B-03: producer in_combat от обычных врагов
# ------------------------------------------------------------------------------

func test_enemy_aggro_blocks_bonfire_save_and_interaction() -> void:
	_make_floor(400.0)
	var player := _spawn_player(0.0)
	var enemy := _spawn_enemy(60.0)
	var bonfire := _spawn_bonfire()

	assert_true(await _wait_for_state(enemy, &"chase"), "enemy aggroes the player")
	assert_true(GameState.in_combat, "EC-06: regular enemy aggro raises in_combat")
	assert_true(GameState.is_combat_source_active(enemy), "enemy registers as combat source")

	assert_false(bonfire.can_save(), "bonfire sees combat and blocks saving")
	assert_false(bonfire.save_to_slot(1), "save_to_slot is rejected in combat")
	assert_eq(_save_failures.size(), 1, "save_failed is emitted")
	if _save_failures.size() == 1:
		assert_eq(_save_failures[0]["reason"], "in_combat")
		assert_eq(_save_failures[0]["slot"], 1)
		assert_false(
			SaveManager.has_slot(1),
			"no slot file is written in combat (EC-06)"
		)

	var interaction := player.get_node("Interaction") as PlayerInteraction
	assert_not_null(interaction, "PlayerInteraction is mounted on the player")
	if interaction != null:
		assert_false(interaction.can_interact(), "interaction is blocked in combat")


func test_multiple_aggressors_keep_combat_until_last_one_leaves() -> void:
	_make_floor(500.0)
	var _player := _spawn_player(0.0)
	var first := _spawn_enemy(60.0)
	var second := _spawn_enemy(-60.0)

	assert_true(await _wait_for_state(first, &"chase"), "first enemy aggroes")
	assert_true(await _wait_for_state(second, &"chase"), "second enemy aggroes")
	assert_true(GameState.in_combat, "two aggressors keep combat active")

	first.hurtbox.receive_damage(Damage.create(999.0))
	await wait_physics_frames(1)
	assert_true(first.is_dead, "first enemy is dead")
	assert_false(
		GameState.is_combat_source_active(first),
		"dead enemy releases its combat source"
	)
	assert_true(
		GameState.in_combat,
		"combat stays active while the second aggressor is alive"
	)

	second.hurtbox.receive_damage(Damage.create(999.0))
	await wait_physics_frames(1)
	assert_false(
		GameState.in_combat,
		"combat ends only after the last aggressor is gone"
	)


# ------------------------------------------------------------------------------
# B-03: смерть на арене сбрасывает бой и открывает барьеры
# ------------------------------------------------------------------------------

func test_player_death_in_final_arena_clears_combat_and_opens_barriers() -> void:
	var zone := await _spawn_zone()
	if zone == null:
		return
	var arena := zone.get_node("Arena")
	var _player := _spawn_arena_player(zone)
	assert_true(await _wait_for_fight(arena), "entry starts the final fight")
	assert_true(GameState.in_combat, "fight raises in_combat")
	assert_true(bool(arena.call(&"are_barriers_closed")), "barriers are closed in combat")

	# Смерть игрока (контракт DeathHandler): арена обязана прервать бой.
	EventBus.player_died.emit()
	await wait_physics_frames(2)

	assert_false(GameState.in_combat, "death clears in_combat (B-03)")
	assert_false(bool(arena.call(&"is_fight_active")), "arena fight is aborted")
	var boss := arena.get(&"boss") as BossBase
	assert_not_null(boss, "final boss exists")
	if boss != null:
		assert_false(boss.fight_active, "boss fight is aborted on player death")
	assert_false(bool(arena.call(&"are_barriers_closed")), "barriers are open")
	for barrier: StaticBody2D in _arena_barriers(arena):
		assert_eq(barrier.collision_layer, 0, "barrier collision layer is cleared")

	var bonfire := _spawn_bonfire()
	assert_true(bonfire.can_save(), "saving is available after death on the arena")
	assert_true(GameState.can_save(), "GameState allows saving after death")
	assert_true(bonfire.save_to_slot(1), "save actually writes after death")
	assert_true(SaveManager.has_slot(1), "slot file exists after the save")


func test_leaving_zone_05_in_combat_clears_flag() -> void:
	var zone := SceneRouter.instantiate_zone(ZONE_SCENE)
	assert_not_null(zone)
	if zone == null:
		return
	add_child(zone)
	await wait_physics_frames(2)
	var arena := zone.get_node("Arena")
	var _player := _spawn_arena_player(zone)
	assert_true(await _wait_for_fight(arena), "fight is active before leaving")
	assert_true(GameState.in_combat, "in_combat is set during the fight")

	zone.queue_free()
	await wait_physics_frames(2)
	assert_false(GameState.in_combat, "Zone05Arena._exit_tree clears in_combat (B-03)")


# ------------------------------------------------------------------------------
# MINOR-06: i-frames гасят knockback/flash
# ------------------------------------------------------------------------------

func test_roll_iframes_suppress_knockback_and_flash() -> void:
	_make_floor(400.0)
	var player := _spawn_player(0.0)
	await wait_physics_frames(6)
	GameState.set_hp(GameState.hp_max)

	player.state_machine.force_state(&"roll")
	for _i: int in 24:
		if player.is_invulnerable():
			break
		await get_tree().physics_frame
	assert_true(player.is_invulnerable(), "roll reaches its i-frame window")

	var hp_before: float = GameState.hp
	var velocity_before: Vector2 = player.velocity
	var hurtbox := player.get_node("Hurtbox") as Hurtbox
	assert_not_null(hurtbox, "player has a hurtbox")
	if hurtbox == null:
		return
	var flash_before: int = hurtbox.flash_applied_count
	var damage := Damage.create(5.0, Vector2(80.0, 0.0), 0.1)
	assert_false(
		hurtbox.receive_damage(damage),
		"roll i-frames reject the hit at the hurtbox level"
	)
	assert_almost_eq(GameState.hp, hp_before, 0.001, "no HP loss during i-frames")
	assert_almost_eq(player.velocity.x, velocity_before.x, 0.001, "no knockback in i-frames")
	assert_eq(hurtbox.flash_applied_count, flash_before, "no flash in i-frames")
	assert_ne(player.visual.modulate, Damage.FLASH_COLOR, "sprite is not flashed")

	# Вне i-frames та же реакция применяется — гейт не «глушит» урон навсегда.
	await wait_physics_frames(30)
	assert_false(player.is_invulnerable(), "roll i-frames are over")
	player.velocity = Vector2.ZERO
	hurtbox.receive_damage(Damage.create(5.0, Vector2(60.0, 0.0), 0.1))
	assert_almost_eq(player.velocity.x, 60.0, 0.001, "knockback applies outside i-frames")
	assert_lt(GameState.hp, hp_before, "damage applies outside i-frames")
