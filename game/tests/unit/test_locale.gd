extends GutTest
## T-36 — локализация RU/EN (TASKS T-36; PLAN §3.5; DESIGN §9.6 п.6).
##
## Проверяет acceptance:
##   * единые CSV-ключи `assets/locale/{ru,en}.csv`, у каждого ключа есть
##     перевод в обеих локалях;
##   * смена языка мгновенно обновляет живой UI без пересоздания экрана;
##   * пользовательские строки UI идут через `tr()` — в `ui/**/*.gd` нет
##     строковых литералов с кириллицей;
##   * данные (фракции/зоны/способности/концовки) отдают локализованный текст;
##   * RU/EN строки не пустые (переполнение проверяется рендером 480×270).
##
## Язык восстанавливается после каждого теста; user:// не затрагивается.

const CSV_RU: String = "res://assets/locale/ru.csv"
const CSV_EN: String = "res://assets/locale/en.csv"
const UI_DIR: String = "res://ui"
const MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")

const CYRILLIC_LITERAL := "\"(?:[^\"\\\\]|\\\\.)*[А-Яа-яЁё](?:[^\"\\\\]|\\\\.)*\""

var _language: String = Config.LANGUAGE_RU


func before_each() -> void:
	_language = Config.language
	Config.language = Config.LANGUAGE_RU
	TranslationServer.set_locale(Config.LANGUAGE_RU)


func after_each() -> void:
	Config.language = _language
	TranslationServer.set_locale(_language)
	Locale.refresh_bindings()


# ------------------------------------------------------------------------------
# CSV и TranslationServer
# ------------------------------------------------------------------------------

func test_csv_files_have_identical_non_empty_key_sets() -> void:
	var ru_keys: Array[String] = _read_keys(CSV_RU)
	var en_keys: Array[String] = _read_keys(CSV_EN)
	assert_gt(ru_keys.size(), 200, "в CSV заведены все пользовательские строки")
	assert_eq(ru_keys, en_keys, "наборы ключей ru/en совпадают")
	for key: String in ru_keys:
		assert_false(key.is_empty(), "пустой ключ недопустим")
		assert_eq(ru_keys.count(key), 1, "ключ %s уникален" % key)


func test_every_key_translates_in_ru_and_en() -> void:
	var keys: Array[String] = _read_keys(CSV_RU)
	TranslationServer.set_locale(Config.LANGUAGE_RU)
	for key: String in keys:
		var ru: String = TranslationServer.translate(key)
		assert_false(ru.is_empty(), "RU-перевод не пуст: %s" % key)
	TranslationServer.set_locale(Config.LANGUAGE_EN)
	for key: String in keys:
		var en: String = TranslationServer.translate(key)
		assert_false(en.is_empty(), "EN-перевод не пуст: %s" % key)


func test_locale_switches_translation_server_and_restores() -> void:
	Locale.set_language(Config.LANGUAGE_EN)
	assert_eq(TranslationServer.get_locale(), Config.LANGUAGE_EN)
	assert_true(Locale.is_english())
	assert_eq(Locale.translate_key("ui.menu.continue"), "Continue")
	assert_eq(Locale.format_key("ui.saves.slot_empty", [2]), "Slot 2 is empty")
	Locale.set_language(Config.LANGUAGE_RU)
	assert_eq(TranslationServer.get_locale(), Config.LANGUAGE_RU)
	assert_eq(Locale.translate_key("ui.menu.continue"), "Продолжить")


# ------------------------------------------------------------------------------
# Мгновенное обновление UI
# ------------------------------------------------------------------------------

func test_bound_label_updates_on_language_change() -> void:
	var label := Label.new()
	add_child_autofree(label)
	Locale.bind(label, "ui.menu.continue")
	assert_eq(label.text, "Продолжить")
	Locale.set_language(Config.LANGUAGE_EN)
	Locale.refresh_bindings()
	assert_eq(label.text, "Continue", "привязанная подпись обновилась без перезапуска")
	Locale.bind_tooltip(label, "ui.menu.hint_continue")
	assert_eq(label.tooltip_text, "Load the latest save")
	Locale.set_language(Config.LANGUAGE_RU)
	Locale.refresh_bindings()
	assert_eq(label.text, "Продолжить")


func test_main_menu_refreshes_without_reopen() -> void:
	var menu := MENU_SCENE.instantiate() as MainMenu
	add_child_autofree(menu)
	menu.start_visible = false
	menu.refresh_saves()
	assert_string_contains(menu.get_title_text(), "ПЕПЕЛЬНЫЙ")
	assert_eq(menu.get_menu_items()[1].text, "Новая игра")

	Locale.set_language(Config.LANGUAGE_EN)
	assert_string_contains(menu.get_title_text(), "ASHEN", "заголовок обновился сразу")
	assert_eq(menu.get_menu_items()[1].text, "New game", "пункты меню обновились сразу")
	assert_eq(menu.get_menu_items()[0].text, "Continue")

	Locale.set_language(Config.LANGUAGE_RU)
	assert_eq(menu.get_menu_items()[1].text, "Новая игра")


func test_hud_static_labels_refresh_without_rebuild() -> void:
	var hud := AshenHUD.new()
	add_child_autofree(hud)
	assert_eq(hud.get_no_stamina_text(), "НЕТ СИЛ")
	Locale.set_language(Config.LANGUAGE_EN)
	assert_eq(hud.get_no_stamina_text(), "NO STAMINA")
	assert_eq(hud.get_level_text(), tr("ui.common.level") % hud.level)
	Locale.set_language(Config.LANGUAGE_RU)
	assert_eq(hud.get_no_stamina_text(), "НЕТ СИЛ")


# ------------------------------------------------------------------------------
# Данные и статические помощники
# ------------------------------------------------------------------------------

func test_data_names_and_epilogues_are_localized() -> void:
	Locale.set_language(Config.LANGUAGE_EN)
	assert_eq(FactionManager.get_faction_name(&"order"), "Order of Ash")
	var zone: ZoneData = load("res://data/zones/zone_01_village.tres") as ZoneData
	assert_eq(zone.get_display_name(), "Bastion Village")
	assert_eq(zone.get_epigraph(), "Ash remembers the names of those who stayed.")

	Locale.set_language(Config.LANGUAGE_RU)
	assert_eq(FactionManager.get_faction_name(&"order"), "Орден Пепла")
	assert_eq(zone.get_display_name(), "Деревня-бастион")


func test_ending_catalog_uses_current_locale() -> void:
	Locale.set_language(Config.LANGUAGE_EN)
	var ending: EndingText = EndingCatalog.resolve(&"free", "Free Marches")
	assert_string_contains(ending.title, "FREE MARCHES")
	assert_string_contains(ending.body, "burned the throne")
	assert_string_contains(ending.faction_line, "Free Marches")

	Locale.set_language(Config.LANGUAGE_RU)
	var neutral: EndingText = EndingCatalog.resolve(&"", "")
	assert_eq(neutral.title, "ПЕПЕЛ НА ВЕТРУ")


func test_campfire_slot_cards_are_localized() -> void:
	Locale.set_language(Config.LANGUAGE_EN)
	var empty: Dictionary = Campfire.build_slot_view({"exists": false}, 1)
	assert_eq(empty["title"], "— Empty —")
	assert_eq(empty["tooltip"], "Slot 1: empty")
	assert_eq(Campfire.format_play_time(22320.0), "6h 12m")
	Locale.set_language(Config.LANGUAGE_RU)
	assert_eq(Campfire.format_play_time(22320.0), "6ч 12м")


func test_translate_for_forces_language_independently() -> void:
	assert_eq(LocaleText.translate_for("en", "ui.common.ok"), "OK")
	assert_eq(LocaleText.translate_for("ru", "ui.common.ok"), "Ок")
	assert_eq(LocaleText.translate_for("en", "ui.saves.minutes", [3]), "3m")


# ------------------------------------------------------------------------------
# Нет хардкода текста в UI
# ------------------------------------------------------------------------------

func test_ui_scripts_have_no_cyrillic_string_literals() -> void:
	var files: Array[String] = []
	_collect_scripts(UI_DIR, files)
	assert_gt(files.size(), 20, "просканированы все UI-скрипты")
	var regex := RegEx.new()
	assert_eq(regex.compile(CYRILLIC_LITERAL), OK)
	for path: String in files:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			fail_test("не удалось открыть %s" % path)
			continue
		var line_number: int = 0
		while not file.eof_reached():
			var line: String = file.get_line()
			line_number += 1
			var trimmed: String = line.strip_edges()
			if trimmed.begins_with("#"):
				continue
			if (
				trimmed.contains("push_warning(")
				or trimmed.contains("push_error(")
				or trimmed.contains("printerr(")
				or trimmed.contains("print(")
			):
				continue
			if regex.search(line) != null:
				fail_test(
					"хардкод текста в %s:%d — используйте tr(key)" % [path, line_number]
				)


# ------------------------------------------------------------------------------
# Помощники
# ------------------------------------------------------------------------------

func _read_keys(path: String) -> Array[String]:
	var keys: Array[String] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail_test("CSV не найден: %s" % path)
		return keys
	var rows: Array = _parse_csv(file.get_as_text())
	if rows.is_empty():
		return keys
	for index: int in range(1, rows.size()):
		var row: Array = rows[index]
		if row.is_empty():
			continue
		keys.append(str(row[0]))
	keys.sort()
	return keys


## Минимальный CSV-парсер: кавычки, экранированные кавычки и переводы строк
## внутри значений (лор фракций, тексты концовок).
func _parse_csv(text: String) -> Array:
	var rows: Array = []
	var row: Array[String] = []
	var field: String = ""
	var in_quotes: bool = false
	var index: int = 0
	while index < text.length():
		var ch: String = text[index]
		if in_quotes:
			if ch == "\"":
				if index + 1 < text.length() and text[index + 1] == "\"":
					field += "\""
					index += 2
					continue
				in_quotes = false
				index += 1
				continue
			field += ch
			index += 1
			continue
		if ch == "\"":
			in_quotes = true
		elif ch == ",":
			row.append(field)
			field = ""
		elif ch == "\n":
			row.append(field)
			rows.append(row.duplicate())
			row.clear()
			field = ""
		elif ch != "\r":
			field += ch
		index += 1
	if not field.is_empty() or not row.is_empty():
		row.append(field)
		rows.append(row.duplicate())
	return rows


func _collect_scripts(directory: String, result: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var path: String = directory.path_join(entry)
		if dir.current_is_dir():
			_collect_scripts(path, result)
		elif entry.ends_with(".gd"):
			result.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
