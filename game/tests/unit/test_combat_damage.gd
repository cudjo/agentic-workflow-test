extends GutTest
## T-10 — урон и данные оружия (AC-03.1).
##
## Формула: max(min_damage, weapon_damage * combo_multiplier * damage_multiplier - defense).
## Все коэффициенты берутся из `data/balance/balancing.tres`.

const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const WEAPON_PATHS: Array[String] = [
	"res://data/weapons/light_dagger.tres",
	"res://data/weapons/one_handed_sword.tres",
	"res://data/weapons/two_handed_axe.tres",
]

var balance: BalancingParams


func before_each() -> void:
	balance = load(BALANCE_PATH) as BalancingParams
	assert_not_null(balance, "balancing.tres must load")


func test_damage_formula_uses_balance_and_combo_multiplier() -> void:
	var plain: Damage = Damage.compute(balance, 10.0)
	assert_almost_eq(
		plain.amount,
		10.0 * balance.damage_multiplier,
		0.001,
		"base hit = weapon damage * damage_multiplier"
	)

	var combo_hit: Damage = Damage.compute(balance, 10.0, 1.5)
	assert_almost_eq(
		combo_hit.amount,
		15.0 * balance.damage_multiplier,
		0.001,
		"combo multiplier scales the hit"
	)

	var armored: Damage = Damage.compute(balance, 10.0, 1.0, 4.0)
	assert_almost_eq(
		armored.amount,
		10.0 * balance.damage_multiplier - 4.0,
		0.001,
		"defense is subtracted after scaling"
	)


func test_damage_never_drops_below_min_damage() -> void:
	var blocked: Damage = Damage.compute(balance, 1.0, 1.0, 100.0)
	assert_almost_eq(blocked.amount, balance.min_damage, 0.001, "min_damage floor")


func test_hit_flash_is_capped_at_100_ms() -> void:
	var slow_balance := BalancingParams.new()
	slow_balance.hit_flash_duration = 0.5
	slow_balance.min_damage = balance.min_damage
	var hit: Damage = Damage.compute(slow_balance, 10.0)
	assert_almost_eq(
		hit.hit_flash_duration,
		Damage.HIT_FLASH_MAX_SEC,
		0.0001,
		"flash from balance is hard-capped (AC-03.1)"
	)

	var explicit: Damage = Damage.create(5.0, Vector2.ZERO, 1.0)
	assert_lte(
		explicit.hit_flash_duration,
		Damage.HIT_FLASH_MAX_SEC,
		"explicit flash is capped too (AC-03.1)"
	)
	assert_true(
		balance.hit_flash_duration <= Damage.HIT_FLASH_MAX_SEC,
		"balanced flash is <= 100 ms"
	)


func test_knockback_is_applied_to_character_body() -> void:
	var body := CharacterBody2D.new()
	add_child_autofree(body)
	var hit: Damage = Damage.create(5.0, Vector2(80.0, -20.0))
	hit.apply_knockback(body)
	assert_eq(body.velocity, Vector2(80.0, -20.0), "knockback adds an impulse")


func test_weapon_resources_are_valid_data_with_2_to_3_hit_combos() -> void:
	var seen_types: Dictionary = {}
	for path: String in WEAPON_PATHS:
		var weapon := load(path) as WeaponData
		assert_not_null(weapon, "weapon loads: %s" % path)
		if weapon == null:
			continue
		assert_true(weapon.is_valid(), "weapon data is valid: %s" % path)
		assert_true(
			weapon.get_combo_length() >= 2 and weapon.get_combo_length() <= 3,
			"combo has 2-3 hits: %s" % path
		)
		assert_gt(weapon.damage, 0.0, "damage > 0: %s" % path)
		assert_gt(weapon.attack_speed, 0.0, "attack_speed > 0: %s" % path)
		assert_ne(weapon.id, &"", "weapon id is set: %s" % path)
		seen_types[weapon.weapon_type] = true

	assert_eq(seen_types.size(), 3, "light / one-handed / two-handed are distinct")


func test_game_state_uses_default_one_handed_weapon() -> void:
	var weapon: WeaponData = GameState.weapon
	assert_not_null(weapon, "GameState has a current weapon")
	if weapon == null:
		return
	assert_eq(weapon.id, &"one_handed_sword", "default run weapon")
