extends Node2D
## Backdrop зоны 2 «Болото» (T-15, DESIGN §8.6, SPEC §5).
##
## Палитра зоны 2: green-9/green/green-3 (тёмная вода и мох), brown/brown-9
## (мокрая земля), steel-9 (туман). Рисует глухое небо, гнилые деревья,
## топь и редкие болотные огни. Только графика — коллизии в TileMapLayer
## и WorldBounds.

const VIEW_WIDTH := 480.0
const VIEW_HEIGHT := 270.0
const FLOOR_TOP := 224.0
const WATER_TOP := 208.0
const HORIZON := 172.0

const SKY_BANDS: Array[Color] = [
	UITokens.GREEN_9,
	UITokens.GREEN,
	UITokens.GREEN_3,
	UITokens.STEEL_9,
]

## Стволы мёртвых деревьев: x, высота, наклон ветвей.
const TREES: Array[Vector3] = [
	Vector3(36.0, 96.0, 1.0),
	Vector3(74.0, 68.0, -1.0),
	Vector3(118.0, 82.0, 1.0),
	Vector3(286.0, 88.0, -1.0),
	Vector3(338.0, 60.0, 1.0),
	Vector3(392.0, 78.0, -1.0),
	Vector3(452.0, 100.0, 1.0),
]

## Болотные огни (тусклое gold-9, DESIGN §8.6).
const WISPS: Array[Vector2] = [
	Vector2(132.0, 150.0),
	Vector2(246.0, 132.0),
	Vector2(388.0, 146.0),
]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_sky()
	_draw_horizon()
	_draw_dead_trees()
	_draw_mire()
	_draw_water()
	_draw_wisps()


func _draw_sky() -> void:
	var band_height := HORIZON / float(SKY_BANDS.size())
	for index in SKY_BANDS.size():
		draw_rect(
			Rect2(0.0, band_height * index, VIEW_WIDTH, band_height + 1.0),
			SKY_BANDS[index]
		)


func _draw_horizon() -> void:
	# Мутная полоса испарений на горизонте (steel-9 = болотный туман).
	for x in range(0, int(VIEW_WIDTH), 4):
		var top := HORIZON - 10.0 - 6.0 * (0.5 + 0.5 * sin(float(x) * 0.05))
		draw_rect(Rect2(float(x), top, 4.0, HORIZON - top), UITokens.STEEL_9)


func _draw_dead_trees() -> void:
	for tree: Vector3 in TREES:
		_draw_dead_tree(tree.x, tree.y, tree.z)


func _draw_dead_tree(x: float, height: float, lean: float) -> void:
	var base_y := FLOOR_TOP
	var top_y := base_y - height
	# Ствол с изломом: 3 px у земли, 1 px у вершины.
	draw_rect(Rect2(x, top_y + height * 0.45, 2.0, height * 0.55), UITokens.BROWN_9)
	draw_rect(Rect2(x + 0.5 * lean, top_y + height * 0.2, 1.0, height * 0.3), UITokens.BROWN_9)
	# Ветви-сучья.
	var branch_y := top_y + height * 0.34
	var branch := 0
	while branch < 3:
		var by := branch_y + float(branch) * 12.0
		var length := 8.0 + 4.0 * float(branch)
		draw_rect(Rect2(x - length * lean, by, length, 1.0), UITokens.BROWN_9)
		draw_rect(Rect2(x + 2.0, by + 4.0, length * 0.7, 1.0), UITokens.GREEN_9)
		branch += 1
	# Свисающий мох.
	if int(x) % 2 == 0:
		draw_rect(Rect2(x - 3.0 * lean, top_y + height * 0.42, 1.0, 10.0), UITokens.GREEN_3)


func _draw_mire() -> void:
	draw_rect(Rect2(0.0, FLOOR_TOP, VIEW_WIDTH, VIEW_HEIGHT - FLOOR_TOP), UITokens.BROWN_9)
	draw_rect(Rect2(0.0, FLOOR_TOP, VIEW_WIDTH, 2.0), UITokens.BROWN)
	for x in range(0, int(VIEW_WIDTH), 3):
		var value := _hash(x, 71)
		if value < 0.18:
			draw_rect(Rect2(float(x), FLOOR_TOP + 2.0 + value * 80.0, 2.0, 1.0), UITokens.BROWN)
		elif value > 0.9:
			draw_rect(Rect2(float(x), FLOOR_TOP + 1.0, 1.0, 2.0), UITokens.GREEN_3)


func _draw_water() -> void:
	# Вода в Hazard-слоях: x-диапазоны совпадают с тайлами hazard (колонки 8–12, 16–18).
	for pool: Rect2 in [Rect2(128.0, WATER_TOP, 80.0, 16.0), Rect2(256.0, WATER_TOP, 48.0, 16.0)]:
		draw_rect(pool, UITokens.STEEL_9)
		draw_rect(Rect2(pool.position.x, pool.position.y, pool.size.x, 1.0), UITokens.STEEL)
		for ripple in range(0, int(pool.size.x), 8):
			var rx := pool.position.x + float(ripple)
			draw_rect(Rect2(rx, pool.position.y + 4.0 + _hash(int(rx), 83) * 8.0, 4.0, 1.0), UITokens.STEEL)
	# Рябь и пузыри по всей топи.
	for i in 18:
		var x := floorf(_hash(i, 91) * VIEW_WIDTH)
		var y := WATER_TOP + 2.0 + floorf(_hash(i, 97) * 12.0)
		draw_rect(Rect2(x, y, 1.0, 1.0), UITokens.STEEL_3)
	# Мост из гнилых досок над водой.
	draw_rect(Rect2(120.0, WATER_TOP + 2.0, 32.0, 3.0), UITokens.BROWN)
	draw_rect(Rect2(120.0, WATER_TOP + 2.0, 32.0, 1.0), UITokens.BROWN_3)


func _draw_wisps() -> void:
	for wisp: Vector2 in WISPS:
		draw_rect(Rect2(wisp, Vector2(1.0, 1.0)), UITokens.GOLD_9)
		draw_rect(Rect2(wisp + Vector2(-2.0, 1.0), Vector2(1.0, 1.0)), UITokens.GREEN_3)


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
