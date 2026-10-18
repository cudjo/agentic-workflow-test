class_name AshenBar
extends Control
## AshenBar — сегментная шкала HUD (DESIGN §5, §6.3).
##
## Виды:
##   HP      — 112×10, сегменты blood-3/blood, число «74/100», след урона gold-9;
##             < 25% — рамка blood-3 + state text «КРИТИЧНО» (не только цвет).
##   STAMINA — 96×8, сегменты steel-3/steel; 0 — рамка blood-3, «!» и «НЕТ СИЛ»
##             (AC-03.3, DESIGN §6.3).
##   BOSS    — 248×8, метки фаз на 33% и 66%, `get_phase()` для баннера «ФАЗА II».
##
## След урона — второй слой, убывающий ступенями (DAMAGE_TRAIL_STEP), а не
## плавным твином (DESIGN §4.5: ступенчатая анимация).

signal values_changed(current: float, maximum: float)
signal damage_trail_finished

enum Kind { HP, STAMINA, BOSS }

@export var kind: Kind = Kind.HP:
	set(value):
		kind = value
		_apply_kind()

@export var value: float = 100.0:
	set(new_value):
		value = maxf(0.0, new_value)
		queue_redraw()

@export var max_value: float = 100.0:
	set(new_maximum):
		max_value = maxf(1.0, new_maximum)
		queue_redraw()

## Число поверх шкалы (HP: 74/100). У выносливости/босса — выключено.
@export var show_number: bool = true:
	set(value):
		show_number = value
		queue_redraw()

## След урона (gold-9), убывает ступенями.
@export var trail_enabled: bool = true:
	set(value):
		trail_enabled = value
		queue_redraw()

var _trail_ratio: float = -1.0
var _trail_timer: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_trail_ratio = -1.0


func _ready() -> void:
	_apply_kind()
	_trail_ratio = maxf(_trail_ratio, get_ratio())


func _process(delta: float) -> void:
	advance_trail(delta)


func _apply_kind() -> void:
	match kind:
		Kind.HP:
			custom_minimum_size = UITokens.BAR_HP_SIZE
			show_number = true
		Kind.STAMINA:
			custom_minimum_size = UITokens.BAR_STAMINA_SIZE
			show_number = false
		Kind.BOSS:
			custom_minimum_size = UITokens.BAR_BOSS_SIZE
			show_number = false
	queue_redraw()


## Установить значения (HP/выносливость/босс). След урона стартует со старой
## доли, если значение уменьшилось; при лечении — сбрасывается.
func set_values(new_value: float, new_maximum: float) -> void:
	var old_ratio: float = get_ratio()
	max_value = maxf(1.0, new_maximum)
	value = clampf(new_value, 0.0, max_value)
	var current_ratio: float = get_ratio()
	if current_ratio > old_ratio:
		_trail_ratio = current_ratio
	elif trail_enabled:
		_trail_ratio = maxf(_trail_ratio, old_ratio)
	_trail_ratio = maxf(_trail_ratio, current_ratio)
	_trail_timer = 0.0
	values_changed.emit(value, max_value)
	queue_redraw()


func get_ratio() -> float:
	return clampf(value / maxf(1.0, max_value), 0.0, 1.0)


## Количество сегментов при текущем размере (3 px + 1 px зазор).
func get_segment_count() -> int:
	var content_width: int = int(size.x) - (UITokens.BORDER_BAR + 1) * 2
	if content_width <= 0:
		content_width = int(custom_minimum_size.x) - (UITokens.BORDER_BAR + 1) * 2
	var pitch: int = UITokens.BAR_SEGMENT + UITokens.BAR_SEGMENT_GAP
	return maxi(1, int(floor(float(content_width + UITokens.BAR_SEGMENT_GAP) / float(pitch))))


func get_filled_segments() -> int:
	var ratio: float = get_ratio()
	if ratio <= 0.0:
		return 0
	return maxi(1, int(round(ratio * float(get_segment_count()))))


func get_trail_ratio() -> float:
	return get_ratio() if _trail_ratio < 0.0 else _trail_ratio


func get_trail_segments() -> int:
	return int(round(get_trail_ratio() * float(get_segment_count())))


## Ступенчатое убывание следа урона. Публичный — тесты не ждут реальные таймеры.
func advance_trail(delta: float) -> void:
	if not trail_enabled:
		_trail_ratio = get_ratio()
		return
	var ratio: float = get_ratio()
	var trail: float = get_trail_ratio()
	if trail <= ratio + 0.0001:
		return
	_trail_timer += delta
	var segments: int = get_segment_count()
	var changed: bool = false
	while _trail_timer >= UITokens.DAMAGE_TRAIL_STEP and trail > ratio:
		_trail_timer -= UITokens.DAMAGE_TRAIL_STEP
		trail = maxf(ratio, trail - 1.0 / float(segments))
		_trail_ratio = trail
		changed = true
	if changed:
		queue_redraw()
		if trail <= ratio + 0.0001:
			damage_trail_finished.emit()


func is_critical() -> bool:
	return kind == Kind.HP and get_ratio() < UITokens.HP_CRITICAL_RATIO


func is_exhausted() -> bool:
	return kind == Kind.STAMINA and value <= 0.0


## Фаза босса: 1 (100–66%), 2 (66–33%), 3 (< 33%). Для остальных видов — 1.
func get_phase() -> int:
	if kind != Kind.BOSS:
		return 1
	var ratio: float = get_ratio()
	if ratio > UITokens.BOSS_PHASE_MARKS[1]:
		return 1
	if ratio > UITokens.BOSS_PHASE_MARKS[0]:
		return 2
	return 3


## Текстовая дублёр-подпись состояния (не только цвет): «НЕТ СИЛ», «КРИТИЧНО».
func get_state_text() -> String:
	if is_exhausted():
		return "НЕТ СИЛ"
	if is_critical():
		return "КРИТИЧНО"
	return ""


func get_fill_colors() -> Array:
	match kind:
		Kind.STAMINA:
			return [UITokens.STEEL_3, UITokens.STEEL]
		_:
			return [UITokens.BLOOD_3, UITokens.BLOOD]


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var content := Rect2(
		Vector2(UITokens.BORDER_BAR + 1, UITokens.BORDER_BAR + 1),
		size - Vector2((UITokens.BORDER_BAR + 1) * 2, (UITokens.BORDER_BAR + 1) * 2)
	)
	if content.size.x <= 0.0 or content.size.y <= 0.0:
		return

	var frame_color: Color = UITokens.STONE_3
	if is_exhausted() or is_critical():
		frame_color = UITokens.BLOOD_3

	draw_rect(rect, frame_color)
	draw_rect(rect.grow(-1), UITokens.VOID)

	var colors: Array = get_fill_colors()
	var pitch: int = UITokens.BAR_SEGMENT + UITokens.BAR_SEGMENT_GAP
	var segments: int = get_segment_count()
	var trail_segments: int = mini(get_trail_segments(), segments)
	var filled_segments: int = mini(get_filled_segments(), segments)

	if trail_enabled:
		for i in trail_segments:
			var trail_x: float = content.position.x + float(i * pitch)
			draw_rect(
				Rect2(trail_x, content.position.y, float(UITokens.BAR_SEGMENT), content.size.y),
				UITokens.GOLD_9
			)

	for i in filled_segments:
		var segment_x: float = content.position.x + float(i * pitch)
		draw_rect(
			Rect2(segment_x, content.position.y, float(UITokens.BAR_SEGMENT), content.size.y),
			colors[0]
		)
		draw_rect(
			Rect2(
				segment_x + float(UITokens.BAR_SEGMENT),
				content.position.y,
				float(UITokens.BAR_SEGMENT_GAP),
				content.size.y
			),
			colors[1]
		)
		if content.size.y >= 3.0:
			draw_rect(
				Rect2(segment_x, content.position.y, float(UITokens.BAR_SEGMENT), 2.0),
				UITokens.BAR_HIGHLIGHT
			)

	if kind == Kind.BOSS:
		for mark in UITokens.BOSS_PHASE_MARKS:
			var mark_x: float = content.position.x + floor(content.size.x * mark)
			draw_rect(
				Rect2(mark_x, content.position.y, 2.0, content.size.y),
				UITokens.VOID
			)

	if show_number:
		_draw_number(content)
	elif is_exhausted():
		# AC-03.3: не только цвет — знак «!» поверх пустой шкалы.
		UIStyle.draw_bang(
			self,
			Rect2(content.position.x, content.position.y - 1, 6, 6),
			UITokens.BLOOD,
			UITokens.BONE
		)


func _draw_number(content: Rect2) -> void:
	var text: String = "%d/%d" % [int(round(value)), int(round(max_value))]
	var baseline: float = (
		content.position.y
		+ (content.size.y - UIStyle.text_height(UITokens.FONT_BODY)) * 0.5
		+ UIStyle.baseline_y(UITokens.FONT_BODY)
	)
	UIStyle.draw_text(
		self,
		Vector2(content.position.x - 1.0, baseline),
		text,
		UITokens.BONE,
		UITokens.FONT_BODY,
		content.size.x - 2.0,
		HORIZONTAL_ALIGNMENT_RIGHT,
		true
	)
