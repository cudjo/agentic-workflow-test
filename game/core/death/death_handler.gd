class_name DeathHandler
extends Node
## DeathHandler — смерть, бюджет `t_death`, corpse run и возрождение (T-26).
##
## Поток (AC-05.2/05.3, EC-01/EC-03/EC-04/EC-05):
##   1. `EventBus.player_died` (Player.kill()/смертельный урон) →
##      `GameState.drop_corpse()`: инвентарь/валюта уходят в метку на месте
##      гибели, `death_active = true` (персист для EC-04).
##   2. Идёт бюджет `balance.t_death` (physics-tick). Действия игрока уже
##      прерваны FSM-состоянием Death (EC-01).
##   3. По истечении бюджета эмитится `EventBus.death_screen_requested(info)` —
##      хук для экрана смерти T-22. При `auto_respawn` игрок сразу возрождается
##      у последнего костра с полным HP; T-22 может выключить авто-возрождение
##      и вызвать `respawn()` по кнопке.
##   4. Узел Corpse спавнится после возрождения (не в момент смерти), чтобы
##      мёртвое тело на месте гибели не подобрало метку по контакту.
##
## EC-04: смерть персистится сразу (`SaveManager.save_slot` в
## `GameState.active_slot`). Если игра закрыта в бюджете смерти, загруженный
## сейв содержит `death_active`/corpse; `resolve_pending_death()` при загрузке
## даёт обычную смерть: возрождение у костра, потеря уже в метке.
##
## EC-05: повторная смерть до подбора помечает предыдущую метку потерянной
## навсегда (`GameState.drop_corpse` → `EventBus.corpse_lost`); узлы Corpse
## в мире становятся черепом и больше не подбираются.
##
## Узел ставится в постоянную сцену (Main/Overlay или рядом с игроком).
## Тесты вызывают `tick(delta)` напрямую с выключенным `_physics_process`.

const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const CORPSE_SCENE: PackedScene = preload("res://world/props/corpse.tscn")
const PLAYER_GROUP: StringName = &"player"
const CORPSE_GROUP: StringName = &"corpses"
const WORLD_ZONE_GROUP: StringName = &"world_zone"

## idle — смерть не обрабатывается; dying — идёт бюджет t_death;
## dead — бюджет истёк, ждём `respawn()` (T-22, auto_respawn = false).
var phase: StringName = &"idle"
var time_left: float = 0.0
## Позиция последней смерти (корректна в фазе dying/dead и после неё).
var death_position: Vector2 = Vector2.ZERO
## Снимок для экрана смерти: corpse info + признак потери предыдущей метки.
var last_death_info: Dictionary = {}

## Игрок; ищется по `player_path`, иначе по группе `player`.
@export var player_path: NodePath
## Данные таймингов; по умолчанию `GameState.balance` / `balancing.tres`.
@export var balance: BalancingParams
## Возрождать автоматически по истечении t_death. T-22 ставит false и вызывает
## `respawn()` из кнопки «Возродиться у костра».
@export var auto_respawn: bool = true
## Писать death-автосейв в активный слот (EC-04).
@export var persist_death: bool = true
## Слот death-автосейва; 0 — взять `GameState.active_slot`.
@export var death_save_slot: int = 0
## Контейнер для узла Corpse; иначе текущая зона (`world_zone`), иначе родитель.
@export var corpse_parent_path: NodePath

var player: Player
var corpse_parent: Node

var _fallback_position: Vector2 = Vector2.ZERO
var _corpse_node: Corpse = null


func _ready() -> void:
	if balance == null:
		balance = GameState.balance
	if balance == null:
		balance = load(BALANCE_PATH) as BalancingParams
	if balance == null:
		push_error("DeathHandler: balancing resource is missing at %s" % BALANCE_PATH)

	_resolve_player()
	if player != null:
		_fallback_position = player.global_position

	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)
	if not EventBus.zone_entered.is_connected(_on_zone_entered):
		EventBus.zone_entered.connect(_on_zone_entered)
	if not EventBus.save_loaded.is_connected(_on_save_loaded):
		EventBus.save_loaded.connect(_on_save_loaded)

	# EC-04: GameState уже содержит смерть из загруженного сейва — при загрузке
	# игра должна вести себя как после обычной смерти (без «отката»).
	if GameState.death_active:
		call_deferred(&"resolve_pending_death")


func _physics_process(delta: float) -> void:
	tick(delta)


## Продвигает бюджет смерти. Публичный для детерминированных GUT-тестов
## (узел добавляется с `set_physics_process(false)`).
func tick(delta: float) -> void:
	if phase != &"dying":
		return
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		_finish_death_budget()


## Начинает обработку смерти (обычно из `EventBus.player_died`).
func begin_death() -> void:
	if phase != &"idle":
		return
	_resolve_player()
	if player != null:
		death_position = player.global_position
	else:
		death_position = GameState.respawn_position

	var zone_id: StringName = GameState.current_zone_id
	var previous_lost: bool = false
	var previous_info: Dictionary = {}
	if GameState.has_corpse():
		previous_info = GameState.get_corpse_info()
	var drop_result: Dictionary = GameState.drop_corpse(zone_id, death_position)
	previous_lost = bool(drop_result.get("previous_lost", false))
	if previous_lost:
		previous_info = drop_result.get("previous", previous_info)
		_mark_world_corpses_lost()
	# Следующая метка — новый узел; старый (череп) остаётся в мире, но больше
	# не является «текущей» corpse-меткой.
	_corpse_node = null

	GameState.death_active = true
	last_death_info = GameState.get_corpse_info().duplicate(true)
	last_death_info["previous_lost"] = previous_lost
	last_death_info["previous"] = previous_info
	last_death_info["death_position"] = death_position
	last_death_info["zone_id"] = String(zone_id)

	_persist_death()
	phase = &"dying"
	time_left = balance.t_death if balance != null else 1.2


## Завершает бюджет: открывает экран смерти (хук T-22) и при auto_respawn
## возрождает игрока. Экран может вызвать `respawn()` сам.
func _finish_death_budget() -> void:
	time_left = 0.0
	phase = &"dead"
	EventBus.death_screen_requested.emit(last_death_info.duplicate(true))
	if auto_respawn:
		respawn()


## Возрождает игрока у последнего костра с полным HP (AC-05.2), спавнит
## corpse-метку в мире и очищает флаг смерти (EC-04). Идемпотентно.
func respawn() -> void:
	_resolve_player()
	var target_position: Vector2 = GameState.respawn_position
	if not GameState.has_checkpoint():
		target_position = _fallback_position if player != null else GameState.respawn_position

	GameState.reset_hp()
	GameState.death_active = false

	if player != null:
		player.global_position = target_position
		player.velocity = Vector2.ZERO
		player.reset_player()

	phase = &"idle"
	time_left = 0.0
	_spawn_corpse_from_state()
	EventBus.player_respawned.emit(GameState.respawn_zone_id, target_position)


## Разрешает смерть, загруженную из сейва (EC-04). Вызывается при загрузке
## слота/старте, если `GameState.death_active`. Никакого бюджета: потеря уже
## случилась до выхода из игры, при загрузке — обычное возрождение.
func resolve_pending_death() -> void:
	if not GameState.death_active:
		return
	respawn()


# ------------------------------------------------------------------------------
# Persistence (EC-04)
# ------------------------------------------------------------------------------

## Пишет death-автосейв в активный слот: выход в бюджете смерти не откатывает
## потерю (EC-04). Если слот не выбран (0), сейв не пишется — при следующей
## загрузке останется последнее ручное сохранение (ограничение MVP).
func _persist_death() -> void:
	if not persist_death:
		return
	var slot: int = death_save_slot
	if slot <= 0:
		slot = GameState.active_slot
	if not SaveManager.is_valid_slot(slot):
		return

	var previous: Dictionary = SaveManager.get_slot_metadata(slot)
	var zone_id: String = str(GameState.current_zone_id)
	var meta: Dictionary = {
		"zone_id": zone_id if not zone_id.is_empty() else str(previous.get("zone_id", "")),
		"zone_name": str(previous.get("zone_name", "")),
		"level": int(previous.get("level", 0)),
		"play_time": float(previous.get("play_time", 0.0)),
	}
	SaveManager.save_slot(slot, meta)


# ------------------------------------------------------------------------------
# Corpse nodes
# ------------------------------------------------------------------------------

## Спавнит Corpse по сохранённому состоянию, если метка в текущей зоне и не
## потеряна. Повторный вызов не дублирует узел.
func _spawn_corpse_from_state() -> void:
	if not GameState.has_corpse():
		return
	if GameState.is_corpse_lost():
		return
	var zone_id: StringName = GameState.current_zone_id
	# Метка из другой зоны не спавнится здесь; текущая зона ещё не загружена
	# (загрузка сейва до T-17) — тоже ждём `zone_entered`.
	if zone_id == &"" and GameState.corpse_zone_id != &"":
		return
	if zone_id != &"" and GameState.corpse_zone_id != &"" \
		and GameState.corpse_zone_id != zone_id:
		return
	if is_instance_valid(_corpse_node) and _corpse_node.is_inside_tree():
		return

	var container: Node = _corpse_container()
	if container == null:
		return
	var corpse: Corpse = CORPSE_SCENE.instantiate() as Corpse
	if corpse == null:
		push_error("DeathHandler: corpse scene has no Corpse root")
		return
	container.add_child(corpse)
	corpse.setup(GameState.corpse_position, false)
	_corpse_node = corpse


## Существующие узлы Corpse навсегда теряют содержимое (EC-05) — череп.
func _mark_world_corpses_lost() -> void:
	for node: Node in get_tree().get_nodes_in_group(CORPSE_GROUP):
		var corpse: Corpse = node as Corpse
		if corpse != null:
			corpse.mark_lost()


func _corpse_container() -> Node:
	if not corpse_parent_path.is_empty():
		corpse_parent = get_node_or_null(corpse_parent_path)
	if corpse_parent != null and is_instance_valid(corpse_parent):
		return corpse_parent
	var zones: Array[Node] = get_tree().get_nodes_in_group(WORLD_ZONE_GROUP)
	if not zones.is_empty():
		return zones[0]
	return get_parent()


# ------------------------------------------------------------------------------
# EventBus
# ------------------------------------------------------------------------------

func _on_player_died() -> void:
	begin_death()


func _on_zone_entered(zone_id: StringName, _display_name: String) -> void:
	# Смерть из загруженного сейва разрешается после появления зоны.
	if GameState.death_active:
		call_deferred(&"resolve_pending_death")
		return
	if GameState.has_corpse() and GameState.corpse_zone_id == zone_id:
		_spawn_corpse_from_state()


func _on_save_loaded(_slot: int) -> void:
	if GameState.death_active:
		call_deferred(&"resolve_pending_death")


func _resolve_player() -> void:
	if player != null and is_instance_valid(player):
		return
	if not player_path.is_empty():
		player = get_node_or_null(player_path) as Player
	if player != null:
		return
	if not is_inside_tree():
		return
	var nodes: Array[Node] = get_tree().get_nodes_in_group(PLAYER_GROUP)
	if not nodes.is_empty():
		player = nodes[0] as Player
