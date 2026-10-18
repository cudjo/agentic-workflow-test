class_name AshenToast
extends PanelContainer
## AshenToast — тост/уведомление (DESIGN §5, §6.4).
##
## success: панель solid, галочка steel-3, текст bone.
## danger:  панель danger (рамка blood-3), значок «!» blood/bone, текст blood-5.
## info:    панель solid, нейтральный значок steel-3.
##
## Показ ≤ 1 с для подтверждений (AC-05.1); таймер настраивается. Иконка
## дублирует смысл помимо цвета («✓» / «!»).

signal expired

enum Kind { SUCCESS, DANGER, INFO }

@export var duration: float = 1.0

var _kind: Kind = Kind.INFO
var _message: String = ""
var _built: bool = false
var _icon: _ToastIcon
var _label: Label
var _timer: Timer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	custom_minimum_size = Vector2(0, UITokens.TOAST_MIN_HEIGHT)
	add_theme_stylebox_override(
		"panel",
		UIStyle.panel_style(UIStyle.PanelVariant.SOLID, UITokens.PANEL_PADDING, UITokens.SP_4, UITokens.PANEL_PADDING)
	)


func _ready() -> void:
	_ensure_built()


## Показать сообщение. `kind` — Kind.SUCCESS/DANGER/INFO.
func show_message(message: String, kind: Kind = Kind.SUCCESS, show_duration: float = -1.0) -> void:
	_message = message
	_kind = kind
	if show_duration >= 0.0:
		duration = show_duration
	_ensure_built()
	visible = true
	_apply_kind()
	_label.text = message
	if duration > 0.0:
		_timer.start(duration)
	else:
		_timer.stop()


func hide_message() -> void:
	visible = false
	if _timer != null:
		_timer.stop()


func get_kind() -> Kind:
	return _kind


func get_message() -> String:
	return _message


func get_text_color() -> Color:
	return UITokens.BLOOD_5 if _kind == Kind.DANGER else UITokens.BONE


func _ensure_built() -> void:
	if _built:
		return
	_built = true

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", UITokens.SP_2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_icon = _ToastIcon.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_icon)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", UIStyle.font())
	_label.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	_label.add_theme_color_override("font_color", UITokens.BONE)
	box.add_child(_label)

	add_child(box)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)


func _apply_kind() -> void:
	var variant: int = UIStyle.PanelVariant.DANGER if _kind == Kind.DANGER else UIStyle.PanelVariant.SOLID
	add_theme_stylebox_override(
		"panel",
		UIStyle.panel_style(variant, UITokens.PANEL_PADDING, UITokens.SP_4, UITokens.PANEL_PADDING)
	)
	_icon.kind = _kind
	_icon.queue_redraw()
	_label.add_theme_color_override("font_color", get_text_color())


func _on_timeout() -> void:
	visible = false
	expired.emit()


## Внутренний значок: галочка/«!»/точка — форма, не только цвет.
class _ToastIcon:
	extends Control

	## 0 = success, 1 = danger, 2 = info (совпадает с AshenToast.Kind).
	var kind: int = 2

	func _init() -> void:
		custom_minimum_size = Vector2(UITokens.ICON, UITokens.ICON)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, Vector2(UITokens.ICON, UITokens.ICON))
		match kind:
			0:
				draw_rect(rect, UITokens.STEEL_9)
				UIStyle.draw_frame(self, rect, 1, UITokens.STEEL_3)
				UIStyle.draw_check(self, rect, UITokens.STEEL_3)
			1:
				draw_rect(rect, UITokens.BLOOD)
				UIStyle.draw_frame(self, rect, 1, UITokens.BLOOD_3)
				draw_rect(Rect2(5, 2, 2, 5), UITokens.BONE)
				draw_rect(Rect2(5, 9, 2, 1), UITokens.BONE)
			_:
				draw_rect(rect, UITokens.STEEL_9)
				UIStyle.draw_frame(self, rect, 1, UITokens.STEEL_3)
				draw_rect(Rect2(5, 2, 2, 2), UITokens.STEEL_3)
				draw_rect(Rect2(5, 5, 2, 2), UITokens.STEEL_3)
				draw_rect(Rect2(5, 9, 2, 1), UITokens.STEEL_3)
