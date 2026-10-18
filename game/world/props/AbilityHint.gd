class_name AbilityHint
extends Node2D
## AbilityHint — подсказка «Нужно: <СПОСОБНОСТЬ>» + замок над ability gate
## (T-09, AC-02.4, PLAN §3.3).
##
## Локальная видимая подсказка обязательна: без неё физический блок выглядел бы
## «скрытой блокировкой». HUD (T-19) получает то же состояние отдельно через
## `EventBus.ability_hint_changed` — сигнал эмитит `AbilityGate`, когда игрок
## входит/выходит из зоны подсказки или способность получена.
##
## Узел живёт в мировых координатах (`top_level = true`), чтобы масштаб
## препятствия (например, ×2.5 у завала) не растягивал 8-px текст.
## Владелец (`AbilityGate`) задаёт позицию через `set_world_position()`.

const PADDING_X: float = 3.0
const PADDING_Y: float = 2.0
const ICON_WIDTH: float = 7.0
const ICON_GAP: float = 3.0
const BORDER: float = 1.0
const HINT_PREFIX: String = "Нужно:"

var _ability_id: StringName = &""
var _text: String = ""
var _shown: bool = false
var _label: Label
var _panel_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	top_level = true
	_ensure_label()
	visible = false


func _ensure_label() -> void:
	if _label != null:
		return
	_label = Label.new()
	_label.name = "HintLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", UIStyle.font())
	_label.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	_label.add_theme_color_override("font_color", UITokens.BONE)
	_label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)


## Показать подсказку для способности. `label_override` — имя из данных
## (`AbilityGateData.hint_label`); пусто — `AbilityRegistry.display_name`.
func show_required(ability_id: StringName, label_override: String = "") -> void:
	if ability_id == &"":
		hide_hint()
		return
	_ability_id = ability_id
	var display: String = label_override.strip_edges()
	if display.is_empty():
		var ability: AbilityBase = AbilityRegistry.get_ability(ability_id)
		if ability != null and not ability.display_name.is_empty():
			display = ability.display_name
		else:
			display = String(ability_id)
	_text = "%s %s" % [HINT_PREFIX, display.to_upper()]
	_shown = true
	_apply()


func hide_hint() -> void:
	_shown = false
	_ability_id = &""
	_text = ""
	visible = false
	if _label != null:
		_label.text = ""


func is_shown() -> bool:
	return _shown


func get_text() -> String:
	return _text


func get_ability_id() -> StringName:
	return _ability_id


## Мировые координаты текста (владелец пересчитывает при масштабе/перемещении).
func set_world_position(world_position: Vector2) -> void:
	top_level = true
	global_position = world_position


func _apply() -> void:
	_ensure_label()
	_label.text = _text
	var text_size: Vector2 = Vector2(
		UIStyle.text_width(_text, UITokens.FONT_BODY),
		UIStyle.text_height(UITokens.FONT_BODY)
	)
	_panel_size = Vector2(
		PADDING_X * 2.0 + ICON_WIDTH + ICON_GAP + text_size.x,
		PADDING_Y * 2.0 + text_size.y
	)
	_label.position = Vector2(
		-_panel_size.x * 0.5 + PADDING_X + ICON_WIDTH + ICON_GAP,
		-_panel_size.y * 0.5 + PADDING_Y - 1.0
	)
	_label.size = Vector2(text_size.x + 1.0, text_size.y + 2.0)
	visible = _shown
	queue_redraw()


func _draw() -> void:
	if not _shown or _panel_size == Vector2.ZERO:
		return
	var rect: Rect2 = Rect2(-_panel_size * 0.5, _panel_size)
	draw_rect(rect, Color(UITokens.NIGHT_9, 0.92))
	draw_rect(rect, UITokens.STONE_5, false, BORDER)

	# Замок: дужка + корпус, читается на 8 px и дублирует смысл текстом.
	var icon_x: float = rect.position.x + PADDING_X
	var icon_y: float = -3.0
	draw_rect(Rect2(icon_x + 1.0, icon_y - 5.0, 5.0, 5.0), UITokens.GOLD_3, false, 1.0)
	draw_rect(Rect2(icon_x, icon_y, ICON_WIDTH, 5.0), UITokens.GOLD_3)
	draw_rect(Rect2(icon_x + 3.0, icon_y + 2.0, 1.0, 2.0), UITokens.VOID)
