extends Node2D
## Арена финального босса (T-16): пустая площадка и точка спавна для T-32.
##
## Контракт с T-32 (босс 5):
##   * `BossSpawn` (Marker2D) — точка появления финального босса;
##   * `get_boss_spawn_position()` — та же точка в мировых координатах;
##   * `get_arena_bounds()` — прямоугольник арены (босс не выходит за него,
##     T-32 передаёт его в BossBase.arena_bounds / BossArena.bounds);
##   * арена пустая: босс, барьеры и триггер боя добавляет T-32.
##
## Сейчас рисуется только рунический круг спавна (blood-3 — редкий акцент
## финала, DESIGN §8.6) и метки границ арены. Коллизий нет.

## Локальные границы арены: отступ от стен и потолка, пол — на FLOOR_TOP.
@export var arena_bounds: Rect2 = Rect2(24.0, 40.0, 432.0, 184.0)

@onready var boss_spawn: Marker2D = get_node_or_null("BossSpawn") as Marker2D


func _ready() -> void:
	add_to_group(&"boss_arena_slot")
	queue_redraw()


## Мировая точка спавна финального босса (T-32).
func get_boss_spawn_position() -> Vector2:
	if boss_spawn != null:
		return boss_spawn.global_position
	return global_position + Vector2(240.0, 224.0)


func get_arena_bounds() -> Rect2:
	return Rect2(global_position + arena_bounds.position, arena_bounds.size)


## Арена обязана оставаться пустой до T-32: ни босса, ни барьеров здесь нет.
func is_empty() -> bool:
	return get_child_count() == 1 and boss_spawn != null


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
