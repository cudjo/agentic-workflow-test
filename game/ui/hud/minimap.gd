class_name AshenMinimap
extends Control
## AshenMinimap — миникарта HUD 96x54 (T-33, DESIGN §4.3/§5).
##
## Заменяет `_MinimapStub` T-19, сохраняя API HUD:
##   `hud.set_minimap_data({...})`, `hud.get_minimap()`, `get_minimap_data()`.
##
## Рисует тот же снимок `WorldMapModel.build()`, что и полная карта:
## комнаты 8x6 px, посещённые зоны, текущая позиция, костры и закрытые
## проходы. Состояние дублируется формой (замок/огонёк/метка), не только
## цветом. Данные не хранят UI-состояния — только снимок модели.

const SIZE := UITokens.MINIMAP_SIZE

## Совместимость с заглушкой T-19: клетка игрока. Реальная позиция приходит
## в снимке (`player.cell`/`player.local`); поле остаётся для внешних вызовов.
var player_room: Vector2i = Vector2i(1, 0)

## Кратность миникарты: 1 — HUD 96x54, 2 — экран смерти 192x108 (T-22).
## Комната и маркеры масштабируются вместе, поэтому карта остаётся той же.
@export_range(1, 4, 1) var zoom: int = 1:
	set(value):
		zoom = clampi(value, 1, 4)
		custom_minimum_size = SIZE * float(zoom)
		if _renderer != null:
			_renderer.cell_size = UITokens.MINIMAP_ROOM * float(zoom)
			_renderer.marker_scale = float(zoom)
		queue_redraw()

var _renderer: MapRenderer
var _data: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	_renderer = MapRenderer.new()
	_renderer.cell_size = UITokens.MINIMAP_ROOM
	_renderer.marker_scale = 1.0
	_renderer.show_labels = false
	_renderer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_renderer)


func _ready() -> void:
	_renderer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


## Снимок карты (WorldMapModel.build) или совместимый с T-19 словарь.
## Неизвестные ключи игнорируются, падений нет.
func set_data(data: Dictionary) -> void:
	_data = data.duplicate(true)
	var room: Variant = data.get("player_room")
	if room is Vector2i:
		player_room = room
	elif room is Vector2:
		player_room = Vector2i(room)
	_renderer.set_data(_data)
	queue_redraw()


func get_data() -> Dictionary:
	return _data.duplicate(true)


func get_renderer() -> MapRenderer:
	return _renderer


func get_player_room() -> Vector2i:
	var player: Variant = _data.get("player")
	if player is Dictionary:
		var cell: Variant = (player as Dictionary).get("cell")
		if cell is Vector2i:
			return cell
	return player_room
