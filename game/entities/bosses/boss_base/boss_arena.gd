class_name BossArena
extends Node2D
## BossArena — арена босса (T-30): закрывает выходы на время боя и
## восстанавливает EC-09 при повторном входе.
##
## Контракт сцены:
##   * `Boss` (BossBase) — инстанс босса;
##   * `Trigger` (Area2D, маска слоя player) — вход игрока на арену;
##   * StaticBody2D-барьеры в группе `arena_barrier` — физические стены,
##     включаются (`collision_layer = world`) на время боя.
##
## Если `GameState.is_boss_defeated(boss_id)` уже true, босс не появляется,
## барьеры открыты, а отложенная награда выдаётся здесь — при следующем
## входе в зону (EC-09). Арт — программные заглушки через `_draw()`.

signal fight_started
signal fight_finished

const BARRIER_GROUP: StringName = &"arena_barrier"
const PLAYER_GROUP: StringName = &"player"

@export var boss_path: NodePath = ^"Boss"
@export var trigger_path: NodePath = ^"Trigger"
## Мировые границы арены (локальные для корня арены): босс не выходит за них.
@export var bounds: Rect2 = Rect2(8.0, 40.0, 464.0, 184.0)
## Стартовать бой сразу при загрузке (демо/тесты); в игре — по входу игрока.
@export var start_on_ready: bool = false

@export_group("Placeholder art")
@export var arena_size: Vector2 = Vector2(480.0, 270.0)
@export var sky_color: Color = Color(0.101961, 0.121569, 0.180392, 1.0)
@export var ground_color: Color = Color(0.231373, 0.180392, 0.133333, 1.0)
@export var accent_color: Color = Color(0.752941, 0.541176, 0.243137, 1.0)
@export var barrier_color: Color = Color(0.878431, 0.709804, 0.415686, 0.9)
@export var floor_height: float = 16.0

var boss: BossBase = null
var _trigger: Area2D = null
var _fight_started: bool = false
var _barriers_closed: bool = false
var _zone_id: StringName = &""


func _ready() -> void:
	add_to_group(&"boss_arena")
	boss = get_node_or_null(boss_path) as BossBase
	_trigger = get_node_or_null(trigger_path) as Area2D
	if _trigger != null:
		_trigger.body_entered.connect(_on_trigger_body_entered)
	_open_barriers()

	if boss != null and boss.data != null:
		_zone_id = boss.data.zone_id
		boss.defeated.connect(_on_boss_defeated)
		if GameState.is_boss_defeated(boss.data.id):
			boss.queue_free()
			boss = null
			GameState.claim_pending_boss_rewards(_zone_id)
		elif start_on_ready:
			start_fight.call_deferred()
	queue_redraw()


## Выход из зоны в бою (SceneRouter) не должен оставлять `in_combat` включённым.
func _exit_tree() -> void:
	if _fight_started:
		_fight_started = false
		GameState.set_in_combat(false)


## Открывает бой. Возвращает false, если босс уже побеждён/отсутствует.
func start_fight() -> bool:
	if _fight_started:
		return true
	if boss == null or not is_instance_valid(boss):
		# Повторный вход на арену после смерти босса: добираем награду EC-09.
		if _zone_id != &"":
			GameState.claim_pending_boss_rewards(_zone_id)
		GameState.set_in_combat(false)
		_open_barriers()
		return false

	if boss.data != null and GameState.is_boss_defeated(boss.data.id):
		boss.queue_free()
		boss = null
		GameState.claim_pending_boss_rewards(_zone_id)
		GameState.set_in_combat(false)
		_open_barriers()
		return false

	_fight_started = true
	_close_barriers()
	# EC-06 (Integration-02): бой блокирует не-боевые интерактивы и сохранение.
	GameState.set_in_combat(true)
	boss.arena_bounds = Rect2(global_position + bounds.position, bounds.size)
	if not boss.activate_fight():
		_fight_started = false
		GameState.set_in_combat(false)
		_open_barriers()
		return false
	fight_started.emit()
	return true


func is_fight_active() -> bool:
	return _fight_started


func are_barriers_closed() -> bool:
	return _barriers_closed


func get_boss() -> BossBase:
	return boss


func _on_trigger_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group(PLAYER_GROUP):
		return
	start_fight()


func _on_boss_defeated(_boss: BossBase) -> void:
	_fight_started = false
	GameState.set_in_combat(false)
	_open_barriers()
	fight_finished.emit()


func _close_barriers() -> void:
	_set_barriers_closed(true)


func _open_barriers() -> void:
	_set_barriers_closed(false)


func _set_barriers_closed(closed: bool) -> void:
	_barriers_closed = closed
	for node: Node in _barrier_nodes():
		if node is StaticBody2D:
			var body := node as StaticBody2D
			body.set_deferred(
				"collision_layer",
				CombatLayers.WORLD if closed else 0
			)
			body.set_deferred("collision_mask", 0)
	queue_redraw()


func _barrier_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(BARRIER_GROUP):
		if is_ancestor_of(node):
			result.append(node)
	return result


func _draw() -> void:
	# Фон и пол — программные заглушки за тем же контрактом сцены.
	draw_rect(Rect2(Vector2.ZERO, arena_size), sky_color)
	var floor_y: float = arena_size.y - floor_height
	draw_rect(Rect2(0.0, floor_y, arena_size.x, floor_height), ground_color)
	draw_rect(Rect2(0.0, 0.0, 8.0, floor_y), ground_color.darkened(0.25))
	draw_rect(Rect2(arena_size.x - 8.0, 0.0, 8.0, floor_y), ground_color.darkened(0.25))
	# Золотые створки барьера видны только когда выход закрыт.
	if _barriers_closed:
		draw_rect(Rect2(0.0, 0.0, 8.0, floor_y), barrier_color)
		draw_rect(Rect2(arena_size.x - 8.0, 0.0, 8.0, floor_y), barrier_color)
		draw_line(Vector2(0.0, 0.0), Vector2(arena_size.x, 0.0), accent_color, 1.0)
