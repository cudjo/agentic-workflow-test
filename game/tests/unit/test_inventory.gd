extends GutTest
## T-21 — экран инвентаря и характеристик (DESIGN §6.2/§8.4/§9; SPEC US-08,
## AC-08.2, AC-06.x).
##
## Проверяем:
##   * 3 колонки и сетку 6×4 (24 ячейки), 6 слотов экипировки, 4 характеристики;
##   * состояния ячеек: обычный/выбран/надет/требования/пусто/недоступно;
##   * требования «ЕСТЬ N» / «НЕТ · ещё N» из `GameState.get_equipment_info()`;
##   * золотой маркер надетого предмета;
##   * кнопки «+» всегда отключены с причиной «повышайте у учителя» и ценой шага;
##   * репутацию фракций с нулём посередине и знаком числа (+2/−1/0);
##   * открытие/закрытие только клавиатурой и геймпадом (InputMap `inventory`).
##
## Данные не дублируются: стартовые характеристики и цены шагов берутся из
## `progression.tres` через GameState; репутация — через FactionManager.

const INVENTORY_SCENE := preload("res://ui/inventory/Inventory.tscn")
const SWORD_PATH: String = "res://data/weapons/one_handed_sword.tres"

var _inventory: InventoryScreen

var _saved_inventory: Array[StringName] = []
var _saved_stats: Dictionary = {}
var _saved_learning_points: int = 0
var _saved_level: int = 1
var _saved_xp: int = 0
var _saved_hp: float = 0.0
var _saved_weapon: WeaponData
var _saved_reputation: Dictionary = {}
var _saved_chosen_faction: StringName = &""


func before_each() -> void:
	_saved_inventory = GameState.get_inventory()
	_saved_stats = GameState.get_stats()
	_saved_learning_points = GameState.learning_points
	_saved_level = GameState.level
	_saved_xp = GameState.xp
	_saved_hp = GameState.hp
	_saved_weapon = GameState.weapon
	_saved_reputation = GameState.get_all_faction_reputation()
	_saved_chosen_faction = GameState.chosen_faction

	GameState.clear_inventory()
	GameState.reset_progression()
	GameState.set_learning_points(3)
	GameState.reset_hp()
	GameState.reset_factions()
	GameState.set_weapon(load(SWORD_PATH) as WeaponData)

	_inventory = INVENTORY_SCENE.instantiate() as InventoryScreen
	assert_not_null(_inventory, "Inventory.tscn instantiates as InventoryScreen")
	_inventory.pause_on_open = false
	add_child_autofree(_inventory)


func after_each() -> void:
	GameState.restore_progression(
		_saved_stats,
		_saved_learning_points,
		_saved_level,
		_saved_xp
	)
	GameState.restore_hp(_saved_hp)
	GameState.set_weapon(_saved_weapon)
	GameState.restore_inventory(_saved_inventory)
	GameState.restore_factions(_saved_reputation, _saved_chosen_faction)


# ------------------------------------------------------------------------------
# Структура: 3 колонки, сетка 6×4, экипировка, характеристики, репутация
# ------------------------------------------------------------------------------

func test_screen_has_three_columns_and_6x4_grid() -> void:
	assert_eq(
		_inventory.get_tab_titles(),
		["ГЕРОЙ", "КАРТА", "ЖУРНАЛ", "ФРАКЦИИ"],
		"вкладки как в макете inventory.html"
	)
	assert_eq(_inventory.get_active_tab(), 0, "открыт раздел ГЕРОЙ")

	assert_eq(_inventory.get_grid_capacity(), 24, "сетка 6×4 = 24 ячейки")
	assert_eq(_inventory.get_grid_columns(), 6)
	assert_eq(_inventory.get_grid_rows(), 4)

	assert_not_null(_inventory.get_node_or_null("Root/EquipmentPanel"), "колонка A")
	assert_not_null(_inventory.get_node_or_null("Root/ItemsPanel"), "колонка B")
	assert_not_null(_inventory.get_node_or_null("Root/DetailPanel"), "колонка D")
	assert_not_null(_inventory.get_node_or_null("Root/StatsPanel"), "колонка C")

	assert_eq(_inventory.get_equipment_data().size(), 6, "6 слотов экипировки")
	assert_eq(_inventory.get_stat_data().size(), 4, "4 характеристики")
	assert_eq(
		_inventory.get_reputation_data().size(),
		FactionManager.get_faction_ids().size(),
		"репутация по всем фракциям из FactionManager"
	)
	assert_eq(_inventory.get_stat_data()[0]["stat_id"], &"strength")

	var grid: Array[Dictionary] = _inventory.get_grid_data()
	assert_eq(grid.size(), 24)
	for index: int in grid.size():
		assert_true(bool(grid[index]["empty"]), "ячейка %d пуста до выдачи предметов" % index)
	assert_eq(_inventory.get_detail_data()["empty"], true, "описание пустой ячейки")


# ------------------------------------------------------------------------------
# Требования: «НЕТ · ещё N» / «ЕСТЬ» (DESIGN §6.2, AC-08.2)
# ------------------------------------------------------------------------------

func test_requirements_switch_from_missing_to_met() -> void:
	_add_item(&"two_handed_axe")
	_add_item(&"light_dagger")

	var axe_index: int = _inventory.find_grid_index(&"two_handed_axe")
	assert_eq(axe_index, 0, "секира — первая ячейка")
	var axe_slot: InventoryItemSlot = _inventory.get_grid_slot(axe_index)
	assert_not_null(axe_slot)
	assert_eq(axe_slot.get_state_name(), "requirements", "требования не выполнены")
	assert_true(axe_slot.has_requirement_marker(), "красный «!» в ячейке")
	assert_eq(axe_slot.requirement_summary, "НЕТ · ещё 4", "сила 5 при требовании 9")

	_inventory.select_grid_index(axe_index)
	var detail: Dictionary = _inventory.get_detail_data()
	assert_eq(detail["item_id"], &"two_handed_axe")
	assert_eq(detail["met"], false)
	var requirements: Array = detail["requirements"]
	assert_eq(requirements.size(), 1, "у секиры одно требование")
	assert_eq(requirements[0]["stat_id"], &"strength")
	assert_eq(requirements[0]["required"], 9)
	assert_eq(requirements[0]["current"], 5)
	assert_eq(requirements[0]["tag"], "НЕТ · ещё 4", "требование показано текстом")

	# Поднимаем силу до 9 (как это сделал бы учитель) — тег меняется на «ЕСТЬ 9».
	var stats: Dictionary = GameState.get_stats()
	stats[&"strength"] = 9
	GameState.restore_progression(stats, GameState.learning_points, GameState.level, GameState.xp)
	_inventory.refresh()

	axe_slot = _inventory.get_grid_slot(axe_index)
	assert_false(axe_slot.has_requirement_marker(), "требования выполнены")
	assert_eq(axe_slot.requirement_summary, "ЕСТЬ")
	detail = _inventory.get_detail_data()
	assert_eq(detail["met"], true)
	assert_eq(detail["requirements"][0]["tag"], "ЕСТЬ 9")
	assert_true(str(detail["requirements"][0]["tag"]).begins_with("ЕСТЬ"))

	# Кинжал по-прежнему требует ловкость 8 (стартовая 5).
	var dagger_index: int = _inventory.find_grid_index(&"light_dagger")
	var dagger_slot: InventoryItemSlot = _inventory.get_grid_slot(dagger_index)
	assert_eq(dagger_slot.requirement_summary, "НЕТ · ещё 3")
	_inventory.select_grid_index(dagger_index)
	assert_eq(_inventory.get_detail_data()["requirements"][0]["tag"], "НЕТ · ещё 3")


func test_item_without_requirements_is_available() -> void:
	_add_item(&"one_handed_sword")
	var sword_index: int = _inventory.find_grid_index(&"one_handed_sword")
	_inventory.select_grid_index(sword_index)
	var detail: Dictionary = _inventory.get_detail_data()
	assert_eq(detail["met"], true)
	assert_eq(detail["requirements"].size(), 0, "у меча нет требований")
	assert_eq(detail["requirement_summary"], "")


# ------------------------------------------------------------------------------
# Состояния ячеек (DESIGN §6.2)
# ------------------------------------------------------------------------------

func test_all_six_cell_states_are_representable() -> void:
	_add_item(&"one_handed_sword")
	_add_item(&"two_handed_axe")
	_add_item(&"sealed_relic")

	# Обычный: меч не выбран, но надет (маркер — отдельный флаг).
	_inventory.select_grid_index(23)
	var sword_index: int = _inventory.find_grid_index(&"one_handed_sword")
	var sword_slot: InventoryItemSlot = _inventory.get_grid_slot(sword_index)
	assert_eq(sword_slot.get_state_name(), "normal")
	assert_true(sword_slot.has_equipped_marker(), "надет")

	# Выбранный.
	_inventory.select_grid_index(sword_index)
	assert_eq(sword_slot.get_state_name(), "selected")
	assert_true(sword_slot.is_selected())

	# Требования не выполнены + выбран (золотая рамка поверх «!»).
	var axe_index: int = _inventory.find_grid_index(&"two_handed_axe")
	_inventory.select_grid_index(axe_index)
	var axe_slot: InventoryItemSlot = _inventory.get_grid_slot(axe_index)
	assert_eq(axe_slot.get_state_name(), "requirements")
	assert_true(axe_slot.is_selected(), "выбор сохраняется и на проблемной ячейке")
	assert_true(axe_slot.has_requirement_marker())

	# Недоступно (замок): способность не открыта.
	var relic_index: int = _inventory.find_grid_index(&"sealed_relic")
	var relic_slot: InventoryItemSlot = _inventory.get_grid_slot(relic_index)
	assert_eq(relic_slot.get_state_name(), "unavailable")
	assert_true(relic_slot.has_lock_marker())
	assert_false(relic_slot.has_requirement_marker())
	_inventory.select_grid_index(relic_index)
	var relic_detail: Dictionary = _inventory.get_detail_data()
	assert_eq(relic_detail["unavailable"], true)
	assert_true(str(relic_detail["unavailable_reason"]).contains("НЕ ОТКРЫТА"))

	# Пустая.
	var empty_slot: InventoryItemSlot = _inventory.get_grid_slot(23)
	assert_true(empty_slot.is_empty())
	assert_eq(empty_slot.get_state_name(), "empty")


func test_duplicate_items_are_stacked_and_counter_is_shown() -> void:
	_add_item(&"healing_herb")
	_add_item(&"healing_herb")
	_add_item(&"ash_shard")
	var grid: Array[Dictionary] = _inventory.get_grid_data()
	assert_eq(grid[0]["item_id"], &"healing_herb")
	assert_eq(grid[0]["count"], 2, "две травы складываются в одну ячейку")
	assert_eq(grid[1]["item_id"], &"ash_shard")
	assert_eq(grid[2]["empty"], true)
	var count_label := _inventory.get_node_or_null("Root/ItemsCount") as Label
	assert_not_null(count_label)
	assert_eq(count_label.text, "2/24", "счётчик занятых ячеек")


# ------------------------------------------------------------------------------
# Экипировка: золотой маркер надетого (DESIGN §6.2)
# ------------------------------------------------------------------------------

func test_equipped_marker_is_gold_on_grid_and_equipment_slot() -> void:
	_add_item(&"one_handed_sword")
	var sword_index: int = _inventory.find_grid_index(&"one_handed_sword")
	var sword_slot: InventoryItemSlot = _inventory.get_grid_slot(sword_index)
	assert_true(sword_slot.has_equipped_marker())
	assert_eq(sword_slot.get_equipped_marker_color(), UITokens.GOLD, "маркер золотой")

	var equipment: Array[Dictionary] = _inventory.get_equipment_data()
	var weapon_row: Dictionary = _find_row(equipment, "slot_id", &"weapon")
	assert_eq(weapon_row["item_id"], &"one_handed_sword")
	assert_false(bool(weapon_row["empty"]))

	var weapon_slot: InventoryItemSlot = _inventory.get_equipment_slot(&"weapon")
	assert_not_null(weapon_slot)
	assert_true(weapon_slot.has_equipped_marker())
	assert_eq(weapon_slot.get_equipped_marker_color(), UITokens.GOLD)

	# Броня/кольца — отдельные слоты; маркер обязан появиться и там.
	_add_item(&"leather_armor")
	_inventory.set_equipped_item(&"armor", &"leather_armor")
	var armor_row: Dictionary = _find_row(_inventory.get_equipment_data(), "slot_id", &"armor")
	assert_eq(armor_row["item_id"], &"leather_armor")
	var armor_index: int = _inventory.find_grid_index(&"leather_armor")
	assert_true(
		_inventory.get_grid_slot(armor_index).has_equipped_marker(),
		"надетый предмет в сетке помечен золотым квадратом"
	)
	assert_eq(_inventory.get_equipment_summary()["armor"], 5, "броня из данных каталога")


# ------------------------------------------------------------------------------
# «+» всегда отключена с причиной и ценой шага (AC-08.2)
# ------------------------------------------------------------------------------

func test_plus_buttons_are_disabled_with_teacher_reason_and_cost() -> void:
	var rows: Array[Dictionary] = _inventory.get_stat_data()
	assert_eq(rows.size(), 4)
	for row: Dictionary in rows:
		var stat_id: StringName = StringName(row["stat_id"])
		assert_true(bool(row["disabled"]), "%s: «+» отключена" % stat_id)
		assert_true(
			str(row["reason"]).to_lower().contains("учител"),
			"%s: причина «повышайте у учителя»" % stat_id
		)
		assert_gt(int(row["required_points"]), 0, "%s: показана цена шага" % stat_id)
		assert_eq(
			int(row["required_points"]),
			GameState.get_training_cost(stat_id),
			"%s: цена не дублируется, а читается из прогрессии" % stat_id
		)

	var ui_rows: Array[Control] = _inventory.get_stat_rows()
	assert_eq(ui_rows.size(), 4)
	for control: Control in ui_rows:
		var row: Variant = control
		assert_true(bool(row.is_plus_disabled()), "UI-строка: «+» отключена")
		assert_true(
			str(row.get_disabled_reason()).to_lower().contains("учител"),
			"UI-строка: причина доступна текстом"
		)
	assert_true(
		_inventory.get_training_note().to_lower().contains("учител"),
		"постоянная подпись «Повышайте у учителя»"
	)


# ------------------------------------------------------------------------------
# Репутация: −/+/0, ноль посередине, знак+число (AC-06.x, DESIGN §9.1)
# ------------------------------------------------------------------------------

func test_reputation_rows_show_sign_and_zero_center() -> void:
	FactionManager.set_reputation(&"ash", 2)
	FactionManager.set_reputation(&"free", -1)
	FactionManager.set_reputation(&"order", 0)
	_inventory.refresh()

	var rows: Array[Dictionary] = _inventory.get_reputation_data()
	assert_eq(rows.size(), 3)

	var ash: Dictionary = _find_row(rows, "faction_id", &"ash")
	assert_eq(ash["value_text"], "+2", "положительная репутация со знаком +")
	assert_eq(ash["side"], "positive")
	assert_eq(float(ash["zero_ratio"]), 0.5, "ноль посередине шкалы")
	assert_eq(ash["value"], FactionManager.get_reputation(&"ash"))

	var free: Dictionary = _find_row(rows, "faction_id", &"free")
	assert_eq(free["value_text"], "-1", "отрицательная репутация со знаком −")
	assert_eq(free["side"], "negative")

	var order: Dictionary = _find_row(rows, "faction_id", &"order")
	assert_eq(order["value_text"], "0", "нулевая репутация — «0», не пусто")
	assert_eq(order["side"], "zero")
	assert_eq(order["fill_ratio"], 0.0)

	var ui_rows: Array[Control] = _inventory.get_reputation_rows()
	assert_eq(ui_rows.size(), 3)
	var texts: Array[String] = []
	for control: Control in ui_rows:
		var row: Variant = control
		texts.append(str(row.get_value_text()))
		assert_eq(float(row.get_zero_ratio()), 0.5, "нулевая отметка посередине")
	assert_true(texts.has("+2"))
	assert_true(texts.has("-1"))
	assert_true(texts.has("0"))


# ------------------------------------------------------------------------------
# Открытие/закрытие только клавиатурой и геймпадом (a11y §9.2)
# ------------------------------------------------------------------------------

func test_open_and_close_with_keyboard_and_gamepad() -> void:
	assert_true(InputMap.has_action(&"inventory"), "действие InputMap inventory")
	assert_true(InputMap.has_action(&"ui_cancel"), "действие InputMap ui_cancel")
	assert_ne(
		AshenKbd.glyph_for_action(&"inventory", AshenKbd.DEVICE_KEYBOARD),
		"?",
		"у действия есть клавиша"
	)
	assert_ne(
		AshenKbd.glyph_for_action(&"inventory", AshenKbd.DEVICE_XBOX),
		"?",
		"у действия есть кнопка Xbox"
	)
	assert_ne(
		AshenKbd.glyph_for_action(&"inventory", AshenKbd.DEVICE_PLAYSTATION),
		"?",
		"у действия есть кнопка PlayStation"
	)

	_inventory.close()
	_inventory._input(_key_event(KEY_I))
	assert_true(_inventory.is_open(), "I открывает инвентарь")

	_inventory._input(_key_event(KEY_ESCAPE))
	assert_false(_inventory.is_open(), "Esc закрывает инвентарь")

	_inventory._input(_joypad_event(6))  # START
	assert_true(_inventory.is_open(), "START геймпада открывает инвентарь")

	_inventory._input(_joypad_event(1))  # B
	assert_false(_inventory.is_open(), "B геймпада закрывает инвентарь")


func test_open_is_idempotent_and_cancel_does_nothing_when_closed() -> void:
	assert_false(_inventory.is_open())
	_inventory._input(_joypad_event(1))
	assert_false(_inventory.is_open(), "закрытый экран не реагирует на B")
	assert_true(_inventory.open(), "open() возвращает true")
	assert_false(_inventory.open(), "повторный open() не перезапускает экран")
	_inventory.close()
	assert_false(_inventory.is_open())


# ------------------------------------------------------------------------------
# Хелперы
# ------------------------------------------------------------------------------

func _add_item(item_id: StringName) -> void:
	GameState.add_item(item_id)
	_inventory.refresh()


func _find_row(rows: Array, key: String, value: Variant) -> Dictionary:
	for row: Variant in rows:
		if row is Dictionary and (row as Dictionary).get(key) == value:
			return row as Dictionary
	return {}


func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	return event


func _joypad_event(button_index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = true
	return event
