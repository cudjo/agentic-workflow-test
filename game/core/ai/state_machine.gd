class_name EnemyStateMachine
extends RefCounted
## EnemyStateMachine — поведенческий FSM врага (T-12, PLAN §2.1 `core/ai/`).
##
## Состояния и приоритеты согласованы с FSM игрока (DESIGN §7):
##   Death 100 > Hurt 90 > Attack 60 > Chase 50 > Patrol 0.
##
## `request_state()` — только переход на состояние с более высоким
## приоритетом (реакция на урон/смерть, обнаружение игрока). Возврат к
## обычному поведению после завершения атаки/отшатывания — `force_state()`:
## таймеры состояний принадлежат Enemy, а не внешнему наблюдателю.
## Death терминален: из него нет переходов (нежить получает новый FSM
## на новую «жизнь», см. `undead_enemy.gd`).

signal state_changed(from_state: State, to_state: State)

enum State {
	PATROL,
	CHASE,
	ATTACK,
	HURT,
	DEATH,
}

const PRIORITY: Dictionary = {
	State.PATROL: 0,
	State.CHASE: 50,
	State.ATTACK: 60,
	State.HURT: 90,
	State.DEATH: 100,
}

## Допустимые переходы. Патруль не может «перепрыгнуть» в атаку без
## преследования; Death доступен из любого состояния.
const ALLOWED: Dictionary = {
	State.PATROL: [State.CHASE, State.HURT, State.DEATH],
	State.CHASE: [State.PATROL, State.ATTACK, State.HURT, State.DEATH],
	State.ATTACK: [State.CHASE, State.PATROL, State.HURT, State.DEATH],
	State.HURT: [State.PATROL, State.CHASE, State.DEATH],
	State.DEATH: [],
}

var current: State = State.PATROL
var time_in_state: float = 0.0
var transition_count: int = 0


## Текущее состояние: человекочитаемое имя (тесты, отладка, EventBus).
func get_state_name() -> StringName:
	match current:
		State.PATROL:
			return &"patrol"
		State.CHASE:
			return &"chase"
		State.ATTACK:
			return &"attack"
		State.HURT:
			return &"hurt"
		State.DEATH:
			return &"death"
	return &""


func get_priority(state: State) -> int:
	return int(PRIORITY.get(state, -1))


func can_transition(next: State) -> bool:
	if not ALLOWED.has(current):
		return false
	var allowed: Array = ALLOWED[current]
	return allowed.has(next)


func is_state(state: State) -> bool:
	return current == state


func is_alive_state() -> bool:
	return current != State.DEATH


## Переход только на более приоритетное состояние (Hurt/Death/обнаружение).
func request_state(next: State) -> bool:
	if next == current or not can_transition(next):
		return false
	if get_priority(next) <= get_priority(current):
		return false
	return _transition(next)


## Принудительный переход по таблице (завершение атаки/отшатывания).
func force_state(next: State) -> bool:
	if next == current or not can_transition(next):
		return false
	return _transition(next)


## Продвижение таймера текущего состояния; вызывается один раз за physics tick.
func tick(delta: float) -> void:
	time_in_state += maxf(delta, 0.0)


func _transition(next: State) -> bool:
	var previous: State = current
	current = next
	time_in_state = 0.0
	transition_count += 1
	state_changed.emit(previous, next)
	return true
