extends Node2D
## Арена финального босса (T-16 → T-32).
##
## T-16 оставила здесь только `BossSpawn` и контракт `get_arena_bounds()`.
## T-32 добавляет саму арену:
##   * спавнит финального босса в `BossSpawn` (ноги на полу арены);
##   * закрывает арену `StaticBody2D`-барьерами на время боя;
##   * блокирует `EndingExit` через `gate_on_boss_id` и открывает выход
##     после победы (проверка идёт по `GameState.is_boss_defeated`, EC-09);
##   * при повторном входе после победы босс не появляется, отложенная
##     награда добирается (`GameState.claim_pending_boss_rewards`).
##
## Арт — программные заглушки (рунический круг, золотые створки барьеров).
## Состояние боя — `GameState.in_combat` (EC-06: сохранение в бою запрещено).

signal fight_started
signal fight_finished

const BOSS_SCENE: PackedScene = preload(
	"res://entities/bosses/zone_05/zone_05_boss.tscn"
)
const BARRIER_GROUP: StringName = &"arena_barrier"
const PLAYER_GROUP: StringName = &"player"

## Локальные границы арены: отступ от стен и потолка, пол — на FLOOR_TOP.
@export var arena_bounds: Rect2 = Rect2(24.0, 40.0, 432.0, 184.0)
## Сцена финального босса (подменяется в тестах/будущих фазах).
@export var boss_scene: PackedScene = BOSS_SCENE
## Толщина физических створок на время боя.
@export var barrier_thickness: float = 4.0
## Стартовать бой сразу при загрузке (демо/тесты); в игре — по входу игрока.
@export var start_on_ready: bool = false
## Хук концовки, которому выставляется `gate_on_boss_id`.
@export var ending_hook_path: NodePath = ^"../EndingExit"

var boss: BossBase = null

var _trigger: Area2D = null
var _barriers: Array[StaticBody2D] = []
var _fight_started: bool = false
var _barriers_closed: bool = false
var _boss_id: StringName = &""
var _zone_id: StringName = &""

@onready var boss_spawn: Marker2D = get_node_or_null("BossSpawn") as Marker2D


func _ready() -> void:
	add_to_group(&"boss_arena_slot")
	_connect_player_events()
	_create_trigger()
	_create_barriers()
	_spawn_boss()
	_open_barriers()
	_sync_ending_gate()
	if start_on_ready:
		start_fight.call_deferred()
	queue_redraw()


## Выход из зоны 5 в бою не должен оставлять `GameState.in_combat`
## включённым (B-03): SceneRouter выгружает зону вместе с ареной.
func _exit_tree() -> void:
	if EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.disconnect(_on_player_died)
	if _fight_started:
		_fight_started = false
		GameState.set_in_combat(false)


func _connect_player_events() -> void:
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)


# ------------------------------------------------------------------------------
# Public API (T-16 contract + T-32)
# ------------------------------------------------------------------------------

## Мировая точка спавна финального босса (маркер `BossSpawn`).
func get_boss_spawn_position() -> Vector2:
	if boss_spawn != null:
		return boss_spawn.global_position
	return global_position + Vector2(240.0, 224.0)


func get_arena_bounds() -> Rect2:
	return Rect2(global_position + arena_bounds.position, arena_bounds.size)


func get_boss() -> BossBase:
	return boss


## Босс на арене отсутствует (EC-09 либо арена ещё не инициализирована).
func is_empty() -> bool:
	return boss == null


func is_fight_active() -> bool:
	return _fight_started


func are_barriers_closed() -> bool:
	return _barriers_closed


## Id босса — ключ EC-09 и `gate_on_boss_id` у выхода в концовку.
func get_boss_id() -> StringName:
	return _boss_id


## Открывает бой. Возвращает false, если босс уже побеждён/отсутствует.
func start_fight() -> bool:
	if _fight_started:
		return true
	if boss == null or not is_instance_valid(boss):
		_claim_pending_rewards()
		_open_barriers()
		return false
	if _boss_id != &"" and GameState.is_boss_defeated(_boss_id):
		_despawn_boss()
		_claim_pending_rewards()
		_open_barriers()
		return false

	_fight_started = true
	_close_barriers()
	GameState.set_in_combat(true)
	boss.arena_bounds = get_arena_bounds()
	if not boss.activate_fight():
		_fight_started = false
		GameState.set_in_combat(false)
		_open_barriers()
		return false
	fight_started.emit()
	return true


# ------------------------------------------------------------------------------
# Scene wiring
# ------------------------------------------------------------------------------

func _create_trigger() -> void:
	_trigger = Area2D.new()
	_trigger.name = "Trigger"
	_trigger.collision_layer = 0
	_trigger.collision_mask = CombatLayers.PLAYER_BODY
	_trigger.monitorable = false
	_trigger.position = arena_bounds.position + arena_bounds.size * 0.5

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = arena_bounds.size
	shape.shape = rect
	_trigger.add_child(shape)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_trigger_body_entered)


func _spawn_boss() -> void:
	if boss_scene == null:
		push_error("Zone05Arena: boss_scene is missing")
		return
	boss = boss_scene.instantiate() as BossBase
	if boss == null:
		push_error("Zone05Arena: boss scene is not a BossBase")
		return

	if boss.data != null:
		_boss_id = boss.data.id
		_zone_id = boss.data.zone_id
	if _boss_id != &"" and GameState.is_boss_defeated(_boss_id):
		# EC-09: побеждённый финальный босс не появляется при повторном входе.
		boss.free()
		boss = null
		_claim_pending_rewards()
		return

	boss.name = "Boss"
	add_child(boss)
	_place_boss_on_floor()
	boss.defeated.connect(_on_boss_defeated)


func _place_boss_on_floor() -> void:
	if boss == null:
		return
	var half_height: float = (
		boss.data.body_size.y * 0.5 if boss.data != null else 0.0
	)
	boss.global_position = get_boss_spawn_position() - Vector2(0.0, half_height)


func _create_barriers() -> void:
	var size := Vector2(barrier_thickness, arena_bounds.size.y)
	var center_y: float = arena_bounds.position.y + arena_bounds.size.y * 0.5
	_barriers.append(
		_make_barrier(
			"BarrierLeft",
			Vector2(arena_bounds.position.x, center_y),
			size
		)
	)
	_barriers.append(
		_make_barrier(
			"BarrierRight",
			Vector2(arena_bounds.position.x + arena_bounds.size.x, center_y),
			size
		)
	)


func _make_barrier(
	barrier_name: String,
	at: Vector2,
	size: Vector2
) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = barrier_name
	body.position = at
	body.collision_layer = 0
	body.collision_mask = 0
	body.add_to_group(BARRIER_GROUP)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	return body


func _sync_ending_gate() -> void:
	if _boss_id == &"":
		return
	var hook := get_node_or_null(ending_hook_path)
	if hook != null:
		hook.set(&"gate_on_boss_id", _boss_id)


# ------------------------------------------------------------------------------
# Fight lifecycle
# ------------------------------------------------------------------------------

func _on_trigger_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group(PLAYER_GROUP):
		return
	start_fight()


func _on_boss_defeated(_defeated_boss: BossBase) -> void:
	_fight_started = false
	GameState.set_in_combat(false)
	_open_barriers()
	fight_finished.emit()


## Смерть игрока на арене (B-03): бой прерывается, барьеры открываются,
## `in_combat` сбрасывается, чтобы после возрождения сохранение работало.
func _on_player_died() -> void:
	var was_active: bool = _fight_started
	_fight_started = false
	_abort_boss_fight()
	_open_barriers()
	GameState.reset_combat_state()
	if was_active:
		fight_finished.emit()


## Бой прерван смертью игрока: босс ждёт повторного входа на арену.
func _abort_boss_fight() -> void:
	if boss != null and is_instance_valid(boss):
		boss.fight_active = false


func _claim_pending_rewards() -> void:
	if _zone_id != &"":
		GameState.claim_pending_boss_rewards(_zone_id)


func _despawn_boss() -> void:
	if boss != null and is_instance_valid(boss):
		boss.queue_free()
	boss = null


func _set_barriers_closed(closed: bool) -> void:
	_barriers_closed = closed
	for body: StaticBody2D in _barriers:
		if body == null or not is_instance_valid(body):
			continue
		body.set_deferred(
			"collision_layer",
			CombatLayers.WORLD if closed else 0
		)
		body.set_deferred("collision_mask", 0)
	queue_redraw()


func _close_barriers() -> void:
	_set_barriers_closed(true)


func _open_barriers() -> void:
	_set_barriers_closed(false)


# ------------------------------------------------------------------------------
# Placeholder art
# ------------------------------------------------------------------------------

func _draw() -> void:
	# Рунический круг на полу в точке спавна (локальные координаты).
	var spawn_local := Vector2(240.0, 224.0) - global_position
	if boss_spawn != null:
		spawn_local = boss_spawn.position
	draw_arc(spawn_local + Vector2(0.0, -2.0), 16.0, 0.0, TAU, 20, UITokens.BLOOD_3, 1.0)
	draw_arc(spawn_local + Vector2(0.0, -2.0), 10.0, 0.0, TAU, 16, UITokens.BLOOD_9, 1.0)
	for index in 4:
		var angle := TAU * float(index) / 4.0
		var from := spawn_local + Vector2(cos(angle), sin(angle)) * 16.0
		var to := spawn_local + Vector2(cos(angle), sin(angle)) * 22.0
		draw_line(from + Vector2(0.0, -2.0), to + Vector2(0.0, -2.0), UITokens.BLOOD_3, 1.0)

	# Метки границ арены — бледные насечки на полу.
	var left := arena_bounds.position.x
	var right := arena_bounds.position.x + arena_bounds.size.x
	var floor_y := arena_bounds.position.y + arena_bounds.size.y
	for x: float in [left, right]:
		draw_rect(Rect2(x - 4.0, floor_y - 3.0, 8.0, 2.0), UITokens.STONE_5)
		draw_rect(Rect2(x - 1.0, floor_y - 10.0, 2.0, 8.0), UITokens.STONE_5)

	# Золотые створки видны только когда выход из арены закрыт.
	if _barriers_closed:
		for body: StaticBody2D in _barriers:
			if body == null or not is_instance_valid(body):
				continue
			draw_rect(
				Rect2(
					body.position.x - barrier_thickness * 0.5,
					arena_bounds.position.y,
					barrier_thickness,
					arena_bounds.size.y
				),
				UITokens.GOLD_3
			)
