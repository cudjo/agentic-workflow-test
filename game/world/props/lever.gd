class_name RuinLever
extends Area2D
## Контактный рычаг-переключатель руин (T-16).
##
## Простая загадка-проход (TASKS T-16): рычаг переключается, когда игрок
## входит в его Area2D. `solution_state` — целевое положение для загадки;
## контроллер зоны (`zone_04_puzzle.gd`) открывает проход, когда все рычаги
## стоят в своих целевых положениях. Над рычагом нарисована руна-подсказка:
## три золотые точки — «включён», одна тусклая — «выключен» (состояние
## дублируется формой, а не только цветом).
##
## Слой/маска: Area2D не сканирует ничего, кроме тела игрока (слой 2,
## CombatLayers.PLAYER_BODY). Ввод не перехватывается — взаимодействие
## контактное, пока система `interact` (T-03/T-04) не даёт полноценный вызов.

signal toggled(lever_id: StringName, active: bool)

@export var lever_id: StringName = &"lever"
@export var active: bool = false
## Целевое положение рычага в решении загадки.
@export var solution_state: bool = true
## Пауза между переключениями, чтобы проход по рычагу не «дребезжал».
@export var cooldown: float = 0.35

var _cooldown_left: float = 0.0


func _ready() -> void:
	add_to_group(&"ruin_lever")
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	monitorable = false
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group(&"player"):
		return
	if _cooldown_left > 0.0:
		return
	toggle()


## Переключает рычаг; эмитит `toggled` только при фактической смене состояния.
func toggle() -> void:
	set_active(not active)


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	_cooldown_left = cooldown
	queue_redraw()
	toggled.emit(lever_id, active)


func is_at_solution() -> bool:
	return active == solution_state


func _draw() -> void:
	# Каменное основание и стойка (origin — у пола).
	draw_rect(Rect2(-7.0, -4.0, 14.0, 4.0), UITokens.STONE_9)
	draw_rect(Rect2(-5.0, -6.0, 10.0, 2.0), UITokens.BROWN_3)
	draw_rect(Rect2(-3.0, -15.0, 6.0, 10.0), UITokens.STONE)
	draw_rect(Rect2(-3.0, -15.0, 1.0, 10.0), UITokens.STONE_3)

	# Рукоять: вправо/вверх — включён, влево/вниз — выключен.
	var handle := UITokens.GOLD if active else UITokens.STONE_5
	draw_rect(Rect2(-1.0, -21.0, 2.0, 7.0), handle)
	if active:
		draw_rect(Rect2(1.0, -21.0, 6.0, 2.0), handle)
	else:
		draw_rect(Rect2(-7.0, -19.0, 6.0, 2.0), handle)

	# Руна-подсказка цели: три точки = «включён», одна = «выключен».
	if solution_state:
		draw_rect(Rect2(-4.0, -27.0, 2.0, 2.0), UITokens.GOLD_9)
		draw_rect(Rect2(-1.0, -27.0, 2.0, 2.0), UITokens.GOLD_9)
		draw_rect(Rect2(2.0, -27.0, 2.0, 2.0), UITokens.GOLD_9)
	else:
		draw_rect(Rect2(-1.0, -27.0, 2.0, 2.0), UITokens.BLOOD_9)
