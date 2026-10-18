extends Control
## ComponentShowcase — витрина UI-компонентов T-18 (dev-сцена, не входит в Main).
##
## Назначение: наглядно показать все состояния компонентов и доказать
## переиспользование (каждый компонент применён ≥ 2 раз). Скрипт собирает
## HUD-кластер, меню, инвентарь с вкладками и два диалога.
##
## Запуск: godot --path game res://ui/components/showcase/ComponentShowcase.tscn

var _focus_target: AshenMenuItem


func _ready() -> void:
	theme = UIStyle.theme()
	_build_hud()
	_build_menu()
	_build_toasts()
	_build_inventory()
	_build_dialogs()
	_build_prompts()
	await get_tree().process_frame
	if _focus_target != null and is_instance_valid(_focus_target):
		_focus_target.grab_focus()


func _build_hud() -> void:
	var hud := _add_panel(UIStyle.PanelVariant.SOLID, Vector2(8, 8), Vector2(320, 104))
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(300, 92)
	hud.add_child(inner)

	var portrait := AshenPanel.new()
	portrait.variant = UIStyle.PanelVariant.INSET
	portrait.padding = UITokens.SP_1
	portrait.position = Vector2.ZERO
	portrait.size = Vector2(UITokens.PORTRAIT_HUD, UITokens.PORTRAIT_HUD)
	inner.add_child(portrait)
	var level := _make_label("УР7", "GoldLabel")
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(level)

	var hp := AshenBar.new()
	hp.kind = AshenBar.Kind.HP
	hp.position = Vector2(36, 0)
	hp.size = UITokens.BAR_HP_SIZE
	hp.set_values(74, 100)
	inner.add_child(hp)

	var stamina := AshenBar.new()
	stamina.kind = AshenBar.Kind.STAMINA
	stamina.position = Vector2(36, 16)
	stamina.size = UITokens.BAR_STAMINA_SIZE
	stamina.set_values(0, 80)
	inner.add_child(stamina)

	var quick_states := [
		AshenSlot.State.SELECTED,
		AshenSlot.State.NORMAL,
		AshenSlot.State.EMPTY,
		AshenSlot.State.UNAVAILABLE,
	]
	var quick_counts := [3, 5, -1, -1]
	var quick_keys := ["1", "2", "3", "4"]
	for index in quick_states.size():
		var slot := AshenSlot.new()
		slot.state = quick_states[index]
		slot.count = quick_counts[index]
		slot.key_hint = quick_keys[index]
		slot.position = Vector2(36 + index * 25, 36)
		slot.size = Vector2(UITokens.SLOT_HUD, UITokens.SLOT_HUD)
		inner.add_child(slot)

	var wallet := AshenPanel.new()
	wallet.variant = UIStyle.PanelVariant.GLASS
	wallet.padding = UITokens.SP_1
	wallet.position = Vector2(180, 0)
	wallet.size = Vector2(112, 44)
	inner.add_child(wallet)
	var wallet_column := VBoxContainer.new()
	wallet_column.add_theme_constant_override("separation", UITokens.SP_1)
	wallet.add_child(wallet_column)
	wallet_column.add_child(_make_label("МОНЕТЫ 1 240", "GoldLabel"))
	wallet_column.add_child(_make_label("ОП 3", "MutedLabel"))
	wallet_column.add_child(_make_label("ЗОНА 1 · ХАБ", "MutedLabel"))


func _build_menu() -> void:
	var menu := _add_panel(UIStyle.PanelVariant.SOLID, Vector2(8, 120), Vector2(216, 172))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	menu.add_child(column)

	var continue_item := _make_menu_item("Продолжить", true, "Нет сохранений")
	column.add_child(continue_item)

	_focus_target = _make_menu_item("Новая игра")
	column.add_child(_focus_target)

	column.add_child(_make_menu_item("Загрузить"))
	column.add_child(_make_menu_item("Настройки"))

	var toggle := _make_menu_item("Субтитры звуков")
	toggle.is_toggle = true
	toggle.button_pressed = true
	column.add_child(toggle)

	column.add_child(_make_menu_item("Выход"))

	var hint := _make_label("↑ ↓ · выбрать    Enter · ок", "MutedLabel")
	column.add_child(hint)


func _build_toasts() -> void:
	var saved := AshenToast.new()
	saved.position = Vector2(488, 8)
	saved.custom_minimum_size = Vector2(300, UITokens.TOAST_MIN_HEIGHT)
	add_child(saved)
	saved.show_message("СОХРАНЕНО · СЛОТ 1", AshenToast.Kind.SUCCESS, 0.0)

	var danger := AshenToast.new()
	danger.position = Vector2(488, 36)
	danger.custom_minimum_size = Vector2(300, UITokens.TOAST_MIN_HEIGHT)
	add_child(danger)
	danger.show_message("Сохранение в бою запрещено", AshenToast.Kind.DANGER, 0.0)


func _build_inventory() -> void:
	var inventory := _add_panel(UIStyle.PanelVariant.SOLID, Vector2(8, 304), Vector2(432, 224))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITokens.SP_2)
	inventory.add_child(column)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", UITokens.SP_1)
	column.add_child(tabs)
	var tab_titles := ["ЭКИПИРОВКА", "ИНВЕНТАРЬ", "ФРАКЦИИ"]
	for index in tab_titles.size():
		var tab := AshenTab.new()
		tab.text = tab_titles[index]
		tab.selected = index == 0
		tab.custom_minimum_size = Vector2(128, UITokens.TAB_HEIGHT)
		tabs.add_child(tab)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", UITokens.SLOT_GAP)
	grid.add_theme_constant_override("v_separation", UITokens.SLOT_GAP)
	column.add_child(grid)

	var states := [
		AshenSlot.State.SELECTED,
		AshenSlot.State.EQUIPPED,
		AshenSlot.State.REQUIREMENTS,
		AshenSlot.State.UNAVAILABLE,
		AshenSlot.State.NORMAL,
		AshenSlot.State.NORMAL,
		AshenSlot.State.EMPTY,
		AshenSlot.State.EMPTY,
	]
	for index in states.size():
		var slot := AshenSlot.new()
		slot.slot_size = UITokens.SLOT_INV
		slot.state = states[index]
		slot.requirement_delta = 2 if states[index] == AshenSlot.State.REQUIREMENTS else 0
		slot.count = index + 1 if states[index] == AshenSlot.State.NORMAL else -1
		grid.add_child(slot)

	column.add_child(_make_label("Требования: НЕТ · ещё 2", "DangerLabel"))
	column.add_child(_make_label("Надето: меч · 12 урона", "SteelLabel"))


func _build_dialogs() -> void:
	var first := _add_dialog(
		Vector2(488, 72),
		"Хранитель Огня",
		"Пламя помнит тех, кто возвращается. Дать ему запомнить и тебя?",
		[
			{"text": "Сохранить игру"},
			{"text": "О Болоте"},
			{"text": "Клятва", "tag": "[Орден+1]"},
			{"text": "Уйти", "tag": "", "disabled": false},
		],
		"Орден Пепла"
	)

	var second := _add_dialog(
		Vector2(488, 184),
		"Хранитель Огня",
		"Не здесь, путник. Пока рядом враги, пламя не примет клятву.",
		[
			{"text": "Сохранить игру", "disabled": true, "reason": "Рядом враги"},
			{"text": "Повторить"},
			{"text": "Другой слот"},
			{"text": "Отмена"},
		],
		"Орден Пепла"
	)
	second.instant_text = true

func _build_prompts() -> void:
	var prompt_one := AshenPrompt.new()
	prompt_one.position = Vector2(488, 300)
	add_child(prompt_one)
	prompt_one.setup(&"interact", "Осмотреть")

	var prompt_two := AshenPrompt.new()
	prompt_two.position = Vector2(488, 320)
	add_child(prompt_two)
	prompt_two.setup(&"jump", "Прыжок")

	var raw_kbd := AshenKbd.new()
	raw_kbd.position = Vector2(488, 344)
	raw_kbd.action = &"attack"
	add_child(raw_kbd)

	var raw_kbd_pad := AshenKbd.new()
	raw_kbd_pad.position = Vector2(508, 344)
	raw_kbd_pad.action = &"dash"
	raw_kbd_pad.device_override = AshenKbd.DEVICE_PLAYSTATION
	add_child(raw_kbd_pad)


func _add_panel(variant: int, position: Vector2, panel_size: Vector2) -> AshenPanel:
	var panel := AshenPanel.new()
	panel.variant = variant
	panel.position = position
	panel.size = panel_size
	add_child(panel)
	return panel


func _add_dialog(
	position: Vector2,
	display_name: String,
	text: String,
	answers: Array,
	faction: String
) -> AshenDialog:
	var dialog := AshenDialog.new()
	dialog.instant_text = true
	dialog.position = position
	dialog.size = UITokens.DIALOG_SIZE
	add_child(dialog)
	dialog.setup(display_name, text, answers, faction)
	return dialog


func _make_menu_item(label_text: String, disabled: bool = false, reason: String = "") -> AshenMenuItem:
	var item := AshenMenuItem.new()
	item.text = label_text
	item.font_size = UITokens.FONT_BODY
	item.disabled = disabled
	item.disabled_reason = reason
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item


func _make_label(label_text: String, variation: String = "MutedLabel") -> Label:
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = StringName(variation)
	return label
