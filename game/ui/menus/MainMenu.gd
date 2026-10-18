class_name MainMenu
extends CanvasLayer
## MainMenu — главное меню (T-20): макет `docs/mockups/main-menu.html`,
## DESIGN §6.1/§8.1/§9, TASKS T-20.
##
## Состав:
##   * название «ПЕПЕЛЬНЫЙ БАСТИОН / ASHEN BASTION» (в EN — «ASHEN BASTION /
##     ПЕПЕЛЬНЫЙ БАСТИОН · working title»);
##   * фон: луна, замок на скале, силуэт героя, туман дизерингом Байера 4×4
##     (статичный — «Без мигания» не меняет картинку);
##   * пункты: Продолжить · Новая игра · Загрузить · Настройки · Выход;
##   * «Продолжить» отключено без валидных слотов, причина видна inline и в
##     строке-подсказке (DESIGN §6.1);
##   * нижняя строка: подсказки ввода (клавиатура/Xbox/PS через AshenPrompt),
##     переключатель RU/EN, версия;
##   * вложенные экраны: Settings.tscn (настройки/a11y) и SaveSlots.tscn
##     (3 слота, занят/пуст/повреждён, EC-07).
##
## Управление без мыши (DESIGN §9.2): ↑/↓ или D-pad/стик — пункты, Enter/A —
## выбор, ←/→ — язык на кнопках RU/EN, Esc/B — назад из вложенных экранов.
## Фокус виден на всех интерактивных элементах, включая отключённые
## (причина отключения должна читаться с клавиатуры/геймпада).
##
## Экран самодостаточен: его можно запустить как `res://ui/menus/MainMenu.tscn`.
## Если в дереве есть Main/WorldRoot — старт игры идёт через SceneRouter,
## иначе сцена меняется на `res://Main.tscn` (GameState переживает смену).
## В GUT `handle_game_start`/`handle_quit` выключаются, проверяются сигналы.

signal continue_requested(slot: int)
signal new_game_requested
signal load_requested(slot: int)
signal quit_requested
signal game_started(slot: int)

enum View { MAIN, LOAD, SETTINGS }

const SETTINGS_SCENE: PackedScene = preload("res://ui/menus/Settings.tscn")
const SLOTS_SCENE: PackedScene = preload("res://ui/menus/SaveSlots.tscn")

const GAME_VERSION: String = "0.1.0"
const SLOT_MIN: int = 1
const SLOT_MAX: int = 3

const TITLE_POS := Vector2(32, 16)
const SUBTITLE_POS := Vector2(32, 78)
const RULE_RECT := Rect2(32, 96, 200, 4)
const MENU_RECT := Rect2(24, 108, 240, 112)
const STATUS_RECT := Rect2(24, 224, 432, 12)
const FOOTER_RECT := Rect2(24, 248, 432, 12)
const MENU_WIDTH: int = 216

## Вложенные экраны.
@export var handle_game_start: bool = true
@export var handle_quit: bool = true
@export var start_visible: bool = true

var _root: Control
var _backdrop: Control
var _title_l1: Label
var _title_l2: Label
var _subtitle: Label
var _rule: Control
var _menu_scroll: ScrollContainer
var _menu_box: VBoxContainer
var _status_label: Label
var _footer: HBoxContainer
var _prompt_move: AshenPrompt
var _prompt_ok: AshenPrompt
var _prompt_back: AshenPrompt
var _lang_ru: _LangButton
var _lang_en: _LangButton
var _version_label: Label

var _menu_items: Array[AshenMenuItem] = []
var _menu_ids: Array[StringName] = []
var _focus_order: Array[Control] = []
var _continue_button: AshenMenuItem

var _settings_view: AshenSettingsView
var _slots_view: AshenSaveSlots
var _view: View = View.MAIN
var _return_focus_index: int = 0

var _scan: Dictionary = {
	"valid_slot": 0,
	"exists": false,
	"corrupted": false,
}


func _init() -> void:
	name = "MainMenu"
	layer = 20


func _ready() -> void:
	_ensure_built()
	_connect_signals()
	refresh_saves()
	apply_ui_scale()
	_apply_language()
	visible = start_visible
	_root.visible = start_visible
	if start_visible:
		call_deferred(&"_focus_initial")


func _exit_tree() -> void:
	if Config.has_signal(&"language_changed") and Config.language_changed.is_connected(_on_language_changed):
		Config.language_changed.disconnect(_on_language_changed)
	if Config.has_signal(&"ui_scale_changed") and Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.disconnect(_on_ui_scale_changed)
	if EventBus.save_completed.is_connected(_on_save_changed):
		EventBus.save_completed.disconnect(_on_save_changed)
	if EventBus.save_failed.is_connected(_on_save_failed):
		EventBus.save_failed.disconnect(_on_save_failed)
	if EventBus.slot_corrupted.is_connected(_on_slot_corrupted):
		EventBus.slot_corrupted.disconnect(_on_slot_corrupted)


# ------------------------------------------------------------------------------
# Публичный API (интеграция + GUT)
# ------------------------------------------------------------------------------

func open() -> void:
	_ensure_built()
	visible = true
	_root.visible = true
	show_view(View.MAIN)
	refresh_saves()
	apply_ui_scale()
	_apply_language()
	call_deferred(&"_focus_initial")


func close() -> void:
	visible = false
	if _root != null:
		_root.visible = false
	_release_focus()


func is_open() -> bool:
	return _root != null and _root.visible


func show_view(view: View, return_index: int = -1) -> void:
	_ensure_built()
	if view != View.MAIN and _view == View.MAIN:
		_return_focus_index = (
			return_index if return_index >= 0 else maxi(_current_focus_index(), 0)
		)
	_view = view
	_apply_view_visibility()
	if view == View.SETTINGS:
		_settings_view.open()
	elif view == View.LOAD:
		_slots_view.open()
	else:
		call_deferred(&"_restore_main_focus")


func _apply_view_visibility() -> void:
	var main: bool = _view == View.MAIN
	var large: bool = _is_large_scale()
	_menu_scroll.visible = main
	_status_label.visible = main
	_subtitle.visible = main
	# При 200% пункты выше и шире: линейка убирается, чтобы список помещался.
	_rule.visible = main and not large
	_settings_view.visible = _view == View.SETTINGS
	_slots_view.visible = _view == View.LOAD


func _is_large_scale() -> bool:
	return Config.ui_scale >= Config.UI_SCALE_200


func _apply_ui_scale_layout() -> void:
	var large: bool = _is_large_scale()
	# 200%: список начинается ниже подзаголовка и занимает 140 px; строка
	# состояния сдвигается к футеру. 100/150% — геометрия макета.
	_menu_scroll.position = Vector2(
		float(MENU_RECT.position.x),
		92.0 if large else MENU_RECT.position.y
	)
	_menu_scroll.size = Vector2(
		float(MENU_RECT.size.x),
		140.0 if large else MENU_RECT.size.y
	)
	_status_label.position = Vector2(
		float(STATUS_RECT.position.x),
		232.0 if large else STATUS_RECT.position.y
	)
	_apply_view_visibility()


func get_view() -> View:
	return _view


func refresh_saves() -> void:
	_scan = _scan_saves()
	var valid_slot: int = int(_scan.get("valid_slot", 0))
	_continue_button.disabled = valid_slot <= 0
	# Button.disabled сбрасывает focus_mode в NONE (Godot 4.4), а причина
	# отключения должна читаться с клавиатуры/геймпада (DESIGN §6.1/§9.2).
	_continue_button.focus_mode = Control.FOCUS_ALL
	_continue_button.disabled_reason = _continue_reason() if valid_slot <= 0 else ""
	_continue_button.text = _t("Продолжить", "Continue")
	_continue_button.custom_minimum_size = Vector2(
		MENU_WIDTH,
		float(_continue_button.get_row_height())
	)
	_update_item_meta(_continue_button, _t("Продолжить", "Continue"))
	if _continue_button.has_focus():
		_update_status()


## Номер последнего валидного слота (0 — нет). Продолжение грузит самый свежий.
func get_continue_slot() -> int:
	return int(_scan.get("valid_slot", 0))


func get_continue_button() -> AshenMenuItem:
	return _continue_button


func get_menu_items() -> Array[AshenMenuItem]:
	var copy: Array[AshenMenuItem] = []
	copy.assign(_menu_items)
	return copy


func get_language_buttons() -> Array[Control]:
	var copy: Array[Control] = [_lang_ru, _lang_en]
	return copy


func get_settings_view() -> AshenSettingsView:
	return _settings_view


func get_slots_view() -> AshenSaveSlots:
	return _slots_view


func get_title_text() -> String:
	return "%s %s" % [_title_l1.text, _title_l2.text]


func get_subtitle_text() -> String:
	return _subtitle.text


func get_status_text() -> String:
	return _status_label.text


func get_version_text() -> String:
	return _version_label.text


func get_focused_index() -> int:
	return _current_focus_index()


func focus_item(index: int) -> void:
	if index < 0 or index >= _focus_order.size():
		return
	_focus_order[index].grab_focus()


## Тестовый/интеграционный вызов пункта по индексу (0 — Продолжить).
func activate_item(index: int) -> void:
	if index < 0 or index >= _menu_ids.size():
		return
	_on_menu_item_pressed(_menu_ids[index])


## Переключает язык и сохраняет его (нижняя кнопка RU/EN).
func set_language(code: String) -> void:
	Config.set_language(code)
	Config.save_settings()


func apply_ui_scale() -> void:
	var font_size: int = _menu_font_size()
	for item: AshenMenuItem in _menu_items:
		item.font_size = font_size
		item.custom_minimum_size = Vector2(MENU_WIDTH, float(item.get_row_height()))
	_apply_ui_scale_layout()
	if _settings_view != null:
		_settings_view.apply_ui_scale()
	if _slots_view != null:
		_slots_view.apply_ui_scale()


# ------------------------------------------------------------------------------
# Построение
# ------------------------------------------------------------------------------

func _ensure_built() -> void:
	if _root != null:
		return

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_backdrop = _MenuBackdrop.new()
	_backdrop.name = "Backdrop"
	_root.add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_title()
	_build_menu()
	_build_status()
	_build_views()
	_build_footer()


func _build_title() -> void:
	_title_l1 = _make_label("ПЕПЕЛЬНЫЙ", UITokens.BONE, UITokens.FONT_H1)
	_title_l1.name = "TitleLine1"
	_place(_title_l1, TITLE_POS, Vector2(416, UITokens.FONT_H1))
	_title_l1.add_theme_color_override("font_shadow_color", UITokens.VOID)
	_title_l1.add_theme_constant_override("shadow_offset_x", 2)
	_title_l1.add_theme_constant_override("shadow_offset_y", 2)

	_title_l2 = _make_label("БАСТИОН", UITokens.GOLD_3, UITokens.FONT_TITLE)
	_title_l2.name = "TitleLine2"
	_place(_title_l2, Vector2(TITLE_POS.x, 42), Vector2(416, UITokens.FONT_TITLE))
	_title_l2.add_theme_color_override("font_shadow_color", UITokens.BROWN_9)
	_title_l2.add_theme_constant_override("shadow_offset_x", 2)
	_title_l2.add_theme_constant_override("shadow_offset_y", 2)

	_subtitle = _make_label(
		"ASHEN BASTION · рабочее название",
		UITokens.STONE_5,
		UITokens.FONT_BODY
	)
	_subtitle.name = "Subtitle"
	_place(_subtitle, SUBTITLE_POS, Vector2(416, UITokens.LINE_BODY))

	_rule = _Rule.new()
	_rule.name = "Rule"
	_root.add_child(_rule)
	_rule.position = RULE_RECT.position
	_rule.size = RULE_RECT.size


func _build_menu() -> void:
	_menu_scroll = ScrollContainer.new()
	_menu_scroll.name = "MenuScroll"
	_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Полоса прокрутки не нужна: при 100/150% список помещается целиком,
	# при 200% follow_focus прокручивает к выбранному пункту (DESIGN §9.2).
	_menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_menu_scroll.follow_focus = true
	_menu_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_menu_scroll)
	_menu_scroll.position = MENU_RECT.position
	_menu_scroll.size = MENU_RECT.size

	_menu_box = VBoxContainer.new()
	_menu_box.name = "Menu"
	_menu_box.add_theme_constant_override("separation", 0)
	_menu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_scroll.add_child(_menu_box)

	_add_menu_item(&"continue", "Продолжить")
	_add_menu_item(&"new", "Новая игра")
	_add_menu_item(&"load", "Загрузить")
	_add_menu_item(&"settings", "Настройки")
	_add_menu_item(&"exit", "Выход")


func _add_menu_item(id: StringName, text: String) -> AshenMenuItem:
	var item := AshenMenuItem.new()
	item.name = String(id).capitalize().replace(" ", "")
	item.text = text
	item.font_size = UITokens.FONT_BODY
	item.focus_mode = Control.FOCUS_ALL
	item.set_meta(&"menu_id", id)
	item.set_meta(&"a11y_role", "menuitem")
	item.set_meta(&"a11y_name", text)
	item.pressed.connect(_on_menu_item_pressed.bind(id))
	item.focus_entered.connect(_on_focus_changed)
	item.mouse_entered.connect(_on_focus_changed)
	_menu_box.add_child(item)
	item.custom_minimum_size = Vector2(MENU_WIDTH, float(item.get_row_height()))
	_menu_items.append(item)
	_menu_ids.append(id)
	_focus_order.append(item)
	if id == &"continue":
		_continue_button = item
	return item


func _build_status() -> void:
	_status_label = _make_label("", UITokens.STONE_5, UITokens.FONT_BODY)
	_status_label.name = "Status"
	_place(_status_label, STATUS_RECT.position, STATUS_RECT.size)


func _build_views() -> void:
	_settings_view = SETTINGS_SCENE.instantiate() as AshenSettingsView
	_settings_view.name = "Settings"
	_root.add_child(_settings_view)
	_settings_view.visible = false
	_settings_view.closed.connect(_on_subview_closed)
	_settings_view.remap_requested.connect(_on_remap_requested)
	_settings_view.settings_changed.connect(_on_settings_changed)

	_slots_view = SLOTS_SCENE.instantiate() as AshenSaveSlots
	_slots_view.name = "SaveSlots"
	_root.add_child(_slots_view)
	_slots_view.visible = false
	_slots_view.closed.connect(_on_subview_closed)
	_slots_view.slot_selected.connect(_on_slot_selected)


func _build_footer() -> void:
	_footer = HBoxContainer.new()
	_footer.name = "Footer"
	_footer.add_theme_constant_override("separation", UITokens.SP_3)
	_footer.alignment = BoxContainer.ALIGNMENT_BEGIN
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_footer)
	_footer.position = FOOTER_RECT.position
	_footer.size = FOOTER_RECT.size

	_prompt_move = AshenPrompt.new()
	_prompt_move.name = "PromptMove"
	_prompt_move.setup(&"ui_up", "Выбор")
	_footer.add_child(_prompt_move)

	_prompt_ok = AshenPrompt.new()
	_prompt_ok.name = "PromptOk"
	_prompt_ok.setup(&"ui_accept", "Ок")
	_footer.add_child(_prompt_ok)

	_prompt_back = AshenPrompt.new()
	_prompt_back.name = "PromptBack"
	_prompt_back.setup(&"ui_cancel", "Назад")
	_footer.add_child(_prompt_back)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_child(spacer)

	_lang_ru = _make_lang_button("ru")
	_lang_en = _make_lang_button("en")
	_footer.add_child(_lang_ru)
	_footer.add_child(_lang_en)
	_focus_order.append(_lang_ru)
	_focus_order.append(_lang_en)

	_version_label = _make_label("v" + GAME_VERSION, UITokens.STONE_5, UITokens.FONT_BODY)
	_version_label.name = "Version"
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version_label.custom_minimum_size = Vector2(44, UITokens.LINE_BODY)
	_footer.add_child(_version_label)


func _make_lang_button(code: String) -> _LangButton:
	var button := _LangButton.new()
	button.name = "Lang" + code.to_upper()
	button.lang_code = code
	button.tooltip_text = "RU" if code == "ru" else "EN"
	button.set_meta(&"a11y_role", "switch")
	button.set_meta(&"a11y_name", "Русский" if code == "ru" else "English")
	button.pressed.connect(_on_lang_pressed.bind(code))
	button.focus_entered.connect(_on_focus_changed)
	button.mouse_entered.connect(_on_focus_changed)
	return button


func _make_label(
	text: String,
	color: Color,
	size: int,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIStyle.font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _place(control: Control, position: Vector2, control_size: Vector2) -> void:
	_root.add_child(control)
	control.position = position
	control.size = control_size


# ------------------------------------------------------------------------------
# Язык и масштаб
# ------------------------------------------------------------------------------

func _menu_font_size() -> int:
	return UITokens.FONT_BODY * Config.ui_scale / 100


func _t(ru: String, en: String) -> String:
	return en if Config.is_english() else ru


func _apply_language() -> void:
	var english: bool = Config.is_english()
	_title_l1.text = "ASHEN" if english else "ПЕПЕЛЬНЫЙ"
	_title_l2.text = "BASTION" if english else "БАСТИОН"
	_subtitle.text = (
		"ПЕПЕЛЬНЫЙ БАСТИОН · working title"
		if english
		else "ASHEN BASTION · рабочее название"
	)

	for index: int in _menu_items.size():
		var item: AshenMenuItem = _menu_items[index]
		var id: StringName = _menu_ids[index]
		item.text = _menu_text(id)
		_update_item_meta(item, item.text)

	_LangButton.set_active(_lang_ru, not english)
	_LangButton.set_active(_lang_en, english)

	_prompt_move.setup(&"ui_up", _t("Выбор", "Select"))
	_prompt_ok.setup(&"ui_accept", _t("Ок", "OK"))
	_prompt_back.setup(&"ui_cancel", _t("Назад", "Back"))

	refresh_saves()
	_update_status()
	if _settings_view != null:
		_settings_view.refresh()
	if _slots_view != null:
		_slots_view.refresh()


func _menu_text(id: StringName) -> String:
	match id:
		&"continue":
			return _t("Продолжить", "Continue")
		&"new":
			return _t("Новая игра", "New game")
		&"load":
			return _t("Загрузить", "Load")
		&"settings":
			return _t("Настройки", "Settings")
		&"exit":
			return _t("Выход", "Exit")
	return ""


func _hint_for(id: StringName) -> String:
	match id:
		&"continue":
			return _t("Загрузить последнее сохранение", "Load the latest save")
		&"new":
			return _t("Начать новое путешествие", "Start a new journey")
		&"load":
			return _t("Выбрать сохранение", "Choose a save")
		&"settings":
			return _t("Язык, масштаб, доступность", "Language, scale, accessibility")
		&"exit":
			return _t("Выйти из игры", "Quit the game")
	return ""


func _update_item_meta(item: AshenMenuItem, accessible_name: String) -> void:
	item.set_meta(&"a11y_name", accessible_name)
	item.set_meta(&"a11y_disabled_reason", item.disabled_reason)


func _on_lang_pressed(code: String) -> void:
	set_language(code)


func _on_focus_changed() -> void:
	_update_status()


func _update_status() -> void:
	if _status_label == null:
		return
	var owner: Control = _current_focus_owner()
	var text: String = ""
	var is_reason: bool = false
	if owner != null:
		if owner == _lang_ru or owner == _lang_en:
			text = _t("Язык интерфейса", "Interface language")
		else:
			for index: int in _menu_items.size():
				var item: AshenMenuItem = _menu_items[index]
				if owner != item:
					continue
				if item.disabled and not item.disabled_reason.is_empty():
					text = item.disabled_reason
					is_reason = true
				else:
					text = _hint_for(_menu_ids[index])
				break
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color",
		UITokens.BONE if is_reason else UITokens.STONE_5
	)


# ------------------------------------------------------------------------------
# Ввод: только клавиатура/D-pad/стик (DESIGN §9.2)
# ------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _root == null or not _root.visible or _view != View.MAIN:
		return
	if event.is_action_pressed(&"ui_down", true):
		_move_focus(1)
		_consume_input()
	elif event.is_action_pressed(&"ui_up", true):
		_move_focus(-1)
		_consume_input()
	elif event.is_action_pressed(&"ui_left", true):
		if _is_language_focused():
			_set_language_by_direction(-1)
			_consume_input()
	elif event.is_action_pressed(&"ui_right", true):
		if _is_language_focused():
			_set_language_by_direction(1)
			_consume_input()
	elif event.is_action_pressed(&"ui_accept"):
		# Отключённый пункт не должен «молчать»: показываем причину (DESIGN §6.1).
		var owner: Control = _current_focus_owner()
		if owner is AshenMenuItem:
			var item := owner as AshenMenuItem
			if item.disabled and not item.disabled_reason.is_empty():
				_show_reason(item.disabled_reason)
				_consume_input()


func _move_focus(step: int) -> void:
	if _focus_order.is_empty():
		return
	var current: int = _current_focus_index()
	var next: int = 0 if current < 0 else wrapi(current + step, 0, _focus_order.size())
	if current < 0 and step < 0:
		next = _focus_order.size() - 1
	_focus_order[next].grab_focus()


func _is_language_focused() -> bool:
	var owner: Control = _current_focus_owner()
	return owner == _lang_ru or owner == _lang_en


func _set_language_by_direction(step: int) -> void:
	var target: _LangButton = _lang_en if step > 0 else _lang_ru
	target.grab_focus()
	set_language(target.lang_code)


func _show_reason(reason: String) -> void:
	_status_label.text = reason
	_status_label.add_theme_color_override("font_color", UITokens.BONE)


func _focus_initial() -> void:
	if not is_open() or _view != View.MAIN:
		return
	var index: int = 1 if _continue_button.disabled else 0
	focus_item(index)


func _restore_main_focus() -> void:
	if not is_open() or _view != View.MAIN:
		return
	focus_item(clampi(_return_focus_index, 0, _focus_order.size() - 1))


func _current_focus_owner() -> Control:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	return viewport.gui_get_focus_owner()


func _current_focus_index() -> int:
	var owner: Control = _current_focus_owner()
	if owner == null:
		return -1
	return _focus_order.find(owner)


func _consume_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _release_focus() -> void:
	var owner: Control = _current_focus_owner()
	if owner != null and _root != null and _root.is_ancestor_of(owner):
		owner.release_focus()


# ------------------------------------------------------------------------------
# Действия меню
# ------------------------------------------------------------------------------

func _on_menu_item_pressed(id: StringName) -> void:
	match id:
		&"continue":
			_on_continue_pressed()
		&"new":
			_emit_new_game()
		&"load":
			show_view(View.LOAD, _menu_ids.find(id))
		&"settings":
			show_view(View.SETTINGS, _menu_ids.find(id))
		&"exit":
			_emit_quit()


func _on_continue_pressed() -> void:
	var slot: int = get_continue_slot()
	if slot <= 0:
		_show_reason(_continue_reason())
		return
	continue_requested.emit(slot)
	if handle_game_start:
		_start_game(slot)


func _emit_new_game() -> void:
	new_game_requested.emit()
	if handle_game_start:
		_start_game(0)


func _emit_quit() -> void:
	quit_requested.emit()
	if handle_quit:
		get_tree().quit()


func _on_slot_selected(slot: int) -> void:
	load_requested.emit(slot)
	if handle_game_start:
		_start_game(slot)


func _on_subview_closed() -> void:
	show_view(View.MAIN)


func _on_remap_requested() -> void:
	# T-24: экран ремапа ещё не нарисован — пункт disabled с пояснением.
	pass


func _on_settings_changed(_key: String) -> void:
	# Значения уже применены Config; язык/масштаб приходят сигналами Config.
	pass


func _on_language_changed(_code: String) -> void:
	_apply_language()


func _on_ui_scale_changed(_scale: int) -> void:
	apply_ui_scale()


func _on_save_changed(_slot: int) -> void:
	refresh_saves()


func _on_save_failed(_slot: int, _reason: String) -> void:
	refresh_saves()


func _on_slot_corrupted(slot: int, reason: String) -> void:
	refresh_saves()
	if _view == View.LOAD and _slots_view != null:
		_slots_view.show_error(slot, reason)


# ------------------------------------------------------------------------------
# Сохранения: скан, причина «Продолжить», EC-07
# ------------------------------------------------------------------------------

func _scan_saves() -> Dictionary:
	var scan: Dictionary = {"valid_slot": 0, "exists": false, "invalid": false}
	var best_time: int = -1
	for slot: int in range(SLOT_MIN, SLOT_MAX + 1):
		var meta: Dictionary = SaveManager.get_slot_metadata(slot)
		var exists: bool = bool(meta.get("exists", false))
		var valid: bool = bool(meta.get("valid", false))
		if exists:
			scan["exists"] = true
		if exists and not valid:
			scan["invalid"] = true
		if not valid:
			continue
		var saved_at: int = int(meta.get("saved_at_unix", 0))
		if saved_at > best_time or (saved_at == best_time and slot > int(scan["valid_slot"])):
			best_time = saved_at
			scan["valid_slot"] = slot
	return scan


func _continue_reason() -> String:
	if bool(_scan.get("invalid", false)):
		return _t("Сохранения повреждены", "Saves are corrupted")
	return _t("Нет сохранений", "No saves")


func _has_world_root() -> bool:
	if not is_inside_tree():
		return false
	var scene: Node = get_tree().current_scene
	if scene != null and scene.get_node_or_null("WorldRoot") is Node2D:
		return true
	return get_node_or_null("/root/Main/WorldRoot") is Node2D


# ------------------------------------------------------------------------------
# Старт игры (новая/продолжить/загрузка)
# ------------------------------------------------------------------------------

func _start_game(slot: int) -> void:
	var zone: StringName = &""
	if slot > 0:
		if not SaveManager.load_slot(slot):
			var failure: String = str(SaveManager.read_slot(slot).get("reason", SaveManager.LOAD_CORRUPTED))
			show_view(View.LOAD)
			_slots_view.show_error(slot, failure)
			return
		var meta: Dictionary = SaveManager.get_slot_metadata(slot)
		zone = GameState.respawn_zone_id
		if zone == &"":
			zone = StringName(str(meta.get("zone_id", "")))
	else:
		_reset_for_new_game()

	if zone == &"":
		zone = GameState.current_zone_id
	if zone == &"":
		zone = SceneRouter.DEFAULT_ZONE_ID

	var in_place: bool = _has_world_root()
	if in_place:
		SceneRouter.reset()
	GameState.current_zone_id = zone

	game_started.emit(slot)
	if in_place:
		if not SceneRouter.bootstrap(zone):
			push_warning("MainMenu: не удалось загрузить зону '%s'" % zone)
		close()
		return

	var error: Error = get_tree().change_scene_to_file("res://Main.tscn")
	if error != OK:
		push_error("MainMenu: не удалось сменить сцену на Main.tscn (%s)" % error_string(error))
		return
	close()


func _reset_for_new_game() -> void:
	GameState.active_slot = 0
	GameState.current_zone_id = &""
	GameState.set_in_combat(false)
	GameState.currency = 0
	GameState.clear_inventory()
	GameState.clear_abilities()
	GameState.level = 1
	GameState.xp = 0
	GameState.set_learning_points(0)
	GameState.reset_progression()
	GameState.reset_factions()
	GameState.reset_boss_progress()
	GameState.reset_death_state(true)
	GameState.reset_hp()
	GameState.reset_stamina()
	if SceneRouter.has_method(&"reset"):
		SceneRouter.reset()


func _connect_signals() -> void:
	if not Config.language_changed.is_connected(_on_language_changed):
		Config.language_changed.connect(_on_language_changed)
	if not Config.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Config.ui_scale_changed.connect(_on_ui_scale_changed)
	if not EventBus.save_completed.is_connected(_on_save_changed):
		EventBus.save_completed.connect(_on_save_changed)
	if not EventBus.save_failed.is_connected(_on_save_failed):
		EventBus.save_failed.connect(_on_save_failed)
	if not EventBus.slot_corrupted.is_connected(_on_slot_corrupted):
		EventBus.slot_corrupted.connect(_on_slot_corrupted)


# ------------------------------------------------------------------------------
# Пиксельный фон (без внешнего арта): луна, замок, силуэт, туман дизерингом
# ------------------------------------------------------------------------------

class _MenuBackdrop extends Control:
	var _bayer: Array = [
		[0, 8, 2, 10],
		[12, 4, 14, 6],
		[3, 11, 1, 9],
		[15, 7, 13, 5],
	]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		_draw_sky()
		_draw_moon(Vector2(372, 48))
		_draw_castle()
		_draw_fog()
		_draw_foreground()
		_draw_scrim()

	func _draw_sky() -> void:
		draw_rect(Rect2(0, 0, size.x, size.y), UITokens.NIGHT_9)
		draw_rect(Rect2(0, 0, size.x, 82), UITokens.NIGHT)
		draw_rect(Rect2(0, 82, size.x, 34), UITokens.NIGHT_3)
		draw_rect(Rect2(0, 116, size.x, 36), UITokens.NIGHT_5)
		draw_rect(Rect2(0, 152, size.x, size.y - 152), UITokens.NIGHT_9)
		draw_rect(Rect2(0, 151, size.x, 1), UITokens.STEEL_9)

		var stars: Array[Vector2] = [
			Vector2(18, 20), Vector2(48, 44), Vector2(74, 16), Vector2(104, 58),
			Vector2(136, 28), Vector2(166, 48), Vector2(198, 14), Vector2(228, 36),
			Vector2(264, 60), Vector2(292, 22), Vector2(318, 42), Vector2(346, 12),
			Vector2(412, 26), Vector2(438, 54), Vector2(462, 18), Vector2(450, 74),
			Vector2(88, 74), Vector2(214, 70), Vector2(300, 78), Vector2(406, 8),
		]
		for index: int in stars.size():
			var star: Vector2 = stars[index]
			var color: Color = UITokens.STEEL_3 if index % 4 == 0 else UITokens.STONE_5
			var star_size: int = 2 if index % 5 == 0 else 1
			draw_rect(Rect2(star, Vector2(star_size, star_size)), color)

	func _draw_moon(center: Vector2) -> void:
		_draw_disc(center, 21, Color(UITokens.STEEL_3, 0.06))
		_draw_disc(center, 18, Color(UITokens.STEEL_3, 0.10))
		_draw_disc(center, 14, UITokens.BONE)
		_draw_disc(center + Vector2(4, -2), 2, UITokens.STONE_5)
		_draw_disc(center + Vector2(-5, 4), 2, UITokens.STONE_5)
		_draw_disc(center + Vector2(3, 6), 1, UITokens.STONE_5)
		# Холодный серп справа: луна не «тёплая» (DESIGN §8.7).
		draw_rect(Rect2(center.x + 11, center.y - 6, 3, 12), UITokens.STEEL_3)

	func _draw_disc(center: Vector2, radius: int, color: Color) -> void:
		for dy: int in range(-radius, radius + 1):
			var half: int = int(sqrt(float(radius * radius - dy * dy)))
			draw_rect(
				Rect2(center.x - float(half), center.y + float(dy), float(half * 2 + 1), 1.0),
				color
			)

	func _draw_castle() -> void:
		# Дальний утёс.
		draw_rect(Rect2(238, 196, 242, 74), UITokens.NIGHT)
		draw_rect(Rect2(268, 186, 212, 84), UITokens.NIGHT_3)
		draw_rect(Rect2(300, 176, 180, 94), UITokens.NIGHT_9)

		# Стены и башни (силуэт на фоне неба).
		draw_rect(Rect2(330, 150, 132, 56), UITokens.NIGHT_9)
		draw_rect(Rect2(330, 118, 22, 88), UITokens.NIGHT_9)
		draw_rect(Rect2(360, 100, 26, 106), UITokens.NIGHT_9)
		draw_rect(Rect2(420, 112, 24, 94), UITokens.NIGHT_9)
		draw_rect(Rect2(382, 78, 38, 128), UITokens.NIGHT_9)

		# Зубцы.
		for x: int in [330, 338, 360, 370, 420, 430, 382, 394, 406]:
			var y: int = 118
			if x >= 360 and x < 386:
				y = 100
			elif x >= 420:
				y = 112
			elif x >= 382:
				y = 78
			draw_rect(Rect2(x, y - 5, 5, 5), UITokens.NIGHT_9)

		# Шпиль центральной башни.
		draw_rect(Rect2(394, 60, 14, 6), UITokens.NIGHT_9)
		draw_rect(Rect2(398, 52, 6, 8), UITokens.NIGHT_9)
		draw_rect(Rect2(400, 44, 2, 8), UITokens.STONE_9)

		# Окна: эмиссивный gold-3 (не затемняется), рама gold-9.
		for window: Rect2 in [
			Rect2(338, 132, 3, 5), Rect2(368, 116, 3, 5),
			Rect2(428, 128, 3, 5), Rect2(394, 96, 4, 6),
			Rect2(400, 132, 3, 5), Rect2(344, 170, 3, 5),
		]:
			draw_rect(window.grow(1), UITokens.GOLD_9)
			draw_rect(window, UITokens.GOLD_3)

		# Ворота.
		draw_rect(Rect2(386, 184, 16, 22), UITokens.VOID)
		draw_rect(Rect2(388, 182, 12, 3), UITokens.STONE_9)

		# Передний утёс.
		draw_rect(Rect2(300, 208, 180, 62), UITokens.BROWN_9)
		draw_rect(Rect2(322, 202, 158, 68), UITokens.NIGHT_9)
		draw_rect(Rect2(352, 214, 128, 56), UITokens.BROWN_9)
		for rock: Rect2 in [
			Rect2(328, 198, 12, 4), Rect2(430, 196, 14, 4),
			Rect2(360, 214, 18, 3), Rect2(454, 220, 10, 3),
		]:
			draw_rect(rock, UITokens.STONE_9)

	func _draw_fog() -> void:
		# Дизеринг Байера 4×4: ступенчатый туман, без плавного градиента.
		var top: int = 168
		var bottom: int = 252
		var step: int = 2
		for y: int in range(top, bottom, step):
			var depth: float = float(y - top) / float(bottom - top)
			var threshold: int = int(round(2.0 + depth * 9.0))
			for x: int in range(0, int(size.x), step):
				var cell: int = int(_bayer[(y / step) % 4][(x / step) % 4])
				if cell >= threshold:
					continue
				var alpha: float = 0.10 + depth * 0.10
				draw_rect(
					Rect2(x, y, step, step),
					Color(UITokens.STEEL_9, alpha)
				)

	func _draw_foreground() -> void:
		# Левый утёс.
		draw_rect(Rect2(0, 214, 176, 56), UITokens.BROWN_9)
		draw_rect(Rect2(0, 220, 152, 50), UITokens.NIGHT_9)
		draw_rect(Rect2(0, 226, 132, 44), UITokens.BROWN_9)
		draw_rect(Rect2(34, 232, 96, 38), UITokens.NIGHT_9)
		draw_rect(Rect2(0, 214, 176, 2), UITokens.STONE_9)

		# Силуэт героя на утёсе (10×22): читается за счёт контрового света.
		var base := Vector2(146, 192)
		draw_rect(Rect2(base + Vector2(2, 0), Vector2(5, 4)), UITokens.VOID)
		draw_rect(Rect2(base + Vector2(1, 4), Vector2(7, 9)), UITokens.VOID)
		draw_rect(Rect2(base + Vector2(0, 7), Vector2(9, 8)), UITokens.VOID)
		draw_rect(Rect2(base + Vector2(2, 13), Vector2(2, 7)), UITokens.VOID)
		draw_rect(Rect2(base + Vector2(5, 13), Vector2(2, 7)), UITokens.VOID)
		draw_rect(Rect2(base + Vector2(8, 4), Vector2(1, 10)), UITokens.STEEL_9)
		draw_rect(Rect2(base + Vector2(7, 1), Vector2(1, 3)), UITokens.STEEL_9)
		draw_rect(Rect2(base + Vector2(1, 21), Vector2(7, 1)), UITokens.STEEL_9)

		# Нижняя ступенчатая тень под футер.
		var alphas: Array[float] = [0.55, 0.42, 0.30, 0.18]
		for index: int in alphas.size():
			draw_rect(
				Rect2(0, size.y - float((alphas.size() - index) * 5), size.x, 5),
				Color(UITokens.VOID, alphas[index])
			)

	func _draw_scrim() -> void:
		var alphas: Array[float] = [0.58, 0.50, 0.42, 0.34, 0.26, 0.18, 0.10]
		for index: int in alphas.size():
			draw_rect(
				Rect2(index * 32, 0, 32, size.y),
				Color(UITokens.VOID, alphas[index])
			)


class _Rule extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		draw_rect(Rect2(0, 1, size.x, 1), UITokens.GOLD_9)
		draw_rect(Rect2(0, size.y - 2, size.x, 1), UITokens.GOLD_9)
		draw_rect(Rect2(98, 0, 2, 5), UITokens.GOLD)
		draw_rect(Rect2(97, 1, 4, 1), UITokens.GOLD)
		draw_rect(Rect2(96, 2, 1, 1), UITokens.GOLD_3)
		draw_rect(Rect2(101, 2, 1, 1), UITokens.GOLD_3)


class _LangButton extends Button:
	var lang_code: String = "ru"
	var active: bool = false:
		set(value):
			active = value
			queue_redraw()
	var font_size: int = UITokens.FONT_BODY:
		set(value):
			font_size = value
			queue_redraw()

	func _init() -> void:
		UIStyle.make_custom_button(self)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(22, UITokens.KBD_HEIGHT)
		mouse_entered.connect(_on_mouse_entered)

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		var focused: bool = has_focus() and focus_mode == Control.FOCUS_ALL
		draw_rect(rect, UITokens.GOLD if active else UITokens.VOID)
		UIStyle.draw_frame(
			self,
			rect,
			UITokens.BORDER_INNER,
			UITokens.GOLD if active else UITokens.STONE_3
		)
		if focused:
			UIStyle.draw_frame(self, rect.grow(-1), UITokens.BORDER_INNER, UITokens.GOLD_3)
			UIStyle.draw_focus_brackets(
				self,
				rect.grow(-2),
				UITokens.GOLD_3,
				UITokens.FOCUS_ARM,
				UITokens.BORDER_INNER
			)
		var baseline: float = (
			(rect.size.y - UIStyle.text_height(font_size)) * 0.5
			+ UIStyle.baseline_y(font_size)
		)
		UIStyle.draw_text(
			self,
			Vector2(0, baseline),
			lang_code.to_upper(),
			UITokens.VOID if active else UITokens.STONE_5,
			font_size,
			rect.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	static func set_active(button: _LangButton, value: bool) -> void:
		button.active = value

	func _on_mouse_entered() -> void:
		if is_inside_tree():
			grab_focus()
