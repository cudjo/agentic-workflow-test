extends GutTest
## T-26 — смерть, corpse run и чекпоинты-костры (PLAN §3.4, SPEC US-05,
## AC-05.2/05.3, EC-01/03/04/05/06).
##
## Тесты используют настоящие Player/Bonfire/DeathHandler/Corpse-сцены.
## Бюджет смерти прогоняется детерминированно через `DeathHandler.tick()`
## (physics-обработчик узла выключен), чтобы не зависеть от реального времени.
##
## Слоты пишутся в `user://test_saves_t26`; глобальное состояние GameState
## восстанавливается в after_each, чтобы не влиять на другие GUT-скрипты.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const BONFIRE_SCENE: PackedScene = preload("res://world/props/bonfire.tscn")
const CORPSE_SCENE: PackedScene = preload("res://world/props/corpse.tscn")
const TEST_DIR: String = "user://test_saves_t26"

var _original_saves_dir: String = SaveManager.DEFAULT_SAVES_DIR
var _original_hp: float = 0.0
var _original_currency: int = 0
var _original_inventory: Array[StringName] = []
var _original_abilities: Array[StringName] = []
var _original_death_active: bool = false
var _original_corpse: Dictionary = {}
var _original_respawn: Dictionary = {}
var _original_active_slot: int = 0
var _original_in_combat: bool = false
var _original_zone: StringName = &""


func before_all() -> void:
	_original_saves_dir = SaveManager.saves_dir
	SaveManager.saves_dir = TEST_DIR


func after_all() -> void:
	SaveManager.saves_dir = _original_saves_dir
	_cleanup_dir()
	var parent: DirAccess = DirAccess.open(TEST_DIR.get_base_dir())
	if parent != null and parent.dir_exists(TEST_DIR.get_file()):
		parent.remove(TEST_DIR.get_file())


func before_each() -> void:
	_original_hp = GameState.hp
	_original_currency = GameState.currency
	_original_inventory = GameState.get_inventory()
	_original_abilities = GameState.get_abilities()
	_original_death_active = GameState.death_active
	_original_corpse = GameState.get_corpse_info()
	_original_respawn = {
		"bonfire": GameState.respawn_bonfire,
		"zone_id": GameState.respawn_zone_id,
		"position": GameState.respawn_position,
	}
	_original_active_slot = GameState.active_slot
	_original_in_combat = GameState.in_combat
	_original_zone = GameState.current_zone_id

	_cleanup_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	_free_corpses()
	_reset_global_state()


func after_each() -> void:
	_free_corpses()
	GameState.set_hp(_original_hp)
	GameState.currency = _original_currency
	GameState.restore_inventory(_original_inventory)
	GameState.restore_abilities(_original_abilities)
	GameState.restore_death_state(
		_original_death_active,
		bool(_original_corpse.get("active", false)),
		StringName(str(_original_corpse.get("zone_id", ""))),
		_original_corpse.get("position", Vector2.ZERO),
		_original_corpse.get("items", []),
		int(_original_corpse.get("currency", 0)),
		bool(_original_corpse.get("lost", false))
	)
	GameState.restore_respawn_bonfire(
		StringName(str(_original_respawn.get("bonfire", ""))),
		StringName(str(_original_respawn.get("zone_id", ""))),
		_original_respawn.get("position", Vector2.ZERO)
	)
	GameState.active_slot = _original_active_slot
	GameState.set_in_combat(_original_in_combat)
	GameState.current_zone_id = _original_zone
	_cleanup_dir()


func _reset_global_state() -> void:
	GameState.set_hp(GameState.hp_max)
	GameState.currency = 0
	GameState.clear_inventory()
	GameState.clear_abilities()
	GameState.clear_corpse()
	GameState.death_active = false
	GameState.restore_respawn_bonfire(&"", &"", Vector2.ZERO)
	GameState.active_slot = 0
	GameState.set_in_combat(false)
	GameState.current_zone_id = &"zone_01_village"


func _spawn_player(at_position: Vector2 = Vector2.ZERO) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.global_position = at_position
	player.velocity = Vector2.ZERO
	return player


func _spawn_handler() -> DeathHandler:
	var handler: DeathHandler = DeathHandler.new()
	add_child_autofree(handler)
	handler.set_physics_process(false)
	return handler


# ------------------------------------------------------------------------------
# HP / death budget
# ------------------------------------------------------------------------------

func test_hp_comes_from_balance_and_lethal_damage_kills() -> void:
	var player: Player = _spawn_player()
	player.set_physics_process(false)

	assert_gt(GameState.hp_max, 0.0, "max HP comes from balancing.tres")
	assert_almost_eq(GameState.hp, GameState.hp_max, 0.001, "run starts at full HP")

	watch_signals(EventBus)
	player.apply_damage(30.0)
	assert_almost_eq(GameState.hp, GameState.hp_max - 30.0, 0.001, "damage reduces HP")
	assert_eq(player.get_state_name(), &"hurt", "non-lethal damage enters Hurt")
	assert_signal_emitted(EventBus, "player_health_changed")

	player.apply_damage(GameState.hp_max)
	assert_true(player.is_dead, "HP <= 0 kills the player")
	assert_almost_eq(GameState.hp, 0.0, 0.001, "HP is clamped at zero")
	assert_eq(player.get_state_name(), &"death", "death state is terminal (EC-01)")
	assert_signal_emitted(EventBus, "player_died")


func test_death_drops_loot_at_death_position_and_respawns_after_t_death() -> void:
	var player: Player = _spawn_player(Vector2(300.0, 200.0))
	player.set_physics_process(false)
	var handler: DeathHandler = _spawn_handler()
	GameState.set_respawn_bonfire(
		&"zone_01_village",
		&"hub",
		Vector2(112.0, 212.0)
	)
	GameState.restore_inventory([&"ash_shard", &"bone_charm"])
	GameState.currency = 37

	watch_signals(EventBus)
	player.kill()

	assert_eq(handler.phase, &"dying", "death budget starts immediately")
	assert_true(GameState.death_active, "pending death is recorded (EC-04)")
	assert_eq(handler.time_left, player.balance.t_death, "budget is t_death")

	# AC-05.2: инвентарь и валюта лежат на месте гибели.
	assert_true(GameState.has_corpse(), "corpse marker is created")
	assert_eq(GameState.corpse_position, Vector2(300.0, 200.0), "corpse is at the death spot")
	assert_eq(GameState.get_inventory(), [], "inventory moved into the corpse")
	assert_eq(GameState.currency, 0, "currency moved into the corpse")
	assert_eq(GameState.corpse_currency, 37, "corpse keeps the currency")
	assert_signal_emitted(EventBus, "corpse_dropped")
	assert_eq(
		get_tree().get_nodes_in_group(&"corpses").size(),
		0,
		"corpse node waits until respawn (dead body cannot self-pickup)"
	)

	handler.tick(player.balance.t_death * 0.5)
	assert_eq(player.get_state_name(), &"death", "still dead inside the budget")
	assert_almost_eq(GameState.hp, 0.0, 0.001, "HP stays zero inside the budget")

	handler.tick(player.balance.t_death)
	assert_eq(handler.phase, &"idle", "budget finished")
	assert_false(GameState.death_active, "death resolved")
	assert_almost_eq(GameState.hp, GameState.hp_max, 0.001, "respawn restores full HP")
	assert_false(player.is_dead, "player is alive again")
	assert_eq(player.get_state_name(), &"idle", "player is idle after respawn")
	assert_eq(
		player.global_position,
		Vector2(112.0, 212.0),
		"player respawns at the bonfire (AC-05.2)"
	)
	assert_signal_emitted(EventBus, "death_screen_requested")
	assert_signal_emitted(EventBus, "player_respawned")

	var corpses: Array[Node] = get_tree().get_nodes_in_group(&"corpses")
	assert_eq(corpses.size(), 1, "corpse node appears after respawn")
	if not corpses.is_empty():
		assert_eq(
			(corpses[0] as Node2D).global_position,
			Vector2(300.0, 200.0),
			"corpse node stays at the death spot"
		)


func test_death_during_dash_and_in_air_interrupts_and_respawns() -> void:
	var player: Player = _spawn_player(Vector2(40.0, 40.0))
	player.set_physics_process(false)
	var handler: DeathHandler = _spawn_handler()
	GameState.set_respawn_bonfire(
		&"zone_01_village",
		&"hub",
		Vector2(112.0, 212.0)
	)

	# EC-01: смерть во время рывка.
	player.state_machine.force_state(&"dash")
	assert_eq(player.get_state_name(), &"dash", "precondition: dashing")
	player.kill()
	assert_eq(player.get_state_name(), &"death", "death interrupts Dash (EC-01)")
	assert_eq(player.velocity, Vector2.ZERO, "dash momentum is cleared")

	handler.tick(player.balance.t_death)
	assert_eq(player.get_state_name(), &"idle", "respawned after dash death")
	assert_eq(player.global_position, Vector2(112.0, 212.0))
	assert_almost_eq(GameState.hp, GameState.hp_max, 0.001)

	# EC-01: смерть в воздухе.
	player.state_machine.force_state(&"jump")
	assert_eq(player.get_state_name(), &"jump", "precondition: airborne")
	player.kill()
	assert_eq(player.get_state_name(), &"death", "death interrupts Jump (EC-01)")
	handler.tick(player.balance.t_death)
	assert_eq(player.get_state_name(), &"idle")
	assert_eq(player.global_position, Vector2(112.0, 212.0))


# ------------------------------------------------------------------------------
# Corpse run (AC-05.3, EC-05)
# ------------------------------------------------------------------------------

func test_corpse_is_picked_up_by_contact() -> void:
	var player: Player = _spawn_player(Vector2(60.0, 60.0))
	var handler: DeathHandler = _spawn_handler()
	GameState.set_respawn_bonfire(&"zone_01_village", &"hub", Vector2(0.0, 0.0))
	GameState.restore_inventory([&"ash_shard"])
	GameState.currency = 21

	player.kill()
	handler.tick(player.balance.t_death)
	assert_true(GameState.has_corpse(), "corpse is waiting on the ground")

	var corpses: Array[Node] = get_tree().get_nodes_in_group(&"corpses")
	assert_eq(corpses.size(), 1)
	var corpse: Corpse = corpses[0] as Corpse
	assert_not_null(corpse)

	# Возвращаемся на место гибели: подбор по контакту.
	player.set_physics_process(false)
	player.global_position = corpse.global_position
	watch_signals(EventBus)
	await wait_physics_frames(3)

	assert_false(GameState.has_corpse(), "contact consumes the corpse marker (AC-05.3)")
	assert_true(corpse.is_collected(), "corpse node reports pickup")
	assert_eq(GameState.get_inventory(), [&"ash_shard"], "items are returned")
	assert_eq(GameState.currency, 21, "currency is returned")
	assert_signal_emitted(EventBus, "corpse_collected")


func test_second_death_before_pickup_makes_loss_irreversible() -> void:
	var player: Player = _spawn_player(Vector2(10.0, 10.0))
	player.set_physics_process(false)
	var handler: DeathHandler = _spawn_handler()
	GameState.set_respawn_bonfire(&"zone_01_village", &"hub", Vector2(0.0, 0.0))
	GameState.restore_inventory([&"ash_shard"])
	GameState.currency = 10

	player.kill()
	handler.tick(player.balance.t_death)
	var corpses: Array[Node] = get_tree().get_nodes_in_group(&"corpses")
	assert_eq(corpses.size(), 1)
	var first_corpse: Corpse = corpses[0] as Corpse
	assert_not_null(first_corpse)

	# Новая добыча и смерть до подбора первой метки (EC-05).
	GameState.restore_inventory([&"bone_charm"])
	GameState.currency = 5
	player.global_position = Vector2(90.0, 20.0)
	watch_signals(EventBus)
	player.kill()

	assert_signal_emitted(EventBus, "corpse_lost")
	assert_true(first_corpse.lost, "the old marker becomes a skull (EC-05)")
	assert_false(first_corpse.collect(), "lost corpse cannot be picked up")
	assert_eq(GameState.get_inventory(), [], "second death also drops current loot")

	# Вторая метка содержит только вторую добычу; первая потеряна навсегда.
	assert_true(GameState.has_corpse())
	assert_false(GameState.is_corpse_lost(), "new marker is recoverable")
	assert_eq(GameState.corpse_items, [&"bone_charm"])
	assert_eq(GameState.corpse_currency, 5)

	handler.tick(player.balance.t_death)
	var all_corpses: Array[Node] = get_tree().get_nodes_in_group(&"corpses")
	assert_eq(all_corpses.size(), 2, "skull and new corpse coexist")

	var second_corpse: Corpse = null
	for node: Node in all_corpses:
		if node != first_corpse:
			second_corpse = node as Corpse
	assert_not_null(second_corpse, "new corpse node is spawned")
	if second_corpse != null:
		assert_true(second_corpse.collect(), "new corpse is recoverable")

	assert_eq(GameState.get_inventory(), [&"bone_charm"], "only the second drop returns")
	assert_eq(GameState.currency, 5)
	assert_false(
		GameState.get_inventory().has(&"ash_shard"),
		"loot from the first death is gone forever (EC-05)"
	)


# ------------------------------------------------------------------------------
# Pit, EC-03
# ------------------------------------------------------------------------------

func test_fall_into_pit_deals_full_damage_even_in_dash_iframes() -> void:
	var player: Player = _spawn_player(Vector2(0.0, 0.0))
	player.fall_death_y = 100.0
	player.global_position = Vector2(0.0, 150.0)
	await wait_physics_frames(2)

	assert_true(player.is_dead, "falling below the limit kills (EC-03)")
	assert_eq(player.get_state_name(), &"death")
	assert_almost_eq(GameState.hp, 0.0, 0.001, "falling deals full damage")

	# Даже i-frames рывка не спасают от пропасти (EC-01/EC-03).
	GameState.set_hp(GameState.hp_max)
	player.reset_player()
	# T-07: рывок требует способность (AC-02.2), иначе состояние выходит.
	GameState.add_ability(&"dash")
	player.state_machine.force_state(&"dash")
	assert_true(player.is_invulnerable(), "precondition: dash i-frames")
	player.global_position = Vector2(0.0, 150.0)
	await wait_physics_frames(2)
	assert_true(player.is_dead, "pit damage bypasses dash i-frames")
	assert_almost_eq(GameState.hp, 0.0, 0.001)


# ------------------------------------------------------------------------------
# Bonfire: checkpoint + save point (AC-05.1, EC-06)
# ------------------------------------------------------------------------------

func test_bonfire_checkpoint_and_in_combat_blocks_save() -> void:
	var bonfire: Bonfire = BONFIRE_SCENE.instantiate()
	add_child_autofree(bonfire)
	bonfire.zone_id = &"zone_01_village"
	bonfire.bonfire_id = &"hub"
	bonfire.position = Vector2(112.0, 224.0)

	watch_signals(bonfire)
	bonfire.activate_checkpoint()
	assert_signal_emitted_with_parameters(bonfire, "checkpoint_activated", [&"hub"])
	assert_eq(GameState.respawn_bonfire, &"zone_01_village/hub", "bonfire is the checkpoint")
	assert_eq(GameState.respawn_zone_id, &"zone_01_village")
	assert_eq(GameState.respawn_position, Vector2(112.0, 212.0), "respawn uses offset")

	assert_true(bonfire.can_save(), "saving is allowed outside combat")
	assert_true(
		bonfire.save_to_slot(1, {"level": 2, "play_time": 5.0}),
		"bonfire is the save point (AC-05.1)"
	)
	assert_true(SaveManager.has_slot(1), "slot is written by the bonfire")

	GameState.set_in_combat(true)
	watch_signals(EventBus)
	assert_false(bonfire.can_save(), "combat blocks saving (EC-06)")
	assert_false(bonfire.save_to_slot(2), "in-combat save is refused")
	assert_signal_emitted_with_parameters(
		EventBus,
		"save_failed",
		[2, Bonfire.SAVE_REASON_IN_COMBAT]
	)
	assert_false(SaveManager.has_slot(2), "nothing was written in combat")


func test_bonfire_contact_activates_checkpoint() -> void:
	var bonfire: Bonfire = BONFIRE_SCENE.instantiate()
	add_child_autofree(bonfire)
	bonfire.zone_id = &"zone_01_village"
	bonfire.bonfire_id = &"camp"
	bonfire.position = Vector2(100.0, 100.0)

	var player: Player = _spawn_player(Vector2(100.0, 92.0))
	player.set_physics_process(false)
	await wait_physics_frames(3)

	assert_eq(
		GameState.respawn_bonfire,
		&"zone_01_village/camp",
		"touching the bonfire sets the checkpoint"
	)
	assert_eq(GameState.respawn_position, Vector2(100.0, 88.0))


# ------------------------------------------------------------------------------
# EC-04: quit during the death budget
# ------------------------------------------------------------------------------

func test_quit_during_death_budget_persists_death_and_resolves_on_load() -> void:
	var player: Player = _spawn_player(Vector2(200.0, 150.0))
	player.set_physics_process(false)
	var handler: DeathHandler = _spawn_handler()
	GameState.set_respawn_bonfire(
		&"zone_01_village",
		&"hub",
		Vector2(112.0, 212.0)
	)
	GameState.restore_inventory([&"ash_shard"])
	GameState.currency = 44

	# Обычное сохранение у костра выбирает активный слот.
	assert_true(SaveManager.save_slot(1, {"zone_id": "zone_01_village"}))
	assert_eq(GameState.active_slot, 1, "active slot is remembered")

	# Смерть и «выход из игры» в бюджете: death-автосейв уже записан.
	player.kill()
	assert_true(GameState.death_active)
	assert_true(GameState.has_corpse())

	# Сбрасываем память процесса (как при новом запуске).
	handler.get_parent().remove_child(handler)
	handler.free()
	player.get_parent().remove_child(player)
	player.free()
	GameState.reset_death_state()
	GameState.restore_inventory([])
	GameState.currency = 0
	GameState.restore_respawn_bonfire(&"", &"", Vector2.ZERO)

	assert_true(SaveManager.load_slot(1), "death autosave loads")
	assert_true(GameState.death_active, "death is not rolled back (EC-04)")
	assert_almost_eq(GameState.hp, 0.0, 0.001, "loaded HP is zero")
	assert_eq(GameState.get_inventory(), [], "loot is still lost")
	assert_eq(GameState.currency, 0)
	assert_eq(GameState.corpse_items, [&"ash_shard"], "corpse is persisted")
	assert_eq(GameState.corpse_currency, 44, "lost currency is persisted")
	assert_eq(GameState.corpse_position, Vector2(200.0, 150.0), "corpse spot is persisted")
	assert_eq(GameState.respawn_bonfire, &"zone_01_village/hub", "checkpoint is persisted")

	# Новый процесс: DeathHandler разрешает отложенную смерть как обычную.
	var player_after: Player = _spawn_player(Vector2(0.0, 0.0))
	player_after.set_physics_process(false)
	var handler_after: DeathHandler = _spawn_handler()
	handler_after.resolve_pending_death()

	assert_false(GameState.death_active, "pending death is resolved on load")
	assert_almost_eq(GameState.hp, GameState.hp_max, 0.001, "full HP after load-respawn")
	assert_false(player_after.is_dead)
	assert_eq(player_after.global_position, Vector2(112.0, 212.0), "respawn at the bonfire")
	assert_true(GameState.has_corpse(), "corpse remains for the corpse run")
	assert_false(GameState.is_corpse_lost())


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

## Corpse-узлы спавнятся в рантайме и не входят в autofree GUT — чистим сами,
## иначе группа `corpses` накапливает узлы между тестами.
func _free_corpses() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"corpses"):
		if not is_instance_valid(node):
			continue
		var parent: Node = node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.free()


func _cleanup_dir() -> void:
	var directory: DirAccess = DirAccess.open(TEST_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for directory_name: String in directory.get_directories():
		directory.remove(directory_name)
