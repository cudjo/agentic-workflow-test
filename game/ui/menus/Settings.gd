class_name AshenSettingsView
extends Control
## Settings — экран настроек и доступности (T-20, DESIGN §6.1/§9; макет
## `docs/mockups/main-menu.html`, состояние «Настройки / a11y»).
##
## Строки (сверху вниз, единый порядок фокуса):
##   Язык / Language        ←/→ RU/EN        (Config.language → TranslationServer)
##   Масштаб интерфейса     ←/→ 100/150/200  (Config.ui_scale → UI)
##   Режим окна             ←/→ окно/полный экран/без рамки (DisplayServer)
##   Читаемость силуэтов    тумблер           (Config.silhouette_readability)
##   Без мигания экрана     тумблер           (Config.no_flash)
##   Субтитры звуков        тумблер           (Config.sound_subtitles)
##   Управление (ремап)     disabled + причина «T-24» (макет ещё не нарисован)
##
## Любое изменение сразу пишется в `user://settings.cfg` через Config
## (`save_settings`) и применяется в рантайме. Управление без мыши:
## ↑/↓ — строки, ←/→ — значение, Enter/A — изменить, Esc/B — назад.
## Состояние тумблера дублируется положением ползунка и текстом ВКЛ/ВЫКЛ.

signal closed
signal settings_changed(key: String)
signal remap_requested

const PANEL_RECT := Rect2(24, 88, 376, 154)
const PANEL_RECT_200 := Rect2(24, 76, 376, 166)

const ROW_LANGUAGE: String = "language"
const ROW_UI_SCALE: String = "ui_scale"
const ROW_WINDOW_MODE: String = "window_mode"
const ROW_SILHOUETTE: String = "silhouette"
const ROW_NO_FLASH: String = "no_flash"
const ROW_SUBTITLES: String = "subtitles"
const ROW_REMAP: String = "remap"

const ROW_ORDER: Array[String] = [
	ROW_LANGUAGE,
	ROW_UI_SCALE,
	ROW_WINDOW_MODE,
	ROW_SILHOUETTE,
	ROW_NO_FLASH,
	ROW_SUBTITLES,
	ROW_REMAP,
]

var _panel: AshenPanel
var _heading: Label
var _scroll: ScrollContainer
var _box: VBoxContainer
var _rows: Array[_SettingRow] = []
var _built: bool = false
var _last_focus: int = 0


func _init() -> void:
	name = "Settings"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_ensure_built()
	if not Config.language_changed.is_connected(_on_language_changed):
		Config.language_changed.connect(_on_language_changed)
	if not Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.connect(_on_ui_scale_changed)
	_apply_scale_layout()
	refresh()


func _exit_tree() -> void:
	if Config.language_changed.is_connected(_on_language_changed):
		Config.language_changed.disconnect(_on_language_changed)
	if Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.disconnect(_on_ui_scale_changed)


# ------------------------------------------------------------------------------
# Публичный API
# ------------------------------------------------------------------------------

func open() -> void:
	_ensure_built()
	visible = true
	_apply_scale_layout()
	refresh()
	call_deferred(&"_focus_initial")


func close() -> void:
	if not visible:
		return
	visible = false
	_release_focus()
	closed.emit()


func is_open() -> bool:
	return visible


func get_rows() -> Array[_SettingRow]:
	var copy: Array[_SettingRow] = []
	copy.assign(_rows)
	return copy


func get_row(index: int) -> _SettingRow:
	if index < 0 or index >= _rows.size():
		return null
	return _rows[index]


func get_row_id(index: int) -> String:
	if index < 0 or index >= ROW_ORDER.size():
		return ""
	return ROW_ORDER[index]


func get_value_text(id: String) -> String:
	var index: int = ROW_ORDER.find(id)
	if index < 0:
		return ""
	return _rows[index].get_value_text()


func get_focused_index() -> int:
	var owner: Control = _focus_owner()
	if owner == null:
		return -1
	return _rows.find(owner)


func focus_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_rows[index].grab_focus()


## Активирует строку так же, как Enter/A (для GUT и интеграции).
func activate_row(index: int) -> void:
	if index < 0 or index >= ROW_ORDER.size():
		return
	_activate(ROW_ORDER[index])


## Меняет значение строки на шаг (←/→). Возвращает true, если значение изменилось.
func adjust_row(index: int, step: int) -> bool:
	if index < 0 or index >= ROW_ORDER.size():
		return false
	return _adjust(ROW_ORDER[index], step)


func refresh() -> void:
	if not _built:
		return
	_heading.text = tr("ui.settings.heading")

	for index: int in _rows.size():
		var row: _SettingRow = _rows[index]
		var id: String = ROW_ORDER[index]
		row.label_text = _row_label(id)
		row.disabled = id == ROW_REMAP
		# Button.disabled сбрасывает focus_mode (Godot 4.4): причина T-24
		# должна оставаться доступной с клавиатуры/геймпада (DESIGN §9.2).
		row.focus_mode = Control.FOCUS_ALL
		row.disabled_reason = (
			tr("ui.settings.remap_soon")
			if id == ROW_REMAP
			else ""
		)
		row.is_toggle = _is_toggle(id)
		row.font_size = _row_font_size()
		match id:
			ROW_LANGUAGE:
				row.value_text = tr("ui.settings.language_value")
			ROW_UI_SCALE:
				row.value_text = "%d%%" % Config.ui_scale
			ROW_WINDOW_MODE:
				row.value_text = _window_mode_text(Config.window_mode)
			ROW_SILHOUETTE:
				row.toggle_value = Config.silhouette_readability
			ROW_NO_FLASH:
				row.toggle_value = Config.no_flash
			ROW_SUBTITLES:
				row.toggle_value = Config.sound_subtitles
			ROW_REMAP:
				row.value_text = (
					tr("ui.settings.remap_input")
					if Config.ui_scale <= Config.UI_SCALE_100
					else (
						"T-24"
						if Config.ui_scale >= Config.UI_SCALE_200
						else tr("ui.settings.remap_short")
					)
				)
		row.toggle_text_on = tr("ui.common.on")
		row.toggle_text_off = tr("ui.common.off")
		row.apply_layout()
		row.set_meta(&"a11y_label", row.label_text)
		row.set_meta(&"a11y_value", row.value_text if not row.is_toggle else (tr("ui.common.on") if row.toggle_value else tr("ui.common.off")))
		row.set_meta(&"a11y_disabled_reason", row.disabled_reason)


func apply_ui_scale() -> void:
	if not _built:
		return
	_apply_scale_layout()
	var font: int = _row_font_size()
	for row: _SettingRow in _rows:
		row.font_size = font
		row.apply_layout()


func _apply_scale_layout() -> void:
	if _panel == null:
		return
	var large: bool = Config.ui_scale >= Config.UI_SCALE_200
	_panel.position = PANEL_RECT_200.position if large else PANEL_RECT.position
	_panel.size = PANEL_RECT_200.size if large else PANEL_RECT.size


func get_panel_control() -> AshenPanel:
	return _panel


# ------------------------------------------------------------------------------
# Построение
# ------------------------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = AshenPanel.new()
	_panel.name = "SettingsPanel"
	_panel.variant = UIStyle.PanelVariant.GLASS
	_panel.padding = 1
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_panel.position = PANEL_RECT.position
	_panel.size = PANEL_RECT.size

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", UITokens.SP_1)
	_panel.add_child(content)

	_heading = _make_label("", UITokens.GOLD_3, UITokens.FONT_BODY)
	_heading.name = "Heading"
	_heading.custom_minimum_size = Vector2(0, UITokens.LINE_BODY)
	content.add_child(_heading)

	_scroll = ScrollContainer.new()
	_scroll.name = "Rows"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)

	_box = VBoxContainer.new()
	_box.name = "RowList"
	_box.add_theme_constant_override("separation", 0)
	_box.custom_minimum_size = Vector2(PANEL_RECT.size.x - 28.0, 0)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)

	for id: String in ROW_ORDER:
		var row := _SettingRow.new()
		row.name = "Row_" + id
		row.focus_mode = Control.FOCUS_ALL
		row.set_meta(&"a11y_role", "switch" if _is_toggle(id) else "button")
		row.pressed.connect(_on_row_pressed.bind(id))
		row.focus_entered.connect(_on_row_focus_changed)
		row.mouse_entered.connect(_on_row_focus_changed)
		_box.add_child(row)
		_rows.append(row)


func _make_label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIStyle.font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


# ------------------------------------------------------------------------------
# Тексты
# ------------------------------------------------------------------------------

func _row_label(id: String) -> String:
	if Config.ui_scale >= Config.UI_SCALE_200:
		match id:
			ROW_LANGUAGE:
				return tr("ui.settings.row_language_short")
			ROW_UI_SCALE:
				return tr("ui.settings.row_scale_short")
			ROW_WINDOW_MODE:
				return tr("ui.settings.row_window_short")
			ROW_SILHOUETTE:
				return tr("ui.settings.row_silhouette_short")
			ROW_NO_FLASH:
				return tr("ui.settings.row_no_flash_short")
			ROW_SUBTITLES:
				return tr("ui.settings.row_subtitles_short")
			ROW_REMAP:
				return tr("ui.settings.row_remap_short")
		return ""
	match id:
		ROW_LANGUAGE:
			return tr("ui.settings.row_language")
		ROW_UI_SCALE:
			return tr("ui.settings.row_scale")
		ROW_WINDOW_MODE:
			return tr("ui.settings.row_window")
		ROW_SILHOUETTE:
			return tr("ui.settings.row_silhouette")
		ROW_NO_FLASH:
			return tr("ui.settings.row_no_flash")
		ROW_SUBTITLES:
			return tr("ui.settings.row_subtitles")
		ROW_REMAP:
			return tr("ui.settings.row_remap")
	return ""


func _window_mode_text(mode: int) -> String:
	match mode:
		Config.WINDOW_FULLSCREEN:
			return tr("ui.settings.window_fullscreen")
		Config.WINDOW_BORDERLESS:
			return tr("ui.settings.window_borderless")
		_:
			return tr("ui.settings.window_windowed")


func _is_toggle(id: String) -> bool:
	return id in [ROW_SILHOUETTE, ROW_NO_FLASH, ROW_SUBTITLES]


func _row_font_size() -> int:
	return UITokens.FONT_BODY * Config.ui_scale / 100


# ------------------------------------------------------------------------------
# Изменение значений
# ------------------------------------------------------------------------------

func _on_row_pressed(id: String) -> void:
	_activate(id)


func _activate(id: String) -> void:
	match id:
		ROW_LANGUAGE:
			Config.set_language(Config.LANGUAGE_EN if not Config.is_english() else Config.LANGUAGE_RU)
		ROW_UI_SCALE:
			Config.ui_scale = Config.next_ui_scale(Config.ui_scale, 1)
		ROW_WINDOW_MODE:
			Config.window_mode = wrapi(Config.window_mode + 1, 0, 3)
		ROW_SILHOUETTE:
			Config.set_silhouette_readability(not Config.silhouette_readability)
		ROW_NO_FLASH:
			Config.set_no_flash(not Config.no_flash)
		ROW_SUBTITLES:
			Config.set_sound_subtitles(not Config.sound_subtitles)
		ROW_REMAP:
			# Пункт disabled: причина уже видна в строке (T-24).
			remap_requested.emit()
			return
		_:
			return
	_after_change(id)


func _adjust(id: String, step: int) -> bool:
	if id == ROW_REMAP:
		remap_requested.emit()
		return false
	match id:
		ROW_LANGUAGE:
			Config.set_language(Config.LANGUAGE_EN if step > 0 else Config.LANGUAGE_RU)
		ROW_UI_SCALE:
			Config.ui_scale = Config.next_ui_scale(Config.ui_scale, step)
		ROW_WINDOW_MODE:
			Config.window_mode = wrapi(Config.window_mode + step, 0, 3)
		ROW_SILHOUETTE:
			Config.set_silhouette_readability(step > 0)
		ROW_NO_FLASH:
			Config.set_no_flash(step > 0)
		ROW_SUBTITLES:
			Config.set_sound_subtitles(step > 0)
		_:
			return false
	_after_change(id)
	return true


func _after_change(id: String) -> void:
	Config.save_settings()
	settings_changed.emit(id)
	refresh()


func _on_language_changed(_code: String) -> void:
	refresh()


func _on_ui_scale_changed(_scale: int) -> void:
	apply_ui_scale()
	refresh()


func _on_row_focus_changed() -> void:
	var index: int = get_focused_index()
	if index >= 0:
		_last_focus = index


# ------------------------------------------------------------------------------
# Ввод
# ------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		_consume_input()
		return
	if event.is_action_pressed(&"ui_down", true):
		_move_focus(1)
		_consume_input()
	elif event.is_action_pressed(&"ui_up", true):
		_move_focus(-1)
		_consume_input()
	elif event.is_action_pressed(&"ui_left", true) or event.is_action_pressed(&"ui_right", true):
		var index: int = get_focused_index()
		if index < 0:
			index = _last_focus
		var step: int = 1 if event.is_action_pressed(&"ui_right", true) else -1
		adjust_row(index, step)
		_consume_input()


func _move_focus(step: int) -> void:
	if _rows.is_empty():
		return
	var current: int = get_focused_index()
	var next: int = 0 if current < 0 else wrapi(current + step, 0, _rows.size())
	if current < 0 and step < 0:
		next = _rows.size() - 1
	focus_row(next)


func _focus_initial() -> void:
	if not visible or _rows.is_empty():
		return
	focus_row(clampi(_last_focus, 0, _rows.size() - 1))


func _release_focus() -> void:
	var owner: Control = _focus_owner()
	if owner != null and is_ancestor_of(owner):
		owner.release_focus()


func _focus_owner() -> Control:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	return viewport.gui_get_focus_owner()


func _consume_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


# ------------------------------------------------------------------------------
# Строка настройки: label слева, значение/тумблер справа, видимый фокус
# ------------------------------------------------------------------------------

class _SettingRow extends Button:
	var label_text: String = "":
		set(value):
			label_text = value
			queue_redraw()
	var value_text: String = "":
		set(value):
			value_text = value
			queue_redraw()
	var is_toggle: bool = false:
		set(value):
			is_toggle = value
			queue_redraw()
	var toggle_value: bool = false:
		set(value):
			toggle_value = value
			queue_redraw()
	var toggle_text_on: String = "ui.common.on"
	var toggle_text_off: String = "ui.common.off"
	var font_size: int = UITokens.FONT_BODY:
		set(value):
			font_size = value
			apply_layout()
	var disabled_reason: String = "":
		set(value):
			disabled_reason = value
			tooltip_text = value
			apply_layout()

	func _init() -> void:
		UIStyle.make_custom_button(self)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		mouse_entered.connect(_on_mouse_entered)
		apply_layout()

	func apply_layout() -> void:
		custom_minimum_size = Vector2(0, float(get_row_height()))
		queue_redraw()

	func get_row_height() -> int:
		var base: int = maxi(UITokens.ROW_MENU_BODY, font_size + UITokens.SP_1)
		if disabled and not disabled_reason.is_empty():
			base += UITokens.LINE_BODY
		return base

	func get_value_text() -> String:
		if is_toggle:
			return tr(toggle_text_on) if toggle_value else tr(toggle_text_off)
		return value_text

	func is_focus_visible() -> bool:
		return has_focus() and focus_mode == Control.FOCUS_ALL

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		var focused: bool = is_focus_visible()
		var hovered: bool = is_hovered()
		var padding: int = UITokens.PANEL_PADDING
		var base_row: int = maxi(UITokens.ROW_MENU_BODY, font_size + UITokens.SP_1)
		var baseline: float = (
			(float(base_row) - UIStyle.text_height(font_size)) * 0.5
			+ UIStyle.baseline_y(font_size)
		)

		if focused:
			draw_rect(rect, UITokens.NIGHT_3)
		if focused or hovered:
			UIStyle.draw_frame(self, rect, UITokens.BORDER_INNER, UITokens.GOLD_9)
		if focused:
			UIStyle.draw_focus_brackets(
				self,
				rect.grow(-2),
				UITokens.GOLD_3,
				UITokens.FOCUS_ARM,
				UITokens.BORDER_INNER
			)

		var cursor_x: float = float(padding)
		if focused:
			UIStyle.draw_text(
				self,
				Vector2(cursor_x, baseline),
				">",
				UITokens.GOLD_3,
				font_size
			)
			cursor_x += float(font_size) + float(UITokens.SP_1)

		var value_width: float = _value_width()
		var label_width: float = maxf(
			size.x - cursor_x - value_width - float(padding),
			0.0
		)
		var label_color: Color = UITokens.STONE_3
		if not disabled:
			label_color = UITokens.BONE if (focused or hovered) else UITokens.STONE_5
		UIStyle.draw_text(
			self,
			Vector2(cursor_x, baseline),
			label_text,
			label_color,
			font_size,
			label_width
		)

		if is_toggle:
			_draw_toggle(rect, baseline)
		else:
			_draw_value(rect, baseline)

		if disabled and not disabled_reason.is_empty():
			UIStyle.draw_text(
				self,
				Vector2(cursor_x, baseline + float(UITokens.LINE_BODY)),
				disabled_reason,
				UITokens.STONE_5,
				UITokens.FONT_BODY,
				size.x - cursor_x - float(padding)
			)

	func _value_width() -> float:
		var padding: float = float(UITokens.PANEL_PADDING)
		if is_toggle:
			return (
				UIStyle.text_width(toggle_text_on, UITokens.FONT_BODY)
				+ float(UITokens.SP_2)
				+ float(UITokens.TOGGLE_TRACK.x)
				+ padding
			)
		var arrows: float = UIStyle.text_width("< ", UITokens.FONT_BODY) \
			+ UIStyle.text_width(" >", UITokens.FONT_BODY)
		return arrows + UIStyle.text_width(value_text, font_size) + padding

	func _draw_value(rect: Rect2, baseline: float) -> void:
		var padding: float = float(UITokens.PANEL_PADDING)
		var left_text: String = "< "
		var right_text: String = " >"
		var value_width: float = UIStyle.text_width(value_text, font_size)
		var left_width: float = UIStyle.text_width(left_text, UITokens.FONT_BODY)
		var right_width: float = UIStyle.text_width(right_text, UITokens.FONT_BODY)
		var total: float = left_width + value_width + right_width
		var x: float = rect.size.x - padding - total
		var color: Color = UITokens.STONE_3 if disabled else UITokens.GOLD_3
		UIStyle.draw_text(self, Vector2(x, baseline), left_text, color, UITokens.FONT_BODY)
		UIStyle.draw_text(
			self,
			Vector2(x + left_width, baseline),
			value_text,
			UITokens.STONE_3 if disabled else UITokens.BONE,
			font_size
		)
		UIStyle.draw_text(
			self,
			Vector2(x + left_width + value_width, baseline),
			right_text,
			color,
			UITokens.FONT_BODY
		)

	func _draw_toggle(rect: Rect2, baseline: float) -> void:
		var padding: float = float(UITokens.PANEL_PADDING)
		var track_width: float = float(UITokens.TOGGLE_TRACK.x)
		var track_height: float = float(UITokens.TOGGLE_TRACK.y)
		var track_x: float = rect.size.x - padding - track_width
		var track_y: float = (rect.size.y - track_height) * 0.5
		var on: bool = toggle_value
		var text: String = toggle_text_on if on else toggle_text_off
		var text_color: Color = UITokens.STONE_3 if disabled else (
			UITokens.STEEL_3 if on else UITokens.STONE_5
		)
		UIStyle.draw_text(
			self,
			Vector2(
				track_x - UIStyle.text_width(text, UITokens.FONT_BODY) - float(UITokens.SP_2),
				baseline
			),
			text,
			text_color,
			UITokens.FONT_BODY
		)
		draw_rect(
			Rect2(track_x, track_y, track_width, track_height),
			UITokens.STONE_9 if not disabled else UITokens.NIGHT_3
		)
		UIStyle.draw_frame(
			self,
			Rect2(track_x, track_y, track_width, track_height),
			UITokens.BORDER_INNER,
			UITokens.GOLD if on and not disabled else UITokens.STONE_3
		)
		var knob_x: float = track_x + (7.0 if on else 1.0)
		draw_rect(
			Rect2(
				knob_x,
				track_y + 1.0,
				float(UITokens.TOGGLE_KNOB),
				track_height - 2.0
			),
			UITokens.GOLD if on and not disabled else UITokens.STONE_5
		)

	func _on_mouse_entered() -> void:
		if is_inside_tree():
			grab_focus()
