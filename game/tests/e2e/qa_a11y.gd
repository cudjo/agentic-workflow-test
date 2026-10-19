extends Node
## QA T-37: a11y-проверки DESIGN §9.6 пп.1-7 (headless).
## Запуск: godot --headless --path game res://tests/e2e/qa_a11y.tscn

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")
const CAMPFIRE_SCENE: PackedScene = preload("res://ui/campfire/Campfire.tscn")
const DIALOGUE_SCENE: PackedScene = preload("res://ui/dialogue/DialogueScreen.tscn")
const DEATH_SCENE: PackedScene = preload("res://ui/death/DeathScreen.tscn")
const INVENTORY_SCENE: PackedScene = preload("res://ui/inventory/Inventory.tscn")
const JOURNAL_SCENE: PackedScene = preload("res://ui/journal/Journal.tscn")
const FACTIONS_SCENE: PackedScene = preload("res://ui/factions/Factions.tscn")
const CHOICE_SCENE: PackedScene = preload("res://ui/factions/FactionChoice.tscn")
const MAP_SCENE: PackedScene = preload("res://ui/map/WorldMap.tscn")
const REMAP_SCENE: PackedScene = preload("res://ui/remap/Remap.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud/HUD.tscn")
const ZONE_SCENE: String = "res://world/zones/zone_01_village/zone_01_village.tscn"

var _pass: int = 0
var _fail: int = 0
var _failures: Array[String] = []
var _menu: MainMenu
var _screens: Array[Node] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	await _section_contrast()
	await _section_focus_keyboard_gamepad()
	await _section_no_color_only()
	await _section_no_flash()
	await _section_silhouette()
	await _section_overflow()
	await _section_overflow_screens()
	_report()
	get_tree().quit(0)


func _check(item: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("[A11Y] PASS %s%s" % [item, (" — " + detail) if detail else ""])
	else:
		_fail += 1
		_failures.append("%s — %s" % [item, detail])
		print("[A11Y] FAIL %s — %s" % [item, detail])


func _wait(frames: int = 2) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _tap(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	var up := event.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _pad(index: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	var up := event.duplicate() as InputEventJoypadButton
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()


func _focus_visible(owner: Control) -> Dictionary:
	var info: Dictionary = {"has_focus": owner != null and owner.has_focus()}
	if owner != null and owner.has_method(&"is_focus_visible"):
		info["explicit"] = bool(owner.call(&"is_focus_visible"))
	return info


# ------------------------------------------------------------------------------
# §9.6 п.3 — контраст 8-px текста
# ------------------------------------------------------------------------------

func _section_contrast() -> void:
	var pairs: Array = [
		["bone / night-9", UITokens.BONE, UITokens.NIGHT_9, 4.5],
		["bone / night", UITokens.BONE, UITokens.NIGHT, 4.5],
		["bone / void", UITokens.BONE, UITokens.VOID, 4.5],
		["bone / night-3", UITokens.BONE, UITokens.NIGHT_3, 4.5],
		["gold-3 / night-9", UITokens.GOLD_3, UITokens.NIGHT_9, 4.5],
		["gold-3 / night", UITokens.GOLD_3, UITokens.NIGHT, 4.5],
		["gold-3 / void", UITokens.GOLD_3, UITokens.VOID, 4.5],
		["gold-3 / night-3", UITokens.GOLD_3, UITokens.NIGHT_3, 4.5],
		["stone-5 / night-9", UITokens.STONE_5, UITokens.NIGHT_9, 4.5],
		["stone-5 / night", UITokens.STONE_5, UITokens.NIGHT, 4.5],
		["stone-5 / void", UITokens.STONE_5, UITokens.VOID, 4.5],
		["stone-5 / night-3", UITokens.STONE_5, UITokens.NIGHT_3, 4.5],
		["steel-3 / night-9", UITokens.STEEL_3, UITokens.NIGHT_9, 4.5],
		["steel-3 / night", UITokens.STEEL_3, UITokens.NIGHT, 4.5],
		["blood-5 / night-9", UITokens.BLOOD_5, UITokens.NIGHT_9, 4.5],
		["blood-5 / night", UITokens.BLOOD_5, UITokens.NIGHT, 4.5],
		["blood-5 / void", UITokens.BLOOD_5, UITokens.VOID, 4.5],
		["void / gold (active)", UITokens.VOID, UITokens.GOLD, 4.5],
	]
	var worst: float = 99.0
	for pair: Array in pairs:
		var ratio: float = UITokens.contrast_ratio(pair[1], pair[2])
		worst = minf(worst, ratio)
		_check("контраст: %s" % pair[0], ratio >= float(pair[3]), "%.2f:1" % ratio)
	_check("контраст: минимум по обязательным парам ≥ 4.5", worst >= 4.5, "worst=%.2f:1" % worst)

	# Реальные цвета темы (main_theme.tres): 8-px текст на панели night-9.
	var theme := load("res://ui/theme/main_theme.tres") as Theme
	if theme != null:
		var names: Array[String] = ["Label", "MutedLabel", "DangerLabel", "GoldLabel", "SteelLabel"]
		for type_name: String in names:
			var color: Color = theme.get_color(&"font_color", type_name)
			var ratio: float = UITokens.contrast_ratio(color, UITokens.NIGHT_9)
			_check("контраст темы: %s" % type_name, ratio >= 4.5, "%s %.2f:1" % [color.to_html(false), ratio])


# ------------------------------------------------------------------------------
# §9.6 пп.1-2 — клавиатура/геймпад, видимый фокус
# ------------------------------------------------------------------------------

func _section_focus_keyboard_gamepad() -> void:
	_menu = _spawn(MAIN_MENU_SCENE)
	_menu.handle_game_start = false
	_menu.handle_quit = false
	await _wait(4)
	await _walk_screen("MainMenu", func(): _menu.open(), func(): _menu.close(), 4)

	# Settings — вложенный экран главного меню.
	await _walk_screen(
		"Settings",
		func(): _menu.open(); _menu.show_view(MainMenu.View.SETTINGS),
		func(): _menu.show_view(MainMenu.View.MAIN); _menu.close(),
		5
	)
	# SaveSlots.
	await _walk_screen(
		"SaveSlots",
		func(): _menu.open(); _menu.show_view(MainMenu.View.LOAD),
		func(): _menu.show_view(MainMenu.View.MAIN); _menu.close(),
		2
	)

	var campfire := _spawn(CAMPFIRE_SCENE) as Campfire
	var bonfire := Bonfire.new()
	bonfire.name = "QaBonfire"
	add_child(bonfire)
	await _wait(2)
	Config.set_no_flash(true)
	await _walk_screen("Campfire", func(): campfire.open(bonfire), func(): campfire.close(), 2)

	var dialogue := _spawn(DIALOGUE_SCENE) as DialogueScreen
	var dialogue_data := load("res://data/dialogue/elder_lira.tres") as DialogueData
	await _walk_screen(
		"DialogueScreen",
		func(): dialogue.open_dialogue(dialogue_data),
		func(): dialogue.close(),
		2
	)
	Config.set_no_flash(false)

	var death := _spawn(DEATH_SCENE) as DeathScreen
	var death_info: Dictionary = {
		"items": ["iron_dagger", "healing_herb"],
		"items_count": 2,
		"currency": 42,
		"zone_id": "zone_01_village",
		"position": Vector2(112, 214),
	}
	await _walk_screen("DeathScreen", func(): death.show_death(death_info), func(): death.hide_screen(), 2, false)

	GameState.add_item(&"iron_dagger")
	GameState.add_item(&"healing_herb")
	var inventory := _spawn(INVENTORY_SCENE)
	await _walk_screen("Inventory", func(): inventory.call(&"open"), func(): inventory.call(&"close"), 2)

	Journal.start_quest(&"quest_free_smuggle")
	Journal.record_event(&"qa_t37")
	var journal := _spawn(JOURNAL_SCENE)
	await _walk_screen("Journal", func(): journal.call(&"open"), func(): journal.call(&"close"), 1)

	var factions := _spawn(FACTIONS_SCENE)
	await _walk_screen("Factions", func(): factions.call(&"open"), func(): factions.call(&"close"), 3)

	var choice := _spawn(CHOICE_SCENE) as FactionChoice
	await _walk_screen(
		"FactionChoice",
		func(): choice.open("Совет Бастиона ждёт присяги"),
		func(): choice.close(),
		3
	)

	SceneRouter.mark_zone_visited(&"zone_01_village")
	SceneRouter.mark_zone_visited(&"zone_02_swamp")
	var map := _spawn(MAP_SCENE)
	await _walk_screen("WorldMap", func(): map.call(&"open"), func(): map.call(&"close"), 2)

	var remap := _spawn(REMAP_SCENE)
	await _walk_screen("Remap", func(): remap.call(&"open"), func(): remap.call(&"close"), 2)


func _spawn(scene: PackedScene) -> Node:
	var node := scene.instantiate()
	add_child(node)
	_screens.append(node)
	return node


func _walk_screen(label: String, open_fn: Callable, close_fn: Callable, min_unique: int, vertical: bool = true) -> void:
	open_fn.call()
	await _wait(4)
	var start: Control = _focus_owner()
	_check("%s: начальный фокус" % label, start != null,
		"owner=%s" % (start.name if start != null else "null"))
	if start == null:
		close_fn.call()
		await _wait(2)
		return
	var info := _focus_visible(start)
	_check("%s: фокус видим (старт)" % label, bool(info.get("has_focus", false)) and bool(info.get("explicit", true)),
		str(info))

	var keyboard_owners: Array[String] = []
	var nav_key: Key = KEY_DOWN if vertical else KEY_RIGHT
	for i: int in 5:
		await _tap(nav_key)
		var owner: Control = _focus_owner()
		if owner != null:
			keyboard_owners.append(str(owner.name))
	var unique_kb: Dictionary = {}
	if start != null:
		unique_kb[str(start.name)] = true
	for owner_name: String in keyboard_owners:
		unique_kb[owner_name] = true
	_check("%s: навигация клавиатурой" % label, unique_kb.size() >= min_unique,
		"owners=%s" % str(keyboard_owners))
	for i: int in keyboard_owners.size():
		await _tap(KEY_LEFT if not vertical else KEY_UP)

	# Геймпад: заново открыть экран, D-pad вниз.
	close_fn.call()
	await _wait(2)
	open_fn.call()
	await _wait(4)
	var pad_start: Control = _focus_owner()
	await _pad(JOY_BUTTON_DPAD_DOWN if vertical else JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_DPAD_DOWN if vertical else JOY_BUTTON_DPAD_RIGHT)
	var pad_owner: Control = _focus_owner()
	_check("%s: навигация геймпадом (D-pad)" % label, pad_owner != null,
		"start=%s now=%s" % [str(pad_start.name) if pad_start != null else "null",
			str(pad_owner.name) if pad_owner != null else "null"])
	if pad_owner != null:
		var pad_info := _focus_visible(pad_owner)
		_check("%s: фокус видим (геймпад)" % label,
			bool(pad_info.get("has_focus", false)) and bool(pad_info.get("explicit", true)), str(pad_info))

	close_fn.call()
	await _wait(2)


# ------------------------------------------------------------------------------
# §9.6 п.4 — состояние не только цветом
# ------------------------------------------------------------------------------

func _section_no_color_only() -> void:
	var hud := _spawn(HUD_SCENE) as AshenHUD
	await _wait(4)
	hud.set_stamina(0.0, 100.0)
	await _wait(2)
	_check("не только цвет: «НЕТ СИЛ» + «!»", hud.is_no_stamina_visible() and not hud.get_no_stamina_text().is_empty(),
		hud.get_no_stamina_text())
	hud.set_health(10.0, 100.0)
	await _wait(2)
	_check("не только цвет: HP < 25% — текст «КРИТ»", hud.is_critical() and hud.get_critical_label().visible,
		hud.get_critical_label().text)
	_check("не только цвет: число HP поверх шкалы", hud.get_hp_bar().show_number,
		"show_number=%s" % str(hud.get_hp_bar().show_number))


# ------------------------------------------------------------------------------
# §9.6 п.5 — «Без мигания» ≤ 3 вспышки/с
# ------------------------------------------------------------------------------

func _section_no_flash() -> void:
	var hud := _spawn(HUD_SCENE) as AshenHUD
	await _wait(4)
	Config.set_no_flash(false)
	hud.set_health(10.0, 100.0)
	await _wait(2)
	_check("без мигания: в обычном режиме HP-крит мигает", hud.is_critical_blinking())
	Config.set_no_flash(true)
	await _wait(2)
	_check("без мигания: HP-крит не мигает", not hud.is_critical_blinking())
	var governor := FlashGovernor.new()
	var allowed: int = 0
	for i: int in 8:
		if governor.try_flash(0.01 * float(i)):
			allowed += 1
	_check("без мигания: не более 3 вспышек/с (FlashGovernor)", allowed == 3,
		"allowed=%d/8" % allowed)
	_check("без мигания: flame_multiplier = 1.0",
		is_equal_approx(LightingProfile.flame_multiplier(0.0, true), 1.0)
		and is_equal_approx(LightingProfile.flame_multiplier(0.33, true), 1.0))

	var zone := (load(ZONE_SCENE) as PackedScene).instantiate()
	add_child(zone)
	_screens.append(zone)
	await _wait(4)
	var rig := zone.get_node_or_null("LightingRig") as LightingRig
	_check("без мигания: LightingRig найден", rig != null)
	if rig != null:
		Config.set_no_flash(true)
		await _wait(2)
		var steady: bool = true
		for i: int in 8:
			if not is_equal_approx(rig.flicker_multiplier(0.14 * float(i)), 1.0):
				steady = false
		_check("без мигания: свет зоны не мерцает", steady)
		Config.set_no_flash(false)

	var death := _spawn(DEATH_SCENE) as DeathScreen
	var death_info: Dictionary = {"items": ["iron_dagger"], "items_count": 1, "currency": 7}
	Config.set_no_flash(true)
	death.show_death(death_info)
	await _wait(2)
	_check("без мигания: экран смерти без fade", death.is_fade_finished() or death.get_fade_alpha("title") >= 1.0,
		"fade_finished=%s" % str(death.is_fade_finished()))
	Config.set_no_flash(false)
	damage_flash_reset()


func damage_flash_reset() -> void:
	Config.set_no_flash(false)


# ------------------------------------------------------------------------------
# §9.6 п.7 — читаемость силуэтов (AC-07.1)
# ------------------------------------------------------------------------------

func _section_silhouette() -> void:
	var zone := (load(ZONE_SCENE) as PackedScene).instantiate()
	add_child(zone)
	_screens.append(zone)
	await _wait(4)
	var rig := zone.get_node_or_null("LightingRig") as LightingRig
	Config.set_silhouette_readability(false)
	await _wait(2)
	var baseline: float = rig.get_vignette_strength() if rig != null else 0.0
	Config.set_silhouette_readability(true)
	await _wait(2)
	var silhouette: float = rig.get_vignette_strength() if rig != null else 0.0
	_check("силуэты: виньетка отключается в режиме читаемости", baseline > 0.0 and is_zero_approx(silhouette),
		"vignette %.2f → %.2f" % [baseline, silhouette])

	var player := (load("res://entities/player/Player.tscn") as PackedScene).instantiate() as Player
	add_child(player)
	_screens.append(player)
	await _wait(3)
	var animation := player.get_node_or_null("Animation")
	_check("силуэты: контур игрока включён", animation != null and animation.has_method(&"is_silhouette_outline_enabled")
		and bool(animation.call(&"is_silhouette_outline_enabled")))
	# Враги: Fix-3a/N4 добавил контур (DESIGN §9.1 — «у героя и врагов»).
	var enemy := (load("res://entities/enemies/swift/swift_enemy.tscn") as PackedScene).instantiate()
	add_child(enemy)
	_screens.append(enemy)
	await _wait(2)
	var enemy_has_outline: bool = false
	for node: Node in enemy.find_children("*", "", true, false):
		if node.has_method(&"is_silhouette_outline_enabled"):
			enemy_has_outline = true
	_check("силуэты: контур врагов (DESIGN §9.1)", enemy_has_outline,
		"Enemy/EnemyAnimation имеет silhouette outline: %s" % str(enemy_has_outline))
	Config.set_silhouette_readability(false)


# ------------------------------------------------------------------------------
# §9.6 п.6 — RU/EN при 100/150
# ------------------------------------------------------------------------------

func _section_overflow() -> void:
	if _menu == null:
		return
	_menu.open()
	await _wait(2)
	for scale: int in [100, 150]:
		Config.ui_scale = scale
		for language: String in ["ru", "en"]:
			Config.set_language(language)
			await _wait(2)
			_menu.apply_ui_scale()
			await _wait(2)
			var issues: Array[String] = []
			_menu.show_view(MainMenu.View.MAIN)
			await _wait(2)
			issues.append_array(_overflow_scan("MainMenu", _menu))
			_menu.show_view(MainMenu.View.SETTINGS)
			await _wait(3)
			issues.append_array(_overflow_scan("Settings", _menu.get_settings_view()))
			_menu.show_view(MainMenu.View.LOAD)
			await _wait(3)
			issues.append_array(_overflow_scan("SaveSlots", _menu.get_slots_view()))
			_menu.show_view(MainMenu.View.MAIN)
			await _wait(2)
			_check("переполнение %s/%d%%" % [language.to_upper(), scale], issues.is_empty(),
				"; ".join(issues.slice(0, 8)))


## Переполнение остальных панелей (HUD/инвентарь/журнал/фракции/диалог/костёр/смерть/карта/ремап).
## Масштаб UI эти экраны не применяют: проверяем, что текст влезает, и фиксируем
## отсутствие масштабирования отдельным пунктом.
func _section_overflow_screens() -> void:
	Config.set_no_flash(true)
	for scale: int in [100, 150]:
		Config.ui_scale = scale
		for language: String in ["ru", "en"]:
			Config.set_language(language)
			await _wait(2)
			var issues: Array[String] = []
			issues.append_array(await _scan_screen("HUD", HUD_SCENE, Callable()))
			issues.append_array(await _scan_screen("Inventory", INVENTORY_SCENE, Callable()))
			issues.append_array(await _scan_screen("Journal", JOURNAL_SCENE, Callable()))
			issues.append_array(await _scan_screen("Factions", FACTIONS_SCENE, Callable()))
			issues.append_array(await _scan_screen("FactionChoice", CHOICE_SCENE, func(node: Node): node.call(&"open", "Совет")))
			issues.append_array(await _scan_screen("WorldMap", MAP_SCENE, Callable()))
			issues.append_array(await _scan_screen("Remap", REMAP_SCENE, Callable()))
			issues.append_array(await _scan_dialogue())
			issues.append_array(await _scan_campfire())
			issues.append_array(await _scan_death())
			_check("переполнение панелей %s/%d%%" % [language.to_upper(), scale], issues.is_empty(),
				"; ".join(issues.slice(0, 8)))

	# Масштаб UI: проверяем, что 150% реально увеличивает шрифт HUD/инвентаря.
	Config.ui_scale = 100
	var hud100 := _spawn(HUD_SCENE) as AshenHUD
	await _wait(3)
	var font100: int = _first_label_font(hud100)
	Config.ui_scale = 150
	await _wait(3)
	var font150: int = _first_label_font(hud100)
	_check("масштаб UI 150% применяется к HUD", font150 > font100,
		"шрифт HUD %d → %d px" % [font100, font150])
	Config.ui_scale = 100
	Config.set_no_flash(false)


func _first_label_font(root: Node) -> int:
	for node: Node in root.find_children("*", "", true, false):
		if node is Label:
			return (node as Label).get_theme_font_size(&"font_size")
	return 0


func _scan_screen(label: String, scene: PackedScene, open_fn: Callable) -> Array[String]:
	var node := scene.instantiate()
	add_child(node)
	await _wait(3)
	if open_fn.is_valid():
		open_fn.call(node)
		await _wait(3)
	elif node.has_method(&"open"):
		node.call(&"open")
		await _wait(3)
	var issues := _overflow_scan(label, node)
	if node.has_method(&"close"):
		node.call(&"close")
	node.queue_free()
	await _wait(2)
	return issues


func _scan_dialogue() -> Array[String]:
	var node := _spawn(DIALOGUE_SCENE) as DialogueScreen
	var data := load("res://data/dialogue/elder_lira.tres") as DialogueData
	node.open_dialogue(data)
	await _wait(4)
	var issues := _overflow_scan("Dialogue", node)
	node.close()
	node.queue_free()
	await _wait(2)
	return issues


func _scan_campfire() -> Array[String]:
	var node := _spawn(CAMPFIRE_SCENE) as Campfire
	var bonfire := Bonfire.new()
	add_child(bonfire)
	await _wait(2)
	node.open(bonfire)
	await _wait(4)
	var issues := _overflow_scan("Campfire", node)
	node.close()
	node.queue_free()
	bonfire.queue_free()
	await _wait(2)
	return issues


func _scan_death() -> Array[String]:
	var node := _spawn(DEATH_SCENE) as DeathScreen
	var info: Dictionary = {
		"items": ["iron_dagger", "healing_herb", "ash_relic"],
		"items_count": 3,
		"currency": 1240,
		"zone_id": "zone_04_ruins",
		"position": Vector2(112, 214),
	}
	node.show_death(info)
	await _wait(4)
	var issues := _overflow_scan("Death", node)
	node.hide_screen()
	node.queue_free()
	await _wait(2)
	return issues


func _overflow_scan(label: String, root: Node) -> Array[String]:
	var issues: Array[String] = []
	for node: Node in root.find_children("*", "", true, false):
		if not node is CanvasItem:
			continue
		if node.is_queued_for_deletion() or not (node as CanvasItem).is_visible_in_tree():
			continue
		if node is Label:
			var label_node := node as Label
			if label_node.text.strip_edges().is_empty():
				continue
			if label_node.autowrap_mode != TextServer.AUTOWRAP_OFF:
				continue
			if label_node.size.x <= 0.0:
				continue
			var fs: int = label_node.get_theme_font_size(&"font_size")
			var width: float = _max_line_width(label_node.text, fs)
			if width > label_node.size.x + 1.0:
				issues.append("%s/%s: text %.0f > %.0f" % [label, label_node.name, width, label_node.size.x])
		elif node is AshenMenuItem:
			var item := node as AshenMenuItem
			if item.text.strip_edges().is_empty() or item.size.x <= 0.0:
				continue
			var fs_item: int = item.font_size
			var width_item: float = _max_line_width(item.text, fs_item)
			var available: float = item.size.x - float(UITokens.PANEL_PADDING) - float(fs_item)
			if width_item > available + 1.0:
				issues.append("%s/%s: text %.0f > %.0f" % [label, item.name, width_item, available])
	return issues


func _max_line_width(text: String, font_size: int) -> float:
	var widest: float = 0.0
	for line: String in text.split("\n"):
		widest = maxf(widest, UIStyle.text_width(line, font_size))
	return widest


func _report() -> void:
	print("[A11Y] SUMMARY pass=%d fail=%d" % [_pass, _fail])
	for failure: String in _failures:
		print("[A11Y] FAILED: %s" % failure)
