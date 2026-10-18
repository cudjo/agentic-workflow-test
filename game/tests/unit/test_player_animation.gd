extends GutTest
## T-05 — анимации и визуал игрока (DESIGN §7, AC-02.1/02.2, AC-03.3).
##
## Проверяем контракт кадров (16×24, ≤16 цветов, все анимации DESIGN §7),
## привязку состояние FSM → анимация через EventBus, визуальные признаки
## (double jump flash, dash trail, dust, death marker), режим «без мигания»
## и idle-вариант при нуле выносливости.

const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const ACTION_LIST: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"attack", &"block", &"roll", &"dash",
]
const DESIGN_ANIMATIONS: Array[StringName] = [
	&"idle", &"run", &"jump_rise", &"jump_apex", &"fall", &"land",
	&"double_jump", &"dash", &"wall_slide", &"attack_1", &"attack_2",
	&"attack_3", &"block", &"roll", &"hurt", &"death", &"out_of_stamina",
	&"sit",
]

var _no_flash_backup: bool = false


func before_each() -> void:
	_no_flash_backup = Config.no_flash
	Config.set_no_flash(false)
	GameState.reset_stamina()
	_reset_input()


func after_each() -> void:
	Config.set_no_flash(_no_flash_backup)
	GameState.reset_stamina()
	_reset_input()


func _reset_input() -> void:
	for action: StringName in ACTION_LIST:
		Input.action_release(action)
		InputManager.just_pressed(action)
		InputManager.consume_coyote_time(action)


func _spawn_player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	return player


func _animation(player: Player) -> PlayerAnimation:
	return player.get_node("Animation") as PlayerAnimation


# ------------------------------------------------------------------------------
# Кадровый контракт
# ------------------------------------------------------------------------------

func test_placeholder_contains_every_design_animation() -> void:
	var names: Array[StringName] = PlayerSpriteFrames.animation_names()
	for expected: StringName in DESIGN_ANIMATIONS:
		assert_true(names.has(expected), "animation '%s' must exist" % expected)


func test_placeholder_frames_are_16x24_and_within_16_colors() -> void:
	var balance: BalancingParams = load(BALANCE_PATH) as BalancingParams
	assert_not_null(balance, "balancing.tres must load")
	var frames: SpriteFrames = PlayerSpriteFrames.build(balance)
	assert_eq(
		frames.get_animation_names().size(),
		PlayerSpriteFrames.FRAME_COUNTS.size(),
		"every contract animation is built"
	)

	var unique_colors: Dictionary = {}
	assert_lte(
		PlayerSpriteFrames.PLACEHOLDER_COLORS.size(),
		PlayerSpriteFrames.MAX_COLORS,
		"placeholder palette is within the 16-color budget"
	)
	for anim_name: StringName in PlayerSpriteFrames.FRAME_COUNTS.keys():
		assert_true(frames.has_animation(anim_name), "'%s' is in SpriteFrames" % anim_name)
		var count: int = frames.get_frame_count(anim_name)
		assert_eq(
			count,
			PlayerSpriteFrames.FRAME_COUNTS[anim_name],
			"'%s' frame count matches DESIGN §7" % anim_name
		)
		for frame_index: int in count:
			var texture: Texture2D = frames.get_frame_texture(anim_name, frame_index)
			assert_not_null(texture, "frame texture exists")
			var image: Image = texture.get_image()
			assert_eq(image.get_width(), PlayerSpriteFrames.SIZE.x, "sprite width is 16")
			assert_eq(image.get_height(), PlayerSpriteFrames.SIZE.y, "sprite height is 24")
			var painted: int = 0
			for y: int in image.get_height():
				for x: int in image.get_width():
					var color: Color = image.get_pixel(x, y)
					if color.a > 0.0:
						painted += 1
						unique_colors[color.to_html()] = true
			assert_gt(painted, 0, "'%s' frame %d is not empty" % [anim_name, frame_index])
	assert_lte(unique_colors.size(), PlayerSpriteFrames.MAX_COLORS, "≤16 colors per sprite")


func test_animation_speeds_follow_balancing() -> void:
	var balance: BalancingParams = load(BALANCE_PATH) as BalancingParams
	var frames: SpriteFrames = PlayerSpriteFrames.build(balance)
	assert_almost_eq(
		frames.get_animation_speed(&"idle"),
		1.0 / balance.anim_idle_frame,
		0.001,
		"idle cadence comes from balancing.tres"
	)
	assert_almost_eq(
		frames.get_animation_speed(&"dash"),
		4.0 / balance.t_dash,
		0.001,
		"dash covers T_dash with 4 frames"
	)
	assert_almost_eq(
		frames.get_animation_speed(&"death"),
		1.0 / balance.anim_death_frame,
		0.001,
		"death cadence comes from balancing.tres"
	)


# ------------------------------------------------------------------------------
# FSM → animation wiring
# ------------------------------------------------------------------------------

func test_animation_node_is_wired_into_player_scene() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)
	assert_not_null(animation, "Player.tscn contains PlayerAnimation")
	var sprite: AnimatedSprite2D = animation.get_node("Sprite") as AnimatedSprite2D
	assert_not_null(sprite, "AnimatedSprite2D child exists")
	assert_not_null(sprite.sprite_frames, "frames are assigned")
	assert_false(
		(player.get_node("Visual") as Sprite2D).visible,
		"legacy placeholder sprite is hidden behind the animation"
	)
	assert_eq(animation.current_animation, &"idle", "starts in idle")


func test_every_fsm_state_maps_to_a_contract_animation() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)
	for state_name: StringName in PlayerStateMachine.PRIORITIES.keys():
		EventBus.player_state_changed.emit(state_name)
		var current: StringName = animation.get_current_animation()
		assert_true(
			PlayerSpriteFrames.FRAME_COUNTS.has(current),
			"state '%s' plays a contract animation (got '%s')" % [state_name, current]
		)
		var expected: StringName = PlayerAnimation.STATE_TO_ANIMATION[state_name]
		if state_name == &"jump":
			# Состояние jump уточняется по velocity: подъём или апекс.
			assert_true(
				current == PlayerSpriteFrames.ANIM_JUMP_RISE
				or current == PlayerSpriteFrames.ANIM_JUMP_APEX,
				"state 'jump' plays jump_rise/jump_apex"
			)
		else:
			assert_eq(
				current,
				expected,
				"state '%s' maps to its DESIGN §7 animation" % state_name
			)


func test_jump_switches_between_rise_and_apex() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)

	player.velocity = Vector2(0.0, -180.0)
	EventBus.player_state_changed.emit(&"jump")
	animation.tick(0.0)
	assert_eq(animation.get_current_animation(), &"jump_rise", "ascending jump")

	player.velocity = Vector2(0.0, 0.0)
	animation.tick(0.0)
	assert_eq(animation.get_current_animation(), &"jump_apex", "apex near zero vy")

	player.velocity = Vector2(0.0, 120.0)
	EventBus.player_state_changed.emit(&"fall")
	animation.tick(0.0)
	assert_eq(animation.get_current_animation(), &"fall", "falling plays fall")


func test_attack_combo_uses_three_distinct_animations() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)
	assert_not_null(player.combo, "player has a combo tracker")

	EventBus.player_state_changed.emit(&"attack")
	animation.tick(0.0)
	assert_eq(animation.get_current_animation(), &"attack_1", "combo step 1")

	player.combo.step_index = 1
	animation.tick(0.0)
	assert_eq(animation.get_current_animation(), &"attack_2", "combo step 2")

	player.combo.step_index = 2
	animation.tick(0.0)
	assert_eq(animation.get_current_animation(), &"attack_3", "combo step 3")


# ------------------------------------------------------------------------------
# Визуальные признаки
# ------------------------------------------------------------------------------

func test_double_jump_flash_is_steel3_for_two_to_three_frames() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)
	var sprite: AnimatedSprite2D = animation.sprite

	EventBus.player_state_changed.emit(&"double_jump")
	assert_eq(animation.get_current_animation(), &"double_jump", "double jump animation")
	assert_true(animation.is_double_jump_flash_active(), "flash is active on entry")
	assert_eq(sprite.modulate, UITokens.STEEL_3, "flash is steel-3")

	# 3 кадра double jump при 6 кадрах / 0.36 s ≈ 0.18 s.
	animation.tick(0.17)
	assert_true(animation.is_double_jump_flash_active(), "flash lasts ~3 frames")
	animation.tick(0.02)
	assert_false(animation.is_double_jump_flash_active(), "flash ends after 3 frames")
	assert_eq(sprite.modulate, Color.WHITE, "tint is restored")


func test_dash_has_two_steel9_ghosts_and_iframe_look() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)

	EventBus.player_state_changed.emit(&"dash")
	assert_eq(animation.get_current_animation(), &"dash", "dash animation")
	assert_eq(animation.sprite.modulate, UITokens.STEEL_3, "cold i-frames look")
	var ghosts: Array[Sprite2D] = animation.get_dash_ghosts()
	assert_eq(ghosts.size(), 2, "dash leaves 2 ghost frames (steel-9)")
	for ghost: Sprite2D in ghosts:
		assert_almost_eq(ghost.modulate.r, UITokens.STEEL_9.r, 0.001, "ghost uses steel-9")
		assert_almost_eq(ghost.modulate.g, UITokens.STEEL_9.g, 0.001, "ghost uses steel-9")
		assert_almost_eq(ghost.modulate.b, UITokens.STEEL_9.b, 0.001, "ghost uses steel-9")
		assert_gt(ghost.modulate.a, 0.0, "ghost is visible")


func test_run_spawns_dust_particles() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)

	EventBus.player_state_changed.emit(&"run")
	animation.tick(player.balance.anim_dust_interval + 0.01)
	assert_eq(animation.dust_spawn_count, 1, "run emits dust on the step interval")
	animation.tick(player.balance.anim_dust_interval)
	assert_eq(animation.dust_spawn_count, 2, "dust repeats while running")

	EventBus.player_state_changed.emit(&"idle")
	animation.tick(player.balance.anim_dust_interval * 2.0)
	assert_eq(animation.dust_spawn_count, 2, "no dust outside run")


func test_death_spawns_thing_marker() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)

	EventBus.player_state_changed.emit(&"death")
	assert_eq(animation.get_current_animation(), &"death", "death animation")
	assert_true(animation.has_death_marker(), "«Твои вещи» marker appears on death")
	var marker: Sprite2D = animation._death_marker as Sprite2D
	assert_not_null(marker, "marker sprite exists")
	var image: Image = marker.texture.get_image()
	assert_eq(image.get_width(), 12, "marker icon width")
	assert_eq(image.get_height(), 12, "marker icon height")
	var has_gold: bool = false
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y) == UITokens.GOLD_9:
				has_gold = true
	assert_true(has_gold, "marker has a gold-9 halo")

	animation.clear_death_marker()
	assert_false(animation.has_death_marker(), "marker can be cleared on respawn")


# ------------------------------------------------------------------------------
# a11y и выносливость
# ------------------------------------------------------------------------------

func test_hurt_flash_respects_no_flash() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)

	EventBus.player_state_changed.emit(&"hurt")
	assert_true(animation.is_flash_active(), "default mode flashes on hurt")
	assert_eq(animation.sprite.modulate, UITokens.BONE, "hurt flash is bright")
	animation.tick(PlayerAnimation.HURT_FLASH_TIME + 0.01)
	assert_false(animation.is_flash_active(), "flash is shorter than 100 ms")
	assert_eq(animation.sprite.modulate, Color.WHITE, "tint is restored")

	Config.set_no_flash(true)
	EventBus.player_state_changed.emit(&"hurt")
	assert_false(animation.is_flash_active(), "no_flash disables the hurt flash")
	assert_eq(
		animation.sprite.modulate,
		UITokens.BLOOD_5,
		"no_flash uses a steady tone change instead of blinking"
	)
	animation.tick(player.balance.t_hurt + 0.01)
	assert_eq(animation.sprite.modulate, Color.WHITE, "tone is restored after hurt")


func test_zero_stamina_idle_uses_out_of_stamina_variant() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)

	GameState.stamina = 0.0
	EventBus.player_state_changed.emit(&"idle")
	animation.tick(0.0)
	assert_eq(
		animation.get_current_animation(),
		&"out_of_stamina",
		"AC-03.3: idle variant when stamina is empty"
	)

	GameState.reset_stamina()
	EventBus.player_state_changed.emit(&"idle")
	animation.tick(0.0)
	assert_eq(animation.get_current_animation(), &"idle", "idle returns after recovery")


func test_sit_at_bonfire_animation_is_available() -> void:
	var player: Player = _spawn_player()
	var animation: PlayerAnimation = _animation(player)

	animation.play_sit()
	assert_eq(animation.get_current_animation(), &"sit", "sit animation for bonfire")

	animation.play_idle()
	assert_eq(animation.get_current_animation(), &"idle", "returns to idle")
