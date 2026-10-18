class_name AshenTab
extends Button
## AshenTab — заголовок раздела (DESIGN §5, §6.1).
##
## Обычная вкладка: текст stone-5. Выбранная: текст gold-3 + фон night-9 +
## рамка stone-9 (низ открыт — вкладка «срастается» с панелью), т.е. состояние
## читается формой, а не только цветом. Фокус: рамка gold-3 2 px внутри.

@export var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

@export_range(8, 16, 8) var font_size: int = UITokens.FONT_BODY:
	set(value):
		font_size = value
		queue_redraw()


func _init() -> void:
	UIStyle.make_custom_button(self)
	custom_minimum_size = Vector2(0, UITokens.TAB_HEIGHT)
	mouse_entered.connect(_on_mouse_entered)


func _ready() -> void:
	custom_minimum_size.y = UITokens.TAB_HEIGHT
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func is_focus_visible() -> bool:
	return has_focus() and focus_mode == Control.FOCUS_ALL


func get_label_color() -> Color:
	if selected:
		return UITokens.GOLD_3
	if is_focus_visible() or is_hovered():
		return UITokens.BONE
	return UITokens.STONE_5


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var focused: bool = is_focus_visible()

	if selected:
		draw_rect(rect, UITokens.NIGHT_9)
		draw_rect(Rect2(0, 0, rect.size.x, UITokens.BORDER_PANEL), UITokens.STONE_9)
		draw_rect(Rect2(0, 0, UITokens.BORDER_PANEL, rect.size.y), UITokens.STONE_9)
		draw_rect(
			Rect2(rect.size.x - UITokens.BORDER_PANEL, 0, UITokens.BORDER_PANEL, rect.size.y),
			UITokens.STONE_9
		)
		# Маркер выбранной вкладки: 2×3 gold у верхней кромки (дубль формой).
		draw_rect(Rect2(3, 1, 2, 3), UITokens.GOLD)
	elif focused or is_hovered():
		draw_rect(rect, UITokens.NIGHT_3)

	var padding: int = UITokens.SP_3
	var baseline: float = (
		(rect.size.y - UIStyle.text_height(font_size)) * 0.5
		+ UIStyle.baseline_y(font_size)
	)
	UIStyle.draw_text(
		self,
		Vector2(float(padding), baseline),
		text,
		get_label_color(),
		font_size,
		rect.size.x - float(padding * 2),
		HORIZONTAL_ALIGNMENT_CENTER
	)

	if focused:
		UIStyle.draw_frame(self, rect.grow(-1), UITokens.BORDER_FOCUS, UITokens.GOLD_3)


func _on_mouse_entered() -> void:
	if is_inside_tree():
		grab_focus()
