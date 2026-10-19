extends Node
## QA T-37 (повторный прогон, ревизия 48de7dc): сквозной e2e-прогон как игрок.
## Запуск: godot --headless --path . res://tests/e2e/qa_e2e.tscn
##
## В отличие от прогона на c7c0d62 способности получаются физическим входом
## в AbilityPickup, враги берутся из собранных зон (EnemySpawner), а выбор
## фракции проверяется в сюжетном потоке (Main -> FactionChoice).
## После проверки боевого потока оставшиеся враги убираются QA-изоляцией,
## чтобы последующие шаги (костёр/смерть/боссы) не зависели от случайного AI.

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")
const PLAYER_GROUP: StringName = &"player"

var _results: Array[Dictionary] = []
var _main: Node = null
var _menu: MainMenu = null
var _dummy_scene: Node = null
var _phase_events: Array[String] = []
var _combat_xp_before: int = 0
var _combat_xp_after: int = 0


func _ready() -> void:
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	_run.call_deferred()


func _on_boss_phase_changed(boss_id: StringName, phase_index: int, title: String) -> void:
	_phase_events.append("%s:%d:%s" % [boss_id, phase_index, title])


func _run() -> void:
	await _stage_menu()
	await _stage_remap_from_settings()
	await _stage_navigation_from_menu()
	await _stage_start_game()
	await _stage_zone_1()
	await _stage_teacher_training()
	await _stage_ability_pickup(&"double_jump", "zone_01_village")
	await _stage_enemy_combat()
	await _stage_journal_factions_keys()
	await _stage_campfire_save()
	await _stage_death_corpse()
	await _stage_dialogue_faction()
	await _stage_bosses_and_ending()
	_report()
	await _teardown()
	get_tree().quit(0)


## QA-гигиена: перед выходом освобождаем смонтированные сцены, чтобы teardown
## движка не падал на осиротевших узлах/ресурсах (N6).
func _teardown() -> void:
	get_tree().paused = false
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		_main = null
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	if _dummy_scene != null and is_instance_valid(_dummy_scene):
		_dummy_scene.queue_free()
		_dummy_scene = null
	await _wait_process(5)
	await _wait_physics(2)


func _check(step: String, ok: bool, detail: String = "") -> bool:
	_results.append({"step": step, "ok": ok, "detail": detail})
	print("[E2E] %s %s%s" % ["PASS" if ok else "FAIL", step, (" — " + detail) if detail else ""])
	return ok


func _player() -> Player:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(PLAYER_GROUP)
	for node: Node in nodes:
		if node is Player:
			return node as Player
	return null


func _key(keycode: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap_key(keycode: Key) -> void:
	_key(keycode, true)
	await get_tree().process_frame
	_key(keycode, false)
	await get_tree().process_frame


func _joy_button(index: JoyButton, pressed: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)


func _wait_physics(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame


func _wait_process(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ------------------------------------------------------------------------------
# 1. Меню
# ------------------------------------------------------------------------------

func _stage_menu() -> void:
	_dummy_scene = Node.new()
	_dummy_scene.name = "QaDummyScene"
	get_tree().root.add_child(_dummy_scene)
	get_tree().current_scene = _dummy_scene

	_menu = MAIN_MENU_SCENE.instantiate() as MainMenu
	add_child(_menu)
	await _wait_process(3)

	_check("menu: MainMenu открыт", _menu.is_open(), "view=%d" % _menu.get_view())
	var items := _menu.get_menu_items()
	_check("menu: пункты меню построены", items.size() >= 5, "items=%d" % items.size())
	var start_focus := _menu.get_focused_index()
	_check("menu: начальный фокус на пункте меню", start_focus >= 0, "focus=%d" % start_focus)

	await _tap_key(KEY_DOWN)
	var after_down := _menu.get_focused_index()
	await _tap_key(KEY_UP)
	var after_up := _menu.get_focused_index()
	_check("menu: навигация клавиатурой (вниз/вверх)", after_down != start_focus and after_up == start_focus,
		"start=%d down=%d up=%d" % [start_focus, after_down, after_up])

	_joy_button(JOY_BUTTON_DPAD_DOWN, true)
	await get_tree().process_frame
	_joy_button(JOY_BUTTON_DPAD_DOWN, false)
	await get_tree().process_frame
	var joy_down := _menu.get_focused_index()
	_joy_button(JOY_BUTTON_DPAD_UP, true)
	await get_tree().process_frame
	_joy_button(JOY_BUTTON_DPAD_UP, false)
	await get_tree().process_frame
	var joy_up := _menu.get_focused_index()
	_check("menu: навигация геймпадом (D-pad вниз/вверх)", joy_down != start_focus and joy_up == start_focus,
		"start=%d down=%d up=%d" % [start_focus, joy_down, joy_up])


# ------------------------------------------------------------------------------
# 2. Ремап из настроек (B5 / AC-01.3)
# ------------------------------------------------------------------------------

func _stage_remap_from_settings() -> void:
	_menu.show_view(MainMenu.View.SETTINGS)
	await _wait_process(3)
	var settings := _menu.get_settings_view()
	_check("настройки: экран открыт", settings != null and settings.is_open())
	if settings == null:
		return
	var remap_index: int = settings.ROW_ORDER.find(settings.ROW_REMAP)
	var row = settings.get_row(remap_index)
	_check("настройки: строка «Управление» активна", row != null and not row.disabled,
		"disabled=%s reason='%s'" % [str(row.disabled) if row != null else "n/a",
		str(row.disabled_reason) if row != null else "n/a"])

	settings.focus_row(remap_index)
	await get_tree().process_frame
	await _tap_key(KEY_ENTER)
	await _wait_process(3)
	var remap := _menu.get_remap_view()
	_check("ремап: открывается из строки «Управление»", remap != null and remap.is_open(),
		"open=%s" % (str(remap.is_open()) if remap != null else "n/a"))
	if remap != null and remap.is_open():
		var actions: Array[StringName] = remap.get_actions()
		_check("ремап: действия ввода перечислены", actions.has(&"move_left") and actions.has(&"attack"),
			"actions=%d" % actions.size())
		_check("ремап: добавлены journal/factions", actions.has(&"journal") and actions.has(&"factions"))
		await _tap_key(KEY_ESCAPE)
		await _wait_process(3)
		_check("ремап: закрывается Esc и возвращает настройки",
			not remap.is_open() and settings.is_open(), "remap_open=%s settings_open=%s" %
			[str(remap.is_open()), str(settings.is_open())])


func _stage_navigation_from_menu() -> void:
	_menu.show_view(MainMenu.View.MAIN)
	await _wait_process(3)
	_check("menu: возврат в главное меню", _menu.get_view() == MainMenu.View.MAIN)


# ------------------------------------------------------------------------------
# 3. Новая игра
# ------------------------------------------------------------------------------

func _stage_start_game() -> void:
	_menu.focus_item(1)
	await get_tree().process_frame
	await _tap_key(KEY_ENTER)
	for i: int in 180:
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == "Main":
			break
	var main_ok: bool = get_tree().current_scene != null and get_tree().current_scene.name == "Main"
	_check("menu: «Новая игра» → Main.tscn", main_ok,
		"current=%s" % (get_tree().current_scene.name if get_tree().current_scene != null else "null"))
	if not main_ok:
		return
	_main = get_tree().current_scene
	await _wait_process(6)
	await _wait_physics(6)
	_check("загрузка: зона 1 активна", SceneRouter.current_zone_id == &"zone_01_village",
		"zone=%s load=%.3f s" % [SceneRouter.current_zone_id, SceneRouter.last_load_seconds])
	_check("новая игра: способностей ещё нет", GameState.get_abilities().is_empty(),
		"abilities=%s" % str(GameState.get_abilities()))


# ------------------------------------------------------------------------------
# 4. Зона 1: спавн, движение, прыжок, HUD
# ------------------------------------------------------------------------------

func _stage_zone_1() -> void:
	if _main == null:
		return
	var player := _player()
	_check("зона 1: игрок заспавнен", player != null)
	if player == null:
		return
	var start_x: float = player.global_position.x
	Input.action_press(&"move_right")
	await _wait_physics(20)
	Input.action_release(&"move_right")
	var moved_x: float = player.global_position.x
	_check("управление: движение вправо", moved_x > start_x + 10.0,
		"x %.1f → %.1f" % [start_x, moved_x])

	await _wait_physics(10)
	var ground_y: float = player.global_position.y
	Input.action_press(&"jump")
	await _wait_physics(1)
	Input.action_release(&"jump")
	await _wait_physics(14)
	var apex_y: float = player.global_position.y
	_check("управление: прыжок", apex_y < ground_y - 8.0,
		"y %.1f → %.1f" % [ground_y, apex_y])

	var hud := _main.get_node_or_null("HUD")
	_check("HUD смонтирован", hud != null and hud.visible)
	_check("Campfire UI смонтирован", _main.get_node_or_null("Campfire") != null)
	_check("DialogueScreen смонтирован", _main.get_node_or_null("DialogueScreen") != null)
	_check("DeathHandler смонтирован", get_tree().get_first_node_in_group(&"death_handler") != null)


# ------------------------------------------------------------------------------
# 4b. Учитель в хабе: панель, тренировка, предусловия (N3, AC-08.1/08.2)
# ------------------------------------------------------------------------------

func _stage_teacher_training() -> void:
	if _main == null:
		return
	var teacher := SceneRouter.current_zone.get_node_or_null("NPCs/TeacherQuartermaster") as Teacher
	_check("N3: учитель в хабе (зона 1)", teacher != null,
		"teachers=%d" % get_tree().get_nodes_in_group(&"teachers").size())
	if teacher == null:
		return
	GameState.add_learning_points(50)
	var player := _player()
	if player == null:
		return
	player.global_position = teacher.global_position
	player.velocity = Vector2.ZERO
	await _wait_physics(3)
	await _tap_key(KEY_E)
	await _wait_process(4)
	_check("N3: interact открывает панель учителя", teacher.is_open() and get_tree().paused,
		"open=%s paused=%s" % [str(teacher.is_open()), str(get_tree().paused)])

	var strength_before: int = GameState.get_stat(&"strength")
	var training := teacher.get_training_info()
	var result := teacher.train()
	_check("AC-08.1: тренировка повышает характеристику на 1",
		bool(result.get("ok", false)) and GameState.get_stat(&"strength") == strength_before + 1,
		"strength %d → %d cost=%s" % [strength_before, GameState.get_stat(&"strength"),
		str(training.get("cost", -1))])
	_check("AC-08.1: стоимость следующего шага растёт",
		int(result.get("next_cost", -1)) > int(result.get("cost_paid", -1)),
		"paid=%s next=%s" % [str(result.get("cost_paid")), str(result.get("next_cost"))])

	var skill := teacher.get_skill_info(&"power_strike")
	_check("AC-08.2: навык с невыполненным предусловием недоступен",
		not bool(skill.get("available", true)) and not bool(skill.get("prerequisites_met", true))
		and String(skill.get("reason", "")).contains("8"),
		"requires=%s reason='%s'" % [str(skill.get("requires", {})), str(skill.get("reason", ""))])
	var points_before: int = GameState.learning_points
	var learned := teacher.learn_skill(&"power_strike")
	_check("AC-08.2: недоступный навык не списывает очки",
		not bool(learned.get("ok", true)) and GameState.learning_points == points_before,
		"ok=%s points=%d" % [str(learned.get("ok")), GameState.learning_points])

	await _tap_key(KEY_ESCAPE)
	await _wait_process(3)
	_check("N3: Esc закрывает панель и снимает паузу",
		not teacher.is_open() and not get_tree().paused,
		"open=%s paused=%s" % [str(teacher.is_open()), str(get_tree().paused)])


# ------------------------------------------------------------------------------
# 5. Способности: физический подбор в мире (B1 / US-02)
# ------------------------------------------------------------------------------

func _find_pickup(ability_id: StringName) -> AbilityPickup:
	var zone := SceneRouter.current_zone
	if zone == null:
		return null
	for node: Node in zone.find_children("*", "", true, false):
		if node is AbilityPickup and (node as AbilityPickup).ability_id == ability_id:
			return node as AbilityPickup
	return null


func _collect_pickup(ability_id: StringName) -> bool:
	var player := _player()
	var pickup := _find_pickup(ability_id)
	if player == null or pickup == null:
		return false
	# Подходим как игрок: встаём слева и идём вправо в область подбора.
	player.global_position = pickup.global_position + Vector2(-16, 0)
	player.velocity = Vector2.ZERO
	await _wait_physics(3)
	Input.action_press(&"move_right")
	await _wait_physics(14)
	Input.action_release(&"move_right")
	await _wait_physics(3)
	if not pickup.is_collected():
		# Физика могла не зафиксировать вход — ставим игрока точно в область.
		player.global_position = pickup.global_position
		await _wait_physics(4)
	return pickup.is_collected() or GameState.has_ability(ability_id)


func _stage_ability_pickup(ability_id: StringName, zone_label: String) -> void:
	if _main == null:
		return
	var pickup := _find_pickup(ability_id)
	_check("способности %s: точка подбора в %s" % [ability_id, zone_label], pickup != null,
		"pickup=%s" % (str(pickup.name) if pickup != null else "null"))
	if pickup == null:
		return
	if ability_id == &"wall_climb":
		var dash_gate := SceneRouter.current_zone.get_node_or_null("Props/DashGate") as AbilityGate
		_check("SPEC §4.1: wall_climb — источник optional_secret в зоне 2",
			str(pickup.get_meta(&"source", &"")) == "optional_secret",
			"source=%s zone=%s" % [str(pickup.get_meta(&"source", &"")), str(SceneRouter.current_zone_id)])
		_check("SPEC §4.1: wall_climb за dash-gate (опциональный секрет)",
			dash_gate != null and dash_gate.is_open()
			and pickup.global_position.x > dash_gate.global_position.x,
			"pickup_x=%.0f gate_x=%s open=%s" % [pickup.global_position.x,
			str(dash_gate.global_position.x) if dash_gate != null else "n/a",
			str(dash_gate.is_open()) if dash_gate != null else "n/a"])
	var before := GameState.has_ability(ability_id)
	var ok := await _collect_pickup(ability_id)
	_check("способности %s: получена игроком (вход в область)" % ability_id,
		ok and not before and GameState.has_ability(ability_id),
		"before=%s after=%s abilities=%s" % [str(before), str(GameState.has_ability(ability_id)),
		str(GameState.get_abilities())])

	var gate_name: String = ""
	match ability_id:
		&"double_jump":
			gate_name = "Props/Rubble"
		&"dash":
			gate_name = "Props/DashGate"
		&"wall_climb":
			# N5/SPEC §4.1: wall_climb — опциональный секрет зоны 2; его gate
			# (WallClimbGate) живёт в зоне 3 и проверяется после перехода.
			gate_name = ""
	if gate_name != "":
		var gate := SceneRouter.current_zone.get_node_or_null(gate_name) as AbilityGate
		await _wait_physics(3)
		_check("способности %s: gate %s открыт" % [ability_id, gate_name],
			gate != null and gate.is_open(),
			"open=%s" % (str(gate.is_open()) if gate != null else "n/a"))


# ------------------------------------------------------------------------------
# 6. Бой с обычными врагами из зоны (B2 / AC-03.1)
# ------------------------------------------------------------------------------

func _stage_enemy_combat() -> void:
	if _main == null:
		return
	var zone := SceneRouter.current_zone
	var spawner := zone.get_node_or_null("Enemies/EnemySpawner") as EnemySpawner
	_check("враги: EnemySpawner в зоне 1", spawner != null)
	if spawner == null:
		return
	var alive: Array[Enemy] = spawner.get_alive_enemies()
	_check("враги: обычные враги заспавнены", alive.size() >= 4, "alive=%d" % alive.size())
	if alive.is_empty():
		return
	var enemy: Enemy = alive[0]
	var xp_before: int = GameState.xp
	_check("враги: у врага есть визуал и HP", enemy.is_visible_in_tree() and enemy.hp > 0.0,
		"%s hp=%.1f" % [str(enemy.name), enemy.hp])

	var player := _player()
	if player == null:
		return
	GameState.reset_hp()
	var hp_before: float = enemy.hp
	var hit: bool = false
	for attempt: int in 6:
		if not is_instance_valid(enemy) or enemy.is_dead:
			break
		player.global_position = enemy.global_position + Vector2(-14, 0)
		player.velocity = Vector2.ZERO
		player.facing = 1
		GameState.heal_hp(100.0)
		var attack_event := InputEventKey.new()
		attack_event.physical_keycode = KEY_J
		attack_event.keycode = KEY_J
		attack_event.pressed = true
		Input.parse_input_event(attack_event)
		await _wait_physics(2)
		var release_event := attack_event.duplicate() as InputEventKey
		release_event.pressed = false
		Input.parse_input_event(release_event)
		await _wait_physics(18)
		if enemy.hp < hp_before:
			hit = true
			hp_before = enemy.hp
	_check("бой: атака игрока ранит врага в мире", hit or (is_instance_valid(enemy) and enemy.is_dead),
		"hp=%.1f dead=%s" % [enemy.hp if is_instance_valid(enemy) else -1.0,
		str(enemy.is_dead) if is_instance_valid(enemy) else "freed"])

	# Добивание для проверки опыта; если враг уже мёртв — XP уже начислен.
	var guard: int = 0
	while is_instance_valid(enemy) and not enemy.is_dead and guard < 10:
		guard += 1
		player.global_position = enemy.global_position + Vector2(-14, 0)
		player.facing = 1
		GameState.heal_hp(100.0)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_J
		ev.keycode = KEY_J
		ev.pressed = true
		Input.parse_input_event(ev)
		await _wait_physics(2)
		var rev := ev.duplicate() as InputEventKey
		rev.pressed = false
		Input.parse_input_event(rev)
		await _wait_physics(20)
	# Смерть врага проигрывается ~1.1 c; EventBus.enemy_died эмитится в
	# `_finish_death()`, поэтому опыт появляется только после анимации.
	await _wait_physics(90)
	_combat_xp_before = xp_before
	_combat_xp_after = GameState.xp
	_check("бой: враг побеждён, опыт начислен", GameState.xp > xp_before,
		"xp %d → %d" % [xp_before, GameState.xp])

	# QA-изоляция: убираем оставшихся врагов, чтобы AI не влиял на
	# последующие проверки костра/смерти/боссов.
	for other: Enemy in spawner.get_alive_enemies():
		if is_instance_valid(other) and other != enemy:
			other.queue_free()
	await _wait_physics(3)


# ------------------------------------------------------------------------------
# 7. Журнал и фракции по клавишам (B6)
# ------------------------------------------------------------------------------

func _stage_journal_factions_keys() -> void:
	if _main == null:
		return
	var journal := _main.get_node("Journal") as JournalScreen
	var factions := _main.get_node("Factions") as FactionsScreen
	var inventory := _main.get_node("Inventory") as InventoryScreen

	await _tap_key(KEY_N)
	await _wait_process(2)
	_check("журнал: открывается клавишей N в игре", journal.is_open() and get_tree().paused,
		"open=%s paused=%s" % [str(journal.is_open()), str(get_tree().paused)])
	await _tap_key(KEY_N)
	await _wait_process(2)
	_check("журнал: закрывается повторной N", not journal.is_open() and not get_tree().paused,
		"open=%s paused=%s" % [str(journal.is_open()), str(get_tree().paused)])

	await _tap_key(KEY_F)
	await _wait_process(2)
	_check("фракции: открываются клавишей F в игре", factions.is_open() and get_tree().paused,
		"open=%s paused=%s" % [str(factions.is_open()), str(get_tree().paused)])
	await _tap_key(KEY_F)
	await _wait_process(2)
	_check("фракции: закрываются повторной F", not factions.is_open() and not get_tree().paused,
		"open=%s paused=%s" % [str(factions.is_open()), str(get_tree().paused)])

	await _tap_key(KEY_I)
	await _wait_process(2)
	_check("инвентарь: открывается клавишей I", inventory.is_open(),
		"open=%s" % str(inventory.is_open()))
	await _tap_key(KEY_I)
	await _wait_process(2)
	_check("инвентарь: закрывается повторной I", not inventory.is_open())


# ------------------------------------------------------------------------------
# 8. Костёр → сохранение
# ------------------------------------------------------------------------------

func _stage_campfire_save() -> void:
	if _main == null:
		return
	var zone := SceneRouter.current_zone
	var player := _player()
	var bonfire := zone.get_node_or_null("Props/Bonfire") as Bonfire
	if player == null or bonfire == null:
		_check("костёр: объекты найдены", false)
		return
	player.global_position = bonfire.global_position + Vector2(0, -10)
	player.velocity = Vector2.ZERO
	await _wait_physics(3)
	var interaction := player.get_node_or_null("Interaction") as PlayerInteraction
	_check("костёр: interact находит костёр", interaction != null and interaction.get_nearest_interactable() == bonfire)
	var opened: bool = interaction != null and interaction.try_interact()
	await _wait_process(2)
	var campfire := _main.get_node("Campfire") as Campfire
	_check("костёр: UI открыт", opened and campfire.is_open())
	_check("костёр: чекпоинт активирован", GameState.has_checkpoint(),
		"zone=%s pos=%s" % [GameState.respawn_zone_id, str(GameState.respawn_position)])

	campfire.select_answer(0)
	await _wait_process(2)
	_check("костёр: экран слотов", campfire.get_state_name() == "slots", campfire.get_state_name())
	campfire.select_slot(1)
	await _wait_process(4)
	var meta := SaveManager.get_slot_metadata(1)
	_check("сохранение: слот 1 записан", bool(meta.get("valid", false)),
		"meta=%s" % str(meta))
	_check("сохранение: active_slot=1", GameState.active_slot == 1, "slot=%d" % GameState.active_slot)
	campfire.close()
	await _wait_process(2)

	GameState.currency = 777
	GameState.hp = 1.0
	var loaded := SaveManager.load_slot(1)
	await _wait_process(3)
	_check("загрузка: слот 1 читается", loaded)
	_check("загрузка: валюта восстановлена", GameState.currency != 777,
		"currency=%d" % GameState.currency)


# ------------------------------------------------------------------------------
# 9. Смерть → экран смерти → возрождение → corpse run
# ------------------------------------------------------------------------------

func _stage_death_corpse() -> void:
	if _main == null:
		return
	var zone := SceneRouter.current_zone
	var player := _player()
	if player == null:
		return
	var bonfire := zone.get_node_or_null("Props/Bonfire") as Bonfire
	if bonfire != null:
		bonfire.activate_checkpoint()
	GameState.add_item(&"iron_dagger")
	GameState.add_item(&"healing_herb")
	GameState.currency = 42
	var death_position: Vector2 = player.global_position
	player.kill()
	await _wait_physics(3)
	var handler := get_tree().get_first_node_in_group(&"death_handler") as DeathHandler
	_check("смерть: DeathHandler перехватил", handler != null and handler.phase == &"dying",
		"phase=%s" % (handler.phase if handler != null else "null"))
	if handler == null:
		return
	handler.tick(GameState.balance.t_death + 0.1)
	await _wait_process(3)
	var screen := _main.get_node("Overlay/DeathScreen") as DeathScreen
	_check("смерть: экран смерти показан", screen != null and screen.is_shown())
	_check("смерть: инвентарь ушёл в corpse", GameState.has_corpse() and int(GameState.get_corpse_info()["items_count"]) == 2,
		"corpse=%s" % str(GameState.get_corpse_info()))
	_check("смерть: валюта ушла в corpse", GameState.currency == 0 and int(GameState.get_corpse_info()["currency"]) == 42)
	screen.respawn_now()
	await _wait_process(3)
	_check("смерть: возрождение у костра", not GameState.death_active and GameState.hp > 0.0,
		"hp=%.1f pos=%s" % [GameState.hp, str(player.global_position)])
	var corpse := get_tree().get_first_node_in_group(&"corpses") as Corpse
	var corpse_at: String = str(corpse.global_position) if corpse != null else "n/a"
	_check("corpse run: метка заспавнена", corpse != null,
		"at=%s death=%s" % [corpse_at, str(death_position)])
	if corpse != null:
		player.global_position = corpse.global_position
		await _wait_physics(5)
		_check("corpse run: инвентарь и валюта подобраны",
			GameState.get_inventory().size() == 2 and GameState.currency == 42,
			"items=%s currency=%d" % [str(GameState.get_inventory()), GameState.currency])


# ------------------------------------------------------------------------------
# 10. Диалог/квест → сюжетный выбор фракции (B4)
# ------------------------------------------------------------------------------

func _stage_dialogue_faction() -> void:
	if _main == null:
		return
	var zone := SceneRouter.current_zone
	var player := _player()
	if player == null:
		return
	var keeper := zone.get_node_or_null("NPCs/KeeperNpc") as DialogueNpc
	var dialogue := _main.get_node("DialogueScreen") as DialogueScreen
	if keeper == null:
		_check("диалог: NPC хранителя в зоне 1", false)
		return
	player.global_position = keeper.global_position
	await _wait_physics(2)
	var interaction := player.get_node_or_null("Interaction") as PlayerInteraction
	var opened: bool = interaction != null and interaction.try_interact()
	await _wait_process(2)
	var runner_id: String = "null"
	if dialogue.get_runner() != null and dialogue.get_runner().data != null:
		runner_id = str(dialogue.get_runner().data.id)
	_check("диалог: открывается у NPC", opened and dialogue.is_open(), "runner=%s" % runner_id)
	if dialogue.is_open():
		var before := GameState.get_faction_reputation(&"free")
		dialogue.select_answer(0)
		await _wait_process(2)
		var quests := Journal.get_active_quests()
		_check("квест: взят у NPC", not quests.is_empty(), "active=%s" % str(quests))
		dialogue.close()
		await _wait_process(2)
		# Повторный разговор: в узле start доступен отчёт по активному квесту.
		opened = interaction != null and interaction.try_interact()
		await _wait_process(2)
		_check("диалог: повторное открытие для отчёта", opened and dialogue.is_open())
		dialogue.select_answer(1)
		await _wait_process(3)
		var completed := Journal.get_completed_quests()
		_check("квест: завершён у NPC", not completed.is_empty(), "completed=%s" % str(completed))
		_check("фракции: репутация изменилась", GameState.get_faction_reputation(&"free") != before,
			"free %d → %d" % [before, GameState.get_faction_reputation(&"free")])
		dialogue.close()
		await _wait_process(5)

	var choice := _main.get_node_or_null("FactionChoice") as FactionChoice
	_check("фракции: экран выбора смонтирован", choice != null)
	_check("фракции: выбор открывается сюжетным триггером после квеста",
		choice != null and choice.is_open() and get_tree().paused,
		"open=%s paused=%s" % [str(choice.is_open()) if choice != null else "n/a", str(get_tree().paused)])
	if choice == null or not choice.is_open():
		return

	# Fix-3a/N1: Esc на экране выбора закрывает его без присяги, но не «съедает»
	# выбор навсегда: флаг запроса снимается, повторный разговор с NPC открывает
	# экран снова. Проверяем оба пути отмены (Esc и B геймпада).
	await _tap_key(KEY_ESCAPE)
	await _wait_process(4)
	_check("N1: Esc закрывает выбор без присяги", not choice.is_open() and not FactionManager.is_faction_chosen(),
		"open=%s chosen=%s" % [str(choice.is_open()), str(FactionManager.is_faction_chosen())])
	_check("N1: отмена сбрасывает запрос Main", not bool(_main.get("_faction_choice_requested")),
		"requested=%s pending=%s" % [str(_main.get("_faction_choice_requested")),
		str(_main.get("_faction_choice_pending"))])
	player.global_position = keeper.global_position
	await _wait_physics(2)
	opened = interaction != null and interaction.try_interact()
	await _wait_process(2)
	if opened and dialogue.is_open():
		dialogue.close()
		await _wait_process(6)
	_check("N1: после Esc выбор снова открывается разговором с NPC", choice.is_open(),
		"open=%s" % str(choice.is_open()))

	if choice.is_open():
		_joy_button(JOY_BUTTON_B, true)
		await get_tree().process_frame
		_joy_button(JOY_BUTTON_B, false)
		await _wait_process(4)
		_check("N1: B геймпада закрывает выбор без присяги",
			not choice.is_open() and not FactionManager.is_faction_chosen(),
			"open=%s chosen=%s" % [str(choice.is_open()), str(FactionManager.is_faction_chosen())])
		# Второй повтор: выбор должен открываться столько раз, сколько нужно.
		player.global_position = keeper.global_position
		await _wait_physics(2)
		opened = interaction != null and interaction.try_interact()
		await _wait_process(2)
		if opened and dialogue.is_open():
			dialogue.close()
			await _wait_process(6)
		_check("N1: после B выбор снова открывается", choice.is_open(),
			"open=%s" % str(choice.is_open()))

	if not choice.is_open():
		_check("N1: выбор доступен для подтверждения после отмен", false)
		return

	# Игровой путь: выбрать «free» и подтвердить Enter (фокус на Confirm).
	choice.select_faction(&"free")
	choice.get_confirm_button().grab_focus()
	await _wait_process(2)
	await _tap_key(KEY_ENTER)
	await _wait_process(3)
	_check("фракции: выбор сохранён", GameState.chosen_faction == &"free",
		"chosen=%s paused=%s" % [str(GameState.chosen_faction), str(get_tree().paused)])
	_check("фракции: экран закрылся и игра снята с паузы",
		not choice.is_open() and not get_tree().paused,
		"open=%s paused=%s" % [str(choice.is_open()), str(get_tree().paused)])


# ------------------------------------------------------------------------------
# 11. 5 боссов, видимость и концовка
# ------------------------------------------------------------------------------

func _stage_bosses_and_ending() -> void:
	if _main == null:
		return
	var boss_ids: Array[StringName] = []

	var boss1: StringName = await _fight_current_boss(&"zone_01_village")
	if boss1 != &"":
		boss_ids.append(boss1)
	await _transition_to(&"zone_02_swamp", &"gate")

	var boss2: StringName = await _fight_current_boss(&"zone_02_swamp")
	if boss2 != &"":
		boss_ids.append(boss2)
	await _stage_ability_pickup(&"dash", "zone_02_swamp")
	# Fix-3a/N5 + SPEC §4.1: wall_climb — опциональный секрет зоны 2 за dash-gate.
	await _stage_ability_pickup(&"wall_climb", "zone_02_swamp")
	await _transition_to(&"zone_03_mountains", &"east_gate")
	_check("SPEC §4.1: в зоне 3 нет дублирующего pickup wall_climb",
		_find_pickup(&"wall_climb") == null, "pickup должен быть только в зоне 2")
	var zone3_wall_gate := SceneRouter.current_zone.get_node_or_null("Props/WallClimbGate") as AbilityGate
	_check("AC-04.3: WallClimbGate зоны 3 открыт после получения wall_climb",
		zone3_wall_gate != null and zone3_wall_gate.is_open(),
		"open=%s" % (str(zone3_wall_gate.is_open()) if zone3_wall_gate != null else "n/a"))

	var boss3: StringName = await _fight_current_boss(&"zone_03_mountains")
	if boss3 != &"":
		boss_ids.append(boss3)
	await _transition_to(&"zone_04_ruins", &"to_ruins")

	var boss4: StringName = await _fight_current_boss(&"zone_04_ruins")
	if boss4 != &"":
		boss_ids.append(boss4)
	await _transition_to(&"zone_05_finale", &"to_finale")

	var boss5: StringName = await _fight_current_boss(&"zone_05_finale")
	if boss5 != &"":
		boss_ids.append(boss5)

	_check("боссы: побеждено 5 боссов", boss_ids.size() == 5 and GameState.get_bosses_defeated().size() == 5,
		"killed=%s state=%s" % [str(boss_ids), str(GameState.get_bosses_defeated())])
	_check("боссы: фазы сменялись", not _phase_events.is_empty(), str(_phase_events))

	var finale := SceneRouter.current_zone
	var hook := finale.get_node_or_null("EndingExit")
	_check("финал: EndingExit есть", hook != null)
	if hook != null and hook.has_method(&"request_ending"):
		var faction: StringName = hook.request_ending()
		_check("финал: концовка учитывает выбранную фракцию", faction == &"free",
			"faction=%s chosen=%s" % [str(faction), str(GameState.chosen_faction)])
		await _wait_seconds(1.2)
		var seq := finale.get_node_or_null("EndingSequence")
		var ending_id: StringName = seq.get_ending_id() if seq != null else &""
		_check("финал: концовка запущена", ending_id != &"", "id=%s" % str(ending_id))
		_check("финал: фракционная концовка free", ending_id == &"ending_free",
			"id=%s (ожидалось ending_free)" % str(ending_id))
		if seq != null:
			seq.advance()
			await _wait_seconds(0.2)
			for i: int in 80:
				seq.advance()
				await get_tree().process_frame
				if seq.is_finished():
					break
			_check("финал: титры завершены", seq.is_finished(),
				"state=%s" % seq.get_state_name())


func _is_arena_visible(arena: Node) -> bool:
	if arena == null or not (arena is CanvasItem):
		return false
	var item := arena as CanvasItem
	var boss: BossBase = arena.get_boss() if arena.has_method(&"get_boss") else null
	var boss_visible: bool = boss != null and boss.is_visible_in_tree() and boss.modulate.a > 0.01
	return item.is_visible_in_tree() and item.self_modulate.a > 0.99 and item.modulate.a > 0.99 and boss_visible


func _fight_current_boss(label: StringName) -> StringName:
	var zone := SceneRouter.current_zone
	if zone == null:
		_check("босс %s: зона активна" % label, false)
		return &""
	# QA-изоляция: обычные враги не должны мешать замеру босс-фаз.
	for node: Node in zone.find_children("*", "", true, false):
		if node is Enemy and not (node is BossBase):
			(node as Enemy).queue_free()
	await _wait_physics(2)

	var arena := _find_boss_arena(zone)
	_check("босс %s: арена найдена" % label, arena != null)
	if arena == null:
		return &""
	var boss: BossBase = arena.get_boss()
	_check("босс %s: арена и босс видимы" % label, _is_arena_visible(arena),
		"arena.self_modulate.a=%.2f boss=%s boss_visible=%s" % [
			(arena as CanvasItem).self_modulate.a if arena is CanvasItem else -1.0,
			str(boss != null),
			str(boss.is_visible_in_tree() if boss != null else false)])

	if not arena.is_fight_active():
		var player := _player()
		if player != null:
			player.global_position = arena.global_position + arena.bounds.position + arena.bounds.size * 0.5
			await _wait_physics(6)
		if not arena.is_fight_active():
			arena.start_fight()
			await _wait_physics(4)
	_check("босс %s: бой начался" % label, arena.is_fight_active())
	if boss == null:
		_check("босс %s: босс существует" % label, false)
		return &""
	var boss_id: StringName = boss.data.id
	_check("босс %s: %s на арене" % [label, boss_id], boss.fight_active,
		"hp=%.1f phase=%d" % [boss.hp, boss.phase_index])

	# Переход фазы: HP 60% пересекает порог 66% (AC-03.4).
	boss.hp = boss.data.max_hp * 0.6
	boss._on_hurtbox_damaged(Damage.create(1.0, Vector2.ZERO, 0.05))
	await _wait_physics(3)
	_check("босс %s: смена фазы" % label, boss.phase_index >= 1,
		"phase=%d events=%s" % [boss.phase_index, str(_phase_events)])

	# Добивание; смерть длится boss_death_duration = 1.1 c.
	await _wait_physics(30)
	boss.hp = 1.0
	boss._on_hurtbox_damaged(Damage.create(999.0, Vector2.ZERO, 0.05))
	await _wait_physics(90)
	_check("босс %s: побеждён" % label, GameState.is_boss_defeated(boss_id),
		"boss=%s state=%s" % [boss_id, str(GameState.get_bosses_defeated())])
	await _wait_physics(5)
	return boss_id


## Физический переход через ZoneExit (как игрок), с замером времени загрузки.
func _transition_to(target_zone: StringName, exit_id: StringName) -> void:
	var zone := SceneRouter.current_zone
	if zone == null or zone.zone_data == null:
		_check("переход %s: активная зона" % target_zone, false)
		return
	var exit_position := Vector2.ZERO
	var found: bool = false
	for e: ZoneExit in zone.zone_data.exits:
		if e != null and e.id == exit_id:
			exit_position = e.position
			found = true
			break
	_check("переход %s: выход %s найден" % [target_zone, exit_id], found)
	if not found:
		return
	var player := _player()
	if player == null:
		_check("переход %s: игрок есть" % target_zone, false)
		return
	player.global_position = exit_position
	player.velocity = Vector2.ZERO
	await _wait_physics(4)
	var ok: bool = false
	for i: int in 240:
		await get_tree().process_frame
		if SceneRouter.current_zone_id == target_zone and not SceneRouter.is_loading:
			ok = true
			break
	_check("переход %s: зона загружена" % target_zone, ok,
		"zone=%s load=%.3f s" % [SceneRouter.current_zone_id, SceneRouter.last_load_seconds])
	_check("переход %s: загрузка ≤ 3 с" % target_zone, SceneRouter.last_load_seconds <= 3.0,
		"%.3f s" % SceneRouter.last_load_seconds)
	await _wait_physics(4)


func _find_boss_arena(node: Node) -> Node:
	for child: Node in node.find_children("*", "", true, false):
		if child.has_method(&"get_boss") and child.has_method(&"start_fight"):
			return child
	return null


func _report() -> void:
	var passed: int = 0
	for r: Dictionary in _results:
		if bool(r["ok"]):
			passed += 1
	print("[E2E] SUMMARY passed=%d failed=%d total=%d" % [passed, _results.size() - passed, _results.size()])
	for r: Dictionary in _results:
		if not bool(r["ok"]):
			print("[E2E] FAILED: %s — %s" % [r["step"], r["detail"]])
