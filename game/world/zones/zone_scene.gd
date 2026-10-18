class_name ZoneScene
extends Node2D
## ZoneScene — корень сцены зоны, совместимый с WorldRoot (PLAN §2.3).
## Применяет ZoneData ко всем слоям сцены и создаёт точки входа/выходы.
##
## Контракт для SceneRouter (T-17): корень — Node2D/ZoneScene с заполненным zone_data.
## Сцена не рисует HUD/UI (слои Main.tscn) и не хранит состояние забега.

signal zone_ready(data: ZoneData)
signal exit_requested(exit_id: StringName, target_zone_id: StringName, target_entry_id: StringName)

const WORLD_ZONE_GROUP := &"world_zone"
const PLAYER_GROUP := &"player"
## Слой 2 физики проекта — player (project.godot, [layer_names]).
const PLAYER_COLLISION_LAYER_BIT := 1 << 1

@export var zone_data: ZoneData

@onready var sky: ColorRect = %Sky
@onready var ambient: CanvasModulate = %Ambient
@onready var ground: TileMapLayer = %Ground
@onready var platforms: TileMapLayer = %Platforms
@onready var ladders: TileMapLayer = %Ladders
@onready var hazards: TileMapLayer = %Hazards
@onready var entries: Node2D = %Entries
@onready var exits_root: Node2D = %Exits


func _ready() -> void:
	add_to_group(WORLD_ZONE_GROUP)
	if zone_data == null:
		push_error("ZoneScene: zone_data is not assigned")
		return

	for issue: String in zone_data.validate():
		push_error("ZoneScene(%s): %s" % [zone_data.id, issue])

	name = String(zone_data.id)
	_apply_zone_data()
	_spawn_entry_markers()
	_spawn_exit_areas()

	_emit_zone_entered()
	zone_ready.emit(zone_data)


func _emit_zone_entered() -> void:
	# Через autoload EventBus (PLAN §2.2), но без compile-time зависимости от синглтона:
	# так ZoneScene грузится и инструментами (генератор пайплайна) вне дерева autoload'ов.
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null and event_bus.has_signal(&"zone_entered"):
		event_bus.emit_signal(&"zone_entered", zone_data.id, zone_data.display_name)


func _apply_zone_data() -> void:
	ambient.color = Color(zone_data.ambient_level, zone_data.ambient_level, zone_data.ambient_level, 1.0)

	if zone_data.tileset != null:
		ground.tile_set = zone_data.tileset
		platforms.tile_set = zone_data.tileset
		ladders.tile_set = zone_data.tileset
		hazards.tile_set = zone_data.tileset

	if zone_data.palette != null:
		var palette := zone_data.palette
		sky.color = palette.background
		ground.modulate = palette.ground
		platforms.modulate = palette.accent
		ladders.modulate = palette.accent
		hazards.modulate = palette.hazard

		var bonfire := get_node_or_null("Props/Bonfire") as Bonfire
		if bonfire != null:
			bonfire.flame_color = palette.accent


func _spawn_entry_markers() -> void:
	for entry: ZoneEntryPoint in zone_data.entry_points:
		if entry == null:
			continue
		var marker := Marker2D.new()
		marker.name = "Entry_%s" % entry.id
		marker.position = entry.position
		marker.set_meta(&"entry_id", entry.id)
		entries.add_child(marker)


func _spawn_exit_areas() -> void:
	for exit_def: ZoneExit in zone_data.exits:
		if exit_def == null:
			continue
		var area := Area2D.new()
		area.name = "Exit_%s" % exit_def.id
		area.position = exit_def.position
		area.collision_layer = 0
		area.collision_mask = PLAYER_COLLISION_LAYER_BIT
		area.monitorable = false
		area.set_meta(&"exit_id", exit_def.id)
		area.set_meta(&"target_zone_id", exit_def.target_zone_id)
		area.set_meta(&"target_entry_id", exit_def.target_entry_id)

		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = exit_def.size
		shape.shape = rect
		area.add_child(shape)

		area.body_entered.connect(_on_exit_body_entered.bind(exit_def))
		exits_root.add_child(area)


func _on_exit_body_entered(body: Node2D, exit_def: ZoneExit) -> void:
	if body == null or not body.is_in_group(PLAYER_GROUP):
		return
	exit_requested.emit(exit_def.id, exit_def.target_zone_id, exit_def.target_entry_id)
