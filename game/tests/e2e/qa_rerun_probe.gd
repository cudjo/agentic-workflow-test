extends Node
## QA T-37 rerun (48de7dc): независимые проверки двух спорных мест.
## 1) Масштаб UI 150% на экранах, кроме HUD/меню.
## 2) Отмена FactionChoice (Esc/B) — можно ли вернуться к выбору.
## Запуск: godot --headless --path game res://tests/e2e/qa_rerun_probe.tscn

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

var _main: Node = null
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(item: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("[PROBE2] PASS %s — %s" % [item, detail])
	else:
		_fail += 1
		print("[PROBE2] FAIL %s — %s" % [item, detail])


func _run() -> void:
	Config.ui_scale = Config.UI_SCALE_100
	_main = MAIN_SCENE.instantiate()
	SceneRouter.bind_world_root(_main.get_node("WorldRoot") as Node2D)
	add_child(_main)
	await _wait(10)
	await _wait_physics(6)
	await _probe_ui_scale()
	await _probe_faction_cancel()
	print("[PROBE2] SUMMARY pass=%d fail=%d" % [_pass, _fail])
	get_tree().quit(0)


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _wait_physics(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame


func _first_font(root: Node) -> int:
	for node: Node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and not label.text.strip_edges().is_empty():
			return label.get_theme_font_size(&"font_size")
	return -1


func _probe_ui_scale() -> void:
	Config.ui_scale = Config.UI_SCALE_100
	await _wait(2)
	for entry: Dictionary in SCREENS:
		var scene := load(String(entry["path"])) as PackedScene
		var screen := scene.instantiate()
		if entry["name"] != "DeathScreen" and "pause_on_open" in screen:
			screen.set(&"pause_on_open", false)
		add_child(screen)
		await _wait(2)
		if screen.has_method(&"open"):
			screen.call(&"open")
		await _wait(2)
		var at_100: int = _first_font(screen)
		Config.ui_scale = Config.UI_SCALE_150
		await _wait(3)
		var at_150: int = _first_font(screen)
		_check("ui 150%%: %s" % entry["name"], at_100 > 0 and at_150 > at_100,
			"font %d → %d px" % [at_100, at_150])
		Config.ui_scale = Config.UI_SCALE_100
		await _wait(2)
		if screen.has_method(&"close"):
			screen.call(&"close")
		screen.queue_free()
		await _wait(1)


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


func _probe_faction_cancel() -> void:
	var zone := SceneRouter.current_zone
	var player := get_tree().get_first_node_in_group(&"player") as Player
	var keeper := zone.get_node_or_null("NPCs/KeeperNpc") as DialogueNpc
	var dialogue := _main.get_node("DialogueScreen") as DialogueScreen
	if player == null or keeper == null:
		_check("faction cancel: NPC/игрок найдены", false)
		return
	player.global_position = keeper.global_position
	await _wait_physics(2)
	var interaction := player.get_node_or_null("Interaction") as PlayerInteraction
	var opened: bool = interaction != null and interaction.try_interact()
	await _wait(2)
	if not opened or not dialogue.is_open():
		_check("faction cancel: диалог открыт", false)
		return
	dialogue.select_answer(0)
	await _wait(2)
	dialogue.close()
	await _wait(2)
	opened = interaction != null and interaction.try_interact()
	await _wait(2)
	if not opened or not dialogue.is_open():
		_check("faction cancel: повторный диалог открыт", false)
		return
	dialogue.select_answer(1)
	await _wait(4)
	dialogue.close()
	await _wait(6)

	var choice := _main.get_node_or_null("FactionChoice") as FactionChoice
	_check("faction cancel: экран выбора открылся после квеста",
		choice != null and choice.is_open(), "open=%s" % (str(choice.is_open()) if choice != null else "n/a"))
	if choice == null or not choice.is_open():
		return
	# Игрок нажимает Esc/B — экран сам предлагает «закрыть без выбора».
	await _tap(KEY_ESCAPE)
	await _wait(4)
	_check("faction cancel: Esc закрывает экран без выбора",
		not choice.is_open() and not FactionManager.is_faction_chosen(),
		"open=%s chosen=%s" % [str(choice.is_open()), str(FactionManager.is_faction_chosen())])

	# Fix-3a/N1: отмена снимает запрос, и выбор можно открыть повторно.
	var requested: bool = bool(_main.get("_faction_choice_requested"))
	_check("faction cancel: отмена сбрасывает запрос Main",
		not requested, "_faction_choice_requested=%s pending=%s" % [str(requested),
		str(_main.get("_faction_choice_pending"))])
	_main.call("_request_faction_choice")
	await _wait(4)
	_check("faction cancel: выбор снова открывается после отмены",
		choice.is_open() and not FactionManager.is_faction_chosen(),
		"open=%s chosen=%s" % [str(choice.is_open()), str(FactionManager.is_faction_chosen())])
