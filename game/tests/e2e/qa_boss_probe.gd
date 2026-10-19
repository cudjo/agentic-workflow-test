extends Node
## QA T-37: точечная проверка убийства финального босса и концовки.

const ZONE: String = "res://world/zones/zone_05_finale/zone_05_finale.tscn"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameState.reset_boss_progress()
	GameState.reset_hp()
	var zone := (load(ZONE) as PackedScene).instantiate()
	add_child(zone)
	await get_tree().process_frame
	await get_tree().process_frame
	var arena: Node = null
	for child: Node in zone.find_children("*", "", true, false):
		if child.has_method(&"get_boss") and child.has_method(&"start_fight"):
			arena = child
			break
	print("[BOSS] arena=", arena)
	var boss: BossBase = arena.get_boss()
	print("[BOSS] boss=", boss, " hp=", boss.hp, " fight=", boss.fight_active, " dead=", boss.is_dead)
	var started: bool = arena.start_fight()
	print("[BOSS] start_fight=", started, " fight=", boss.fight_active, " arena=", arena.is_fight_active())
	boss.hp = 1.0
	print("[BOSS] before damage hp=", boss.hp, " phase=", boss.phase_index, " invuln=", boss._phase_invulnerable_left)
	boss._on_hurtbox_damaged(Damage.create(999.0, Vector2.ZERO, 0.05))
	print("[BOSS] after damage hp=", boss.hp, " dead=", boss.is_dead, " fsm=", boss.fsm.current)
	for i: int in 180:
		await get_tree().physics_frame
		if i % 30 == 0:
			print("[BOSS] frame ", i, " hp=", boss.hp, " dead=", boss.is_dead, " fsm=", boss.fsm.current,
				" valid=", is_instance_valid(boss), " queued=", boss.is_queued_for_deletion() if is_instance_valid(boss) else "n/a",
				" defeated=", GameState.is_boss_defeated(&"zone_05_sovereign"))
	print("[BOSS] final defeated=", GameState.is_boss_defeated(&"zone_05_sovereign"),
		" bosses=", str(GameState.get_bosses_defeated()), " currency=", GameState.currency)
	var hook := zone.get_node_or_null("EndingExit")
	print("[BOSS] hook=", hook)
	if hook != null:
		var faction: StringName = hook.request_ending()
		print("[BOSS] ending requested faction=", faction)
		for i: int in 120:
			await get_tree().process_frame
			if i == 50:
				break
		var seq := zone.get_node_or_null("EndingSequence")
		print("[BOSS] seq=", seq, " state=", seq.get_state_name() if seq != null else "n/a",
			" id=", seq.get_ending_id() if seq != null else "n/a")
		if seq != null:
			seq.advance()
			await get_tree().process_frame
			for i: int in 20:
				seq.advance()
				await get_tree().process_frame
			print("[BOSS] seq final state=", seq.get_state_name(), " finished=", seq.is_finished())
	get_tree().quit(0)
