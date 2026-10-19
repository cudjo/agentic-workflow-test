extends Node
## QA T-37 (48de7dc): визуальный кадр босса зоны 1 без наложения игрока.
## Запуск: godot --path . res://tests/e2e/qa_visual_probe.tscn --quit-after 12000

const MAIN_SCENE: PackedScene = preload("res://Main.tscn")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	SceneRouter.bind_world_root(main.get_node("WorldRoot") as Node2D)
	add_child(main)
	await _wait(20)
	var zone := SceneRouter.current_zone
	var arena := zone.get_node_or_null("Arena/BossArenaZone01")
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if arena != null and player != null:
		player.global_position = Vector2(100, 214)
		player.velocity = Vector2.ZERO
		if not arena.is_fight_active():
			arena.start_fight()
		await _wait(30)
		var boss: BossBase = arena.get_boss()
		print("[VIS] zone=%s arena_alpha=%.2f boss=%s boss_visible=%s boss_pos=%s" % [
			SceneRouter.current_zone_id,
			(arena as CanvasItem).self_modulate.a,
			str(boss != null),
			str(boss.is_visible_in_tree() if boss != null else false),
			str(boss.global_position) if boss != null else "n/a",
		])
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image != null:
			image.resize(960, 540, Image.INTERPOLATE_NEAREST)
			image.save_png("user://qa_boss_zone1_clear.png")
			print("[VIS] saved user://qa_boss_zone1_clear.png")
	await _wait(5)
	get_tree().quit(0)


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame
