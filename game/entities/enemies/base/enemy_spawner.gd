class_name EnemySpawner
extends Node2D
## EnemySpawner — спавн врагов из данных-групп (T-12).
##
## Держит список `EnemySpawnEntry` (сцена + количество + смещение) и
## добавляет врагов детьми спавнера: точка спавна становится их `home`
## (центр патруля и leash), поэтому AI не выходит за пределы зоны.
## Спавнер следит за `died` каждого врага и сообщает `all_defeated`;
## нежить с возрождением не считается побеждённой до окончательной смерти.

signal enemy_spawned(enemy: Enemy)
signal all_defeated

@export var entries: Array[EnemySpawnEntry] = []
## Спавнить в `_ready()` (encounter-сцены). Тесты/скрипты выключают и зовут
## `spawn_all()` вручную.
@export var auto_spawn: bool = true

var spawned_count: int = 0
var defeated_count: int = 0

var _alive: Array[Enemy] = []


func _ready() -> void:
	if auto_spawn:
		spawn_all()


## Спавнит все группы; возвращает созданных врагов.
func spawn_all() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for entry: EnemySpawnEntry in entries:
		if entry == null or not entry.is_valid():
			push_warning("EnemySpawner: skipped invalid entry")
			continue
		for index: int in entry.count:
			var local_position: Vector2 = entry.offset + Vector2(entry.spacing * float(index), 0.0)
			var enemy: Enemy = spawn_one(entry.enemy_scene, local_position)
			if enemy != null:
				result.append(enemy)
	return result


## Спавн одного врага по локальному смещению от спавнера.
func spawn_one(scene: PackedScene, local_offset: Vector2) -> Enemy:
	if scene == null:
		push_warning("EnemySpawner: enemy_scene is null")
		return null
	var enemy: Enemy = scene.instantiate() as Enemy
	if enemy == null:
		push_error("EnemySpawner: scene root is not an Enemy")
		return null
	enemy.position = local_offset
	add_child(enemy)
	_alive.append(enemy)
	spawned_count += 1
	enemy.died.connect(_on_enemy_died)
	enemy_spawned.emit(enemy)
	return enemy


## Враги, которые ещё не погибли окончательно (включая возрождающуюся нежить).
func get_alive_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for enemy: Enemy in _alive:
		if is_instance_valid(enemy):
			result.append(enemy)
	return result


## Сколько врагов ещё не погибли окончательно.
func remaining_count() -> int:
	return get_alive_enemies().size()


func _on_enemy_died(enemy: Enemy) -> void:
	_alive.erase(enemy)
	defeated_count += 1
	if spawned_count > 0 and _alive.is_empty():
		all_defeated.emit()
