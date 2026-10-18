class_name AshenMenuItem
extends Button
## AshenMenuItem — строка меню/списка с кареткой (DESIGN §6.1).
##
## Состояния:
##   обычное          — текст stone-5, без фона;
##   hover            — текст bone, фон night-3;
##   фокус            — как hover + золотая каретка «>» + внутренняя рамка gold-9;
##   активно/нажато   — заливка gold, текст void, каретка void;
##   отключено        — текст stone-3, обязательна причина (tooltip + inline);
##   toggle           — ползунок вправо/влево + рамка gold (не только цвет).
##
## Фокус и hover совпадают (DESIGN §9.2: мышь: hover = фокус).

@export_range(8, 32, 8) var font_size: int = UITokens.FONT_BODY:
	set(value):
		font_size = value
		_apply_row_height()
		queue_redraw()

## Причина отключения — обязательна (DESIGN §6.1, a11y §9.6 п.4).
@export var disabled_reason: String = "":
	set(value):
		disabled_reason = value
		_apply_row_height()
		_update_tooltip()
		queue_redraw()

## Тег последствия перед текстом, например «[Орден+1]» (DESIGN §5 Dialog).
@export var prefix_tag: String = "":
	set(value):
		prefix_tag = value
		queue_redraw()

## Переключатель: состояние дублируется положением ползунка.
@export var is_toggle: bool = false:
	set(value):
		is_toggle = value
		toggle_mode = value
		queue_redraw()

@export var show_toggle_text: bool = false:
	set(value):
		show_toggle_text = value
		queue_redraw()


func _init() -> void:
	UIStyle.make_custom_button(self)
	mouse_entered.connect(_on_mouse_entered)
	_apply_row_height()


func _ready() -> void:
	_apply_row_height()
	_update_tooltip()
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	toggled.connect(func(_pressed: bool) -> void: queue_redraw())


func _apply_row_height() -> void:
	var row: int = (
		UITokens.ROW_MENU_H2
		if font_size >= UITokens.FONT_H2
		else UITokens.ROW_MENU_BODY
	)
	if disabled and disabled_reason != "":
		row += UITokens.LINE_BODY
	custom_minimum_size = Vector2(custom_minimum_size.x, float(row))


func _update_tooltip() -> void:
	if disabled and disabled_reason != "":
		tooltip_text = disabled_reason
	else:
		tooltip_text = ""


func get_row_height() -> int:
	return int(custom_minimum_size.y)


func get_label_color() -> Color:
	if disabled:
		return UITokens.STONE_3
	if is_active_state():
		return UITokens.VOID
	if is_focus_visible() or is_hovered():
		return UITokens.BONE
	return UITokens.STONE_5


func is_focus_visible() -> bool:
	return has_focus() and focus_mode == Control.FOCUS_ALL


## Активное состояние: нажатие мышью или включённый toggle.
func is_active_state() -> bool:
	return (toggle_mode and button_pressed) or is_pressed()


func get_caret_text() -> String:
	if disabled or not (is_focus_visible() or is_active_state()):
		return ""
	return ">"


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var active: bool = is_active_state()
	var focused: bool = is_focus_visible()
	var hovered: bool = is_hovered()
	var padding: int = (
		UITokens.PANEL_PADDING_DIALOG if font_size >= UITokens.FONT_H2 else UITokens.PANEL_PADDING
	)

	if not disabled and (active or focused or hovered):
		draw_rect(rect, UITokens.GOLD if active else UITokens.NIGHT_3)

	if focused and not active and not disabled:
		UIStyle.draw_frame(self, rect, UITokens.BORDER_INNER, UITokens.GOLD_9)

	var text_color: Color = get_label_color()
	var caret_color: Color = UITokens.VOID if active else UITokens.GOLD_3
	var caret_width: int = font_size
	var cursor_x: float = float(padding)
	var base_row: int = (
		UITokens.ROW_MENU_H2
		if font_size >= UITokens.FONT_H2
		else UITokens.ROW_MENU_BODY
	)
	var baseline: float = (
		(float(base_row) - UIStyle.text_height(font_size)) * 0.5
		+ UIStyle.baseline_y(font_size)
	)

	if get_caret_text() != "":
		UIStyle.draw_text(
			self,
			Vector2(cursor_x, baseline),
			">",
			caret_color,
			font_size
		)
	cursor_x += float(caret_width) + float(UITokens.SP_1)

	var label_x: float = cursor_x
	if prefix_tag != "":
		UIStyle.draw_text(
			self,
			Vector2(label_x, baseline),
			prefix_tag,
			UITokens.STEEL_3 if not active else UITokens.VOID,
			font_size
		)
		label_x += UIStyle.text_width(prefix_tag, font_size) + float(UITokens.SP_1)

	var available_width: float = rect.size.x - label_x - float(padding)
	if is_toggle:
		available_width -= _toggle_width() + float(UITokens.SP_2)
	UIStyle.draw_text(
		self,
		Vector2(label_x, baseline),
		text,
		text_color,
		font_size,
		maxf(available_width, 0.0)
	)

	if disabled and disabled_reason != "":
		UIStyle.draw_text(
			self,
			Vector2(label_x, baseline + float(UITokens.LINE_BODY)),
			disabled_reason,
			UITokens.STONE_5,
			UITokens.FONT_BODY,
			rect.size.x - label_x - float(padding),
			HORIZONTAL_ALIGNMENT_LEFT
		)

	if is_toggle:
		_draw_toggle(rect, active or button_pressed)


func _toggle_width() -> float:
	return (
		UITokens.TOGGLE_TRACK.x
		if not show_toggle_text
		else UITokens.TOGGLE_TRACK.x + float(UITokens.SP_1)
		+ UIStyle.text_width("ВЫКЛ", UITokens.FONT_BODY)
	)


func _draw_toggle(rect: Rect2, on: bool) -> void:
	var track_width: float = UITokens.TOGGLE_TRACK.x
	var track_height: float = UITokens.TOGGLE_TRACK.y
	var track_x: float = rect.size.x - float(UITokens.PANEL_PADDING) - track_width
	var track_y: float = (rect.size.y - track_height) * 0.5
	draw_rect(Rect2(track_x, track_y, track_width, track_height), UITokens.STONE_9)
	UIStyle.draw_frame(
		self,
		Rect2(track_x, track_y, track_width, track_height),
		UITokens.BORDER_INNER,
		UITokens.GOLD if on else UITokens.STONE_3
	)
	var knob_x: float = track_x + (7.0 if on else 1.0)
	draw_rect(
		Rect2(
			knob_x,
			track_y + 1.0,
			float(UITokens.TOGGLE_KNOB),
			track_height - 2.0
		),
		UITokens.GOLD if on else UITokens.STONE_5
	)

	if show_toggle_text:
		UIStyle.draw_text(
			self,
			Vector2(
				track_x - UIStyle.text_width("ВКЛ", UITokens.FONT_BODY) - float(UITokens.SP_1),
				rect.size.y * 0.5 + UIStyle.baseline_y(UITokens.FONT_BODY) * 0.5 - 1.0
			),
			"ВКЛ" if on else "ВЫКЛ",
			UITokens.STEEL_3 if on else UITokens.STONE_5,
			UITokens.FONT_BODY
		)


func _on_mouse_entered() -> void:
	if not disabled and is_inside_tree():
		grab_focus()
