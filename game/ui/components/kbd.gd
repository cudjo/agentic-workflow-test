class_name AshenKbd
extends Control
## AshenKbd — клавиша/глиф кнопки (DESIGN §5 Kbd/Prompt, EC-08).
##
## Глиф выбирается автоматически по InputManager.active_device:
##   keyboard    — подпись клавиши из InputMap («E», «SPC», «←»);
##   xbox        — A/B/X/Y, LB/RB, D-pad;
##   playstation — ✕/○/□/△, L1/R1, D-pad;
##   gamepad     — нейтральные A/B/X/Y.
## При смене устройства глиф обновляется без перезапуска (сигнал device_changed).
##
## Символы ○ □ △ берутся из fallback-шрифта темы (Press Start 2P их не имеет).

const DEVICE_KEYBOARD := "keyboard"
const DEVICE_XBOX := "xbox"
const DEVICE_PLAYSTATION := "playstation"
const DEVICE_GENERIC := "gamepad"

## Godot JoyButton индексы (проект использует именно их в InputMap).
const XBOX_BUTTONS := {
	0: "A", 1: "B", 2: "X", 3: "Y",
	4: "BACK", 5: "GUIDE", 6: "START", 7: "L3", 8: "R3",
	9: "LB", 10: "RB", 11: "↑", 12: "↓", 13: "←", 14: "→",
}
const PLAYSTATION_BUTTONS := {
	0: "✕", 1: "○", 2: "□", 3: "△",
	4: "SEL", 5: "PS", 6: "OPT", 7: "L3", 8: "R3",
	9: "L1", 10: "R1", 11: "↑", 12: "↓", 13: "←", 14: "→",
}
const GENERIC_BUTTONS := {
	0: "A", 1: "B", 2: "X", 3: "Y",
	4: "SEL", 5: "HOME", 6: "START", 7: "L3", 8: "R3",
	9: "L1", 10: "R1", 11: "↑", 12: "↓", 13: "←", 14: "→",
}
const KEY_LABELS := {
	KEY_SPACE: "SPC",
	KEY_SHIFT: "SHF",
	KEY_CTRL: "CTL",
	KEY_ALT: "ALT",
	KEY_ESCAPE: "ESC",
	KEY_ENTER: "ENT",
	KEY_KP_ENTER: "ENT",
	KEY_TAB: "TAB",
	KEY_BACKSPACE: "BSP",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
	KEY_UP: "↑",
	KEY_DOWN: "↓",
}

## Действие InputMap, чей глиф показывается.
@export var action: StringName = &"interact":
	set(value):
		action = value
		refresh()

## Пустая строка — брать активное устройство из InputManager (EC-08).
@export var device_override: String = "":
	set(value):
		device_override = value
		refresh()

var _glyph: String = "?"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UITokens.KBD_HEIGHT, UITokens.KBD_HEIGHT)


func _ready() -> void:
	var input_manager: Node = get_node_or_null("/root/InputManager")
	if input_manager != null and input_manager.has_signal("device_changed"):
		input_manager.device_changed.connect(_on_device_changed)
	refresh()


func refresh() -> void:
	_glyph = glyph_for_action(action, get_device())
	var width: float = maxf(
		float(UITokens.KBD_HEIGHT),
		UIStyle.text_width(_glyph, UITokens.FONT_BODY) + float(UITokens.SP_2)
	)
	custom_minimum_size = Vector2(width, UITokens.KBD_HEIGHT)
	queue_redraw()


func get_device() -> String:
	if device_override != "":
		return device_override
	return active_device()


func get_glyph() -> String:
	return _glyph


func is_gamepad_glyph() -> bool:
	return get_device() != DEVICE_KEYBOARD


## Активное устройство из InputManager (без жёсткой зависимости от autoload).
static func active_device() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var input_manager: Node = tree.root.get_node_or_null("InputManager")
		if input_manager != null:
			var device: Variant = input_manager.get("active_device")
			if device is String and device != "":
				return device
	return DEVICE_KEYBOARD


## Подпись действия для устройства. Чистая функция — проверяется GUT-тестом.
static func glyph_for_action(action_name: StringName, device: String) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action_name)
	if device == DEVICE_KEYBOARD:
		for event in events:
			if event is InputEventKey:
				return _key_glyph(event as InputEventKey)
		return "?"

	for event in events:
		if event is InputEventJoypadButton:
			return _pad_glyph((event as InputEventJoypadButton).button_index, device)
	# Ремап мог оставить только клавиатуру — показываем клавишу, не «?».
	for event in events:
		if event is InputEventKey:
			return _key_glyph(event as InputEventKey)
	return "?"


static func _key_glyph(event: InputEventKey) -> String:
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if KEY_LABELS.has(code):
		return KEY_LABELS[code]
	var label: String = OS.get_keycode_string(code)
	if label == "":
		return "?"
	return label.to_upper().substr(0, 3)


static func _pad_glyph(button_index: int, device: String) -> String:
	var table: Dictionary = GENERIC_BUTTONS
	if device == DEVICE_XBOX:
		table = XBOX_BUTTONS
	elif device == DEVICE_PLAYSTATION:
		table = PLAYSTATION_BUTTONS
	return table.get(button_index, "?")


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var gamepad: bool = is_gamepad_glyph()
	var background: Color = UITokens.STEEL_9 if gamepad else UITokens.STONE_9
	var border: Color = UITokens.STEEL_3 if gamepad else UITokens.STONE_3

	draw_rect(rect, background)
	UIStyle.draw_frame(self, rect, UITokens.BORDER_INNER, border)
	draw_rect(
		Rect2(0, rect.size.y - 2, rect.size.x, 2),
		border
	)

	var baseline: float = (
		(rect.size.y - 2.0 - UIStyle.text_height(UITokens.FONT_BODY)) * 0.5
		+ UIStyle.baseline_y(UITokens.FONT_BODY)
	)
	UIStyle.draw_text(
		self,
		Vector2(1, baseline),
		_glyph,
		UITokens.BONE,
		UITokens.FONT_BODY,
		rect.size.x - 2.0,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _on_device_changed(_device: String, _device_id: int) -> void:
	if device_override == "":
		refresh()
