class_name Rubble
extends StaticBody2D
## Завал — переиспользуемый prop (T-13): физический блок, который снимается
## способностью/скриптом (blocking = false). Заглушка: нарисованная груда камней.

@export var blocking: bool = true:
	set(value):
		blocking = value
		queue_redraw()
		if is_node_ready():
			_apply_blocking()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_apply_blocking()


func _apply_blocking() -> void:
	collision_shape.set_deferred(&"disabled", not blocking)
	modulate.a = 1.0 if blocking else 0.55


func _draw() -> void:
	draw_rect(Rect2(-16, -8, 32, 8), Color("3b2e22"))
	draw_rect(Rect2(-13, -14, 11, 7), Color("4a4a4f"))
	draw_rect(Rect2(0, -18, 13, 10), Color("4a4a4f"))
	draw_rect(Rect2(-7, -20, 10, 8), Color("6b6b70"))
	draw_rect(Rect2(-13, -14, 11, 1), Color("9a9a9c"))
	draw_rect(Rect2(0, -18, 13, 1), Color("9a9a9c"))
