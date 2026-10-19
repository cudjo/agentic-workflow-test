extends Node
## QA T-37: смена языка на смонтированном Main (реальный игровой путь).

const MAIN_SCENE: PackedScene = preload("res://Main.tscn")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	var world_root := main.get_node("WorldRoot") as Node2D
	SceneRouter.bind_world_root(world_root)
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var death := main.get_node("Overlay/DeathScreen") as DeathScreen
	print("[LANG] before: ", _labels(death))
	Config.set_language("en")
	await get_tree().process_frame
	await get_tree().process_frame
	print("[LANG] after EN: ", _labels(death))
	Config.set_language("ru")
	await get_tree().process_frame
	print("[LANG] after RU: ", _labels(death))
	get_tree().quit(0)


func _labels(death: DeathScreen) -> String:
	var out: Array[String] = []
	for node: Node in death.find_children("*", "Label", true, false):
		var label := node as Label
		if label.name in ["CoinsRow", "ItemsRow"] or label.text.contains("МОНЕТ") or label.text.contains("ПРЕДМ"):
			out.append("%s='%s'" % [label.name, label.text])
	return str(out)
