extends Node
## Раннер генератора T-16: запускает build_zones_04_05.gd в обычном древе
## проекта, чтобы autoload-имена (GameState) были доступны при компиляции.
##
## Запуск (из каталога game/):
##   godot --headless --path game res://tests/tools/build_zones_04_05.tscn

func _ready() -> void:
	var builder := (load("res://tests/tools/build_zones_04_05.gd") as GDScript).new() as Node
	if builder == null:
		push_error("T-16: не удалось создать builder")
		get_tree().quit(1)
		return
	var ok: bool = bool(builder.call(&"build"))
	builder.free()
	get_tree().quit(0 if ok else 1)
