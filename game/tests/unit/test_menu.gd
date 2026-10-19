extends GutTest
## T-20 — главное меню и настройки (TASKS T-20; DESIGN §6.1/§8.1/§9;
## макеты `docs/mockups/main-menu.html`).
##
## Проверяем acceptance на живых сценах:
##   * `MainMenu.tscn`: название/пункты/подсказки/RU-EN/версия; навигация
##     только клавиатурой и только геймпадом (ui_* в InputMap);
##   * «Продолжить» отключено без валидных сохранений, причина видна;
##   * `Settings.tscn`: язык, масштаб 100/150/200, режим окна, a11y-тумблеры,
##     ремап открывает Remap (T-24); всё пишется в settings.cfg и перечитывается
##     «после перезапуска»;
##   * `SaveSlots.tscn`: занят/пуст/повреждён (EC-07) — ошибка, предложение
##     другого слота, без вылета и без сигнала загрузки.
##
## Слоты и настройки пишутся во временные `user://test_menu_t20*`; реальные
## user:// файлы и `SaveManager.saves_dir`/`Config.settings_path`
## восстанавливаются в after_each.

const MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")
const SETTINGS_SCENE: PackedScene = preload("res://ui/menus/Settings.tscn")
const SLOTS_SCENE: PackedScene = preload("res://ui/menus/SaveSlots.tscn")
const CONFIG_SCRIPT: Script = preload("res://autoload/Config.gd")

const TEST_DIR: String = "user://test_menu_t20"
const TEST_SETTINGS: String = "user://test_menu_t20_settings.cfg"
const ZONE: String = "zone_01_village"
const ZONE_NAME: String = "Деревня-бастион"

var menu: MainMenu

var _saves_dir: String = SaveManager.DEFAULT_SAVES_DIR
var _settings_path: String = Config.DEFAULT_SETTINGS_PATH
var _language: String = Config.LANGUAGE_RU
var _ui_scale: int = Config.UI_SCALE_100
var _window_mode: int = Config.WINDOW_WINDOWED
var _no_flash: bool = false
var _silhouette: bool = false
var _subtitles: bool = true
var _master: float = 1.0
var _music: float = 0.8
var _sfx: float = 0.8
var _active_slot: int = 0


func before_all() -> void:
	_saves_dir = SaveManager.saves_dir
	_settings_path = Config.settings_path
	SaveManager.saves_dir = TEST_DIR


func after_all() -> void:
	SaveManager.saves_dir = _saves_dir
	Config.settings_path = _settings_path
	_cleanup_dir(TEST_DIR)
	_remove_file(TEST_SETTINGS)


func before_each() -> void:
	_language = Config.language
	_ui_scale = Config.ui_scale
	_window_mode = Config.window_mode
	_no_flash = Config.no_flash
	_silhouette = Config.silhouette_readability
	_subtitles = Config.sound_subtitles
	_master = Config.master_volume
	_music = Config.music_volume
	_sfx = Config.sfx_volume
	_active_slot = GameState.active_slot

	Config.settings_path = TEST_SETTINGS
	_remove_file(TEST_SETTINGS)
	Config.set_language(Config.LANGUAGE_RU)
	Config.ui_scale = Config.UI_SCALE_100
	Config.window_mode = Config.WINDOW_WINDOWED
	Config.set_no_flash(false)
	Config.set_silhouette_readability(false)
	Config.set_sound_subtitles(true)
	Config.set_master_volume(1.0)
	Config.set_music_volume(0.8)
	Config.set_sfx_volume(0.8)

	SaveManager.saves_dir = TEST_DIR
	_cleanup_dir(TEST_DIR)
	_make_dir(TEST_DIR)
	GameState.active_slot = 0

	menu = _make_menu()
	# `_ready` планирует _focus_initial через call_deferred: даём ему выполниться,
	# чтобы тест мог сам управлять фокусом.
	await wait_process_frames(2)


func after_each() -> void:
	if menu != null and is_instance_valid(menu):
		menu.close()
	menu = null
	await wait_process_frames(1)

	Config.settings_path = _settings_path
	Config.set_language(_language)
	Config.ui_scale = _ui_scale
	Config.window_mode = _window_mode
	Config.set_no_flash(_no_flash)
	Config.set_silhouette_readability(_silhouette)
	Config.set_sound_subtitles(_subtitles)
	Config.set_master_volume(_master)
	Config.set_music_volume(_music)
	Config.set_sfx_volume(_sfx)
	SaveManager.saves_dir = _saves_dir
	GameState.active_slot = _active_slot
	_cleanup_dir(TEST_DIR)
	_remove_file(TEST_SETTINGS)


# ------------------------------------------------------------------------------
# A. Название, пункты, язык, версия
# ------------------------------------------------------------------------------

func test_title_items_subtitle_version_and_ru_en_switch() -> void:
	var title: String = menu.get_title_text()
	assert_string_contains(title, "ПЕПЕЛЬНЫЙ")
	assert_string_contains(title, "БАСТИОН")
	assert_string_contains(menu.get_subtitle_text(), "ASHEN BASTION")
	assert_eq(menu.get_version_text(), "v0.1.0")

	var texts: Array[String] = _menu_texts()
	assert_eq(
		texts,
		["Продолжить", "Новая игра", "Загрузить", "Настройки", "Выход"],
		"пункты меню по макету main-menu.html"
	)

	var lang: Array[Control] = menu.get_language_buttons()
	assert_eq(lang.size(), 2, "переключатель RU/EN внизу")
	(lang[1] as Button).pressed.emit()
	await wait_process_frames(1)

	assert_eq(Config.language, Config.LANGUAGE_EN)
	assert_eq(Config.settings_path, TEST_SETTINGS)
	assert_true(FileAccess.file_exists(TEST_SETTINGS), "язык сохранён в settings.cfg")
	assert_eq(ConfigFile.new().load(TEST_SETTINGS), OK)
	var file := ConfigFile.new()
	file.load(TEST_SETTINGS)
	assert_eq(str(file.get_value(Config.SETTINGS_SECTION, "language", "")), "en")

	assert_eq(menu.get_menu_items()[0].text, "Continue")
	assert_eq(menu.get_title_text(), "ASHEN BASTION")
	assert_string_contains(menu.get_subtitle_text(), "ПЕПЕЛЬНЫЙ БАСТИОН")
	assert_eq(TranslationServer.get_locale().substr(0, 2), "en")

	(lang[0] as Button).pressed.emit()
	await wait_process_frames(1)
	assert_eq(Config.language, Config.LANGUAGE_RU)
	assert_eq(menu.get_menu_items()[0].text, "Продолжить")


func test_status_hint_for_focused_item_and_language_button() -> void:
	menu.focus_item(1)
	await wait_process_frames(1)
	assert_eq(menu.get_status_text(), "Начать новое путешествие")

	menu.focus_item(5)
	await wait_process_frames(1)
	assert_eq(menu.get_status_text(), "Язык интерфейса")


# ------------------------------------------------------------------------------
# B. «Продолжить» без сохранений + причина (DESIGN §6.1)
# ------------------------------------------------------------------------------

func test_continue_is_disabled_without_saves_and_reason_is_shown() -> void:
	var continue_button: AshenMenuItem = menu.get_continue_button()
	assert_true(continue_button.disabled, "без сохранений «Продолжить» отключено")
	assert_eq(continue_button.disabled_reason, "Нет сохранений")
	assert_eq(continue_button.tooltip_text, "Нет сохранений", "причина в tooltip")
	assert_gt(
		continue_button.get_row_height(),
		UITokens.ROW_MENU_BODY,
		"строка выше базовой: причина нарисована inline"
	)

	menu.focus_item(0)
	await wait_process_frames(1)
	assert_true(continue_button.has_focus())
	assert_true(continue_button.is_focus_visible(), "фокус виден и на disabled-пункте")
	assert_eq(continue_button.get_caret_text(), "", "disabled без каретки")

	assert_eq(menu.get_status_text(), "Нет сохранений", "причина в строке-подсказке")

	watch_signals(menu)
	menu._input(_action(&"ui_accept"))
	await wait_process_frames(1)
	assert_signal_not_emitted(menu, "continue_requested")


func test_continue_stays_disabled_when_all_saves_are_corrupted() -> void:
	_write_corrupt_slot(1)
	menu.refresh_saves()

	var continue_button: AshenMenuItem = menu.get_continue_button()
	assert_true(continue_button.disabled)
	assert_string_contains(continue_button.disabled_reason, "повреждены")


# ------------------------------------------------------------------------------
# C. Навигация только клавиатурой / только геймпадом (a11y §9.2)
# ------------------------------------------------------------------------------

func test_focus_order_wraps_with_keyboard_and_gamepad_actions() -> void:
	menu.focus_item(0)
	await wait_process_frames(1)
	assert_eq(menu.get_focused_index(), 0)

	menu._input(_action(&"ui_up"))
	await wait_process_frames(1)
	assert_true(menu.get_language_buttons()[1].has_focus(), "↑ с первого пункта → EN")

	menu._input(_action(&"ui_down"))
	await wait_process_frames(1)
	assert_eq(menu.get_focused_index(), 0, "↓ с EN замыкает на «Продолжить»")

	for expected: int in [1, 2, 3, 4, 5, 6, 0]:
		menu._input(_action(&"ui_down"))
		await wait_process_frames(1)
		if expected <= 4:
			assert_eq(menu.get_focused_index(), expected)
		elif expected == 5:
			assert_true(menu.get_language_buttons()[0].has_focus(), "после «Выход» — RU")
		elif expected == 6:
			assert_true(menu.get_language_buttons()[1].has_focus(), "после RU — EN")
		else:
			assert_eq(menu.get_focused_index(), 0, "после EN — снова первый пункт")


func test_all_menu_actions_have_keyboard_and_gamepad_events() -> void:
	for action: StringName in [&"ui_up", &"ui_down", &"ui_accept", &"ui_cancel"]:
		var has_key: bool = false
		var has_pad: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				has_key = true
			elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
				has_pad = true
		assert_true(has_key, "%s: есть клавиша" % action)
		assert_true(has_pad, "%s: есть кнопка/стик геймпада" % action)


func test_every_menu_item_is_focusable_and_has_a11y_meta() -> void:
	for item: AshenMenuItem in menu.get_menu_items():
		assert_eq(item.focus_mode, Control.FOCUS_ALL)
		assert_false(str(item.get_meta(&"a11y_name", "")).is_empty())
		assert_eq(str(item.get_meta(&"a11y_role", "")), "menuitem")
	for button: Control in menu.get_language_buttons():
		assert_eq(button.focus_mode, Control.FOCUS_ALL)
		assert_false(str(button.get_meta(&"a11y_name", "")).is_empty())


# ------------------------------------------------------------------------------
# D. Загрузка: занят/пуст/повреждён (EC-07)
# ------------------------------------------------------------------------------

func test_valid_save_enables_continue_and_load_slot_emits() -> void:
	assert_true(_make_save(1, ZONE_NAME, 7, 22320.0), "сейв создан")
	menu.refresh_saves()

	var continue_button: AshenMenuItem = menu.get_continue_button()
	assert_false(continue_button.disabled)
	assert_eq(menu.get_continue_slot(), 1)

	watch_signals(menu)
	menu.activate_item(0)
	await wait_process_frames(1)
	assert_signal_emitted_with_parameters(menu, "continue_requested", [1])

	menu.activate_item(2)
	await wait_process_frames(1)
	assert_eq(menu.get_view(), MainMenu.View.LOAD)
	var slots: AshenSaveSlots = menu.get_slots_view()
	assert_eq(slots.get_state(1), AshenSaveSlots.CardState.VALID)
	assert_eq(slots.get_card(0).title_text, ZONE_NAME)

	watch_signals(slots)
	slots.activate_slot(1)
	await wait_process_frames(1)
	assert_signal_emitted_with_parameters(slots, "slot_selected", [1])
	assert_signal_emitted_with_parameters(menu, "load_requested", [1])


func test_corrupted_slot_shows_error_and_offers_another_without_crash() -> void:
	_write_corrupt_slot(2)
	menu.refresh_saves()
	menu.show_view(MainMenu.View.LOAD)
	await wait_process_frames(1)

	var slots: AshenSaveSlots = menu.get_slots_view()
	assert_eq(slots.get_state(2), AshenSaveSlots.CardState.CORRUPTED)
	assert_string_contains(slots.get_card(1).title_text, "повреждён")
	assert_string_contains(slots.get_card(1).detail_text, "Контрольная сумма")

	watch_signals(slots)
	slots.activate_slot(2)
	await wait_process_frames(1)

	assert_string_contains(slots.get_alert_text(), "Слот 2 повреждён")
	assert_string_contains(slots.get_alert_text(), "выберите другой")
	assert_true(slots.is_alert_visible())
	assert_signal_not_emitted(slots, "slot_selected", "повреждённый слот не грузится")
	assert_ne(slots.get_focused_index(), 1, "фокус переведён на другой слот")
	assert_true(menu.is_open(), "меню не вылетело")


func test_empty_slot_shows_reason_and_does_not_load() -> void:
	menu.show_view(MainMenu.View.LOAD)
	await wait_process_frames(1)
	var slots: AshenSaveSlots = menu.get_slots_view()
	assert_eq(slots.get_state(1), AshenSaveSlots.CardState.EMPTY)
	assert_eq(slots.get_card(0).title_text, "— Пусто —")

	watch_signals(slots)
	slots.activate_slot(1)
	await wait_process_frames(1)
	assert_string_contains(slots.get_alert_text(), "пуст")
	assert_signal_not_emitted(slots, "slot_selected")


func test_escape_from_slots_and_settings_returns_to_previous_item() -> void:
	menu.activate_item(2)
	await wait_process_frames(1)
	assert_eq(menu.get_view(), MainMenu.View.LOAD)
	menu.get_slots_view()._input(_action(&"ui_cancel"))
	await wait_process_frames(1)
	assert_eq(menu.get_view(), MainMenu.View.MAIN)
	assert_eq(menu.get_focused_index(), 2, "возврат запоминает «Загрузить»")

	menu.activate_item(3)
	await wait_process_frames(1)
	assert_eq(menu.get_view(), MainMenu.View.SETTINGS)
	menu.get_settings_view()._input(_action(&"ui_cancel"))
	await wait_process_frames(1)
	assert_eq(menu.get_view(), MainMenu.View.MAIN)
	assert_eq(menu.get_focused_index(), 3, "возврат запоминает «Настройки»")


# ------------------------------------------------------------------------------
# E. Настройки: значения, сохранение, применение
# ------------------------------------------------------------------------------

func test_settings_language_switch_updates_labels_and_file() -> void:
	var settings: AshenSettingsView = menu.get_settings_view()
	menu.show_view(MainMenu.View.SETTINGS)
	await wait_process_frames(1)

	assert_eq(settings.get_row(0).label_text, "Язык / Language")
	assert_eq(settings.get_value_text(AshenSettingsView.ROW_LANGUAGE), "Русский")

	settings.activate_row(0)
	await wait_process_frames(1)
	assert_eq(Config.language, Config.LANGUAGE_EN)
	assert_eq(settings.get_row(0).label_text, "Language / Язык")
	assert_eq(settings.get_value_text(AshenSettingsView.ROW_LANGUAGE), "English")
	assert_eq(_saved_value("language"), "en")


func test_settings_ui_scale_cycles_100_150_200_and_applies_to_menu() -> void:
	var settings: AshenSettingsView = menu.get_settings_view()
	menu.show_view(MainMenu.View.SETTINGS)
	await wait_process_frames(1)

	settings.activate_row(1)
	await wait_process_frames(1)
	assert_eq(Config.ui_scale, 150)
	assert_eq(menu.get_menu_items()[0].font_size, 12, "меню применяет масштаб сразу")
	assert_eq(_saved_value("ui_scale"), 150)

	settings.activate_row(1)
	await wait_process_frames(1)
	assert_eq(Config.ui_scale, 200)
	assert_eq(menu.get_menu_items()[0].font_size, 16)
	assert_eq(_saved_value("ui_scale"), 200)

	settings.activate_row(1)
	await wait_process_frames(1)
	assert_eq(Config.ui_scale, 100)
	assert_eq(menu.get_menu_items()[0].font_size, 8)
	assert_eq(_saved_value("ui_scale"), 100)


func test_settings_window_mode_cycles_and_persists() -> void:
	var settings: AshenSettingsView = menu.get_settings_view()
	menu.show_view(MainMenu.View.SETTINGS)
	await wait_process_frames(1)

	assert_eq(settings.get_value_text(AshenSettingsView.ROW_WINDOW_MODE), "В окне")
	settings.activate_row(2)
	await wait_process_frames(1)
	assert_eq(Config.window_mode, Config.WINDOW_FULLSCREEN)
	assert_eq(settings.get_value_text(AshenSettingsView.ROW_WINDOW_MODE), "Полный экран")
	assert_eq(Config.display_mode_for(Config.window_mode), DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert_eq(_saved_value("window_mode"), 1)

	settings.activate_row(2)
	await wait_process_frames(1)
	assert_eq(Config.window_mode, Config.WINDOW_BORDERLESS)
	assert_eq(_saved_value("window_mode"), 2)

	settings.activate_row(2)
	await wait_process_frames(1)
	assert_eq(Config.window_mode, Config.WINDOW_WINDOWED)
	assert_eq(_saved_value("window_mode"), 0)


func test_settings_a11y_toggles_apply_signals_and_persist() -> void:
	var settings: AshenSettingsView = menu.get_settings_view()
	menu.show_view(MainMenu.View.SETTINGS)
	await wait_process_frames(1)
	watch_signals(Config)

	settings.activate_row(3)
	await wait_process_frames(1)
	assert_true(Config.silhouette_readability)
	assert_true(bool(_saved_value("silhouette_readability")))
	assert_signal_emitted(Config, "visual_accessibility_changed")

	settings.activate_row(4)
	await wait_process_frames(1)
	assert_true(Config.no_flash)
	assert_true(bool(_saved_value("no_flash")))

	settings.activate_row(5)
	await wait_process_frames(1)
	assert_false(Config.sound_subtitles)
	assert_false(bool(_saved_value("sound_subtitles")))
	assert_signal_emitted(Config, "audio_settings_changed")

	# Тумблер не только цветом: положение и текст дублируют состояние.
	assert_eq(settings.get_row(4).get_value_text(), "ВКЛ")


func test_settings_remap_opens_remap_screen() -> void:
	var settings: AshenSettingsView = menu.get_settings_view()
	menu.show_view(MainMenu.View.SETTINGS)
	await wait_process_frames(1)
	var remap_row: Control = settings.get_row(6)
	assert_false(remap_row.disabled, "ремап доступен после T-24")
	assert_eq(remap_row.tooltip_text, "")
	assert_eq(remap_row.get_row_height(), UITokens.ROW_MENU_BODY)

	settings.focus_row(6)
	await wait_process_frames(1)
	assert_true(remap_row.has_focus(), "строка ремапа доступна фокусу")
	assert_eq(remap_row.focus_mode, Control.FOCUS_ALL)

	watch_signals(settings)
	settings.adjust_row(6, 1)
	await wait_process_frames(2)
	assert_signal_emitted(settings, "remap_requested")
	assert_true(menu.get_remap_view().is_open(), "открывается экран Remap")
	assert_false(settings.visible, "настройки скрыты под ремапом")
	assert_eq(Config.ui_scale, 100, "ремап не меняет масштаб UI")

	menu.get_remap_view().close()
	await wait_process_frames(2)
	assert_true(settings.visible, "после закрытия ремапа возвращаемся в настройки")


func test_slot_formatters_cover_time_date_and_elide() -> void:
	assert_eq(AshenSaveSlots.format_play_time(0.0, false), "0м")
	assert_eq(AshenSaveSlots.format_play_time(22320.0, false), "6ч 12м")
	assert_eq(AshenSaveSlots.format_play_time(22320.0, true), "6h 12m")
	assert_eq(AshenSaveSlots.format_saved_at(0), "")
	assert_eq(AshenSaveSlots.format_saved_at(1760000000).length(), 10)

	var long_text: String = "Очень длинное название зоны, которое не помещается"
	var short_text: String = AshenSaveSlots.elide(long_text, 120.0, UITokens.FONT_BODY)
	assert_lte(UIStyle.text_width(short_text, UITokens.FONT_BODY), 120.0)
	assert_true(short_text.ends_with(".."))


func test_config_normalizes_language_scale_and_window_mode() -> void:
	assert_eq(Config.normalize_language("EN_us"), "en")
	assert_eq(Config.normalize_language("de"), "ru")
	assert_eq(Config.normalize_ui_scale(90), 100)
	assert_eq(Config.normalize_ui_scale(130), 150)
	assert_eq(Config.normalize_ui_scale(190), 200)
	assert_eq(Config.next_ui_scale(200, 1), 100)
	assert_eq(Config.next_ui_scale(100, -1), 200)
	assert_eq(int(Config.display_mode_for(Config.WINDOW_FULLSCREEN)), int(DisplayServer.WINDOW_MODE_FULLSCREEN))
	# MINOR-01: «Без рамки» — оконный режим + WINDOW_FLAG_BORDERLESS, а не
	# эксклюзивный полный экран (раньше маппинг был перепутан).
	assert_eq(int(Config.display_mode_for(Config.WINDOW_BORDERLESS)), int(DisplayServer.WINDOW_MODE_WINDOWED))
	assert_false(Config.is_borderless_mode(Config.WINDOW_FULLSCREEN))
	assert_false(Config.is_borderless_mode(Config.WINDOW_WINDOWED))
	assert_true(Config.is_borderless_mode(Config.WINDOW_BORDERLESS))



func test_settings_persist_and_reload_after_restart() -> void:
	Config.set_language(Config.LANGUAGE_EN)
	Config.ui_scale = 200
	Config.window_mode = Config.WINDOW_BORDERLESS
	Config.set_no_flash(true)
	Config.set_silhouette_readability(true)
	Config.set_sound_subtitles(false)
	Config.set_music_volume(0.25)
	assert_true(Config.save_settings(), "settings.cfg записан")

	# «Перезапуск»: сбрасываем память и читаем файл заново.
	Config.set_language(Config.LANGUAGE_RU)
	Config.ui_scale = 100
	Config.window_mode = Config.WINDOW_WINDOWED
	Config.set_no_flash(false)
	Config.set_silhouette_readability(false)
	Config.set_sound_subtitles(true)
	Config.set_music_volume(1.0)

	assert_true(Config.load_settings(), "settings.cfg прочитан")
	assert_eq(Config.language, Config.LANGUAGE_EN)
	assert_eq(Config.ui_scale, 200)
	assert_eq(Config.window_mode, Config.WINDOW_BORDERLESS)
	assert_true(Config.no_flash)
	assert_true(Config.silhouette_readability)
	assert_false(Config.sound_subtitles)
	assert_almost_eq(Config.music_volume, 0.25, 0.001)

	# После загрузки UI перестраивается: масштаб 200 → 16 px в меню.
	menu.apply_ui_scale()
	assert_eq(menu.get_menu_items()[0].font_size, 16)


func test_config_load_keeps_other_sections_input_remap() -> void:
	var file := ConfigFile.new()
	file.set_value("input", "remap_jump", "Space")
	assert_eq(file.save(TEST_SETTINGS), OK, "подготовлен файл с [input]")

	Config.set_language(Config.LANGUAGE_EN)
	Config.ui_scale = 150
	assert_true(Config.save_settings())

	var loaded := ConfigFile.new()
	assert_eq(loaded.load(TEST_SETTINGS), OK)
	assert_eq(str(loaded.get_value("input", "remap_jump", "")), "Space", "ремап T-03 не потерян")
	assert_eq(int(loaded.get_value(Config.SETTINGS_SECTION, "ui_scale", 0)), 150)


func test_menu_texts_fit_at_100_and_150_percent() -> void:
	var settings: AshenSettingsView = menu.get_settings_view()
	for scale: int in [Config.UI_SCALE_100, Config.UI_SCALE_150]:
		Config.ui_scale = scale
		menu.apply_ui_scale()
		settings.apply_ui_scale()
		await wait_process_frames(2)

		var item_font: int = 8 * scale / 100
		for text: String in _menu_texts():
			var width: float = UIStyle.text_width(text, item_font)
			assert_lt(
				width + float(item_font) + float(UITokens.SP_3 * 2),
				float(MainMenu.MENU_WIDTH),
				"%s помещается в меню при %d%%" % [text, scale]
			)

		for index: int in settings.get_rows().size():
			var row: Control = settings.get_row(index)
			if row.size.x <= 0.0:
				continue
			var label: String = settings.get_row(index).label_text
			var value: String = settings.get_row(index).get_value_text()
			var total: float = UIStyle.text_width(label, settings.get_row(index).font_size) \
				+ UIStyle.text_width(value, UITokens.FONT_BODY) \
				+ float(UITokens.PANEL_PADDING * 6)
			assert_lt(
				total,
				row.size.x,
				"строка %s помещается при %d%% (row=%.0f)" % [label, scale, row.size.x]
			)


# ------------------------------------------------------------------------------
# F. Обработчики SaveManager/EventBus не роняют меню
# ------------------------------------------------------------------------------

func test_slot_corrupted_signal_refreshes_menu_and_shows_error_in_load_view() -> void:
	_write_corrupt_slot(3)
	menu.show_view(MainMenu.View.LOAD)
	await wait_process_frames(1)
	EventBus.slot_corrupted.emit(3, SaveManager.LOAD_CORRUPTED)
	await wait_process_frames(1)
	assert_eq(menu.get_slots_view().get_state(3), AshenSaveSlots.CardState.CORRUPTED)
	assert_string_contains(menu.get_slots_view().get_alert_text(), "повреждён")


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _make_menu() -> MainMenu:
	var instance := MENU_SCENE.instantiate() as MainMenu
	instance.handle_game_start = false
	instance.handle_quit = false
	instance.start_visible = true
	add_child_autofree(instance)
	return instance


func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _menu_texts() -> Array[String]:
	var texts: Array[String] = []
	for item: AshenMenuItem in menu.get_menu_items():
		texts.append(item.text)
	return texts


func _make_save(slot: int, zone_name: String, level: int, play_time: float) -> bool:
	return SaveManager.save_slot(slot, {
		"zone_id": ZONE,
		"zone_name": zone_name,
		"level": level,
		"play_time": play_time,
	})


func _write_corrupt_slot(slot: int) -> void:
	_make_dir(TEST_DIR)
	var path: String = TEST_DIR.path_join("slot_%d.json" % slot)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "файл слота открыт на запись")
	if file == null:
		return
	file.store_string("{\"schema_version\":1,\"checksum\":\"deadbeef\",\"body\":{}}")
	file.close()


func _saved_value(key: String) -> Variant:
	var file := ConfigFile.new()
	if file.load(TEST_SETTINGS) != OK:
		return null
	return file.get_value(Config.SETTINGS_SECTION, key, null)


func _make_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cleanup_dir(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory != null:
		for file_name: String in directory.get_files():
			directory.remove(file_name)
	DirAccess.remove_absolute(absolute)
