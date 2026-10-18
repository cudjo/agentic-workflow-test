class_name EnemySpawnEntry
extends Resource
## EnemySpawnEntry — одна группа спавна для `EnemySpawner` (T-12).
## Позиции задаются смещением от узла спавнера; `spacing` раскладывает
## несколько врагов по горизонтали.

@export var enemy_scene: PackedScene
@export var count: int = 1
@export var offset: Vector2 = Vector2.ZERO
## Шаг между врагами группы по X, px; 0 — все в одной точке.
@export var spacing: float = 0.0


func is_valid() -> bool:
	return enemy_scene != null and count > 0
