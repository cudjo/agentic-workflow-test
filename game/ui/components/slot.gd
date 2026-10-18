class_name AshenSlot
extends Button
## AshenSlot — ячейка инвентаря / быстрого слота / способности (DESIGN §6.2).
##
## Состояния:
##   NORMAL       — рамка stone-9, фон void;
##   SELECTED     — рамка gold + внутренняя gold-9;
##   EQUIPPED     — золотой маркер 3×3 в левом верхнем углу;
##   UNAVAILABLE  — иконка 45% + замок;
##   EMPTY        — пунктирная рамка;
##   REQUIREMENTS — иконка 55% + красный «!» (blood + bone), «ещё N» в подсказке.
##
## Фокус всегда виден: золотая рамка + внутренняя gold-9 + уголковые скобки
## (форма отличается от просто «выбранного» состояния). Мышь: hover = фокус.

enum State { NORMAL, SELECTED, EQUIPPED, UNAVAILABLE, EMPTY, REQUIREMENTS }

@export var state: State = State.NORMAL:
	set(value):
		state = value
		_update_tooltip()
		queue_redraw()

## 22 px — HUD, 28 px — инвентарь (DESIGN §4.3).
@export var slot_size: int = UITokens.SLOT_HUD:
	set(value):
		slot_size = maxi(UITokens.HIT_TARGET, value)
		custom_minimum_size = Vector2(slot_size, slot_size)
		queue_redraw()

## Счётчик внизу справа; -1 — не показывать.
@export var count: int = -1:
	set(value):
		count = value
		queue_redraw()

## Подпись клавиши/кнопки вверху слева («1»…«4»).
@export var key_hint: String = "":
	set(value):
		key_hint = value
		queue_redraw()

@export var item_icon: Texture2D:
	set(value):
		item_icon = value
		queue_redraw()

## Насколько не хватает требований: «НЕТ · ещё N» (DESIGN §6.2).
@export var requirement_delta: int = 0:
	set(value):
		requirement_delta = maxi(0, value)
		_update_tooltip()


func _init() -> void:
	UIStyle.make_custom_button(self)
	custom_minimum_size = Vector2(slot_size, slot_size)
	mouse_entered.connect(_on_mouse_entered)


func _ready() -> void:
	custom_minimum_size = Vector2(slot_size, slot_size)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_update_tooltip()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, UITokens.VOID)
	if state == State.EMPTY:
		UIStyle.draw_dashed_frame(self, rect, UITokens.BORDER_SLOT, UITokens.STONE_9)
	else:
		var border: Color = get_border_color()
		UIStyle.draw_frame(self, rect, UITokens.BORDER_SLOT, border)
		if state == State.SELECTED:
			UIStyle.draw_frame(
				self,
				rect.grow(-float(UITokens.BORDER_SLOT)),
				UITokens.BORDER_INNER,
				UITokens.GOLD_9
			)

	var inner := rect.grow(-float(UITokens.BORDER_SLOT))
	if state != State.EMPTY:
		_draw_icon(inner)

	if state == State.EQUIPPED:
		draw_rect(
			Rect2(rect.position + Vector2(2, 2), Vector2(UITokens.RIVET_SIZE, UITokens.RIVET_SIZE)),
			UITokens.GOLD
		)

	if state == State.REQUIREMENTS:
		UIStyle.draw_bang(
			self,
			Rect2(
				rect.size - Vector2(UITokens.SLOT_BADGE + 2, UITokens.SLOT_BADGE + 2),
				Vector2(UITokens.SLOT_BADGE, UITokens.SLOT_BADGE)
			),
			UITokens.BLOOD,
			UITokens.BONE
		)
	elif state == State.UNAVAILABLE:
		UIStyle.draw_lock(
			self,
			Rect2(
				rect.size - UITokens.SLOT_LOCK_SIZE - Vector2(UITokens.SP_1, UITokens.SP_1),
				UITokens.SLOT_LOCK_SIZE
			),
			UITokens.STONE_5
		)

	if key_hint != "":
		UIStyle.draw_text(
			self,
			Vector2(1, UIStyle.baseline_y(UITokens.FONT_BODY)),
			key_hint,
			UITokens.BONE,
			UITokens.FONT_BODY,
			-1.0,
			HORIZONTAL_ALIGNMENT_LEFT,
			true
		)

	if count >= 0:
		var baseline: float = size.y - 1.0
		UIStyle.draw_text(
			self,
			Vector2(0, baseline),
			str(count),
			UITokens.BONE,
			UITokens.FONT_BODY,
			size.x - 2.0,
			HORIZONTAL_ALIGNMENT_RIGHT,
			true
		)

	if is_focus_visible():
		UIStyle.draw_frame(self, rect, UITokens.BORDER_FOCUS, UITokens.GOLD)
		UIStyle.draw_frame(
			self,
			rect.grow(-float(UITokens.BORDER_FOCUS)),
			UITokens.BORDER_INNER,
			UITokens.GOLD_9
		)
		UIStyle.draw_focus_brackets(self, rect.grow(-3), UITokens.GOLD_3, UITokens.FOCUS_ARM, UITokens.BORDER_FOCUS)


func _draw_icon(inner: Rect2) -> void:
	var icon_size: float = float(UITokens.ICON)
	var icon_rect := Rect2(
		inner.position + (inner.size - Vector2(icon_size, icon_size)) * 0.5,
		Vector2(icon_size, icon_size)
	)
	var alpha: float = 1.0
	if state == State.UNAVAILABLE:
		alpha = 0.45
	elif state == State.REQUIREMENTS:
		alpha = 0.55

	if item_icon != null:
		draw_texture_rect(item_icon, icon_rect, false, Color(1, 1, 1, alpha))
		return

	# Программная заглушка иконки (арт появится в T-05/T-21).
	draw_rect(icon_rect.grow(-2), Color(UITokens.STEEL_9, alpha))
	UIStyle.draw_frame(self, icon_rect.grow(-2), 1, Color(UITokens.STEEL_3, alpha))
	draw_rect(
		Rect2(icon_rect.position + Vector2(5, 3), Vector2(2, 6)),
		Color(UITokens.STEEL_3, alpha)
	)


## Цвет рамки состояния (для тестов/a11y-аудита).
func get_border_color() -> Color:
	match state:
		State.SELECTED:
			return UITokens.GOLD
		State.REQUIREMENTS:
			return UITokens.BLOOD_3
		_:
			return UITokens.STONE_9


func is_focus_visible() -> bool:
	return has_focus() and focus_mode == Control.FOCUS_ALL


func has_equipped_marker() -> bool:
	return state == State.EQUIPPED


func has_lock_marker() -> bool:
	return state == State.UNAVAILABLE


func has_requirement_marker() -> bool:
	return state == State.REQUIREMENTS


func is_empty() -> bool:
	return state == State.EMPTY


func _update_tooltip() -> void:
	match state:
		State.REQUIREMENTS:
			tooltip_text = "НЕТ · ещё %d" % requirement_delta if requirement_delta > 0 else "НЕТ"
		State.UNAVAILABLE:
			tooltip_text = "Недоступно"
		_:
			tooltip_text = ""


func _on_mouse_entered() -> void:
	if not disabled and is_inside_tree():
		grab_focus()
