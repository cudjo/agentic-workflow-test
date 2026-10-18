extends GutTest
## T-23 — костёр: диалог и сохранение (TASKS T-23; DESIGN §6.4/§8.5/§9;
## SPEC US-05, AC-05.1, Q3/EC-06, EC-14; макет `docs/mockups/campfire.html`).
##
## Проверяем acceptance на живой сцене `res://ui/campfire/Campfire.tscn`:
##   * реплика печатается 22 мс/символ, фокус по умолчанию — «Сохранить игру»;
##   * 3 карточки слота из `SaveManager.get_slot_metadata` (зона/уровень/время/
##     «Перезапись», пустой слот);
##   * сохранение подтверждается тостом ≤ 1 с, загрузка восстанавливает состояние
##     (AC-05.1);
##   * в бою пункт отключён с причиной и тостом (EC-06);
##   * ошибка диска — тост опасности с вариантами, прежний слот цел (EC-14);
##   * ответ с тегом `[Фракция±N]` применяет репутацию через FactionManager;
##   * управление только клавиатурой/геймпадом (фокус, Esc, ↑/↓).
##
## Слоты пишутся в отдельный `user://test_campfire_t23`; `SaveManager.saves_dir`
## переопределяется на время файла и восстанавливается в `after_all`.

const SCENE: PackedScene = preload("res://ui/campfire/Campfire.tscn")
const TEST_DIR: String = "user://test_campfire_t23"
const ZONE: StringName = &"zone_01_village"
const ZONE_NAME: String = "Деревня-бастион"
const OATH_EVENT: StringName = &"action_campfire_oath"
const OATH_FACTION: StringName = &"order"

var screen: Campfire
var bonfire: Bonfire

var _saves_dir: String = SaveManager.DEFAULT_SAVES_DIR
var _in_combat: bool = false
var _hp: float = 0.0
var _stamina: float = 0.0
var _currency: int = 0
var _inventory: Array[StringName] = []
var _abilities: Array[StringName] = []
var _active_slot: int = 0
var _factions: Dictionary = {}
var _chosen_faction: StringName = &""
var _stats: Dictionary = {}
var _learning_points: int = 0
var _level: int = 1
var _xp: int = 0
var _zone: StringName = &""
var _death_active: bool = false
var _corpse: Dictionary = {}
var _respawn: Dictionary = {}
var _no_flash: bool = false


func before_all() -> void:
	_saves_dir = SaveManager.saves_dir
	SaveManager.saves_dir = TEST_DIR


func after_all() -> void:
	SaveManager.saves_dir = _saves_dir
	_cleanup_dir()
	var parent: DirAccess = DirAccess.open(TEST_DIR.get_base_dir())
	if parent != null and parent.dir_exists(TEST_DIR.get_file()):
		parent.remove(TEST_DIR.get_file())


func before_each() -> void:
	_in_combat = GameState.in_combat
	_hp = GameState.hp
	_stamina = GameState.stamina
	_currency = GameState.currency
	_inventory = GameState.get_inventory()
	_abilities = GameState.get_abilities()
	_active_slot = GameState.active_slot
	_factions = GameState.get_all_faction_reputation()
	_chosen_faction = GameState.chosen_faction
	_stats = GameState.get_stats()
	_learning_points = GameState.learning_points
	_level = GameState.level
	_xp = GameState.xp
	_zone = GameState.current_zone_id
	_death_active = GameState.death_active
	_corpse = GameState.get_corpse_info()
	_respawn = {
		"bonfire": GameState.respawn_bonfire,
		"zone_id": GameState.respawn_zone_id,
		"position": GameState.respawn_position,
	}
	_no_flash = Config.no_flash

	GameState.set_in_combat(false)
	GameState.currency = 0
	GameState.clear_inventory()
	GameState.clear_abilities()
	GameState.active_slot = 0
	GameState.reset_factions()
	GameState.reset_progression()
	GameState.set_hp(GameState.hp_max)
	GameState.restore_death_state(false, false, &"", Vector2.ZERO, [], 0, false)
	GameState.restore_respawn_bonfire(&"", &"", Vector2.ZERO)
	GameState.current_zone_id = ZONE
	Config.no_flash = false

	_cleanup_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))

	screen = SCENE.instantiate() as Campfire
	add_child_autofree(screen)
	await wait_process_frames(1)

	bonfire = Bonfire.new()
	bonfire.name = "TestBonfire"
	bonfire.zone_id = ZONE
	add_child_autofree(bonfire)
	await wait_process_frames(1)


func after_each() -> void:
	Config.no_flash = _no_flash
	GameState.restore_progression(_stats, _learning_points, _level, _xp)
	GameState.stamina = _stamina
	GameState.restore_hp(_hp)
	GameState.currency = _currency
	GameState.restore_inventory(_inventory)
	GameState.restore_abilities(_abilities)
	GameState.active_slot = _active_slot
	GameState.restore_factions(_factions, _chosen_faction)
	GameState.restore_death_state(
		_death_active,
		bool(_corpse.get("active", false)),
		StringName(str(_corpse.get("zone_id", ""))),
		_corpse.get("position", Vector2.ZERO),
		_corpse.get("items", []),
		int(_corpse.get("currency", 0)),
		bool(_corpse.get("lost", false))
	)
	GameState.restore_respawn_bonfire(
		StringName(str(_respawn.get("bonfire", ""))),
		StringName(str(_respawn.get("zone_id", ""))),
		_respawn.get("position", Vector2.ZERO)
	)
	GameState.current_zone_id = _zone
	GameState.set_in_combat(_in_combat)
	_cleanup_dir()


# ------------------------------------------------------------------------------
# Сцена, слой, диалог и фокус
# ------------------------------------------------------------------------------

func test_scene_is_canvas_layer_20_with_overlay_40() -> void:
	assert_true(screen is CanvasLayer, "костёр — CanvasLayer")
	assert_eq(screen.layer, 20, "диалог на слое 20 (DESIGN §4.4)")
	assert_eq(screen.get_toast_layer().layer, 40, "тост поверх экранов — слой 40")
	assert_false(screen.is_open(), "до открытия диалог скрыт")
	assert_false(screen.visible)


func test_open_types_replica_at_22ms_and_focuses_save() -> void:
	screen.open(bonfire)

	var dialog: AshenDialog = screen.get_dialog()
	assert_true(screen.is_open())
	assert_true(screen.visible)
	assert_true(dialog.is_visible_in_tree(), "диалог реально виден, а не только открыт по флагу")
	assert_eq(dialog.get_display_name(), "Хранитель Огня")
	assert_eq(dialog.get_answer_count(), 4, "2×2 варианта макета")
	assert_eq(dialog.get_answer_item(0).text, "Сохранить игру")
	assert_true(dialog.is_typing(), "реплика печатается, а не появляется сразу")
	assert_eq(dialog.get_visible_characters(), 0)

	dialog.advance_typing(UITokens.TYPE_SPEED * 3.0)
	assert_eq(dialog.get_visible_characters(), 3, "1 символ / 22 мс")

	dialog.reveal_all()
	await wait_process_frames(1)
	assert_false(dialog.is_typing())
	assert_eq(
		get_viewport().gui_get_focus_owner(),
		dialog.get_answer_item(0),
		"фокус по умолчанию — «Сохранить игру»"
	)


func test_no_flash_shows_text_instantly() -> void:
	Config.no_flash = true
	screen.open(bonfire)

	var dialog: AshenDialog = screen.get_dialog()
	assert_false(dialog.is_typing(), "«Без мигания» отключает печать (DESIGN §9.3)")
	assert_eq(dialog.get_visible_characters(), dialog.get_total_characters())
	await wait_process_frames(1)
	assert_eq(get_viewport().gui_get_focus_owner(), dialog.get_answer_item(0))


# ------------------------------------------------------------------------------
# Слоты
# ------------------------------------------------------------------------------

func test_slots_show_three_cards_with_metadata() -> void:
	SaveManager.save_slot(3, {
		"zone_id": "zone_03_mountains",
		"zone_name": "Горный перевал",
		"level": 5,
		"play_time": 13200.0,
	})
	SaveManager.save_slot(1, {
		"zone_id": "zone_02_swamp",
		"zone_name": "Болото",
		"level": 7,
		"play_time": 22320.0,
	})
	GameState.active_slot = 1

	await _open()
	await _choose(0)

	assert_eq(screen.get_state_name(), "slots")
	assert_true(screen.get_slots_panel().visible)
	assert_true(screen.get_slots_panel().is_visible_in_tree(), "панель слотов реально видна")
	assert_eq(screen.get_slot_card_count(), 3)

	var first: Dictionary = screen.get_slot_card_data(0)
	assert_eq(first["title"], "Болото", "занятый слот показывает зону")
	assert_eq(first["details"], "УР7 · 6ч 12м", "уровень и время")
	assert_true(first["overwrite"], "занятый слот помечен «Перезапись»")
	assert_false(first["empty"])

	var second: Dictionary = screen.get_slot_card_data(1)
	assert_true(second["empty"], "пустой слот")
	assert_eq(second["title"], "— Пусто —")
	assert_false(second["overwrite"])

	var third: Dictionary = screen.get_slot_card_data(2)
	assert_eq(third["title"], "Горный перевал")
	assert_eq(third["details"], "УР5 · 3ч 40м")

	await wait_process_frames(1)
	assert_eq(
		get_viewport().gui_get_focus_owner(),
		screen.get_slot_card(0),
		"фокус на активном слоте"
	)


func test_save_shows_success_toast_under_one_second() -> void:
	await _open()
	await _choose(0)
	screen.select_slot(1)
	await wait_process_frames(1)

	assert_eq(screen.get_state_name(), "saved")
	assert_true(SaveManager.has_slot(1))

	var toast: AshenToast = screen.get_toast()
	assert_true(toast.visible)
	assert_eq(toast.get_kind(), AshenToast.Kind.SUCCESS, "успех — галочка, не только цвет")
	assert_eq(toast.get_message(), "СОХРАНЕНО · СЛОТ 1")
	assert_true(toast.duration <= 1.0, "подтверждение ≤ 1 с (AC-05.1)")

	await wait_seconds(1.1)
	assert_false(toast.visible, "тост успеха скрывается за ≤ 1 с")


func test_save_and_load_restores_state_ac05_1() -> void:
	GameState.currency = 120
	GameState.add_item(&"rusty_sword")
	GameState.add_ability(&"dash")
	GameState.set_faction_reputation(OATH_FACTION, 12)
	GameState.level = 4
	GameState.xp = 100
	GameState.set_hp(42.0)

	await _open()
	await _choose(0)
	screen.select_slot(1)
	await wait_process_frames(1)
	assert_eq(screen.get_state_name(), "saved")

	var metadata: Dictionary = SaveManager.get_slot_metadata(1)
	assert_true(metadata["valid"])
	assert_eq(metadata["zone_id"], "zone_01_village", "костёр передал зону в сейв")
	assert_eq(metadata["zone_name"], ZONE_NAME)
	assert_eq(metadata["level"], 4)

	GameState.currency = 0
	GameState.clear_inventory()
	GameState.clear_abilities()
	GameState.set_faction_reputation(OATH_FACTION, 0)
	GameState.level = 1
	GameState.xp = 0
	GameState.set_hp(GameState.hp_max)

	assert_true(SaveManager.load_slot(1), "слот читается и применяется")
	assert_eq(GameState.currency, 120)
	assert_true(GameState.get_inventory().has(&"rusty_sword"))
	assert_true(GameState.has_ability(&"dash"))
	assert_eq(GameState.get_faction_reputation(OATH_FACTION), 12)
	assert_eq(GameState.level, 4)
	assert_eq(GameState.xp, 100)
	assert_almost_eq(GameState.hp, 42.0, 0.001)
	assert_eq(GameState.active_slot, 1)


# ------------------------------------------------------------------------------
# EC-06: сохранение в бою запрещено
# ------------------------------------------------------------------------------

func test_combat_disables_save_answer_with_reason_and_toast() -> void:
	GameState.set_in_combat(true)
	screen.open(bonfire)
	var dialog: AshenDialog = screen.get_dialog()
	dialog.reveal_all()
	await wait_process_frames(1)

	var save_answer: AshenMenuItem = dialog.get_answer_item(0)
	assert_true(save_answer.disabled, "пункт отключён")
	assert_eq(save_answer.disabled_reason, "В бою нельзя", "короткая причина в списке")
	assert_string_contains(
		dialog.get_body_text(),
		"Сохранение в бою запрещено",
		"полная причина видна в реплике"
	)
	assert_eq(dialog.get_body_text(), tr(Campfire.COMBAT_TEXT))

	var toast: AshenToast = screen.get_toast()
	assert_true(toast.visible)
	assert_eq(toast.get_kind(), AshenToast.Kind.DANGER)
	assert_eq(toast.get_message(), "Сохранение в бою запрещено")
	assert_false(screen.get_slots_panel().visible)

	# Даже программный выбор отключённого пункта не пишет на диск.
	screen.select_answer(0)
	await wait_process_frames(1)
	assert_eq(screen.get_state_name(), "talk")
	assert_false(SaveManager.has_slot(1), "в бою запись не создаётся")

	var rebuilt: AshenDialog = screen.get_dialog()
	rebuilt.reveal_all()
	await wait_process_frames(1)
	assert_false(rebuilt.get_answer_item(0).has_focus(), "фокус не на disabled-пункте")
	assert_eq(
		get_viewport().gui_get_focus_owner(),
		rebuilt.get_answer_item(1),
		"фокус переходит на первый доступный ответ"
	)


func test_combat_started_while_open_rebuilds_view() -> void:
	await _open()
	assert_false(screen.get_dialog().get_answer_item(0).disabled)

	GameState.set_in_combat(true)
	await wait_process_frames(1)

	var dialog: AshenDialog = screen.get_dialog()
	assert_true(dialog.get_answer_item(0).disabled)
	assert_eq(dialog.get_answer_item(0).disabled_reason, "В бою нельзя")
	assert_string_contains(dialog.get_body_text(), "Сохранение в бою запрещено")
	assert_eq(screen.get_toast().get_message(), "Сохранение в бою запрещено")
	assert_eq(screen.get_toast().get_kind(), AshenToast.Kind.DANGER)

	GameState.set_in_combat(false)
	await wait_process_frames(1)
	assert_false(screen.get_dialog().get_answer_item(0).disabled, "вне боя пункт снова доступен")


func test_combat_started_in_slots_returns_to_talk() -> void:
	await _open()
	await _choose(0)
	assert_eq(screen.get_state_name(), "slots")

	GameState.set_in_combat(true)
	await wait_process_frames(1)
	assert_eq(screen.get_state_name(), "talk", "из выбора слота сохраняться нельзя")
	assert_eq(screen.get_toast().get_message(), "Сохранение в бою запрещено")


# ------------------------------------------------------------------------------
# EC-14: ошибка диска и целостность прежней записи
# ------------------------------------------------------------------------------

func test_disk_error_shows_danger_toast_and_keeps_previous_slot() -> void:
	GameState.currency = 55
	assert_true(SaveManager.save_slot(1, {
		"zone_id": "zone_01_village",
		"zone_name": ZONE_NAME,
		"level": 3,
		"play_time": 900.0,
	}))
	GameState.currency = 999

	var original: String = _read_file(SaveManager.get_slot_path(1))
	var temp_path: String = SaveManager.get_slot_path(1) + ".tmp"
	assert_eq(
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_path)),
		OK,
		"блокируем атомарную запись: tmp — каталог"
	)

	await _open()
	await _choose(0)
	screen.select_slot(1)
	await wait_process_frames(1)

	assert_eq(screen.get_state_name(), "error")
	var toast: AshenToast = screen.get_toast()
	assert_true(toast.visible)
	assert_eq(toast.get_kind(), AshenToast.Kind.DANGER)
	assert_eq(toast.get_message(), "Нет места на диске. Прежняя запись цела.")

	var dialog: AshenDialog = screen.get_dialog()
	assert_eq(dialog.get_answer_count(), 3, "Повторить / Другой слот / Отмена")
	assert_eq(dialog.get_answer_item(0).text, "Повторить")
	assert_eq(dialog.get_answer_item(1).text, "Другой слот")
	assert_eq(dialog.get_answer_item(2).text, "Отмена  Esc")

	assert_eq(_read_file(SaveManager.get_slot_path(1)), original, "старый файл не тронут")
	var previous: Dictionary = SaveManager.read_slot(1)
	assert_true(previous["ok"], "прежняя запись по-прежнему валидна")
	var body: Dictionary = previous["body"]
	assert_eq(int(body["state"]["currency"]), 55, "в слоте осталось прежнее состояние")
	assert_eq(SaveManager.get_slot_metadata(1)["level"], 3)


func test_retry_after_disk_error_saves_when_space_returns() -> void:
	var temp_path: String = SaveManager.get_slot_path(1) + ".tmp"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_path))

	await _open()
	await _choose(0)
	screen.select_slot(1)
	await wait_process_frames(1)
	assert_eq(screen.get_state_name(), "error")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	screen.select_answer(0)
	await wait_process_frames(1)

	assert_eq(screen.get_state_name(), "saved", "«Повторить» завершает сохранение")
	assert_eq(screen.get_toast().get_message(), "СОХРАНЕНО · СЛОТ 1")
	assert_true(SaveManager.has_slot(1))


func test_slot_corrupted_signal_shows_danger_toast() -> void:
	await _open()
	EventBus.slot_corrupted.emit(2, SaveManager.LOAD_CORRUPTED)
	await wait_process_frames(1)

	assert_eq(screen.get_state_name(), "error")
	assert_eq(screen.get_toast().get_kind(), AshenToast.Kind.DANGER)
	assert_eq(screen.get_toast().get_message(), "Слот повреждён. Прежняя запись цела.")
	var dialog: AshenDialog = screen.get_dialog()
	assert_eq(dialog.get_answer_count(), 2)
	assert_eq(dialog.get_answer_item(0).text, "Другой слот")


func test_error_another_slot_and_cancel_return_to_flow() -> void:
	var temp_path: String = SaveManager.get_slot_path(1) + ".tmp"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_path))

	await _open()
	await _choose(0)
	screen.select_slot(1)
	await wait_process_frames(1)
	assert_eq(screen.get_state_name(), "error")

	screen.select_answer(1)
	await wait_process_frames(1)
	assert_eq(screen.get_state_name(), "slots", "«Другой слот» открывает выбор")

	screen.select_slot(1)
	await wait_process_frames(1)
	assert_eq(screen.get_state_name(), "error")

	screen.select_answer(2)
	await wait_process_frames(1)
	assert_eq(screen.get_state_name(), "talk", "«Отмена» возвращает к диалогу")


# ------------------------------------------------------------------------------
# Фракционный тег (AC-06.1)
# ------------------------------------------------------------------------------

func test_oath_answer_is_tagged_and_applies_reputation() -> void:
	await _open()
	var dialog: AshenDialog = screen.get_dialog()
	var expected_tag: String = _expected_oath_tag()
	assert_eq(dialog.get_answer_tag(2), expected_tag, "тег [Фракция±N] из таблицы Δ")
	assert_string_contains(dialog.get_answer_tag(2), "Орден")

	var delta: int = FactionManager.get_action_delta(OATH_FACTION, OATH_EVENT)
	assert_gt(delta, 0, "клятва должна давать положительную репутацию")
	var before: int = FactionManager.get_reputation(OATH_FACTION)

	await _choose(2)

	assert_eq(
		FactionManager.get_reputation(OATH_FACTION),
		before + delta,
		"выбор применяет apply_reputation_event (AC-06.1)"
	)
	assert_true(screen.get_toast().visible)
	assert_string_contains(screen.get_toast().get_message(), "Клятва принята")

	# Повторная клятва в этом диалоге не фармит репутацию.
	await _choose(2)
	assert_eq(FactionManager.get_reputation(OATH_FACTION), before + delta)


# ------------------------------------------------------------------------------
# Клавиатура/геймпад и геометрия
# ------------------------------------------------------------------------------

func test_keyboard_navigation_wraps_slots_and_escape_goes_back() -> void:
	await _open()
	await _choose(0)

	assert_eq(get_viewport().gui_get_focus_owner(), screen.get_slot_card(0))
	Input.parse_input_event(_action_event(&"ui_down"))
	await wait_process_frames(1)
	assert_eq(screen.get_selected_slot(), 2)
	assert_eq(get_viewport().gui_get_focus_owner(), screen.get_slot_card(1))

	Input.parse_input_event(_action_event(&"ui_down"))
	await wait_process_frames(1)
	assert_eq(screen.get_selected_slot(), 3)

	Input.parse_input_event(_action_event(&"ui_down"))
	await wait_process_frames(1)
	assert_eq(screen.get_selected_slot(), 1, "навигация заворачивается")

	Input.parse_input_event(_action_event(&"ui_cancel"))
	await wait_process_frames(1)
	assert_eq(screen.get_state_name(), "talk", "Esc из слотов — назад")

	Input.parse_input_event(_action_event(&"ui_cancel"))
	await wait_process_frames(1)
	assert_false(screen.is_open(), "Esc из диалога закрывает костёр")
	assert_false(screen.visible)


func test_layout_matches_mockup_and_fits_480x270() -> void:
	await _open()

	var dialog: AshenDialog = screen.get_dialog()
	assert_eq(dialog.position, Vector2(8, 166), "диалог макета в кадре 480×270")
	assert_eq(dialog.size, UITokens.DIALOG_SIZE)
	assert_true(dialog.position.y + dialog.size.y <= 270.0 - float(UITokens.SAFE_MARGIN))

	await _choose(0)
	var panel: AshenPanel = screen.get_slots_panel()
	assert_eq(panel.position, Vector2(96, 22), "панель слотов макета")
	assert_eq(int(panel.size.x), 288)
	assert_true(panel.position.y + panel.size.y < dialog.position.y, "панель не перекрывает диалог")
	assert_true(panel.position.x + panel.size.x <= 480.0 - float(UITokens.SAFE_MARGIN))


func test_zone_time_formatting_and_empty_slot_view() -> void:
	assert_eq(Campfire.format_play_time(22320.0), "6ч 12м")
	assert_eq(Campfire.format_play_time(0.0), "0ч 00м")
	assert_eq(Campfire.format_play_time(-5.0), "0ч 00м")

	var empty: Dictionary = Campfire.build_slot_view({"exists": false}, 2)
	assert_true(empty["empty"])
	assert_eq(empty["title"], "— Пусто —")
	assert_false(empty["overwrite"])

	var occupied: Dictionary = Campfire.build_slot_view({
		"exists": true,
		"valid": true,
		"zone_name": "Болото",
		"level": 7,
		"play_time": 22320.0,
	}, 1)
	assert_false(occupied["empty"])
	assert_true(occupied["overwrite"])
	assert_eq(occupied["details"], "УР7 · 6ч 12м")


func test_zone_display_name_comes_from_zone_data() -> void:
	assert_eq(Campfire.zone_display_name(ZONE), ZONE_NAME)
	assert_eq(Campfire.zone_display_name(&"unknown_zone"), "")


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _open() -> void:
	screen.open(bonfire)
	await wait_process_frames(1)
	var dialog: AshenDialog = screen.get_dialog()
	if dialog.is_typing():
		dialog.reveal_all()
	await wait_process_frames(1)


func _choose(index: int) -> void:
	screen.select_answer(index)
	await wait_process_frames(1)


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _read_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _expected_oath_tag() -> String:
	var delta: int = FactionManager.get_action_delta(OATH_FACTION, OATH_EVENT)
	var faction_name: String = FactionManager.get_faction_name(OATH_FACTION)
	var space: int = faction_name.find(" ")
	if space > 0:
		faction_name = faction_name.substr(0, space)
	var sign_text: String = "+" if delta > 0 else ""
	return "[%s%s%d]" % [faction_name, sign_text, delta]


func _cleanup_dir() -> void:
	var directory: DirAccess = DirAccess.open(TEST_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for dir_name: String in directory.get_directories():
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(TEST_DIR.path_join(dir_name))
		)
