extends Node2D
## Backdrop зоны 5 «Финал» (T-16, DESIGN §8.6, SPEC §5).
##
## Палитра зоны 5: void (небо), stone-9/stone/stone-5 (монолиты и пол),
## bone (бледный свет и пепел). Зона почти монохромна: цветовые каналы
## держатся в одной серой шкале, единственный акцент — редкие blood-3
## трещины/руны (3 штуки, не больше). Никаких тёплых пятен: финал холоден
## и пуст. Коллизии — в TileMapLayer и WorldBounds, здесь только арт.

const VIEW_WIDTH := 480.0
const VIEW_HEIGHT := 270.0
const FLOOR_TOP := 224.0
const HORIZON := 196.0

const SKY_BANDS: Array[Color] = [
	UITokens.VOID,
	UITokens.STONE_9,
	UITokens.STONE,
]

## Монолиты: x, верх, ширина.
const MONOLITHS: Array[Vector3] = [
	Vector3(18.0, 44.0, 20.0),
	Vector3(78.0, 76.0, 12.0),
	Vector3(150.0, 58.0, 16.0),
	Vector3(300.0, 70.0, 14.0),
	Vector3(398.0, 48.0, 22.0),
	Vector3(458.0, 86.0, 12.0),
]

## Редкие blood-3 акценты: x, y, высота. Ровно три на всю зону.
const BLOOD_CRACKS: Array[Vector3] = [
	Vector3(159.0, 128.0, 26.0),
	Vector3(405.0, 118.0, 34.0),
	Vector3(238.0, 214.0, 4.0),
]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_sky()
	_draw_moon()
	_draw_horizon()
	_draw_monoliths()
	_draw_broken_arch()
	_draw_blood_cracks()
	_draw_ash()


func _draw_sky() -> void:
	var band_height := HORIZON / float(SKY_BANDS.size())
	for index in SKY_BANDS.size():
		draw_rect(
			Rect2(0.0, band_height * index, VIEW_WIDTH, band_height + 1.0),
			SKY_BANDS[index]
		)


func _draw_moon() -> void:
	# Бледный диск — единственный «источник» в небе, монохромный.
	var center := Vector2(372.0, 52.0)
	draw_circle(center, 18.0, Color(UITokens.STONE_9, 0.5))
	draw_circle(center, 13.0, UITokens.BONE)
	draw_circle(center + Vector2(4.0, -3.0), 11.0, UITokens.STONE_9)
	draw_rect(Rect2(center.x - 9.0, center.y + 5.0, 7.0, 2.0), UITokens.STONE_5)


func _draw_horizon() -> void:
	# Горизонт — глухая стена тьмы, без деталей: финал обрывается в пустоту.
	draw_rect(Rect2(0.0, HORIZON, VIEW_WIDTH, FLOOR_TOP - HORIZON), UITokens.VOID)
	for x in range(0, int(VIEW_WIDTH), 8):
		var height := 2.0 + floorf(_hash(x, 13) * 6.0)
		draw_rect(Rect2(float(x), HORIZON - height, 8.0, height), UITokens.STONE_9)


func _draw_monoliths() -> void:
	for monolith: Vector3 in MONOLITHS:
		var x := monolith.x
		var top := monolith.y
		var width := monolith.z
		var height := FLOOR_TOP - top
		draw_rect(Rect2(x, top, width, height), UITokens.STONE_9)
		draw_rect(Rect2(x, top, width, 2.0), UITokens.STONE)
		# Грань и трещины — светлее/темнее той же серой шкалы.
		draw_rect(Rect2(x + 2.0, top, 2.0, height), UITokens.STONE)
		draw_rect(Rect2(x + width - 3.0, top, 1.0, height), UITokens.VOID)
		for notch in 4:
			var ny := top + 14.0 + float(notch) * 24.0 + _hash(int(x) + notch, 19) * 10.0
			draw_rect(Rect2(x + 4.0, ny, width - 8.0, 1.0), UITokens.STONE_5 if notch % 2 == 0 else UITokens.STONE_9)


func _draw_broken_arch() -> void:
	# Разрушенная арка над ареной: два пилона и обломок перекрытия.
	var top := 70.0
	draw_rect(Rect2(208.0, top, 8.0, FLOOR_TOP - top), UITokens.STONE_9)
	draw_rect(Rect2(264.0, top, 8.0, FLOOR_TOP - top), UITokens.STONE_9)
	draw_rect(Rect2(208.0, top, 64.0, 6.0), UITokens.STONE)
	draw_rect(Rect2(208.0, top, 26.0, 3.0), UITokens.STONE_5)
	draw_rect(Rect2(246.0, top + 6.0, 18.0, 2.0), UITokens.VOID)
	draw_rect(Rect2(272.0, top, 10.0, 10.0), UITokens.STONE_9)


func _draw_blood_cracks() -> void:
	# Единственные цветные пятна зоны: blood-3, по 1 px, без заливок.
	for crack: Vector3 in BLOOD_CRACKS:
		var x := crack.x
		var y := crack.y
		var height := crack.z
		draw_rect(Rect2(x, y, 1.0, height), UITokens.BLOOD_3)
		draw_rect(Rect2(x - 2.0, y + height * 0.45, 2.0, 1.0), UITokens.BLOOD_3)
		draw_rect(Rect2(x + 1.0, y + height * 0.7, 2.0, 1.0), UITokens.BLOOD_3)


func _draw_ash() -> void:
	# Пепел на полу: серая крошка, без цветных вкраплений.
	for index in 30:
		var x := floorf(_hash(index, 23) * VIEW_WIDTH)
		var y := FLOOR_TOP - floorf(_hash(index, 29) * 6.0)
		draw_rect(Rect2(x, y, 1.0 + floorf(_hash(index, 31) * 2.0), 1.0), UITokens.STONE_5)
	for index in 12:
		var x := floorf(_hash(index, 37) * VIEW_WIDTH)
		var y := 120.0 + floorf(_hash(index, 41) * 90.0)
		draw_rect(Rect2(x, y, 1.0, 1.0), Color(UITokens.BONE, 0.25))


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
