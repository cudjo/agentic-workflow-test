extends Node2D
## Передний план зоны 1 (T-14): влажная земля поверх тайлового пола —
## лужи с отражениями, мох по кромке, бочки у ворот. Только графика, без коллизий.

const VIEW_WIDTH := 480.0
const FLOOR_TOP := 224.0

const PUDDLES: Array[Rect2] = [
	Rect2(140.0, 230.0, 52.0, 5.0),
	Rect2(214.0, 252.0, 38.0, 4.0),
	Rect2(300.0, 239.0, 40.0, 4.0),
	Rect2(36.0, 246.0, 30.0, 3.0),
]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_moss_edge()
	_draw_wet_ground()
	_draw_puddles()
	_draw_barrels()
	_draw_ledge_face()
	_draw_rubble_cap()


func _draw_ledge_face() -> void:
	# Передняя кромка уступа под one-way тайлами: камень + 1 px светлый кант.
	draw_rect(Rect2(304.0, 183.0, 112.0, 9.0), UITokens.STONE_9)
	draw_rect(Rect2(304.0, 183.0, 112.0, 1.0), UITokens.STONE_3)
	var brick_x := 304.0
	while brick_x < 416.0:
		draw_rect(Rect2(brick_x + 1.0, 185.0, 14.0, 6.0), UITokens.STONE)
		draw_rect(Rect2(brick_x + 1.0, 185.0, 14.0, 1.0), UITokens.STONE_3)
		brick_x += 16.0


func _draw_rubble_cap() -> void:
	# Завал: вершина совпадает с верхом коллизии (y≈164), чтобы блокировка
	# была видимой, а не «невидимой стеной» (AC-02.4). Камни рисуются поверх
	# растянутого prop'а и читаются единой грудой.
	draw_rect(Rect2(424.0, 214.0, 14.0, 10.0), UITokens.STONE_9)
	draw_rect(Rect2(438.0, 211.0, 16.0, 13.0), UITokens.STONE)
	draw_rect(Rect2(454.0, 210.0, 18.0, 14.0), UITokens.STONE_9)
	draw_rect(Rect2(427.0, 196.0, 17.0, 16.0), UITokens.STONE)
	draw_rect(Rect2(445.0, 192.0, 19.0, 18.0), UITokens.STONE_3)
	draw_rect(Rect2(430.0, 183.0, 15.0, 12.0), UITokens.STONE_9)
	draw_rect(Rect2(447.0, 181.0, 13.0, 11.0), UITokens.STONE)
	draw_rect(Rect2(434.0, 172.0, 20.0, 11.0), UITokens.STONE)
	draw_rect(Rect2(438.0, 164.0, 11.0, 8.0), UITokens.STONE_3)
	draw_rect(Rect2(438.0, 164.0, 11.0, 1.0), UITokens.STONE_5)
	draw_rect(Rect2(434.0, 172.0, 20.0, 1.0), UITokens.STONE_3)
	# Трещины/тени, чтобы груда не читалась монолитом.
	draw_rect(Rect2(444.0, 196.0, 1.0, 8.0), UITokens.STONE_9)
	draw_rect(Rect2(452.0, 186.0, 1.0, 7.0), UITokens.STONE_9)
	draw_rect(Rect2(432.0, 205.0, 1.0, 6.0), UITokens.STONE_3)


func _draw_moss_edge() -> void:
	for x in range(0, int(VIEW_WIDTH)):
		if _hash(x, 61) > 0.55:
			var height := 1.0 + floorf(_hash(x, 67) * 2.0)
			draw_rect(Rect2(float(x), FLOOR_TOP - height, 1.0, height), UITokens.GREEN_3)


func _draw_wet_ground() -> void:
	for x in range(0, int(VIEW_WIDTH), 2):
		for y in range(int(FLOOR_TOP) + 2, 270, 4):
			var value := _hash(x, y)
			if value < 0.12:
				draw_rect(Rect2(float(x), float(y), 2.0, 1.0), UITokens.BROWN_9)
			elif value > 0.94:
				draw_rect(Rect2(float(x), float(y), 1.0, 1.0), UITokens.BROWN_3)


func _draw_puddles() -> void:
	for puddle: Rect2 in PUDDLES:
		draw_rect(puddle, UITokens.STEEL_9)
		draw_rect(Rect2(puddle.position.x, puddle.position.y, puddle.size.x, 1.0), UITokens.STEEL)
	# Тёплые отражения факелов и костра.
	for glint: Vector2 in [Vector2(174.0, 231.0), Vector2(186.0, 233.0), Vector2(160.0, 232.0), Vector2(310.0, 240.0)]:
		draw_rect(Rect2(glint, Vector2(1.0, 1.0)), UITokens.GOLD_9)


func _draw_barrels() -> void:
	_draw_barrel(Rect2(262.0, 206.0, 14.0, 16.0))
	_draw_barrel(Rect2(278.0, 210.0, 16.0, 12.0))


func _draw_barrel(rect: Rect2) -> void:
	draw_rect(rect, UITokens.BROWN_3)
	draw_rect(Rect2(rect.position.x, rect.position.y + 3.0, rect.size.x, 1.0), UITokens.BROWN_9)
	draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y - 4.0, rect.size.x, 1.0), UITokens.BROWN_9)
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1.0), UITokens.BROWN)
	draw_rect(Rect2(rect.position.x + 3.0, rect.position.y, 1.0, rect.size.y), UITokens.BROWN)


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
