extends Node
## QA T-37 — финальный прогон после Fix-3a/Fix-3b (ревизия aece545).
## Независимые проверки N2 (UI 150% на 8 экранах), N4 (контур врагов)
## и N5 (расположение wall_climb по SPEC §4.1).
## Запуск: godot --headless --path . res://tests/e2e/qa_final_probe.tscn

const SCREENS: Array[Dictionary] = [
	{"name": "Inventory", "path": "res://ui/inventory/Inventory.tscn"},
	{"name": "Journal", "path": "res://ui/journal/Journal.tscn"},
	{"name": "Factions", "path": "res://ui/factions/Factions.tscn"},
	{"name": "FactionChoice", "path": "res://ui/factions/FactionChoice.tscn"},
	{"name": "WorldMap", "path": "res://ui/map/WorldMap.tscn"},
	{"name": "Campfire", "path": "res://ui/campfire/Campfire.tscn"},
	{"name": "Remap", "path": "res://ui/remap/Remap.tscn"},
	{"name": "DeathScreen", "path": "res://ui/death/DeathScreen.tscn"},
]

const ZONE_02: String = "res://world/zones/zone_02_swamp/zone_02_swamp.tscn"
const ZONE_03: String = "res://world/zones/zone_03_mountains/zone_03_mountains.tscn"
const SWIFT_ENEMY: String = "res://entities/enemies/swift/swift_enemy.tscn"

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(item: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("[FINAL] PASS %s — %s" % [item, detail])
	else:
		_fail += 1
		print("[FINAL] FAIL %s — %s" % [item, detail])


func _wait(frames: int = 2) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _run() -> void:
	await _probe_ui_scale()
	await _probe_enemy_outline()
	await _probe_wall_climb_source()
	print("[FINAL] SUMMARY pass=%d fail=%d" % [_pass, _fail])
	get_tree().quit(0)


# ------------------------------------------------------------------------------
# N2 / DESIGN §9.6 п.6 — UI 150% на 8 экранах
# ------------------------------------------------------------------------------

func _first_label_font(root: Node) -> int:
	for node: Node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and not label.text.is_empty():
			return label.get_theme_font_size(&"font_size")
	return -1


func _probe_ui_scale() -> void:
	Config.ui_scale = Config.UI_SCALE_100
	await _wait(2)
	for entry: Dictionary in SCREENS:
		var packed := load(String(entry["path"])) as PackedScene
		if packed == null:
			_check("N2 ui 150%%: %s" % entry["name"], false, "сцена не загрузилась")
			continue
		var screen := packed.instantiate()
		if entry["name"] != "DeathScreen":
			screen.set(&"pause_on_open", false)
		add_child(screen)
		await _wait(2)
		if screen.has_method(&"open"):
			screen.call(&"open")
		await _wait(2)
		var at_100: int = _first_label_font(screen)
		Config.ui_scale = Config.UI_SCALE_150
		await _wait(3)
		var at_150: int = _first_label_font(screen)
		_check("N2 ui 150%%: %s" % entry["name"], at_100 > 0 and at_150 > at_100,
			"font %d → %d px" % [at_100, at_150])
		Config.ui_scale = Config.UI_SCALE_100
		await _wait(2)
		if screen.has_method(&"close"):
			screen.call(&"close")
		screen.queue_free()
		await _wait(1)


# ------------------------------------------------------------------------------
# N4 / DESIGN §9.1 — контур врагов в «Читаемость силуэтов»
# ------------------------------------------------------------------------------

func _probe_enemy_outline() -> void:
	Config.set_silhouette_readability(false)
	var enemy := (load(SWIFT_ENEMY) as PackedScene).instantiate()
	add_child(enemy)
	await _wait(3)
	var off: bool = bool(enemy.call(&"is_silhouette_outline_enabled"))
	var material: ShaderMaterial = enemy.call(&"get_outline_material") as ShaderMaterial
	Config.set_silhouette_readability(true)
	await _wait(3)
	var on: bool = bool(enemy.call(&"is_silhouette_outline_enabled"))
	_check("N4: контур врага выключен при silhouette_readability=false", not off, "enabled=%s" % str(off))
	_check("N4: контур врага включён при silhouette_readability=true", on, "enabled=%s" % str(on))
	_check("N4: у врага есть контурный материал", material != null, str(material))
	Config.set_silhouette_readability(false)
	enemy.queue_free()
	await _wait(2)


# ------------------------------------------------------------------------------
# N5 / SPEC §4.1 — wall_climb в зоне 2 (опциональный секрет)
# ------------------------------------------------------------------------------

func _probe_wall_climb_source() -> void:
	var zone2 := (load(ZONE_02) as PackedScene).instantiate()
	add_child(zone2)
	await _wait(3)
	var pickup := zone2.get_node_or_null("Props/AbilityPickupWallClimb") as AbilityPickup
	var dash_pickup := zone2.get_node_or_null("Props/AbilityPickupDash") as AbilityPickup
	var dash_gate := zone2.get_node_or_null("Props/DashGate") as AbilityGate
	_check("N5: wall_climb pickup находится в зоне 2", pickup != null
		and pickup.ability_id == &"wall_climb",
		"pickup=%s" % (str(pickup.name) if pickup != null else "null"))
	_check("N5: источник wall_climb — optional_secret",
		pickup != null and str(pickup.get_meta(&"source", &"")) == "optional_secret",
		"source=%s" % (str(pickup.get_meta(&"source", &"")) if pickup != null else "n/a"))
	_check("N5: wall_climb стоит за dash-gate",
		pickup != null and dash_gate != null
		and dash_gate.get_required_ability() == &"dash"
		and pickup.global_position.x > dash_gate.global_position.x,
		"pickup_x=%s gate_x=%s dash_gate=%s" % [
			str(pickup.global_position.x) if pickup != null else "n/a",
			str(dash_gate.global_position.x) if dash_gate != null else "n/a",
			str(dash_gate.get_required_ability()) if dash_gate != null else "n/a"])
	_check("N5: dash pickup в зоне 2 (SPEC §4.1), источник помечен teacher_npc",
		dash_pickup != null and dash_pickup.ability_id == &"dash"
		and str(dash_pickup.get_meta(&"source", &"")) == "teacher_npc",
		"source=%s" % (str(dash_pickup.get_meta(&"source", &"")) if dash_pickup != null else "n/a"))
	zone2.queue_free()
	await _wait(2)

	var zone3 := (load(ZONE_03) as PackedScene).instantiate()
	add_child(zone3)
	await _wait(3)
	var duplicate := zone3.get_node_or_null("Props/AbilityPickupWallClimb") as AbilityPickup
	var wall_gate := zone3.get_node_or_null("Props/WallClimbGate") as AbilityGate
	_check("N5: в зоне 3 нет дублирующего pickup wall_climb", duplicate == null,
		"pickup=%s" % (str(duplicate.name) if duplicate != null else "null"))
	_check("N5: WallClimbGate зоны 3 требует wall_climb",
		wall_gate != null and wall_gate.get_required_ability() == &"wall_climb",
		"required=%s" % (str(wall_gate.get_required_ability()) if wall_gate != null else "n/a"))
	var closed: bool = wall_gate != null and not wall_gate.is_open()
	GameState.add_ability(&"wall_climb")
	await _wait(3)
	var opened: bool = wall_gate != null and wall_gate.is_open()
	_check("N5/AC-04.3: gate зоны 3 закрыт без способности и открыт после получения",
		closed and opened, "closed_before=%s open_after=%s" % [str(closed), str(opened)])
	zone3.queue_free()
	await _wait(2)
