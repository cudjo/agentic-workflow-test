class_name EndingScreen
extends Control
## EndingScreen — экран концовки (T-32) на компонентах T-18.
##
## Полноэкранный `Control`: фон void, панель `AshenPanel` (glass), заголовок
## gold-3, текст bone, строка фракции steel-3 и фокусируемая кнопка
## `AshenMenuItem` «ДАЛЬШЕ» (клавиатура/геймпад). Текст приходит из
## `EndingCatalog.resolve()`; нейтральная концовка — при заглушке T-27.
##
## Экран не решает, когда показываться: это делает `EndingSequence`.

signal advance_requested

const PANEL_MIN_SIZE := Vector2(420.0, 0.0)
const BODY_WIDTH := 360

var _ending_id: StringName = &""
var _faction_id: StringName = &""

var _background: ColorRect
var _panel: AshenPanel
var _kicker: Label
var _title: Label
var _body: Label
var _faction: Label
var _continue: AshenMenuItem
var _credits_prompt: AshenPrompt


func _init() -> void:
	name = "EndingScreen"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if not Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.connect(_on_locale_changed)


func _exit_tree() -> void:
	if Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.disconnect(_on_locale_changed)


func _on_locale_changed(_code: String) -> void:
	_retranslate()


func _retranslate() -> void:
	if _ending_id == &"":
		return
	_continue.text = tr("ui.ending.continue")
	_credits_prompt.setup(&"ui_accept", tr("ui.ending.credits_hint"))
	if _ending_id == EndingCatalog.NEUTRAL_ID:
		show_ending(EndingCatalog.resolve(&"", String(_faction_id)), _faction_id)
	else:
		var faction_id: StringName = StringName(String(_ending_id).trim_prefix(EndingCatalog.FACTION_PREFIX))
		show_ending(EndingCatalog.resolve(faction_id, FactionManager.get_faction_name(faction_id)), faction_id)


## Показывает концовку. `ending` уже разрешён каталогом по фракции.
func show_ending(ending: EndingText, faction_id: StringName = &"") -> void:
	_ensure_built()
	if ending == null:
		return
	_ending_id = ending.id
	_faction_id = faction_id
	_kicker.text = ending.kicker
	_title.text = ending.title
	_body.text = ending.body
	_faction.text = ending.faction_line
	_title.add_theme_color_override("font_color", ending.accent)
	_panel.variant = UIStyle.PanelVariant.GLASS
	visible = true
	move_to_front()
	if _continue != null and _continue.is_inside_tree():
		_continue.grab_focus()


func hide_ending() -> void:
	visible = false


func is_ending_visible() -> bool:
	return visible


func get_ending_id() -> StringName:
	return _ending_id


func get_faction_id() -> StringName:
	return _faction_id


func get_title_text() -> String:
	_ensure_built()
	return _title.text


func get_body_text() -> String:
	_ensure_built()
	return _body.text


func get_continue_button() -> AshenMenuItem:
	_ensure_built()
	return _continue


func _ensure_built() -> void:
	if _panel == null:
		_build()


func _build() -> void:
	if _panel != null:
		return

	_background = ColorRect.new()
	_background.name = "Backdrop"
	_background.color = UITokens.VOID
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background)

	var top_rule := ColorRect.new()
	top_rule.color = UITokens.GOLD_9
	top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_rule.offset_top = 32.0
	top_rule.offset_bottom = 33.0
	add_child(top_rule)

	var bottom_rule := ColorRect.new()
	bottom_rule.color = UITokens.GOLD_9
	bottom_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_rule.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_rule.offset_top = -33.0
	bottom_rule.offset_bottom = -32.0
	add_child(bottom_rule)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = AshenPanel.new()
	_panel.variant = UIStyle.PanelVariant.GLASS
	_panel.padding = UITokens.PANEL_PADDING_DIALOG
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITokens.SP_3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	_kicker = _make_label(UITokens.FONT_BODY, UITokens.STONE_5)
	column.add_child(_kicker)

	_title = _make_label(UITokens.FONT_H2, UITokens.GOLD_3)
	column.add_child(_title)

	var divider := ColorRect.new()
	divider.color = UITokens.STONE_9
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(divider)

	_body = _make_label(UITokens.FONT_BODY, UITokens.BONE)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(BODY_WIDTH, 0.0)
	column.add_child(_body)

	_faction = _make_label(UITokens.FONT_BODY, UITokens.STEEL_3)
	column.add_child(_faction)

	_continue = AshenMenuItem.new()
	_continue.name = "Continue"
	_continue.text = tr("ui.ending.continue")
	_continue.font_size = UITokens.FONT_BODY
	_continue.custom_minimum_size = Vector2(200.0, 16.0)
	_continue.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue.pressed.connect(_on_continue_pressed)
	column.add_child(_continue)

	var prompt := AshenPrompt.new()
	_credits_prompt = prompt
	prompt.setup(&"ui_accept", tr("ui.ending.credits_hint"))
	prompt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(prompt)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UIStyle.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_continue_pressed() -> void:
	advance_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or event == null:
		return
	if event.is_action_pressed(&"ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		advance_requested.emit()
