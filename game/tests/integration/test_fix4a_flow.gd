extends GutTest
## Fix-4a — блокеры финального ревью Guardian (B-01/B-02/B-04) и MINOR-01/05.
##
## Покрытие (сценарии как у игрока, на настоящих сценах/автолоадах):
##   * B-01/AC-05.2: чекпоинт в зоне 1 → переход в зону 2 → смерть → возрождение
##     НЕ телепортирует в координаты чужой зоны, а грузит зону 1 (экран
##     загрузки) и ставит игрока на позицию костра; corpse остаётся в зоне 2.
##   * B-02/AC-05.1: сохранение у костра зоны 4 (288,224) → загрузка слота →
##     игрок в зоне 4 ровно на позиции костра, а не на первой entry.
##   * B-04: экран смерти → «В главное меню» → death-состояние снято,
##     SceneRouter сброшен, запрошен MainMenu.tscn (смена сцены подменена хуком,
##     чтобы не уничтожить раннер GUT).
##   * MINOR-05: присяга открывается только по сюжетному квесту, побочный квест
##     не взводит запрос выбора фракции.
##   * MINOR-01: маппинг режимов окна (borderless ≠ exclusive fullscreen).
##
## Слоты пишутся в `user://test_saves_fix4a`; глобальное состояние GameState,
## SceneRouter и SaveManager восстанавливается в after_each/after_all.

const MAIN_SCENE: PackedScene = preload("res://Main.tscn")
const MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")

const ZONE_01: StringName = &"zone_01_village"
const ZONE_02: StringName = &"zone_02_swamp"
const ZONE_04: StringName = &"zone_04_ruins"
## Позиции с offset спавна костра (origin + respawn_offset (0, -12)).
const BONFIRE_01: Vector2 = Vector2(112.0, 212.0)
const BONFIRE_04: Vector2 = Vector2(288.0, 212.0)
const TEST_DIR: String = "user://test_saves_fix4a"

var _host: Node2D
var _world_root: Node2D
var _fake_main: Node2D = null

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
	_cleanup_dir()


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

	SceneRouter.reset()
	SceneRouter.load_timeout = SceneRouter.LOAD_TIMEOUT
	SceneRouter.min_loading_time = SceneRouter.MIN_LOADING_TIME
	SceneRouter.exit_grace_time = SceneRouter.EXIT_GRACE_TIME
	GameState.clear_corpse()
	GameState.death_active = false
	GameState.set_hp(GameState.hp_max)
	GameState.set_in_combat(false)
	GameState.current_zone_id = &""
	GameState.restore_respawn_bonfire(&"", &"", Vector2.ZERO)
	GameState.reset_factions()
	GameState.active_slot = 0
	_cleanup_dir()

	_host = Node2D.new()
	_host.name = "Fix4aHost"
	add_child_autofree(_host)
	_world_root = Node2D.new()
	_world_root.name = "WorldRoot"
	_host.add_child(_world_root)
	SceneRouter.bind_world_root(_world_root)


func after_each() -> void:
	SceneRouter.reset()
	SceneRouter.unbind_world_root()
	_free_fake_main()
	await wait_physics_frames(1)
	get_tree().paused = false

	GameState.clear_corpse()
	GameState.death_active = _original_death_active
	GameState.restore_death_state(
		_original_death_active,
		bool(_original_corpse.get("active", false)),
		StringName(str(_original_corpse.get("zone_id", ""))),
		_original_corpse.get("position", Vector2.ZERO),
		_original_corpse.get("items", []),
		int(_original_corpse.get("currency", 0)),
		bool(_original_corpse.get("lost", false))
	)
	GameState.set_hp(_original_hp)
	GameState.currency = _original_currency
	GameState.restore_inventory(_original_inventory)
	GameState.restore_abilities(_original_abilities)
	GameState.restore_respawn_bonfire(
		StringName(str(_original_respawn.get("bonfire", ""))),
		StringName(str(_original_respawn.get("zone_id", ""))),
		_original_respawn.get("position", Vector2.ZERO)
	)
	GameState.active_slot = _original_active_slot
	GameState.set_in_combat(_original_in_combat)
	GameState.current_zone_id = _original_zone
	GameState.reset_factions()
	_cleanup_dir()


# ------------------------------------------------------------------------------
# B-01 / AC-05.2 — возрождение в зоне чекпоинта
# ------------------------------------------------------------------------------

func test_death_in_other_zone_respawns_at_checkpoint_zone_and_bonfire() -> void:
	# Игрок сохранился у костра зоны 1 и ушёл в зону 2 (без активации её костра).
	assert_true(SceneRouter.bootstrap(ZONE_01, &"start"), "zone 1 starts")
	GameState.set_respawn_bonfire(ZONE_01, &"hub", BONFIRE_01)
	assert_true(
		SaveManager.save_slot(1, {"zone_id": String(ZONE_01)}),
		"save at the zone 1 bonfire"
	)
	await _transition(ZONE_02, &"west_gate")
	assert_eq(GameState.current_zone_id, ZONE_02)

	var player: Player = SceneRouter.player
	assert_not_null(player, "player exists after the transition")
	if player == null:
		return
	player.set_physics_process(false)
	# Зона 2 живая: её костёр/враги могли сработать за кадры перехода. Для
	# сценария важно, что игрок сохранился в зоне 1 и её костёр — чекпоинт.
	GameState.set_respawn_bonfire(ZONE_01, &"hub", BONFIRE_01)
	GameState.restore_hp(GameState.hp_max)
	assert_eq(GameState.respawn_zone_id, ZONE_01, "checkpoint stays in zone 1")

	var handler: DeathHandler = DeathHandler.new()
	add_child_autofree(handler)
	handler.set_physics_process(false)
	await wait_process_frames(1)

	# Смерть в зоне 2; чекпоинт остался в зоне 1.
	player.global_position = Vector2(300.0, 200.0)
	player.kill()
	assert_eq(handler.phase, &"dying", "death budget started")

	watch_signals(EventBus)
	handler.tick(handler.balance.t_death)

	# B-01: это не телепортация, а переход в зону чекпоинта с экраном загрузки.
	assert_true(SceneRouter.is_loading, "cross-zone respawn uses a transition")
	await wait_for_signal(SceneRouter.transition_finished, 5.0)
	await wait_physics_frames(2)

	assert_eq(handler.phase, &"idle", "respawn finished")
	assert_false(GameState.death_active, "death is resolved")
	assert_eq(SceneRouter.current_zone_id, ZONE_01, "player is back in the checkpoint zone")
	assert_eq(
		SceneRouter.current_entry_id,
		SceneRouter.CHECKPOINT_ENTRY_ID,
		"virtual checkpoint entry is used"
	)
	var respawn_position: Vector2 = SceneRouter.player.global_position
	assert_almost_eq(
		respawn_position.x,
		BONFIRE_01.x,
		0.01,
		"player stands at the zone 1 bonfire (AC-05.2)"
	)
	assert_almost_eq(
		respawn_position.y,
		BONFIRE_01.y,
		4.0,
		"y is the bonfire spawn point (gravity pulls at most a few px)"
	)
	assert_almost_eq(GameState.hp, GameState.hp_max, 0.001, "respawn restores full HP")
	assert_eq(
		GameState.corpse_zone_id,
		ZONE_02,
		"corpse stays where the player died (corpse run, AC-05.3)"
	)
	assert_signal_emitted(EventBus, "player_respawned")


# ------------------------------------------------------------------------------
# B-02 / AC-05.1 — загрузка слота ставит игрока у костра
# ------------------------------------------------------------------------------

func test_loading_slot_starts_player_at_zone_4_bonfire() -> void:
	# Сейв у костра зоны 4 (у зоны нет entry `start`, костёр — 288,224).
	GameState.current_zone_id = ZONE_04
	GameState.set_respawn_bonfire(ZONE_04, &"ruins_camp", BONFIRE_04)
	assert_true(
		SaveManager.save_slot(1, {"zone_id": String(ZONE_04)}),
		"save at the zone 4 bonfire"
	)

	# «Новый процесс»: память забега пуста, на диске — слот у костра.
	SceneRouter.reset()
	GameState.reset_death_state(true)
	GameState.current_zone_id = &""

	# MainMenu грузит in-place, если в дереве есть /root/Main/WorldRoot.
	_make_fake_main()
	var menu: MainMenu = MENU_SCENE.instantiate() as MainMenu
	add_child_autofree(menu)
	await wait_process_frames(2)
	assert_eq(menu.get_continue_slot(), 1, "the slot is visible to the menu")

	menu._start_game(1)

	assert_eq(SceneRouter.current_zone_id, ZONE_04, "the checkpoint zone is loaded")
	assert_eq(
		SceneRouter.current_entry_id,
		SceneRouter.CHECKPOINT_ENTRY_ID,
		"loading uses the virtual checkpoint entry"
	)
	assert_not_null(SceneRouter.player, "player is spawned")
	if SceneRouter.player != null:
		# Позиция читается сразу после синхронного bootstrap — до гравитации.
		assert_eq(
			SceneRouter.player.global_position,
			BONFIRE_04,
			"player stands at the zone 4 bonfire, not on the first entry (AC-05.1)"
		)
		assert_ne(
			SceneRouter.player.global_position,
			Vector2(32.0, 214.0),
			"the first zone 4 entry is not used"
		)
		SceneRouter.player.set_physics_process(false)


# ------------------------------------------------------------------------------
# B-04 — экран смерти → главное меню; MINOR-05 — фильтр присяги
# ------------------------------------------------------------------------------

func test_death_screen_menu_returns_to_main_menu_and_resets_death_state() -> void:
	var main: Node = await _mount_main()
	if main == null:
		return
	var death := main.get_node_or_null("Overlay/DeathScreen") as DeathScreen
	assert_not_null(death, "DeathScreen is mounted in Main")
	if death == null:
		return
	assert_true(
		death.is_connected(&"main_menu_requested", Callable(main, &"_on_main_menu_requested")),
		"B-04: Main listens to the death screen menu button"
	)
	var constants: Dictionary = (main.get_script() as Script).get_script_constant_map()
	assert_true(
		ResourceLoader.exists(str(constants.get("MAIN_MENU_SCENE_PATH", ""))),
		"the main menu scene exists"
	)

	# Смена current_scene внутри GUT уничтожила бы раннер — подменяем загрузчик.
	var opened: Array[bool] = [false]
	main.set("menu_scene_loader", func() -> void: opened[0] = true)

	GameState.set_hp(0.0)
	GameState.death_active = true
	GameState.set_in_combat(true)
	death.show_death({
		"items": [],
		"currency": 0,
		"position": Vector2(300.0, 200.0),
		"zone_id": String(ZONE_01),
	})
	await wait_process_frames(1)
	assert_true(death.is_shown(), "death screen is shown")

	death.get_menu_button().pressed.emit()
	await wait_process_frames(2)

	assert_true(opened[0], "B-04: MainMenu.tscn load is requested")
	assert_false(death.is_shown(), "death screen is hidden")
	assert_false(GameState.death_active, "death state is cleared")
	assert_almost_eq(GameState.hp, GameState.hp_max, 0.001, "run is not left at hp=0")
	assert_false(GameState.in_combat, "combat flag is reset")
	assert_eq(SceneRouter.current_zone_id, &"", "SceneRouter is reset for the menu")
	assert_null(SceneRouter.player, "the run player is released")


func test_faction_choice_is_armed_only_by_the_oath_quest() -> void:
	var main: Node = await _mount_main()
	if main == null:
		return
	var constants: Dictionary = (main.get_script() as Script).get_script_constant_map()
	var oath_quest: StringName = StringName(str(constants.get("FACTION_OATH_QUEST", "")))
	assert_eq(oath_quest, &"quest_free_smuggle", "the oath quest id is fixed")

	# Сбрасываем флаги Main и фракционное состояние (экран ещё не открывался).
	main.set("_faction_choice_pending", false)
	main.set("_faction_choice_requested", false)
	GameState.reset_factions()

	# Побочный квест: репутация меняется, но присяга не запрашивается.
	main.call(&"_on_quest_completed", &"quest_clear_swamp", "Очистить болото")
	assert_false(
		bool(main.get("_faction_choice_pending")),
		"MINOR-05: a side quest does not arm the faction choice"
	)
	assert_false(bool(main.get("_faction_choice_requested")))

	# Сюжетный квест присяги взводит запрос.
	main.call(&"_on_quest_completed", oath_quest, "Обряд")
	assert_true(
		bool(main.get("_faction_choice_pending")),
		"MINOR-05: only the oath quest arms the faction choice"
	)
	# Не даём отложенному вызову открыть FactionChoice (он ставит дерево на
	# паузу и усложнил бы следующий тест).
	main.set("_faction_choice_requested", true)
	await wait_process_frames(1)


func test_window_mode_mapping_borderless_is_not_exclusive_fullscreen() -> void:
	assert_eq(
		int(Config.display_mode_for(Config.WINDOW_FULLSCREEN)),
		int(DisplayServer.WINDOW_MODE_FULLSCREEN),
		"fullscreen uses the engine fullscreen mode"
	)
	assert_eq(
		int(Config.display_mode_for(Config.WINDOW_BORDERLESS)),
		int(DisplayServer.WINDOW_MODE_WINDOWED),
		"MINOR-01: borderless is windowed"
	)
	assert_true(Config.is_borderless_mode(Config.WINDOW_BORDERLESS))
	assert_false(Config.is_borderless_mode(Config.WINDOW_FULLSCREEN))
	assert_false(Config.is_borderless_mode(Config.WINDOW_WINDOWED))


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _mount_main() -> Node:
	SceneRouter.reset()
	SceneRouter.unbind_world_root()
	GameState.current_zone_id = &""
	var main: Node = MAIN_SCENE.instantiate()
	var zone_root: Node2D = main.get_node("WorldRoot") as Node2D
	SceneRouter.bind_world_root(zone_root)
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


func _transition(zone_id: StringName, entry_id: StringName) -> void:
	var started: bool = SceneRouter.change_zone(zone_id, entry_id)
	assert_true(started, "transition to '%s' starts" % zone_id)
	if started:
		await wait_for_signal(SceneRouter.transition_finished, 5.0)
	await wait_physics_frames(2)


## /root/Main/WorldRoot — условие `MainMenu._has_world_root()` для загрузки
## «на месте» (без смены сцены) в GUT.
func _make_fake_main() -> void:
	_free_fake_main()
	_fake_main = Node2D.new()
	_fake_main.name = "Main"
	var zone_root := Node2D.new()
	zone_root.name = "WorldRoot"
	_fake_main.add_child(zone_root)
	get_tree().root.add_child(_fake_main)
	SceneRouter.bind_world_root(zone_root)


func _free_fake_main() -> void:
	if _fake_main != null and is_instance_valid(_fake_main):
		if _fake_main.get_parent() != null:
			_fake_main.get_parent().remove_child(_fake_main)
		_fake_main.free()
	_fake_main = null


func _cleanup_dir() -> void:
	var directory: DirAccess = DirAccess.open(TEST_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
