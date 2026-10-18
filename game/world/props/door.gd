class_name ZoneDoor
extends Node2D
## Дверь — переиспользуемый prop (T-13). Заглушка: 16x32 проём; locked рисует
## поперечную балку. Переход между зонами выполняет SceneRouter (T-17) по ZoneExit.

@export var accent: Color = Color("c08a3e"):
	set(value):
		accent = value
		queue_redraw()

@export var locked: bool = false:
	set(value):
		locked = value
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-8, -32, 16, 32), Color("262c3e"))
	draw_rect(Rect2(-6, -30, 12, 30), Color("3b2e22"))
	draw_rect(Rect2(-6, -30, 12, 1), accent)
	draw_rect(Rect2(-6, -15, 12, 1), Color("2a2018"))
	if locked:
		draw_rect(Rect2(-8, -20, 16, 3), accent)
		draw_rect(Rect2(-2, -19, 4, 1), Color("0b0c10"))
