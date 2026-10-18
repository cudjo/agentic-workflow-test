class_name DeathScreen
extends CanvasLayer
## DeathScreen — экран смерти (T-22, DESIGN §6.5/§8.3, SPEC AC-05.2/05.3, EC-05).
##
## Появляется по `EventBus.death_screen_requested(info)` после бюджета `t_death`
## (T-26). `info` — снимок `GameState.get_corpse_info()` нового corpse-маркера
## плюс `previous_lost`/`previous` (старая метка) и `death_position`/`zone_id`.
##
## Два состояния (не только цветом):
##   * первая смерть — «ОСТАЛОСЬ НА МЕСТЕ ГИБЕЛИ»: валюта, число предметов,
##     превью первых 5, на карте мешок «Твои вещи» и костёр;
##   * повторная смерть до подбора — «УТРАЧЕНО НАВСЕГДА»: описание потерянной
##     метки, на карте череп, подпись «Вернуть уже нельзя» (EC-05).
##
## Появление — ступенчатый fade из `UITokens.FADE_STEPS` шагов с задержками
## макета death.html (заголовок → панели → кнопки → предупреждение). Режим
## «Без мигания» (`Config.no_flash`) показывает всё сразу (DESIGN §9.3).
##
## Фокус по умолчанию — «Возродиться у костра»; экран проходится без мыши
## (стрелки/D-pad переключают кнопки, Enter/A подтверждает). Кнопка возрождения
## вызывает `DeathHandler.respawn()` (T-26), поэтому экран выключает
## `auto_respawn` у найденного обработчика: смерть ждёт решения игрока.

const LAYER: int = 40
const DEATH_HANDLER_GROUP: StringName = &"death_handler"

const TITLE_TEXT: String = "ТЫ ПОГИБ"
const HEADING_FIRST: String = "ОСТАЛОСЬ НА МЕСТЕ ГИБЕЛИ"
const HEADING_LOST: String = "УТРАЧЕНО НАВСЕГДА"
const SUBTITLE_LOST: String = "Ты пал снова, не вернув своё"
const SUBTITLE_PLACE: String = "место гибели"
const SUBTITLE_UNKNOWN: String = "Место гибели"
const FOOTNOTE_FIRST: String = "Экипировка — тоже там."
const FOOTNOTE_LOST: String = "Вернуть уже нельзя."
const WARNING_FIRST: String = "Умрёшь до подбора — вещи пропадут навсегда."
const WARNING_LOST: String = "Прошлая потеря необратима."
const LEGEND_BAG: String = "Твои вещи"
const LEGEND_LOST: String = "Утрачено"
const LEGEND_BONFIRE: String = "Костёр"
const ACTION_RESPAWN: String = "Возродиться у костра"
const ACTION_MENU: String = "В главное меню"
const KEYS_HINT: String = "Ок"
const COINS_LABEL: String = "Монеты"
const ITEMS_LABEL: String = "Предметы"
const EMPTY_PREVIEW: String = "—"

## Геометрия макета death.html в кадре 480×270.
const TITLE_RECT := Rect2(0, 10, 480, 52)
const LEFT_RECT := Rect2(24, 70, 216, 142)
const RIGHT_RECT := Rect2(248, 70, 208, 142)
const ACTIONS_POSITION := Vector2(24, 220)
const ACTION_HEIGHT: int = 22
const KEYS_RECT := Rect2(344, 225, 112, 12)
const WARNING_RECT := Rect2(24, 248, 432, 12)
const PREVIEW_SLOT: int = 24
const PREVIEW_MAX: int = 5

## Задержки ступенчатого fade относительно появления экрана (death.html).
const FADE_DELAYS: Dictionary = {
	"title": 0.2,
	"panels": 0.9,
	"actions": 1.5,
	"warning": 2.0,
}

## Экран запросил главное меню (интеграция с T-20; сцена меню появится там).
signal main_menu_requested

var _root: Control
var _backdrop: Control
var _title_block: VBoxContainer
var _title_label: Label
var _subtitle_label: Label
var _left_panel: AshenPanel
var _heading_label: Label
var _currency_label: Label
var _items_label: Label
var _preview_box: HBoxContainer
var _more_label: Label
var _footnote_label: Label
var _right_panel: AshenPanel
var _minimap: AshenMinimap
var _legend_icon: _DeathIcon
var _legend_label: Label
var _actions: HBoxContainer
var _respawn_button: AshenMenuItem
var _menu_button: AshenMenuItem
var _warning: HBoxContainer
var _warning_label: Label

var _preview_slots: Array[AshenSlot] = []
var _map_model: WorldMapModel
var _map_snapshot: Dictionary = {}
var _view: Dictionary = {}
var _handler: DeathHandler

var _showing: bool = false
var _animating: bool = false
var _fade_time: float = 0.0
var _fade_alphas: Dictionary = {}
var _fade_targets: Dictionary = {}
var _built: bool = false


func _init() -> void:
	name = "DeathScreen"
	layer = LAYER


func _ready() -> void:
	_ensure_built()
	if not EventBus.death_screen_requested.is_connected(_on_death_screen_requested):
		EventBus.death_screen_requested.connect(_on_death_screen_requested)
	if not EventBus.player_respawned.is_connected(_on_player_respawned):
		EventBus.player_respawned.connect(_on_player_respawned)
	set_process(false)
	call_deferred(&"_adopt_death_handler")


func _exit_tree() -> void:
	if EventBus.death_screen_requested.is_connected(_on_death_screen_requested):
		EventBus.death_screen_requested.disconnect(_on_death_screen_requested)
	if EventBus.player_respawned.is_connected(_on_player_respawned):
		EventBus.player_respawned.disconnect(_on_player_respawned)


func _process(delta: float) -> void:
	advance_fade(delta)


# ------------------------------------------------------------------------------
# Публичный API
# ------------------------------------------------------------------------------

## Показывает экран для снимка смерти. Повторный вызов перезапускает появление.
func show_death(info: Dictionary) -> void:
	_ensure_built()
	var view: Dictionary = build_view(info)
	_view = view.duplicate(true)
	_apply_view(_view)

	# T-26: экран — единственный путь возрождения, авто-возрождение выключаем.
	var handler: DeathHandler = find_death_handler()
	if handler != null:
		handler.auto_respawn = false

	visible = true
	_showing = true
	_start_fade()
	call_deferred(&"_focus_default")


## Скрывает экран и снимает фокус; повторный вызов безопасен.
func hide_screen() -> void:
	_showing = false
	visible = false
	_animating = false
	set_process(false)
	var focus: Control = null
	var viewport: Viewport = get_viewport()
	if viewport != null:
		focus = viewport.gui_get_focus_owner()
	if focus != null and is_instance_valid(focus) and _root != null and _root.is_ancestor_of(focus):
		focus.release_focus()


func is_shown() -> bool:
	return _showing


func is_lost_death() -> bool:
	return bool(_view.get("lost", false))


## Последний применённый снимок (для тестов/QA).
func get_view_data() -> Dictionary:
	return _view.duplicate(true)


## Снимок `WorldMapModel.build()` с меткой гибели (для тестов/QA).
func get_map_snapshot() -> Dictionary:
	return _map_snapshot.duplicate(true)


## Возрождение у костра через T-26. Идемпотентно: `DeathHandler.respawn()`.
func respawn_now() -> void:
	var handler: DeathHandler = find_death_handler()
	if handler != null:
		handler.respawn()
	else:
		push_warning("DeathScreen: DeathHandler не найден — возрождение пропущено")
	hide_screen()


## Обработчик T-26, если он есть в дереве (группа `death_handler`).
func find_death_handler() -> DeathHandler:
	if _handler != null and is_instance_valid(_handler):
		return _handler
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group(DEATH_HANDLER_GROUP):
		if node is DeathHandler:
			_handler = node as DeathHandler
			return _handler
	# Обработчик мог быть добавлен без группы — ищем по типу.
	_handler = _find_handler_in(get_tree().root)
	return _handler


# ------------------------------------------------------------------------------
# Ступенчатый fade (DESIGN §6.5/§9.3)
# ------------------------------------------------------------------------------

## Продвигает появление детерминированно (тесты вызывают напрямую).
func advance_fade(delta: float) -> void:
	if not _animating:
		return
	_fade_time += maxf(delta, 0.0)
	for key: Variant in FADE_DELAYS.keys():
		var name := str(key)
		var progress: float = _fade_time - float(FADE_DELAYS[key])
		var alpha: float = _step_alpha(progress)
		_fade_alphas[name] = alpha
		var targets: Variant = _fade_targets.get(name, [])
		if targets is Array:
			for target: Variant in targets:
				(target as Control).modulate.a = alpha
	if _fade_time >= _fade_end_time():
		_animating = false
		set_process(false)


## Текущая прозрачность группы: "title", "panels", "actions", "warning".
func get_fade_alpha(group: String) -> float:
	return float(_fade_alphas.get(group, 0.0))


func is_fade_finished() -> bool:
	return not _animating


## Чистое представление снимка смерти. Первая смерть показывает новый corpse,
## повторная — потерянную метку (`previous`, EC-05).
static func build_view(info: Dictionary) -> Dictionary:
	var lost: bool = bool(info.get("previous_lost", false))
	var source: Dictionary = info
	if lost:
		var previous: Variant = info.get("previous", {})
		if previous is Dictionary and not (previous as Dictionary).is_empty():
			source = previous

	var items: Array[String] = _string_array(source.get("items", []))
	var preview: Array[String] = _string_array(source.get("preview", []))
	var count: int = int(source.get("items_count", items.size()))
	if count <= 0:
		count = items.size()
	# Превью — до 5 типов предметов (как в макете): дубликаты показываются
	# счётчиком на одном слоте, а не несколькими одинаковыми слотами.
	var unique_source: Array[String] = items if not items.is_empty() else preview
	var trimmed: Array[String] = []
	for item_id: String in unique_source:
		if trimmed.has(item_id):
			continue
		trimmed.append(item_id)
		if trimmed.size() >= PREVIEW_MAX:
			break

	var position := Vector2.ZERO
	var raw_position: Variant = source.get("position", null)
	if not (raw_position is Vector2):
		raw_position = info.get("death_position", Vector2.ZERO)
	if raw_position is Vector2:
		position = raw_position

	var zone_id: String = str(source.get("zone_id", ""))
	if zone_id.is_empty():
		zone_id = str(info.get("zone_id", ""))

	return {
		"lost": lost,
		"heading": HEADING_LOST if lost else HEADING_FIRST,
		"currency": int(source.get("currency", 0)),
		"items": items,
		"items_count": count,
		"preview": trimmed,
		"extra_count": maxi(count - trimmed.size(), 0),
		"footnote": FOOTNOTE_LOST if lost else FOOTNOTE_FIRST,
		"warning": WARNING_LOST if lost else WARNING_FIRST,
		"subtitle": SUBTITLE_LOST if lost else "",
		"zone_id": zone_id,
		"position": position,
	}


## Число с разрядным пробелом: 1240 → «1 240» (как в макете).
static func format_number(value: int) -> String:
	var negative: bool = value < 0
	var digits: String = str(absi(value))
	var grouped: String = ""
	while digits.length() > 3:
		grouped = " " + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	grouped = digits + grouped
	return ("-" if negative else "") + grouped


# ------------------------------------------------------------------------------
# Построение UI
# ------------------------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_backdrop = _Backdrop.new()
	_root.add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_title()
	_build_left_panel()
	_build_right_panel()
	_build_actions()
	_build_keys()
	_build_warning()

	_fade_targets = {
		"title": [_title_block],
		"panels": [_left_panel, _right_panel],
		"actions": [_actions],
		"warning": [_warning],
	}
	for key: Variant in FADE_DELAYS.keys():
		_fade_alphas[str(key)] = 0.0


func _build_title() -> void:
	_title_block = VBoxContainer.new()
	_title_block.name = "TitleBlock"
	_title_block.add_theme_constant_override("separation", UITokens.SP_3)
	_root.add_child(_title_block)
	_title_block.position = TITLE_RECT.position
	_title_block.size = TITLE_RECT.size

	_title_label = _make_label(
		TITLE_TEXT,
		UITokens.BLOOD_3,
		UITokens.FONT_TITLE,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_title_label.name = "Title"
	_title_label.custom_minimum_size = Vector2(0, UITokens.FONT_TITLE)
	_title_label.add_theme_color_override("font_shadow_color", UITokens.BLOOD_9)
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_block.add_child(_title_label)

	_subtitle_label = _make_label(
		"",
		UITokens.STONE_5,
		UITokens.FONT_BODY,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_subtitle_label.name = "Subtitle"
	_subtitle_label.custom_minimum_size = Vector2(0, UITokens.LINE_BODY)
	_title_block.add_child(_subtitle_label)


func _build_left_panel() -> void:
	_left_panel = _make_panel(LEFT_RECT, "LeftPanel")
	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", UITokens.SP_2)
	_left_panel.add_child(box)

	_heading_label = _make_label(HEADING_FIRST, UITokens.GOLD_3)
	_heading_label.name = "Heading"
	_heading_label.custom_minimum_size = Vector2(0, UITokens.LINE_BODY)
	box.add_child(_heading_label)

	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = UITokens.STONE_9
	rule.custom_minimum_size = Vector2(0, UITokens.BORDER_INNER)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)

	var coins: Dictionary = _make_loss_row(COINS_LABEL, _DeathIcon.Kind.COIN)
	box.add_child(coins["row"])
	_currency_label = coins["value"] as Label
	_currency_label.add_theme_color_override("font_color", UITokens.GOLD_3)

	var items: Dictionary = _make_loss_row(ITEMS_LABEL, _DeathIcon.Kind.BAG)
	box.add_child(items["row"])
	_items_label = items["value"] as Label

	_preview_box = HBoxContainer.new()
	_preview_box.name = "Preview"
	_preview_box.add_theme_constant_override("separation", UITokens.SP_2)
	_preview_box.custom_minimum_size = Vector2(0, PREVIEW_SLOT)
	box.add_child(_preview_box)

	_more_label = _make_label("", UITokens.STONE_5)
	_more_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_preview_box.add_child(_more_label)

	_footnote_label = _make_label(FOOTNOTE_FIRST, UITokens.STONE_5)
	_footnote_label.name = "Footnote"
	_footnote_label.custom_minimum_size = Vector2(0, UITokens.LINE_BODY)
	box.add_child(_footnote_label)


func _build_right_panel() -> void:
	_right_panel = _make_panel(RIGHT_RECT, "RightPanel")
	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", UITokens.SP_2)
	_right_panel.add_child(box)

	# Карта возвращения ×2: те же комнаты/ккостры, что в HUD (T-33), плюс
	# метка гибели, которую добавляет снимок экрана смерти.
	var map_wrap := Control.new()
	map_wrap.name = "MapWrap"
	map_wrap.custom_minimum_size = UITokens.MINIMAP_SIZE * 2.0
	map_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(map_wrap)

	_minimap = AshenMinimap.new()
	_minimap.name = "Minimap"
	_minimap.zoom = 2
	# Экран смерти показывает не мировую сетку 12x9, а одну зону крупно:
	# клетка 192x108 (зона целиком), маркеры ×2. Так место гибели и костёр
	# не сливаются в одной клетке мира (DESIGN §6.5: «карта возвращения»).
	var renderer: MapRenderer = _minimap.get_renderer()
	renderer.grid_size = Vector2i.ONE
	renderer.cell_size = UITokens.MINIMAP_SIZE * 2.0
	renderer.marker_scale = 2.0
	renderer.room_fill = UITokens.NIGHT_3
	map_wrap.add_child(_minimap)
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var legend := HBoxContainer.new()
	legend.name = "Legend"
	legend.add_theme_constant_override("separation", UITokens.SP_4)
	box.add_child(legend)

	var own := HBoxContainer.new()
	own.add_theme_constant_override("separation", UITokens.SP_1 + 1)
	legend.add_child(own)
	_legend_icon = _DeathIcon.new()
	_legend_icon.kind = _DeathIcon.Kind.BAG
	own.add_child(_legend_icon)
	_legend_label = _make_label(LEGEND_BAG, UITokens.STONE_5)
	_legend_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	own.add_child(_legend_label)

	var fire := HBoxContainer.new()
	fire.add_theme_constant_override("separation", UITokens.SP_1 + 1)
	legend.add_child(fire)
	var fire_icon := _DeathIcon.new()
	fire_icon.kind = _DeathIcon.Kind.BONFIRE
	fire.add_child(fire_icon)
	var fire_label := _make_label(LEGEND_BONFIRE, UITokens.STONE_5)
	fire_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fire.add_child(fire_label)


func _build_actions() -> void:
	_actions = HBoxContainer.new()
	_actions.name = "Actions"
	_actions.add_theme_constant_override("separation", UITokens.SP_3)
	_root.add_child(_actions)
	_actions.position = ACTIONS_POSITION

	_respawn_button = _make_action(ACTION_RESPAWN, "Respawn")
	_respawn_button.pressed.connect(_on_respawn_pressed)
	_menu_button = _make_action(ACTION_MENU, "MainMenu")
	_menu_button.pressed.connect(_on_menu_pressed)


func _build_keys() -> void:
	var keys := HBoxContainer.new()
	keys.name = "Keys"
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(keys)
	keys.anchor_left = 1.0
	keys.anchor_right = 1.0
	keys.offset_left = -float(480.0 - KEYS_RECT.position.x)
	keys.offset_right = -float(480.0 - (KEYS_RECT.position.x + KEYS_RECT.size.x))
	keys.offset_top = KEYS_RECT.position.y
	keys.offset_bottom = KEYS_RECT.position.y + KEYS_RECT.size.y

	var prompt := AshenPrompt.new()
	prompt.name = "ConfirmPrompt"
	prompt.setup(&"ui_accept", KEYS_HINT)
	keys.add_child(prompt)


func _build_warning() -> void:
	_warning = HBoxContainer.new()
	_warning.name = "Warning"
	_warning.add_theme_constant_override("separation", UITokens.SP_2)
	_root.add_child(_warning)
	_warning.position = WARNING_RECT.position
	_warning.size = WARNING_RECT.size

	var badge := _WarningBadge.new()
	badge.name = "WarningBadge"
	_warning.add_child(badge)

	_warning_label = _make_label(WARNING_FIRST, UITokens.BONE)
	_warning_label.name = "WarningText"
	_warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warning.add_child(_warning_label)


func _make_panel(rect: Rect2, node_name: String) -> AshenPanel:
	var panel := AshenPanel.new()
	panel.name = node_name
	# padding 0: 6 px внутреннего отступа рамки достаточно, а карта ×2 (192)
	# помещается в правую панель (196 px контента).
	panel.padding = 0
	panel.variant = UIStyle.PanelVariant.GLASS
	_root.add_child(panel)
	panel.position = rect.position
	panel.size = rect.size
	return panel


func _make_loss_row(title: String, icon_kind: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_2)
	row.custom_minimum_size = Vector2(0, UITokens.LINE_BODY)

	var icon := _DeathIcon.new()
	icon.kind = icon_kind
	row.add_child(icon)

	var label := _make_label(title, UITokens.BONE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var value := _make_label("0", UITokens.BONE)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(48, UITokens.LINE_BODY)
	row.add_child(value)
	return {"row": row, "value": value}


func _make_action(title: String, node_name: String) -> AshenMenuItem:
	var item := AshenMenuItem.new()
	item.name = node_name
	item.text = title
	item.font_size = UITokens.FONT_BODY
	var width: float = UIStyle.text_width(title, UITokens.FONT_BODY) + float(UITokens.SP_3 * 3)
	_actions.add_child(item)
	# `_ready()` компонента сбрасывает высоту на базовую строку — фиксируем
	# 22 px макета после добавления в дерево.
	item.custom_minimum_size = Vector2(width, float(ACTION_HEIGHT))
	return item


func _make_label(
	title: String,
	color: Color,
	size: int = UITokens.FONT_BODY,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = title
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


# ------------------------------------------------------------------------------
# Применение данных
# ------------------------------------------------------------------------------

func _apply_view(view: Dictionary) -> void:
	var lost: bool = bool(view.get("lost", false))

	_subtitle_label.text = _subtitle_for(view, lost)

	_heading_label.text = str(view.get("heading", HEADING_FIRST))
	_heading_label.add_theme_color_override(
		"font_color",
		UITokens.BLOOD_5 if lost else UITokens.GOLD_3
	)

	_currency_label.text = format_number(int(view.get("currency", 0)))
	_items_label.text = str(int(view.get("items_count", 0)))

	var items: Array[String] = _string_array(view.get("items", []))
	var preview: Array[String] = _string_array(view.get("preview", []))
	_rebuild_preview(items, preview)

	var extra: int = int(view.get("extra_count", 0))
	_more_label.text = "+%d" % extra if extra > 0 else ""
	_more_label.visible = extra > 0

	_footnote_label.text = str(view.get("footnote", FOOTNOTE_FIRST))
	_footnote_label.add_theme_color_override(
		"font_color",
		UITokens.BLOOD_5 if lost else UITokens.STONE_5
	)

	_warning_label.text = str(view.get("warning", WARNING_FIRST))
	_warning_label.add_theme_color_override(
		"font_color",
		UITokens.STONE_5 if lost else UITokens.BONE
	)

	_legend_label.text = LEGEND_LOST if lost else LEGEND_BAG
	_legend_icon.kind = _DeathIcon.Kind.SKULL if lost else _DeathIcon.Kind.BAG
	_legend_icon.queue_redraw()

	_map_snapshot = _build_map_snapshot(view)
	_minimap.set_data(_map_snapshot)


func _subtitle_for(view: Dictionary, lost: bool) -> String:
	if lost:
		return SUBTITLE_LOST
	var zone_id: String = str(view.get("zone_id", ""))
	var zone_name: String = _zone_display_name(zone_id)
	if zone_name.is_empty():
		return SUBTITLE_UNKNOWN
	return "%s · %s" % [zone_name, SUBTITLE_PLACE]


func _rebuild_preview(items: Array[String], preview: Array[String]) -> void:
	for child: Node in _preview_box.get_children():
		if child == _more_label:
			continue
		child.free()
	_preview_slots.clear()

	var counts: Dictionary = {}
	for item_id: String in items:
		counts[item_id] = int(counts.get(item_id, 0)) + 1

	if preview.is_empty():
		var empty := _make_label(EMPTY_PREVIEW, UITokens.STONE_5)
		empty.name = "EmptyPreview"
		_preview_box.add_child(empty)
		_preview_box.move_child(empty, 0)
		return

	for index: int in preview.size():
		var item_id: String = preview[index]
		var slot := AshenSlot.new()
		slot.name = "Preview%d" % (index + 1)
		slot.slot_size = PREVIEW_SLOT
		slot.state = AshenSlot.State.NORMAL
		slot.focus_mode = Control.FOCUS_NONE
		var copies: int = int(counts.get(item_id, 1))
		if copies > 1:
			slot.count = copies
		_preview_box.add_child(slot)
		# `_ready()` компонента пересобирает tooltip для состояния NORMAL,
		# поэтому id предмета ставим после добавления в дерево.
		slot.tooltip_text = item_id
		_preview_box.move_child(slot, index)
		_preview_slots.append(slot)


# ------------------------------------------------------------------------------
# Мини-карта возвращения (T-33 + T-22)
# ------------------------------------------------------------------------------

## Снимок локальной карты зоны: одна комната (world_rect зоны) крупно, костры
## из `ZoneData.map_bonfires` и метка гибели. Игрок мёртв — маркер не рисуется.
## Формат совместим с `MapRenderer` T-33, но без гейтов/связей: на экране
## смерти важны только костёр и место гибели (DESIGN §6.5).
func _build_map_snapshot(view: Dictionary) -> Dictionary:
	var zone_id := StringName(str(view.get("zone_id", "")))
	if zone_id == &"":
		zone_id = GameState.current_zone_id
	if zone_id == &"":
		return {}

	var data: ZoneData = _map_model_instance().get_zone(zone_id)
	if data == null:
		return {}
	var room: ZoneRoom = WorldMapModel.first_room(data)
	if room == null:
		return {}

	var world_rect: Rect2 = room.world_rect
	var position: Vector2 = view.get("position", Vector2.ZERO)
	var bonfires: Array[Dictionary] = []
	for bonfire_position: Vector2 in data.map_bonfires:
		bonfires.append({
			"zone_id": zone_id,
			"cell": Vector2i.ZERO,
			"local": _local_in_rect(bonfire_position, world_rect),
		})

	return {
		"rooms": [{
			"zone_id": zone_id,
			"zone_name": data.display_name,
			"room_id": room.id,
			"cell": Vector2i.ZERO,
			"world_rect": world_rect,
			"current": true,
			"index": 1,
		}],
		"links": [],
		"gates": [],
		"bonfires": bonfires,
		"player": {
			"zone_id": zone_id,
			"cell": Vector2i.ZERO,
			"local": _local_in_rect(position, world_rect),
			"valid": false,
		},
		"player_room": Vector2i.ZERO,
		"current_zone_id": zone_id,
		"visited_zone_ids": [zone_id],
		"grid_size": Vector2i.ONE,
		"corpse": {
			"zone_id": zone_id,
			"cell": Vector2i.ZERO,
			"local": _local_in_rect(position, world_rect),
			"lost": bool(view.get("lost", false)),
		},
	}


func _map_model_instance() -> WorldMapModel:
	if _map_model == null:
		_map_model = WorldMapModel.new()
		_map_model.reload()
	return _map_model


func _zone_display_name(zone_id: String) -> String:
	if zone_id.is_empty():
		return ""
	var data: ZoneData = _map_model_instance().get_zone(StringName(zone_id))
	if data == null:
		return ""
	return data.display_name


func _local_in_rect(position: Vector2, rect: Rect2) -> Vector2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var local := Vector2(
		(position.x - rect.position.x) / rect.size.x,
		(position.y - rect.position.y) / rect.size.y
	)
	return Vector2(clampf(local.x, 0.0, 1.0), clampf(local.y, 0.0, 1.0))


# ------------------------------------------------------------------------------
# Fade helpers
# ------------------------------------------------------------------------------

func _start_fade() -> void:
	_fade_time = 0.0
	var no_flash: bool = Config.no_flash
	for key: Variant in FADE_DELAYS.keys():
		var name := str(key)
		var alpha: float = 1.0 if no_flash else 0.0
		_fade_alphas[name] = alpha
		var targets: Variant = _fade_targets.get(name, [])
		if targets is Array:
			for target: Variant in targets:
				(target as Control).modulate.a = alpha
	_animating = not no_flash
	set_process(_animating)


func _step_alpha(progress: float) -> float:
	if progress <= 0.0:
		return 0.0
	if progress >= UITokens.FADE_TIME:
		return 1.0
	var step: float = UITokens.FADE_TIME / float(UITokens.FADE_STEPS)
	var steps: int = int(floor(progress / step + 0.0001))
	return clampf(float(steps) / float(UITokens.FADE_STEPS), 0.0, 1.0)


func _fade_end_time() -> float:
	var latest: float = 0.0
	for key: Variant in FADE_DELAYS.keys():
		latest = maxf(latest, float(FADE_DELAYS[key]) + UITokens.FADE_TIME)
	return latest


func _adopt_death_handler() -> void:
	var handler: DeathHandler = find_death_handler()
	if handler != null:
		handler.auto_respawn = false


# ------------------------------------------------------------------------------
# Ввод и действия
# ------------------------------------------------------------------------------

## Стрелки/D-pad переключают две кнопки, не отдавая событие игровому миру.
func _input(event: InputEvent) -> void:
	if not _showing:
		return
	if event.is_action_pressed(&"ui_left", true):
		_move_action_focus(-1)
		_consume_input()
	elif event.is_action_pressed(&"ui_right", true):
		_move_action_focus(1)
		_consume_input()


func _move_action_focus(step: int) -> void:
	var index: int = 1 if _menu_button.has_focus() else 0
	index = wrapi(index + step, 0, 2)
	var target: AshenMenuItem = _respawn_button if index == 0 else _menu_button
	target.grab_focus()


func _consume_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _focus_default() -> void:
	if _showing and _respawn_button != null:
		_respawn_button.grab_focus()


func _on_respawn_pressed() -> void:
	respawn_now()


func _on_menu_pressed() -> void:
	hide_screen()
	main_menu_requested.emit()


# ------------------------------------------------------------------------------
# EventBus
# ------------------------------------------------------------------------------

func _on_death_screen_requested(info: Dictionary) -> void:
	show_death(info)


func _on_player_respawned(_zone_id: StringName, _position: Vector2) -> void:
	if _showing:
		hide_screen()


func _find_handler_in(node: Node) -> DeathHandler:
	for child: Node in node.get_children():
		if child is DeathHandler:
			return child as DeathHandler
		var found: DeathHandler = _find_handler_in(child)
		if found != null:
			return found
	return null


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			result.append(str(entry))
	return result


# ------------------------------------------------------------------------------
# Пиксельные элементы (без внешнего арта)
# ------------------------------------------------------------------------------

## Затемнение сцены и красная «кайма» макета death.html (DESIGN §6.5).
class _Backdrop extends Control:

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0196, 0.0235, 0.0314, 0.5))
		var rings: Array[Dictionary] = [
			{"inset": 0.0, "width": 4.0, "color": Color(UITokens.BLOOD_9, 0.8)},
			{"inset": 4.0, "width": 4.0, "color": Color(UITokens.BLOOD, 0.4)},
			{"inset": 8.0, "width": 4.0, "color": Color(UITokens.BLOOD, 0.2)},
			{"inset": 12.0, "width": 4.0, "color": Color(UITokens.BLOOD, 0.08)},
		]
		for ring: Dictionary in rings:
			var inset: float = float(ring["inset"])
			var rect := Rect2(
				Vector2(inset, inset),
				size - Vector2(inset * 2.0, inset * 2.0)
			)
			draw_rect(rect, ring["color"] as Color, false, float(ring["width"]))


## 12×12 пиктограммы: монета, мешок, череп, костёр. Форма (не только цвет)
## различает «Твои вещи» и «Утрачено навсегда».
class _DeathIcon extends Control:

	enum Kind { COIN, BAG, SKULL, BONFIRE }

	var kind: Kind = Kind.COIN

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(12, 12)

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		match kind:
			Kind.COIN:
				draw_rect(Rect2(2, 2, 8, 8), UITokens.GOLD_9)
				UIStyle.draw_frame(self, Rect2(2, 2, 8, 8), 1, UITokens.GOLD_3)
				draw_rect(Rect2(4, 3, 1, 3), UITokens.GOLD_3)
			Kind.BAG:
				draw_rect(Rect2(3, 1, 6, 2), UITokens.GOLD_3)
				draw_rect(Rect2(2, 3, 8, 7), UITokens.GOLD_9)
				draw_rect(Rect2(2, 3, 8, 2), UITokens.GOLD_3)
				draw_rect(Rect2(5, 5, 2, 2), UITokens.VOID)
			Kind.SKULL:
				draw_rect(Rect2(3, 1, 6, 2), UITokens.BONE)
				draw_rect(Rect2(2, 3, 8, 4), UITokens.BONE)
				draw_rect(Rect2(3, 7, 6, 2), UITokens.BONE)
				draw_rect(Rect2(4, 9, 1, 2), UITokens.BONE)
				draw_rect(Rect2(7, 9, 1, 2), UITokens.BONE)
				draw_rect(Rect2(4, 4, 2, 2), UITokens.VOID)
				draw_rect(Rect2(7, 4, 2, 2), UITokens.VOID)
			Kind.BONFIRE:
				draw_rect(Rect2(2, 8, 8, 2), UITokens.GOLD_9)
				draw_rect(Rect2(5, 2, 2, 6), UITokens.GOLD_3)
				draw_rect(Rect2(4, 4, 1, 3), UITokens.GOLD)
				draw_rect(Rect2(8, 4, 1, 3), UITokens.GOLD)


## «!» предупреждения: фон blood, рамка blood-3, знак bone (DESIGN §9.1:
## опасность не только цветом).
class _WarningBadge extends Control:

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(12, 12)

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, UITokens.BLOOD)
		UIStyle.draw_frame(self, rect, 1, UITokens.BLOOD_3)
		UIStyle.draw_bang(
			self,
			Rect2(Vector2(2, 2), Vector2(8, 8)),
			UITokens.BLOOD,
			UITokens.BONE
		)


# ------------------------------------------------------------------------------
# Тестовые/QA-геттеры
# ------------------------------------------------------------------------------

func get_root_control() -> Control:
	return _root


func get_title_label() -> Label:
	return _title_label


func get_subtitle_label() -> Label:
	return _subtitle_label


func get_heading_label() -> Label:
	return _heading_label


func get_currency_label() -> Label:
	return _currency_label


func get_items_label() -> Label:
	return _items_label


func get_more_label() -> Label:
	return _more_label


func get_footnote_label() -> Label:
	return _footnote_label


func get_warning_label() -> Label:
	return _warning_label


func get_legend_label() -> Label:
	return _legend_label


func get_legend_icon() -> Control:
	return _legend_icon


func get_respawn_button() -> AshenMenuItem:
	return _respawn_button


func get_menu_button() -> AshenMenuItem:
	return _menu_button


func get_actions() -> HBoxContainer:
	return _actions


func get_left_panel() -> AshenPanel:
	return _left_panel


func get_right_panel() -> AshenPanel:
	return _right_panel


func get_minimap() -> AshenMinimap:
	return _minimap


func get_preview_slots() -> Array[AshenSlot]:
	var copy: Array[AshenSlot] = []
	copy.assign(_preview_slots)
	return copy
