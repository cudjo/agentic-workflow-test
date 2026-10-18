extends GutTest
## T-24 — недостающие макеты в Godot: ремап, журнал, фракции, выбор фракции.
##
## Проверяем acceptance T-24 на живых сценах:
##   * `ui/remap/Remap.tscn` — действия из InputMap, захват, сохранение через
##     InputManager (`user://settings.cfg`), сброс, подсветка дублей (AC-01.3);
##   * `ui/journal/Journal.tscn` — активные/завершённые квесты и события,
##     вкладки Tab/LB/RB, пустые состояния;
##   * `ui/factions/Factions.tscn` — репутация, статус доступа, причина
##     ограничения и альтернатива (AC-06.2, EC-11);
##   * `ui/factions/FactionChoice.tscn` — открывается по сюжетному сигналу и
##     фиксирует выбор через `FactionManager.choose_faction` (US-06).
##
## Ремап пишет в реальный `user://settings.cfg`: исходные привязки снимаются в
## `before_all` и восстанавливаются после каждого изменяющего теста.

const REMAP_SCENE: PackedScene = preload("res://ui/remap/Remap.tscn")
const JOURNAL_SCENE: PackedScene = preload("res://ui/journal/Journal.tscn")
const FACTIONS_SCENE: PackedScene = preload("res://ui/factions/Factions.tscn")
const CHOICE_SCENE: PackedScene = preload("res://ui/factions/FactionChoice.tscn")

const QUEST_ACTIVE: StringName = &"quest_clear_swamp"
const QUEST_COMPLETED: StringName = &"quest_guard_patrol"
const QUEST_ACTIVE_TITLE: String = "Очистить болото"
const QUEST_COMPLETED_TITLE: String = "Патруль у ворот"
const FACTION_ORDER: StringName = &"order"
const FACTION_FREE: StringName = &"free"
const FACTION_ASH: StringName = &"ash"
const ORDER_NAME: String = "Орден Пепла"
const FREE_NAME: String = "Вольные Марки"

var _saved_events: Dictionary = {}
var _saved_journal: Dictionary = {}
var _saved_factions: Dictionary = {}
var _saved_chosen: StringName = &""
var _saved_language: String = "ru"
var _saved_paused: bool = false
var _remap_touched: bool = false


func before_all() -> void:
	for action: StringName in InputMap.get_actions():
		var events: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.duplicate() as InputEvent)
		_saved_events[String(action)] = events


func after_all() -> void:
	_restore_events()


func before_each() -> void:
	_saved_paused = get_tree().paused
	get_tree().paused = false

	_saved_journal = Journal.get_state()
	Journal.reset_state()

	_saved_factions = GameState.get_all_faction_reputation()
	_saved_chosen = GameState.chosen_faction
	GameState.reset_factions()

	_saved_language = Config.language
	Config.language = "ru"

	_remap_touched = false


func after_each() -> void:
	Journal.restore_state(_saved_journal)
	GameState.restore_factions(_saved_factions, _saved_chosen)
	Config.language = _saved_language
	if _remap_touched:
		_restore_events()
		_remap_touched = false
	get_tree().paused = _saved_paused


# ------------------------------------------------------------------------------
# Помощники
# ------------------------------------------------------------------------------

func _spawn_remap() -> RemapScreen:
	var screen := REMAP_SCENE.instantiate() as RemapScreen
	screen.pause_on_open = false
	add_child_autofree(screen)
	return screen


func _spawn_journal() -> JournalScreen:
	var screen := JOURNAL_SCENE.instantiate() as JournalScreen
	screen.pause_on_open = false
	add_child_autofree(screen)
	return screen


func _spawn_factions() -> FactionsScreen:
	var screen := FACTIONS_SCENE.instantiate() as FactionsScreen
	screen.pause_on_open = false
	add_child_autofree(screen)
	return screen


func _spawn_choice() -> FactionChoice:
	var screen := CHOICE_SCENE.instantiate() as FactionChoice
	screen.pause_on_open = false
	add_child_autofree(screen)
	return screen


func _seed_journal() -> void:
	Journal.start_quest(QUEST_ACTIVE)
	Journal.start_quest(QUEST_COMPLETED)
	Journal.complete_quest(QUEST_COMPLETED)
	Journal.record_event(&"zone_entered", "Деревня-бастион")
	Journal.record_event(&"boss_defeated", "Палач пал")


func _key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _tab_event() -> InputEventKey:
	return _key_event(KEY_TAB)


func _joy_button(index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _resolved_key_codes(action: StringName) -> Array[int]:
	var codes: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			codes.append(key.physical_keycode if key.physical_keycode != 0 else key.keycode)
	return codes


func _restore_events() -> void:
	for raw_action: Variant in _saved_events.keys():
		var action := StringName(str(raw_action))
		var events: Array[InputEvent] = []
		for saved: Variant in _saved_events[raw_action]:
			if saved is InputEvent:
				events.append((saved as InputEvent).duplicate() as InputEvent)
		InputManager.remap_action(action, events)


func _find_faction_view(view: Dictionary, faction_id: StringName) -> Dictionary:
	for entry: Dictionary in view.get("factions", []):
		if StringName(entry.get("id", &"")) == faction_id:
			return entry
	return {}


func _find_row(rows: Array[AshenMenuItem], faction_id: StringName) -> AshenMenuItem:
	for row: AshenMenuItem in rows:
		if StringName(row.get_meta("faction_id", &"")) == faction_id:
			return row
	return null


# ------------------------------------------------------------------------------
# Ремап (AC-01.3)
# ------------------------------------------------------------------------------

func test_remap_scene_lists_gameplay_actions_from_inputmap() -> void:
	var screen := _spawn_remap()
	assert_true(screen is CanvasLayer, "ремап — CanvasLayer")
	assert_eq(screen.layer, 20, "слой UI 20")
	assert_false(screen.visible, "до открытия скрыт")

	var rows: Array[Dictionary] = screen.get_action_rows()
	assert_gt(rows.size(), 9, "список действий непустой")
	var actions: Array[StringName] = screen.get_actions()
	assert_true(actions.has(&"move_left"), "move_left из InputMap")
	assert_true(actions.has(&"jump"), "jump из InputMap")
	assert_true(actions.has(&"attack"), "attack из InputMap")
	assert_true(actions.has(&"interact"), "interact из InputMap")
	for action: StringName in actions:
		assert_false(String(action).begins_with("ui_"), "ui_* не ремапятся: %s" % action)

	var jump_row: Dictionary = {}
	for row: Dictionary in rows:
		if StringName(row.get("action", &"")) == &"jump":
			jump_row = row
			break
	assert_false(jump_row.is_empty(), "строка jump есть")
	assert_string_contains(str(jump_row.get("bindings", "")), "ПРОБЕЛ", "клавиша jump видна")
	assert_string_contains(str(jump_row.get("bindings", "")), "A", "кнопка геймпада видна")

	screen.open()
	assert_true(screen.visible, "open() показывает экран")
	assert_false(screen.is_capturing(), "захват не начат сам по себе")
	screen.close()
	assert_false(screen.visible, "close() скрывает экран")


func test_remap_assigns_event_and_persists_to_settings() -> void:
	var screen := _spawn_remap()
	_remap_touched = true
	var original_pad: int = _find_pad_button(&"jump")

	var event := _key_event(KEY_F)
	assert_true(screen.assign_event(&"jump", event), "новое событие принято")
	assert_true(_resolved_key_codes(&"jump").has(KEY_F), "InputMap обновлён: F")
	assert_eq(_find_pad_button(&"jump"), original_pad, "кнопка геймпада сохранена")
	assert_string_contains(screen.get_status_text(), "СОХРАНЕНО", "статус сохранения")

	var config := ConfigFile.new()
	assert_eq(config.load("user://settings.cfg"), OK, "settings.cfg читается")
	var raw: Variant = config.get_value("input", "jump", "")
	assert_true(raw is String and not str(raw).is_empty(), "секция input/jump записана")
	var parsed: Variant = JSON.parse_string(str(raw))
	assert_true(parsed is Array, "привязки jump — JSON-массив")
	var found: bool = false
	for entry: Variant in parsed:
		if entry is Dictionary and int((entry as Dictionary).get("keycode", 0)) == KEY_F:
			found = true
	assert_true(found, "KEY_F сохранён в user://settings.cfg")


func test_remap_duplicate_event_is_flagged_with_text() -> void:
	var screen := _spawn_remap()
	_remap_touched = true
	var move_left_events: Array[InputEvent] = InputMap.action_get_events(&"move_left")
	var duplicate_key: InputEventKey = null
	for event: InputEvent in move_left_events:
		if event is InputEventKey:
			duplicate_key = (event as InputEventKey).duplicate() as InputEventKey
			break
	assert_not_null(duplicate_key, "у move_left есть клавиша")

	assert_true(screen.assign_event(&"jump", duplicate_key), "дубль назначен (с подсветкой)")
	var conflicts: Dictionary = screen.get_conflicts()
	assert_gt(conflicts.size(), 0, "конфликт найден")

	var jump_row: Dictionary = {}
	for row: Dictionary in screen.get_action_rows():
		if StringName(row.get("action", &"")) == &"jump":
			jump_row = row
			break
	assert_true(bool(jump_row.get("conflict", false)), "строка jump подсвечена")
	var conflict_names: Array = jump_row.get("conflict_actions", [])
	assert_true(conflict_names.has("ВЛЕВО"), "видно конфликтующее действие")
	assert_string_contains(screen.get_status_text(), "ДУБЛЬ", "статус сообщает о дубле")
	var row_node: AshenMenuItem = screen.get_row(&"jump")
	assert_not_null(row_node)
	assert_string_contains(row_node.tooltip_text, "ВЛЕВО", "tooltip перечисляет дубль")


func test_remap_reset_restores_project_defaults() -> void:
	var screen := _spawn_remap()
	_remap_touched = true
	var original_codes: Array[int] = _resolved_key_codes(&"jump")
	var event := _key_event(KEY_F)
	assert_true(screen.assign_event(&"jump", event))

	screen.reset_bindings()
	assert_eq(_resolved_key_codes(&"jump"), original_codes, "сброс вернул дефолты")
	assert_string_contains(screen.get_status_text(), "СБРОШЕНО", "статус сброса")


func test_remap_capture_takes_next_key_and_cancel_keeps_binding() -> void:
	var screen := _spawn_remap()
	_remap_touched = true
	var original_codes: Array[int] = _resolved_key_codes(&"jump")

	screen.open()
	screen.start_capture(&"jump")
	assert_true(screen.is_capturing(), "захват начат")
	var capturing_row: Dictionary = {}
	for row: Dictionary in screen.get_action_rows():
		if StringName(row.get("action", &"")) == &"jump":
			capturing_row = row
			break
	assert_true(bool(capturing_row.get("capturing", false)), "строка показывает ожидание")

	var escape := _key_event(KEY_ESCAPE)
	screen._input(escape)
	assert_false(screen.is_capturing(), "Esc отменяет захват")
	assert_eq(_resolved_key_codes(&"jump"), original_codes, "отмена не меняет привязку")

	screen.start_capture(&"jump")
	var new_key := _key_event(KEY_G)
	screen._input(new_key)
	assert_false(screen.is_capturing(), "захват завершён")
	assert_true(_resolved_key_codes(&"jump").has(KEY_G), "следующая клавиша назначена")


# ------------------------------------------------------------------------------
# Журнал (Journal.gd → вкладка «Журнал»)
# ------------------------------------------------------------------------------

func test_journal_shows_active_and_completed_quests() -> void:
	_seed_journal()
	var screen := _spawn_journal()
	screen.open()
	var view: Dictionary = screen.get_view_data()

	assert_eq(view.get("active", []), [QUEST_ACTIVE_TITLE], "активный квест показан")
	assert_eq(view.get("completed", []), [QUEST_COMPLETED_TITLE], "завершённый квест показан")
	assert_eq(screen.get_tab_index(), JournalScreen.TAB_QUESTS, "открыта вкладка квестов")

	var rows: Array[AshenMenuItem] = screen.get_list_rows()
	assert_eq(rows.size(), 2, "две строки квестов")
	assert_eq(rows[0].prefix_tag, "АКТИВЕН ", "статус активного словом")
	assert_eq(rows[1].prefix_tag, "ЗАВЕРШЁН ", "статус завершённого словом")
	assert_string_contains(screen.get_detail_status_label().text, "АКТИВЕН", "детали активного")
	assert_string_contains(screen.get_detail_text_label().text, "Орден платит", "описание квеста")


func test_journal_events_tab_lists_recorded_events() -> void:
	_seed_journal()
	var screen := _spawn_journal()
	screen.open(JournalScreen.TAB_EVENTS)
	var view: Dictionary = screen.get_view_data()

	assert_eq(screen.get_tab_index(), JournalScreen.TAB_EVENTS, "открыта вкладка событий")
	assert_eq(view.get("events", []), ["Деревня-бастион", "Палач пал"], "события показаны")
	assert_eq(screen.get_list_rows().size(), 2, "по строке на событие")
	assert_eq(screen.get_list_rows()[0].prefix_tag, "01 ", "события нумеруются")
	assert_string_contains(screen.get_detail_status_label().text, "СОБЫТИЕ", "тип записи словом")
	assert_eq(screen.get_detail_text_label().text, "Деревня-бастион", "текст события в деталях")


func test_journal_tabs_navigate_with_tab_and_lb_rb() -> void:
	_seed_journal()
	var screen := _spawn_journal()
	screen.open()
	var bar: AshenTabBar = screen.get_tab_bar()
	assert_eq(bar.get_tab_count(), 2, "две вкладки")

	assert_true(bar.handle_tab_input(_tab_event()), "Tab переключает вкладку")
	assert_eq(screen.get_tab_index(), JournalScreen.TAB_EVENTS, "Tab → события")
	assert_true(bar.handle_tab_input(_joy_button(AshenTabBar.JOYPAD_PREV_BUTTON)), "LB переключает")
	assert_eq(screen.get_tab_index(), JournalScreen.TAB_QUESTS, "LB → квесты")
	assert_true(bar.handle_tab_input(_joy_button(AshenTabBar.JOYPAD_NEXT_BUTTON)), "RB переключает")
	assert_eq(screen.get_tab_index(), JournalScreen.TAB_EVENTS, "RB → события")


func test_journal_refreshes_when_journal_changes() -> void:
	_seed_journal()
	var screen := _spawn_journal()
	screen.open()
	assert_eq((screen.get_view_data().get("active", []) as Array).size(), 1)

	Journal.start_quest(&"quest_free_smuggle")
	Journal.record_event(&"quest_started", "Новый заказ")
	var view: Dictionary = screen.get_view_data()
	assert_eq((view.get("active", []) as Array).size(), 2, "новый квест появился без переоткрытия")
	assert_eq((view.get("events", []) as Array).size(), 3, "событие появилось без переоткрытия")


func test_journal_empty_state_is_explicit() -> void:
	var screen := _spawn_journal()
	screen.open()
	var view: Dictionary = screen.get_view_data()
	assert_true(bool(view.get("empty", false)), "пустой журнал помечен")
	assert_eq(screen.get_list_rows().size(), 0, "строк нет")
	assert_eq(screen.get_detail_text_label().text, tr(JournalScreen.EMPTY_JOURNAL), "пустое состояние текстом")
	assert_string_contains(
		screen.get_detail_text_label().text,
		"ЖУРНАЛ ПУСТ",
		"пустое состояние не только цветом"
	)


# ------------------------------------------------------------------------------
# Фракции (AC-06.2)
# ------------------------------------------------------------------------------

func test_factions_list_shows_reputation_and_access_status() -> void:
	FactionManager.set_reputation(FACTION_ORDER, 0)
	FactionManager.set_reputation(FACTION_FREE, 0)
	FactionManager.set_reputation(FACTION_ASH, 5)
	var screen := _spawn_factions()
	screen.open()
	var view: Dictionary = screen.get_view_data()
	assert_eq((view.get("factions", []) as Array).size(), 3, "три фракции")

	var order: Dictionary = _find_faction_view(view, FACTION_ORDER)
	assert_eq(int(order.get("reputation", -1)), 0, "репутация Ордена")
	assert_eq(int(order.get("threshold", -1)), 10, "порог из данных")
	assert_false(bool(order.get("allowed", true)), "0 < 10 — доступ закрыт")

	var ash: Dictionary = _find_faction_view(view, FACTION_ASH)
	assert_true(bool(ash.get("allowed", false)), "5 ≥ 5 — доступ открыт")

	var rows: Array[AshenMenuItem] = screen.get_list_rows()
	var order_row: AshenMenuItem = _find_row(rows, FACTION_ORDER)
	assert_not_null(order_row, "строка Ордена")
	assert_eq(order_row.prefix_tag, "ЗАКР ", "статус закрыт словом")
	assert_string_contains(order_row.text, "Орден Пепла +0", "имя и знак репутации в списке")
	var ash_row: AshenMenuItem = _find_row(rows, FACTION_ASH)
	assert_not_null(ash_row)
	assert_eq(ash_row.prefix_tag, "ОТКР ", "статус открыт словом")


func test_factions_detail_explains_denial_and_alternative() -> void:
	FactionManager.set_reputation(FACTION_ORDER, -5)
	var screen := _spawn_factions()
	screen.open(FACTION_ORDER)
	var detail: String = screen.get_detail_text()
	assert_string_contains(detail, "ЗАКРЫТ", "отказ виден словом")
	assert_string_contains(detail, "ПОРОГ", "порог показан")
	assert_string_contains(detail, "Орден Пепла", "причина содержит фракцию")
	assert_string_contains(detail, "-5", "причина содержит репутацию")
	assert_string_contains(detail, "10", "причина содержит порог")
	assert_string_contains(detail, "АЛЬТЕРНАТИВА", "EC-11: альтернатива показана")
	assert_string_contains(detail, FREE_NAME, "альтернативная фракция названа")


func test_factions_access_tab_lists_territory_trader_and_quests() -> void:
	FactionManager.set_reputation(FACTION_ORDER, -5)
	var screen := _spawn_factions()
	screen.open(FACTION_ORDER)
	screen.set_tab(FactionsScreen.TAB_ACCESS)
	assert_eq(screen.get_tab_index(), FactionsScreen.TAB_ACCESS, "вкладка доступа")
	var detail: String = screen.get_detail_text()
	assert_string_contains(detail, "ТЕРРИТОРИЯ", "территория")
	assert_string_contains(detail, "ТОРГОВЕЦ", "торговец")
	assert_string_contains(detail, "КВЕСТЫ", "квесты")
	assert_string_contains(detail, "ЗАКРЫТ", "отказ с причиной")
	assert_string_contains(detail, "ПОРОГ", "объяснение ограничения")


func test_factions_tabs_navigate_with_tab_and_lb_rb() -> void:
	var screen := _spawn_factions()
	screen.open()
	var bar: AshenTabBar = screen.get_tab_bar()
	assert_true(bar.handle_tab_input(_tab_event()), "Tab переключает вкладку")
	assert_eq(screen.get_tab_index(), FactionsScreen.TAB_ACCESS, "Tab → доступ")
	assert_true(bar.handle_tab_input(_joy_button(AshenTabBar.JOYPAD_PREV_BUTTON)), "LB переключает")
	assert_eq(screen.get_tab_index(), FactionsScreen.TAB_REPUTATION, "LB → список")
	assert_true(bar.handle_tab_input(_joy_button(AshenTabBar.JOYPAD_NEXT_BUTTON)), "RB переключает")
	assert_eq(screen.get_tab_index(), FactionsScreen.TAB_ACCESS, "RB → доступ")


func test_factions_refresh_on_reputation_and_mark_choice() -> void:
	var screen := _spawn_factions()
	screen.open(FACTION_ORDER)
	FactionManager.set_reputation(FACTION_ORDER, 15)
	var view: Dictionary = screen.get_view_data()
	var order: Dictionary = _find_faction_view(view, FACTION_ORDER)
	assert_true(bool(order.get("allowed", false)), "порог пересёкся — доступ открыт")
	var row: AshenMenuItem = _find_row(screen.get_list_rows(), FACTION_ORDER)
	assert_not_null(row)
	assert_eq(row.prefix_tag, "ОТКР ", "список обновился по сигналу")

	assert_true(FactionManager.choose_faction(FACTION_ORDER), "выбор фракции")
	view = screen.get_view_data()
	order = _find_faction_view(view, FACTION_ORDER)
	assert_true(bool(order.get("chosen", false)), "маркер выбора в данных")
	row = _find_row(screen.get_list_rows(), FACTION_ORDER)
	assert_string_contains(row.text, "*", "маркер выбора в строке (не только цветом)")
	assert_string_contains(screen.get_detail_text(), "ВЫБРАНА", "детали сообщают о выборе")


# ------------------------------------------------------------------------------
# Выбор фракции (US-06)
# ------------------------------------------------------------------------------

func test_faction_choice_opens_from_story_signal() -> void:
	var screen := _spawn_choice()
	assert_false(screen.is_open(), "сначала скрыт")

	EventBus.faction_choice_requested.emit("Совет Бастиона ждёт присяги")
	assert_true(screen.is_open(), "сюжетный сигнал открывает экран")
	assert_string_contains(str(screen.get_view_data().get("reason", "")), "Совет", "причина показана")
	assert_false(get_tree().paused, "тесты не ставят игру на паузу")

	screen.close()
	assert_false(screen.is_open(), "закрывается")


func test_faction_choice_lists_factions_and_fixes_selection() -> void:
	var screen := _spawn_choice()
	watch_signals(screen)
	screen.open("Присяга")
	assert_eq(screen.get_list_rows().size(), 3, "три фракции в выборе")
	assert_eq(screen.get_view_data().get("chosen", &""), &"", "выбора ещё нет")

	screen.select_faction(FACTION_ORDER)
	assert_eq(
		FactionManager.get_selected_faction(),
		&"",
		"выбор не фиксируется до подтверждения"
	)

	assert_true(screen.confirm_choice(), "подтверждение принято")
	assert_eq(
		FactionManager.get_selected_faction(),
		FACTION_ORDER,
		"FactionManager.choose_faction зафиксировал выбор"
	)
	assert_eq(screen.get_last_choice(), FACTION_ORDER, "экран помнит выбор")
	assert_signal_emitted(screen, "choice_made", "сигнал выбора отправлен")
	assert_false(screen.is_open(), "после присяги экран закрыт")


func test_faction_choice_shows_existing_selection() -> void:
	assert_true(FactionManager.choose_faction(FACTION_ASH))
	var screen := _spawn_choice()
	screen.open()
	var view: Dictionary = screen.get_view_data()
	assert_eq(view.get("chosen"), FACTION_ASH, "текущий выбор виден")
	assert_eq(view.get("selected"), FACTION_ASH, "выбранная фракция — по умолчанию")
	var row: AshenMenuItem = _find_row(screen.get_list_rows(), FACTION_ASH)
	assert_not_null(row)
	assert_string_contains(row.text, "*", "маркер выбранной фракции")
	assert_string_contains(screen.get_detail_text(), "ВЫБРАНА", "детали сообщают о выборе")


func test_faction_choice_navigation_and_cancel() -> void:
	var screen := _spawn_choice()
	screen.open()
	var initial: StringName = screen.get_selected_faction()
	assert_eq(initial, FACTION_ASH, "первая фракция по стабильному порядку")

	screen._input(_action_event(&"ui_down"))
	assert_eq(screen.get_selected_faction(), FACTION_FREE, "↓ меняет выбранную фракцию")

	screen._input(_action_event(&"ui_cancel"))
	assert_false(screen.is_open(), "Esc закрывает без выбора")
	assert_eq(FactionManager.get_selected_faction(), &"", "выбор не сделан")


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _find_pad_button(action: StringName) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return (event as InputEventJoypadButton).button_index
	return -1
