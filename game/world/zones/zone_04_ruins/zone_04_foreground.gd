extends Node2D
## Передний план зоны 4 «Руины-храм» (T-16): редкие угли, пыль и пепел.
##
## «Гнетущая тишина»: движение почти отсутствует — 10 угольков медленно
## поднимаются над костром, 16 пылинок висят в воздухе. Никаких партиклов
## и шейдеров, один `_draw` за кадр; ввод не затрагивается.

const VIEW_WIDTH := 480.0
const FLOOR_TOP := 224.0
const EMBER_COUNT := 10
const DUST_COUNT := 16

const BONFIRE_AT := Vector2(288.0, 220.0)

var _time: float = 0.0
var _embers: Array[Vector2] = []
var _dust: Array[Vector2] = []


func _ready() -> void:
	for index in EMBER_COUNT:
		_embers.append(Vector2(
			BONFIRE_AT.x + (_hash(index, 53) - 0.5) * 20.0,
			BONFIRE_AT.y - _hash(index, 59) * 12.0
		))
	for index in DUST_COUNT:
		_dust.append(Vector2(
			_hash(index, 61) * VIEW_WIDTH,
			110.0 + _hash(index, 67) * 100.0
		))
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Количество угольков (для тестов и настройки).
func get_ember_count() -> int:
	return _embers.size()


func _draw() -> void:
	_draw_embers()
	_draw_dust()
	_draw_ash_edge()


func _draw_embers() -> void:
	for index in _embers.size():
		var seed := _embers[index]
		var rise := fposmod(_time * (6.0 + float(index % 4)) + seed.y * 4.0, 26.0)
		var sway := sin(_time * 1.1 + float(index) * 1.7) * 3.0
		var at := Vector2(seed.x + sway, seed.y - rise)
		var color := UITokens.GOLD if index % 3 == 0 else UITokens.GOLD_9
		draw_rect(Rect2(at, Vector2(1.0, 1.0)), color)
		# Уголёк гаснет в верхней точке.
		if rise > 18.0:
			draw_rect(Rect2(at + Vector2(1.0, 1.0), Vector2(1.0, 1.0)), UITokens.BLOOD)


func _draw_dust() -> void:
	for index in _dust.size():
		var seed := _dust[index]
		var drift := sin(_time * 0.35 + float(index) * 0.9) * 4.0
		var at := Vector2(seed.x + drift, seed.y + cos(_time * 0.27 + float(index)) * 2.0)
		var alpha := 0.18 + 0.12 * _hash(index, 71)
		draw_rect(Rect2(at, Vector2(1.0, 1.0)), Color(UITokens.BONE, alpha))


func _draw_ash_edge() -> void:
	# Пепел и мелкая крошка на полу храма.
	for x in range(0, int(VIEW_WIDTH), 3):
		if _hash(x, 73) < 0.55:
			continue
		var height := 1.0 + floorf(_hash(x, 79) * 2.0)
		draw_rect(Rect2(float(x), FLOOR_TOP - height, 2.0, height), UITokens.STONE_9)


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
