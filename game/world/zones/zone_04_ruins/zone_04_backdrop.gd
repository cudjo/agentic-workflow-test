extends Node2D
## Backdrop зоны 4 «Руины-храм» (T-16, DESIGN §8.6, SPEC §5).
##
## Палитра зоны 4: brown/brown-3 (камень храма), brown-9 (тьма), gold-9/gold
## (жёлтый отсвет свечей и витражей), blood (красные пятна/печати).
## Рисует глухое тёмное небо, разрушенную стену храма, арки, колонны,
## витражи и кровавые следы. Только графика; коллизии — в TileMapLayer
## и WorldBounds. Источники света — в сцене (Lights), здесь только цвет.

const VIEW_WIDTH := 480.0
const FLOOR_TOP := 224.0
const HORIZON := 96.0

const SKY_BANDS: Array[Color] = [
	UITokens.BROWN_9,
	UITokens.BROWN,
	UITokens.BROWN_3,
]

## Колонны: x, верх, низ.
const PILLARS: Array[Vector3] = [
	Vector3(24.0, 58.0, FLOOR_TOP),
	Vector3(120.0, 78.0, FLOOR_TOP),
	Vector3(264.0, 70.0, FLOOR_TOP),
	Vector3(336.0, 86.0, FLOOR_TOP),
	Vector3(456.0, 62.0, FLOOR_TOP),
]

## Витражи: x, верх, высота.
const WINDOWS: Array[Vector3] = [
	Vector3(160.0, 118.0, 52.0),
	Vector3(320.0, 126.0, 44.0),
]

## Кровавые пятна на полу: x, ширина.
const BLOOD_STAINS: Array[Vector2] = [
	Vector2(84.0, 18.0),
	Vector2(252.0, 12.0),
	Vector2(412.0, 22.0),
]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_sky()
	_draw_far_wall()
	_draw_arches()
	_draw_pillars()
	_draw_windows()
	_draw_blood_stains()
	_draw_rubble()


func _draw_sky() -> void:
	var band_height := HORIZON / float(SKY_BANDS.size())
	for index in SKY_BANDS.size():
		draw_rect(
			Rect2(0.0, band_height * index, VIEW_WIDTH, band_height + 1.0),
			SKY_BANDS[index]
		)
	# Пыльный градиент к полу: ступенчатые полосы, без шейдеров.
	for step in 4:
		var alpha := 0.06 + 0.03 * float(step)
		draw_rect(
			Rect2(0.0, HORIZON + 22.0 + float(step) * 10.0, VIEW_WIDTH, 10.0),
			Color(UITokens.BROWN_9, alpha)
		)


func _draw_far_wall() -> void:
	draw_rect(Rect2(0.0, HORIZON, VIEW_WIDTH, FLOOR_TOP - HORIZON), UITokens.BROWN_9)
	# Кладка: горизонтальные швы и вертикальные стыки вразбежку.
	for y in range(int(HORIZON), int(FLOOR_TOP), 8):
		draw_rect(Rect2(0.0, float(y), VIEW_WIDTH, 1.0), UITokens.BROWN)
		var offset := 0 if (y / 8) % 2 == 0 else 8
		for x in range(offset, int(VIEW_WIDTH), 16):
			draw_rect(Rect2(float(x), float(y), 1.0, 8.0), UITokens.BROWN)
	# Разрушенный верх стены: рваная кромка.
	for x in range(0, int(VIEW_WIDTH), 6):
		var bite := 4.0 + floorf(_hash(x, 11) * 10.0)
		draw_rect(Rect2(float(x), HORIZON, 6.0, bite), UITokens.BROWN_9)


func _draw_arches() -> void:
	# Три пролома-арки: тёмный проём, каменные косяки и золотой замок.
	for center_x: float in [88.0, 240.0, 392.0]:
		var half := 30.0
		var top := 104.0
		draw_rect(Rect2(center_x - half, top + 12.0, half * 2.0, FLOOR_TOP - top - 12.0), UITokens.BROWN_9)
		draw_rect(Rect2(center_x - half, top, 6.0, FLOOR_TOP - top), UITokens.BROWN_3)
		draw_rect(Rect2(center_x + half - 6.0, top, 6.0, FLOOR_TOP - top), UITokens.BROWN_3)
		draw_rect(Rect2(center_x - half, top, half * 2.0, 6.0), UITokens.BROWN_3)
		draw_rect(Rect2(center_x - half, top, half * 2.0, 1.0), UITokens.STONE_9)
		# Золотой замковый камень — редкий тёплый блик.
		draw_rect(Rect2(center_x - 2.0, top + 1.0, 4.0, 4.0), UITokens.GOLD_9)
		# Обломанный зуб арки.
		draw_rect(Rect2(center_x + half - 10.0, top + 6.0, 4.0, 5.0), UITokens.BROWN_9)


func _draw_pillars() -> void:
	for pillar: Vector3 in PILLARS:
		var x := pillar.x
		var top := pillar.y
		var height := pillar.z - top
		# Тень, ствол, тёплый блик с одной стороны.
		draw_rect(Rect2(x - 7.0, top, 14.0, height), UITokens.BROWN_9)
		draw_rect(Rect2(x - 5.0, top, 10.0, height), UITokens.BROWN_3)
		draw_rect(Rect2(x - 5.0, top, 2.0, height), UITokens.BROWN)
		# Капитель и база.
		draw_rect(Rect2(x - 8.0, top, 16.0, 4.0), UITokens.BROWN)
		draw_rect(Rect2(x - 8.0, top, 16.0, 1.0), UITokens.STONE_9)
		draw_rect(Rect2(x - 8.0, FLOOR_TOP - 4.0, 16.0, 4.0), UITokens.BROWN)
		# Сколы: пара тёмных выщербин.
		var notch_y := top + 18.0 + floorf(_hash(int(x), 17) * 40.0)
		draw_rect(Rect2(x + 2.0, notch_y, 3.0, 2.0), UITokens.BROWN_9)


func _draw_windows() -> void:
	for window: Vector3 in WINDOWS:
		var x := window.x
		var top := window.y
		var height := window.z
		draw_rect(Rect2(x - 8.0, top, 16.0, height), UITokens.STONE_9)
		draw_rect(Rect2(x - 6.0, top + 2.0, 12.0, height - 4.0), UITokens.BROWN_9)
		# Витраж: тусклое золото + кроваво-красный акцент в центре.
		draw_rect(Rect2(x - 4.0, top + 4.0, 8.0, height - 8.0), UITokens.GOLD_9)
		draw_rect(Rect2(x - 4.0, top + 4.0, 8.0, 2.0), UITokens.GOLD)
		draw_rect(Rect2(x - 2.0, top + height * 0.45, 4.0, 6.0), UITokens.BLOOD)
		# Свинцовые переплёты.
		draw_rect(Rect2(x - 1.0, top + 4.0, 1.0, height - 8.0), UITokens.BROWN_9)
		draw_rect(Rect2(x - 4.0, top + height * 0.5, 8.0, 1.0), UITokens.BROWN_9)


func _draw_blood_stains() -> void:
	for stain: Vector2 in BLOOD_STAINS:
		draw_rect(Rect2(stain.x, FLOOR_TOP - 2.0, stain.y, 2.0), UITokens.BLOOD)
		draw_rect(Rect2(stain.x + 3.0, FLOOR_TOP - 4.0, maxf(stain.y - 8.0, 4.0), 2.0), UITokens.BLOOD_9)
	# Ритуальная печать у алтаря (восточная часть храма).
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var point := Vector2(424.0, 220.0) + Vector2(cos(angle), sin(angle) * 0.35) * 16.0
		draw_rect(Rect2(point.x, point.y, 2.0, 1.0), UITokens.BLOOD)


func _draw_rubble() -> void:
	# Обломки у пола: камни, пыль, редкие золотые искры.
	for index in 26:
		var x := floorf(_hash(index, 31) * VIEW_WIDTH)
		var y := FLOOR_TOP - floorf(_hash(index, 37) * 8.0)
		var size := 1.0 + floorf(_hash(index, 41) * 3.0)
		draw_rect(Rect2(x, y, size, 1.0), UITokens.BROWN)
	for index in 10:
		var x := floorf(_hash(index, 43) * VIEW_WIDTH)
		var y := FLOOR_TOP - 2.0 - floorf(_hash(index, 47) * 4.0)
		draw_rect(Rect2(x, y, 1.0, 1.0), UITokens.GOLD_9)


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
