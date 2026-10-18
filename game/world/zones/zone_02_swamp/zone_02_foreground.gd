extends Node2D
## Передний план зоны 2 «Болото» (T-15): камыш, ряска, пузыри и мокрая кромка.
## Только графика поверх тайлов; коллизий нет.

const VIEW_WIDTH := 480.0
const FLOOR_TOP := 224.0
const WATER_TOP := 208.0

const PUDDLES: Array[Rect2] = [
	Rect2(52.0, 230.0, 38.0, 4.0),
	Rect2(154.0, 246.0, 52.0, 5.0),
	Rect2(222.0, 232.0, 30.0, 4.0),
	Rect2(334.0, 250.0, 44.0, 4.0),
	Rect2(414.0, 236.0, 32.0, 3.0),
]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_reeds()
	_draw_moss_edge()
	_draw_puddles()
	_draw_water_surface()
	_draw_bubbles()


func _draw_reeds() -> void:
	for x in range(4, int(VIEW_WIDTH), 7):
		if _hash(x, 13) < 0.45:
			continue
		var height := 4.0 + floorf(_hash(x, 17) * 7.0)
		draw_rect(Rect2(float(x), FLOOR_TOP - height, 1.0, height), UITokens.GREEN_3)
		if _hash(x, 19) > 0.6:
			draw_rect(Rect2(float(x) + 1.0, FLOOR_TOP - height + 1.0, 2.0, 1.0), UITokens.GREEN)


func _draw_moss_edge() -> void:
	for x in range(0, int(VIEW_WIDTH)):
		if _hash(x, 23) > 0.48:
			var height := 1.0 + floorf(_hash(x, 29) * 2.0)
			draw_rect(Rect2(float(x), FLOOR_TOP - height, 1.0, height), UITokens.GREEN_3)


func _draw_puddles() -> void:
	for puddle: Rect2 in PUDDLES:
		draw_rect(puddle, UITokens.STEEL_9)
		draw_rect(Rect2(puddle.position.x, puddle.position.y, puddle.size.x, 1.0), UITokens.STEEL)
		draw_rect(Rect2(puddle.position.x + 3.0, puddle.position.y + 2.0, 5.0, 1.0), UITokens.GREEN_3)


func _draw_water_surface() -> void:
	# Блик по кромке воды (hazard-тайлы рисуются поверх — modulate steel-9).
	for pool: Rect2 in [Rect2(128.0, WATER_TOP, 80.0, 3.0), Rect2(256.0, WATER_TOP, 48.0, 3.0)]:
		draw_rect(pool, UITokens.STEEL)
		for x in range(int(pool.position.x), int(pool.position.x + pool.size.x), 6):
			draw_rect(Rect2(float(x), WATER_TOP + 3.0, 3.0, 1.0), UITokens.STEEL_3)
	# Ряска на поверхности.
	for i in 9:
		var x := 132.0 + floorf(_hash(i, 31) * 72.0)
		draw_rect(Rect2(x, WATER_TOP + 2.0 + floorf(_hash(i, 37) * 6.0), 2.0, 1.0), UITokens.GREEN_3)


func _draw_bubbles() -> void:
	for i in 12:
		var x := floorf(_hash(i, 41) * VIEW_WIDTH)
		var y := WATER_TOP + 3.0 + floorf(_hash(i, 43) * 9.0)
		draw_rect(Rect2(x, y, 1.0, 1.0), UITokens.STEEL_3)
		if i % 4 == 0:
			draw_rect(Rect2(x + 1.0, y - 2.0, 1.0, 1.0), UITokens.STEEL_9)


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
