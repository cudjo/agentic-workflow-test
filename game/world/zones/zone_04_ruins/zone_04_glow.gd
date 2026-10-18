extends Node2D
## Эмиссивный жёлто-красный отсвет руин (T-16, DESIGN §8.7).
##
## Живёт на отдельном CanvasLayer (layer 1), поэтому НЕ затемняется
## CanvasModulate — как эмиссивные окна/пламя в DESIGN §8.7. Рисует два
## столба света из проломов крыши: тёплый gold-9 над костром и красный
## blood-3 над алтарём за запечатанной дверью. Это «жёлто-красный отсвет»
## зоны 4, видимый даже при ambient 0.26.
##
## Свет физически не отбрасывает тени и не влияет на геймплей: только арт.
## Точечные источники (PointLight2D) остаются в сцене (Lights/).

const FLOOR_TOP := 224.0

## Столбы света: x, ширина, цвет, максимальная альфа.
const SHAFTS: Array[Vector4] = [
	Vector4(268.0, 40.0, 0.0, 0.13),
	Vector4(404.0, 40.0, 1.0, 0.10),
]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_roof_holes()
	for shaft: Vector4 in SHAFTS:
		var color := UITokens.GOLD_9 if int(shaft.z) == 0 else UITokens.BLOOD_3
		_draw_shaft(shaft.x, shaft.y, color, shaft.w)


func _draw_roof_holes() -> void:
	# Проломы в своде: яркая кромка и тёмный провал.
	draw_rect(Rect2(268.0, 30.0, 40.0, 6.0), Color(UITokens.GOLD_9, 0.45))
	draw_rect(Rect2(274.0, 33.0, 28.0, 3.0), Color(UITokens.GOLD_3, 0.25))
	draw_rect(Rect2(404.0, 30.0, 40.0, 6.0), Color(UITokens.BLOOD_3, 0.35))
	draw_rect(Rect2(410.0, 33.0, 28.0, 3.0), Color(UITokens.BLOOD_3, 0.18))


func _draw_shaft(x: float, width: float, color: Color, max_alpha: float) -> void:
	# Столб расширяется к полу; альфа падает ступенями (пиксельный дизеринг).
	var steps := 24
	var step_height := (FLOOR_TOP - 36.0) / float(steps)
	for step in steps:
		var t := float(step) / float(steps - 1)
		var spread := width * (0.55 + 0.45 * t)
		var alpha := max_alpha * (1.0 - 0.75 * t)
		var shade := Color(color, alpha)
		draw_rect(Rect2(x - spread * 0.5, 36.0 + step_height * step, spread, step_height + 1.0), shade)
		# Внутреннее ядро столба чуть ярче.
		draw_rect(
			Rect2(x - spread * 0.22, 36.0 + step_height * step, spread * 0.44, step_height + 1.0),
			Color(color, alpha * 0.7)
		)
	# Пятно света на полу.
	draw_rect(Rect2(x - width * 0.75, FLOOR_TOP - 2.0, width * 1.5, 3.0), Color(color, max_alpha * 0.7))
