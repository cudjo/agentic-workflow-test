class_name AshenPrompt
extends HBoxContainer
## AshenPrompt — контекстная подсказка ввода: [глиф] + текст (DESIGN §5).
##
## Глиф — AshenKbd, автоматически переключается между клавиатурой/Xbox/PS
## по InputManager.active_device (EC-08, a11y §9.2).

@export var action: StringName = &"interact":
	set(value):
		action = value
		_apply()

@export var label_text: String = "":
	set(value):
		label_text = value
		_apply()

var _kbd: AshenKbd
var _label: Label
var _built: bool = false


func _init() -> void:
	add_theme_constant_override("separation", UITokens.SP_2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_ensure_built()
	_apply()


## Удобный конструктор для экранов: `prompt.setup(&"interact", "Осмотреть")`.
func setup(new_action: StringName, new_text: String) -> void:
	action = new_action
	label_text = new_text
	_apply()


func get_kbd() -> AshenKbd:
	_ensure_built()
	return _kbd


func get_text() -> String:
	return label_text


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_kbd = AshenKbd.new()
	_kbd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kbd)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", UIStyle.font())
	_label.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	_label.add_theme_color_override("font_color", UITokens.BONE)
	_label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)


func _apply() -> void:
	if not _built:
		return
	_kbd.action = action
	_label.text = label_text
