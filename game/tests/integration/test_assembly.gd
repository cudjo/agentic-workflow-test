extends GutTest
## Integration-02: финальная сборка готовых систем.
##
## Проверяет то, что нельзя проверить юнитами:
##   1. MainMenu — точка входа проекта (ProjectSettings) и reset «Новой игры»
##      (passed_gates/journal/visited_zones).
##   2. Монтаж Main.tscn: HUD (слой 10), DialogueScreen (слой 20), Campfire,
##      DeathHandler (группа `death_handler`).
##   3. Полный флоу сборки: Main → SceneRouter.bootstrap → зона 1, игрок в зоне,
##      NPC на маркерах, арена босса в зоне.
##   4. Interact-система игрока: костёр → Campfire, NPC → DialogueScreen,
##      in_combat блокирует не-боевые интерактивы.
##   5. Арены боссов вмонтированы в зоны 1–4: вход в правую половину запускает
##      бой, барьеры закрываются; в зоне 5 арена T-32 уже смонтирована.
##   6. DeathHandler: смерть → экран смерти → возрождение у костра.

const MAIN_SCENE: PackedScene = preload("res://Main.tscn")
const MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")
const PLAYER_GROUP: StringName = &"player"

const ZONE_PATHS: Array[String] = [
	"res://world/zones/zone_01_village/zone_01_village.tscn",
	"res://world/zones/zone_02_swamp/zone_02_swamp.tscn",
	"res://world/zones/zone_03_mountains/zone_03_mountains.tscn",
	"res://world/zones/zone_04_ruins/zone_04_ruins.tscn",
]
const ARENA_NAMES: Array[StringName] = [
	&"BossArenaZone01",
	&"BossArenaZone02",
	&"BossArenaZone03",
	&"BossArenaZone04",
]

var main: Node = null

# Снимок общего состояния (autoload'ы) — тесты не должны его протекать.
var _hp: float = 0.0
var _stamina: float = 0.0
var _currency: int = 0
var _inventory: Array[StringName] = []
var _abilities: Array[StringName] = []
var _active_slot: int = 0
var _in_combat: bool = false
var _zone: StringName = &""
var _visited: Array[StringName] = []
var _passed_gates: Array[StringName] = []
var _journal: Dictionary = {}


func before_each() -> void:
	_hp = GameState.hp
	_stamina = GameState.stamina
	_currency = GameState.currency
	_inventory = GameState.get_inventory()
	_abilities = GameState.get_abilities()
	_active_slot = GameState.active_slot
	_in_combat = GameState.in_combat
	_zone = GameState.current_zone_id
	_visited = SceneRouter.get_visited_zone_ids()
	_passed_gates = AbilityGate.get_passed_gate_ids()
	_journal = Journal.get_state()

	SceneRouter.reset()
	SceneRouter.unbind_world_root()
	GameState.set_in_combat(false)
	GameState.current_zone_id = &""
	GameState.active_slot = 0
	GameState.reset_death_state(true)
	AbilityGate.reset_passed_gates()
	Journal.reset_state()
	main = null


func after_each() -> void:
	SceneRouter.reset()
	SceneRouter.unbind_world_root()
	if main != null and is_instance_valid(main):
		main.queue_free()
	main = null

	GameState.set_in_combat(_in_combat)
	GameState.set_hp(_hp)
	GameState.restore_stamina(_stamina)
	GameState.currency = _currency
	GameState.restore_inventory(_inventory)
	GameState.restore_abilities(_abilities)
	GameState.active_slot = _active_slot
	GameState.current_zone_id = _zone
	SceneRouter.restore_visited_zones(_visited)
	AbilityGate.restore_passed_gates(_passed_gates)
	Journal.restore_state(_journal)


## Монтирует Main как обычную дочернюю сцену: WorldRoot привязывается до
## `_ready`, поэтому `SceneRouter.bootstrap()` находит его и загружает зону 1.
func _mount_main() -> Node:
	main = MAIN_SCENE.instantiate()
	var world_root := main.get_node("WorldRoot") as Node2D
	SceneRouter.bind_world_root(world_root)
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


func _player() -> Player:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(PLAYER_GROUP)
	for node: Node in nodes:
		if node is Player:
			return node as Player
	return null


# ------------------------------------------------------------------------------
# 1. Точка входа + reset «Новой игры»
# ------------------------------------------------------------------------------

func test_main_scene_is_the_menu() -> void:
	assert_eq(
		str(ProjectSettings.get_setting("application/run/main_scene")),
		"res://ui/menus/MainMenu.tscn",
		"игра стартует с главного меню, а не сразу с Main"
	)


func test_new_game_resets_world_progress() -> void:
	AbilityGate.mark_gate_passed(&"village_ledge")
	Journal.start_quest(&"quest_clear_swamp")
	Journal.record_event(&"assembly_test")
	SceneRouter.restore_visited_zones([&"zone_02_swamp", &"zone_03_mountains"])
	assert_eq(AbilityGate.get_passed_gate_ids().size(), 1)

	var menu := MENU_SCENE.instantiate() as MainMenu
	menu.handle_game_start = false
	menu.handle_quit = false
	add_child_autofree(menu)
	await wait_process_frames(1)

	menu._reset_for_new_game()

	assert_eq(AbilityGate.get_passed_gate_ids().size(), 0, "passed_gates сброшены")
	assert_eq(Journal.get_active_quests().size(), 0, "журнал: активные квесты пусты")
	assert_eq(Journal.get_completed_quests().size(), 0)
	assert_eq(Journal.get_events().size(), 0, "журнал: события пусты")
	assert_eq(SceneRouter.get_visited_zone_ids().size(), 0, "visited_zones сброшены")
	assert_eq(GameState.active_slot, 0)


# ------------------------------------------------------------------------------
# 2. Монтаж Main
# ------------------------------------------------------------------------------

func test_main_mounts_hud_dialogue_and_death_handler() -> void:
	await _mount_main()

	var hud := main.get_node_or_null("HUD") as AshenHUD
	assert_not_null(hud, "HUD (T-19) смонтирован в Main")
	if hud != null:
		assert_eq(hud.layer, 10, "HUD на слое 10")
		assert_true(hud.visible, "HUD виден")
		assert_not_null(hud.get_root_control(), "HUD построен")

	var dialogue := main.get_node_or_null("DialogueScreen") as DialogueScreen
	assert_not_null(dialogue, "DialogueScreen (T-28) смонтирован")
	if dialogue != null:
		assert_eq(dialogue.layer, 20, "диалог на слое 20")
		assert_true(dialogue.is_in_group(&"dialogue_ui"), "диалог в группе dialogue_ui")

	var campfire := main.get_node_or_null("Campfire") as Campfire
	assert_not_null(campfire, "Campfire (T-23) смонтирован")
	if campfire != null:
		assert_true(campfire.is_in_group(&"campfire_ui"), "костёр в группе campfire_ui")

	var handler := main.get_node_or_null("DeathHandler") as DeathHandler
	assert_not_null(handler, "DeathHandler (T-26) смонтирован")
	if handler != null:
		assert_true(handler.is_in_group(&"death_handler"), "обработчик в группе death_handler")

	for node_name: String in ["Inventory", "Journal", "Factions", "FactionChoice", "Remap", "WorldMap"]:
		assert_not_null(main.get_node_or_null(node_name), "%s доступен в Main" % node_name)
	assert_not_null(main.get_node_or_null("Overlay/DeathScreen"), "DeathScreen (T-22) остаётся в Main")


# ------------------------------------------------------------------------------
# 3. Сборка мира: зона 1, игрок, NPC, арена
# ------------------------------------------------------------------------------

func test_bootstrap_spawns_player_in_zone_1_with_hud() -> void:
	await _mount_main()

	assert_eq(SceneRouter.current_zone_id, &"zone_01_village", "bootstrap загрузил зону 1")
	var zone := SceneRouter.current_zone as ZoneScene
	assert_not_null(zone)

	var player := _player()
	assert_not_null(player, "игрок создан SceneRouter")
	if player != null:
		assert_eq(player.get_parent(), zone, "игрок находится в дереве зоны")
		assert_almost_eq(player.global_position.x, 100.0, 0.1, "спавн на entry 'start'")
		assert_almost_eq(player.global_position.y, 214.0, 0.1)
		assert_not_null(player.get_node_or_null("Interaction"), "у игрока есть interact-система")

	var hud := main.get_node("HUD") as AshenHUD
	assert_true(hud.visible, "HUD виден после старта зоны")

	# NPC на маркерах хаба (T-14 → T-28).
	var keeper := zone.get_node_or_null("NPCs/KeeperNpc") as DialogueNpc
	var trader := zone.get_node_or_null("NPCs/TraderNpc") as TraderNpc
	assert_not_null(keeper, "хранитель стоит в хабе")
	assert_not_null(trader, "торговец стоит в хабе")
	if keeper != null:
		var marker := zone.get_node_or_null("NPCs/NPC_Keeper") as Marker2D
		assert_not_null(marker)
		assert_eq(keeper.position, marker.position, "NPC_Keeper использован как точка")
		assert_eq(keeper.get_dialogue_id(), &"elder_lira")
	if trader != null:
		var marker := zone.get_node_or_null("NPCs/Trader") as Marker2D
		assert_not_null(marker)
		assert_eq(trader.position, marker.position, "Trader использован как точка")
		assert_eq(trader.get_dialogue_id(), &"quartermaster_helga")
		assert_false(trader.stock.is_empty(), "у торговца есть ассортимент")

	var arena := zone.get_node_or_null("Arena/BossArenaZone01") as BossArena
	assert_not_null(arena, "арена босса 1 вставлена в зону 1")
	if arena != null:
		assert_not_null(arena.get_boss(), "босс 1 заспавнен на арене")


# ------------------------------------------------------------------------------
# 4. Interact-система
# ------------------------------------------------------------------------------

func test_interact_opens_campfire_and_npc_dialogue() -> void:
	await _mount_main()
	var zone := SceneRouter.current_zone as ZoneScene
	var player := _player()
	assert_not_null(player)
	if player == null:
		return

	var interaction := player.get_node("Interaction") as PlayerInteraction
	var campfire := main.get_node("Campfire") as Campfire
	var dialogue := main.get_node("DialogueScreen") as DialogueScreen
	var bonfire := zone.get_node("Props/Bonfire") as Bonfire
	var keeper := zone.get_node("NPCs/KeeperNpc") as DialogueNpc

	# Костёр: игрок стоит рядом, ближайший интерактив — костёр.
	player.global_position = bonfire.global_position + Vector2(0, -10)
	assert_eq(interaction.get_nearest_interactable(), bonfire, "рядом с костром выбран костёр")
	assert_true(interaction.try_interact(), "interact открывает костёр")
	assert_true(campfire.is_open(), "Campfire.open(bonfire) вызван")
	campfire.close()
	assert_false(campfire.is_open())

	# NPC: игрок стоит на маркере хранителя.
	player.global_position = keeper.global_position
	assert_eq(interaction.get_nearest_interactable(), keeper, "рядом с NPC выбран NPC")
	assert_true(interaction.try_interact(), "interact открывает диалог")
	assert_true(dialogue.is_open(), "DialogueScreen.open_npc(npc) вызван")
	assert_eq(dialogue.get_runner().data.id, &"elder_lira")
	dialogue.close()
	assert_false(dialogue.is_open())

	# EC-06: в бою не-боевые интерактивы не открываются.
	GameState.set_in_combat(true)
	assert_false(interaction.try_interact(), "в бою interact заблокирован")
	assert_false(dialogue.is_open())
	GameState.set_in_combat(false)


# ------------------------------------------------------------------------------
# 5. Арены боссов в зонах 1–4
# ------------------------------------------------------------------------------

func test_boss_arenas_are_mounted_in_zones_1_to_4() -> void:
	for index: int in ZONE_PATHS.size():
		var zone := SceneRouter.instantiate_zone(ZONE_PATHS[index])
		assert_not_null(zone, "%s загружается" % ZONE_PATHS[index])
		if zone == null:
			continue
		add_child_autofree(zone)
		await wait_process_frames(2)

		var arena := zone.get_node_or_null("Arena/%s" % ARENA_NAMES[index]) as BossArena
		assert_not_null(arena, "%s: арена вставлена" % zone.zone_data.id)
		if arena == null:
			continue
		assert_not_null(arena.get_boss(), "%s: босс заспавнен" % zone.zone_data.id)
		assert_false(arena.is_fight_active(), "бой ждёт входа игрока")
		assert_false(arena.are_barriers_closed(), "до входа барьеры открыты")

		var trigger := arena.get_node_or_null("Trigger") as Area2D
		assert_not_null(trigger)
		if trigger != null:
			assert_almost_eq(trigger.position.x, 354.0, 0.1, "вход — правая половина комнаты")
			var shape := trigger.get_node("CollisionShape2D") as CollisionShape2D
			assert_not_null(shape)
			if shape != null and shape.shape is RectangleShape2D:
				assert_eq(
					(shape.shape as RectangleShape2D).size,
					Vector2(228, 200),
					"триггер начинается у маркера ArenaEntrance"
				)
		zone.queue_free()
		await wait_process_frames(1)


func test_entering_the_arena_starts_the_fight_and_closes_barriers() -> void:
	await _mount_main()
	var zone := SceneRouter.current_zone as ZoneScene
	var arena := zone.get_node("Arena/BossArenaZone01") as BossArena
	var player := _player()
	assert_not_null(arena)
	assert_not_null(player)
	if arena == null or player == null:
		return

	player.global_position = Vector2(360, 214)
	await wait_physics_frames(4)
	await wait_process_frames(1)

	assert_true(arena.is_fight_active(), "вход игрока запускает бой")
	assert_true(GameState.in_combat, "бой выставляет GameState.in_combat (EC-06)")
	var left := arena.get_node("BarrierLeft") as StaticBody2D
	var right := arena.get_node("BarrierRight") as StaticBody2D
	assert_eq(left.collision_layer, CombatLayers.WORLD, "левый выход закрыт")
	assert_eq(right.collision_layer, CombatLayers.WORLD, "правый выход закрыт")


# ------------------------------------------------------------------------------
# 6. Смерть → экран смерти → возрождение у костра
# ------------------------------------------------------------------------------

func test_death_screen_and_respawn_at_bonfire() -> void:
	await _mount_main()
	var zone := SceneRouter.current_zone as ZoneScene
	var player := _player()
	var handler := get_tree().get_first_node_in_group(&"death_handler") as DeathHandler
	var screen := main.get_node("Overlay/DeathScreen") as DeathScreen
	assert_not_null(player)
	assert_not_null(handler)
	assert_not_null(screen)
	if player == null or handler == null or screen == null:
		return
	# `_adopt_death_handler` вызывается через call_deferred — даём ему кадр.
	await wait_process_frames(1)

	var bonfire := zone.get_node("Props/Bonfire") as Bonfire
	bonfire.activate_checkpoint()
	assert_true(GameState.has_checkpoint(), "костёр — точка возрождения")

	player.kill()
	await wait_process_frames(2)
	assert_eq(handler.phase, &"dying", "смерть перехвачена DeathHandler")
	handler.tick(GameState.balance.t_death + 0.1)
	await wait_process_frames(2)

	assert_eq(handler.phase, &"dead", "бюджет t_death истёк, ждём кнопку")
	assert_true(screen.is_shown(), "экран смерти показан")
	assert_false(handler.auto_respawn, "экран смерти выключил авто-возрождение")

	screen.respawn_now()
	await wait_process_frames(2)
	assert_false(GameState.death_active, "смерть разрешена")
	assert_false(screen.is_shown(), "экран смерти скрыт")
	assert_almost_eq(player.global_position.x, bonfire.global_position.x, 0.5, "возрождение у костра")
	assert_almost_eq(
		player.global_position.y,
		bonfire.global_position.y + bonfire.respawn_offset.y,
		0.5
	)
