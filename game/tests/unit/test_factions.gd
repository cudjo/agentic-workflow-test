extends GutTest
## T-27 — фракции: реестр данных, репутация по Δ-таблице (AC-06.1),
## пороги доступа с объяснением (AC-06.2), альтернатива через союзную
## фракцию (EC-11) и выбранная фракция для концовки T-32 (US-06).
##
## Менеджер читает/пишет `GameState.factions`/`chosen_faction`; каждый тест
## начинается с чистого фракционного состояния и восстанавливает исходное.

const ORDER: StringName = &"order"
const FREE: StringName = &"free"
const ASH: StringName = &"ash"

const CLEAR_SWAMP: StringName = &"quest_clear_swamp"
const FREE_SMUGGLE: StringName = &"quest_free_smuggle"

var _original_factions: Dictionary = {}
var _original_chosen: StringName = &""


func before_each() -> void:
	_original_factions = GameState.get_all_faction_reputation()
	_original_chosen = GameState.chosen_faction
	FactionManager.reset_state()


func after_each() -> void:
	GameState.restore_factions(_original_factions, _original_chosen)


# ------------------------------------------------------------------------------
# Registry / data
# ------------------------------------------------------------------------------

func test_registry_loads_three_valid_factions_from_data() -> void:
	assert_eq(FactionManager.get_faction_count(), 3, "three factions are registered")
	assert_eq(FactionManager.get_faction_ids().size(), 3, "ordered id list has 3 entries")

	for faction_id: StringName in [ORDER, FREE, ASH]:
		var data: FactionData = FactionManager.get_faction(faction_id)
		assert_not_null(data, "%s has a data resource" % faction_id)
		if data == null:
			continue
		assert_true(data.is_valid(), "%s data is valid" % faction_id)
		assert_false(FactionManager.get_faction_name(faction_id).is_empty(), "name is set")
		assert_false(FactionManager.get_faction_lore(faction_id).is_empty(), "lore is set")
		assert_true(
			FactionManager.has_faction(data.alternative_faction_id),
			"%s has an existing alternative faction (EC-11)" % faction_id
		)
		assert_true(
			data.access_threshold >= data.reputation_min
				and data.access_threshold <= data.reputation_max,
			"%s threshold is inside the reputation scale" % faction_id
		)

	assert_ne(
		FactionManager.get_faction_name(ORDER),
		FactionManager.get_faction_name(FREE),
		"factions have distinct display names"
	)


func test_delta_table_is_data_driven() -> void:
	assert_eq(
		FactionManager.get_action_delta(ORDER, CLEAR_SWAMP),
		15,
		"order delta comes from the .tres table"
	)
	assert_eq(
		FactionManager.get_action_delta(FREE, CLEAR_SWAMP),
		5,
		"another faction may react to the same quest"
	)
	assert_eq(
		FactionManager.get_action_delta(ORDER, &"action_unknown"),
		0,
		"unknown action has no effect"
	)
	assert_false(
		FactionManager.get_reputation_table(ORDER).is_empty(),
		"the whole delta table is available for UI/journal"
	)


# ------------------------------------------------------------------------------
# AC-06.1 — quest completion changes reputation and triggers reaction
# ------------------------------------------------------------------------------

func test_quest_completion_changes_reputation_by_delta_and_emits_reaction() -> void:
	watch_signals(EventBus)

	var results: Array[Dictionary] = FactionManager.complete_quest(CLEAR_SWAMP)

	assert_eq(FactionManager.get_reputation(ORDER), 15, "order gains +15 (AC-06.1)")
	assert_eq(FactionManager.get_reputation(FREE), 5, "free gains +5")
	assert_eq(FactionManager.get_reputation(ASH), -5, "ash loses -5")
	assert_eq(results.size(), 3, "one result per affected faction")

	var order_result: Dictionary = _result_for(results, ORDER)
	assert_eq(int(order_result.get("delta", 0)), 15, "applied delta is reported")
	assert_eq(int(order_result.get("value", 0)), 15, "new value is reported")
	assert_true(bool(order_result.get("access_granted", false)), "threshold is now open")
	assert_eq(
		StringName(str(order_result.get("reaction", ""))),
		FactionManager.REACTION_NEUTRAL,
		"NPC reaction is reported for dialogue T-28"
	)

	assert_signal_emitted_with_parameters(
		EventBus,
		"faction_reputation_changed",
		[ORDER, 15]
	)
	assert_signal_emitted_with_parameters(
		EventBus,
		"faction_quest_completed",
		[CLEAR_SWAMP, ORDER, 15, FactionManager.REACTION_NEUTRAL]
	)
	assert_signal_emitted_with_parameters(
		EventBus,
		"faction_access_changed",
		[ORDER, true]
	)


func test_npc_reaction_follows_reputation_relative_to_threshold() -> void:
	assert_eq(
		FactionManager.get_npc_reaction(ORDER),
		FactionManager.REACTION_WARY,
		"neutral 0 is below the order threshold 10 -> wary"
	)
	FactionManager.set_reputation(ORDER, 10)
	assert_eq(
		FactionManager.get_npc_reaction(ORDER),
		FactionManager.REACTION_NEUTRAL,
		"at the threshold NPC is neutral"
	)
	FactionManager.set_reputation(ORDER, 30)
	assert_eq(
		FactionManager.get_npc_reaction(ORDER),
		FactionManager.REACTION_FRIENDLY,
		"+20 above the threshold -> friendly"
	)
	FactionManager.set_reputation(ORDER, 60)
	assert_eq(
		FactionManager.get_npc_reaction(ORDER),
		FactionManager.REACTION_TRUSTED,
		"+50 above the threshold -> trusted"
	)
	FactionManager.set_reputation(ORDER, -11)
	assert_eq(
		FactionManager.get_npc_reaction(ORDER),
		FactionManager.REACTION_HOSTILE,
		"far below the threshold -> hostile"
	)


# ------------------------------------------------------------------------------
# AC-06.2 — below threshold access is limited with a clear reason
# ------------------------------------------------------------------------------

func test_below_threshold_blocks_territory_and_trader_with_reason() -> void:
	assert_false(
		FactionManager.can_enter_territory(ORDER),
		"0 < 10 blocks the order territory (AC-06.2)"
	)
	assert_false(FactionManager.can_trade(ORDER), "the order trader is blocked too")

	var territory: Dictionary = FactionManager.get_access_info(
		ORDER,
		FactionManager.AccessKind.TERRITORY
	)
	assert_false(bool(territory["allowed"]), "territory access is denied")
	assert_eq(int(territory["threshold"]), 10, "threshold is exposed to UI")
	assert_eq(int(territory["reputation"]), 0, "current reputation is exposed")
	var reason: String = str(territory["reason"])
	assert_true(reason.contains("Орден Пепла"), "reason names the faction")
	assert_true(reason.contains("10"), "reason states the required threshold")
	assert_true(reason.contains("0"), "reason states the current reputation")
	assert_true(reason.contains("Внутренний двор"), "reason names the territory")

	var trade: Dictionary = FactionManager.get_access_info(
		ORDER,
		FactionManager.AccessKind.TRADER
	)
	assert_false(bool(trade["allowed"]), "trader access is denied")
	assert_true(str(trade["reason"]).contains("Торговец"), "trader reason is specific")
	assert_ne(str(trade["reason"]), reason, "territory and trader have distinct reasons")


func test_threshold_crossing_grants_access_and_emits_signal() -> void:
	watch_signals(EventBus)

	assert_eq(FactionManager.set_reputation(ORDER, 10), 10, "reputation reaches threshold")

	assert_true(FactionManager.can_enter_territory(ORDER), "territory is open at threshold")
	assert_true(FactionManager.can_trade(ORDER), "trader is open at threshold")
	var info: Dictionary = FactionManager.get_access_info(ORDER)
	assert_true(bool(info["allowed"]), "access info reports granted")
	assert_eq(str(info["reason"]), "", "granted access has no denial reason")
	assert_signal_emitted_with_parameters(
		EventBus,
		"faction_access_changed",
		[ORDER, true]
	)

	FactionManager.set_reputation(ORDER, 0)
	assert_false(
		FactionManager.can_enter_territory(ORDER),
		"dropping below threshold closes access again"
	)


# ------------------------------------------------------------------------------
# EC-11 — hostile faction is unavailable, alternative via another faction
# ------------------------------------------------------------------------------

func test_hostile_faction_offers_alternative_through_another_faction() -> void:
	FactionManager.set_reputation(ORDER, -20)
	FactionManager.set_reputation(FREE, 15)

	var access: Dictionary = FactionManager.get_access_info(ORDER)
	assert_false(bool(access["allowed"]), "order access is denied")
	assert_eq(
		StringName(str(access["alternative_faction_id"])),
		FREE,
		"free is the alternative faction"
	)
	assert_true(
		bool(access["alternative_allowed"]),
		"free reputation opens the alternative route (EC-11)"
	)

	var quest: Dictionary = FactionManager.get_quest_access(CLEAR_SWAMP)
	assert_false(bool(quest["available"]), "order quest is unavailable")
	assert_true(str(quest["reason"]).contains("Орден Пепла"), "reason explains the refusal")
	assert_eq(
		StringName(str(quest["alternative_faction_id"])),
		FREE,
		"alternative faction is exposed to T-28"
	)
	assert_true(bool(quest["alternative_allowed"]), "alternative quest is available")
	assert_eq(
		StringName(str(quest["alternative_quest_id"])),
		FREE_SMUGGLE,
		"concrete alternative quest id is provided"
	)
	assert_false(FactionManager.is_quest_available(CLEAR_SWAMP), "order quest stays locked")
	assert_true(FactionManager.is_quest_available(FREE_SMUGGLE), "free quest is open")

	FactionManager.set_reputation(FREE, -20)
	var broken_alternative: Dictionary = FactionManager.get_quest_access(CLEAR_SWAMP)
	assert_false(
		bool(broken_alternative["alternative_allowed"]),
		"alternative closes when the ally is hostile too"
	)
	assert_eq(
		StringName(str(broken_alternative["alternative_quest_id"])),
		&"",
		"no alternative quest is offered"
	)


# ------------------------------------------------------------------------------
# US-06 — choice drives the ending faction id (T-32)
# ------------------------------------------------------------------------------

func test_choice_and_best_faction_supply_stable_ending_id() -> void:
	watch_signals(EventBus)

	assert_eq(FactionManager.get_selected_faction(), &"", "no choice by default")
	assert_eq(
		FactionManager.get_ending_faction_id(),
		&"",
		"neutral ending when nobody is chosen or liked (T-32)"
	)

	assert_true(FactionManager.choose_faction(ASH), "existing faction can be chosen")
	assert_eq(GameState.chosen_faction, ASH, "choice is stored in GameState")
	assert_eq(FactionManager.get_selected_faction(), ASH, "selected faction is readable")
	assert_eq(
		FactionManager.get_ending_faction_id(),
		ASH,
		"chosen faction is the stable ending id"
	)
	assert_signal_emitted_with_parameters(
		EventBus,
		"faction_chosen",
		[ASH, FactionManager.get_faction_name(ASH)]
	)
	assert_false(FactionManager.choose_faction(&"unknown"), "unknown faction is rejected")

	FactionManager.clear_faction_choice()
	FactionManager.set_reputation(ORDER, 20)
	FactionManager.set_reputation(FREE, 15)
	assert_eq(
		FactionManager.get_ending_faction_id(),
		ORDER,
		"without an explicit choice the best positive faction is used"
	)

	FactionManager.set_reputation(ORDER, -5)
	FactionManager.set_reputation(FREE, 0)
	assert_eq(
		FactionManager.get_ending_faction_id(),
		&"",
		"nobody positive -> neutral ending, not a hostile faction"
	)


func test_reputation_is_clamped_to_faction_scale() -> void:
	assert_eq(FactionManager.set_reputation(ORDER, 999), 100, "upper clamp")
	assert_eq(FactionManager.set_reputation(ORDER, -999), -100, "lower clamp")
	assert_eq(GameState.get_faction_reputation(ORDER), -100, "state keeps clamped value")


# ------------------------------------------------------------------------------
# Persistence bridge / robustness
# ------------------------------------------------------------------------------

func test_restore_state_and_reset_bridge_to_game_state() -> void:
	FactionManager.restore_state({"order": 12, "free": 7}, FREE)

	assert_eq(FactionManager.get_reputation(ORDER), 12, "reputation is restored")
	assert_eq(FactionManager.get_reputation(FREE), 7, "second faction is restored")
	assert_eq(FactionManager.get_selected_faction(), FREE, "choice is restored")
	assert_true(FactionManager.can_enter_territory(ORDER), "restored reputation opens access")

	FactionManager.reset_state()
	assert_eq(FactionManager.get_reputation(ORDER), 0, "reset clears reputation")
	assert_eq(GameState.get_all_faction_reputation(), {}, "state map is empty")
	assert_eq(FactionManager.get_selected_faction(), &"", "reset clears the choice")


func test_unknown_faction_is_safe() -> void:
	assert_eq(FactionManager.get_reputation(&"unknown"), 0, "unknown reputation is neutral")
	assert_false(FactionManager.can_enter_territory(&"unknown"), "unknown faction is closed")
	assert_eq(
		FactionManager.get_npc_reaction(&"unknown"),
		FactionManager.REACTION_NEUTRAL,
		"unknown faction reaction is neutral"
	)
	var info: Dictionary = FactionManager.get_access_info(&"unknown")
	assert_false(bool(info["allowed"]), "unknown faction access is denied")
	assert_true(
		str(info["reason"]).contains("Неизвестная"),
		"unknown faction reason is explicit"
	)
	assert_false(
		FactionManager.get_quest_access(&"unknown_quest")["available"],
		"unknown quest is unavailable"
	)


func _result_for(results: Array[Dictionary], faction_id: StringName) -> Dictionary:
	for result: Dictionary in results:
		if StringName(str(result.get("faction_id", ""))) == faction_id:
			return result
	return {}
