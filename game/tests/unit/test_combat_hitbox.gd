extends GutTest
## T-10 — hitbox/hurtbox, слои, попадание в бою (AC-03.1, AC-03.3).
##
## Интеграционные тесты работают на реальных 60 Hz physics-кадрах, как игра:
## игрок бьёт dummy-цель впереди, проверяются урон по формуле, отбрасывание,
## вспышка ≤ 100 мс и списание выносливости.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const DEFAULT_WEAPON_PATH: String = "res://data/weapons/one_handed_sword.tres"
const AXE_PATH: String = "res://data/weapons/two_handed_axe.tres"
const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]


func before_each() -> void:
	GameState.reset_stamina()
	GameState.set_weapon(load(DEFAULT_WEAPON_PATH) as WeaponData)
	_reset_input()


func after_each() -> void:
	GameState.set_weapon(load(DEFAULT_WEAPON_PATH) as WeaponData)
	GameState.clear_abilities()
	_reset_input()


func _reset_input() -> void:
	for action: StringName in ACTION_LIST:
		Input.action_release(action)
		InputManager.just_pressed(action)
		InputManager.consume_coyote_time(action)


func _spawn_player() -> Player:
	var floor_body := StaticBody2D.new()
	floor_body.name = "TestFloor"
	floor_body.position = Vector2(0.0, 8.0)
	var floor_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400.0, 16.0)
	floor_shape.shape = rect
	floor_body.add_child(floor_shape)
	add_child_autofree(floor_body)

	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.position = Vector2(0.0, -10.0)
	player.velocity = Vector2.ZERO
	return player


## Dummy-цель: CharacterBody2D + Hurtbox (enemy layer) + серый спрайт.
func _spawn_target(x: float) -> Dictionary:
	var body := CharacterBody2D.new()
	body.name = "Dummy"
	body.collision_layer = 0
	body.collision_mask = 0

	var sprite := Sprite2D.new()
	sprite.name = "Visual"
	sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)
	var texture := PlaceholderTexture2D.new()
	texture.size = Vector2(16.0, 24.0)
	sprite.texture = texture
	body.add_child(sprite)

	var hurtbox := Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.hurt_layer = CombatLayers.ENEMY_HURTBOX
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12.0, 20.0)
	shape.shape = rect
	hurtbox.add_child(shape)
	body.add_child(hurtbox)

	add_child_autofree(body)
	body.position = Vector2(x, -10.0)
	return {"body": body, "hurtbox": hurtbox, "sprite": sprite}


func _settle(player: Player) -> void:
	for _i: int in 15:
		await get_tree().physics_frame
	assert_true(player.is_on_floor(), "player settles on the floor")
	assert_eq(player.get_state_name(), &"idle", "settled player is idle")


func test_hitbox_and_hurtbox_use_combat_layers() -> void:
	var hitbox := Hitbox.new()
	add_child_autofree(hitbox)
	assert_eq(hitbox.collision_layer, CombatLayers.PLAYER_HITBOX, "player hitbox layer")
	assert_eq(hitbox.collision_mask, CombatLayers.ENEMY_HURTBOX, "hits enemy hurtboxes")
	assert_false(hitbox.active, "inactive by default")

	var enemy_hitbox := Hitbox.new()
	enemy_hitbox.hit_layer = CombatLayers.ENEMY_HITBOX
	enemy_hitbox.target_mask = CombatLayers.PLAYER_HURTBOX
	add_child_autofree(enemy_hitbox)
	assert_eq(enemy_hitbox.collision_layer, CombatLayers.ENEMY_HITBOX)
	assert_eq(enemy_hitbox.collision_mask, CombatLayers.PLAYER_HURTBOX)

	var hurtbox := Hurtbox.new()
	add_child_autofree(hurtbox)
	assert_eq(hurtbox.collision_layer, CombatLayers.ENEMY_HURTBOX, "hurtbox layer")
	assert_eq(hurtbox.collision_mask, 0, "hurtbox does not scan")


func test_invulnerable_hurtbox_ignores_damage() -> void:
	var hurtbox := Hurtbox.new()
	hurtbox.invulnerable = true
	add_child_autofree(hurtbox)

	assert_false(hurtbox.receive_damage(Damage.create(5.0)), "i-frames reject the hit")
	assert_eq(hurtbox.hit_count, 0)
	assert_null(hurtbox.last_damage)


func test_attack_deals_formula_damage_knockback_and_short_flash() -> void:
	var player: Player = _spawn_player()
	var target: Dictionary = _spawn_target(14.0)
	var hurtbox: Hurtbox = target["hurtbox"]
	var sprite: Sprite2D = target["sprite"]
	var body: CharacterBody2D = target["body"]
	await _settle(player)

	var weapon: WeaponData = player.get_weapon()
	var stamina_before: float = GameState.stamina

	InputManager.press_buffered(&"attack")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"attack", "attack starts")

	var frames: int = 0
	while hurtbox.hit_count == 0 and frames < 40:
		await get_tree().physics_frame
		frames += 1

	assert_eq(hurtbox.hit_count, 1, "target is hit exactly once per swing (AC-03.1)")
	assert_not_null(hurtbox.last_damage, "hit carries a damage payload")
	if hurtbox.last_damage == null:
		return

	var expected: float = (
		weapon.damage
		* weapon.get_step_multiplier(0)
		* player.balance.damage_multiplier
	)
	assert_almost_eq(
		hurtbox.last_damage.amount,
		expected,
		0.001,
		"damage follows the formula from balancing.tres"
	)
	assert_almost_eq(
		hurtbox.last_damage.knockback.x,
		weapon.knockback * player.balance.knockback_scale,
		0.001,
		"knockback comes from weapon data + balance scale"
	)
	assert_lte(
		hurtbox.last_damage.hit_flash_duration,
		Damage.HIT_FLASH_MAX_SEC,
		"hit flash is <= 100 ms (AC-03.1)"
	)
	assert_almost_eq(
		body.velocity.x,
		weapon.knockback * player.balance.knockback_scale,
		0.001,
		"knockback is applied to the target"
	)
	assert_eq(sprite.modulate, Damage.FLASH_COLOR, "hit flash is visible on the sprite")
	assert_almost_eq(
		GameState.stamina,
		stamina_before - player.balance.e_attack,
		0.001,
		"attack spends E_attack"
	)

	await get_tree().create_timer(0.2).timeout
	assert_eq(
		sprite.modulate,
		Color(0.5, 0.5, 0.5, 1.0),
		"flash ends within 100 ms and restores modulate"
	)


func test_attack_does_not_hit_behind_the_player() -> void:
	var player: Player = _spawn_player()
	var target: Dictionary = _spawn_target(-14.0)
	var hurtbox: Hurtbox = target["hurtbox"]
	await _settle(player)

	InputManager.press_buffered(&"attack")
	var frames: int = 0
	while frames < 40:
		await get_tree().physics_frame
		frames += 1

	assert_eq(hurtbox.hit_count, 0, "hitbox is in front of the player")


func test_attack_is_refused_at_zero_stamina_and_raises_hud_flag() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	GameState.stamina = 0.0
	assert_true(GameState.is_stamina_exhausted(), "HUD flag is raised at 0 stamina (AC-03.3)")

	InputManager.press_buffered(&"attack")
	await get_tree().physics_frame

	assert_ne(player.get_state_name(), &"attack", "no stamina -> attack is not performed")
	assert_almost_eq(GameState.stamina, 0.0, 0.001, "failed attack spends nothing")
	assert_true(GameState.is_stamina_exhausted(), "HUD flag stays up")


func test_combo_link_in_window_starts_second_hit_and_spends_stamina_again() -> void:
	var player: Player = _spawn_player()
	_spawn_target(14.0)
	await _settle(player)

	InputManager.press_buffered(&"attack")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"attack")

	var frames: int = 0
	while not player.combo.can_link() and player.combo.is_active() and frames < 40:
		await get_tree().physics_frame
		frames += 1
	assert_true(player.combo.can_link(), "link window opens inside the swing")

	var stamina_before: float = GameState.stamina
	InputManager.press_buffered(&"attack")
	await get_tree().physics_frame

	assert_eq(player.combo.step_index, 1, "second combo hit is linked")
	assert_almost_eq(
		GameState.stamina,
		stamina_before - player.balance.e_attack,
		0.001,
		"each combo hit spends E_attack"
	)


func test_player_combo_is_configured_from_weapon_data() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	var axe := load(AXE_PATH) as WeaponData
	GameState.set_weapon(axe)
	InputManager.press_buffered(&"attack")
	await get_tree().physics_frame

	assert_eq(player.get_state_name(), &"attack")
	assert_eq(player.combo.step_count, axe.get_combo_length(), "combo length from weapon")
	assert_almost_eq(
		player.combo.step_duration,
		player.balance.t_attack * axe.attack_speed,
		0.001,
		"step duration = t_attack * weapon.attack_speed"
	)


func test_dash_and_block_spend_their_stamina() -> void:
	# T-07: рывок доступен только со способностью (AC-02.2).
	GameState.add_ability(&"dash")
	var player: Player = _spawn_player()
	await _settle(player)
	var stamina_before: float = GameState.stamina

	InputManager.press_buffered(&"dash")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"dash", "dash starts")
	assert_almost_eq(
		GameState.stamina,
		stamina_before - player.balance.e_dash,
		0.001,
		"dash spends E_dash"
	)

	var frames: int = 0
	while player.get_state_name() == &"dash" and frames < 20:
		await get_tree().physics_frame
		frames += 1

	Input.action_press(&"block")
	await get_tree().physics_frame
	assert_eq(player.get_state_name(), &"block", "block starts while held")
	assert_almost_eq(
		GameState.stamina,
		stamina_before - player.balance.e_dash - player.balance.e_block,
		0.001,
		"block spends E_block"
	)
	Input.action_release(&"block")
