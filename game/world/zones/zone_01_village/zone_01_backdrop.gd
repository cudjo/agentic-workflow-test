extends Node2D
## Backdrop зоны 1 «Деревня-бастион» (T-14, DESIGN §8.6, макет zone-village.html).
##
## Программная заглушка арта за тем же контрактом: 480×270, палитра зоны 1
## из UITokens (stone/stone-3/brown/night + мох green-3, кровля brown-9).
## Рисует дальний план до тайлового слоя: небо, луну, хребты, силуэт замка,
## каменную стену-бастион с мхом, стяг, ворота с поднятой решёткой, хижину
## с тёплым окном, опоры уступа и влажную землю.
##
## Коллизии зоны — в TileMapLayer и WorldBounds; здесь только графика.

const VIEW_WIDTH := 480.0
const VIEW_HEIGHT := 270.0

const WALL_TOP := 112.0
const FLOOR_TOP := 224.0
const GATE_CENTER_X := 212.0
const GATE_SPRING_Y := 164.0
const HUT_RIGHT := 96.0
const LEDGE_LEFT := 304.0
const LEDGE_RIGHT := 416.0
const LEDGE_TOP := 176.0
const LEDGE_FACE := 192.0

const FAR_RIDGE := Color("#161b27")
const NEAR_RIDGE := Color("#1a2030")
const CASTLE := Color("#10141d")
const BRICK_TONES := [
	Color("#4a4a4f"),
	Color("#44444a"),
	Color("#505056"),
	Color("#3f3f45"),
]
const BRICK_MORTAR := Color("#2b2b30")
const BRICK_HIGHLIGHT := Color("#5a5a60")


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_sky()
	_draw_stars()
	_draw_moon()
	_draw_ridges()
	_draw_castle()
	_draw_wall()
	_draw_banner()
	_draw_gate()
	_draw_torch_brackets()
	_draw_hut()
	_draw_ledge_supports()
	_draw_ground_base()
	_draw_ledge_door()


func _draw_ledge_door() -> void:
	# Проём в стене за дверью на уступе (сам prop Door рисуется поверх).
	draw_rect(Rect2(399.0, 143.0, 18.0, 33.0), UITokens.STONE_9)
	draw_rect(Rect2(401.0, 145.0, 14.0, 31.0), UITokens.VOID)
	draw_rect(Rect2(398.0, 142.0, 20.0, 2.0), UITokens.STONE_5)


func _draw_sky() -> void:
	var bands: Array[Color] = [UITokens.NIGHT_9, UITokens.NIGHT, UITokens.NIGHT_3, UITokens.NIGHT_5]
	var band_height := 170.0 / float(bands.size())
	for index in bands.size():
		draw_rect(
			Rect2(0.0, band_height * index, VIEW_WIDTH, band_height + 1.0),
			bands[index]
		)


func _draw_stars() -> void:
	for i in 90:
		var x := floorf(_hash(i, 17) * VIEW_WIDTH)
		var y := floorf(_hash(i, 23) * 120.0) + 2.0
		var color := UITokens.STONE_5 if _hash(i, 31) > 0.3 else UITokens.BONE
		draw_rect(Rect2(x, y, 1.0, 1.0), color)


func _draw_moon() -> void:
	draw_circle(Vector2(250.0, 46.0), 13.0, UITokens.BONE)
	draw_circle(Vector2(255.0, 43.0), 12.0, UITokens.NIGHT)
	draw_rect(Rect2(244.0, 50.0, 3.0, 2.0), UITokens.STONE_5)
	draw_rect(Rect2(248.0, 54.0, 2.0, 2.0), UITokens.STONE_5)


func _draw_ridges() -> void:
	# Дальний хребет: 1 px-колонки, как в макете.
	for x in range(0, int(VIEW_WIDTH), 2):
		var top := 150.0 - 22.0 * (0.5 + 0.5 * sin(float(x) * 0.035))
		draw_rect(Rect2(float(x), top, 2.0, 170.0 - top), FAR_RIDGE)
	# Средний хребет у основания стены.
	for x in range(0, int(VIEW_WIDTH), 3):
		var top_near := 176.0 - 10.0 * (0.5 + 0.5 * sin(float(x) * 0.07 + 1.2))
		draw_rect(Rect2(float(x), top_near, 3.0, WALL_TOP + 4.0 - top_near), NEAR_RIDGE)


func _draw_castle() -> void:
	# Силуэт замка на утёсе (за стеной): башни + шпили + редкие окна.
	var towers: Array = [
		[0, 26, 60, true],
		[30, 34, 44, false],
		[70, 40, 84, true],
		[116, 30, 52, false],
		[150, 26, 70, true],
		[180, 38, 46, false],
	]
	var base_x := 110.0
	var ground_y := 150.0
	for k in towers.size():
		var tower: Array = towers[k]
		var x := base_x + float(tower[0])
		var width := float(tower[1])
		var height := float(tower[2])
		var top := ground_y - height
		draw_rect(Rect2(x, top, width, height), CASTLE)
		if bool(tower[3]):
			var spire_height := roundf(width * 1.5)
			for row in int(spire_height):
				var ww := maxf(2.0, roundf((width + 4.0) * (1.0 - float(row) / spire_height)))
				draw_rect(Rect2(x + roundf((width - ww) * 0.5), top - float(row) - 1.0, ww, 1.0), CASTLE)
		else:
			var battle := 0.0
			while battle < width:
				draw_rect(Rect2(x + battle, top - 3.0, 4.0, 3.0), CASTLE)
				battle += 6.0
		var window_y := top + 8.0
		while window_y < ground_y - 12.0:
			if _hash(k, int(window_y)) > 0.4:
				draw_rect(Rect2(x + floorf(width * 0.5) - 1.0, window_y, 2.0, 5.0), UITokens.GOLD_9)
			window_y += 14.0


func _draw_wall() -> void:
	draw_rect(Rect2(0.0, WALL_TOP, VIEW_WIDTH, FLOOR_TOP - WALL_TOP), BRICK_MORTAR)
	var row := 0
	var y := WALL_TOP + 2.0
	while y < FLOOR_TOP:
		var offset := float((row % 2) * 8)
		var x := -offset
		while x < VIEW_WIDTH:
			var tone: Color = BRICK_TONES[int(_hash(int(x), int(y)) * BRICK_TONES.size()) % BRICK_TONES.size()]
			var bx := maxf(x + 1.0, 0.0)
			var ex := minf(x + 16.0, VIEW_WIDTH)
			if ex > bx:
				draw_rect(Rect2(bx, y + 1.0, ex - bx, 6.0), tone)
				draw_rect(Rect2(bx, y + 1.0, ex - bx, 1.0), BRICK_HIGHLIGHT)
			x += 16.0
		row += 1
		y += 8.0

	# Зубцы по верху стены.
	var crenel_x := 0.0
	while crenel_x < VIEW_WIDTH:
		draw_rect(Rect2(crenel_x + 4.0, WALL_TOP - 8.0, 14.0, 8.0), BRICK_TONES[1])
		draw_rect(Rect2(crenel_x + 4.0, WALL_TOP - 8.0, 14.0, 1.0), BRICK_HIGHLIGHT)
		crenel_x += 24.0
	draw_rect(Rect2(0.0, WALL_TOP, VIEW_WIDTH, 2.0), BRICK_MORTAR)

	# Мох у основания: плотнее к земле (макет §8.6 «серые стены с мхом»).
	var threshold := 0.55
	for mx in range(0, int(VIEW_WIDTH)):
		var moss := _hash(mx, 41)
		if mx % 2 == 0 and moss > threshold:
			var length := 1.0 + floorf(_hash(mx, 43) * 3.0)
			draw_rect(Rect2(float(mx), FLOOR_TOP - length, 1.0, length), UITokens.GREEN_3)
	for pocket in 26:
		var px := floorf(_hash(pocket, 47) * VIEW_WIDTH)
		var py := FLOOR_TOP - 8.0 - floorf(_hash(pocket, 53) * 26.0)
		draw_rect(Rect2(px, py, 2.0, 1.0), UITokens.GREEN_3)


func _draw_banner() -> void:
	# Красный стяг деревни на стене (DESIGN §8.6).
	draw_rect(Rect2(280.0, 118.0, 18.0, 2.0), UITokens.BROWN_3)
	for row in 38:
		var notch := 0
		if row > 30:
			notch = row - 30
		draw_rect(Rect2(282.0 + notch, 120.0 + row, 14.0 - notch * 2.0, 1.0), UITokens.BLOOD)
	draw_rect(Rect2(288.0, 128.0, 2.0, 10.0), UITokens.GOLD_9)
	draw_rect(Rect2(285.0, 131.0, 8.0, 2.0), UITokens.GOLD_9)


func _draw_gate() -> void:
	# Каменная арка ворот: поднятая решётка, проход в зону 2.
	draw_rect(Rect2(GATE_CENTER_X - 32.0, GATE_SPRING_Y, 64.0, FLOOR_TOP - GATE_SPRING_Y), UITokens.STONE_3)
	draw_circle(Vector2(GATE_CENTER_X, GATE_SPRING_Y), 32.0, UITokens.STONE_3)
	# Светлый кант арки в 1 px (не заливает проём).
	draw_rect(Rect2(GATE_CENTER_X - 31.0, GATE_SPRING_Y, 1.0, FLOOR_TOP - GATE_SPRING_Y), UITokens.STONE_5)
	draw_rect(Rect2(GATE_CENTER_X + 30.0, GATE_SPRING_Y, 1.0, FLOOR_TOP - GATE_SPRING_Y), UITokens.STONE_5)
	draw_rect(Rect2(GATE_CENTER_X - 28.0, GATE_SPRING_Y, 56.0, FLOOR_TOP - GATE_SPRING_Y), UITokens.VOID)
	draw_circle(Vector2(GATE_CENTER_X, GATE_SPRING_Y), 28.0, UITokens.VOID)

	# Поднятая решётка: вертикальные прутья от арки вверх.
	var bar_x := GATE_CENTER_X - 25.0
	while bar_x < GATE_CENTER_X + 25.0:
		var top := GATE_SPRING_Y - sqrt(maxf(0.0, 784.0 - (bar_x - GATE_CENTER_X) * (bar_x - GATE_CENTER_X)))
		draw_rect(Rect2(bar_x, top, 2.0, GATE_SPRING_Y - top), UITokens.BROWN_3)
		bar_x += 6.0
	draw_rect(Rect2(GATE_CENTER_X - 28.0, GATE_SPRING_Y - 1.0, 56.0, 2.0), UITokens.BROWN)
	draw_rect(Rect2(GATE_CENTER_X - 28.0, GATE_SPRING_Y + 8.0, 56.0, 2.0), UITokens.BROWN)


func _draw_torch_brackets() -> void:
	for tx: float in [171.0, 257.0]:
		draw_rect(Rect2(tx, 168.0, 2.0, 12.0), UITokens.BROWN_3)
		draw_rect(Rect2(tx - 2.0, 166.0, 6.0, 3.0), UITokens.STONE_9)
		draw_rect(Rect2(tx - 1.0, 180.0, 4.0, 2.0), UITokens.STONE_9)
		# Пламя (эмиссивный акцент; свет даёт PointLight2D).
		draw_rect(Rect2(tx - 1.0, 158.0, 4.0, 6.0), UITokens.GOLD)
		draw_rect(Rect2(tx, 155.0, 2.0, 4.0), UITokens.GOLD_3)


func _draw_hut() -> void:
	# Хижина: брёвна, тёмная кровля, тёплое окно.
	draw_rect(Rect2(14.0, 150.0, HUT_RIGHT - 14.0, FLOOR_TOP - 150.0), UITokens.BROWN_3)
	var plank_x := 16.0
	while plank_x < HUT_RIGHT:
		draw_rect(Rect2(plank_x, 150.0, 1.0, FLOOR_TOP - 150.0), UITokens.BROWN)
		plank_x += 6.0
	draw_rect(Rect2(14.0, 150.0, HUT_RIGHT - 14.0, 3.0), UITokens.BROWN_9)
	draw_rect(Rect2(14.0, 186.0, HUT_RIGHT - 14.0, 2.0), UITokens.BROWN_9)
	draw_rect(Rect2(14.0, 150.0, 3.0, FLOOR_TOP - 150.0), UITokens.BROWN_9)
	draw_rect(Rect2(HUT_RIGHT - 3.0, 150.0, 3.0, FLOOR_TOP - 150.0), UITokens.BROWN_9)

	for row in 32:
		var half := maxf(2.0, roundf(float(row) * 50.0 / 32.0))
		var roof_color := UITokens.BROWN_9
		if row % 4 != 0:
			roof_color = Color("#33261b") if row % 2 == 1 else Color("#2e231a")
		draw_rect(Rect2(55.0 - half, 118.0 + row, half * 2.0, 1.0), roof_color)
	draw_rect(Rect2(5.0, 148.0, 100.0, 3.0), UITokens.BROWN_9)

	draw_rect(Rect2(58.0, 166.0, 14.0, 16.0), UITokens.BROWN_9)
	draw_rect(Rect2(60.0, 168.0, 10.0, 12.0), UITokens.GOLD)
	draw_rect(Rect2(64.0, 168.0, 2.0, 12.0), UITokens.BROWN_9)
	draw_rect(Rect2(60.0, 173.0, 10.0, 2.0), UITokens.BROWN_9)

	draw_rect(Rect2(26.0, 190.0, 16.0, FLOOR_TOP - 190.0), Color("#1f1812"))
	var door_x := 30.0
	while door_x < 42.0:
		draw_rect(Rect2(door_x, 190.0, 1.0, FLOOR_TOP - 190.0), UITokens.BROWN_9)
		door_x += 4.0
	draw_rect(Rect2(36.0, 206.0, 2.0, 2.0), UITokens.GOLD_9)


func _draw_ledge_supports() -> void:
	# Опоры уступа (сам уступ — one-way тайлы Platforms).
	draw_rect(Rect2(320.0, LEDGE_FACE, 10.0, FLOOR_TOP - LEDGE_FACE), UITokens.STONE_9)
	draw_rect(Rect2(392.0, LEDGE_FACE, 10.0, FLOOR_TOP - LEDGE_FACE), UITokens.STONE_9)
	draw_rect(Rect2(320.0, LEDGE_FACE, 10.0, 1.0), UITokens.STONE_3)
	draw_rect(Rect2(392.0, LEDGE_FACE, 10.0, 1.0), UITokens.STONE_3)
	# Кирпичная кромка под тайловой плитой.
	draw_rect(Rect2(LEDGE_LEFT, LEDGE_TOP + 8.0, LEDGE_RIGHT - LEDGE_LEFT, LEDGE_FACE - LEDGE_TOP - 8.0), BRICK_MORTAR)
	var brick_x := LEDGE_LEFT
	while brick_x < LEDGE_RIGHT:
		draw_rect(Rect2(brick_x + 1.0, LEDGE_TOP + 9.0, 14.0, 6.0), BRICK_TONES[1])
		brick_x += 16.0


func _draw_ground_base() -> void:
	draw_rect(Rect2(0.0, FLOOR_TOP, VIEW_WIDTH, VIEW_HEIGHT - FLOOR_TOP), UITokens.BROWN)
	draw_rect(Rect2(0.0, FLOOR_TOP, VIEW_WIDTH, 1.0), UITokens.BROWN_3)


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
