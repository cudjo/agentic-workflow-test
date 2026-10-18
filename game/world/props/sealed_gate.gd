class_name SealedGate
extends StaticBody2D
## Запечатанная дверь храма (T-16) — физический проход, который открывает
## загадка с рычагами. Пока `blocking`, створка перекрывает проём (слой world,
## как тайлы); после `open()` коллизия снимается, створка «уходит в стену».
##
## Контракт для загадки: `blocking`, `open()`, `close()`, сигнал `opened`.
## Origin — у пола: створка рисуется вверх (16×32), как дверной проём в стене.

signal opened

@export var blocking: bool = true:
	set(value):
		blocking = value
		if is_node_ready():
			_apply_blocking()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = CombatLayers.WORLD
	collision_mask = 0
	_apply_blocking()


func open() -> void:
	if not blocking:
		return
	blocking = false
	_apply_blocking()
	opened.emit()


func close() -> void:
	if blocking:
		return
	blocking = true
	_apply_blocking()


func _apply_blocking() -> void:
	collision_shape.set_deferred(&"disabled", not blocking)
	queue_redraw()


func _draw() -> void:
	if blocking:
		# Каменная створка с золотыми и кровавыми рунами печати.
		draw_rect(Rect2(-8.0, -32.0, 16.0, 32.0), UITokens.BROWN_9)
		draw_rect(Rect2(-7.0, -31.0, 14.0, 30.0), UITokens.BROWN)
		draw_rect(Rect2(-1.0, -32.0, 2.0, 32.0), UITokens.BROWN_3)
		draw_rect(Rect2(-4.0, -25.0, 8.0, 2.0), UITokens.GOLD_9)
		draw_rect(Rect2(-2.0, -21.0, 4.0, 7.0), UITokens.GOLD_9)
		draw_rect(Rect2(-4.0, -10.0, 8.0, 2.0), UITokens.BLOOD)
		draw_rect(Rect2(-2.0, -7.0, 4.0, 2.0), UITokens.BLOOD)
	else:
		# Проём открыт: видны только косяки и порог.
		draw_rect(Rect2(-8.0, -32.0, 2.0, 32.0), UITokens.STONE_9)
		draw_rect(Rect2(6.0, -32.0, 2.0, 32.0), UITokens.STONE_9)
		draw_rect(Rect2(-6.0, -2.0, 12.0, 2.0), UITokens.STONE_3)
