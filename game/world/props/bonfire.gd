class_name Bonfire
extends Node2D
## Костёр — переиспользуемый prop (T-13) и будущая точка сохранения/чекпоинт (T-26).
## Заглушка с тем же контрактом: цвет пламени приходит из палитры зоны (ZoneData).

@export var flame_color: Color = Color("c08a3e"):
	set(value):
		flame_color = value
		queue_redraw()


func _draw() -> void:
	# Камни вокруг основания (ось Y — вниз, origin у земли).
	draw_rect(Rect2(-11, -4, 22, 4), Color("303035"))
	draw_rect(Rect2(-9, -6, 18, 3), Color("3b2e22"))
	# Пламя: три ступени, верхняя светлее.
	draw_rect(Rect2(-5, -14, 10, 8), flame_color)
	draw_rect(Rect2(-3, -18, 6, 5), flame_color.lightened(0.22))
	draw_rect(Rect2(-1, -21, 2, 4), flame_color.lightened(0.45))
