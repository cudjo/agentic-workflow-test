extends GutTest
## T-29 — прогрессия: характеристики, стоимость шагов (AC-08.1), очки
## обучения, опыт/уровень, учителя с предусловиями навыков (AC-08.2) и
## контракт требований экипировки для инвентаря (T-21).
##
## Тесты работают с реальными данными `data/balance/progression.tres` и
## `data/balance/teachers/*.tres`: значения не дублируются в тестах, кроме
## ожидаемых стартовых (5) и шагов таблицы. Каждый тест начинается с чистой
## прогрессии и восстанавливает исходное состояние GameState.

const PROGRESSION_PATH: String = "res://data/balance/progression.tres"
const TEACHER_IDS: Array[StringName] = [&"quartermaster", &"huntress", &"elder"]

var _original_stats: Dictionary = {}
var _original_learning_points: int = 0
var _original_level: int = 1
var _original_xp: int = 0
var _original_hp: float = 0.0
var _original_stamina: float = 0.0
var _original_abilities: Array[StringName] = []

var _teacher: Teacher = null


func before_each() -> void:
	_original_stats = GameState.get_stats()
	_original_learning_points = GameState.learning_points
	_original_level = GameState.level
	_original_xp = GameState.xp
	_original_hp = GameState.hp
	_original_stamina = GameState.stamina
	_original_abilities = GameState.get_abilities()

	GameState.reset_progression()
	GameState.clear_abilities()
	GameState.reset_hp()
	GameState.reset_stamina()
	GameState.set_learning_points(0)

	_teacher = Teacher.new()
	_teacher.teacher_id = &"quartermaster"


func after_each() -> void:
	if is_instance_valid(_teacher):
		_teacher.free()
		_teacher = null
	GameState.restore_progression(
		_original_stats,
		_original_learning_points,
		_original_level,
		_original_xp
	)
	GameState.restore_hp(_original_hp)
	GameState.stamina = _original_stamina
	GameState.restore_abilities(_original_abilities)


# ------------------------------------------------------------------------------
# Data (не хардкод)
# ------------------------------------------------------------------------------

func test_progression_tables_are_valid_and_loaded_from_data() -> void:
	var data: ProgressionData = load(PROGRESSION_PATH) as ProgressionData
	assert_not_null(data, "progression.tres loads")
	if data == null:
		return
	assert_true(data.is_valid(), "progression tables are valid")
	assert_eq(data.stat_ids.size(), 4, "four stats are defined")
	assert_eq(data.get_start_value(&"strength"), 5, "strength starts at 5")

	for stat_id: StringName in data.stat_ids:
		var costs: Array[int] = data.get_step_cost_table(stat_id)
		assert_eq(
			costs.size(),
			data.get_max_value(stat_id) - data.get_start_value(stat_id),
			"%s cost table covers every step to max" % stat_id
		)
		for index: int in range(1, costs.size()):
			assert_gt(
				costs[index],
				costs[index - 1],
				"%s step cost grows (AC-08.1)" % stat_id
			)

	assert_eq(data.get_level_for_xp(0), 1, "0 XP is level 1")
	assert_eq(
		data.get_level_for_xp(data.xp_thresholds[0]),
		2,
		"first XP threshold reaches level 2"
	)
	assert_eq(
		data.get_level_for_xp(1_000_000),
		data.get_max_level(),
		"XP is capped at max level"
	)


func test_teacher_data_files_are_valid() -> void:
	for teacher_id: StringName in TEACHER_IDS:
		var probe: Teacher = Teacher.new()
		probe.teacher_id = teacher_id
		var data: TeacherData = probe.get_data()
		assert_not_null(data, "%s data loads" % teacher_id)
		if data != null:
			assert_true(data.is_valid(), "%s data is valid" % teacher_id)
			assert_eq(data.id, teacher_id, "teacher id matches the file")
			assert_false(data.get_skill_ids().is_empty(), "teacher teaches skills")
			for skill_id: StringName in data.get_skill_ids():
				var skill: Dictionary = data.get_skill(skill_id)
				assert_false(skill.is_empty(), "%s skill is readable" % skill_id)
		probe.free()


# ------------------------------------------------------------------------------
# AC-08.1 — step cost and +1 stat
# ------------------------------------------------------------------------------

func test_training_costs_points_increases_stat_and_grows_next_cost() -> void:
	GameState.set_learning_points(1)
	var cost_before: int = GameState.get_training_cost(&"strength")
	assert_eq(cost_before, 1, "first strength step costs 1 (from the table)")

	watch_signals(EventBus)
	var result: Dictionary = GameState.train_stat(&"strength")

	assert_true(bool(result.get("ok", false)), "training succeeds")
	assert_eq(GameState.get_stat(&"strength"), 6, "stat grows by exactly 1 (AC-08.1)")
	assert_eq(GameState.learning_points, 0, "points are spent")
	assert_eq(int(result.get("cost_paid", 0)), cost_before, "paid the table cost")
	assert_eq(int(result.get("next_cost", -1)), 2, "next step costs 2")
	assert_gt(
		GameState.get_training_cost(&"strength"),
		cost_before,
		"the next step is more expensive (AC-08.1)"
	)

	assert_signal_emitted_with_parameters(
		EventBus,
		"stat_changed",
		[&"strength", 6, 2]
	)
	assert_signal_emitted_with_parameters(EventBus, "learning_points_changed", [0])


func test_training_without_points_changes_nothing() -> void:
	GameState.set_learning_points(0)
	watch_signals(EventBus)

	var result: Dictionary = GameState.train_stat(&"dexterity")

	assert_false(bool(result.get("ok", true)), "training is refused")
	assert_eq(String(result.get("reason", "")), "not_enough_points", "reason is explicit")
	assert_eq(GameState.get_stat(&"dexterity"), 5, "stat is unchanged")
	assert_eq(GameState.learning_points, 0, "points are unchanged")
	assert_signal_not_emitted(EventBus, "stat_changed")


func test_training_at_max_value_is_refused() -> void:
	var data: ProgressionData = load(PROGRESSION_PATH) as ProgressionData
	var maximum: int = data.get_max_value(&"strength")
	GameState.stats[&"strength"] = maximum
	GameState.set_learning_points(50)

	var result: Dictionary = GameState.train_stat(&"strength")

	assert_false(bool(result.get("ok", true)), "maxed stat cannot be trained")
	assert_eq(String(result.get("reason", "")), "max", "reason: max")
	assert_eq(GameState.get_stat(&"strength"), maximum, "value stays at max")
	assert_eq(GameState.learning_points, 50, "points are not spent")


func test_teacher_trains_its_own_stat_and_cost_grows() -> void:
	var data: TeacherData = _teacher.get_data()
	assert_not_null(data, "teacher data is loaded by id")
	if data == null:
		return
	assert_eq(data.stat_id, &"strength", "quartermaster trains strength")

	GameState.set_learning_points(3)
	var info: Dictionary = _teacher.get_training_info()
	assert_true(bool(info.get("available", false)), "training is available")
	assert_eq(int(info.get("cost", -1)), 1, "first step costs 1")
	assert_eq(int(info.get("cost_after", -1)), 2, "UI shows the growing next cost")

	var first: Dictionary = _teacher.train()
	assert_true(bool(first.get("ok", false)), "teacher training succeeds")
	assert_eq(GameState.get_stat(&"strength"), 6, "stat +1 (AC-08.1)")
	assert_eq(GameState.learning_points, 2, "one point spent")

	var second: Dictionary = _teacher.train()
	assert_true(bool(second.get("ok", false)), "second training succeeds")
	assert_eq(GameState.get_stat(&"strength"), 7, "another +1")
	assert_eq(int(second.get("cost_paid", 0)), 2, "the second step cost 2")
	assert_eq(GameState.learning_points, 0, "all points spent")


# ------------------------------------------------------------------------------
# Experience / level / learning points
# ------------------------------------------------------------------------------

func test_xp_levels_up_and_awards_learning_points() -> void:
	watch_signals(EventBus)

	var almost: Dictionary = GameState.add_xp(99)
	assert_eq(int(almost.get("level", 0)), 1, "below the threshold stays level 1")
	assert_eq(GameState.learning_points, 0, "no points before level up")
	assert_eq(int(almost.get("xp_to_next", -1)), 1, "1 XP left to level 2")

	var level_up: Dictionary = GameState.add_xp(1)
	assert_eq(int(level_up.get("level", 0)), 2, "threshold reaches level 2")
	assert_eq(int(level_up.get("levels_gained", 0)), 1, "one level gained")
	assert_eq(GameState.learning_points, 2, "2 points per level (data)")
	assert_eq(GameState.xp, 100, "XP is accumulated")
	assert_eq(GameState.get_xp_to_next_level(), 150, "to level 3 needs 150 more")

	assert_signal_emitted_with_parameters(EventBus, "level_changed", [2, 2])
	assert_signal_emitted_with_parameters(EventBus, "xp_changed", [100, 150])

	var third: Dictionary = GameState.add_xp(150)
	assert_eq(int(third.get("level", 0)), 3, "next threshold reaches level 3")
	assert_eq(GameState.learning_points, 4, "points accumulate")

	GameState.add_xp(1_000_000)
	assert_eq(GameState.level, GameState.progression_rules.get_max_level(), "level is capped")
	assert_eq(GameState.get_xp_to_next_level(), 0, "no next level at the cap")


# ------------------------------------------------------------------------------
# AC-08.2 — skill prerequisites
# ------------------------------------------------------------------------------

func test_skill_prerequisite_blocks_learning_and_shows_required_value() -> void:
	GameState.set_learning_points(10)

	var info: Dictionary = _teacher.get_skill_info(&"power_strike")
	assert_false(bool(info.get("available", true)), "skill is unavailable (AC-08.2)")
	assert_false(bool(info.get("prerequisites_met", true)), "prerequisite is not met")
	assert_eq(int(info.get("missing", []).size()), 1, "one missing stat")
	assert_eq(int(info.get("missing")[0].get("required", 0)), 8, "required strength is 8")
	assert_eq(int(info.get("missing")[0].get("current", 0)), 5, "current strength is 5")
	var reason: String = str(info.get("reason", ""))
	assert_true(reason.contains("8"), "reason shows the required value (AC-08.2)")
	assert_true(reason.contains("5"), "reason shows the current value")

	var result: Dictionary = _teacher.learn_skill(&"power_strike")
	assert_false(bool(result.get("ok", true)), "learning is refused")
	assert_eq(GameState.learning_points, 10, "points are not spent")
	assert_false(GameState.has_ability(&"power_strike"), "skill is not granted")


func test_skill_is_available_after_prerequisite_and_costs_points() -> void:
	GameState.restore_progression({"strength": 8}, 0, 1, 0)
	GameState.set_learning_points(2)
	watch_signals(EventBus)

	var info: Dictionary = _teacher.get_skill_info(&"power_strike")
	assert_true(bool(info.get("prerequisites_met", false)), "prerequisite is met")
	assert_true(bool(info.get("available", false)), "skill becomes available")

	var result: Dictionary = _teacher.learn_skill(&"power_strike")
	assert_true(bool(result.get("ok", false)), "skill is learned")
	assert_eq(GameState.learning_points, 0, "skill cost is charged")
	assert_true(GameState.has_ability(&"power_strike"), "ability id is stored")
	assert_signal_emitted_with_parameters(
		EventBus,
		"ability_acquired",
		[&"power_strike"]
	)

	var again: Dictionary = _teacher.learn_skill(&"power_strike")
	assert_false(bool(again.get("ok", true)), "the same skill is not bought twice")
	assert_eq(GameState.learning_points, 0, "no points are charged twice")


# ------------------------------------------------------------------------------
# Equipment requirements contract for T-21
# ------------------------------------------------------------------------------

func test_equipment_requirements_flag_items_for_inventory() -> void:
	var axe: Dictionary = GameState.get_equipment_info(&"two_handed_axe")
	assert_false(bool(axe.get("met", true)), "heavy axe requirements are not met")
	assert_eq(int(axe.get("requirements", {}).get(&"strength", 0)), 9, "axe needs strength 9")
	assert_eq(int(axe.get("missing", []).size()), 1, "one requirement is missing")
	assert_eq(int(axe.get("missing")[0].get("required", 0)), 9, "required value is exposed")
	assert_eq(int(axe.get("missing")[0].get("current", 0)), 5, "current value is exposed")
	var axe_reason: String = str(axe.get("reason", ""))
	assert_true(axe_reason.contains("9"), "reason shows the required value for T-21")
	assert_true(axe_reason.contains("5"), "reason shows the current value for T-21")

	var sword: Dictionary = GameState.get_equipment_info(&"one_handed_sword")
	assert_true(bool(sword.get("met", false)), "items without requirements are usable")
	assert_eq(str(sword.get("reason", "x")), "", "no denial reason")

	var dagger: Dictionary = GameState.get_equipment_info(&"light_dagger")
	assert_false(bool(dagger.get("met", true)), "dagger requires dexterity")
	assert_eq(int(dagger.get("missing")[0].get("required", 0)), 8, "dagger needs dexterity 8")

	GameState.restore_progression({"strength": 9}, 0, 1, 0)
	assert_true(
		GameState.meets_equipment_requirements(&"two_handed_axe"),
		"requirements are met after strength grows"
	)
	assert_false(
		GameState.meets_equipment_requirements(&"light_dagger"),
		"dexterity requirement is independent"
	)


# ------------------------------------------------------------------------------
# Derived effects / restore
# ------------------------------------------------------------------------------

func test_enemy_death_and_quest_award_xp_from_data() -> void:
	EventBus.enemy_died.emit(&"swift_fiend", Vector2.ZERO)
	assert_eq(GameState.xp, 25, "enemy XP comes from the data table")
	assert_eq(GameState.level, 1, "25 XP is below level 2")

	var quest: Dictionary = GameState.award_quest_xp(&"quest_clear_swamp")
	assert_true(bool(quest.get("ok", false)), "quest XP is awarded")
	assert_eq(int(quest.get("amount", 0)), 100, "quest XP amount comes from data")
	assert_eq(GameState.xp, 125, "XP accumulates")
	assert_eq(GameState.level, 2, "crossing the threshold levels up")
	assert_eq(GameState.learning_points, 2, "level up awards learning points")

	var unknown: Dictionary = GameState.award_quest_xp(&"quest_unknown")
	assert_false(bool(unknown.get("ok", true)), "unknown quest gives no XP")
	assert_eq(String(unknown.get("reason", "")), "unknown_quest", "reason is explicit")
	assert_eq(GameState.xp, 125, "unknown quest leaves XP unchanged")

	EventBus.enemy_died.emit(&"unknown_enemy", Vector2.ZERO)
	assert_eq(GameState.xp, 125, "unknown enemy gives no XP")


func test_health_and_endurance_raise_derived_maximums() -> void:
	var hp_before: float = GameState.hp_max
	var stamina_before: float = GameState.stamina_max
	GameState.set_learning_points(10)

	GameState.train_stat(&"health")
	assert_almost_eq(
		GameState.hp_max,
		hp_before + GameState.progression_data.health_per_point,
		0.001,
		"health raises max HP"
	)
	assert_almost_eq(
		GameState.hp,
		hp_before + GameState.progression_data.health_per_point,
		0.001,
		"raising health heals by the gained amount"
	)

	GameState.train_stat(&"endurance")
	assert_almost_eq(
		GameState.stamina_max,
		stamina_before + GameState.progression_data.stamina_per_point,
		0.001,
		"endurance raises max stamina"
	)
	assert_almost_eq(
		GameState.stamina,
		stamina_before + GameState.progression_data.stamina_per_point,
		0.001,
		"current stamina is not lost on the upgrade"
	)


func test_restore_progression_validates_values_and_notifies_ui() -> void:
	watch_signals(EventBus)

	GameState.restore_progression(
		{"strength": 999, "dexterity": -3, "luck": 7},
		4,
		99,
		400
	)

	assert_eq(GameState.get_stat(&"strength"), 20, "value is clamped to max")
	assert_eq(GameState.get_stat(&"dexterity"), 5, "value is clamped to start")
	assert_false(GameState.stats.has(&"luck"), "unknown stats are dropped")
	assert_eq(GameState.learning_points, 4, "learning points are restored")
	assert_eq(GameState.level, GameState.progression_rules.get_max_level(), "level is capped")
	assert_eq(GameState.xp, 400, "XP is restored")
	assert_signal_emitted(EventBus, "stat_changed")
	assert_signal_emitted(EventBus, "learning_points_changed")
	assert_signal_emitted(EventBus, "level_changed")
	assert_signal_emitted(EventBus, "xp_changed")
