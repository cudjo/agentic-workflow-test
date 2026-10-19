extends Node
## QA Fix-4a/4b — независимая e2e-проверка блокеров Guardian на сборке `v2`
## (HEAD 00eae32) реальными сценами Main/Zone/Player/Enemy/Bonfire/DeathScreen/
## MainMenu. Драйвер живёт в /root, поэтому переживает смены current_scene.
##
## Покрытие:
##   B-01 — костёр зоны 1 → физический выход в зону 2 → смерть → возрождение
##          в зоне 1 у костра (не телепорт в чужие координаты).
##   B-02 — костёр зоны 4 (288,224) → сохранение → «перезапуск» через MainMenu →
##          загрузка слота → игрок у костра (288,212), а не на первой entry.
##   B-03 — обычный враг агрится → EC-06 (сохранение/интерактив запрещены);
##          смерть в финальной арене → in_combat=false, барьеры открыты.
##   B-04 — экран смерти → «В главное меню» → MainMenu без soft-lock.
##   MINOR-01 — маппинг режима окна (borderless ≠ exclusive fullscreen).
##   MINOR-05 — присяга открывается только сюжетным квестом.
##   MINOR-06 — i-frames переката гасят knockback/flash.
##
## Слоты пишутся в `user://qa_fix4ab_saves` (удаляются в конце).

const MAIN_PATH: String = "res://Main.tscn"
const MENU_PATH: String = "res://ui/menus/MainMenu.tscn"

const ZONE_01: StringName = &"zone_01_village"
const ZONE_02: StringName = &"zone_02_swamp"
const ZONE_04: StringName = &"zone_04_ruins"
const ZONE_05: StringName = &"zone_05_finale"

## Позиция игрока по чекпоинту костра: origin + respawn_offset (0,-12).
const BONFIRE_01: Vector2 = Vector2(112.0, 212.0)
const BONFIRE_04: Vector2 = Vector2(288.0, 212.0)
const ZONE_04_FIRST_ENTRY: Vector2 = Vector2(32.0, 214.0)

const TEST_DIR: String = "user://qa_fix4ab_saves"
const OATH_QUEST: StringName = &"quest_free_smuggle"
const SIDE_QUEST: StringName = &"quest_clear_swamp"

var _pass: int = 0
var _fail: int = 0
var _saves_original: String = ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_saves_original = SaveManager.saves_dir
	SaveManager.saves_dir = TEST_DIR
	_cleanup_dir()

	print("[FIX4AB] === старт e2e-приёмки Fix-4a/Fix-4b (MainMenu → Main → зоны) ===")
	await _stage_b01()
	await _stage_b02()
	await _stage_b03()
	await _stage_b04()
	await _stage_minor05()
	await _stage_minor06()
	await _stage_minor01()

	SaveManager.saves_dir = _saves_original
	_cleanup_dir()
	_get_tree_safe().paused = false
	_report()
	await _wait_process(5)
	get_tree().quit(0 if _fail == 0 else 1)


func _get_tree_safe() -> SceneTree:
	return get_tree()


# ------------------------------------------------------------------------------
# B-01
# ------------------------------------------------------------------------------

func _stage_b01() -> void:
	_section("B-01/AC-05.2 — возрождение в зоне чекпоинта")
	if not await _fresh_main():
		return

	var bonfire := _bonfire()
	var player := _player()
	if not _expect("B-01 setup: костёр и игрок в зоне 1", bonfire != null and player != null):
		return

	# Физический вход в Area2D костра (как игрок), не ручной set_respawn_bonfire.
	player.global_position = bonfire.global_position + Vector2(0.0, -4.0)
	player.velocity = Vector2.ZERO
	await _wait_physics(5)
	_expect(
		"B-01: костёр зоны 1 активирует чекпоинт физическим входом",
		GameState.respawn_zone_id == ZONE_01
			and GameState.respawn_position.is_equal_approx(BONFIRE_01),
		"zone=%s pos=%s" % [GameState.respawn_zone_id, str(GameState.respawn_position)]
	)
	_expect(
		"B-01: сохранение у костра зоны 1",
		bonfire.save_to_slot(1),
		"slot1=%s" % str(SaveManager.get_slot_metadata(1).get("valid", false))
	)

	# Физический выход zone1 → zone2 (Area2D Exits/Exit_gate), не телепорт.
	var exit_node := SceneRouter.current_zone.get_node_or_null("Exits/Exit_gate") as Area2D
	_expect("B-01: физический выход zone1→zone2 существует", exit_node != null)
	if exit_node == null:
		return
	player.global_position = exit_node.global_position
	player.velocity = Vector2.ZERO
	var moved: bool = await _wait_zone(ZONE_02, 240)
	_expect("B-01: физический переход в зону 2", moved, "zone=%s" % SceneRouter.current_zone_id)
	_expect(
		"B-01: без костра зоны 2 чекпоинт остаётся в зоне 1",
		GameState.respawn_zone_id == ZONE_01,
		"checkpoint_zone=%s" % GameState.respawn_zone_id
	)

	player = _player()
	if not _expect("B-01: игрок существует в зоне 2", player != null):
		return
	GameState.set_hp(GameState.hp_max)
	player.set_physics_process(false)
	player.global_position = Vector2(300.0, 200.0)
	player.kill()
	await _wait_physics(2)
	var handler := get_tree().get_first_node_in_group(&"death_handler") as DeathHandler
	if not _expect("B-01: DeathHandler начал смерть", handler != null and handler.phase == &"dying"):
		return
	var budget: float = handler.balance.t_death if handler.balance != null else 1.2
	handler.tick(budget + 0.1)
	await _wait_process(3)

	var main := _current_main()
	var screen: DeathScreen = null
	if main != null:
		screen = main.get_node_or_null("Overlay/DeathScreen") as DeathScreen
	_expect("B-01: экран смерти показан", screen != null and screen.is_shown())

	# Захват состояния сразу в момент transition_finished (до гравитации).
	var capture: Dictionary = {"done": false}
	var on_transition := func(zone_id: StringName, entry_id: StringName) -> void:
		capture["done"] = true
		capture["zone"] = zone_id
		capture["entry"] = entry_id
		capture["pos"] = (
			SceneRouter.player.global_position if SceneRouter.player != null else Vector2(-1.0, -1.0)
		)
	SceneRouter.transition_finished.connect(on_transition)
	if screen != null:
		screen.get_respawn_button().pressed.emit()
	for _i: int in 600:
		if bool(capture.get("done", false)):
			break
		await get_tree().process_frame
	SceneRouter.transition_finished.disconnect(on_transition)
	await _wait_physics(3)

	_expect(
		"B-01: возрождение использует переход в зону чекпоинта (не телепорт)",
		bool(capture.get("done", false))
			and StringName(str(capture.get("zone", ""))) == ZONE_01
			and StringName(str(capture.get("entry", ""))) == SceneRouter.CHECKPOINT_ENTRY_ID,
		"zone=%s entry=%s" % [str(capture.get("zone", "")), str(capture.get("entry", ""))]
	)
	var spawn_pos: Vector2 = capture.get("pos", Vector2(-1.0, -1.0))
	_expect(
		"B-01: игрок у костра зоны 1 (112,212)",
		absf(spawn_pos.x - BONFIRE_01.x) <= 0.5 and absf(spawn_pos.y - BONFIRE_01.y) <= 4.0,
		"spawn=%s target=%s" % [str(spawn_pos), str(BONFIRE_01)]
	)
	_expect(
		"B-01: после возрождения активна зона 1",
		SceneRouter.current_zone_id == ZONE_01 and not SceneRouter.is_loading,
		"zone=%s loading=%s" % [SceneRouter.current_zone_id, str(SceneRouter.is_loading)]
	)
	_expect(
		"B-01: смерть разрешена, HP полный",
		not GameState.death_active and GameState.hp >= GameState.hp_max - 0.01,
		"death=%s hp=%.1f" % [str(GameState.death_active), GameState.hp]
	)
	_expect(
		"B-01: corpse остался в зоне гибели (corpse run)",
		GameState.corpse_zone_id == ZONE_02,
		"corpse_zone=%s" % GameState.corpse_zone_id
	)


# ------------------------------------------------------------------------------
# B-02
# ------------------------------------------------------------------------------

func _stage_b02() -> void:
	_section("B-02/AC-05.1 — загрузка слота ставит игрока у костра зоны 4")
	await _reset_run()
	var ok_scene: bool = await _load_scene(MENU_PATH, "MainMenu")
	_expect("B-02: MainMenu загружен", ok_scene)
	if not ok_scene:
		return
	var menu := get_tree().current_scene as MainMenu
	_expect("B-02: главное меню активно", menu != null)
	if menu == null:
		return

	# Старт новой игры → зона 1 → переход в зону 4 (как игрок).
	menu.call(&"_start_game", 0)
	var to_main: bool = await _wait_scene_name("Main", 600)
	_expect("B-02: «Новая игра» открывает Main", to_main)
	_expect("B-02: зона 1 после новой игры", await _wait_zone(ZONE_01, 300))
	var started: bool = SceneRouter.change_zone(ZONE_04, &"from_swamp")
	_expect("B-02: переход в зону 4 запущен", started)
	_expect("B-02: зона 4 загружена", await _wait_zone(ZONE_04, 300))

	var bonfire := _bonfire()
	var player := _player()
	if not _expect("B-02 setup: костёр и игрок в зоне 4", bonfire != null and player != null):
		return
	player.global_position = bonfire.global_position + Vector2(0.0, -4.0)
	player.velocity = Vector2.ZERO
	await _wait_physics(5)
	_expect(
		"B-02: чекпоинт зоны 4 у костра (288,212)",
		GameState.respawn_zone_id == ZONE_04
			and GameState.respawn_position.is_equal_approx(BONFIRE_04),
		"zone=%s pos=%s bonfire=%s" % [
			GameState.respawn_zone_id,
			str(GameState.respawn_position),
			str(bonfire.global_position),
		]
	)
	_expect("B-02: слот 2 сохранён у костра зоны 4", bonfire.save_to_slot(2))
	_expect(
		"B-02: метаданные слота 2 указывают зону 4",
		StringName(str(SaveManager.get_slot_metadata(2).get("zone_id", ""))) == ZONE_04,
		str(SaveManager.get_slot_metadata(2))
	)

	# «Перезапуск»: память забега сброшена, на диске — слот у костра.
	await _reset_run()
	var menu_ok: bool = await _load_scene(MENU_PATH, "MainMenu")
	_expect("B-02: меню после перезапуска", menu_ok)
	if not menu_ok:
		return
	menu = get_tree().current_scene as MainMenu
	if menu == null:
		return
	_expect(
		"B-02: меню видит слот 2",
		menu.get_continue_slot() == 2,
		"continue_slot=%d" % menu.get_continue_slot()
	)

	var capture: Dictionary = {"done": false}
	var on_transition := func(zone_id: StringName, entry_id: StringName) -> void:
		capture["done"] = true
		capture["zone"] = zone_id
		capture["entry"] = entry_id
		capture["pos"] = (
			SceneRouter.player.global_position if SceneRouter.player != null else Vector2(-1.0, -1.0)
		)
	SceneRouter.transition_finished.connect(on_transition)
	menu.call(&"_start_game", 2)
	var loaded_main: bool = await _wait_scene_name("Main", 600)
	for _i: int in 300:
		if bool(capture.get("done", false)):
			break
		await get_tree().process_frame
	SceneRouter.transition_finished.disconnect(on_transition)
	await _wait_process(3)

	_expect("B-02: загрузка слота 2 открывает Main", loaded_main)
	_expect(
		"B-02: загружена зона 4 через чекпоинт",
		bool(capture.get("done", false))
			and StringName(str(capture.get("zone", ""))) == ZONE_04
			and StringName(str(capture.get("entry", ""))) == SceneRouter.CHECKPOINT_ENTRY_ID,
		"zone=%s entry=%s" % [str(capture.get("zone", "")), str(capture.get("entry", ""))]
	)
	var spawn_pos: Vector2 = capture.get("pos", Vector2(-1.0, -1.0))
	_expect(
		"B-02: игрок стоит у костра зоны 4 (288,212), не на первой entry",
		absf(spawn_pos.x - BONFIRE_04.x) <= 0.5
			and absf(spawn_pos.y - BONFIRE_04.y) <= 4.0
			and spawn_pos.distance_to(ZONE_04_FIRST_ENTRY) > 8.0,
		"spawn=%s first_entry=%s" % [str(spawn_pos), str(ZONE_04_FIRST_ENTRY)]
	)
	await _wait_physics(2)
	player = _player()
	_expect(
		"B-02: после физики игрок остаётся у костра",
		player != null
			and absf(player.global_position.x - BONFIRE_04.x) <= 1.0
			and absf(player.global_position.y - BONFIRE_04.y) <= 6.0,
		"player=%s" % (str(player.global_position) if player != null else "null")
	)


# ------------------------------------------------------------------------------
# B-03
# ------------------------------------------------------------------------------

func _stage_b03() -> void:
	_section("B-03/EC-06 — бой обычных врагов и смерть на арене")
	# Продолжаем в зоне 4 после B-02: там реальный EnemySpawner.
	if SceneRouter.current_zone_id != ZONE_04:
		await _fresh_main()
		SceneRouter.change_zone(ZONE_04, &"from_swamp")
		await _wait_zone(ZONE_04, 300)

	var player := _player()
	var zone := SceneRouter.current_zone
	if not _expect("B-03 setup: игрок и зона 4", player != null and zone != null):
		return
	GameState.reset_combat_state()
	GameState.set_hp(GameState.hp_max)
	GameState.reset_stamina()
	var spawner := zone.get_node_or_null("Enemies/EnemySpawner") as EnemySpawner
	var enemies: Array[Enemy] = []
	if spawner != null:
		enemies = spawner.get_alive_enemies()
	_expect("B-03: в зоне 4 есть обычные враги", enemies.size() > 0, "alive=%d" % enemies.size())

	var aggro: bool = false
	for enemy: Enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		player.global_position = enemy.global_position + Vector2(20.0, 0.0)
		player.velocity = Vector2.ZERO
		GameState.set_hp(GameState.hp_max)
		for _i: int in 90:
			await get_tree().physics_frame
			if GameState.in_combat:
				aggro = true
				break
		if aggro:
			break
	_expect("B-03: обычный враг агрится → in_combat=true", aggro, "in_combat=%s" % str(GameState.in_combat))
	_expect("B-03: EC-06 — сохранение в бою запрещено (GameState)", not GameState.can_save())

	var bonfire := _bonfire()
	if not _expect("B-03: костёр зоны 4 найден", bonfire != null):
		return
	SaveManager.delete_slot(3)
	var failures: Array[Dictionary] = []
	var on_fail := func(slot: int, reason: String) -> void:
		failures.append({"slot": slot, "reason": reason})
	EventBus.save_failed.connect(on_fail)
	var saved_in_combat: bool = bonfire.save_to_slot(3)
	EventBus.save_failed.disconnect(on_fail)
	_expect(
		"B-03: EC-06 — костёр отклоняет сохранение в бою",
		not saved_in_combat and not SaveManager.has_slot(3),
		"saved=%s has_slot=%s" % [str(saved_in_combat), str(SaveManager.has_slot(3))]
	)
	_expect(
		"B-03: причина отказа in_combat",
		failures.size() == 1 and str(failures[0].get("reason", "")) == "in_combat",
		str(failures)
	)
	var interaction := player.get_node_or_null("Interaction") as PlayerInteraction
	_expect(
		"B-03: EC-06 — интерактив (костёр) заблокирован в бою",
		interaction != null and not interaction.can_interact()
	)

	# Смерть в финальной арене.
	await _reset_run()
	if not await _fresh_main():
		return
	_expect("B-03: переход в зону 5", SceneRouter.change_zone(ZONE_05, &"from_ruins"))
	_expect("B-03: зона 5 загружена", await _wait_zone(ZONE_05, 300))
	player = _player()
	if not _expect("B-03: игрок в зоне 5", player != null):
		return
	GameState.set_hp(GameState.hp_max)
	player.global_position = Vector2(60.0, 200.0)
	player.velocity = Vector2.ZERO

	var arena := SceneRouter.current_zone.get_node_or_null("Arena")
	var fight: bool = false
	for _i: int in 180:
		if arena != null and bool(arena.call(&"is_fight_active")):
			fight = true
			break
		await get_tree().physics_frame
	_expect("B-03: вход в арену запускает бой", fight)
	if arena == null:
		return
	_expect(
		"B-03: бой арены поднимает in_combat и закрывает барьеры",
		GameState.in_combat and bool(arena.call(&"are_barriers_closed")),
		"in_combat=%s barriers_closed=%s" % [
			str(GameState.in_combat), str(arena.call(&"are_barriers_closed"))
		]
	)

	player.set_physics_process(false)
	player.kill()
	await _wait_physics(3)
	_expect(
		"B-03: смерть на арене сбрасывает in_combat",
		not GameState.in_combat,
		"in_combat=%s" % str(GameState.in_combat)
	)
	_expect(
		"B-03: смерть прерывает бой арены",
		not bool(arena.call(&"is_fight_active")),
		"fight_active=%s" % str(arena.call(&"is_fight_active"))
	)
	var boss := arena.get("boss") as BossBase
	_expect(
		"B-03: босс остановлен",
		boss == null or not boss.fight_active,
		"boss_fight=%s" % (str(boss.fight_active) if boss != null else "null")
	)
	_expect(
		"B-03: барьеры арены открыты",
		not bool(arena.call(&"are_barriers_closed")),
		"closed=%s" % str(arena.call(&"are_barriers_closed"))
	)
	var barriers_open: bool = true
	var barrier_count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"arena_barrier"):
		if arena.is_ancestor_of(node) and node is StaticBody2D:
			barrier_count += 1
			if (node as StaticBody2D).collision_layer != 0:
				barriers_open = false
	_expect(
		"B-03: collision_layer барьеров снят",
		barrier_count > 0 and barriers_open,
		"barriers=%d open=%s" % [barrier_count, str(barriers_open)]
	)
	_expect(
		"B-03: после смерти на арене сохранение снова доступно",
		GameState.can_save()
	)


# ------------------------------------------------------------------------------
# B-04
# ------------------------------------------------------------------------------

func _stage_b04() -> void:
	_section("B-04 — экран смерти → «В главное меню» без soft-lock")
	if not await _fresh_main():
		return
	var main := _current_main()
	var player := _player()
	if not _expect("B-04 setup: Main и игрок", main != null and player != null):
		return
	GameState.active_slot = 0
	GameState.set_hp(GameState.hp_max)
	player.kill()
	await _wait_physics(2)
	var handler := get_tree().get_first_node_in_group(&"death_handler") as DeathHandler
	if not _expect("B-04: смерть начата", handler != null):
		return
	var budget: float = handler.balance.t_death if handler.balance != null else 1.2
	handler.tick(budget + 0.1)
	await _wait_process(3)
	var screen := main.get_node_or_null("Overlay/DeathScreen") as DeathScreen
	if not _expect("B-04: экран смерти показан", screen != null and screen.is_shown()):
		return
	var menu_button := screen.get_menu_button()
	_expect("B-04: кнопка «В главное меню» есть и активна", menu_button != null and not menu_button.disabled)

	menu_button.pressed.emit()
	var menu_loaded: bool = await _wait_scene_name("MainMenu", 600)
	_expect("B-04: нажатие открывает MainMenu (не soft-lock)", menu_loaded)
	_expect(
		"B-04: death-состояние снято",
		not GameState.death_active and GameState.hp >= GameState.hp_max - 0.01,
		"death=%s hp=%.1f" % [str(GameState.death_active), GameState.hp]
	)
	_expect(
		"B-04: SceneRouter сброшен, игрок освобождён",
		SceneRouter.current_zone_id == &"" and SceneRouter.player == null,
		"zone=%s player=%s" % [SceneRouter.current_zone_id, str(SceneRouter.player)]
	)
	_expect("B-04: дерево не на паузе", not get_tree().paused)

	var menu := get_tree().current_scene as MainMenu
	_expect("B-04: current_scene — MainMenu", menu != null)
	if menu == null:
		return
	await _wait_process(5)
	var focus: Control = get_viewport().gui_get_focus_owner()
	_expect(
		"B-04: меню получило фокус (управляемо без мыши)",
		focus != null and menu.is_ancestor_of(focus),
		"focus=%s" % (focus.name if focus != null else "null")
	)

	# Замкнутый цикл: из меню снова можно начать игру.
	menu.call(&"_start_game", 0)
	var again: bool = await _wait_scene_name("Main", 600)
	_expect("B-04: из меню снова стартует игра", again)
	_expect("B-04: зона 1 загружается после возврата", await _wait_zone(ZONE_01, 300))
	var fresh_player := _player()
	_expect(
		"B-04: новый забег с живым игроком",
		fresh_player != null and not fresh_player.is_dead and GameState.hp > 0.0
	)


# ------------------------------------------------------------------------------
# MINOR-05
# ------------------------------------------------------------------------------

func _stage_minor05() -> void:
	_section("MINOR-05 — присяга только по сюжетному квесту")
	var main := _current_main()
	var choice := main.get_node_or_null("FactionChoice") as FactionChoice if main != null else null
	if not _expect("MINOR-05 setup: Main/FactionChoice", main != null and choice != null):
		return
	GameState.reset_factions()

	var requests: Array[String] = []
	var on_request := func(reason: String) -> void:
		requests.append(reason)
	EventBus.faction_choice_requested.connect(on_request)
	EventBus.quest_completed.emit(SIDE_QUEST, "Очистить болото")
	await _wait_process(4)
	_expect(
		"MINOR-05: побочный квест не открывает присягу",
		requests.is_empty() and not choice.is_open(),
		"requests=%s open=%s" % [str(requests), str(choice.is_open())]
	)

	EventBus.quest_completed.emit(OATH_QUEST, "Обряд присяги")
	await _wait_process(4)
	_expect(
		"MINOR-05: сюжетный квест открывает присягу",
		requests.size() == 1 and choice.is_open(),
		"requests=%s open=%s" % [str(requests), str(choice.is_open())]
	)
	if choice.is_open():
		choice.close()
	await _wait_process(2)
	EventBus.faction_choice_requested.disconnect(on_request)
	_expect("MINOR-05: экран присяги закрывается, пауза снята", not get_tree().paused)


# ------------------------------------------------------------------------------
# MINOR-06
# ------------------------------------------------------------------------------

func _stage_minor06() -> void:
	_section("MINOR-06 — i-frames переката гасят knockback/flash")
	var player := _player()
	if not _expect("MINOR-06 setup: игрок в зоне 1", player != null):
		return
	GameState.reset_hp()
	GameState.reset_stamina()
	player.global_position = Vector2(100.0, 210.0)
	player.velocity = Vector2.ZERO
	await _wait_physics(8)
	GameState.set_hp(GameState.hp_max)

	player.state_machine.force_state(&"roll")
	var iframe: bool = false
	for _i: int in 30:
		if player.is_invulnerable():
			iframe = true
			break
		await get_tree().physics_frame
	_expect("MINOR-06: перекат входит в i-frames", iframe)
	if not iframe:
		return

	var hurtbox := player.get_node_or_null("Hurtbox") as Hurtbox
	if not _expect("MINOR-06: у игрока есть Hurtbox", hurtbox != null):
		return
	var hp_before: float = GameState.hp
	var velocity_before: float = player.velocity.x
	var flashes_before: int = hurtbox.flash_applied_count
	var accepted: bool = hurtbox.receive_damage(
		Damage.create(5.0, Vector2(80.0, 0.0), 0.1)
	)
	_expect("MINOR-06: урон в i-frames отклонён", not accepted)
	_expect(
		"MINOR-06: в i-frames нет потери HP",
		is_equal_approx(GameState.hp, hp_before),
		"hp %.1f → %.1f" % [hp_before, GameState.hp]
	)
	_expect(
		"MINOR-06: в i-frames нет knockback",
		is_equal_approx(player.velocity.x, velocity_before),
		"vx %.1f → %.1f" % [velocity_before, player.velocity.x]
	)
	_expect(
		"MINOR-06: в i-frames нет вспышки",
		hurtbox.flash_applied_count == flashes_before
			and player.visual.modulate != Damage.FLASH_COLOR,
		"flashes %d → %d" % [flashes_before, hurtbox.flash_applied_count]
	)

	var finished: bool = false
	for _i: int in 90:
		if not player.is_invulnerable():
			finished = true
			break
		await get_tree().physics_frame
	_expect("MINOR-06: i-frames заканчиваются", finished)
	player.velocity = Vector2.ZERO
	await _wait_physics(1)
	var hp_after: float = GameState.hp
	var applied: bool = hurtbox.receive_damage(Damage.create(5.0, Vector2(60.0, 0.0), 0.1))
	_expect("MINOR-06: вне i-frames урон проходит", applied)
	_expect(
		"MINOR-06: вне i-frames knockback применяется",
		absf(player.velocity.x - 60.0) <= 0.01,
		"vx=%.2f" % player.velocity.x
	)
	_expect("MINOR-06: вне i-frames HP снижается", GameState.hp < hp_after)


# ------------------------------------------------------------------------------
# MINOR-01
# ------------------------------------------------------------------------------

func _stage_minor01() -> void:
	_section("MINOR-01 — режим окна: borderless ≠ exclusive fullscreen")
	_expect(
		"MINOR-01: WINDOW_FULLSCREEN → WINDOW_MODE_FULLSCREEN",
		int(Config.display_mode_for(Config.WINDOW_FULLSCREEN)) == int(DisplayServer.WINDOW_MODE_FULLSCREEN)
	)
	_expect(
		"MINOR-01: WINDOW_BORDERLESS → WINDOW_MODE_WINDOWED",
		int(Config.display_mode_for(Config.WINDOW_BORDERLESS)) == int(DisplayServer.WINDOW_MODE_WINDOWED)
	)
	_expect(
		"MINOR-01: WINDOW_WINDOWED → WINDOW_MODE_WINDOWED",
		int(Config.display_mode_for(Config.WINDOW_WINDOWED)) == int(DisplayServer.WINDOW_MODE_WINDOWED)
	)
	_expect(
		"MINOR-01: is_borderless_mode только для borderless",
		Config.is_borderless_mode(Config.WINDOW_BORDERLESS)
			and not Config.is_borderless_mode(Config.WINDOW_FULLSCREEN)
			and not Config.is_borderless_mode(Config.WINDOW_WINDOWED)
	)

	var driver_name: String = DisplayServer.get_name()
	if driver_name == "headless":
		_expect(
			"MINOR-01: runtime применения режима окна",
			false,
			"headless DisplayServer: runtime-проверка не выполнена (требуется render-прогон)"
		)
		return

	var original_mode: int = Config.window_mode
	Config.window_mode = Config.WINDOW_BORDERLESS
	await _wait_process(2)
	_expect(
		"MINOR-01: runtime borderless = windowed + флаг",
		int(DisplayServer.window_get_mode()) == int(DisplayServer.WINDOW_MODE_WINDOWED)
			and DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS),
		"mode=%d flag=%s" % [
			DisplayServer.window_get_mode(),
			str(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)),
		]
	)
	Config.window_mode = Config.WINDOW_FULLSCREEN
	await _wait_process(2)
	_expect(
		"MINOR-01: runtime fullscreen = WINDOW_MODE_FULLSCREEN",
		int(DisplayServer.window_get_mode()) == int(DisplayServer.WINDOW_MODE_FULLSCREEN),
		"mode=%d" % DisplayServer.window_get_mode()
	)
	Config.window_mode = original_mode
	await _wait_process(2)


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _expect(step: String, ok: bool, detail: String = "") -> bool:
	if ok:
		_pass += 1
	else:
		_fail += 1
	var suffix: String = (" — " + detail) if not detail.is_empty() else ""
	print("[FIX4AB] %s %s%s" % ["PASS" if ok else "FAIL", step, suffix])
	return ok


func _section(title: String) -> void:
	print("[FIX4AB] --- %s ---" % title)


func _current_main() -> Node:
	var scene := get_tree().current_scene
	if scene != null and scene.name == "Main":
		return scene
	return null


func _player() -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		if node is Player:
			return node as Player
	return null


func _bonfire() -> Bonfire:
	if SceneRouter.current_zone == null:
		return null
	return SceneRouter.current_zone.get_node_or_null("Props/Bonfire") as Bonfire


func _reset_run() -> void:
	get_tree().paused = false
	SceneRouter.reset()
	SceneRouter.unbind_world_root()
	GameState.reset_combat_state()
	GameState.reset_death_state(true)
	GameState.set_hp(GameState.hp_max)
	GameState.reset_stamina()
	GameState.current_zone_id = &""
	GameState.active_slot = 0
	GameState.reset_factions()
	await _wait_process(1)


func _fresh_main() -> bool:
	await _reset_run()
	var loaded: bool = await _load_scene(MAIN_PATH, "Main")
	if not _expect("setup: Main загружен", loaded):
		return false
	var zone_ok: bool = await _wait_zone(ZONE_01, 300)
	_expect("setup: стартовая зона 1 загружена", zone_ok, "zone=%s" % SceneRouter.current_zone_id)
	return zone_ok


func _load_scene(path: String, expected_name: String) -> bool:
	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		_expect("смена сцены '%s'" % path, false, "error=%s" % error_string(error))
		return false
	return await _wait_scene_name(expected_name, 600)


func _wait_scene_name(expected_name: String, frames: int = 600) -> bool:
	for _i: int in frames:
		var scene := get_tree().current_scene
		if scene != null and scene.name == expected_name:
			return true
		await get_tree().process_frame
	return false


func _wait_zone(zone_id: StringName, frames: int = 360) -> bool:
	for _i: int in frames:
		if SceneRouter.current_zone_id == zone_id and not SceneRouter.is_loading:
			return true
		await get_tree().process_frame
	return SceneRouter.current_zone_id == zone_id and not SceneRouter.is_loading


func _wait_process(frames: int) -> void:
	for _i: int in frames:
		await get_tree().process_frame


func _wait_physics(frames: int) -> void:
	for _i: int in frames:
		await get_tree().physics_frame


func _cleanup_dir() -> void:
	var directory: DirAccess = DirAccess.open(TEST_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for dir_name: String in directory.get_directories():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR.path_join(dir_name)))


func _report() -> void:
	print("[FIX4AB] SUMMARY pass=%d fail=%d" % [_pass, _fail])
	print("[FIX4AB] RESULT=%s" % ("PASS" if _fail == 0 else "FAIL"))
