extends Node
## QA T-37: ввод геймпадом в игре + EC-13 (потеря фокуса окна).

const MAIN_SCENE: PackedScene = preload("res://Main.tscn")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	var world_root := main.get_node("WorldRoot") as Node2D
	SceneRouter.bind_world_root(world_root)
	add_child(main)
	await _wait(6)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	print("[INPUT] player=", player)
	if player == null:
		get_tree().quit(0)
		return
	await _wait(6)
	var start_x: float = player.global_position.x
	_axis(0, 1.0)
	await _physics(24)
	print("[INPUT] move right via stick: x %.1f -> %.1f" % [start_x, player.global_position.x])
	_axis(0, 0.0)
	await _physics(8)
	var ground_y: float = player.global_position.y
	_button(JOY_BUTTON_A, true)
	await _physics(1)
	_button(JOY_BUTTON_A, false)
	await _physics(12)
	print("[INPUT] jump via A: y %.1f -> %.1f" % [ground_y, player.global_position.y])
	_button(JOY_BUTTON_X, true)
	await _physics(2)
	_button(JOY_BUTTON_X, false)
	await _physics(2)
	print("[INPUT] attack via X: state=", player.get_state_name())

	# Атака по врагу с земли (в мире врагов нет — спавним для проверки механики).
	await _physics(30)
	var enemy := (load("res://entities/enemies/swift/swift_enemy.tscn") as PackedScene).instantiate() as Enemy
	SceneRouter.current_zone.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(18, 0)
	await _physics(6)
	var hp_before: float = enemy.hp
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.keycode = KEY_J
	key.pressed = true
	Input.parse_input_event(key)
	await _physics(2)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	await _physics(12)
	print("[INPUT] attack damage: enemy hp %.1f -> %.1f (state=%s)" % [
		hp_before, enemy.hp, player.get_state_name()
	])
	enemy.queue_free()

	# EC-13: потеря фокуса окна → пауза/меню.
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _wait(3)
	var menu := main.get_node_or_null("MainMenu")
	print("[INPUT] EC-13 paused=", get_tree().paused, " menu=", menu)
	get_tree().quit(0)


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _physics(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame


func _axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
