extends Node2D
## Передний план зоны 3 (T-15): снегопад и позёмка.
##
## 26 снежинок дрейфуют вниз-вправо под ветром; позиции детерминированы
## (без RandomNumberGenerator) и обновляются простым сложением. Один _draw
## за кадр, без аллокаций — бюджет на 60 FPS с запасом.

const VIEW_WIDTH := 480.0
const VIEW_HEIGHT := 270.0
const FLAKE_COUNT := 26
const FLOOR_TOP := 224.0

var _flakes: Array[Vector2] = []
var _flake_speed: Array[float] = []
var _time: float = 0.0


func _ready() -> void:
	for index in FLAKE_COUNT:
		_flakes.append(Vector2(_hash(index, 3) * VIEW_WIDTH, _hash(index, 5) * VIEW_HEIGHT))
		_flake_speed.append(8.0 + _hash(index, 7) * 14.0)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	for index in _flakes.size():
		var flake := _flakes[index]
		flake.x += (12.0 + 6.0 * sin(_time * 0.7 + float(index))) * delta
		flake.y += _flake_speed[index] * delta
		if flake.y > VIEW_HEIGHT:
			flake.y = -2.0
		if flake.x > VIEW_WIDTH:
			flake.x = -2.0
		_flakes[index] = flake
	queue_redraw()


func _draw() -> void:
	_draw_snow_bank()
	_draw_flakes()
	_draw_ground_wind()


## Количество снежинок (для тестов).
func get_flake_count() -> int:
	return _flakes.size()


func _draw_flakes() -> void:
	for index in _flakes.size():
		var flake := _flakes[index]
		var color := UITokens.BONE if index % 3 != 0 else UITokens.STONE_5
		draw_rect(Rect2(floorf(flake.x), floorf(flake.y), 1.0, 1.0), Color(color, 0.7))


func _draw_snow_bank() -> void:
	draw_rect(Rect2(0.0, FLOOR_TOP - 1.0, VIEW_WIDTH, 1.0), Color(UITokens.BONE, 0.6))
	for x in range(0, int(VIEW_WIDTH), 5):
		if _hash(x, 13) > 0.55:
			draw_rect(Rect2(float(x), FLOOR_TOP - 2.0, 3.0, 1.0), Color(UITokens.BONE, 0.45))


func _draw_ground_wind() -> void:
	# Позёмка: низкие штрихи, бегущие по снегу.
	for index in 7:
		var x := fposmod(float(index) * 68.0 + _time * 38.0, VIEW_WIDTH + 30.0) - 15.0
		var y := FLOOR_TOP - 4.0 - float(index % 3) * 3.0
		draw_line(Vector2(x, y), Vector2(x - 10.0, y), Color(UITokens.STONE_5, 0.55), 1.0)


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
