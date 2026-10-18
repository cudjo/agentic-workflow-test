extends Node
## Integration-02: runner headless-смоука полного флоу.
##
## Запуск из корня репозитория:
##   godot --headless --path game res://tests/tools/assembly_flow_smoke.tscn
##
## Сам runner живёт в current_scene и освобождается при смене сцены на меню,
## поэтому всю проверку ведёт observer, добавленный прямо в root (переживает
## `change_scene_to_file`, как autoload). Код выхода 0 — флоу собран, 1 — нет.

const OBSERVER_SCRIPT: Script = preload("res://tests/tools/assembly_flow_observer.gd")


func _ready() -> void:
	var observer := Node.new()
	observer.name = "AssemblyFlowObserver"
	observer.set_script(OBSERVER_SCRIPT)
	# root занят установкой current_scene во время `_ready` — добавляем отложенно.
	get_tree().root.add_child.call_deferred(observer)
