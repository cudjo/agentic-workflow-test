extends GutTest
## T-17 — переходы зон и экран загрузки (PLAN §2.3/§3.2, SPEC US-04,
## AC-04.1, EC-12; DESIGN §5 Loading).
##
## Тесты гоняют настоящие зоны 1–2 через SceneRouter на тестовом WorldRoot:
## фоновую загрузку, замену только WorldRoot, позицию игрока по точке входа,
## экран загрузки и блокировку ввода (EC-12), привязку fall_death_y (EC-03),
## переспавн corpse-метки и отсутствие утечек узлов при повторных переходах.

const LOADING_SCENE: PackedScene = preload("res://ui/loading/LoadingScreen.tscn")
const ZONE_01: StringName = &"zone_01_village"
const ZONE_02: StringName = &"zone_02_swamp"

var _host: Node2D
var _world_root: Node2D
var _original_zone: StringName = &""
var _original_hp: float = 0.0
var _original_death_active: bool = false
var _original_corpse: Dictionary = {}


func before_each() -> void:
	_original_zone = GameState.current_zone_id
	_original_hp = GameState.hp
	_original_death_active = GameState.death_active
	_original_corpse = GameState.get_corpse_info()

	SceneRouter.reset()
	SceneRouter.load_timeout = SceneRouter.LOAD_TIMEOUT
	SceneRouter.min_loading_time = SceneRouter.MIN_LOADING_TIME
	SceneRouter.exit_grace_time = SceneRouter.EXIT_GRACE_TIME

	_host = Node2D.new()
	add_child_autofree(_host)
	_world_root = Node2D.new()
	_world_root.name = "WorldRoot"
	_host.add_child(_world_root)
	SceneRouter.bind_world_root(_world_root)

	GameState.clear_corpse()
	GameState.death_active = false
	GameState.set_hp(GameState.hp_max)
	GameState.current_zone_id = &""


func after_each() -> void:
	SceneRouter.reset()
	SceneRouter.unbind_world_root()
	await wait_physics_frames(2)

	GameState.restore_death_state(
		_original_death_active,
		bool(_original_corpse.get("active", false)),
		StringName(str(_original_corpse.get("zone_id", ""))),
		_original_corpse.get("position", Vector2.ZERO),
		_original_corpse.get("items", []),
		int(_original_corpse.get("currency", 0)),
		bool(_original_corpse.get("lost", false))
	)
	GameState.set_hp(_original_hp)
	GameState.current_zone_id = _original_zone


func test_bootstrap_loads_start_zone_synchronously() -> void:
	var ok: bool = SceneRouter.bootstrap(ZONE_01, &"start")
	assert_true(ok, "bootstrap enters the start zone")
	assert_false(SceneRouter.is_loading, "bootstrap is not a loading transition")
	assert_eq(SceneRouter.current_zone_id, ZONE_01)
	assert_not_null(SceneRouter.player, "bootstrap spawns the player")
	if SceneRouter.player != null:
		assert_eq(SceneRouter.player.global_position, Vector2(100.0, 214.0))
		assert_true(SceneRouter.player.is_physics_processing())
		assert_almost_eq(
			SceneRouter.player.fall_death_y,
			_world_bottom(SceneRouter.current_zone),
			0.01
		)
	assert_false(
		SceneRouter.bootstrap(ZONE_02, &"west_gate"),
		"bootstrap is idempotent: the world is already running"
	)


# ------------------------------------------------------------------------------
# AC-04.1: переход туда и обратно, позиция по точке входа
# ------------------------------------------------------------------------------

func test_transition_between_two_zones_and_back_places_player_on_entry() -> void:
	await _transition(ZONE_01, &"start")
	assert_eq(SceneRouter.current_zone_id, ZONE_01)
	assert_eq(SceneRouter.current_entry_id, &"start")
	assert_not_null(SceneRouter.player, "first entry spawns the player")
	assert_eq(
		SceneRouter.player.global_position,
		Vector2(100.0, 214.0),
		"player stands on ZoneData entry 'start' (AC-04.1)"
	)
	assert_lt(
		SceneRouter.last_load_seconds,
		SceneRouter.LOAD_TIMEOUT,
		"transition fits the 3 s budget (AC-04.1)"
	)

	await _transition(ZONE_02, &"west_gate")
	assert_eq(SceneRouter.current_zone_id, ZONE_02)
	assert_eq(SceneRouter.current_zone.zone_data.display_name, "Болото")
	assert_eq(
		SceneRouter.player.global_position,
		Vector2(32.0, 214.0),
		"entry 'west_gate' is used from ZoneData"
	)

	await _transition(ZONE_01, &"from_gate")
	assert_eq(SceneRouter.current_zone_id, ZONE_01)
	assert_eq(
		SceneRouter.player.global_position,
		Vector2(245.0, 214.0),
		"returning through the gate uses 'from_gate', not 'start'"
	)
	assert_eq(
		get_tree().get_nodes_in_group(&"world_zone").size(),
		1,
		"only the active zone stays in the tree"
	)


# ------------------------------------------------------------------------------
# EC-12: экран загрузки, ввод заблокирован до конца
# ------------------------------------------------------------------------------

func test_loading_screen_is_shown_and_player_input_is_locked() -> void:
	await _transition(ZONE_01, &"start")
	var player: Player = SceneRouter.player
	assert_not_null(player)

	InputManager.press_buffered(&"attack")
	assert_true(InputManager.is_pressed(&"attack"), "precondition: buffered attack")

	var started: bool = SceneRouter.change_zone(ZONE_02, &"west_gate")
	assert_true(started, "transition starts")
	assert_true(SceneRouter.is_loading, "loading is in progress")
	assert_true(SceneRouter.is_input_locked(), "input is locked (EC-12)")
	assert_false(
		InputManager.is_pressed(&"attack"),
		"buffered attack pressed before loading is cleared (EC-12)"
	)
	assert_false(
		player.is_physics_processing(),
		"player physics is off during loading: attack/move cannot run (EC-12)"
	)

	var screen: LoadingScreen = SceneRouter.loading_screen
	assert_not_null(screen, "loading screen is created")
	if screen != null:
		assert_true(screen.is_shown(), "loading screen is visible")
		assert_eq(screen.layer, 40, "loading lives on CanvasLayer 40")
		var title := screen.get_node("Root/Content/Title") as Label
		assert_not_null(title)
		if title != null:
			assert_eq(title.text, "БОЛОТО", "zone name is the h2 title")
		var epigraph := screen.get_node("Root/Content/Epigraph") as Label
		assert_not_null(epigraph)
		if epigraph != null:
			assert_false(epigraph.text.is_empty(), "zone epigraph is shown")

	await wait_for_signal(SceneRouter.transition_finished, 5.0)
	await wait_physics_frames(2)

	assert_false(SceneRouter.is_loading, "transition finished")
	assert_false(SceneRouter.is_input_locked(), "input is unlocked after loading")
	assert_true(player.is_physics_processing(), "player physics is restored")
	if screen != null:
		assert_false(screen.is_shown(), "loading screen is hidden")
		assert_false(screen.visible, "loading layer is not visible")


# ------------------------------------------------------------------------------
# EC-03: fall_death_y привязан к границам зоны
# ------------------------------------------------------------------------------

func test_fall_limit_is_bound_to_zone_world_bounds() -> void:
	await _transition(ZONE_01, &"start")
	var expected: float = _world_bottom(SceneRouter.current_zone)
	assert_true(is_finite(expected), "zone 1 defines WorldBounds")
	assert_almost_eq(SceneRouter.player.fall_death_y, expected, 0.01)
	assert_almost_eq(expected, 270.0, 0.01, "village floor bottom is 270")

	await _transition(ZONE_02, &"west_gate")
	var swamp_bottom: float = _world_bottom(SceneRouter.current_zone)
	assert_almost_eq(
		SceneRouter.player.fall_death_y,
		swamp_bottom,
		0.01,
		"fall limit follows the new zone bounds"
	)


# ------------------------------------------------------------------------------
# Corpse run: метка переспавнивается при входе в её зону
# ------------------------------------------------------------------------------

func test_corpse_respawns_on_entering_its_zone_only() -> void:
	GameState.restore_death_state(
		false,
		true,
		ZONE_02,
		Vector2(200.0, 200.0),
		[&"ash_shard"],
		7,
		false
	)

	await _transition(ZONE_01, &"start")
	assert_eq(
		get_tree().get_nodes_in_group(&"corpses").size(),
		0,
		"corpse from another zone is not spawned"
	)

	await _transition(ZONE_02, &"west_gate")
	var corpses: Array[Node] = get_tree().get_nodes_in_group(&"corpses")
	assert_eq(corpses.size(), 1, "corpse marker is restored in its zone")
	if not corpses.is_empty():
		var corpse := corpses[0] as Corpse
		assert_not_null(corpse)
		if corpse != null:
			assert_eq(corpse.global_position, Vector2(200.0, 200.0))
			assert_eq(corpse.get_parent(), SceneRouter.current_zone)
			assert_false(corpse.lost, "restored marker is recoverable")

	await _transition(ZONE_01, &"from_gate")
	await wait_physics_frames(2)
	assert_eq(
		get_tree().get_nodes_in_group(&"corpses").size(),
		0,
		"leaving the zone frees its corpse node"
	)

	await _transition(ZONE_02, &"west_gate")
	assert_eq(
		get_tree().get_nodes_in_group(&"corpses").size(),
		1,
		"re-entering the zone respawns the corpse marker"
	)


# ------------------------------------------------------------------------------
# Сигнал для AudioManager (T-34)
# ------------------------------------------------------------------------------

func test_zone_loaded_signal_is_emitted_for_music_crossfade() -> void:
	watch_signals(EventBus)
	await _transition(ZONE_01, &"start")
	assert_signal_emitted_with_parameters(
		EventBus,
		"zone_loaded",
		[ZONE_01, "Деревня-бастион"]
	)
	assert_signal_emitted_with_parameters(
		EventBus,
		"zone_entered",
		[ZONE_01, "Деревня-бастион"]
	)


# ------------------------------------------------------------------------------
# Выход зоны (Area2D) инициирует переход
# ------------------------------------------------------------------------------

func test_zone_exit_area_requests_transition() -> void:
	SceneRouter.exit_grace_time = 0.0
	await _transition(ZONE_01, &"start")

	var exit_def: ZoneExit = SceneRouter.current_zone.zone_data.exits[0]
	assert_eq(exit_def.target_zone_id, ZONE_02, "precondition: gate leads to swamp")
	SceneRouter.player.global_position = exit_def.position

	await wait_for_signal(SceneRouter.transition_finished, 5.0)
	await wait_physics_frames(2)
	assert_eq(SceneRouter.current_zone_id, exit_def.target_zone_id)
	assert_eq(SceneRouter.current_entry_id, exit_def.target_entry_id)
	assert_eq(SceneRouter.player.global_position, Vector2(32.0, 214.0))


# ------------------------------------------------------------------------------
# Повторные переходы: узлы не накапливаются
# ------------------------------------------------------------------------------

func test_repeated_transitions_do_not_leak_nodes() -> void:
	await _transition(ZONE_01, &"start")
	for index: int in 5:
		await _transition(ZONE_02, &"west_gate")
		await _transition(ZONE_01, &"from_gate")

	await wait_physics_frames(2)
	assert_eq(
		get_tree().get_nodes_in_group(&"world_zone").size(),
		1,
		"exactly one active zone after 10 transitions"
	)
	assert_eq(
		get_tree().get_nodes_in_group(&"player").size(),
		1,
		"exactly one player after 10 transitions"
	)
	var screens: int = 0
	for child: Node in _host.get_children():
		if child is LoadingScreen:
			screens += 1
	assert_eq(screens, 1, "one reusable loading screen, not one per transition")


# ------------------------------------------------------------------------------
# Ошибки запроса
# ------------------------------------------------------------------------------

func test_unknown_zone_is_rejected_without_loading() -> void:
	watch_signals(SceneRouter)
	var ok: bool = SceneRouter.change_zone(&"zone_does_not_exist")
	assert_false(ok, "unknown zone is rejected")
	assert_false(SceneRouter.is_loading, "router stays idle")
	assert_false(SceneRouter.is_input_locked())
	assert_signal_emitted(SceneRouter, "transition_failed")


# ------------------------------------------------------------------------------
# Сам экран загрузки (DESIGN §5)
# ------------------------------------------------------------------------------

func test_loading_screen_renders_title_epigraph_and_four_step_spinner() -> void:
	var screen: LoadingScreen = LOADING_SCENE.instantiate() as LoadingScreen
	add_child_autofree(screen)
	assert_eq(screen.layer, 40, "loading is the topmost CanvasLayer")

	screen.show_loading("Болото", "Трясина не отпускает.")
	assert_true(screen.is_shown())
	var title := screen.get_node("Root/Content/Title") as Label
	var epigraph := screen.get_node("Root/Content/Epigraph") as Label
	var spinner := screen.get_node("Root/Content/Spinner") as HBoxContainer
	assert_eq(title.text, "БОЛОТО")
	assert_eq(epigraph.text, "Трясина не отпускает.")
	assert_eq(spinner.get_child_count(), 4, "spinner has exactly 4 steps")
	assert_eq(
		title.get_theme_font_size(&"font_size"),
		UITokens.FONT_H2,
		"title uses h2 typography"
	)
	assert_true(
		title.get_theme_color(&"font_color").is_equal_approx(UITokens.GOLD_3),
		"title uses gold token"
	)

	var first_step := 0
	for child: Node in spinner.get_children():
		var rect := child as ColorRect
		if rect != null and rect.color.is_equal_approx(UITokens.GOLD):
			first_step += 1
	assert_eq(first_step, 1, "exactly one spinner step is lit")

	await wait_seconds(LoadingScreen.SPINNER_STEP_TIME * 2.0)
	assert_gt(screen.spinner_step, 0, "spinner advances in discrete steps")

	screen.hide_loading()
	assert_false(screen.is_shown())
	assert_false(screen.visible)


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _transition(zone_id: StringName, entry_id: StringName) -> void:
	var started: bool = SceneRouter.change_zone(zone_id, entry_id)
	assert_true(started, "transition to '%s' starts" % zone_id)
	if started:
		await wait_for_signal(SceneRouter.transition_finished, 5.0)
	await wait_physics_frames(2)


func _world_bottom(zone: ZoneScene) -> float:
	var bounds := zone.get_node_or_null("WorldBounds") as Node2D
	if bounds == null:
		return INF
	var bottom: float = -INF
	for child: Node in bounds.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or not shape_node.shape is RectangleShape2D:
			continue
		var rect := shape_node.shape as RectangleShape2D
		bottom = maxf(bottom, shape_node.position.y + rect.size.y * 0.5)
	bottom += bounds.global_position.y
	return bottom
