class_name AshenDialog
extends Control
## AshenDialog — диалоговое окно (DESIGN §5, §6.4, T-28).
##
## Состав: портрет 52×52, имя gold-3 + фракция stone-5, реплика с печатью
## 1 символ / 22 мс (Enter/Space — показать сразу), ответы 2×2 с кареткой и
## тегом последствия «[Орден+1]» (steel-3). Все ответы — AshenMenuItem,
## поэтому фокус/состояния §6.1 переиспользуются без дублирования стилей.
##
## При instant_text (режим «Без мигания», DESIGN §9.3) текст появляется сразу.

signal choice_selected(index: int)
signal typing_finished

const BODY_X := UITokens.PORTRAIT_DIALOG + UITokens.SP_1

@export var instant_text: bool = false
@export var focus_answers_on_finish: bool = true

var _portrait_panel: AshenPanel
var _portrait_image: TextureRect
var _portrait_placeholder: _DialogPortrait
var _body_panel: AshenPanel
var _name_label: Label
var _faction_label: Label
var _text_label: RichTextLabel
var _answers_grid: GridContainer
var _answer_items: Array[AshenMenuItem] = []
var _answer_data: Array[Dictionary] = []

var _typing: bool = false
var _accumulator: float = 0.0
var _visible_chars: int = 0
var _total_chars: int = 0
var _built: bool = false


func _init() -> void:
	custom_minimum_size = UITokens.DIALOG_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	_ensure_built()
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()


func _process(delta: float) -> void:
	if _typing:
		advance_typing(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _typing and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select")):
		reveal_all()
		get_viewport().set_input_as_handled()


## Настроить диалог. answers: [{text, tag, disabled, reason}, …] (до 4, сетка 2×2).
func setup(display_name: String, dialogue_text: String, answers: Array = [], faction: String = "") -> void:
	_ensure_built()
	_name_label.text = display_name
	_faction_label.text = faction
	_faction_label.visible = faction != ""
	_clear_answers()

	for index in answers.size():
		var data: Dictionary = answers[index]
		var item := AshenMenuItem.new()
		item.text = String(data.get("text", ""))
		item.prefix_tag = String(data.get("tag", ""))
		item.font_size = UITokens.FONT_BODY
		item.disabled = bool(data.get("disabled", false))
		item.disabled_reason = String(data.get("reason", ""))
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.pressed.connect(_on_answer_pressed.bind(index))
		_answers_grid.add_child(item)
		_answer_items.append(item)
		_answer_data.append(data)

	_text_label.text = dialogue_text
	_total_chars = dialogue_text.length()
	_visible_chars = 0
	_accumulator = 0.0
	_text_label.visible_characters = 0
	_typing = _total_chars > 0 and not instant_text
	_set_answers_focusable(not _typing)
	if not _typing:
		_visible_chars = _total_chars
		_text_label.visible_characters = -1
		_finish_typing()


## Досрочно показать весь текст (Enter/Space или reduced motion).
func reveal_all() -> void:
	if not _typing:
		return
	_visible_chars = _total_chars
	_text_label.visible_characters = -1
	_finish_typing()


## Продвинуть печать на `delta` секунд. Публичный — тесты не ждут реального времени.
func advance_typing(delta: float) -> int:
	if not _typing:
		return _visible_chars
	_accumulator += delta
	while _accumulator >= UITokens.TYPE_SPEED and _visible_chars < _total_chars:
		_accumulator -= UITokens.TYPE_SPEED
		_visible_chars += 1
	_text_label.visible_characters = _visible_chars
	if _visible_chars >= _total_chars:
		_finish_typing()
	return _visible_chars


func is_typing() -> bool:
	return _typing


func get_visible_characters() -> int:
	return _visible_chars


func get_total_characters() -> int:
	return _total_chars


func get_answer_count() -> int:
	return _answer_items.size()


func get_answer_columns() -> int:
	return _answers_grid.columns if _answers_grid != null else 0


func get_answer_item(index: int) -> AshenMenuItem:
	if index < 0 or index >= _answer_items.size():
		return null
	return _answer_items[index]


func get_answer_tag(index: int) -> String:
	if index < 0 or index >= _answer_data.size():
		return ""
	return String(_answer_data[index].get("tag", ""))


func get_display_name() -> String:
	return _name_label.text if _name_label != null else ""


func get_body_text() -> String:
	return _text_label.text if _text_label != null else ""


func set_portrait(texture: Texture2D) -> void:
	_ensure_built()
	_portrait_image.texture = texture
	_portrait_image.visible = texture != null
	_portrait_placeholder.visible = texture == null


func _ensure_built() -> void:
	if _built:
		return
	_built = true

	_portrait_panel = AshenPanel.new()
	_portrait_panel.variant = UIStyle.PanelVariant.SOLID
	_portrait_panel.padding = UITokens.SP_1
	_portrait_panel.position = Vector2.ZERO
	_portrait_panel.size = Vector2(UITokens.PORTRAIT_DIALOG, UITokens.PORTRAIT_DIALOG)
	_portrait_panel.custom_minimum_size = Vector2(UITokens.PORTRAIT_DIALOG, UITokens.PORTRAIT_DIALOG)
	add_child(_portrait_panel)

	_portrait_placeholder = _DialogPortrait.new()
	_portrait_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_panel.add_child(_portrait_placeholder)

	_portrait_image = TextureRect.new()
	_portrait_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_image.visible = false
	_portrait_panel.add_child(_portrait_image)

	_body_panel = AshenPanel.new()
	_body_panel.variant = UIStyle.PanelVariant.GLASS
	_body_panel.padding = UITokens.PANEL_PADDING
	_body_panel.position = Vector2(BODY_X, 0)
	add_child(_body_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITokens.SP_1)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	_body_panel.add_child(column)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", UITokens.SP_3)
	column.add_child(name_row)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", UIStyle.font())
	_name_label.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	_name_label.add_theme_color_override("font_color", UITokens.GOLD_3)
	name_row.add_child(_name_label)

	_faction_label = Label.new()
	_faction_label.add_theme_font_override("font", UIStyle.font())
	_faction_label.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	_faction_label.add_theme_color_override("font_color", UITokens.STONE_5)
	name_row.add_child(_faction_label)

	_text_label = RichTextLabel.new()
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.bbcode_enabled = false
	_text_label.scroll_active = false
	_text_label.fit_content = false
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(0, UITokens.LINE_BODY * 2)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_override("normal_font", UIStyle.font())
	_text_label.add_theme_font_size_override("normal_font_size", UITokens.FONT_BODY)
	_text_label.add_theme_color_override("default_color", UITokens.BONE)
	column.add_child(_text_label)

	_answers_grid = GridContainer.new()
	_answers_grid.columns = 2
	_answers_grid.add_theme_constant_override("h_separation", UITokens.SP_3)
	_answers_grid.add_theme_constant_override("v_separation", 0)
	column.add_child(_answers_grid)

	_layout()


func _layout() -> void:
	if not _built:
		return
	var dialog_width: float = maxf(size.x, UITokens.DIALOG_SIZE.x)
	var dialog_height: float = maxf(size.y, UITokens.DIALOG_SIZE.y)
	_portrait_panel.size = Vector2(UITokens.PORTRAIT_DIALOG, UITokens.PORTRAIT_DIALOG)
	_portrait_panel.custom_minimum_size = _portrait_panel.size
	_body_panel.position = Vector2(BODY_X, 0)
	_body_panel.size = Vector2(dialog_width - BODY_X, dialog_height)


func _clear_answers() -> void:
	for item in _answer_items:
		if is_instance_valid(item):
			item.queue_free()
	_answer_items.clear()
	_answer_data.clear()


func _set_answers_focusable(enabled: bool) -> void:
	for item in _answer_items:
		if not is_instance_valid(item):
			continue
		item.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		item.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _finish_typing() -> void:
	_typing = false
	_visible_chars = _total_chars
	_text_label.visible_characters = -1
	_set_answers_focusable(true)
	if focus_answers_on_finish and not _answer_items.is_empty() and is_inside_tree():
		for item in _answer_items:
			if not item.disabled:
				item.grab_focus()
				break
	typing_finished.emit()


## Выбрать ответ программно (геймпад/тесты).
func select_answer(index: int) -> void:
	if index < 0 or index >= _answer_items.size():
		return
	choice_selected.emit(index)


func _on_answer_pressed(index: int) -> void:
	choice_selected.emit(index)


## Портрет-заглушка до арта NPC (52×52): силуэт в steel/stone.
class _DialogPortrait:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UITokens.NIGHT_3)
		var center_x: float = size.x * 0.5
		# капюшон
		draw_rect(Rect2(center_x - 10, 8, 20, 4), UITokens.STONE_3)
		draw_rect(Rect2(center_x - 12, 12, 24, 4), UITokens.STONE_3)
		# лицо
		draw_rect(Rect2(center_x - 6, 12, 12, 12), UITokens.STONE_5)
		draw_rect(Rect2(center_x - 4, 16, 2, 2), UITokens.VOID)
		draw_rect(Rect2(center_x + 2, 16, 2, 2), UITokens.VOID)
		# плечи/накидка
		draw_rect(Rect2(center_x - 14, 26, 28, 18), UITokens.STEEL_9)
		draw_rect(Rect2(center_x - 3, 26, 6, 18), UITokens.STEEL)
