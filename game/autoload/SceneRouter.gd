extends Node
## SceneRouter — переходы между зонами, экран загрузки и позиция игрока (T-17).
##
## Поток одного перехода (AC-04.1, EC-12):
##   1. `change_zone()` разрешает WorldRoot, показывает LoadingScreen и запускает
##      фоновую загрузку сцены через `ResourceLoader.load_threaded_request()`;
##      физика игрока выключается, буфер ввода очищается — ввод игнорируется.
##   2. `_process()` поллит `load_threaded_get_status()`; блокирующих `load()` и
##      пауз нет, общий бюджет перехода — `load_timeout` (≤ 3 с).
##   3. По готовности заменяется только `Main/WorldRoot`: старая зона
##      освобождается, новая инстанцируется, игрок переносится в неё на точку
##      входа из ZoneData. HUD/UI/Toasts/Overlay остаются нетронутыми.
##   4. `Player.fall_death_y` привязывается к нижней границе `WorldBounds` зоны
##      (EC-03), а corpse-метка из `GameState` переспавнивается в зоне входа.
##   5. `EventBus.zone_loaded` — хук для кроссфейда музыки AudioManager (T-34).
##
## Точка старта игры — `bootstrap()` из `Main.gd`; `reset()` — новая игра/тесты.
##
## Fix-4a (B-01/B-02): и `bootstrap()`, и `change_zone()` принимают необязательную
## точку спавна игрока. Она нужна, когда игрок входит не через физическую точку
## входа, а по чекпоинту костра: загрузка слота (AC-05.1) и возрождение в зоне
## чекпоинта (AC-05.2) ставят игрока ровно в `GameState.respawn_position`.
## Такой вход помечается виртуальным `entry_id = checkpoint` — его нет в
## ZoneData, но позиция задаётся явно и не зависит от первой точки входа.

## Переход начат (зона ещё не активна). Потребители: тесты/QA, HUD.
signal transition_started(zone_id: StringName, entry_id: StringName)
## Переход завершён: новая зона в дереве, игрок на точке входа, экран скрыт.
signal transition_finished(zone_id: StringName, entry_id: StringName)
## Переход не выполнен (битый путь, таймаут). Старая зона остаётся активной.
signal transition_failed(zone_id: StringName, reason: String)
## Зона впервые показана в этом забеге (T-33, AC-04.2). Потребители: карта
## мира и миникарта — открывают комнаты зоны; сейв персистит список
## (`SaveSerializer`, schema v6) и восстанавливает его через
## `restore_visited_zones()`.
signal zone_visited(zone_id: StringName)

const DEFAULT_ZONE_ID: StringName = &"zone_01_village"
const DEFAULT_ENTRY_ID: StringName = &"start"
## Виртуальная точка входа «у костра»: позиция задаётся spawn_position, а не
## ZoneData.entry_points (в зоне 4/5 физической точки `start` нет).
const CHECKPOINT_ENTRY_ID: StringName = &"checkpoint"
const ZONE_SCENE_PATTERN: String = "res://world/zones/%s/%s.tscn"
const ZONE_DATA_PATTERN: String = "res://data/zones/%s.tres"
const LOADING_SCENE: PackedScene = preload("res://ui/loading/LoadingScreen.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const CORPSE_SCENE: PackedScene = preload("res://world/props/corpse.tscn")
const PLAYER_GROUP: StringName = &"player"
const CORPSE_GROUP: StringName = &"corpses"

## Жёсткий бюджет перехода (AC-04.1/NFR, T_load = 3 с).
const LOAD_TIMEOUT: float = 3.0
## Минимальное время показа экрана загрузки: даже мгновенная загрузка должна
## отрисовать экран (иначе он не появляется ни на одном кадре).
const MIN_LOADING_TIME: float = 0.05
## Пауза после входа, в течение которой выходы зоны игнорируются: игрок,
## поставленный на точку входа рядом с выходом, не должен сразу уйти обратно.
const EXIT_GRACE_TIME: float = 0.25

## Корень текущей зоны (Main/WorldRoot). В тестах задаётся `bind_world_root()`.
var world_root: Node2D
## Экран загрузки (создаётся лениво, один на игру).
var loading_screen: LoadingScreen
## Игрок, переносимый между зонами (создаётся при первом входе).
var player: Player
var current_zone: ZoneScene
var current_zone_id: StringName = &""
var current_entry_id: StringName = &""
## Посещённые зоны за забег (T-33, AC-04.2). Порядок — порядок первого входа;
## карта сортирует их по координатам комнат.
var visited_zone_ids: Array[StringName] = []
var is_loading: bool = false
## Длительность последнего успешного перехода, с (AC-04.1: ≤ 3 с).
var last_load_seconds: float = 0.0

## Настраиваемые в тестах тайминги (по умолчанию — константы выше).
var load_timeout: float = LOAD_TIMEOUT
var min_loading_time: float = MIN_LOADING_TIME
var exit_grace_time: float = EXIT_GRACE_TIME

var _pending_zone_id: StringName = &""
var _pending_entry_id: StringName = &""
var _pending_display_name: String = ""
var _pending_scene_path: String = ""
## Явная точка спавна игрока для следующего перехода (`Variant`: Vector2/null).
## `null` — использовать точку входа из ZoneData.
var _pending_spawn_position: Variant = null
## Отложенный запрос старта: MainMenu меняет сцену на Main, а `bootstrap()`
## в новой сцене забирает зону/вход/позицию отсюда (B-02).
var _bootstrap_request: Dictionary = {}
var _elapsed: float = 0.0
var _exit_grace_left: float = 0.0


func _ready() -> void:
	set_process(false)
	# T-33: карта узнаёт о зоне из того же события, что и AudioManager/HUD.
	# `_apply_zone` помечает зону раньше, повторный вызов идемпотентен.
	if EventBus.has_signal(&"zone_loaded"):
		if not EventBus.zone_loaded.is_connected(_on_zone_loaded):
			EventBus.zone_loaded.connect(_on_zone_loaded)


func _on_zone_loaded(zone_id: StringName, _display_name: String) -> void:
	mark_zone_visited(zone_id)


func _process(delta: float) -> void:
	_exit_grace_left = maxf(_exit_grace_left - delta, 0.0)
	if not is_loading:
		if is_zero_approx(_exit_grace_left):
			set_process(false)
		return

	_elapsed += delta
	if _elapsed > load_timeout:
		_fail_transition(_pending_zone_id, "timeout > %.2f s" % load_timeout)
		return

	var status: int = ResourceLoader.load_threaded_get_status(_pending_scene_path)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			# Даём экрану загрузки хотя бы один отрисованный кадр.
			if _elapsed >= min_loading_time:
				_complete_transition()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail_transition(_pending_zone_id, "scene load failed")


# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

## Загружает и инстанцирует сцену зоны, совместимую с WorldRoot (PLAN §2.3,
## контракт T-13). В дерево не добавляет — размещением управляет `change_zone()`
## либо тест/генератор. Возвращает null (и пишет ошибку) при нарушении контракта.
func instantiate_zone(scene_path: String) -> ZoneScene:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("SceneRouter: не удалось загрузить сцену зоны '%s'" % scene_path)
		return null

	var instance := packed.instantiate()
	if not instance is ZoneScene:
		push_error("SceneRouter: корень зоны '%s' должен быть ZoneScene (Node2D)" % scene_path)
		instance.free()
		return null

	var zone := instance as ZoneScene
	if zone.zone_data == null:
		push_error("SceneRouter: у сцены зоны '%s' не задан zone_data" % scene_path)
		zone.free()
		return null
	return zone


## Точка старта игры (Main.gd): первый вход в зону из сейва/по умолчанию.
## Сцена грузится синхронно: это не переход между зонами, а инициализация мира
## (дальше все переходы — фоновые через `change_zone`). Повторный вызов во
## время игры ничего не делает.
##
## `spawn_position` (Fix-4a, B-02): `Vector2` — поставить игрока явно (загрузка
## слота у костра, AC-05.1); `null` — обычная точка входа `entry_id`.
## Вызов без аргументов забирает отложенный запрос `request_bootstrap()`
## (MainMenu → смена сцены на Main).
func bootstrap(
	zone_id: StringName = &"",
	entry_id: StringName = DEFAULT_ENTRY_ID,
	spawn_position: Variant = null
) -> bool:
	if is_loading or current_zone_id != &"":
		return false

	if zone_id == &"" and not _bootstrap_request.is_empty():
		var request: Dictionary = _bootstrap_request
		_bootstrap_request = {}
		zone_id = StringName(str(request.get("zone_id", "")))
		entry_id = StringName(str(request.get("entry_id", DEFAULT_ENTRY_ID)))
		spawn_position = request.get("spawn_position", null)
	else:
		_bootstrap_request = {}

	var target: StringName = zone_id
	if target == &"" or not ResourceLoader.exists(zone_scene_path(target)):
		target = GameState.current_zone_id
	if target == &"" or not ResourceLoader.exists(zone_scene_path(target)):
		target = DEFAULT_ZONE_ID

	var path: String = zone_scene_path(target)
	if not ResourceLoader.exists(path):
		push_error("SceneRouter: сцена стартовой зоны '%s' не найдена (%s)" % [target, path])
		transition_failed.emit(target, "scene not found")
		return false
	var root: Node2D = _resolve_world_root()
	if root == null:
		push_error("SceneRouter: WorldRoot не найден — стартовая зона не загружена")
		transition_failed.emit(target, "WorldRoot is missing")
		return false

	var zone := instantiate_zone(path)
	if zone == null:
		transition_failed.emit(target, "zone contract is broken")
		return false

	var zone_id_actual: StringName = zone.zone_data.id
	_apply_zone(zone, root, entry_id, spawn_position)
	transition_finished.emit(zone_id_actual, entry_id)
	if EventBus.has_signal(&"zone_loaded"):
		EventBus.zone_loaded.emit(zone_id_actual, zone.zone_data.get_display_name())
	return true


## Отложенный старт: MainMenu задаёт зону/вход/позицию и меняет сцену на Main;
## `Main._ready()` вызывает `bootstrap()` без аргументов и забирает запрос.
## Нужен, чтобы загрузка слота у костра (AC-05.1) не теряла позицию при смене
## сцены. Повторный вызов перезаписывает запрос (последний старт побеждает).
func request_bootstrap(
	zone_id: StringName,
	entry_id: StringName = DEFAULT_ENTRY_ID,
	spawn_position: Variant = null
) -> void:
	_bootstrap_request = {
		"zone_id": zone_id,
		"entry_id": entry_id,
		"spawn_position": spawn_position,
	}


## Отменяет отложенный старт (смена сцены не удалась / повторный выбор слота).
func clear_bootstrap_request() -> void:
	_bootstrap_request = {}


## Начинает фоновый переход в зону `zone_id` на точку входа `entry_id`.
## `spawn_position` (Fix-4a): `Vector2` — явная позиция игрока (возрождение у
## костра в другой зоне, B-01); `null` — точка входа из ZoneData.
## Возвращает false, если переход уже идёт, путь зоны битый или нет WorldRoot.
func change_zone(
	zone_id: StringName,
	entry_id: StringName = DEFAULT_ENTRY_ID,
	spawn_position: Variant = null
) -> bool:
	if is_loading:
		return false
	var path: String = zone_scene_path(zone_id)
	if not ResourceLoader.exists(path):
		push_error("SceneRouter: сцена зоны '%s' не найдена (%s)" % [zone_id, path])
		transition_failed.emit(zone_id, "scene not found")
		return false

	var root: Node2D = _resolve_world_root()
	if root == null:
		push_error("SceneRouter: WorldRoot не найден — переход невозможен")
		transition_failed.emit(zone_id, "WorldRoot is missing")
		return false

	_pending_zone_id = zone_id
	_pending_entry_id = entry_id
	_pending_spawn_position = spawn_position
	_pending_scene_path = path
	var zone_data: ZoneData = _load_zone_data(zone_id)
	_pending_display_name = zone_data.get_display_name() if zone_data != null else String(zone_id)
	_elapsed = 0.0
	is_loading = true
	set_process(true)

	_show_loading(zone_data)
	_lock_player()

	var error: Error = ResourceLoader.load_threaded_request(path, "PackedScene", true)
	if error != OK:
		_fail_transition(zone_id, "threaded request failed (%d)" % error)
		return false

	transition_started.emit(zone_id, entry_id)
	return true


## true, пока идёт загрузка: ввод игрока не обрабатывается (EC-12).
func is_input_locked() -> bool:
	return is_loading


## Путь сцены зоны по конвенции `world/zones/<id>/<id>.tscn`.
func zone_scene_path(zone_id: StringName) -> String:
	return ZONE_SCENE_PATTERN % [String(zone_id), String(zone_id)]


# ------------------------------------------------------------------------------
# Visited zones (T-33, AC-04.2)
# ------------------------------------------------------------------------------

## Отмечает зону посещённой один раз. true — зона добавлена впервые.
func mark_zone_visited(zone_id: StringName) -> bool:
	if zone_id == &"" or visited_zone_ids.has(zone_id):
		return false
	visited_zone_ids.append(zone_id)
	zone_visited.emit(zone_id)
	return true


func is_zone_visited(zone_id: StringName) -> bool:
	return visited_zone_ids.has(zone_id)


## Копия списка для карты/сейва: мутация результата не меняет маршрут.
func get_visited_zone_ids() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(visited_zone_ids)
	return copy


## Восстанавливает карту из сейва/теста без сигналов (новая игра — пусто).
func restore_visited_zones(zone_ids: Array) -> void:
	visited_zone_ids.clear()
	for value: Variant in zone_ids:
		var zone_id: StringName = StringName(str(value))
		if zone_id != &"" and not visited_zone_ids.has(zone_id):
			visited_zone_ids.append(zone_id)


func reset_visited_zones() -> void:
	visited_zone_ids.clear()


## Привязка WorldRoot (Main или тестовый хост).
func bind_world_root(root: Node2D) -> void:
	world_root = root


func unbind_world_root() -> void:
	world_root = null


## Сбрасывает маршрутизатор (новая игра/тесты): отменяет переход, убирает экран,
## текущую зону и созданного игрока. Слои Main не трогает.
func reset() -> void:
	is_loading = false
	_pending_zone_id = &""
	_pending_entry_id = &""
	_pending_display_name = ""
	_pending_scene_path = ""
	_pending_spawn_position = null
	_bootstrap_request = {}
	_elapsed = 0.0
	_exit_grace_left = 0.0
	last_load_seconds = 0.0

	if loading_screen != null and is_instance_valid(loading_screen):
		loading_screen.hide_loading()
		var screen_parent: Node = loading_screen.get_parent()
		if screen_parent != null:
			screen_parent.remove_child(loading_screen)
		loading_screen.free()
	loading_screen = null

	if player != null and is_instance_valid(player):
		if player.get_parent() != null:
			player.get_parent().remove_child(player)
		player.free()
	player = null

	if current_zone != null and is_instance_valid(current_zone):
		if current_zone.get_parent() != null:
			current_zone.get_parent().remove_child(current_zone)
		current_zone.free()
	current_zone = null
	current_zone_id = &""
	current_entry_id = &""
	reset_visited_zones()

	if InputManager.has_method(&"clear_buffered_input"):
		InputManager.clear_buffered_input()
	set_process(false)


# ------------------------------------------------------------------------------
# Loading screen
# ------------------------------------------------------------------------------

func _show_loading(zone_data: ZoneData) -> void:
	_ensure_loading_screen()
	if loading_screen == null:
		return
	var display_name: String = _pending_display_name
	var epigraph: String = zone_data.get_epigraph() if zone_data != null else ""
	loading_screen.show_loading(display_name, epigraph)


func _ensure_loading_screen() -> void:
	if loading_screen != null and is_instance_valid(loading_screen):
		return
	var host: Node = _loading_host()
	if host == null:
		return
	loading_screen = LOADING_SCENE.instantiate() as LoadingScreen
	if loading_screen == null:
		push_error("SceneRouter: LoadingScreen.tscn has no LoadingScreen root")
		return
	host.add_child(loading_screen)


func _loading_host() -> Node:
	var root: Node2D = _resolve_world_root()
	if root != null and root.get_parent() != null:
		return root.get_parent()
	return get_tree().current_scene


# ------------------------------------------------------------------------------
# Transition
# ------------------------------------------------------------------------------

func _complete_transition() -> void:
	var packed := ResourceLoader.load_threaded_get(_pending_scene_path) as PackedScene
	if packed == null:
		_fail_transition(_pending_zone_id, "scene is not a PackedScene")
		return

	var zone := packed.instantiate() as ZoneScene
	if zone == null:
		_fail_transition(_pending_zone_id, "scene root is not ZoneScene")
		return
	if zone.zone_data == null:
		zone.free()
		_fail_transition(_pending_zone_id, "ZoneData is missing")
		return

	var root: Node2D = _resolve_world_root()
	if root == null:
		zone.free()
		_fail_transition(_pending_zone_id, "WorldRoot is missing")
		return

	_apply_zone(zone, root, _pending_entry_id, _pending_spawn_position)

	var zone_id: StringName = current_zone_id
	var entry_id: StringName = current_entry_id
	var display_name: String = _pending_display_name
	_finish_transition(zone_id, entry_id, display_name)


## Заменяет содержимое WorldRoot инстанцированной зоной и переносит игрока.
## Общий путь для фонового перехода и синхронного `bootstrap()`.
## `spawn_position` (Vector2) перекрывает точку входа — чекпоинт костра
## (AC-05.1/05.2); `null` — позиция из `entry_id`.
func _apply_zone(
	zone: ZoneScene,
	root: Node2D,
	entry_id: StringName,
	spawn_position: Variant = null
) -> void:
	_detach_player()
	_clear_world(root)

	current_zone = zone
	current_zone_id = zone.zone_data.id
	current_entry_id = entry_id
	mark_zone_visited(current_zone_id)
	root.add_child(zone)
	if not zone.exit_requested.is_connected(_on_zone_exit_requested):
		zone.exit_requested.connect(_on_zone_exit_requested)

	var player_position: Vector2 = _entry_position(zone, current_entry_id)
	if spawn_position is Vector2:
		player_position = spawn_position
	_attach_player(zone, player_position)
	_sync_corpse(zone)
	_exit_grace_left = exit_grace_time
	set_process(true)


func _finish_transition(zone_id: StringName, entry_id: StringName, display_name: String) -> void:
	last_load_seconds = _elapsed
	is_loading = false
	_pending_zone_id = &""
	_pending_entry_id = &""
	_pending_display_name = ""
	_pending_scene_path = ""
	_pending_spawn_position = null
	_elapsed = 0.0
	_unlock_player()
	if loading_screen != null and is_instance_valid(loading_screen):
		loading_screen.hide_loading()

	transition_finished.emit(zone_id, entry_id)
	# T-34: AudioManager подписывается и делает кроссфейд музыки (AC-07.2).
	if EventBus.has_signal(&"zone_loaded"):
		EventBus.zone_loaded.emit(zone_id, display_name)


func _fail_transition(zone_id: StringName, reason: String) -> void:
	push_error("SceneRouter: переход в '%s' не выполнен: %s" % [zone_id, reason])
	last_load_seconds = _elapsed
	is_loading = false
	var failed_id: StringName = zone_id
	_pending_zone_id = &""
	_pending_entry_id = &""
	_pending_display_name = ""
	_pending_scene_path = ""
	_pending_spawn_position = null
	_elapsed = 0.0
	_unlock_player()
	if loading_screen != null and is_instance_valid(loading_screen):
		loading_screen.hide_loading()
	transition_failed.emit(failed_id, reason)


func _clear_world(root: Node2D) -> void:
	var old_children: Array[Node] = []
	old_children.assign(root.get_children())
	for child: Node in old_children:
		root.remove_child(child)
		child.queue_free()
	if current_zone != null and is_instance_valid(current_zone) and current_zone.get_parent() != null:
		var zone_parent: Node = current_zone.get_parent()
		zone_parent.remove_child(current_zone)
		current_zone.queue_free()


# ------------------------------------------------------------------------------
# Player
# ------------------------------------------------------------------------------

func _lock_player() -> void:
	if player == null or not is_instance_valid(player):
		player = _find_player()
	if player == null or not is_instance_valid(player):
		return
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	if InputManager.has_method(&"clear_buffered_input"):
		InputManager.clear_buffered_input()


func _unlock_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	player.set_physics_process(true)
	if InputManager.has_method(&"clear_buffered_input"):
		InputManager.clear_buffered_input()


func _detach_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.get_parent() != null:
		player.get_parent().remove_child(player)


func _attach_player(zone: ZoneScene, entry_position: Vector2) -> void:
	if player == null or not is_instance_valid(player):
		player = _find_player()
	if player == null or not is_instance_valid(player):
		player = PLAYER_SCENE.instantiate() as Player
	if player == null:
		push_error("SceneRouter: Player.tscn has no Player root")
		return
	if player.get_parent() != null:
		player.get_parent().remove_child(player)
	zone.add_child(player)
	player.position = entry_position
	player.set_fall_limit_y(_fall_limit(zone))
	player.reset_player()
	player.set_physics_process(true)


func _find_player() -> Player:
	var existing := get_tree().get_first_node_in_group(PLAYER_GROUP) as Player
	if existing != null:
		return existing
	return null


## Нижняя граница зоны из `WorldBounds` (StaticBody2D + прямоугольные формы).
## За ней — пропасть (EC-03). Нет границ — проверка выключена (`INF`).
func _fall_limit(zone: ZoneScene) -> float:
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
	if not is_finite(bottom):
		return INF
	return bounds.global_position.y + bottom


## Позиция точки входа из ZoneData; неизвестный id — первая точка/ноль.
func _entry_position(zone: ZoneScene, entry_id: StringName) -> Vector2:
	var data: ZoneData = zone.zone_data
	if data == null:
		return Vector2.ZERO
	for entry: ZoneEntryPoint in data.entry_points:
		if entry != null and entry.id == entry_id:
			return entry.position
	if not data.entry_points.is_empty() and data.entry_points[0] != null:
		return data.entry_points[0].position
	return Vector2.ZERO


# ------------------------------------------------------------------------------
# Corpse run across transitions (T-26/T-17)
# ------------------------------------------------------------------------------

## Метка гибели живёт в GameState и переспавнивается при входе в её зону.
## Если DeathHandler уже в дереве, он спавнит метку по `zone_entered` — здесь
## дубликат не создаётся.
func _sync_corpse(zone: ZoneScene) -> void:
	if not GameState.has_corpse() or GameState.is_corpse_lost():
		return
	if GameState.corpse_zone_id != current_zone_id:
		return
	if _has_corpse_node_at(GameState.corpse_position):
		return
	var corpse := CORPSE_SCENE.instantiate() as Corpse
	if corpse == null:
		push_error("SceneRouter: corpse scene has no Corpse root")
		return
	zone.add_child(corpse)
	corpse.setup(GameState.corpse_position, false)


func _has_corpse_node_at(at_position: Vector2) -> bool:
	for node: Node in get_tree().get_nodes_in_group(CORPSE_GROUP):
		var corpse := node as Corpse
		if corpse == null or not is_instance_valid(corpse):
			continue
		if corpse.is_collected():
			continue
		if corpse.lost:
			continue
		if corpse.global_position.is_equal_approx(at_position):
			return true
	return false


# ------------------------------------------------------------------------------
# World root / exits
# ------------------------------------------------------------------------------

func _resolve_world_root() -> Node2D:
	if world_root != null and is_instance_valid(world_root) and world_root.is_inside_tree():
		return world_root
	var scene := get_tree().current_scene
	if scene != null:
		var node := scene.get_node_or_null("WorldRoot") as Node2D
		if node != null:
			world_root = node
			return node
	var main := get_node_or_null("/root/Main/WorldRoot") as Node2D
	if main != null:
		world_root = main
		return main
	return null


func _on_zone_exit_requested(
	exit_id: StringName,
	target_zone_id: StringName,
	target_entry_id: StringName
) -> void:
	if is_loading or _exit_grace_left > 0.0:
		return
	if target_zone_id == &"":
		push_warning("SceneRouter: exit '%s' has no target zone" % exit_id)
		return
	change_zone(target_zone_id, target_entry_id)


func _load_zone_data(zone_id: StringName) -> ZoneData:
	var path: String = ZONE_DATA_PATTERN % String(zone_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ZoneData
