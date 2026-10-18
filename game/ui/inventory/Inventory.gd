class_name InventoryScreen
extends CanvasLayer
## InventoryScreen — экран инвентаря и характеристик (T-21, DESIGN §6.2/§8.4/§9).
##
## Три колонки по `docs/mockups/inventory.html`:
##   * A — экипировка: шлем/броня/оружие/щит/2 кольца + герой, урон/броня/монеты;
##   * B — сетка предметов 6×4, стопки, состояния ячеек (DESIGN §6.2);
##   * D — описание выбранного предмета и требования («ЕСТЬ»/«НЕТ · ещё N»);
##   * C — характеристики (сила/ловкость/выносливость/здоровье), очки обучения,
##     репутация фракций со шкалой −/+/0 и знаком числа.
##
## Данные — только `GameState` (инвентарь, характеристики, очки, валюта) и
## `FactionManager` (репутация/имена/пороги). Требования экипировки —
## `GameState.get_equipment_info()` (T-29), ничего не дублируется.
##
## Кнопки «+» у характеристик всегда отключены: очки тратятся только у
## учителей (AC-08.2). Рядом показана цена следующего шага, а причина
## «Повышайте у учителя» видна текстом и в подсказке — не только цветом.
##
## Открытие/закрытие — только клавиатура (`I`) и геймпад (`START`), действие
## InputMap `inventory`; закрытие также `Esc`/`B` (`ui_cancel`). Пока экран
## открыт, игра на паузе (`pause_on_open`, тесты/QA выключают).

signal opened
signal closed
signal item_selected(item_id: StringName)

const LAYER: int = 20
const ACTION_TOGGLE: StringName = &"inventory"
const SCREEN_SIZE := Vector2(480, 270)

const TAB_TITLES: Array[String] = [
	"ui.inv.tab_hero", "ui.inv.tab_map", "ui.inv.tab_journal", "ui.inv.tab_factions",
]
const ACTIVE_TAB: int = 0

const EQUIPMENT_RECT := Rect2(8, 30, 112, 220)
const ITEMS_RECT := Rect2(128, 30, 189, 148)
const DETAIL_RECT := Rect2(128, 184, 189, 66)
const STATS_RECT := Rect2(325, 30, 147, 220)

const GRID_COLUMNS: int = 6
const GRID_ROWS: int = 4
const GRID_CAPACITY: int = GRID_COLUMNS * GRID_ROWS
const GRID_ORIGIN := Vector2(136, 50)
const GRID_PITCH: int = 29

const EQUIPMENT_ORIGIN := Vector2(16, 48)
const EQUIPMENT_PITCH: int = 30
const HERO_RECT := Rect2(46, 78, 28, 58)

const STATS_X: float = 333.0
const STATS_WIDTH: float = 131.0
const STAT_ROW_HEIGHT: int = 15
const STATS_Y: float = 52.0
const REPUTATION_Y: float = 176.0
const REPUTATION_ROW_HEIGHT: int = 17
## Диапазон шкалы для читаемости: типичные значения репутации ±1…±5.
## Число справа всегда показывает точное значение; длина заливки — для формы.
const REPUTATION_BAR_RANGE: float = 10.0

const TRAINING_REASON: String = "ui.inv.training_reason"
const TRAINING_NOTE: String = "ui.inv.training_note"
const EMPTY_CELL_TEXT: String = "ui.inv.empty_cell"
const EMPTY_INVENTORY_TEXT: String = "ui.inv.empty_inventory"

const STAT_SHORT_NAMES := {
	&"strength": "ui.inv.stat_strength",
	&"dexterity": "ui.inv.stat_dexterity",
	&"endurance": "ui.inv.stat_endurance",
	&"health": "ui.inv.stat_health",
}

## Каталог отображения T-21. Требования/имена оружия приходят из данных
## (`ProgressionData`, `WeaponData`), но `data/items/` пока пуст, поэтому
## подписи и иконки-заглушки живут в UI. Неизвестный id показывается
## человекочитаемо, а не пропадает из сетки.
const ITEM_CATALOG := {
	&"one_handed_sword": {
		"name": "ui.inv.item.one_handed_sword.name",
		"icon": "sword",
		"subtitle": "ui.inv.item.one_handed_sword.subtitle",
		"slot": &"weapon",
	},
	&"two_handed_axe": {
		"name": "ui.inv.item.two_handed_axe.name",
		"icon": "axe",
		"subtitle": "ui.inv.item.two_handed_axe.subtitle",
		"slot": &"weapon",
	},
	&"light_dagger": {
		"name": "ui.inv.item.light_dagger.name",
		"icon": "dagger",
		"subtitle": "ui.inv.item.light_dagger.subtitle",
		"slot": &"weapon",
	},
	&"rusty_sword": {
		"name": "ui.inv.item.rusty_sword.name",
		"icon": "sword",
		"subtitle": "ui.inv.item.rusty_sword.subtitle",
		"slot": &"weapon",
	},
	&"iron_helm": {
		"name": "ui.inv.item.iron_helm.name",
		"icon": "helm",
		"subtitle": "ui.inv.item.iron_helm.subtitle",
		"slot": &"helmet",
		"armor": 3,
	},
	&"leather_armor": {
		"name": "ui.inv.item.leather_armor.name",
		"icon": "armor",
		"subtitle": "ui.inv.item.leather_armor.subtitle",
		"slot": &"armor",
		"armor": 5,
	},
	&"wooden_shield": {
		"name": "ui.inv.item.wooden_shield.name",
		"icon": "shield",
		"subtitle": "ui.inv.item.wooden_shield.subtitle",
		"slot": &"shield",
		"armor": 4,
	},
	&"ashen_ring": {
		"name": "ui.inv.item.ashen_ring.name",
		"icon": "ring",
		"subtitle": "ui.inv.item.ashen_ring.subtitle",
		"slot": &"ring_1",
	},
	&"healing_herb": {
		"name": "ui.inv.item.healing_herb.name",
		"icon": "potion",
		"subtitle": "ui.inv.item.healing_herb.subtitle",
	},
	&"ash_shard": {
		"name": "ui.inv.item.ash_shard.name",
		"icon": "shard",
		"subtitle": "ui.inv.item.ash_shard.subtitle",
	},
	&"bone_charm": {
		"name": "ui.inv.item.bone_charm.name",
		"icon": "charm",
		"subtitle": "ui.inv.item.bone_charm.subtitle",
	},
	&"sealed_relic": {
		"name": "ui.inv.item.sealed_relic.name",
		"icon": "relic",
		"subtitle": "ui.inv.item.sealed_relic.subtitle",
		"available": false,
		"unavailable_reason": "ui.inv.item.sealed_relic.unavailable",
	},
}

## Слоты экипировки в порядке отображения (DESIGN §8.4, mockup `inventory.html`).
const EQUIPMENT_SLOTS: Array[Dictionary] = [
	{"slot_id": &"helmet", "label": "ui.inv.equip_helmet", "cell": Vector2i(1, 0)},
	{"slot_id": &"weapon", "label": "ui.inv.equip_weapon", "cell": Vector2i(0, 1)},
	{"slot_id": &"shield", "label": "ui.inv.equip_shield", "cell": Vector2i(2, 1)},
	{"slot_id": &"ring_1", "label": "ui.inv.equip_ring_1", "cell": Vector2i(0, 2)},
	{"slot_id": &"ring_2", "label": "ui.inv.equip_ring_2", "cell": Vector2i(2, 2)},
	{"slot_id": &"armor", "label": "ui.inv.equip_armor", "cell": Vector2i(1, 3)},
]

## Пауза при открытии. QA/тесты выключают, чтобы не останавливать GUT.
var pause_on_open: bool = true

var _root: Control
var _dim: ColorRect
var _count_label: Label
var _lp_value: Label
var _training_note: Label
var _equipment_values: Dictionary = {}
var _detail_view: ItemDetailView
var _hero: HeroPortrait

var _grid_slots: Array[InventoryItemSlot] = []
var _equipment_slots: Dictionary = {}
var _stat_rows: Array[Control] = []
var _reputation_rows: Array[Control] = []
var _tab_nodes: Array[Control] = []
var _equipment_title: Label
var _items_title: Label
var _stats_title: Label
var _learning_name: Label
var _reputation_title: Label
var _inventory_prompt: AshenPrompt
var _close_prompt: AshenPrompt
var _focus_hint: Label

var _stacks: Array[Dictionary] = []
var _selected_index: int = -1
var _equipped: Dictionary = {}
var _built: bool = false

var _pause_previous: bool = false
var _pause_owned: bool = false


func _init() -> void:
	name = "Inventory"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_ensure_built()
	_connect_events()
	refresh()


func _exit_tree() -> void:
	_disconnect_events()
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false


# ------------------------------------------------------------------------------
# Открытие/закрытие (только клавиатура и геймпад)
# ------------------------------------------------------------------------------

func open() -> bool:
	_ensure_built()
	if visible:
		return false
	if _is_transitioning():
		return false
	refresh()
	visible = true
	_pause_previous = get_tree().paused
	_pause_owned = pause_on_open and not _pause_previous
	if pause_on_open:
		get_tree().paused = true
	_focus_current_slot()
	opened.emit()
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false
	if get_viewport() != null:
		get_viewport().gui_release_focus()
	closed.emit()


func toggle() -> bool:
	if visible:
		close()
		return false
	return open()


func is_open() -> bool:
	return visible


func _input(event: InputEvent) -> void:
	if not visible:
		if _is_toggle_event(event):
			open()
			_consume()
		return

	if _is_toggle_event(event) or event.is_action_pressed(&"ui_cancel"):
		close()
		_consume()
		return
	# Экран модален: подтверждение не должно уходить в мир под ним. Стрелки
	# не перехватываем — навигацию фокуса делает сам UI (a11y §9.2).
	if event.is_action_pressed(&"ui_accept"):
		_consume()


func _is_toggle_event(event: InputEvent) -> bool:
	if not InputMap.has_action(ACTION_TOGGLE):
		return false
	return event.is_action_pressed(ACTION_TOGGLE)


func _consume() -> void:
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


func _is_transitioning() -> bool:
	return SceneRouter.has_method(&"is_input_locked") and bool(SceneRouter.is_input_locked())


# ------------------------------------------------------------------------------
# Данные и снимки для тестов/QA
# ------------------------------------------------------------------------------

## Перечитать GameState/FactionManager и перерисовать экран.
func refresh() -> void:
	_ensure_built()
	_stacks = _build_stacks()
	if _selected_index < 0 and not _stacks.is_empty():
		_selected_index = 0
	_refresh_counter()
	_refresh_equipment()
	_refresh_grid()
	_refresh_detail()
	_refresh_stats()
	_refresh_learning_points()
	_refresh_reputation()
	_refresh_equipment_summary()


func get_grid_capacity() -> int:
	return GRID_CAPACITY


func get_grid_columns() -> int:
	return GRID_COLUMNS


func get_grid_rows() -> int:
	return GRID_ROWS


func get_tab_titles() -> Array[String]:
	return _tab_titles()


func get_active_tab() -> int:
	return ACTIVE_TAB


func get_training_note() -> String:
	return tr(TRAINING_REASON)


func get_learning_points() -> int:
	return GameState.learning_points


func get_selected_index() -> int:
	return _selected_index


func find_grid_index(item_id: StringName) -> int:
	for index: int in _stacks.size():
		if StringName(_stacks[index].get("item_id", &"")) == item_id:
			return index
	return -1


func get_grid_slot(index: int) -> InventoryItemSlot:
	if index < 0 or index >= _grid_slots.size():
		return null
	return _grid_slots[index]


func get_grid_slots() -> Array[InventoryItemSlot]:
	return _grid_slots.duplicate()


func get_equipment_slot(slot_id: StringName) -> InventoryItemSlot:
	return _equipment_slots.get(slot_id) as InventoryItemSlot


func get_stat_rows() -> Array[Control]:
	return _stat_rows.duplicate()


func get_reputation_rows() -> Array[Control]:
	return _reputation_rows.duplicate()


## Выбрать ячейку сетки (фокус — отдельно, чтобы тесты не зависели от ввода).
func select_grid_index(index: int, focus: bool = false) -> void:
	var clamped: int = clampi(index, 0, GRID_CAPACITY - 1)
	_selected_index = clamped
	_refresh_grid()
	_refresh_detail()
	if focus:
		var slot: InventoryItemSlot = get_grid_slot(clamped)
		if slot != null and slot.is_inside_tree():
			slot.grab_focus()
	var stack: Dictionary = _stack_at(clamped)
	if not stack.is_empty():
		item_selected.emit(StringName(stack.get("item_id", &"")))


## Задать надетый предмет слота (экипировка/броня/кольца). Оружие по
## умолчанию берётся из `GameState.weapon`; этот метод позволяет UI/системе
## экипировки показать золотой маркер на остальных слотах.
func set_equipped_item(slot_id: StringName, item_id: StringName) -> void:
	if slot_id == &"":
		return
	_equipped[slot_id] = item_id
	refresh()


func is_item_equipped(item_id: StringName) -> bool:
	if item_id == &"":
		return false
	for equipped_id: Variant in _equipped_ids().values():
		if StringName(str(equipped_id)) == item_id:
			return true
	return false


## Снимок сетки: что реально нарисовано в каждой из 24 ячеек.
func get_grid_data() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in GRID_CAPACITY:
		var slot: InventoryItemSlot = _grid_slots[index]
		var stack: Dictionary = _stack_at(index)
		rows.append({
			"index": index,
			"empty": stack.is_empty(),
			"item_id": StringName(stack.get("item_id", &"")),
			"name": str(stack.get("name", "")),
			"count": int(stack.get("count", 0)),
			"state": slot.get_state_name(),
			"selected": slot.is_selected(),
			"equipped": slot.has_equipped_marker(),
			"requirements": slot.has_requirement_marker(),
			"locked": slot.has_lock_marker(),
			"requirement_summary": slot.requirement_summary,
		})
	return rows


## Снимок описание выбранного предмета (панель D).
func get_detail_data() -> Dictionary:
	var stack: Dictionary = _stack_at(_selected_index)
	if stack.is_empty():
		return {
			"empty": true,
			"item_id": &"",
			"name": tr(EMPTY_CELL_TEXT),
			"subtitle": tr(EMPTY_INVENTORY_TEXT) if _stacks.is_empty() else tr("ui.inv.choose_item"),
			"requirements": [],
			"met": true,
			"requirement_summary": "",
			"equipped": false,
			"unavailable": false,
			"unavailable_reason": "",
			"count": 0,
		}

	var item_id: StringName = StringName(stack.get("item_id", &""))
	var meta: Dictionary = _item_meta(item_id)
	var info: Dictionary = GameState.get_equipment_info(item_id)
	var requirements: Array[Dictionary] = _requirement_rows(item_id)
	var summary: String = _requirement_summary(requirements)
	return {
		"empty": false,
		"item_id": item_id,
		"name": str(stack.get("name", _item_name(item_id))),
		"subtitle": _item_subtitle(item_id),
		"requirements": requirements,
		"met": bool(info.get("met", true)),
		"requirement_summary": summary,
		"reason": str(info.get("reason", "")),
		"equipped": is_item_equipped(item_id),
		"unavailable": not bool(meta.get("available", true)),
		"unavailable_reason": tr(str(meta.get("unavailable_reason", ""))),
		"count": int(stack.get("count", 0)),
	}


## Снимок экипировки (панель A).
func get_equipment_data() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var equipped_ids: Dictionary = _equipped_ids()
	for spec: Dictionary in EQUIPMENT_SLOTS:
		var slot_id: StringName = StringName(spec.get("slot_id", &""))
		var item_id: StringName = StringName(equipped_ids.get(slot_id, &""))
		var slot: InventoryItemSlot = get_equipment_slot(slot_id)
		rows.append({
			"slot_id": slot_id,
			"label": tr(str(spec.get("label", ""))),
			"item_id": item_id,
			"name": "" if item_id == &"" else _item_name(item_id),
			"empty": item_id == &"",
			"state": slot.get_state_name() if slot != null else "empty",
			"requirement_summary": slot.requirement_summary if slot != null else "",
		})
	return rows


## Снимок характеристик (панель C). «+» отключена всегда (AC-08.2).
func get_stat_data() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for stat_id: StringName in GameState.get_stat_ids():
		var cost: int = GameState.get_training_cost(stat_id)
		rows.append({
			"stat_id": stat_id,
			"name": GameState.get_stat_name(stat_id),
			"short_name": _short_stat_name(stat_id),
			"value": GameState.get_stat(stat_id),
			"required_points": cost,
			"cost_text": str(cost) if cost >= 0 else "—",
			"disabled": true,
			"reason": _training_reason(cost),
		})
	return rows


## Снимок репутации (панель C): знак+число, сторона и длина шкалы от нуля.
func get_reputation_data() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for faction_id: StringName in FactionManager.get_faction_ids():
		var value: int = FactionManager.get_reputation(faction_id)
		var display_name: String = FactionManager.get_faction_name(faction_id)
		rows.append({
			"faction_id": faction_id,
			"name": display_name,
			"short_name": _short_faction_name(display_name),
			"value": value,
			"value_text": _format_reputation(value),
			"side": _reputation_side(value),
			"fill_ratio": clampf(absf(float(value)) / REPUTATION_BAR_RANGE, 0.0, 1.0),
			"zero_ratio": 0.5,
			"threshold": FactionManager.get_access_threshold(faction_id),
		})
	return rows


func get_equipment_summary() -> Dictionary:
	var damage: int = 0
	if GameState.weapon != null:
		damage = int(round(GameState.weapon.damage))
	var armor: int = 0
	for item_id: Variant in _equipped_ids().values():
		armor += _item_armor(StringName(str(item_id)))
	return {
		"damage": damage,
		"armor": armor,
		"currency": GameState.currency,
		"currency_text": _format_number(GameState.currency),
	}


## Полный снимок экрана для QA-скриптов.
func get_view_data() -> Dictionary:
	return {
		"open": visible,
		"tabs": get_tab_titles(),
		"active_tab": ACTIVE_TAB,
		"grid": get_grid_data(),
		"grid_capacity": GRID_CAPACITY,
		"grid_columns": GRID_COLUMNS,
		"equipment": get_equipment_data(),
		"detail": get_detail_data(),
		"stats": get_stat_data(),
		"learning_points": GameState.learning_points,
		"training_note": tr(TRAINING_REASON),
		"reputation": get_reputation_data(),
		"summary": get_equipment_summary(),
		"selected_index": _selected_index,
	}


# ------------------------------------------------------------------------------
# Состояние сетки
# ------------------------------------------------------------------------------

func _build_stacks() -> Array[Dictionary]:
	var order: Array[StringName] = []
	var counts: Dictionary = {}
	for raw_id: StringName in GameState.get_inventory():
		if raw_id == &"":
			continue
		if not counts.has(raw_id):
			order.append(raw_id)
			counts[raw_id] = 0
		counts[raw_id] = int(counts[raw_id]) + 1

	var stacks: Array[Dictionary] = []
	for item_id: StringName in order:
		stacks.append({
			"item_id": item_id,
			"count": int(counts.get(item_id, 0)),
			"name": _item_name(item_id),
		})
	return stacks


func _stack_at(index: int) -> Dictionary:
	if index < 0 or index >= _stacks.size() or index >= GRID_CAPACITY:
		return {}
	return _stacks[index]


func _refresh_counter() -> void:
	if _count_label == null:
		return
	var filled: int = mini(_stacks.size(), GRID_CAPACITY)
	var suffix: String = "" if _stacks.size() <= GRID_CAPACITY else "+"
	_count_label.text = "%d%s/%d" % [filled, suffix, GRID_CAPACITY]


func _refresh_grid() -> void:
	for index: int in _grid_slots.size():
		var slot: InventoryItemSlot = _grid_slots[index]
		var selected: bool = index == _selected_index
		var stack: Dictionary = _stack_at(index)
		if stack.is_empty():
			slot.item_id = &""
			slot.item_name = ""
			slot.requirement_summary = ""
			slot.unavailable_reason = ""
			slot.count = -1
			slot.equipped = false
			slot.state = InventoryItemSlot.State.EMPTY
			slot.selected = selected
			continue

		var item_id: StringName = StringName(stack.get("item_id", &""))
		var info: Dictionary = GameState.get_equipment_info(item_id)
		var requirements: Array[Dictionary] = _requirement_rows(item_id)
		var summary: String = _requirement_summary(requirements)
		var blocked: bool = not bool(info.get("met", true))
		var meta: Dictionary = _item_meta(item_id)
		var available: bool = bool(meta.get("available", true))
		var state: InventoryItemSlot.State = InventoryItemSlot.State.NORMAL
		if not available:
			state = InventoryItemSlot.State.UNAVAILABLE
		elif blocked:
			state = InventoryItemSlot.State.REQUIREMENTS
		elif selected:
			state = InventoryItemSlot.State.SELECTED
		slot.apply_item(
			item_id,
			str(stack.get("name", _item_name(item_id))),
			state,
			is_item_equipped(item_id),
			summary,
			tr(str(meta.get("unavailable_reason", ""))),
			_item_icon_kind(item_id)
		)
		slot.selected = selected
		slot.count = int(stack.get("count", 0)) if int(stack.get("count", 0)) > 1 else -1


func _refresh_equipment() -> void:
	var equipped_ids: Dictionary = _equipped_ids()
	for spec: Dictionary in EQUIPMENT_SLOTS:
		var slot_id: StringName = StringName(spec.get("slot_id", &""))
		var slot: InventoryItemSlot = get_equipment_slot(slot_id)
		if slot == null:
			continue
		var item_id: StringName = StringName(equipped_ids.get(slot_id, &""))
		slot.slot_hint = tr(str(spec.get("label", "")))
		slot.selected = false
		if item_id == &"":
			slot.item_id = &""
			slot.item_name = ""
			slot.requirement_summary = ""
			slot.unavailable_reason = ""
			slot.equipped = false
			slot.state = InventoryItemSlot.State.EMPTY
			slot.tooltip_text = tr("ui.inv.slot_empty") % tr(str(spec.get("label", "")))
			continue

		var info: Dictionary = GameState.get_equipment_info(item_id)
		var requirements: Array[Dictionary] = _requirement_rows(item_id)
		var blocked: bool = not bool(info.get("met", true))
		slot.apply_item(
			item_id,
			_item_name(item_id),
			InventoryItemSlot.State.REQUIREMENTS if blocked else InventoryItemSlot.State.NORMAL,
			true,
			_requirement_summary(requirements),
			"",
			_item_icon_kind(item_id)
		)


func _refresh_detail() -> void:
	if _detail_view != null:
		_detail_view.data = get_detail_data()
		_detail_view.queue_redraw()


func _refresh_stats() -> void:
	var rows: Array[Dictionary] = get_stat_data()
	for index: int in _stat_rows.size():
		var row: Variant = _stat_rows[index]
		if index >= rows.size():
			row.visible = false
			continue
		var data: Dictionary = rows[index]
		row.stat_id = StringName(data.get("stat_id", &""))
		row.stat_label = str(data.get("short_name", ""))
		row.full_name = str(data.get("name", ""))
		row.value = int(data.get("value", 0))
		row.required_points = int(data.get("required_points", -1))
		row.disabled_reason = str(data.get("reason", TRAINING_REASON))
		row.tooltip_text = row.disabled_reason
		row.queue_redraw()


func _refresh_learning_points() -> void:
	if _lp_value != null:
		_lp_value.text = str(GameState.learning_points)


func _refresh_reputation() -> void:
	for row: Control in _reputation_rows:
		if row.get_parent() != null:
			row.get_parent().remove_child(row)
		row.free()
	_reputation_rows.clear()

	var rows: Array[Dictionary] = get_reputation_data()
	var y: float = REPUTATION_Y
	for data: Dictionary in rows:
		var row := ReputationRow.new()
		row.name = "Reputation_%s" % str(data.get("faction_id", ""))
		row.faction_id = StringName(data.get("faction_id", &""))
		row.short_name = str(data.get("short_name", ""))
		row.full_name = str(data.get("name", ""))
		row.value = int(data.get("value", 0))
		row.threshold = int(data.get("threshold", 0))
		_root.add_child(row)
		row.position = Vector2(STATS_X, y)
		row.size = Vector2(STATS_WIDTH, float(REPUTATION_ROW_HEIGHT))
		_reputation_rows.append(row)
		y += float(REPUTATION_ROW_HEIGHT)


func _refresh_equipment_summary() -> void:
	var summary: Dictionary = get_equipment_summary()
	for key: String in ["damage", "armor", "currency_text"]:
		var label: Label = _equipment_values.get(key) as Label
		if label == null:
			continue
		label.text = (
			str(summary.get("currency_text", "0"))
			if key == "currency_text"
			else str(summary.get(key, 0))
		)


# ------------------------------------------------------------------------------
# Требования и подписи
# ------------------------------------------------------------------------------

func _requirement_rows(item_id: StringName) -> Array[Dictionary]:
	var info: Dictionary = GameState.get_equipment_info(item_id)
	var requirements: Dictionary = info.get("requirements", {}) as Dictionary
	var rows: Array[Dictionary] = []
	for stat_id: StringName in _ordered_requirement_ids(requirements):
		var required: int = int(requirements.get(stat_id, 0))
		if required <= 0:
			continue
		var current: int = GameState.get_stat(stat_id)
		var deficit: int = maxi(required - current, 0)
		rows.append({
			"stat_id": stat_id,
			"name": GameState.get_stat_name(stat_id),
			"short_name": _short_stat_name(stat_id),
			"required": required,
			"current": current,
			"deficit": deficit,
			"met": deficit == 0,
			"tag": _requirement_tag(required, current, deficit),
		})
	return rows


func _ordered_requirement_ids(requirements: Dictionary) -> Array[StringName]:
	var ordered: Array[StringName] = []
	for stat_id: StringName in GameState.get_stat_ids():
		if requirements.has(stat_id):
			ordered.append(stat_id)
	for key: Variant in requirements.keys():
		var stat_id: StringName = StringName(str(key))
		if stat_id != &"" and not ordered.has(stat_id):
			ordered.append(stat_id)
	return ordered


func _requirement_tag(required: int, current: int, deficit: int) -> String:
	if deficit > 0:
		return tr("ui.inv.none_more") % deficit
	return tr("ui.inv.have") % current


func _requirement_summary(rows: Array[Dictionary]) -> String:
	if rows.is_empty():
		return ""
	var max_deficit: int = 0
	for row: Dictionary in rows:
		max_deficit = maxi(max_deficit, int(row.get("deficit", 0)))
	if max_deficit > 0:
		return tr("ui.inv.none_more") % max_deficit
	return tr("ui.inv.have_all")


func _training_reason(cost: int) -> String:
	if cost < 0:
		return tr("ui.inv.training_max") % tr(TRAINING_REASON)
	return tr("ui.inv.training_need") % [tr(TRAINING_REASON), cost, _points_word(cost)]


func _points_word(cost: int) -> String:
	if Locale.is_english():
		return tr("ui.inv.points_word")
	var tail: int = cost % 100
	if tail >= 11 and tail <= 14:
		return tr("ui.inv.points_word_many")
	match cost % 10:
		1:
			return tr("ui.inv.points_word_one")
		2, 3, 4:
			return tr("ui.inv.points_word_few")
		_:
			return tr("ui.inv.points_word_many")


func _short_stat_name(stat_id: StringName) -> String:
	var known: Variant = STAT_SHORT_NAMES.get(stat_id)
	if known is String:
		return tr(str(known))
	var name: String = GameState.get_stat_name(stat_id).to_upper()
	if name.length() > 6:
		return name.substr(0, 6)
	return name


func _short_faction_name(display_name: String) -> String:
	var upper: String = display_name.to_upper()
	var parts: PackedStringArray = upper.split(" ", false)
	var first: String = parts[0] if not parts.is_empty() else upper
	if first.length() > 6:
		return first.substr(0, 5) + "."
	return first


func _format_reputation(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)


func _reputation_side(value: int) -> String:
	if value > 0:
		return "positive"
	if value < 0:
		return "negative"
	return "zero"


func _format_number(value: int) -> String:
	var digits: String = str(absi(value))
	var grouped: String = ""
	while digits.length() > 3:
		grouped = " " + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + grouped


func _tab_titles() -> Array[String]:
	var titles: Array[String] = []
	for key: String in TAB_TITLES:
		titles.append(tr(key))
	return titles


func _on_locale_changed(_code: String) -> void:
	_retranslate()


func _retranslate() -> void:
	if not _built:
		return
	var titles: Array[String] = _tab_titles()
	for index: int in _tab_nodes.size():
		var node: Control = _tab_nodes[index]
		if index < titles.size():
			node.set(&"text", titles[index])
	_equipment_title.text = tr("ui.inv.equipment")
	_items_title.text = tr("ui.inv.items")
	_stats_title.text = tr("ui.inv.stats")
	_learning_name.text = tr("ui.inv.learning_points")
	_reputation_title.text = tr("ui.inv.reputation")
	_training_note.text = tr(TRAINING_NOTE)
	_inventory_prompt.setup(ACTION_TOGGLE, tr("ui.inv.inventory"))
	_close_prompt.setup(&"ui_cancel", tr("ui.inv.close"))
	_focus_hint.text = tr("ui.inv.focus_hint")
	refresh()


func _item_meta(item_id: StringName) -> Dictionary:
	var meta: Variant = ITEM_CATALOG.get(item_id)
	return meta as Dictionary if meta is Dictionary else {}


func _item_name(item_id: StringName) -> String:
	var meta: Dictionary = _item_meta(item_id)
	var known: Variant = meta.get("name")
	if known is String and known != "":
		return tr(str(known))
	return String(item_id).replace("_", " ").to_upper()


func _item_subtitle(item_id: StringName) -> String:
	var meta: Dictionary = _item_meta(item_id)
	var known: Variant = meta.get("subtitle")
	return tr(str(known)) if known is String else tr("ui.inv.item_fallback")


func _item_armor(item_id: StringName) -> int:
	return int(_item_meta(item_id).get("armor", 0))


func _item_icon_kind(item_id: StringName) -> String:
	var known: Variant = _item_meta(item_id).get("icon")
	return str(known) if known is String else "misc"


func _equipped_ids() -> Dictionary:
	var result: Dictionary = {}
	if GameState.weapon != null and GameState.weapon.id != &"":
		result[&"weapon"] = GameState.weapon.id
	for key: Variant in _equipped.keys():
		var slot_id: StringName = StringName(str(key))
		if slot_id != &"":
			result[slot_id] = StringName(str(_equipped[key]))
	return result


# ------------------------------------------------------------------------------
# Фокус
# ------------------------------------------------------------------------------

func _focus_current_slot() -> void:
	var index: int = _selected_index
	if index < 0:
		index = 0
	var slot: InventoryItemSlot = get_grid_slot(index)
	if slot != null and slot.is_inside_tree():
		slot.grab_focus()


func _on_slot_focused(index: int) -> void:
	if _selected_index == index:
		return
	_selected_index = index
	_refresh_grid()
	_refresh_detail()
	var stack: Dictionary = _stack_at(index)
	if not stack.is_empty():
		item_selected.emit(StringName(stack.get("item_id", &"")))


func _on_slot_pressed(index: int) -> void:
	select_grid_index(index)


# ------------------------------------------------------------------------------
# Сигналы состояния
# ------------------------------------------------------------------------------

func _connect_events() -> void:
	if not EventBus.stat_changed.is_connected(_on_stat_changed):
		EventBus.stat_changed.connect(_on_stat_changed)
	if not EventBus.learning_points_changed.is_connected(_on_learning_points_changed):
		EventBus.learning_points_changed.connect(_on_learning_points_changed)
	if not EventBus.level_changed.is_connected(_on_level_changed):
		EventBus.level_changed.connect(_on_level_changed)
	if not EventBus.faction_reputation_changed.is_connected(_on_faction_reputation_changed):
		EventBus.faction_reputation_changed.connect(_on_faction_reputation_changed)
	if not EventBus.save_loaded.is_connected(_on_save_loaded):
		EventBus.save_loaded.connect(_on_save_loaded)
	if not Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.connect(_on_locale_changed)


func _disconnect_events() -> void:
	if EventBus.stat_changed.is_connected(_on_stat_changed):
		EventBus.stat_changed.disconnect(_on_stat_changed)
	if EventBus.learning_points_changed.is_connected(_on_learning_points_changed):
		EventBus.learning_points_changed.disconnect(_on_learning_points_changed)
	if EventBus.level_changed.is_connected(_on_level_changed):
		EventBus.level_changed.disconnect(_on_level_changed)
	if EventBus.faction_reputation_changed.is_connected(_on_faction_reputation_changed):
		EventBus.faction_reputation_changed.disconnect(_on_faction_reputation_changed)
	if EventBus.save_loaded.is_connected(_on_save_loaded):
		EventBus.save_loaded.disconnect(_on_save_loaded)
	if Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.disconnect(_on_locale_changed)


func _on_stat_changed(_stat_id: StringName, _value: int, _next_cost: int) -> void:
	if visible:
		refresh()


func _on_learning_points_changed(_points: int) -> void:
	if visible:
		_refresh_learning_points()
		_refresh_stats()


func _on_level_changed(_level: int, _points_awarded: int) -> void:
	if visible:
		_refresh_learning_points()


func _on_faction_reputation_changed(_faction_id: StringName, _value: int) -> void:
	if visible:
		_refresh_reputation()


func _on_save_loaded(_slot: int) -> void:
	refresh()


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

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(UITokens.VOID, 0.94)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_tabs()
	_build_equipment()
	_build_items()
	_build_detail()
	_build_stats()
	_build_footer()


func _build_tabs() -> void:
	var strip := ColorRect.new()
	strip.name = "TabRule"
	strip.color = UITokens.STONE_9
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(strip)
	strip.position = Vector2(UITokens.SAFE_MARGIN, 26)
	strip.size = Vector2(SCREEN_SIZE.x - UITokens.SAFE_MARGIN * 2, 2)

	var x: float = 14.0
	var titles: Array[String] = _tab_titles()
	for index: int in titles.size():
		var width: float = maxf(
			56.0,
			UIStyle.text_width(titles[index], UITokens.FONT_BODY) + 16.0
		)
		if index == ACTIVE_TAB:
			var tab := AshenTab.new()
			tab.name = "Tab%d" % index
			tab.text = titles[index]
			tab.font_size = UITokens.FONT_BODY
			tab.selected = true
			tab.focus_mode = Control.FOCUS_NONE
			tab.custom_minimum_size = Vector2(width, float(UITokens.TAB_HEIGHT))
			_root.add_child(tab)
			tab.position = Vector2(x, float(UITokens.SAFE_MARGIN - 2))
			tab.size = Vector2(width, float(UITokens.TAB_HEIGHT))
			_tab_nodes.append(tab)
		else:
			# Разделы КАРТА/ЖУРНАЛ/ФРАКЦИИ — отдельные экраны (T-24). Здесь
			# это контекстные подписи, а не disabled-кнопки без причины.
			var label := _make_label(
				titles[index],
				UITokens.STONE_5,
				UITokens.FONT_BODY,
				HORIZONTAL_ALIGNMENT_CENTER
			)
			label.name = "TabLabel%d" % index
			label.position = Vector2(x, 9)
			label.size = Vector2(width, 12)
			label.tooltip_text = tr("ui.inv.separate_screen")
			_tab_nodes.append(label)
			_root.add_child(label)
		x += width + float(UITokens.SP_2)


func _build_equipment() -> void:
	_add_panel("EquipmentPanel", EQUIPMENT_RECT, UIStyle.PanelVariant.SOLID, 0)
	_equipment_title = _make_label(tr("ui.inv.equipment"), UITokens.GOLD_3)
	var title := _equipment_title
	title.name = "EquipmentTitle"
	title.position = Vector2(20, 36)
	title.size = Vector2(88, UITokens.LINE_BODY)
	_root.add_child(title)

	for spec: Dictionary in EQUIPMENT_SLOTS:
		var slot := InventoryItemSlot.new()
		var slot_id: StringName = StringName(spec.get("slot_id", &""))
		var cell: Vector2i = spec.get("cell", Vector2i.ZERO)
		slot.name = "Equip_%s" % str(slot_id)
		slot.slot_size = UITokens.SLOT_INV
		slot.slot_hint = tr(str(spec.get("label", "")))
		slot.focus_mode = Control.FOCUS_NONE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(slot)
		slot.position = EQUIPMENT_ORIGIN + Vector2(
			float(cell.x) * float(EQUIPMENT_PITCH),
			float(cell.y) * float(EQUIPMENT_PITCH)
		)
		slot.size = Vector2(UITokens.SLOT_INV, UITokens.SLOT_INV)
		_equipment_slots[slot_id] = slot

	_hero = HeroPortrait.new()
	_hero.name = "Hero"
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hero)
	_hero.position = HERO_RECT.position
	_hero.size = HERO_RECT.size

	_add_separator("EquipmentRule", Vector2(20, 172), 80)

	var rows: Array[Dictionary] = [
		{"key": "damage", "label": "ui.inv.damage", "y": 182.0, "color": UITokens.BONE},
		{"key": "armor", "label": "ui.inv.armor", "y": 197.0, "color": UITokens.BONE},
		{"key": "currency_text", "label": "ui.inv.coins_short", "y": 212.0, "color": UITokens.GOLD_3},
	]
	for row: Dictionary in rows:
		var name_label := _make_label(tr(str(row.get("label", ""))), UITokens.STONE_5)
		name_label.position = Vector2(20, float(row.get("y", 0.0)))
		name_label.size = Vector2(48, UITokens.LINE_BODY)
		_root.add_child(name_label)

		var value_label := _make_label("0", row.get("color", UITokens.BONE) as Color)
		value_label.name = "EquipValue_%s" % str(row.get("key", ""))
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.position = Vector2(70, float(row.get("y", 0.0)))
		value_label.size = Vector2(38, UITokens.LINE_BODY)
		_root.add_child(value_label)
		_equipment_values[str(row.get("key", ""))] = value_label


func _build_items() -> void:
	_add_panel("ItemsPanel", ITEMS_RECT, UIStyle.PanelVariant.SOLID, 2)

	_items_title = _make_label(tr("ui.inv.items"), UITokens.GOLD_3)
	var title := _items_title
	title.name = "ItemsTitle"
	title.position = Vector2(136, 38)
	title.size = Vector2(100, UITokens.LINE_BODY)
	_root.add_child(title)

	_count_label = _make_label("0/%d" % GRID_CAPACITY, UITokens.STONE_5)
	_count_label.name = "ItemsCount"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.position = Vector2(236, 38)
	_count_label.size = Vector2(73, UITokens.LINE_BODY)
	_root.add_child(_count_label)

	for index: int in GRID_CAPACITY:
		var slot := InventoryItemSlot.new()
		var column: int = index % GRID_COLUMNS
		var row: int = index / GRID_COLUMNS
		slot.name = "Slot%d" % index
		slot.slot_size = UITokens.SLOT_INV
		slot.focus_mode = Control.FOCUS_ALL
		_root.add_child(slot)
		slot.position = GRID_ORIGIN + Vector2(
			float(column * GRID_PITCH),
			float(row * GRID_PITCH)
		)
		slot.size = Vector2(UITokens.SLOT_INV, UITokens.SLOT_INV)
		slot.pressed.connect(_on_slot_pressed.bind(index))
		slot.focus_entered.connect(_on_slot_focused.bind(index))
		_grid_slots.append(slot)

	_connect_grid_neighbors()


func _connect_grid_neighbors() -> void:
	for index: int in _grid_slots.size():
		var slot: InventoryItemSlot = _grid_slots[index]
		var column: int = index % GRID_COLUMNS
		var left: int = index - 1 if column > 0 else index + GRID_COLUMNS - 1
		var right: int = index + 1 if column < GRID_COLUMNS - 1 else index - GRID_COLUMNS + 1
		var up: int = index - GRID_COLUMNS if index >= GRID_COLUMNS else index + GRID_COLUMNS * (GRID_ROWS - 1)
		var down: int = index + GRID_COLUMNS if index + GRID_COLUMNS < GRID_CAPACITY else index - GRID_COLUMNS * (GRID_ROWS - 1)
		slot.focus_neighbor_left = slot.get_path_to(_grid_slots[left])
		slot.focus_neighbor_right = slot.get_path_to(_grid_slots[right])
		slot.focus_neighbor_top = slot.get_path_to(_grid_slots[up])
		slot.focus_neighbor_bottom = slot.get_path_to(_grid_slots[down])


func _build_detail() -> void:
	_add_panel("DetailPanel", DETAIL_RECT, UIStyle.PanelVariant.SOLID, 2)
	_detail_view = ItemDetailView.new()
	_detail_view.name = "Detail"
	_detail_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_detail_view)
	_detail_view.position = Vector2(136, 192)
	_detail_view.size = Vector2(173, 50)


func _build_stats() -> void:
	_add_panel("StatsPanel", STATS_RECT, UIStyle.PanelVariant.SOLID, 0)

	_stats_title = _make_label(tr("ui.inv.stats"), UITokens.GOLD_3)
	var title := _stats_title
	title.name = "StatsTitle"
	title.position = Vector2(STATS_X, 36)
	title.size = Vector2(STATS_WIDTH, UITokens.LINE_BODY)
	_root.add_child(title)

	_add_separator("StatsRuleTop", Vector2(STATS_X, 48), STATS_WIDTH)

	for index: int in GameState.get_stat_ids().size():
		var row := StatRow.new()
		row.name = "StatRow%d" % index
		_root.add_child(row)
		row.position = Vector2(STATS_X, STATS_Y + float(index * STAT_ROW_HEIGHT))
		row.size = Vector2(STATS_WIDTH, float(STAT_ROW_HEIGHT))
		_stat_rows.append(row)

	_add_separator("StatsRuleMid", Vector2(STATS_X, 116), STATS_WIDTH)

	_learning_name = _make_label(tr("ui.inv.learning_points"), UITokens.GOLD_3)
	var lp_name := _learning_name
	lp_name.name = "LearningName"
	lp_name.position = Vector2(STATS_X, 122)
	lp_name.size = Vector2(90, UITokens.LINE_BODY)
	_root.add_child(lp_name)

	_lp_value = _make_label("0", UITokens.GOLD_3)
	_lp_value.name = "LearningValue"
	_lp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lp_value.position = Vector2(STATS_X + 100, 122)
	_lp_value.size = Vector2(31, UITokens.LINE_BODY)
	_root.add_child(_lp_value)

	_training_note = _make_label(tr(TRAINING_NOTE), UITokens.STONE_5)
	_training_note.name = "TrainingNote"
	_training_note.position = Vector2(STATS_X, 134)
	_training_note.size = Vector2(STATS_WIDTH, 24)
	_root.add_child(_training_note)

	_add_separator("StatsRuleBottom", Vector2(STATS_X, 158), STATS_WIDTH)

	_reputation_title = _make_label(tr("ui.inv.reputation"), UITokens.GOLD_3)
	var rep_title := _reputation_title
	rep_title.name = "ReputationTitle"
	rep_title.position = Vector2(STATS_X, 161)
	rep_title.size = Vector2(STATS_WIDTH, UITokens.LINE_BODY)
	_root.add_child(rep_title)


func _build_footer() -> void:
	_inventory_prompt = AshenPrompt.new()
	_inventory_prompt.name = "InventoryPrompt"
	_root.add_child(_inventory_prompt)
	_inventory_prompt.position = Vector2(UITokens.SAFE_MARGIN, 256)
	_inventory_prompt.setup(ACTION_TOGGLE, tr("ui.inv.inventory"))

	_close_prompt = AshenPrompt.new()
	_close_prompt.name = "ClosePrompt"
	_root.add_child(_close_prompt)
	_close_prompt.position = Vector2(120, 256)
	_close_prompt.setup(&"ui_cancel", tr("ui.inv.close"))

	_focus_hint = _make_label(tr("ui.inv.focus_hint"), UITokens.STONE_5)
	_focus_hint.name = "FocusHint"
	_focus_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_focus_hint.position = Vector2(352, 256)
	_focus_hint.size = Vector2(120, UITokens.LINE_BODY)
	_root.add_child(_focus_hint)


func _add_panel(
	panel_name: String,
	rect: Rect2,
	variant: int,
	padding: int
) -> AshenPanel:
	var panel := AshenPanel.new()
	panel.name = panel_name
	panel.variant = variant
	panel.padding = padding
	_root.add_child(panel)
	panel.position = rect.position
	panel.size = rect.size
	return panel


func _add_separator(separator_name: String, at: Vector2, width: float) -> void:
	var rule := ColorRect.new()
	rule.name = separator_name
	rule.color = UITokens.STONE_9
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rule)
	rule.position = at
	rule.size = Vector2(width, 1)


func _make_label(
	text: String,
	color: Color,
	size: int = UITokens.FONT_BODY,
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
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label


# ------------------------------------------------------------------------------
# Внутренние визуальные компоненты
# ------------------------------------------------------------------------------

## Строка характеристики с навсегда отключённой кнопкой «+» (AC-08.2).
## Причина видна в подсказке и постоянной строке «ПОВЫШАЙТЕ У УЧИТЕЛЯ».
class StatRow extends Control:
	var stat_id: StringName = &""
	var stat_label: String = ""
	var full_name: String = ""
	var value: int = 0
	var required_points: int = -1
	var disabled_reason: String = "ui.inv.default_train_reason"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		mouse_entered.connect(_on_mouse_entered)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _ready() -> void:
		tooltip_text = disabled_reason

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var focused: bool = has_focus()
		if focused:
			draw_rect(Rect2(Vector2.ZERO, size), UITokens.NIGHT_3)

		var plus_size: int = 11
		var cost_width: float = 18.0
		var value_width: float = 18.0
		var plus_x: float = size.x - float(plus_size)
		var cost_x: float = plus_x - 2.0 - cost_width
		var value_x: float = cost_x - 2.0 - value_width
		var center_y: float = (size.y - UIStyle.text_height(UITokens.FONT_BODY)) * 0.5
		var baseline: float = center_y + UIStyle.baseline_y(UITokens.FONT_BODY)

		UIStyle.draw_text(
			self,
			Vector2(0, baseline),
			stat_label,
			UITokens.STONE_5,
			UITokens.FONT_BODY,
			value_x - 2.0
		)
		UIStyle.draw_text(
			self,
			Vector2(value_x, baseline),
			str(value),
			UITokens.BONE,
			UITokens.FONT_BODY,
			value_width,
			HORIZONTAL_ALIGNMENT_RIGHT
		)
		UIStyle.draw_text(
			self,
			Vector2(cost_x, baseline),
			"·—" if required_points < 0 else "·%d" % required_points,
			UITokens.STONE_3,
			UITokens.FONT_BODY,
			cost_width,
			HORIZONTAL_ALIGNMENT_RIGHT
		)

		# Кнопка «+» отключена: пунктирная рамка + причина в подсказке/ноте.
		var plus_rect := Rect2(
			Vector2(plus_x, (size.y - float(plus_size)) * 0.5),
			Vector2(float(plus_size), float(plus_size))
		)
		UIStyle.draw_dashed_frame(self, plus_rect, 1, UITokens.STONE_3)
		UIStyle.draw_text(
			self,
			Vector2(plus_rect.position.x, plus_rect.position.y + 8),
			"+",
			UITokens.STONE_3,
			UITokens.FONT_BODY,
			plus_rect.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)

		if focused:
			draw_rect(Rect2(0, 0, 2, size.y), UITokens.GOLD)
			UIStyle.draw_frame(self, Rect2(Vector2.ZERO, size), UITokens.BORDER_INNER, UITokens.GOLD_9)
			UIStyle.draw_focus_brackets(
				self,
				Rect2(Vector2.ZERO, size).grow(-2),
				UITokens.GOLD_3,
				UITokens.FOCUS_ARM,
				UITokens.BORDER_INNER
			)

	func is_plus_disabled() -> bool:
		return true

	func get_disabled_reason() -> String:
		return disabled_reason

	func get_required_points() -> int:
		return required_points

	func get_value() -> int:
		return value

	func get_stat_id() -> StringName:
		return stat_id

	func get_stat_label() -> String:
		return stat_label

	func _on_mouse_entered() -> void:
		if is_inside_tree():
			grab_focus()


## Строка репутации: шкала с нулём посередине, заливка в сторону знака и
## текст «+2»/«−1»/«0» (состояние не только цветом, AC-06.x, DESIGN §9.1).
class ReputationRow extends Control:
	const BAR_X: float = 50.0
	const VALUE_WIDTH: float = 26.0
	const BAR_HEIGHT: float = 6.0
	const DISPLAY_RANGE: float = 10.0

	var faction_id: StringName = &""
	var short_name: String = ""
	var full_name: String = ""
	var value: int = 0
	var threshold: int = 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _ready() -> void:
		tooltip_text = tr("ui.inv.faction_tooltip") % [
			full_name,
			get_value_text(),
			threshold,
		]

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var baseline: float = (
			(size.y - UIStyle.text_height(UITokens.FONT_BODY)) * 0.5
			+ UIStyle.baseline_y(UITokens.FONT_BODY)
		)
		UIStyle.draw_text(
			self,
			Vector2(0, baseline),
			short_name,
			UITokens.STONE_5,
			UITokens.FONT_BODY,
			BAR_X - 2.0
		)

		var bar_width: float = maxf(size.x - BAR_X - VALUE_WIDTH - 3.0, 8.0)
		var bar_rect := Rect2(
			Vector2(BAR_X, (size.y - BAR_HEIGHT) * 0.5),
			Vector2(bar_width, BAR_HEIGHT)
		)
		draw_rect(bar_rect, UITokens.VOID)
		UIStyle.draw_frame(self, bar_rect, UITokens.BORDER_INNER, UITokens.STONE_3)

		var center_x: float = bar_rect.position.x + floor(bar_width * 0.5)
		draw_rect(
			Rect2(center_x, bar_rect.position.y - 1.0, 1.0, BAR_HEIGHT + 2.0),
			UITokens.STONE_5
		)

		var fill_width: float = roundf((bar_width - 2.0) * 0.5 * get_fill_ratio())
		if value != 0 and fill_width >= 1.0:
			var fill_x: float = center_x + 1.0 if value > 0 else center_x - fill_width
			draw_rect(
				Rect2(fill_x, bar_rect.position.y + 1.0, fill_width, BAR_HEIGHT - 2.0),
				UITokens.STEEL_3 if value > 0 else UITokens.BLOOD_3
			)

		var value_color: Color = UITokens.STONE_5
		if value > 0:
			value_color = UITokens.STEEL_3
		elif value < 0:
			value_color = UITokens.BLOOD_5
		UIStyle.draw_text(
			self,
			Vector2(size.x - VALUE_WIDTH, baseline),
			get_value_text(),
			value_color,
			UITokens.FONT_BODY,
			VALUE_WIDTH,
			HORIZONTAL_ALIGNMENT_RIGHT
		)

	func get_value_text() -> String:
		if value > 0:
			return "+%d" % value
		return str(value)

	func get_fill_ratio() -> float:
		return clampf(absf(float(value)) / DISPLAY_RANGE, 0.0, 1.0)

	func get_zero_ratio() -> float:
		return 0.5

	func get_fill_side() -> String:
		if value > 0:
			return "positive"
		if value < 0:
			return "negative"
		return "zero"


## Панель описания: имя, тип, требования «ЕСТЬ N» / «НЕТ · ещё N».
class ItemDetailView extends Control:
	var data: Dictionary = {}

	func _draw() -> void:
		if data.is_empty() or size.x <= 0.0:
			return
		var title: String = _fit(str(data.get("name", "")), size.x)
		UIStyle.draw_text(
			self,
			Vector2(0, UIStyle.baseline_y(UITokens.FONT_BODY)),
			title,
			UITokens.GOLD_3,
			UITokens.FONT_BODY
		)

		var subtitle: String = str(data.get("subtitle", ""))
		if bool(data.get("equipped", false)):
			subtitle = tr("ui.inv.equipped_suffix") % subtitle
		UIStyle.draw_text(
			self,
			Vector2(0, 20.0),
			_fit(subtitle, size.x),
			UITokens.STONE_5,
			UITokens.FONT_BODY
		)

		if bool(data.get("empty", false)):
			return

		if bool(data.get("unavailable", false)):
			var lock_text: String = tr("ui.inv.unavailable_prefix") % str(data.get("unavailable_reason", ""))
			UIStyle.draw_text(
				self,
				Vector2(0, 32.0),
				_fit(lock_text, size.x),
				UITokens.BLOOD_5,
				UITokens.FONT_BODY
			)
			return

		var requirements: Array = data.get("requirements", [])
		if requirements.is_empty():
			UIStyle.draw_text(
				self,
				Vector2(0, 32.0),
				tr("ui.inv.no_requirements"),
				UITokens.STEEL_3,
				UITokens.FONT_BODY
			)
			return

		for index: int in mini(requirements.size(), 2):
			var row: Dictionary = requirements[index]
			var y: float = 32.0 + float(index) * 12.0
			var left: String = "%s %d" % [
				str(row.get("short_name", "")),
				int(row.get("required", 0)),
			]
			UIStyle.draw_text(
				self,
				Vector2(0, y),
				_fit(left, size.x * 0.45),
				UITokens.STONE_5,
				UITokens.FONT_BODY
			)
			_draw_tag(
				str(row.get("tag", "")),
				bool(row.get("met", false)),
				y
			)

	func _draw_tag(text: String, met: bool, baseline: float) -> void:
		if text == "":
			return
		var tag_width: float = UIStyle.text_width(text, UITokens.FONT_BODY) + 6.0
		var tag_rect := Rect2(
			Vector2(size.x - tag_width, baseline - 8.0),
			Vector2(tag_width, 10.0)
		)
		if met:
			UIStyle.draw_frame(self, tag_rect, UITokens.BORDER_INNER, UITokens.STEEL_3)
			UIStyle.draw_text(
				self,
				Vector2(tag_rect.position.x + 3.0, baseline - 1.0),
				text,
				UITokens.STEEL_3,
				UITokens.FONT_BODY
			)
		else:
			draw_rect(tag_rect, UITokens.BLOOD)
			UIStyle.draw_frame(self, tag_rect, UITokens.BORDER_INNER, UITokens.BLOOD_3)
			UIStyle.draw_text(
				self,
				Vector2(tag_rect.position.x + 3.0, baseline - 1.0),
				text,
				UITokens.BONE,
				UITokens.FONT_BODY
			)

	func _fit(text: String, max_width: float) -> String:
		if UIStyle.text_width(text, UITokens.FONT_BODY) <= max_width:
			return text
		var fitted: String = text
		while fitted.length() > 1 and UIStyle.text_width(fitted, UITokens.FONT_BODY) > max_width:
			fitted = fitted.substr(0, fitted.length() - 1)
		return fitted.substr(0, maxi(fitted.length() - 1, 1)) + "."


## Пиксельный силуэт героя 16×24 (заглушка до арт-ассетов, DESIGN §7).
class HeroPortrait extends Control:
	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var origin := Vector2(
			floor((size.x - 16.0) * 0.5),
			floor((size.y - 24.0) * 0.5)
		)
		# Плащ/силуэт.
		draw_rect(Rect2(origin + Vector2(3, 7), Vector2(10, 12)), UITokens.BLOOD_9)
		# Голова.
		draw_rect(Rect2(origin + Vector2(5, 2), Vector2(6, 5)), UITokens.GREEN_3)
		draw_rect(Rect2(origin + Vector2(6, 3), Vector2(1, 1)), UITokens.BONE)
		draw_rect(Rect2(origin + Vector2(9, 3), Vector2(1, 1)), UITokens.BONE)
		# Корпус, руки, ноги.
		draw_rect(Rect2(origin + Vector2(4, 7), Vector2(8, 9)), UITokens.GREEN_3)
		draw_rect(Rect2(origin + Vector2(2, 8), Vector2(2, 7)), UITokens.GREEN_3)
		draw_rect(Rect2(origin + Vector2(12, 8), Vector2(2, 7)), UITokens.GREEN_3)
		draw_rect(Rect2(origin + Vector2(5, 16), Vector2(2, 6)), UITokens.GREEN_3)
		draw_rect(Rect2(origin + Vector2(9, 16), Vector2(2, 6)), UITokens.GREEN_3)
		# Меч.
		draw_rect(Rect2(origin + Vector2(14, 3), Vector2(1, 12)), UITokens.STEEL_3)
		draw_rect(Rect2(origin + Vector2(13, 13), Vector2(3, 1)), UITokens.GOLD_9)
		UIStyle.draw_frame(self, Rect2(origin + Vector2(4, 2), Vector2(8, 6)), 1, UITokens.STONE_5)
