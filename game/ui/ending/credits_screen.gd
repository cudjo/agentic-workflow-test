class_name CreditsScreen
extends Control
## CreditsScreen — титры после концовки (T-32).
##
## Полноэкранный Control на токенах T-18: void-фон, панель `AshenPanel`,
## заголовок gold-3 и медленно прокручиваемые строки. Прокрутка завершается
## сама (`AUTO_SCROLL_TIME`) или по `ui_accept`/`advance()`, после чего
## испускается `credits_finished` — «полный проход до титров» завершён.

signal credits_finished

const AUTO_SCROLL_TIME: float = 8.0
const SCROLL_PIXELS_PER_SECOND: float = 18.0

const CREDITS_LINES: Array[String] = [
	"ui.credits.title_line",
	"ui.credits.english_title",
	"",
	"ui.credits.chapter",
	"",
	"ui.credits.team",
	"ui.credits.engine",
	"ui.credits.font",
	"ui.credits.sound",
	"",
	"ui.credits.thanks",
]

var _background: ColorRect
var _panel: AshenPanel
var _title: Label
var _scroll: ScrollContainer
var _column: VBoxContainer
var _hint: AshenPrompt
var _line_labels: Array[Label] = []
var _elapsed: float = 0.0
var _finished: bool = false


func _init() -> void:
	name = "CreditsScreen"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _on_locale_changed(_code: String) -> void:
	if _title == null:
		return
	_title.text = tr("ui.credits.title")
	_hint.setup(&"ui_accept", tr("ui.credits.finish_hint"))
	for index: int in _line_labels.size():
		var key: String = CREDITS_LINES[index]
		_line_labels[index].text = tr(key) if not key.is_empty() else ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func show_credits() -> void:
	_ensure_built()
	_elapsed = 0.0
	_finished = false
	visible = true
	move_to_front()
	if _scroll != null:
		_scroll.scroll_vertical = 0


func is_credits_visible() -> bool:
	return visible


func is_finished() -> bool:
	return _finished


func get_lines_count() -> int:
	return CREDITS_LINES.size()


func get_lines() -> Array[String]:
	var copy: Array[String] = []
	copy.assign(CREDITS_LINES)
	return copy


## Пропустить/завершить титры (ui_accept, кнопка, тест).
func advance() -> void:
	if not visible:
		return
	finish()


func finish() -> void:
	if _finished:
		return
	_finished = true
	credits_finished.emit()


func _process(delta: float) -> void:
	if not visible or _finished:
		return
	_elapsed += delta
	if _scroll != null:
		_scroll.scroll_vertical = int(_elapsed * SCROLL_PIXELS_PER_SECOND)
	if _elapsed >= AUTO_SCROLL_TIME:
		finish()


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

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = AshenPanel.new()
	_panel.variant = UIStyle.PanelVariant.INSET
	_panel.padding = UITokens.PANEL_PADDING_DIALOG
	_panel.custom_minimum_size = Vector2(420.0, 200.0)
	center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITokens.SP_3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	_title = Label.new()
	_title.text = tr("ui.credits.title")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", UIStyle.font())
	_title.add_theme_font_size_override("font_size", UITokens.FONT_H2)
	_title.add_theme_color_override("font_color", UITokens.GOLD_3)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(380.0, 130.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_scroll)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", UITokens.SP_2)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_column)

	_line_labels.clear()
	for line: String in CREDITS_LINES:
		var label := Label.new()
		label.text = tr(line) if not line.is_empty() else ""
		_line_labels.append(label)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", UIStyle.font())
		label.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
		label.add_theme_color_override(
			"font_color",
			UITokens.BONE if not line.is_empty() else UITokens.STONE_9
		)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_column.add_child(label)

	if not Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.connect(_on_locale_changed)
	_hint = AshenPrompt.new()
	_hint.setup(&"ui_accept", tr("ui.credits.finish_hint"))
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or event == null:
		return
	if event.is_action_pressed(&"ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		finish()
