extends Node2D
## Передний план зоны 5 «Финал» (T-16): пепел и две кровавые искры.
##
## Почти монохром: 14 серых пылинок и 2 редких blood-3 искры у рунных
## трещин. Движение медленное, без шума; один `_draw` за кадр.

const VIEW_WIDTH := 480.0
const VIEW_HEIGHT := 270.0
const ASH_COUNT := 14
const SPARK_COUNT := 2

var _time: float = 0.0
var _ash: Array[Vector2] = []


func _ready() -> void:
	for index in ASH_COUNT:
		_ash.append(Vector2(
			_hash(index, 43) * VIEW_WIDTH,
			_hash(index, 47) * VIEW_HEIGHT
		))
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Количество искр (для тестов): редкие акценты не разрастаются в «гирлянду».
func get_spark_count() -> int:
	return SPARK_COUNT


func _draw() -> void:
	for index in _ash.size():
		var seed := _ash[index]
		var x := fposmod(seed.x + _time * (2.0 + float(index % 3)) + sin(_time * 0.4 + float(index)) * 6.0, VIEW_WIDTH)
		var y := fposmod(seed.y + _time * (4.0 + float(index % 2) * 2.0), VIEW_HEIGHT)
		draw_rect(Rect2(x, y, 1.0, 1.0), Color(UITokens.BONE, 0.22))

	# Две blood-3 искры — у трещин монолитов (координаты совпадают с backdrop).
	for index in SPARK_COUNT:
		var base := Vector2(159.0, 128.0) if index == 0 else Vector2(405.0, 118.0)
		var pulse := 0.55 + 0.45 * sin(_time * 1.6 + float(index) * 2.0)
		draw_rect(Rect2(base + Vector2(-1.0, 6.0), Vector2(2.0, 1.0)), Color(UITokens.BLOOD_3, pulse))


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
