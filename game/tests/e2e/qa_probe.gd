extends Node
## QA T-37 probe (не GUT): сканирует собранный мир на доступность механик.
## Запуск: godot --headless --path game res://tests/e2e/qa_probe.tscn

const ZONE_IDS: Array[StringName] = [
	&"zone_01_village",
	&"zone_02_swamp",
	&"zone_03_mountains",
	&"zone_04_ruins",
	&"zone_05_finale",
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[PROBE] start")
	print("[PROBE] autoload GameState: ", get_node_or_null("/root/GameState"))
	print("[PROBE] autoload SceneRouter: ", get_node_or_null("/root/SceneRouter"))
	for zone_id: StringName in ZONE_IDS:
		var path: String = "res://world/zones/%s/%s.tscn" % [zone_id, zone_id]
		var packed := load(path) as PackedScene
		if packed == null:
			print("[PROBE] %s: LOAD FAIL" % zone_id)
			continue
		var zone := packed.instantiate()
		add_child(zone)
		await get_tree().process_frame
		await get_tree().process_frame
		var pickups: Array[String] = []
		var teachers: Array[String] = []
		var enemies: Array[String] = []
		var bosses: Array[String] = []
		var gates: Array[String] = []
		var npcs: Array[String] = []
		var bonfires: Array[String] = []
		for node: Node in zone.find_children("*", "", true, false):
			if node is AbilityPickup:
				pickups.append(str(node.name))
			if node is Teacher:
				teachers.append(str(node.name))
			if node is Enemy:
				enemies.append(str(node.name))
			if node is BossBase:
				bosses.append(str(node.name))
			if node is AbilityGate:
				gates.append(str(node.name))
			if node is DialogueNpc or node is TraderNpc:
				npcs.append(str(node.name))
			if node is Bonfire:
				bonfires.append(str(node.name))
		print("[PROBE] %s pickups=%s teachers=%s enemies=%s bosses=%s gates=%s npcs=%s bonfires=%s" % [
			zone_id, str(pickups), str(teachers), str(enemies), str(bosses), str(gates), str(npcs), str(bonfires)
		])
		var zd := zone.get("zone_data") as ZoneData
		if zd != null:
			var exits: Array[String] = []
			for e: ZoneExit in zd.exits:
				exits.append("%s->%s req=%s" % [e.id, e.target_zone_id, e.required_ability])
			print("[PROBE] %s exits=%s" % [zone_id, str(exits)])
		zone.queue_free()
		await get_tree().process_frame
	print("[PROBE] done")
	get_tree().quit(0)
