extends GutTest
## T-10 — комбо-окно: 2–3 удара, связка в конце шага, активная фаза хитбокса.

const STEP_DURATION: float = 0.36
const LINK_WINDOW: float = 0.12


func _make_combo() -> ComboTracker:
	var combo := ComboTracker.new()
	combo.setup(3, STEP_DURATION, LINK_WINDOW)
	return combo


func test_start_activates_first_step() -> void:
	var combo := _make_combo()
	assert_false(combo.is_active(), "idle before start")
	assert_eq(combo.start(), 0, "combo starts at hit 1")
	assert_true(combo.is_active())
	assert_eq(combo.step_index, 0)
	assert_almost_eq(combo.time_in_step, 0.0, 0.001)


func test_link_window_opens_only_in_the_tail() -> void:
	var combo := _make_combo()
	combo.start()

	combo.advance(0.20)
	assert_false(combo.can_link(), "too early for the next hit")

	combo.advance(0.05)
	assert_true(combo.can_link(), "window opened at duration - link_window")

	assert_true(combo.try_link(), "hit 2 linked")
	assert_eq(combo.step_index, 1)
	assert_almost_eq(combo.time_in_step, 0.0, 0.001, "new step starts at t=0")


func test_last_step_has_no_link() -> void:
	var combo := _make_combo()
	combo.start()
	combo.advance(0.25)
	assert_true(combo.try_link(), "hit 2")
	combo.advance(0.25)
	assert_true(combo.try_link(), "hit 3")
	combo.advance(0.25)

	assert_false(combo.can_link(), "3-hit combo ends after the third hit")
	assert_false(combo.try_link(), "no fourth hit")


func test_step_ends_and_resets_without_link() -> void:
	var combo := _make_combo()
	combo.start()

	assert_false(combo.advance(0.35), "still swinging at 0.35 s")
	assert_true(combo.is_active())

	assert_true(combo.advance(0.02), "step finished at 0.36 s")
	assert_false(combo.is_active(), "combo resets without a link")


func test_hit_window_uses_balance_ratios() -> void:
	var combo := _make_combo()
	combo.start()

	assert_false(combo.is_hit_active(0.33, 0.66), "windup has no hitbox")
	combo.advance(0.12)
	assert_true(combo.is_hit_active(0.33, 0.66), "active phase has a hitbox")
	combo.advance(0.12)
	assert_false(combo.is_hit_active(0.33, 0.66), "recovery closes the hitbox")


func test_empty_combo_is_safe() -> void:
	var combo := ComboTracker.new()
	combo.setup(0, STEP_DURATION, LINK_WINDOW)
	assert_eq(combo.start(), -1, "no steps -> no combo")
	assert_false(combo.is_active())
	assert_false(combo.can_link())
	assert_false(combo.try_link())
	assert_true(combo.advance(0.1), "inactive combo reports ended")
