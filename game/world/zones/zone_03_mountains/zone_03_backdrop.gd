extends Node2D
## Ближний план зоны 3 «Горный перевал» (T-15): скальные полки, ельник,
## снежные шапки и лёд у подножия. Только графика — коллизии в TileMapLayer.

const VIEW_WIDTH := 480.0
const VIEW_HEIGHT := 270.0
const FLOOR_TOP := 224.0

const PINES: Array[Vector2] = [
	Vector2(20.0, 150.0),
	Vector2(58.0, 168.0),
	Vector2(228.0, 158.0),
	Vector2(268.0, 172.0),
	Vector2(352.0, 164.0),
	Vector2(438.0, 152.0),
]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_cliffs()
	_draw_pines()
	_draw_snow_line()
	_draw_ground_base()
	_draw_ice_ledges()


func _draw_cliffs() -> void:
	# Скальные полки по краям сцены (задний план для тайловых шахт).
	draw_rect(Rect2(0.0, 124.0, 26.0, FLOOR_TOP - 124.0), UITokens.STONE_9)
	draw_rect(Rect2(454.0, 112.0, 26.0, FLOOR_TOP - 112.0), UITokens.STONE_9)
	draw_rect(Rect2(0.0, 124.0, 26.0, 2.0), UITokens.STONE_5)
	draw_rect(Rect2(454.0, 112.0, 26.0, 2.0), UITokens.STONE_5)
	for x in range(2, 26, 6):
		draw_rect(Rect2(float(x), 132.0, 2.0, 82.0), UITokens.STONE)


func _draw_pines() -> void:
	for pine: Vector2 in PINES:
		var x := pine.x
		var base_y := pine.y
		draw_rect(Rect2(x, base_y - 8.0, 2.0, 8.0), UITokens.BROWN_9)
		var row := 0
		while row < 16:
			var half := 2.0 + float(row) * 0.7
			draw_rect(Rect2(x + 1.0 - half, base_y - 8.0 - float(row), half * 2.0, 1.0), UITokens.NIGHT_3)
			row += 1
		# Снег на лапах.
		draw_rect(Rect2(x, base_y - 22.0, 2.0, 1.0), UITokens.BONE)


func _draw_snow_line() -> void:
	draw_rect(Rect2(0.0, FLOOR_TOP - 2.0, VIEW_WIDTH, 2.0), UITokens.STONE_5)
	for x in range(0, int(VIEW_WIDTH), 3):
		if _hash(x, 11) > 0.5:
			draw_rect(Rect2(float(x), FLOOR_TOP - 3.0, 2.0, 1.0), UITokens.BONE)


func _draw_ground_base() -> void:
	draw_rect(Rect2(0.0, FLOOR_TOP, VIEW_WIDTH, VIEW_HEIGHT - FLOOR_TOP), UITokens.STONE_9)
	draw_rect(Rect2(0.0, FLOOR_TOP, VIEW_WIDTH, 1.0), UITokens.STONE_5)
	for x in range(0, int(VIEW_WIDTH), 4):
		var value := _hash(x, 17)
		if value < 0.2:
			draw_rect(Rect2(float(x), FLOOR_TOP + 4.0 + value * 60.0, 2.0, 1.0), UITokens.STONE)
		elif value > 0.88:
			draw_rect(Rect2(float(x), FLOOR_TOP + 1.0, 1.0, 2.0), UITokens.BONE)


func _draw_ice_ledges() -> void:
	# Ледяные наросты под будущими шахтами (визуальная подсказка wall climb).
	for ledge: Rect2 in [Rect2(176.0, 216.0, 32.0, 8.0), Rect2(336.0, 216.0, 32.0, 8.0)]:
		draw_rect(ledge, UITokens.STEEL_9)
		draw_rect(Rect2(ledge.position.x, ledge.position.y, ledge.size.x, 1.0), UITokens.STEEL_3)
		for x in range(int(ledge.position.x), int(ledge.position.x + ledge.size.x), 4):
			draw_rect(Rect2(float(x), ledge.position.y + 2.0, 1.0, 3.0), UITokens.STEEL)


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
