extends GutTest
## T-10 — выносливость: трата, восстановление, флаг «НЕТ СИЛ» (AC-03.3).
##
## Stamina — чистая логика (RefCounted), значения задержки/скорости взяты
## из balancing.tres; GameState делегирует и транслирует сигнал в EventBus.

const BALANCE_PATH: String = "res://data/balance/balancing.tres"


func _make_stamina() -> Stamina:
	var stamina := Stamina.new()
	stamina.setup(100.0, 0.8, 25.0)
	return stamina


func test_spend_subtracts_and_emits_changed() -> void:
	var stamina := _make_stamina()
	watch_signals(stamina)

	assert_true(stamina.spend(12.0), "enough stamina -> spend succeeds")
	assert_almost_eq(stamina.current, 88.0, 0.001, "12 spent")
	assert_signal_emitted(stamina, "changed", "HUD gets a stamina update")
	assert_false(stamina.is_exhausted(), "not exhausted at 88")


func test_spend_fails_without_spending_when_not_enough() -> void:
	var stamina := _make_stamina()
	stamina.spend(95.0)

	assert_false(stamina.spend(12.0), "5 < 12 -> attack/roll is refused")
	assert_almost_eq(stamina.current, 5.0, 0.001, "failed spend changes nothing")


func test_exhausted_flag_rises_at_zero_and_clears_on_restore() -> void:
	var stamina := _make_stamina()
	watch_signals(stamina)

	assert_true(stamina.spend(100.0), "spend everything")
	assert_almost_eq(stamina.current, 0.0, 0.001)
	assert_true(stamina.is_exhausted(), "HUD flag: НЕТ СИЛ (AC-03.3)")
	assert_signal_emitted_with_parameters(stamina, "exhausted_changed", [true])

	stamina.restore(7.0)
	assert_almost_eq(stamina.current, 7.0, 0.001)
	assert_false(stamina.is_exhausted(), "flag clears when stamina returns")
	assert_signal_emitted_with_parameters(stamina, "exhausted_changed", [false])


func test_regen_waits_for_delay_and_requires_rest() -> void:
	var stamina := _make_stamina()
	stamina.spend(50.0)

	stamina.update(0.4, true)
	assert_almost_eq(stamina.current, 50.0, 0.001, "no regen before regen_delay")

	stamina.update(0.4, false)
	assert_almost_eq(stamina.current, 50.0, 0.001, "no regen while acting")

	# 0.8 s have passed since the spend; the next 0.2 s counts as rest.
	stamina.update(0.2, true)
	assert_almost_eq(stamina.current, 55.0, 0.01, "25/s * 0.2 s = 5")


func test_regen_clears_exhausted_flag() -> void:
	var stamina := _make_stamina()
	stamina.spend(100.0)
	assert_true(stamina.is_exhausted())

	stamina.update(0.8, true)
	stamina.update(0.2, true)
	assert_gt(stamina.current, 0.0, "stamina regenerates")
	assert_false(stamina.is_exhausted(), "flag clears after regen")


func test_reset_restores_full_and_clears_flag() -> void:
	var stamina := _make_stamina()
	stamina.spend(100.0)
	stamina.reset()

	assert_almost_eq(stamina.current, 100.0, 0.001)
	assert_false(stamina.is_exhausted())


func test_game_state_uses_balancing_values_and_exposes_flag() -> void:
	var balance := load(BALANCE_PATH) as BalancingParams
	GameState.reset_stamina()
	assert_almost_eq(GameState.stamina_max, balance.stamina_max, 0.001)
	assert_almost_eq(GameState.stamina, balance.stamina_max, 0.001)
	assert_false(GameState.is_stamina_exhausted())

	assert_true(GameState.try_spend_stamina(balance.stamina_max))
	assert_true(GameState.is_stamina_exhausted(), "GameState raises the HUD flag")
	assert_false(GameState.try_spend_stamina(balance.e_attack))
	assert_almost_eq(GameState.stamina, 0.0, 0.001)

	GameState.reset_stamina()
	assert_false(GameState.is_stamina_exhausted())
