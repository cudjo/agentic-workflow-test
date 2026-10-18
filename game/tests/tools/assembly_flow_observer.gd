extends Node
## Integration-02: observer headless-смоука полного флоу (см. runner
## `assembly_flow_smoke.gd`). Живёт в root, поэтому переживает смену сцен.
##
## Сценарий как у игрока: главное меню → «Новая игра» → Main.tscn → зона 1.
## Проверяет: игрок заспавнен, HUD виден, NPC и арена в зоне, `interact`
## у костра открывает экран костра. Код выхода 0 — флоу собран, 1 — нет.

const MENU_PATH: String = "res://ui/menus/MainMenu.tscn"
const NEW_GAME_INDEX: int = 1


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file(MENU_PATH)
	await get_tree().process_frame
	await get_tree().process_frame

	var menu := get_tree().current_scene as MainMenu
	if menu == null:
		_fail("main scene is not MainMenu: %s" % str(get_tree().current_scene))
		return
	print("ASSEMBLY_FLOW_STEP menu")

	menu.activate_item(NEW_GAME_INDEX)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var main := get_tree().current_scene
	if main == null or String(main.name) != "Main":
		_fail("new game did not load Main.tscn: %s" % str(main))
		return
	print("ASSEMBLY_FLOW_STEP main")

	if String(SceneRouter.current_zone_id) != "zone_01_village":
		_fail("zone_01_village is not loaded: %s" % str(SceneRouter.current_zone_id))
		return

	var world_root := main.get_node_or_null("WorldRoot")
	if world_root == null or world_root.get_child_count() == 0:
		_fail("WorldRoot has no zone")
		return
	var zone := world_root.get_child(0)
	print("ASSEMBLY_FLOW_STEP zone=%s" % String(zone.name))

	var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		_fail("player is not spawned")
		return
	var player := players[0] as Node2D
	if player.get_parent() != zone:
		_fail("player is not inside the zone")
		return
	print("ASSEMBLY_FLOW_STEP player=%s" % str(player.global_position))

	var hud := main.get_node_or_null("HUD") as CanvasLayer
	if hud == null or not hud.visible:
		_fail("HUD is not visible")
		return
	print("ASSEMBLY_FLOW_STEP hud=visible")

	if zone.get_node_or_null("NPCs/KeeperNpc") == null:
		_fail("keeper NPC is not placed in zone 1")
		return
	if zone.get_node_or_null("NPCs/TraderNpc") == null:
		_fail("trader NPC is not placed in zone 1")
		return
	if zone.get_node_or_null("Arena/BossArenaZone01") == null:
		_fail("boss arena 1 is not mounted in zone 1")
		return
	print("ASSEMBLY_FLOW_STEP npc=2 arena=1")

	# Пользовательский сценарий interact: подойти к костру и нажать interact.
	var bonfire := zone.get_node_or_null("Props/Bonfire") as Node2D
	var campfire := main.get_node_or_null("Campfire") as Campfire
	var interaction := player.get_node_or_null("Interaction") as PlayerInteraction
	if bonfire == null or campfire == null or interaction == null:
		_fail("campfire/interact wiring is missing")
		return
	GameState.set_in_combat(false)
	player.global_position = bonfire.global_position + Vector2(0.0, -10.0)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not interaction.try_interact():
		_fail("interact near the bonfire did not open the campfire")
		return
	if not campfire.is_open():
		_fail("Campfire.is_open() is false after interact")
		return
	print("ASSEMBLY_FLOW_STEP campfire=open")

	print("ASSEMBLY_FLOW_OK zone=zone_01_village player=spawned hud=visible npc=2 arena=1 campfire=open")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	printerr("ASSEMBLY_FLOW_FAIL: %s" % reason)
	get_tree().quit(1)
