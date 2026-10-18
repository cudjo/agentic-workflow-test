extends GutTest
## T-18: тесты состояний UI-компонентов (DESIGN §6), фокуса (a11y §9.2)
## и переиспользования (витрина ComponentShowcase).

const SHOWCASE_PATH := "res://ui/components/showcase/ComponentShowcase.tscn"


# ------------------------------------------------------------------------------
# Bar
# ------------------------------------------------------------------------------

func test_bar_hp_geometry_segments_and_number_state() -> void:
	var bar := AshenBar.new()
	bar.kind = AshenBar.Kind.HP
	bar.size = UITokens.BAR_HP_SIZE
	add_child_autofree(bar)
	bar.set_values(74, 100)

	assert_eq(bar.custom_minimum_size, UITokens.BAR_HP_SIZE)
	assert_eq(bar.get_segment_count(), 27, "112 px: (108+1)/4 = 27 сегментов")
	assert_eq(bar.get_filled_segments(), 20, "74% от 27 ≈ 20 сегментов")
	assert_false(bar.is_critical())
	assert_eq(bar.get_state_text(), "")


func test_bar_hp_critical_state_is_duplicated_by_text() -> void:
	var bar := AshenBar.new()
	bar.kind = AshenBar.Kind.HP
	bar.size = UITokens.BAR_HP_SIZE
	add_child_autofree(bar)
	bar.set_values(20, 100)

	assert_true(bar.is_critical(), "HP < 25% — критично")
	assert_eq(bar.get_state_text(), "КРИТИЧНО", "состояние не только цветом")
	assert_eq(bar.get_fill_colors()[0], UITokens.BLOOD_3)


func test_bar_stamina_exhausted_state_and_geometry() -> void:
	var bar := AshenBar.new()
	bar.kind = AshenBar.Kind.STAMINA
	bar.size = UITokens.BAR_STAMINA_SIZE
	add_child_autofree(bar)
	bar.set_values(0, 80)

	assert_eq(bar.custom_minimum_size, UITokens.BAR_STAMINA_SIZE)
	assert_eq(bar.get_segment_count(), 23, "96 px: (92+1)/4 = 23 сегмента")
	assert_eq(bar.get_filled_segments(), 0)
	assert_true(bar.is_exhausted(), "AC-03.3: 0 выносливости")
	assert_eq(bar.get_state_text(), "НЕТ СИЛ", "подпись дублирует состояние")
	assert_eq(bar.get_fill_colors()[0], UITokens.STEEL_3)


func test_bar_boss_phase_marks_derive_phases() -> void:
	var bar := AshenBar.new()
	bar.kind = AshenBar.Kind.BOSS
	bar.size = UITokens.BAR_BOSS_SIZE
	add_child_autofree(bar)
	assert_eq(bar.custom_minimum_size, UITokens.BAR_BOSS_SIZE)

	bar.set_values(80, 100)
	assert_eq(bar.get_phase(), 1)
	bar.set_values(50, 100)
	assert_eq(bar.get_phase(), 2)
	bar.set_values(20, 100)
	assert_eq(bar.get_phase(), 3)


func test_bar_damage_trail_drains_in_steps() -> void:
	var bar := AshenBar.new()
	bar.kind = AshenBar.Kind.HP
	bar.size = UITokens.BAR_HP_SIZE
	add_child_autofree(bar)
	bar.set_values(100, 100)
	bar.set_values(50, 100)

	var before: int = bar.get_trail_segments()
	assert_gte(before, bar.get_filled_segments(), "след урона не короче заливки")

	bar.advance_trail(UITokens.DAMAGE_TRAIL_STEP * 5.0)
	var after: int = bar.get_trail_segments()
	assert_lt(after, before, "след убывает ступенями")
	assert_gte(after, bar.get_filled_segments())

	for index in 100:
		bar.advance_trail(UITokens.DAMAGE_TRAIL_STEP)
	assert_almost_eq(bar.get_trail_ratio(), bar.get_ratio(), 0.001)


# ------------------------------------------------------------------------------
# Slot
# ------------------------------------------------------------------------------

func test_slot_states_have_shape_markers_not_only_color() -> void:
	var slot := AshenSlot.new()
	slot.slot_size = UITokens.SLOT_INV
	slot.size = Vector2(UITokens.SLOT_INV, UITokens.SLOT_INV)
	add_child_autofree(slot)

	assert_eq(slot.get_border_color(), UITokens.STONE_9)

	slot.state = AshenSlot.State.SELECTED
	assert_eq(slot.get_border_color(), UITokens.GOLD)

	slot.state = AshenSlot.State.EQUIPPED
	assert_true(slot.has_equipped_marker(), "надет: золотой маркер-квадрат")
	assert_eq(slot.get_border_color(), UITokens.STONE_9)

	slot.state = AshenSlot.State.REQUIREMENTS
	slot.requirement_delta = 2
	assert_true(slot.has_requirement_marker(), "требования: значок «!»")
	assert_eq(slot.get_border_color(), UITokens.BLOOD_3)
	assert_string_contains(slot.tooltip_text, "ещё 2")

	slot.state = AshenSlot.State.UNAVAILABLE
	assert_true(slot.has_lock_marker(), "недоступно: замок")

	slot.state = AshenSlot.State.EMPTY
	assert_true(slot.is_empty(), "пустой: пунктирная рамка")


func test_slot_focus_is_always_visible() -> void:
	var slot := AshenSlot.new()
	slot.size = Vector2(UITokens.SLOT_HUD, UITokens.SLOT_HUD)
	add_child_autofree(slot)
	assert_eq(slot.focus_mode, Control.FOCUS_ALL)
	assert_false(slot.is_focus_visible())
	slot.grab_focus()
	await get_tree().process_frame
	assert_true(slot.is_focus_visible(), "фокус слота виден (рамка + скобки)")


# ------------------------------------------------------------------------------
# MenuItem / Tab
# ------------------------------------------------------------------------------

func test_menu_item_states_and_focus_caret() -> void:
	var item := AshenMenuItem.new()
	item.text = "Новая игра"
	item.font_size = UITokens.FONT_BODY
	item.size = Vector2(216, UITokens.ROW_MENU_BODY)
	add_child_autofree(item)
	item.size = Vector2(216, UITokens.ROW_MENU_BODY)

	assert_eq(item.get_row_height(), 16, "DESIGN §4.3: row-menu 16 px для 8-px шрифта")
	assert_eq(item.get_label_color(), UITokens.STONE_5)
	assert_eq(item.get_caret_text(), "")

	item.grab_focus()
	await get_tree().process_frame
	assert_true(item.is_focus_visible())
	assert_eq(item.get_caret_text(), ">", "золотая каретка при фокусе")
	assert_eq(item.get_label_color(), UITokens.BONE)


func test_menu_item_active_and_toggle_states() -> void:
	var item := AshenMenuItem.new()
	item.text = "Субтитры звуков"
	item.is_toggle = true
	item.button_pressed = true
	item.size = Vector2(216, UITokens.ROW_MENU_BODY)
	add_child_autofree(item)

	assert_true(item.is_active_state(), "toggle включён")
	assert_eq(item.get_label_color(), UITokens.VOID, "активный: текст void на gold")
	assert_eq(item.get_caret_text(), ">", "каретка void на активном фоне")


func test_menu_item_disabled_requires_and_shows_reason() -> void:
	var item := AshenMenuItem.new()
	item.text = "Продолжить"
	item.size = Vector2(216, UITokens.ROW_MENU_BODY)
	add_child_autofree(item)
	item.disabled = true
	item.disabled_reason = "Нет сохранений"

	assert_eq(item.get_label_color(), UITokens.STONE_3)
	assert_eq(item.tooltip_text, "Нет сохранений", "причина обязательна (DESIGN §6.1)")
	assert_false(item.is_focus_visible())
	assert_eq(item.get_caret_text(), "")


func test_tab_selected_and_focus_states() -> void:
	var tab := AshenTab.new()
	tab.text = "ИНВЕНТАРЬ"
	tab.selected = true
	tab.size = Vector2(128, UITokens.TAB_HEIGHT)
	add_child_autofree(tab)

	assert_eq(tab.get_label_color(), UITokens.GOLD_3, "выбранная вкладка — золото")
	tab.grab_focus()
	await get_tree().process_frame
	assert_true(tab.is_focus_visible(), "фокус вкладки виден рамкой 2 px")

	tab.selected = false
	assert_eq(tab.get_label_color(), UITokens.BONE, "фокус без выбора — bone")


# ------------------------------------------------------------------------------
# Toast
# ------------------------------------------------------------------------------

func test_toast_success_and_danger_kinds() -> void:
	var success := AshenToast.new()
	add_child_autofree(success)
	success.show_message("СОХРАНЕНО · СЛОТ 1", AshenToast.Kind.SUCCESS, 0.0)
	assert_true(success.visible)
	assert_eq(success.get_message(), "СОХРАНЕНО · СЛОТ 1")
	assert_eq(success.get_kind(), AshenToast.Kind.SUCCESS)
	assert_eq(success.get_text_color(), UITokens.BONE)

	var danger := AshenToast.new()
	add_child_autofree(danger)
	danger.show_message("Сохранение в бою запрещено", AshenToast.Kind.DANGER, 0.0)
	assert_true(danger.visible)
	assert_eq(danger.get_kind(), AshenToast.Kind.DANGER)
	assert_eq(danger.get_text_color(), UITokens.BLOOD_5, "текст опасности — blood-5")


func test_toast_auto_hides_after_one_second_budget() -> void:
	var toast := AshenToast.new()
	add_child_autofree(toast)
	toast.show_message("СОХРАНЕНО · СЛОТ 1", AshenToast.Kind.SUCCESS, 0.05)
	assert_true(toast.visible)
	await get_tree().create_timer(0.12).timeout
	assert_false(toast.visible, "тост скрывается по таймеру (AC-05.1 ≤ 1 с)")


# ------------------------------------------------------------------------------
# Dialog
# ------------------------------------------------------------------------------

func test_dialog_types_text_and_builds_2x2_answers() -> void:
	var dialog := AshenDialog.new()
	dialog.size = UITokens.DIALOG_SIZE
	add_child_autofree(dialog)
	dialog.setup(
		"Хранитель Огня",
		"Пламя помнит тех, кто возвращается.",
		[
			{"text": "Сохранить игру"},
			{"text": "О Болоте"},
			{"text": "Клятва", "tag": "[Орден+1]"},
			{"text": "Уйти"},
		],
		"Орден Пепла"
	)

	assert_eq(dialog.get_display_name(), "Хранитель Огня")
	assert_eq(dialog.get_answer_count(), 4)
	assert_eq(dialog.get_answer_columns(), 2, "ответы 2×2")
	assert_eq(dialog.get_answer_tag(2), "[Орден+1]", "тег последствия")
	assert_eq(dialog.get_answer_item(2).prefix_tag, "[Орден+1]")
	assert_true(dialog.is_typing(), "текст печатается 22 мс/символ")
	assert_eq(dialog.get_total_characters(), 35)
	assert_eq(dialog.get_visible_characters(), 0)

	dialog.advance_typing(UITokens.TYPE_SPEED * 3.0 + 0.001)
	assert_eq(dialog.get_visible_characters(), 3)
	assert_true(dialog.is_typing())

	watch_signals(dialog)
	dialog.reveal_all()
	assert_false(dialog.is_typing())
	assert_eq(dialog.get_visible_characters(), dialog.get_total_characters())

	dialog.select_answer(2)
	assert_signal_emitted_with_parameters(dialog, "choice_selected", [2])


func test_dialog_instant_text_for_no_flash_mode() -> void:
	var dialog := AshenDialog.new()
	dialog.instant_text = true
	dialog.size = UITokens.DIALOG_SIZE
	add_child_autofree(dialog)
	dialog.setup("Хранитель", "Сразу весь текст.", [{"text": "Продолжить"}])

	assert_false(dialog.is_typing(), "«Без мигания»: печать мгновенна (DESIGN §9.3)")
	assert_eq(dialog.get_visible_characters(), dialog.get_total_characters())
	assert_eq(dialog.get_visible_characters(), dialog.get_body_text().length())


func test_dialog_disabled_answer_keeps_reason() -> void:
	var dialog := AshenDialog.new()
	dialog.instant_text = true
	dialog.size = UITokens.DIALOG_SIZE
	add_child_autofree(dialog)
	dialog.setup(
		"Хранитель",
		"Не здесь, путник.",
		[{"text": "Сохранить игру", "disabled": true, "reason": "Рядом враги"}]
	)

	var item := dialog.get_answer_item(0)
	assert_true(item.disabled)
	assert_eq(item.disabled_reason, "Рядом враги")
	assert_eq(item.tooltip_text, "Рядом враги")


# ------------------------------------------------------------------------------
# Kbd / Prompt
# ------------------------------------------------------------------------------

func test_kbd_glyphs_follow_active_device() -> void:
	assert_eq(AshenKbd.glyph_for_action(&"interact", AshenKbd.DEVICE_KEYBOARD), "E")
	assert_eq(AshenKbd.glyph_for_action(&"interact", AshenKbd.DEVICE_XBOX), "Y")
	assert_eq(AshenKbd.glyph_for_action(&"interact", AshenKbd.DEVICE_PLAYSTATION), "△")
	assert_eq(AshenKbd.glyph_for_action(&"interact", AshenKbd.DEVICE_GENERIC), "Y")
	assert_eq(AshenKbd.glyph_for_action(&"jump", AshenKbd.DEVICE_KEYBOARD), "SPC")
	assert_eq(AshenKbd.glyph_for_action(&"move_left", AshenKbd.DEVICE_KEYBOARD), "A")


func test_kbd_control_uses_override_and_min_size() -> void:
	var kbd := AshenKbd.new()
	kbd.action = &"jump"
	kbd.device_override = AshenKbd.DEVICE_KEYBOARD
	add_child_autofree(kbd)

	assert_eq(kbd.get_glyph(), "SPC")
	assert_gte(kbd.custom_minimum_size.y, float(UITokens.KBD_HEIGHT))
	assert_false(kbd.is_gamepad_glyph())


func test_prompt_combines_glyph_and_text() -> void:
	var prompt := AshenPrompt.new()
	add_child_autofree(prompt)
	prompt.setup(&"interact", "Осмотреть")

	assert_eq(prompt.get_text(), "Осмотреть")
	assert_not_null(prompt.get_kbd())
	assert_eq(prompt.get_kbd().get_glyph(), "E")
	assert_eq(prompt.get_kbd().action, &"interact")


# ------------------------------------------------------------------------------
# Переиспользование (витрина)
# ------------------------------------------------------------------------------

func test_showcase_uses_every_component_at_least_twice() -> void:
	var scene := load(SHOWCASE_PATH) as PackedScene
	assert_not_null(scene)
	var showcase := scene.instantiate()
	add_child_autofree(showcase)
	await get_tree().process_frame
	await get_tree().process_frame

	var counts := {
		"panel": 0,
		"bar": 0,
		"slot": 0,
		"menu_item": 0,
		"tab": 0,
		"toast": 0,
		"dialog": 0,
		"kbd": 0,
		"prompt": 0,
	}
	_count_components(showcase, counts)
	for component_name in counts:
		assert_gte(
			counts[component_name],
			2,
			"компонент %s применён %d раз(а), нужно ≥ 2" % [component_name, counts[component_name]]
		)


func _count_components(node: Node, counts: Dictionary) -> void:
	if node is AshenPanel:
		counts["panel"] += 1
	elif node is AshenBar:
		counts["bar"] += 1
	elif node is AshenSlot:
		counts["slot"] += 1
	elif node is AshenMenuItem:
		counts["menu_item"] += 1
	elif node is AshenTab:
		counts["tab"] += 1
	elif node is AshenToast:
		counts["toast"] += 1
	elif node is AshenDialog:
		counts["dialog"] += 1
	elif node is AshenKbd:
		counts["kbd"] += 1
	elif node is AshenPrompt:
		counts["prompt"] += 1
	for child in node.get_children():
		_count_components(child, counts)
