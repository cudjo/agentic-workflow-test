class_name AshenSaveSlots
extends Control
## SaveSlots — список сохранений главного меню (T-20, DESIGN §6.4/§6.6,
## SPEC §7.4, EC-07; макет `docs/mockups/main-menu.html`, состояние «Загрузка»).
##
## Три карточки из `SaveManager.get_slot_metadata`:
##   * занят     — зона/уровень/время/дата;
##   * пуст      — «— Пусто —», пунктирная рамка;
##   * повреждён — «Файл повреждён» + причина + «!» (не только цветом), EC-07.
##
## Повреждённый/пустой слот не грузится и не роняет экран: показывается
## предупреждение и фокус переводится на другой слот. Валидный слот отдаёт
## сигнал `slot_selected` — загрузку выполняет MainMenu.
##
## Управление: ↑/↓/D-pad — карточки, Enter/A — выбрать, Esc/B — назад.
## Фокус виден на каждой карточке (золотая рамка 2 px + скобки).

signal closed
signal slot_selected(slot: int)

const PANEL_RECT := Rect2(24, 88, 344, 154)
const PANEL_RECT_200 := Rect2(24, 76, 344, 166)
const SLOT_MIN: int = 1
const SLOT_MAX: int = 3
const CARD_FONT_CAP: int = 12

enum CardState { EMPTY, VALID, CORRUPTED }

var _panel: AshenPanel
var _heading: Label
var _scroll: ScrollContainer
var _box: VBoxContainer
var _alert_box: HBoxContainer
var _alert_label: Label
var _cards: Array[_SlotCard] = []
var _built: bool = false

var _alert_slot: int = 0
var _alert_reason: String = ""
var _alert_empty: bool = false


func _init() -> void:
	name = "SaveSlots"
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
	clear_alert()
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


func refresh() -> void:
	if not _built:
		return
	_heading.text = tr("ui.saves.heading")
	var font: int = _card_font_size()
	for slot: int in range(SLOT_MIN, SLOT_MAX + 1):
		var card: _SlotCard = _cards[slot - 1]
		card.font_size = font
		card.meta_font_size = mini(font, CARD_FONT_CAP)
		var meta: Dictionary = SaveManager.get_slot_metadata(slot)
		card.slot = slot
		card.state = _card_state(meta)
		card.title_text = _card_title(slot, meta)
		card.meta_text = _card_meta(meta)
		card.detail_text = _card_detail(meta)
		card.tooltip_text = _card_tooltip(slot, meta)
		card.apply_layout()
		card.set_meta(&"a11y_name", _slot_a11y_name(slot, meta))
		card.set_meta(&"a11y_state", _state_label(card.state))
	_render_alert()


func apply_ui_scale() -> void:
	_apply_scale_layout()
	refresh()


func _apply_scale_layout() -> void:
	if _panel == null:
		return
	var large: bool = Config.ui_scale >= Config.UI_SCALE_200
	_panel.position = PANEL_RECT_200.position if large else PANEL_RECT.position
	_panel.size = PANEL_RECT_200.size if large else PANEL_RECT.size


func clear_alert() -> void:
	_alert_slot = 0
	_alert_reason = ""
	_alert_empty = false
	_render_alert()


## Показывает ошибку загрузки конкретного слота (в т.ч. из MainMenu после
## неудачного `SaveManager.load_slot`) и предлагает другой (EC-07).
func show_error(slot: int, reason: String) -> void:
	_alert_slot = slot
	_alert_reason = reason
	_alert_empty = false
	_render_alert()
	_focus_other(slot)


func get_alert_text() -> String:
	return _alert_label.text if _alert_label != null else ""


func is_alert_visible() -> bool:
	return _alert_box != null and _alert_box.visible


func get_cards() -> Array[_SlotCard]:
	var copy: Array[_SlotCard] = []
	copy.assign(_cards)
	return copy


func get_focused_index() -> int:
	var owner: Control = _focus_owner()
	if owner == null:
		return -1
	return _cards.find(owner)


func get_card(index: int) -> _SlotCard:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index]


## Активирует слот так же, как Enter/A (для GUT и интеграции).
func activate_slot(slot: int) -> void:
	if slot < SLOT_MIN or slot > SLOT_MAX:
		return
	var meta: Dictionary = SaveManager.get_slot_metadata(slot)
	var state: CardState = _card_state(meta)
	if state == CardState.VALID:
		slot_selected.emit(slot)
		return
	if state == CardState.EMPTY:
		_alert_slot = slot
		_alert_reason = ""
		_alert_empty = true
		_render_alert()
		_focus_other(slot)
		return
	show_error(slot, str(meta.get("reason", SaveManager.LOAD_CORRUPTED)))


func get_state(slot: int) -> CardState:
	if slot < SLOT_MIN or slot > SLOT_MAX:
		return CardState.EMPTY
	return _cards[slot - 1].state


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
	_panel.name = "SlotsPanel"
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
	_scroll.name = "SlotList"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)

	_box = VBoxContainer.new()
	_box.name = "Cards"
	_box.add_theme_constant_override("separation", UITokens.SP_2)
	_box.custom_minimum_size = Vector2(PANEL_RECT.size.x - 28.0, 0)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)

	for slot: int in range(SLOT_MIN, SLOT_MAX + 1):
		var card := _SlotCard.new()
		card.name = "Slot%d" % slot
		card.slot = slot
		card.focus_mode = Control.FOCUS_ALL
		card.set_meta(&"a11y_role", "button")
		card.pressed.connect(_on_card_pressed.bind(slot))
		card.focus_entered.connect(_on_card_focus_changed)
		card.mouse_entered.connect(_on_card_focus_changed)
		_box.add_child(card)
		_cards.append(card)

	_alert_box = HBoxContainer.new()
	_alert_box.name = "Alert"
	_alert_box.add_theme_constant_override("separation", UITokens.SP_1)
	_alert_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_alert_box)

	var badge := _AlertBadge.new()
	badge.name = "AlertBadge"
	_alert_box.add_child(badge)

	_alert_label = _make_label("", UITokens.BLOOD_5, UITokens.FONT_BODY)
	_alert_label.name = "AlertText"
	_alert_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alert_box.add_child(_alert_label)
	_alert_box.visible = false


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
# Данные слотов
# ------------------------------------------------------------------------------

func _card_state(meta: Dictionary) -> CardState:
	if not bool(meta.get("exists", false)):
		return CardState.EMPTY
	if bool(meta.get("valid", false)):
		return CardState.VALID
	return CardState.CORRUPTED


func _card_title(slot: int, meta: Dictionary) -> String:
	match _card_state(meta):
		CardState.EMPTY:
			return tr("ui.saves.empty")
		CardState.CORRUPTED:
			if bool(meta.get("corrupted", false)):
				return tr("ui.saves.file_corrupted")
			return tr("ui.saves.file_unsupported")
		_:
			var zone_name: String = _zone_name(meta)
			if zone_name.is_empty():
				return tr("ui.saves.save_number") % slot
			return zone_name


func _card_meta(meta: Dictionary) -> String:
	if _card_state(meta) != CardState.VALID:
		return ""
	var level: int = maxi(1, int(meta.get("level", 1)))
	var play_time: float = float(meta.get("play_time", 0.0))
	var parts: Array[String] = []
	parts.append(tr("ui.common.level") % level)
	parts.append(format_play_time(play_time, Config.is_english()))
	var saved_at: String = format_saved_at(int(meta.get("saved_at_unix", 0)))
	if not saved_at.is_empty():
		parts.append(saved_at)
	return " · ".join(parts)


func _card_detail(meta: Dictionary) -> String:
	if _card_state(meta) != CardState.CORRUPTED:
		return ""
	return reason_text(str(meta.get("reason", SaveManager.LOAD_CORRUPTED)), Config.is_english())


func _card_tooltip(slot: int, meta: Dictionary) -> String:
	match _card_state(meta):
		CardState.EMPTY:
			return tr("ui.saves.slot_empty") % slot
		CardState.CORRUPTED:
			return "%s: %s" % [
				tr("ui.saves.slot_corrupted") % slot,
				_card_detail(meta),
			]
		_:
			return tr("ui.saves.load_slot") % slot


func _slot_a11y_name(slot: int, meta: Dictionary) -> String:
	var state: CardState = _card_state(meta)
	if state == CardState.VALID:
		return tr("ui.saves.a11y_valid") % [slot, _card_title(slot, meta)]
	if state == CardState.EMPTY:
		return tr("ui.saves.a11y_empty") % slot
	return tr("ui.saves.a11y_corrupted") % slot


func _state_label(state: CardState) -> String:
	match state:
		CardState.VALID:
			return "valid"
		CardState.EMPTY:
			return "empty"
		_:
			return "corrupted"


func _zone_name(meta: Dictionary) -> String:
	var zone_id: String = str(meta.get("zone_id", "")).strip_edges()
	if not zone_id.is_empty():
		var path: String = "res://data/zones/%s.tres" % zone_id
		if ResourceLoader.exists(path):
			var data: ZoneData = load(path) as ZoneData
			if data != null:
				return data.get_display_name()
	var zone_name: String = str(meta.get("zone_name", "")).strip_edges()
	return zone_name


func _card_font_size() -> int:
	return UITokens.FONT_BODY * Config.ui_scale / 100


## «6ч 12м» / «6h 12m»; меньше часа — только минуты.
static func format_play_time(seconds: float, english: bool = false) -> String:
	var total: int = maxi(int(seconds), 0)
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	if hours > 0:
		return LocaleText.translate_for("en" if english else "ru", "ui.saves.hours_minutes", [hours, minutes])
	return LocaleText.translate_for("en" if english else "ru", "ui.saves.minutes", [minutes])


## Дата сохранения «14.10.2026»; 0 — пустая строка.
static func format_saved_at(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d.%02d.%04d" % [
		int(date.get("day", 1)),
		int(date.get("month", 1)),
		int(date.get("year", 1970)),
	]


## Причина EC-07 человеческим языком (для карточки и предупреждения).
static func reason_text(reason: String, english: bool = false) -> String:
	match reason:
		SaveManager.LOAD_CORRUPTED:
			return LocaleText.translate_for("en" if english else "ru", "ui.saves.reason_corrupted")
		SaveManager.LOAD_SCHEMA_TOO_NEW:
			return LocaleText.translate_for("en" if english else "ru", "ui.saves.reason_newer")
		SaveManager.LOAD_SCHEMA_UNSUPPORTED:
			return LocaleText.translate_for("en" if english else "ru", "ui.saves.reason_unsupported")
		SaveManager.LOAD_IO_ERROR:
			return LocaleText.translate_for("en" if english else "ru", "ui.saves.reason_io")
		SaveManager.LOAD_INVALID_SLOT:
			return LocaleText.translate_for("en" if english else "ru", "ui.saves.reason_invalid_slot")
		_:
			return LocaleText.translate_for("en" if english else "ru", "ui.saves.reason_corrupted_data")


static func elide(text: String, max_width: float, font_size: int) -> String:
	if max_width <= 0.0 or UIStyle.text_width(text, font_size) <= max_width:
		return text
	var suffix: String = ".."
	var result: String = text
	while not result.is_empty():
		result = result.substr(0, result.length() - 1)
		if UIStyle.text_width(result + suffix, font_size) <= max_width:
			return result + suffix
	return suffix


# ------------------------------------------------------------------------------
# Фокус / ввод
# ------------------------------------------------------------------------------

func _on_card_pressed(slot: int) -> void:
	activate_slot(slot)


func _on_card_focus_changed() -> void:
	pass


func _focus_initial() -> void:
	if not visible or _cards.is_empty():
		return
	for index: int in _cards.size():
		if _cards[index].state == CardState.VALID:
			_cards[index].grab_focus()
			return
	_cards[0].grab_focus()


func _focus_other(slot: int) -> void:
	if _cards.is_empty():
		return
	# Сначала другой валидный слот, затем просто следующий: игрок должен
	# остаться в списке и увидеть причину, а не потерять фокус (EC-07).
	for offset: int in range(1, _cards.size() + 1):
		var candidate: int = wrapi(slot - 1 + offset, 0, _cards.size())
		if _cards[candidate].state == CardState.VALID:
			_cards[candidate].grab_focus()
			return
	for offset: int in range(1, _cards.size() + 1):
		var candidate: int = wrapi(slot - 1 + offset, 0, _cards.size())
		if _cards[candidate].state != CardState.VALID:
			_cards[candidate].grab_focus()
			return


func _move_focus(step: int) -> void:
	if _cards.is_empty():
		return
	var current: int = get_focused_index()
	var next: int = 0 if current < 0 else wrapi(current + step, 0, _cards.size())
	if current < 0 and step < 0:
		next = _cards.size() - 1
	_cards[next].grab_focus()


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


func _focus_owner() -> Control:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	return viewport.gui_get_focus_owner()


func _release_focus() -> void:
	var owner: Control = _focus_owner()
	if owner != null and is_ancestor_of(owner):
		owner.release_focus()


func _consume_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


# ------------------------------------------------------------------------------
# Предупреждение EC-07
# ------------------------------------------------------------------------------

func _render_alert() -> void:
	if _alert_label == null:
		return
	var text: String = ""
	if _alert_slot > 0:
		if _alert_empty:
			text = tr("ui.saves.alert_empty") % _alert_slot
		elif _is_corruption(_alert_reason):
			text = tr("ui.saves.alert_corrupted") % _alert_slot
		else:
			text = tr("ui.saves.alert_error") % _alert_slot
	_alert_label.text = text
	_alert_box.visible = not text.is_empty()


func _is_corruption(reason: String) -> bool:
	return reason == SaveManager.LOAD_CORRUPTED \
		or reason == SaveManager.LOAD_SCHEMA_TOO_NEW \
		or reason == SaveManager.LOAD_SCHEMA_UNSUPPORTED


func _on_language_changed(_code: String) -> void:
	refresh()


func _on_ui_scale_changed(_scale: int) -> void:
	apply_ui_scale()


# ------------------------------------------------------------------------------
# Карточка слота
# ------------------------------------------------------------------------------

class _SlotCard extends Button:
	var slot: int = 1
	var state: int = 0:
		set(value):
			state = value
			queue_redraw()
	var title_text: String = "":
		set(value):
			title_text = value
			queue_redraw()
	var meta_text: String = "":
		set(value):
			meta_text = value
			queue_redraw()
	var detail_text: String = "":
		set(value):
			detail_text = value
			queue_redraw()
	var font_size: int = UITokens.FONT_BODY:
		set(value):
			font_size = value
			apply_layout()
	var meta_font_size: int = UITokens.FONT_BODY:
		set(value):
			meta_font_size = value
			apply_layout()

	func _init() -> void:
		UIStyle.make_custom_button(self)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		mouse_entered.connect(_on_mouse_entered)
		apply_layout()

	func apply_layout() -> void:
		custom_minimum_size = Vector2(0, float(get_card_height()))
		queue_redraw()

	func get_card_height() -> int:
		var line1: int = maxi(font_size, UITokens.FONT_BODY)
		var line2: int = maxi(meta_font_size, UITokens.FONT_BODY)
		return line1 + line2 + UITokens.SP_4

	func is_corrupted() -> bool:
		return state == 2

	func is_empty() -> bool:
		return state == 0

	func is_focus_visible() -> bool:
		return has_focus() and focus_mode == Control.FOCUS_ALL

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		var focused: bool = is_focus_visible()
		var hovered: bool = is_hovered()
		var padding: int = UITokens.PANEL_PADDING
		var line1: int = maxi(font_size, UITokens.FONT_BODY)
		var line2: int = maxi(meta_font_size, UITokens.FONT_BODY)
		var top: int = (size.y - float(line1 + line2)) * 0.5
		var baseline1: float = top + UIStyle.baseline_y(line1)
		var baseline2: float = top + float(line1) + UIStyle.baseline_y(line2)

		draw_rect(rect, UITokens.VOID)
		if state == 0:
			UIStyle.draw_dashed_frame(self, rect, UITokens.BORDER_SLOT, UITokens.STONE_9)
		else:
			var border: Color = UITokens.BLOOD_3 if state == 2 else UITokens.STONE_9
			if focused or hovered:
				border = UITokens.GOLD
			UIStyle.draw_frame(self, rect, UITokens.BORDER_SLOT, border)

		if focused:
			UIStyle.draw_frame(
				self,
				rect.grow(-float(UITokens.BORDER_SLOT)),
				UITokens.BORDER_INNER,
				UITokens.GOLD_9
			)
			UIStyle.draw_focus_brackets(
				self,
				rect.grow(-3),
				UITokens.GOLD_3,
				UITokens.FOCUS_ARM,
				UITokens.BORDER_FOCUS
			)

		var number_color: Color = UITokens.GOLD_3
		if state == 0:
			number_color = UITokens.STONE_5
		elif state == 2:
			number_color = UITokens.BLOOD_5
		UIStyle.draw_text(
			self,
			Vector2(padding, baseline1),
			str(slot),
			number_color,
			16,
			16.0,
			HORIZONTAL_ALIGNMENT_LEFT,
			true
		)

		var text_x: float = float(padding + 18)
		var right_reserve: float = 16.0
		var text_width: float = size.x - text_x - right_reserve
		var title_color: Color = UITokens.BONE
		if state == 0:
			title_color = UITokens.STONE_5
		UIStyle.draw_text(
			self,
			Vector2(text_x, baseline1),
			AshenSaveSlots.elide(title_text, text_width, line1),
			title_color,
			line1,
			text_width
		)

		if state == 2 and not detail_text.is_empty():
			UIStyle.draw_text(
				self,
				Vector2(text_x, baseline2),
				AshenSaveSlots.elide(detail_text, text_width, line2),
				UITokens.STONE_5,
				line2,
				text_width
			)
			UIStyle.draw_bang(
				self,
				Rect2(
					Vector2(size.x - right_reserve + 1.0, (size.y - 10.0) * 0.5),
					Vector2(10, 10)
				),
				UITokens.BLOOD,
				UITokens.BONE
			)
		elif state == 1:
			UIStyle.draw_text(
				self,
				Vector2(text_x, baseline2),
				AshenSaveSlots.elide(meta_text, text_width, line2),
				UITokens.STONE_5,
				line2,
				text_width
			)

	func _on_mouse_entered() -> void:
		if is_inside_tree():
			grab_focus()


class _AlertBadge extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(10, 10)

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, UITokens.BLOOD)
		UIStyle.draw_frame(self, rect, 1, UITokens.BLOOD_3)
		UIStyle.draw_bang(self, rect.grow(-1), UITokens.BLOOD, UITokens.BONE)
