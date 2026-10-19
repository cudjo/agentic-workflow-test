extends Node
## QA Fix-4a/4b: корневая сцена probe. Логика живёт в драйвере, который
## добавляется в /root и переживает смены current_scene (Main ↔ MainMenu).
## Запуск: godot --path game res://tests/e2e/qa_fix4ab.tscn

const DRIVER_SCRIPT: Script = preload("res://tests/e2e/qa_fix4ab_driver.gd")


func _ready() -> void:
	var driver := Node.new()
	driver.name = "QaFix4abDriver"
	driver.set_script(DRIVER_SCRIPT)
	get_tree().root.add_child(driver)
