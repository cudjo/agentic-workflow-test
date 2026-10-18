extends GutTest
## T-09 — ability gates и подсказки над препятствием (PLAN §3.3, SPEC US-02,
## AC-02.4, AC-04.3, EC-10).
##
## Проверяем:
##   * данные `data/ability_gates.tres` (валидность, покрытие способностей) и
##     то, что заглушки T-14/T-15 в зонах — это `AbilityGate` с `gate_id` из данных;
##   * без способности gate физически блокирует тело и видимо показывает
##     «Нужно: <СПОСОБНОСТЬ>» + замок (нет скрытой блокировки);
##   * `EventBus.ability_hint_changed` для HUD при входе в зону подсказки;
##   * получение способности открывает все живые gates с ней, остальные остаются
##     закрытыми (AC-04.3);
##   * EC-10: уже пройденный проход (`mark_passed`) открыт без способности и
##     остаётся открытым для повторно созданного gate с тем же `gate_id`.

const CATALOG_PATH: String = "res://data/ability_gates.tres"
const GATE_SCENE: PackedScene = preload("res://world/props/ability_gate.tscn")
const ZONE_PATHS: Array[String] = [
	"res://world/zones/zone_01_village/zone_01_village.tscn",
	"res://world/zones/zone_02_swamp/zone_02_swamp.tscn",
	"res://world/zones/zone_03_mountains/zone_03_mountains.tscn",
]
const PLAYER_LAYER: int = 1 << 1
const WORLD_LAYER: int = 1
const MOVE_SPEED: float = 120.0


class TestMover extends CharacterBody2D:
	var constant_velocity: Vector2 = Vector2.ZERO

	func _physics_process(_delta: float) -> void:
		velocity = constant_velocity
		move_and_slide()


func before_each() -> void:
	GameState.clear_abilities()
	AbilityGate.reset_passed_gates()
	SceneRouter.reset_visited_zones()


func after_each() -> void:
	GameState.clear_abilities()
	AbilityGate.reset_passed_gates()
	SceneRouter.reset_visited_zones()


# ------------------------------------------------------------------------------
# Данные и интеграция с размещёнными заглушками T-14/T-15
# ------------------------------------------------------------------------------

func test_catalog_is_valid_data_and_covers_all_abilities() -> void:
	var catalog: AbilityGateCatalog = load(CATALOG_PATH) as AbilityGateCatalog
	assert_not_null(catalog, "ability_gates.tres загружается как AbilityGateCatalog")
	if catalog == null:
		return
	assert_eq(catalog.validate(), PackedStringArray(), "данные gates валидны")
	assert_true(catalog.has_gate(&"village_ledge"), "деревня: уступ описан данными")
	assert_true(catalog.has_gate(&"swamp_dash_gate"), "болото: dash-gate описан данными")
	assert_true(catalog.has_gate(&"mountains_wall_climb"), "горы: wall-climb gate в данных")
	assert_true(catalog.has_gate(&"mountains_dash_ledge"), "горы: dash-gate в данных")
	for ability_id: StringName in AbilityRegistry.all_ids():
		assert_has(
			catalog.get_ability_ids(),
			ability_id,
			"способность '%s' покрыта gates" % ability_id
		)


func test_zone_gates_use_data_and_have_no_hardcoded_requirement() -> void:
	var catalog: AbilityGateCatalog = load(CATALOG_PATH) as AbilityGateCatalog
	assert_not_null(catalog)
	var gate_count: int = 0
	for zone_path: String in ZONE_PATHS:
		var packed: PackedScene = load(zone_path) as PackedScene
		assert_not_null(packed, "%s загружается" % zone_path)
		if packed == null:
			continue
		var zone: Node = packed.instantiate()
		var props: Node = zone.get_node_or_null(^"Props")
		assert_not_null(props, "%s: есть Props" % zone_path)
		if props != null:
			for prop: Node in props.get_children():
				if not prop.has_meta(&"ability_gate"):
					continue
				gate_count += 1
				assert_true(prop is AbilityGate, "%s/%s — AbilityGate" % [zone_path, prop.name])
				var gate: AbilityGate = prop as AbilityGate
				if gate == null:
					continue
				assert_ne(gate.get_gate_id(), &"", "%s: gate_id задан" % gate.name)
				assert_eq(
					gate.get_meta(&"ability_gate"),
					catalog.get_ability_id(gate.get_gate_id()),
					"%s: требование совпадает с данными" % gate.name
				)
		zone.free()
	assert_eq(gate_count, 4, "деревня 1 + болото 1 + горы 2: все заглушки заменены")


# ------------------------------------------------------------------------------
# Блокировка и подсказка без способности (AC-02.4)
# ------------------------------------------------------------------------------

func test_locked_gate_shows_hint_and_keeps_collision() -> void:
	var gate: AbilityGate = _spawn_gate(&"village_ledge", Vector2.ZERO)
	assert_true(gate.blocking, "без двойного прыжка gate блокирует")
	assert_false(gate.is_open())
	assert_true(gate.get_hint() != null, "подсказка — часть сцены gate")
	assert_true(gate.get_hint().is_shown(), "подсказка видна без способности")
	assert_string_contains(gate.get_hint_text(), "Нужно:", "формат подсказки AC-02.4")
	assert_string_contains(
		gate.get_hint_text(),
		"ДВОЙНОЙ ПРЫЖОК",
		"в подсказке имя способности из AbilityRegistry"
	)
	assert_false(gate.collision_shape.disabled, "коллизия включена (без скрытой блокировки)")


func test_locked_gate_physically_blocks_body() -> void:
	var gate: AbilityGate = _spawn_gate(&"village_ledge", Vector2.ZERO)
	var body: TestMover = _spawn_mover(Vector2(-60.0, -8.0))
	await wait_physics_frames(40)
	assert_true(gate.blocking, "gate ещё закрыт")
	assert_lt(body.position.x, -16.0, "тело не прошло сквозь закрытый gate")
	assert_gt(body.get_slide_collision_count(), 0, "движение остановлено коллизией gate")

	GameState.add_ability(&"double_jump")
	await wait_physics_frames(2)
	assert_false(gate.blocking, "получение способности открыло gate")
	assert_true(gate.collision_shape.disabled, "коллизия снята после открытия")

	await wait_physics_frames(30)
	assert_gt(body.position.x, 0.0, "после открытия тело проходит препятствие")


func test_gate_hint_signal_for_hud_on_approach_and_after_acquire() -> void:
	var gate: AbilityGate = _spawn_gate(&"swamp_dash_gate", Vector2.ZERO)
	watch_signals(EventBus)
	var player: CharacterBody2D = _spawn_player_stub(Vector2(0.0, -12.0))
	await wait_physics_frames(3)
	assert_signal_emitted_with_parameters(
		EventBus,
		&"ability_hint_changed",
		[&"dash", true]
	)
	assert_true(gate.get_hint().is_shown(), "локальная подсказка тоже видна")

	GameState.add_ability(&"dash")
	await wait_physics_frames(2)
	assert_true(gate.is_open(), "gate открыт способностью")
	assert_false(gate.get_hint().is_shown(), "подсказка скрыта после получения")
	assert_signal_emitted_with_parameters(
		EventBus,
		&"ability_hint_changed",
		[&"dash", false]
	)
	player.queue_free()


# ------------------------------------------------------------------------------
# AC-04.3 — получение X открывает все gates с X, и только их
# ------------------------------------------------------------------------------

func test_ability_opens_all_matching_gates_only() -> void:
	var dash_gate: AbilityGate = _spawn_gate(&"swamp_dash_gate", Vector2(-100.0, 0.0))
	var wall_gate: AbilityGate = _spawn_gate(&"mountains_wall_climb", Vector2(100.0, 0.0))
	var village_gate: AbilityGate = _spawn_gate(&"village_ledge", Vector2(0.0, 0.0))
	assert_true(dash_gate.blocking)
	assert_true(wall_gate.blocking)
	assert_true(village_gate.blocking)

	GameState.add_ability(&"dash")
	assert_true(dash_gate.is_open(), "dash открыл свой gate")
	assert_false(dash_gate.get_hint().is_shown(), "подсказка dash-gate погасла")
	assert_true(wall_gate.blocking, "wall climb gate остался закрыт")
	assert_true(village_gate.blocking, "double jump gate остался закрыт")

	GameState.add_ability(&"wall_climb")
	assert_true(wall_gate.is_open(), "wall climb открыл свой gate")
	assert_true(village_gate.blocking, "чужой gate не открылся")

	GameState.add_ability(&"double_jump")
	assert_true(village_gate.is_open(), "double jump открыл свой gate")
	await wait_physics_frames(2)
	assert_true(dash_gate.collision_shape.disabled)
	assert_true(wall_gate.collision_shape.disabled)
	assert_true(village_gate.collision_shape.disabled)


func test_gate_spawned_after_ability_is_already_open() -> void:
	GameState.add_ability(&"wall_climb")
	var gate: AbilityGate = _spawn_gate(&"mountains_wall_climb", Vector2.ZERO)
	assert_true(gate.is_open(), "загрузка сейва: gate сразу открыт")
	assert_false(gate.get_hint().is_shown(), "подсказка не показывается")


# ------------------------------------------------------------------------------
# EC-10 — уже пройденный альтернативным путём проход не блокируется
# ------------------------------------------------------------------------------

func test_passed_gate_opens_without_ability_and_stays_open() -> void:
	var gate: AbilityGate = _spawn_gate(&"swamp_dash_gate", Vector2.ZERO)
	assert_true(gate.blocking, "до прохода gate закрыт")

	gate.mark_passed()
	assert_true(gate.is_passed(), "проход отмечен пройденным")
	assert_true(gate.is_open(), "пройденный gate не блокирует без dash")
	assert_false(gate.get_hint().is_shown(), "подсказка пройденного gate скрыта")

	gate.queue_free()
	await wait_process_frames(1)

	var again: AbilityGate = _spawn_gate(&"swamp_dash_gate", Vector2(80.0, 0.0))
	assert_true(again.is_open(), "новый gate с тем же gate_id тоже открыт (EC-10)")
	assert_false(again.blocking, "проход остаётся проходимым")


func test_static_mark_opens_gate_before_spawn() -> void:
	AbilityGate.mark_gate_passed(&"mountains_dash_ledge")
	var gate: AbilityGate = _spawn_gate(&"mountains_dash_ledge", Vector2.ZERO)
	assert_true(gate.is_open(), "маршрут отмечен до входа в зону — gate открыт")
	assert_false(gate.get_hint().is_shown(), "подсказки нет")


func test_visited_proof_zone_opens_gate_without_ability() -> void:
	var gate: AbilityGate = _spawn_gate(&"mountains_wall_climb", Vector2.ZERO)
	assert_true(gate.blocking, "до альтернативного маршрута gate закрыт")
	assert_eq(
		gate.get_proof_zone_id(),
		&"zone_04_ruins",
		"proof-зона берётся из данных ability_gates.tres"
	)

	SceneRouter.mark_zone_visited(&"zone_04_ruins")
	assert_true(gate.is_open(), "руины уже достигнуты другим путём — gate не блокирует")
	assert_false(gate.get_hint().is_shown(), "подсказка не нужна")


func test_restore_passed_gates_opens_live_and_future_gates() -> void:
	# Integration-01 (schema v6): загрузка сейва при уже созданной зоне.
	var gate: AbilityGate = _spawn_gate(&"swamp_dash_gate", Vector2.ZERO)
	assert_true(gate.blocking, "до восстановления gate закрыт")

	AbilityGate.restore_passed_gates(["swamp_dash_gate"])
	assert_true(AbilityGate.is_gate_passed(&"swamp_dash_gate"), "набор восстановлен")
	assert_true(gate.is_open(), "живой пройденный gate открыт без способности (EC-10)")
	assert_false(gate.get_hint().is_shown(), "подсказка скрыта")

	var again: AbilityGate = _spawn_gate(&"swamp_dash_gate", Vector2(80.0, 0.0))
	assert_true(again.is_open(), "новый gate с тем же gate_id тоже открыт")

	# Повторное восстановление идемпотентно и заменяет набор.
	AbilityGate.restore_passed_gates(["swamp_dash_gate"])
	assert_eq(AbilityGate.get_passed_gate_ids().size(), 1, "дубликаты не появляются")
	AbilityGate.restore_passed_gates([])
	assert_false(AbilityGate.is_gate_passed(&"swamp_dash_gate"), "пустой сейв заменяет набор")


func test_other_visited_zone_does_not_open_gate() -> void:
	SceneRouter.mark_zone_visited(&"zone_02_swamp")
	var gate: AbilityGate = _spawn_gate(&"village_ledge", Vector2.ZERO)
	assert_true(gate.blocking, "чужая посещённая зона не открывает уступ")


# ------------------------------------------------------------------------------
# Хелперы
# ------------------------------------------------------------------------------

func _spawn_gate(gate_id: StringName, at: Vector2) -> AbilityGate:
	var gate: AbilityGate = GATE_SCENE.instantiate() as AbilityGate
	gate.gate_id = gate_id
	gate.position = at
	add_child_autofree(gate)
	return gate


func _spawn_player_stub(at: Vector2) -> CharacterBody2D:
	var player := CharacterBody2D.new()
	player.position = at
	player.collision_layer = PLAYER_LAYER
	player.collision_mask = 0
	player.add_to_group(&"player")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10.0, 20.0)
	shape.shape = rect
	player.add_child(shape)
	add_child_autofree(player)
	return player


func _spawn_mover(at: Vector2) -> TestMover:
	var body := TestMover.new()
	body.name = "GateTestMover"
	body.position = at
	body.constant_velocity = Vector2(MOVE_SPEED, 0.0)
	body.collision_layer = PLAYER_LAYER
	body.collision_mask = WORLD_LAYER
	body.add_to_group(&"player")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8.0, 16.0)
	shape.shape = rect
	body.add_child(shape)
	add_child_autofree(body)
	return body
