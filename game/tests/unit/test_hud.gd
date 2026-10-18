extends GutTest
## T-19: HUD — HP/выносливость/способности/валюта/зона/подсказки/босс-панель.
##
## Проверяем acceptance T-19 на живой сцене `res://ui/hud/HUD.tscn`:
##   * HP/выносливость/способности/валюта/очки отражают GameState в реальном
##     времени (сигналы EventBus + поллинг валюты);
##   * 0 выносливости → «НЕТ СИЛ» + «!» (AC-03.3), HP<25% → мигание + кайма,
##     отключаемые `Config.no_flash` (DESIGN §6.3/§9.3);
##   * закрытая способность — замок, кулдаун dash — полоса (AC-02.2);
##   * панель босса: метки фаз 33/66 % и «ФАЗА II» (AC-03.4);
##   * контент HUD внутри safe-зоны 8 px, 8-px текст читаем (DESIGN §4.1).

const HUD_SCENE := preload("res://ui/hud/HUD.tscn")

var hud: AshenHUD
var _saved_hp: float = 0.0
var _saved_no_flash: bool = false
var _saved_device: String = "keyboard"


func before_each() -> void:
	_saved_hp = GameState.hp
	_saved_no_flash = Config.no_flash
	_saved_device = InputManager.active_device

	GameState.clear_abilities()
	GameState.currency = 0
	GameState.reset_stamina()
	Config.no_flash = false
	InputManager.active_device = "keyboard"

	hud = HUD_SCENE.instantiate() as AshenHUD
	add_child_autofree(hud)


func after_each() -> void:
	GameState.clear_abilities()
	GameState.currency = 0
	GameState.reset_stamina()
	GameState.restore_hp(_saved_hp)
	Config.no_flash = _saved_no_flash
	InputManager.active_device = _saved_device


# ------------------------------------------------------------------------------
# Слой и геометрия (PLAN §2.3, safe-zone 8 px)
# ------------------------------------------------------------------------------

func test_hud_scene_root_is_canvas_layer_10() -> void:
	assert_true(hud is CanvasLayer, "HUD — CanvasLayer (PLAN §2.3)")
	assert_eq(hud.layer, 10, "слой HUD = 10")
	assert_not_null(hud.get_root_control())
	assert_eq(hud.get_root_control().size, Vector2(480, 270), "кадр 480×270")


func test_hud_content_stays_inside_safe_area() -> void:
	await wait_process_frames(1)
	hud.set_prompt(&"interact", "Осмотреть")
	var safe := Rect2(
		Vector2(UITokens.SAFE_MARGIN, UITokens.SAFE_MARGIN),
		Vector2(480 - UITokens.SAFE_MARGIN * 2, 270 - UITokens.SAFE_MARGIN * 2)
	)
	var controls: Array[Control] = [
		hud.get_portrait(),
		hud.get_level_plate(),
		hud.get_hp_bar(),
		hud.get_stamina_bar(),
		hud.get_minimap_panel(),
		hud.get_zone_label(),
		hud.get_wallet(),
		hud.get_ability_hint_panel(),
		hud.get_prompt_panel(),
		hud.get_boss_bar(),
	]
	controls.append_array(hud.get_ability_slots())
	controls.append_array(hud.get_quick_slots())

	for control: Control in controls:
		var rect: Rect2 = control.get_global_rect()
		assert_true(
			safe.encloses(rect),
			"%s вне safe-зоны 8 px: %s" % [control.name, rect]
		)


# ------------------------------------------------------------------------------
# HP (AC-03.3, DESIGN §6.3)
# ------------------------------------------------------------------------------

func test_health_reflects_game_state_in_real_time() -> void:
	GameState.set_hp(74)
	assert_almost_eq(hud.get_hp_bar().value, 74.0, 0.01, "HP-шкала читает GameState.hp")
	assert_almost_eq(hud.get_hp_bar().max_value, 100.0, 0.01, "максимум из GameState")
	assert_false(hud.is_critical())

	GameState.damage_hp(14)
	assert_almost_eq(hud.get_hp_bar().value, 60.0, 0.01, "урон обновляет шкалу сразу")

	GameState.heal_hp(5)
	assert_almost_eq(hud.get_hp_bar().value, 65.0, 0.01, "лечение обновляет шкалу сразу")


func test_low_health_blinks_and_shows_edge_without_flash_mode() -> void:
	GameState.set_hp(20)
	assert_true(hud.is_critical(), "HP < 25 % — критично")
	assert_true(hud.get_critical_edge().visible, "ступенчатая кайма по краю")
	assert_true(hud.get_critical_label().visible, "подпись «КРИТИЧНО» — не только цвет")

	hud.advance_visuals(0.6)
	assert_true(hud.is_critical_blinking())
	assert_lt(hud.get_hp_bar().modulate.a, 1.0, "шкала мигает 1 Гц ступенями")

	Config.no_flash = true
	hud.advance_visuals(0.1)
	assert_almost_eq(hud.get_hp_bar().modulate.a, 1.0, 0.001, "«Без мигания» — без мерцания")
	assert_true(hud.get_critical_edge().visible, "статичная кайма остаётся")
	assert_true(hud.get_critical_label().visible, "статичная подпись остаётся")


# ------------------------------------------------------------------------------
# Выносливость (AC-03.3)
# ------------------------------------------------------------------------------

func test_stamina_reflects_game_state_and_exhausted_badge() -> void:
	GameState.stamina = 58
	assert_almost_eq(hud.get_stamina_bar().value, 58.0, 0.01, "шкала выносливости")
	assert_false(hud.is_no_stamina_visible())

	GameState.stamina = 0
	assert_true(GameState.is_stamina_exhausted())
	assert_true(hud.get_stamina_bar().is_exhausted())
	assert_true(hud.is_no_stamina_visible(), "0 → «НЕТ СИЛ» (AC-03.3)")
	assert_eq(hud.get_no_stamina_text(), "НЕТ СИЛ")
	assert_eq(hud.get_stamina_bar().get_state_text(), "НЕТ СИЛ")

	GameState.reset_stamina()
	assert_false(hud.is_no_stamina_visible())


# ------------------------------------------------------------------------------
# Способности и кулдаун (AC-02.1/02.2)
# ------------------------------------------------------------------------------

func test_closed_ability_has_lock_until_acquired() -> void:
	var slots: Array[AshenSlot] = hud.get_ability_slots()
	assert_eq(slots.size(), 3, "три слота способностей")

	var double_jump: AshenSlot = hud.get_ability_slot(&"double_jump")
	assert_not_null(double_jump)
	assert_eq(double_jump.state, AshenSlot.State.UNAVAILABLE)
	assert_true(double_jump.has_lock_marker(), "закрытая способность — замок")

	GameState.add_ability(&"double_jump")
	assert_eq(double_jump.state, AshenSlot.State.NORMAL, "получение открывает слот")
	assert_false(double_jump.has_lock_marker())
	assert_not_null(double_jump.item_icon, "у double_jump есть иконка")
	assert_string_contains(double_jump.tooltip_text, "ДВОЙНОЙ ПРЫЖОК")

	assert_eq(
		hud.get_ability_slot(&"wall_climb").state,
		AshenSlot.State.UNAVAILABLE,
		"остальные способности остаются закрытыми"
	)


func test_dash_cooldown_is_shown_as_strip() -> void:
	hud.start_ability_cooldown(&"dash", 0.6)
	assert_true(hud.is_cooldown_active(&"dash"), "кулдаун запущен (AC-02.2)")
	assert_almost_eq(hud.get_cooldown_ratio(&"dash"), 1.0, 0.001)
	var strip: Control = hud.get_cooldown_strip(&"dash")
	assert_not_null(strip)
	assert_true(strip.visible, "полоса кулдауна видна")

	hud.advance_cooldowns(0.3)
	assert_almost_eq(hud.get_cooldown_ratio(&"dash"), 0.5, 0.01, "полоса убывает")

	hud.advance_cooldowns(0.3)
	assert_false(hud.is_cooldown_active(&"dash"))
	assert_false(strip.visible, "после кулдауна полоса скрыта")


func test_cooldown_signal_contract_for_t07() -> void:
	EventBus.ability_cooldown_changed.emit(&"dash", 0.3, 0.6)
	assert_true(hud.is_cooldown_active(&"dash"))
	assert_almost_eq(hud.get_cooldown_ratio(&"dash"), 0.5, 0.01)
	EventBus.ability_cooldown_changed.emit(&"dash", 0.0, 0.6)
	assert_false(hud.is_cooldown_active(&"dash"))


# ------------------------------------------------------------------------------
# Быстрые слоты, валюта, очки обучения (T-21/T-29)
# ------------------------------------------------------------------------------

func test_quick_slots_are_stubs_with_key_hints() -> void:
	var slots: Array[AshenSlot] = hud.get_quick_slots()
	assert_eq(slots.size(), 4, "4 быстрых слота")
	for index: int in slots.size():
		assert_eq(slots[index].state, AshenSlot.State.EMPTY, "пустой слот")
		assert_eq(slots[index].key_hint, str(index + 1))

	assert_true(hud.set_quick_slot(0, &"potion", 3), "слот заполняется (контракт T-21)")
	assert_eq(hud.get_quick_slot(0).count, 3)
	assert_eq(hud.get_quick_slot(0).state, AshenSlot.State.NORMAL)
	assert_false(hud.set_quick_slot(9, &"potion", 1), "неверный индекс — без падения")


func test_currency_and_training_points_reflect_state() -> void:
	GameState.currency = 1240
	hud.advance_visuals(0.0)
	assert_eq(hud.get_currency_text(), "1 240", "валюта в реальном времени (поллинг)")

	GameState.currency = 0
	hud.advance_visuals(0.0)
	assert_eq(hud.get_currency_text(), "0")

	hud.set_training_points(3)
	assert_eq(hud.get_training_points_text(), "ОП 3", "очки обучения — заглушка T-29")

	hud.set_level(7)
	assert_eq(hud.get_level_text(), "УР7", "уровень — заглушка T-29")


# ------------------------------------------------------------------------------
# Зона, мини-карта, подсказки
# ------------------------------------------------------------------------------

func test_zone_name_and_minimap_stub_contract() -> void:
	EventBus.zone_entered.emit(&"zone_02_swamp", "Болото")
	assert_eq(hud.get_zone_text(), "Болото", "название зоны из zone_entered")

	var minimap: Control = hud.get_minimap()
	assert_not_null(minimap, "мини-карта-заглушка до T-33")
	hud.set_minimap_data({"player_room": Vector2i(2, 0), "rooms": [Rect2i(0, 0, 8, 6)]})
	assert_eq(hud.get_minimap_data().get("player_room"), Vector2i(2, 0))
	hud.set_minimap_data({})
	assert_true(hud.get_minimap_data().is_empty(), "битые/пустые данные не роняют HUD")


func test_context_prompt_switches_glyph_by_active_device() -> void:
	assert_false(hud.is_prompt_visible(), "подсказка скрыта по умолчанию")

	hud.set_prompt(&"interact", "Осмотреть")
	assert_true(hud.is_prompt_visible())
	assert_eq(hud.get_prompt_text(), "Осмотреть")

	var kbd: AshenKbd = hud.get_prompt().get_kbd()
	assert_eq(kbd.action, &"interact")
	assert_eq(kbd.get_glyph(), "E", "клавиатура: клавиша из InputMap")

	InputManager.active_device = "xbox"
	kbd.refresh()
	assert_eq(kbd.get_glyph(), "Y", "Xbox: глиф кнопки Y (EC-08)")

	InputManager.active_device = "keyboard"
	kbd.refresh()
	assert_eq(kbd.get_glyph(), "E")


func test_ability_hint_api_and_auto_hide_after_acquire() -> void:
	assert_false(hud.is_ability_hint_visible())

	hud.show_ability_hint(&"double_jump")
	assert_true(hud.is_ability_hint_visible(), "подсказка «Нужно: …» (AC-02.4)")
	assert_eq(hud.get_ability_hint_text(), "ДВОЙНОЙ ПРЫЖОК")

	GameState.add_ability(&"double_jump")
	assert_false(hud.is_ability_hint_visible(), "после получения способности подсказка гаснет")

	GameState.clear_abilities()
	EventBus.ability_hint_changed.emit(&"dash", true)
	assert_true(hud.is_ability_hint_visible(), "контракт T-09: сигнал показывает подсказку")
	assert_eq(hud.get_ability_hint_text(), "РЫВОК")

	EventBus.ability_hint_changed.emit(&"dash", false)
	assert_false(hud.is_ability_hint_visible(), "контракт T-09: сигнал скрывает подсказку")


# ------------------------------------------------------------------------------
# Панель босса (AC-03.4)
# ------------------------------------------------------------------------------

func test_boss_bar_hidden_outside_fight() -> void:
	var boss: AshenBossBar = hud.get_boss_bar()
	assert_not_null(boss)
	assert_false(boss.is_fight_visible(), "панель скрыта вне боя")
	assert_false(boss.visible)


func test_boss_bar_health_phase_marks_and_phase_notice() -> void:
	var boss: AshenBossBar = hud.get_boss_bar()
	EventBus.boss_fight_started.emit(
		&"zone_01_boss",
		"ПЕПЕЛЬНЫЙ ПАЛАЧ",
		240.0,
		PackedFloat32Array([0.66, 0.33])
	)
	assert_true(boss.is_fight_visible(), "бой начался — панель видна")
	assert_eq(boss.display_name, "ПЕПЕЛЬНЫЙ ПАЛАЧ")
	assert_eq(boss.get_name_text(), "ПЕПЕЛЬНЫЙ ПАЛАЧ")
	assert_almost_eq(boss.get_bar().max_value, 240.0, 0.01)

	var marks: PackedFloat32Array = boss.get_phase_marks()
	assert_eq(marks.size(), 2, "метки фаз 33 % / 66 %")
	assert_almost_eq(marks[0], 0.66, 0.001)
	assert_almost_eq(marks[1], 0.33, 0.001)
	assert_true(
		UITokens.BOSS_PHASE_MARKS.has(0.33) and UITokens.BOSS_PHASE_MARKS.has(0.66),
		"пороги фаз из токенов"
	)

	EventBus.boss_health_changed.emit(&"zone_01_boss", 120.0, 240.0)
	assert_almost_eq(boss.get_bar().value, 120.0, 0.01, "HP босса обновляется")

	EventBus.boss_phase_changed.emit(&"zone_01_boss", 1, "Палач разъярён")
	assert_true(boss.is_notice_visible(), "уведомление смены фазы")
	assert_eq(boss.get_notice_text(), "ФАЗА II", "AC-03.4")
	assert_eq(boss.get_notice_subtitle(), "Палач разъярён")
	assert_string_contains(boss.get_phase_text(), "II")

	boss.advance(AshenBossBar.NOTICE_TIME + 0.1)
	assert_false(boss.is_notice_visible(), "уведомление гаснет по таймеру")

	EventBus.boss_defeated.emit(&"zone_01_boss", &"zone_01_village", Vector2.ZERO)
	assert_false(boss.is_fight_visible(), "после победы панель скрыта")


func test_boss_panel_hides_prompt_during_fight() -> void:
	hud.set_prompt(&"interact", "Осмотреть")
	assert_true(hud.is_prompt_visible())

	EventBus.boss_fight_started.emit(
		&"zone_01_boss",
		"ПЕПЕЛЬНЫЙ ПАЛАЧ",
		240.0,
		PackedFloat32Array([0.66, 0.33])
	)
	assert_false(hud.is_prompt_visible(), "в бою контекстная подсказка скрыта (макет)")

	EventBus.boss_defeated.emit(&"zone_01_boss", &"zone_01_village", Vector2.ZERO)
	assert_true(hud.is_prompt_visible(), "после боя подсказка возвращается")


# ------------------------------------------------------------------------------
# Читаемость (NFR §7.2, DESIGN §4.1/§9.1)
# ------------------------------------------------------------------------------

func test_text_tokens_are_readable_at_8px() -> void:
	assert_eq(UITokens.FONT_BODY, 8, "базовый текст 8 px")
	assert_eq(UITokens.FONT_BODY * 2, 16, "на 1280×720 (×2) — 16 px")
	assert_true(UITokens.is_readable(UITokens.BONE, UITokens.NIGHT_9), "bone на night-9")
	assert_true(UITokens.is_readable(UITokens.STONE_5, UITokens.NIGHT_9), "stone-5 на night-9")
	assert_true(UITokens.is_readable(UITokens.BLOOD_5, UITokens.NIGHT_9), "blood-5 на night-9")
	assert_eq(
		hud.get_critical_label().get_theme_font_size("font_size"),
		UITokens.FONT_BODY,
		"подпись «КРИТИЧНО» — 8 px"
	)
