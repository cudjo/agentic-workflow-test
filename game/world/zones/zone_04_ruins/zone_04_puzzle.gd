extends Node2D
## Загадка-проход руин (T-16): три рычага открывают запечатанную дверь.
##
## Каждый `RuinLever` знает своё целевое положение (`solution_state`);
## когда все рычаги стоят в целевых положениях, `Gate` (SealedGate) открывается
## и эмитится `solved`. Простая заглушка-паззл по TASKS T-16: без инвентаря,
## комбинаций предметов и таймеров — только состояние рычагов.
##
## Начальные состояния в сцене (все выключены) не совпадают с решением
## [вкл, выкл, вкл], поэтому дверь закрыта при входе в зону.
##
## Дочерние узлы контракта: `Levers` (RuinLever-ы) и `Gate` (SealedGate).
## Где находится выход в финал — см. zone_04_ruins.tscn (за дверью).

signal solved
signal reset

@export var gate_path: NodePath = ^"Gate"
@export var levers_path: NodePath = ^"Levers"

@onready var gate: SealedGate = get_node_or_null(gate_path) as SealedGate

var _levers: Array[RuinLever] = []
var _solved: bool = false
var _resetting: bool = false


func _ready() -> void:
	var holder := get_node_or_null(levers_path)
	if holder != null:
		for child: Node in holder.get_children():
			var lever := child as RuinLever
			if lever == null:
				continue
			_levers.append(lever)
			lever.toggled.connect(_on_lever_toggled)
	_refresh()


func _on_lever_toggled(_lever_id: StringName, _active: bool) -> void:
	if _resetting:
		return
	_refresh()


func _refresh() -> void:
	if _levers.is_empty():
		return
	for lever: RuinLever in _levers:
		if not lever.is_at_solution():
			return
	if _solved:
		return
	_solved = true
	if gate != null:
		gate.open()
	solved.emit()


func is_solved() -> bool:
	return _solved


func get_lever_count() -> int:
	return _levers.size()


## Возвращает загадку в исходное состояние (повторный вход, тесты).
func reset_puzzle() -> void:
	_resetting = true
	for lever: RuinLever in _levers:
		lever.set_active(false)
	_resetting = false
	if gate != null:
		gate.close()
	_solved = false
	reset.emit()
