class_name Chest
extends Node2D
## Сундук — переиспользуемый prop (T-13). Заглушка: состояние opened рисует
## открытую крышку. Логика добычи — в задачах инвентаря/секретов.

@export var opened: bool = false:
	set(value):
		opened = value
		queue_redraw()

@export var accent: Color = Color("c08a3e"):
	set(value):
		accent = value
		queue_redraw()


func _draw() -> void:
	# Корпус 16x10 и крышка; при opened крышка поднята.
	draw_rect(Rect2(-8, -10, 16, 10), Color("3b2e22"))
	draw_rect(Rect2(-8, -10, 16, 1), Color("54402f"))
	if opened:
		draw_rect(Rect2(-8, -16, 16, 5), Color("54402f"))
		draw_rect(Rect2(-8, -11, 16, 2), Color("0b0c10"))
	else:
		draw_rect(Rect2(-8, -12, 16, 3), Color("54402f"))
	draw_rect(Rect2(-1, -7, 2, 4), accent)
