extends Node
## QA T-37 (ревизия 48de7dc): точечные проверки фиксов Fix-1/Fix-2.
## Запуск: godot --headless --path . res://tests/e2e/qa_fix_probe.tscn
##
## Проверяет: clamp подсказки AbilityHint (AC-02.4), масштаб UI 150% на
## экранах, DeathScreen._retranslate при смене языка, EC-13 (пауза+меню).

const MAIN_SCENE: PackedScene = preload("res://Main.tscn")

const SCREENS: Array[Dictionary] = [
	{"name": "Inventory", "path": "res://ui/inventory/Inventory.tscn"},
	{"name": "Journal", "path": "res://ui/journal/Journal.tscn"},
	{"name": "Factions", "path": "res://ui/factions/Factions.tscn"},
	{"name": "FactionChoice", "path": "res://ui/factions/FactionChoice.tscn"},
	{"name": "WorldMap", "path": "res://ui/map/WorldMap.tscn"},
	{"name": "Campfire", "path": "res://ui/campfire/Campfire.tscn"},
	{"name": "Remap", "path": "res://ui/remap/Remap.tscn"},
	{"name": "DeathScreen", "path": "res://ui/death/DeathScreen.tscn"},
]

var _results: Array[Dictionary] = []
var _main: Node = null


func _ready() -> void:
	_run.call_deferred()


func _check(step: String, ok: bool, detail: String = "") -> bool:
	_results.append({"step": step, "ok": ok, "detail": detail})
	print("[FIX] %s %s%s" % ["PASS" if ok else "FAIL", step, (" — " + detail) if detail else ""])
	return ok


func _run() -> void:
	Config.ui_scale = Config.UI_SCALE_100
	await _setup_main()
	await _test_ability_hint_clamp()
	await _test_ui_scale_screens()
	await _test_death_retranslate()
	await _test_ec13()
	_report()
	get_tree().quit(0)


func _setup_main() -> void:
	_main = MAIN_SCENE.instantiate()
	var world_root := _main.get_node("WorldRoot") as Node2D
	SceneRouter.bind_world_root(world_root)
	add_child(_main)
	await _wait_process(10)
	await _wait_physics(6)
	print("[FIX] main zone=%s" % SceneRouter.current_zone_id)


func _wait_process(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _wait_physics(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame


func _first_label(root: Node) -> Label:
	for node: Node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and not label.text.is_empty():
			return label
	return null


func _label_font(root: Node) -> int:
	var label := _first_label(root)
	if label == null:
		return -1
	return label.get_theme_font_size("font_size")


# ------------------------------------------------------------------------------
# B9 / AC-02.4: подсказка gate не выходит за 480×270
# ------------------------------------------------------------------------------

func _test_ability_hint_clamp() -> void:
	var zone := SceneRouter.current_zone
	if zone == null:
		_check("hint: зона загружена", false)
		return
	var hint := zone.get_node_or_null("Props/Rubble/AbilityHint") as AbilityHint
	_check("hint: AbilityHint у завала найден", hint != null)
	if hint == null:
		return
	# Репозиция B9: завал стоял на x≈448, подсказка уходила за правый край.
	hint.show_required(&"double_jump")
	hint.set_world_position(Vector2(448, 170))
	await _wait_process(3)
	var panel: Vector2 = hint._panel_size
	var offset: Vector2 = hint._offset
	var panel_rect := Rect2(hint.global_position - panel * 0.5 + offset, panel)
	var canvas := get_viewport().get_canvas_transform()
	var a: Vector2 = canvas * panel_rect.position
	var b: Vector2 = canvas * panel_rect.end
	var screen_rect := Rect2(a, b - a)
	var visible_rect := get_viewport().get_visible_rect()
	var inside: bool = (
		screen_rect.position.x >= visible_rect.position.x - 1.0
		and screen_rect.position.y >= visible_rect.position.y - 1.0
		and screen_rect.end.x <= visible_rect.end.x + 1.0
		and screen_rect.end.y <= visible_rect.end.y + 1.0
	)
	_check("hint: подсказка в пределах 480×270 (clamp)", inside,
		"panel=%s offset=%s screen=%s visible=%s" % [str(panel), str(offset), str(screen_rect), str(visible_rect)])
	_check("hint: видимый текст полный", hint.get_text().contains("ДВОЙНОЙ") or hint.get_text().contains("DOUBLE"),
		"text='%s'" % hint.get_text())
	hint.hide_hint()


# ------------------------------------------------------------------------------
# A11y §9.6 п.6: масштаб UI 150% на всех экранах
# ------------------------------------------------------------------------------

func _open_screen(screen: Node) -> void:
	if screen.has_method(&"open"):
		screen.call(&"open")
	if screen.has_method(&"is_open"):
		await get_tree().process_frame


func _test_ui_scale_screens() -> void:
	# HUD — эталон: Fix-2 подключил масштаб.
	var hud := _main.get_node_or_null("HUD") as AshenHUD
	var hud_before: int = hud.get_ui_font_size() if hud != null else -1
	Config.ui_scale = Config.UI_SCALE_150
	await _wait_process(3)
	var hud_after: int = hud.get_ui_font_size() if hud != null else -1
	_check("ui scale: HUD 100→150%", hud_before == 8 and hud_after == 12,
		"%d → %d px" % [hud_before, hud_after])

	for entry: Dictionary in SCREENS:
		var scene := load(String(entry["path"])) as PackedScene
		if scene == null:
			_check("ui scale %s: сцена загружена" % entry["name"], false)
			continue
		var screen := scene.instantiate()
		if entry["name"] != "DeathScreen":
			screen.set(&"pause_on_open", false)
		add_child(screen)
		await _wait_process(2)
		await _open_screen(screen)
		await _wait_process(2)
		var at_150: int = _label_font(screen)
		Config.ui_scale = Config.UI_SCALE_100
		await _wait_process(2)
		var at_100: int = _label_font(screen)
		_check("ui scale: %s масштабируется при 150%%" % entry["name"], at_100 > 0 and at_150 > at_100,
			"font %d px (100%%) → %d px (150%%)" % [at_100, at_150])
		Config.ui_scale = Config.UI_SCALE_150
		await _wait_process(1)
		if screen.has_method(&"close"):
			screen.call(&"close")
		screen.queue_free()
		await _wait_process(1)
	Config.ui_scale = Config.UI_SCALE_100
	await _wait_process(3)


# ------------------------------------------------------------------------------
# B7: DeathScreen._retranslate без Nil и с переводом строк
# ------------------------------------------------------------------------------

func _test_death_retranslate() -> void:
	var death := _main.get_node("Overlay/DeathScreen") as DeathScreen
	_check("lang: DeathScreen смонтирован", death != null)
	if death == null:
		return
	_check("lang: строки потерь инициализированы",
		death._coins_row_label != null and death._items_row_label != null,
		"coins=%s items=%s" % [str(death._coins_row_label), str(death._items_row_label)])
	Config.set_language("en")
	await _wait_process(3)
	var en_coins: String = TranslationServer.translate("ui.death.coins")
	var en_items: String = TranslationServer.translate("ui.death.items")
	var coins_ok: bool = death._coins_row_label != null and death._coins_row_label.text == en_coins
	var items_ok: bool = death._items_row_label != null and death._items_row_label.text == en_items
	_check("lang: EN-строки потерь переведены (без Nil)", coins_ok and items_ok,
		"coins='%s'/'%s' items='%s'/'%s'" % [
			death._coins_row_label.text if death._coins_row_label != null else "null", en_coins,
			death._items_row_label.text if death._items_row_label != null else "null", en_items])
	Config.set_language("ru")
	await _wait_process(3)
	var ru_coins: String = TranslationServer.translate("ui.death.coins")
	_check("lang: возврат RU переводит строки обратно",
		death._coins_row_label != null and death._coins_row_label.text == ru_coins,
		"'%s' (ожидалось '%s')" % [death._coins_row_label.text if death._coins_row_label != null else "null", ru_coins])


# ------------------------------------------------------------------------------
# B10 / EC-13: потеря фокуса → пауза + меню, Resume снимает паузу
# ------------------------------------------------------------------------------

func _test_ec13() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _wait_process(6)
	var menu := _main.get_node_or_null("PauseMenu")
	_check("EC-13: потеря фокуса ставит игру на паузу", get_tree().paused,
		"paused=%s" % str(get_tree().paused))
	var menu_visible: bool = menu != null and (menu as CanvasLayer).visible
	_check("EC-13: меню паузы создано и видимо", menu_visible, "menu=%s" % str(menu))
	if menu == null:
		return
	var resume := menu.get_node_or_null("Root/Center/Panel/Box/Resume") as Control
	_check("EC-13: фокус на «Продолжить»", resume != null and resume.has_focus(),
		"resume=%s focus=%s" % [str(resume != null), str(resume.has_focus() if resume != null else false)])
	if resume != null:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_ENTER
		event.keycode = KEY_ENTER
		event.pressed = true
		Input.parse_input_event(event)
		await _wait_process(2)
		var up := event.duplicate() as InputEventKey
		up.pressed = false
		Input.parse_input_event(up)
		await _wait_process(3)
		_check("EC-13: Resume снимает паузу и скрывает меню",
			not get_tree().paused and not menu.visible,
			"paused=%s visible=%s" % [str(get_tree().paused), str(menu.visible)])


func _report() -> void:
	var passed: int = 0
	for r: Dictionary in _results:
		if bool(r["ok"]):
			passed += 1
	print("[FIX] SUMMARY passed=%d failed=%d total=%d" % [passed, _results.size() - passed, _results.size()])
	for r: Dictionary in _results:
		if not bool(r["ok"]):
			print("[FIX] FAILED: %s — %s" % [r["step"], r["detail"]])
