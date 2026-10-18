extends GutTest
## T-28 — NPC, диалоги и торговцы (US-06, AC-06.1/06.2, EC-11).
##
## Покрытие:
##   * данные `data/dialogue/*.tres` и `data/quests/*.tres` (валидный граф,
##     RU/EN, 52×52-портрет, условия по репутации/квестам);
##   * движок: печать/страницы, 2×2 ответы, условия узлов и ответов,
##     fallback-узел, теги `[Фракция±N]` и фактическое изменение репутации;
##   * квесты: выдача с EC-11, завершение с журналом/опытом/репутацией,
##     идемпотентность;
##   * торговец: недоступен при низкой репутации с причиной (AC-06.2),
##     открывается при пороге, покупка не проходит без доступа;
##   * UI: `AshenDialog` T-18 (2 колонки, печать 22 мс), фокус/соседи для
##     клавиатуры и геймпада, длинный RU/EN-текст помещается в бокс.

const ELDER: StringName = &"elder_lira"
const TRADER: StringName = &"quartermaster_helga"
const GUARD: StringName = &"order_guard"

const FREE_QUEST: StringName = &"quest_free_smuggle"
const ORDER_QUEST: StringName = &"quest_clear_swamp"

var _factions: Dictionary = {}
var _chosen: StringName = &""
var _xp: int = 0
var _level: int = 1
var _learning_points: int = 0
var _currency: int = 0
var _inventory: Array[StringName] = []


func before_each() -> void:
	_factions = GameState.get_all_faction_reputation()
	_chosen = GameState.chosen_faction
	_xp = GameState.xp
	_level = GameState.level
	_learning_points = GameState.learning_points
	_currency = GameState.currency
	_inventory = GameState.get_inventory()

	FactionManager.reset_state()
	Journal.reset_state()
	DialogueCatalog.clear_cache()
	QuestService.clear_cache()


func after_each() -> void:
	GameState.restore_factions(_factions, _chosen)
	GameState.xp = _xp
	GameState.level = _level
	GameState.learning_points = _learning_points
	GameState.currency = _currency
	GameState.restore_inventory(_inventory)
	Journal.reset_state()


# ------------------------------------------------------------------------------
# Data
# ------------------------------------------------------------------------------

func test_catalog_loads_three_valid_dialogues_with_ru_en_texts() -> void:
	var ids: Array[StringName] = DialogueCatalog.get_dialogue_ids()
	assert_eq(ids.size(), 3, "all dialogue resources are registered")
	assert_true(ids.has(ELDER))
	assert_true(ids.has(TRADER))
	assert_true(ids.has(GUARD))

	for dialogue_id: StringName in ids:
		var data: DialogueData = DialogueCatalog.load_dialogue(dialogue_id)
		assert_not_null(data, "%s loads" % dialogue_id)
		if data == null:
			continue
		assert_true(data.is_valid(), "%s has a valid graph" % dialogue_id)
		assert_true(FactionManager.has_faction(data.faction_id), "faction exists")
		assert_false(data.display_name.is_empty())
		assert_ne(data.display_name, data.display_name_en, "RU and EN names differ")
		assert_not_null(data.get_start_node(), "start node exists")

		for node: DialogueNode in data.nodes:
			assert_false(node.get_text("ru").strip_edges().is_empty())
			assert_false(node.get_text("en").strip_edges().is_empty())
			assert_true(node.answers.size() <= 4, "2×2 ответа — не больше четырёх")


func test_quest_data_is_present_and_has_xp_in_progression() -> void:
	var quest_ids: Array[StringName] = QuestService.get_quest_ids()
	assert_eq(quest_ids.size(), 4, "four faction quests are described")
	for quest_id: StringName in quest_ids:
		var data: QuestData = QuestService.get_quest(quest_id)
		assert_not_null(data, "%s loads" % quest_id)
		if data == null:
			continue
		assert_true(data.is_valid())
		assert_false(data.get_title("ru").is_empty())
		assert_false(data.get_title("en").is_empty())
		assert_gt(
			GameState.progression_data.get_quest_xp(quest_id),
			0,
			"%s has quest XP" % quest_id
		)


func test_invalid_next_node_is_rejected() -> void:
	var node := DialogueNode.new()
	node.id = &"start"
	node.text = "Текст"
	var answer := DialogueAnswer.new()
	answer.id = &"broken"
	answer.text = "Дальше"
	answer.next_node_id = &"missing_node"
	node.answers.append(answer)

	var broken := DialogueData.new()
	broken.id = &"broken_dialogue"
	broken.display_name = "Сломанный диалог"
	broken.start_node_id = &"start"
	broken.nodes.append(node)
	assert_false(broken.is_valid(), "dangling transition is invalid")

	var source: DialogueData = DialogueCatalog.load_dialogue(ELDER)
	assert_true(source.is_valid(), "source data is untouched")


func test_npc_exposes_52_portrait_name_and_reaction() -> void:
	var npc := DialogueNpc.new()
	npc.dialogue = DialogueCatalog.load_dialogue(ELDER)
	add_child_autofree(npc)

	var info: Dictionary = npc.get_interact_info("ru")
	assert_eq(info.portrait_size, Vector2i(52, 52), "портрет 52×52 (DESIGN §6.4)")
	assert_eq(info.display_name, "Лира, проводница")
	assert_eq(info.faction_id, &"free")
	assert_eq(info.faction_name, FactionManager.get_faction_name(&"free"))
	assert_eq(info.reaction, FactionManager.REACTION_NEUTRAL)
	assert_true(info.can_interact)
	assert_eq(info.dialogue_id, ELDER)
	assert_not_null(npc.create_runner("ru"), "NPC создаёт движок диалога")

	var bare := DialogueNpc.new()
	add_child_autofree(bare)
	var bare_info: Dictionary = bare.get_interact_info("ru")
	assert_false(bare_info.can_interact)
	assert_false(bare_info.reason.is_empty(), "причина отсутствия диалога видна")
	assert_null(bare.create_runner("ru"))


# ------------------------------------------------------------------------------
# Conditions (AC-06.1/06.2, EC-11)
# ------------------------------------------------------------------------------

func test_condition_checks_reputation_and_reaction() -> void:
	var condition := DialogueCondition.new()
	condition.faction_id = &"free"
	condition.min_reputation = 10
	var low: Dictionary = condition.check(&"free", "ru")
	assert_false(low.met)
	assert_true(low.reason.contains("репутация 10"), "причина содержит порог")
	assert_eq(low.reputation, 0)

	FactionManager.set_reputation(&"free", 10)
	assert_true(condition.check(&"free", "ru").met)

	condition.min_reaction = &"friendly"
	var neutral: Dictionary = condition.check(&"free", "ru")
	assert_false(neutral.met)
	assert_true(neutral.reason.contains("дружб"))
	FactionManager.set_reputation(&"free", 20)
	assert_true(condition.check(&"free", "ru").met)


func test_condition_checks_active_and_completed_quests() -> void:
	var condition := DialogueCondition.new()
	condition.active_quests = [FREE_QUEST]
	assert_false(condition.check(&"free", "ru").met)
	Journal.start_quest(FREE_QUEST)
	assert_true(condition.check(&"free", "ru").met)
	Journal.complete_quest(FREE_QUEST)
	assert_false(condition.check(&"free", "ru").met, "завершённый квест не активен")

	var completed := DialogueCondition.new()
	completed.required_quests = [FREE_QUEST]
	assert_true(completed.check(&"free", "ru").met)
	assert_true(DialogueCondition.new().check(&"free", "ru").met, "empty condition is met")


func test_answer_condition_disabled_with_reason_before_quest() -> void:
	var runner := DialogueRunner.new(DialogueCatalog.load_dialogue(ELDER), "ru")
	var snapshot: Dictionary = runner.start()
	var index: int = _answer_index(snapshot, &"report_job")
	assert_gte(index, 0)
	var answer: Dictionary = snapshot.answers[index]
	assert_true(answer.disabled, "доклад недоступен без активного квеста")
	assert_true(answer.reason.contains("активный квест"), str(answer.reason))
	assert_false(bool(runner.select_answer(index).ok), "недоступный ответ не выбирается")

	Journal.start_quest(FREE_QUEST)
	runner = DialogueRunner.new(DialogueCatalog.load_dialogue(ELDER), "ru")
	snapshot = runner.start()
	assert_false(snapshot.answers[_answer_index(snapshot, &"report_job")].disabled)


func test_node_condition_uses_fallback() -> void:
	var runner := DialogueRunner.new(DialogueCatalog.load_dialogue(GUARD), "ru")
	var snapshot: Dictionary = runner.start()
	var gate_index: int = _answer_index(snapshot, &"to_gate")
	assert_gte(gate_index, 0)

	var low: Dictionary = runner.select_answer(gate_index)
	assert_true(low.ok)
	assert_eq(low.snapshot.node_id, &"gate_denied", "низкая репутация → отказный узел")
	assert_true(low.snapshot.text.contains("Стража"))

	FactionManager.set_reputation(&"order", 10)
	runner = DialogueRunner.new(DialogueCatalog.load_dialogue(GUARD), "ru")
	snapshot = runner.start()
	var high: Dictionary = runner.select_answer(_answer_index(snapshot, &"to_gate"))
	assert_eq(high.snapshot.node_id, &"gate", "порог достигнут → проход открыт")


# ------------------------------------------------------------------------------
# Runner and consequences (AC-06.1)
# ------------------------------------------------------------------------------

func test_runner_returns_speaker_faction_and_2x2_answers() -> void:
	var runner := DialogueRunner.new(DialogueCatalog.load_dialogue(ELDER), "ru")
	var snapshot: Dictionary = runner.start()
	assert_eq(snapshot.speaker, "Лира, проводница")
	assert_eq(snapshot.faction, FactionManager.get_faction_name(&"free"))
	assert_eq(snapshot.answers.size(), 4, "два ряда по два ответа")
	assert_eq(snapshot.page_count, 1)
	assert_false(snapshot.ended)
	assert_false(snapshot.has_next_page)


func test_report_answer_shows_tag_and_completes_quest_ac_06_1() -> void:
	Journal.start_quest(FREE_QUEST)
	watch_signals(EventBus)
	watch_signals(Journal)

	var reputation_before: int = FactionManager.get_reputation(&"free")
	var xp_before: int = GameState.xp
	var runner := DialogueRunner.new(DialogueCatalog.load_dialogue(ELDER), "ru")
	var snapshot: Dictionary = runner.start()
	var index: int = _answer_index(snapshot, &"report_job")
	assert_eq(snapshot.answers[index].tag, "[Вольные+15]", "тег из Δ-таблицы")

	var result: Dictionary = runner.select_answer(index)
	assert_true(result.ok)
	assert_eq(result.snapshot.node_id, &"thanks")
	assert_true(Journal.is_completed(FREE_QUEST), "завершение зафиксировано в журнале")
	assert_false(Journal.is_active(FREE_QUEST))
	assert_eq(
		FactionManager.get_reputation(&"free"),
		reputation_before + 15,
		"репутация изменилась по Δ (AC-06.1)"
	)
	assert_eq(GameState.xp, xp_before + 80, "опыт за квест начислен")

	assert_signal_emitted(EventBus, "quest_completed")
	assert_signal_emitted(Journal, "quest_completed")
	assert_eq(int(result.effects.size()) >= 2, true, "репутация и квест в эффектах")


func test_action_answer_applies_reputation_event_and_journal_tag() -> void:
	var runner := DialogueRunner.new(DialogueCatalog.load_dialogue(GUARD), "ru")
	var snapshot: Dictionary = runner.start()
	var index: int = _answer_index(snapshot, &"oath")
	assert_eq(snapshot.answers[index].tag, "[Орден+1]", "тег действия из Δ-таблицы")
	assert_false(snapshot.answers[index].disabled)

	var result: Dictionary = runner.select_answer(index)
	assert_true(result.ok)
	assert_eq(FactionManager.get_reputation(&"order"), 1, "apply_reputation_event сработал")
	var has_journal_event: bool = false
	for entry: Dictionary in Journal.get_events():
		if entry.get("id") == &"action_campfire_oath":
			has_journal_event = true
			assert_false(str(entry.get("text", "")).is_empty())
	assert_true(has_journal_event, "событие записано в журнал (T-24)")


# ------------------------------------------------------------------------------
# Trade (AC-06.2)
# ------------------------------------------------------------------------------

func test_trader_is_locked_below_threshold_with_reason() -> void:
	var trader: TraderNpc = _make_trader()
	var info: Dictionary = trader.get_trade_info("ru")
	assert_false(info.allowed)
	assert_false(info.can_trade)
	assert_false(info.reason.is_empty(), "причина отказа обязательна")
	assert_true(info.reason.contains("репутац"), str(info.reason))
	assert_eq(int(info.threshold), 10)
	assert_eq(info.alternative_faction_id, &"free", "EC-11: альтернатива есть")

	var buy: Dictionary = trader.buy(&"healing_herb")
	assert_false(buy.ok)
	assert_eq(buy.reason, "no_access")
	assert_eq(GameState.currency, 100, "без доступа монеты не списаны")
	assert_false(GameState.get_inventory().has(&"healing_herb"))

	var runner: DialogueRunner = trader.create_runner("ru")
	var snapshot: Dictionary = runner.start()
	var index: int = _answer_index(snapshot, &"show_goods")
	assert_true(snapshot.answers[index].disabled, "ответ торговца закрыт")
	assert_true(
		str(snapshot.answers[index].reason).contains("репутация"),
		"диалог показывает причину отказа в ячейке ответа"
	)


func test_trader_opens_at_threshold_and_sells() -> void:
	var trader: TraderNpc = _make_trader()
	FactionManager.set_reputation(&"order", 10)
	var info: Dictionary = trader.get_trade_info("ru")
	assert_true(info.allowed)
	assert_true(info.can_trade)
	assert_true(info.reason.is_empty())
	assert_eq(info.items.size(), 2)
	assert_true(info.items[0].affordable)

	var buy: Dictionary = trader.buy(&"healing_herb")
	assert_true(buy.ok)
	assert_eq(buy.price, 25)
	assert_eq(GameState.currency, 75)
	assert_true(GameState.get_inventory().has(&"healing_herb"))

	var runner: DialogueRunner = trader.create_runner("ru")
	var snapshot: Dictionary = runner.start()
	assert_false(snapshot.answers[_answer_index(snapshot, &"show_goods")].disabled)


# ------------------------------------------------------------------------------
# Quests / Journal (EC-11, T-24)
# ------------------------------------------------------------------------------

func test_quest_accept_reports_reason_and_alternative_ec_11() -> void:
	watch_signals(EventBus)
	var denied: Dictionary = QuestService.accept(ORDER_QUEST, "ru")
	assert_false(denied.ok)
	assert_eq(denied.reason, "unavailable")
	assert_false(denied.message.is_empty())
	assert_eq(denied.alternative_faction_id, &"free")
	assert_eq(denied.alternative_quest_id, FREE_QUEST)
	assert_false(Journal.is_active(ORDER_QUEST))

	var accepted: Dictionary = QuestService.accept(FREE_QUEST, "ru")
	assert_true(accepted.ok)
	assert_true(Journal.is_active(FREE_QUEST))
	assert_signal_emitted(EventBus, "quest_started")
	assert_eq(QuestService.accept(FREE_QUEST, "ru").reason, "already_active")


func test_quest_completion_is_idempotent() -> void:
	QuestService.accept(FREE_QUEST, "ru")
	var first: Dictionary = QuestService.complete(FREE_QUEST, "ru")
	assert_true(first.ok)
	assert_eq(FactionManager.get_reputation(&"free"), 15)
	var xp_after_first: int = GameState.xp
	assert_eq(xp_after_first, 80)

	var second: Dictionary = QuestService.complete(FREE_QUEST, "ru")
	assert_false(second.ok)
	assert_eq(second.reason, "already_completed")
	assert_eq(FactionManager.get_reputation(&"free"), 15, "репутация не начислена дважды")
	assert_eq(GameState.xp, xp_after_first, "опыт не начислен дважды")


func test_journal_entries_events_and_state_round_trip() -> void:
	assert_true(Journal.start_quest(FREE_QUEST))
	assert_false(Journal.start_quest(FREE_QUEST), "повторная выдача отклонена")
	assert_true(Journal.is_active(FREE_QUEST))

	assert_true(Journal.record_event(&"event_test", "Событие"))
	assert_false(Journal.record_event(&"event_test", "Событие"), "дубликат отклонён")
	assert_true(Journal.record_event(&"event_test_2", ""))
	assert_eq(Journal.get_events().size(), 2)

	assert_true(Journal.complete_quest(FREE_QUEST))
	assert_eq(Journal.get_quest_status(FREE_QUEST), &"completed")
	var entries: Array[Dictionary] = Journal.get_quest_entries("ru")
	assert_eq(entries.size(), 1)
	assert_eq(entries[0].status, &"completed")
	assert_eq(entries[0].title, "Провести груз через болото")
	assert_eq(entries[0].faction_id, &"free")

	var state: Dictionary = Journal.get_state()
	Journal.reset_state()
	assert_eq(Journal.get_completed_quests().size(), 0)
	Journal.restore_state(state)
	assert_true(Journal.is_completed(FREE_QUEST))
	assert_eq(Journal.get_events().size(), 2)


# ------------------------------------------------------------------------------
# Pagination / RU-EN (box overflow)
# ------------------------------------------------------------------------------

func test_long_ru_and_en_lore_fit_the_dialog_box() -> void:
	for language: String in ["ru", "en"]:
		var runner := DialogueRunner.new(DialogueCatalog.load_dialogue(ELDER), language)
		var snapshot: Dictionary = runner.start()
		var lore_index: int = _answer_index(snapshot, &"ask_lore")
		var result: Dictionary = runner.select_answer(lore_index)
		assert_true(result.ok)
		assert_gt(runner.get_page_count(), 1, "%s lore is paginated" % language)

		var all_text: String = ""
		var pages: int = 0
		while true:
			var page: Dictionary = runner.get_snapshot()
			all_text += page.text
			pages += 1
			assert_true(
				DialogueText.fits(page.text),
				"%s page fits 3 lines × 47 chars" % language
			)
			for line: String in page.text.split("\n", true):
				assert_true(line.length() <= DialogueText.MAX_LINE_CHARS)
				assert_true(
					UIStyle.text_width(line, UITokens.FONT_BODY)
						<= float(UITokens.DIALOG_TEXT_WIDTH),
					"line width fits the 380 px text box"
				)
			if not runner.has_next_page():
				break
			runner.next_page()
		assert_gt(pages, 1)
		if language == "en":
			assert_true(all_text.contains("Bastion"), "EN text is used")
		else:
			assert_true(all_text.contains("Бастион"), "RU text is used")


# ------------------------------------------------------------------------------
# UI: AshenDialog reuse, typing, keyboard/gamepad
# ------------------------------------------------------------------------------

func test_screen_reuses_ashen_dialog_with_typing_and_2x2() -> void:
	var screen := DialogueScreen.new()
	add_child_autofree(screen)
	assert_true(screen.open_dialogue(DialogueCatalog.load_dialogue(ELDER), "ru"))
	assert_true(screen.is_open())

	var dialog: AshenDialog = screen.get_dialog()
	assert_not_null(dialog)
	assert_eq(dialog.get_display_name(), "Лира, проводница")
	assert_eq(dialog.get_answer_columns(), 2, "сетка 2×2 (T-18)")
	assert_eq(dialog.get_answer_count(), 4)
	assert_true(dialog.is_typing(), "печать включается на старте")

	assert_eq(dialog.advance_typing(UITokens.TYPE_SPEED * 0.5), 0, "22 мс/символ")
	assert_eq(dialog.advance_typing(UITokens.TYPE_SPEED * 0.5), 1)
	dialog.reveal_all()
	assert_eq(dialog.get_visible_characters(), dialog.get_total_characters())
	assert_true(dialog.get_answer_item(0).has_focus(), "фокус на первом ответе")


func test_screen_sets_focus_neighbors_for_keyboard_and_gamepad() -> void:
	var screen := DialogueScreen.new()
	add_child_autofree(screen)
	screen.open_dialogue(DialogueCatalog.load_dialogue(ELDER), "ru")
	var dialog: AshenDialog = screen.get_dialog()
	var first: AshenMenuItem = dialog.get_answer_item(0)
	var third: AshenMenuItem = dialog.get_answer_item(2)
	assert_eq(
		first.focus_neighbor_bottom,
		third.get_path(),
		"вниз/вверх ведут на следующий ряд (D-pad)"
	)
	assert_eq(third.focus_neighbor_top, first.get_path())
	assert_eq(
		first.focus_neighbor_right,
		third.get_path(),
		"отключённый ответ пропускается при навигации вправо"
	)

	var has_joypad_accept: bool = false
	for event: InputEvent in InputMap.action_get_events(&"ui_accept"):
		if event is InputEventJoypadButton:
			has_joypad_accept = true
	assert_true(has_joypad_accept, "ui_accept доступен с геймпада")

	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	screen._unhandled_input(cancel)
	assert_false(screen.is_open(), "Esc/B закрывает диалог")


func test_screen_paginates_long_text_and_advances_on_accept() -> void:
	var screen := DialogueScreen.new()
	add_child_autofree(screen)
	screen.open_dialogue(DialogueCatalog.load_dialogue(ELDER), "en")
	var dialog: AshenDialog = screen.get_dialog()
	dialog.reveal_all()
	var lore_index: int = _answer_index(screen.get_runner().get_snapshot(), &"ask_lore")
	var result: Dictionary = screen.select_answer(lore_index)
	assert_true(result.ok)
	assert_true(screen.get_runner().get_page_count() > 1, "lore is paginated")

	var first_page: String = dialog.get_body_text()
	for line: String in first_page.split("\n", true):
		assert_true(UIStyle.text_width(line, UITokens.FONT_BODY) <= UITokens.DIALOG_TEXT_WIDTH)
	assert_eq(dialog.get_answer_count(), 0, "ответы только на последней странице")

	# Первое нажатие досрочно печатает страницу, второе — листает (как в игре).
	dialog.reveal_all()
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	screen._unhandled_input(accept)
	assert_true(
		screen.get_runner().get_current_page() > 0,
		"Enter/A перелистывает длинную реплику"
	)
	assert_ne(dialog.get_body_text(), first_page)


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _answer_index(snapshot: Dictionary, answer_id: StringName) -> int:
	for answer: Dictionary in snapshot.get("answers", []):
		if StringName(str(answer.get("id", ""))) == answer_id:
			return int(answer.get("index", -1))
	return -1


func _make_trader() -> TraderNpc:
	var trader := TraderNpc.new()
	trader.dialogue = DialogueCatalog.load_dialogue(TRADER)
	trader.stock = [&"healing_herb", &"iron_dagger"]
	trader.prices = {"healing_herb": 25, "iron_dagger": 60}
	GameState.currency = 100
	GameState.clear_inventory()
	add_child_autofree(trader)
	return trader
