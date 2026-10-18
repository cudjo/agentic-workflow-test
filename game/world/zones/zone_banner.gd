class_name ZoneBanner
extends CanvasLayer
## Баннер зоны при входе (T-14, DESIGN §8.6): заголовок h2 + «Зона 1 · Хаб».
##
## Подписывается на EventBus.zone_entered (его эмитит ZoneScene из T-13) и
## показывает название зоны один раз за жизнь сцены — «при первом входе».
## Слой 15: выше мира и HUD (10), ниже модального UI (20); ввод не перехватывает
## (mouse_filter = IGNORE).
##
## UI минимальный: баннер не заменяет HUD (T-19) и экран загрузки (T-17),
## цвета/размеры берутся из UITokens (T-18).

enum Phase { HIDDEN, FADE_IN, HOLD, FADE_OUT }

## Слой баннера: над HUD (10) и миром, под модальным UI (20).
const BANNER_LAYER := 15
const TITLE_WIDTH := 480.0
const TITLE_TOP := 52.0
const RULE_WIDTH := 160.0
const VIEW_WIDTH := 480.0
const VIEW_HEIGHT := 270.0
## Ступенчатый fade (DESIGN §4.5): 4 шага.
const FADE_STEPS := UITokens.FADE_STEPS

@export var zone_id: StringName = &""
@export var subtitle: String = ""
@export var fade_in_time: float = 0.2
@export var hold_time: float = 1.8
@export var fade_out_time: float = 0.3

var title_label: Label
var subtitle_label: Label
var rule: ColorRect

var _root: Control
var _phase: Phase = Phase.HIDDEN
var _timer: float = 0.0
var _shown: bool = false


func _ready() -> void:
	layer = BANNER_LAYER
	_build_ui()
	visible = false
	set_process(false)

	if zone_id == &"":
		var zone := get_parent() as ZoneScene
		if zone != null and zone.zone_data != null:
			zone_id = zone.zone_data.id

	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(&"zone_entered"):
		bus.connect(&"zone_entered", _on_zone_entered)


## Показать баннер для зоны. Повторный вызов игнорируется: вход — первый.
func show_banner(display_name: String) -> void:
	if _shown:
		return
	_shown = true
	if title_label == null:
		_build_ui()
	title_label.text = display_name.to_upper()
	visible = true
	_root.modulate.a = 0.0
	_phase = Phase.FADE_IN
	_timer = 0.0
	set_process(true)


## Немедленно скрыть (вызывается тестами и переходами зон).
func hide_now() -> void:
	_phase = Phase.HIDDEN
	_timer = 0.0
	_root.modulate.a = 0.0
	visible = false
	set_process(false)


func is_banner_visible() -> bool:
	return visible and _root != null and _root.modulate.a > 0.0


func _on_zone_entered(id: StringName, display_name: String) -> void:
	if zone_id != &"" and id != zone_id:
		return
	show_banner(display_name)


func _process(delta: float) -> void:
	_timer += delta
	match _phase:
		Phase.FADE_IN:
			_root.modulate.a = _stepped_alpha(_timer / maxf(fade_in_time, 0.001))
			if _timer >= fade_in_time:
				_timer = 0.0
				_phase = Phase.HOLD
		Phase.HOLD:
			_root.modulate.a = 1.0
			if _timer >= hold_time:
				_timer = 0.0
				_phase = Phase.FADE_OUT
		Phase.FADE_OUT:
			_root.modulate.a = _stepped_alpha(1.0 - _timer / maxf(fade_out_time, 0.001))
			if _timer >= fade_out_time:
				hide_now()
		_:
			set_process(false)


func _stepped_alpha(raw: float) -> float:
	var clamped := clampf(raw, 0.0, 1.0)
	return float(int(clamped * FADE_STEPS)) / float(FADE_STEPS)


func _build_ui() -> void:
	if _root != null:
		return
	var font := load(UITokens.FONT_PATH) as Font

	_root = Control.new()
	_root.name = "BannerRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.size = Vector2(VIEW_WIDTH, VIEW_HEIGHT)
	add_child(_root)

	title_label = _make_label(font, UITokens.FONT_H2, UITokens.BONE)
	title_label.name = "Title"
	title_label.position = Vector2(0.0, TITLE_TOP)
	title_label.size = Vector2(TITLE_WIDTH, 20.0)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(title_label)

	rule = ColorRect.new()
	rule.name = "Rule"
	rule.color = UITokens.GOLD_9
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.position = Vector2((VIEW_WIDTH - RULE_WIDTH) * 0.5, TITLE_TOP + 24.0)
	rule.size = Vector2(RULE_WIDTH, 2.0)
	_root.add_child(rule)

	subtitle_label = _make_label(font, UITokens.FONT_BODY, UITokens.STONE_5)
	subtitle_label.name = "Subtitle"
	subtitle_label.position = Vector2(0.0, TITLE_TOP + 30.0)
	subtitle_label.size = Vector2(TITLE_WIDTH, UITokens.LINE_BODY)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.text = subtitle
	subtitle_label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	subtitle_label.add_theme_constant_override("shadow_offset_x", 1)
	subtitle_label.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(subtitle_label)


func _make_label(font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
