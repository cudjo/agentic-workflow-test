class_name MapRenderer
extends Control
## MapRenderer — общая отрисовка карты мира и миникарты (T-33).
##
## Один и тот же снимок `WorldMapModel.build()` рисуется в двух масштабах:
## миникарта HUD — клетка 8x6 px (96x54), полная карта — клетка 23x17 px.
## Поэтому комнаты/связи/маркеры совпадают (acceptance T-33).
##
## Состояние дублируется не только цветом:
##   * текущая комната — двойная золотая рамка + метка игрока;
##   * костёр — форма огонька, а не только золотой цвет;
##   * закрытый проход — замок + иконка/цвет требуемой способности;
##   * посещённая комната — заливка + контур (неизведанная не рисуется).

const CELL_MINIMAP := Vector2(8, 6)
const ABILITY_COLORS: Dictionary = {
	&"double_jump": UITokens.GOLD_3,
	&"dash": UITokens.STEEL_3,
	&"wall_climb": UITokens.BONE,
}
## 5x5 пиктограммы способностей: читаются на полной карте.
const ABILITY_PATTERNS: Dictionary = {
	&"double_jump": [
		".#.#.",
		".#.#.",
		".#.#.",
		"#####",
		".#.#.",
	],
	&"dash": [
		"..#..",
		"...#.",
		"#####",
		"...#.",
		"..#..",
	],
	&"wall_climb": [
		"#.#.#",
		"#.#.#",
		"#####",
		"..#..",
		".###.",
	],
}

@export var cell_size: Vector2 = CELL_MINIMAP:
	set(value):
		cell_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_update_minimum_size()
		queue_redraw()
@export var show_labels: bool = false:
	set(value):
		show_labels = value
		queue_redraw()
@export var selected_zone_id: StringName = &"":
	set(value):
		selected_zone_id = value
		queue_redraw()

var _data: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_minimum_size()


func _ready() -> void:
	_update_minimum_size()


# ------------------------------------------------------------------------------
# Данные
# ------------------------------------------------------------------------------

func set_data(data: Dictionary) -> void:
	_data = data.duplicate(true)
	queue_redraw()


func get_data() -> Dictionary:
	return _data.duplicate(true)


func get_room_count() -> int:
	return _rooms().size()


func get_gate_count() -> int:
	return _gates().size()


func get_bonfire_count() -> int:
	return _bonfires().size()


## Прямоугольники комнат в локальных координатах — для тестов/QA.
func get_room_rects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room: Dictionary in _rooms():
		var cell: Vector2i = room.get("cell", Vector2i(-1, -1))
		result.append({
			"zone_id": room.get("zone_id", &""),
			"rect": cell_rect(cell),
			"current": bool(room.get("current", false)),
		})
	return result


## Состояние маркеров без чтения пикселей — для тестов/QA.
func get_marker_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for gate: Dictionary in _gates():
		result.append({
			"kind": "locked_gate" if bool(gate.get("locked", false)) else "pass",
			"zone_id": gate.get("zone_id", &""),
			"required_ability": gate.get("required_ability", &""),
			"owned": bool(gate.get("owned", false)),
			"target_visited": bool(gate.get("target_visited", false)),
		})
	for bonfire: Dictionary in _bonfires():
		result.append({
			"kind": "bonfire",
			"zone_id": bonfire.get("zone_id", &""),
			"required_ability": &"",
			"owned": true,
			"target_visited": true,
		})
	var player: Dictionary = _data.get("player", {})
	if bool(player.get("valid", false)):
		result.append({
			"kind": "player",
			"zone_id": player.get("zone_id", &""),
			"required_ability": &"",
			"owned": true,
			"target_visited": true,
		})
	return result


func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * cell_size, cell_size)


# ------------------------------------------------------------------------------
# Отрисовка
# ------------------------------------------------------------------------------

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	draw_rect(Rect2(Vector2.ZERO, size), UITokens.VOID)
	if show_labels:
		_draw_grid()

	for link: Dictionary in _links():
		_draw_link(link)
	for room: Dictionary in _rooms():
		_draw_room(room)
	for bonfire: Dictionary in _bonfires():
		_draw_bonfire(bonfire)
	for gate: Dictionary in _gates():
		_draw_gate(gate)
	_draw_player()

	UIStyle.draw_frame(self, Rect2(Vector2.ZERO, size), 1, UITokens.STONE_9)


## Сетка неизведанных клеток: карта читается как карта, а не пустое поле.
func _draw_grid() -> void:
	for y: int in WorldMapModel.GRID_SIZE.y:
		for x: int in WorldMapModel.GRID_SIZE.x:
			var center: Vector2 = cell_rect(Vector2i(x, y)).get_center().floor()
			draw_rect(Rect2(center, Vector2(1, 1)), UITokens.NIGHT_3)
	UIStyle.draw_frame(
		self,
		Rect2(Vector2.ZERO, Vector2(WorldMapModel.GRID_SIZE) * cell_size).grow(-1),
		1,
		UITokens.STONE_9
	)


func _draw_link(link: Dictionary) -> void:
	var from_rect: Rect2 = cell_rect(link.get("from_cell", Vector2i.ZERO))
	var to_rect: Rect2 = cell_rect(link.get("to_cell", Vector2i.ZERO))
	var from: Vector2 = from_rect.position + from_rect.size * link.get("from_local", Vector2(0.5, 0.5))
	var to: Vector2 = to_rect.position + to_rect.size * link.get("to_local", Vector2(0.5, 0.5))
	var color: Color = UITokens.BLOOD_3 if bool(link.get("locked", false)) else UITokens.STEEL_3
	if bool(link.get("locked", false)):
		_draw_dashed_line(from, to, color, 1)
	else:
		draw_line(from, to, color, 1.0)


func _draw_room(room: Dictionary) -> void:
	var rect: Rect2 = cell_rect(room.get("cell", Vector2i(-1, -1)))
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var current: bool = bool(room.get("current", false))
	draw_rect(rect.grow(-1), UITokens.STEEL_9)
	UIStyle.draw_frame(self, rect.grow(-1), 1, UITokens.GOLD_3 if current else UITokens.STEEL)
	if current:
		UIStyle.draw_frame(self, rect.grow(-2), 1, UITokens.GOLD_9)

	if show_labels:
		var baseline: float = 1.0 + UIStyle.baseline_y(UITokens.FONT_BODY)
		UIStyle.draw_text(
			self,
			rect.position + Vector2(2, baseline),
			str(int(room.get("index", 0))),
			UITokens.BONE,
			UITokens.FONT_BODY
		)

	if show_labels and selected_zone_id != &"" and room.get("zone_id", &"") == selected_zone_id:
		UIStyle.draw_focus_brackets(
			self,
			rect.grow(-1),
			UITokens.GOLD_3,
			UITokens.FOCUS_ARM,
			UITokens.BORDER_FOCUS
		)


func _draw_bonfire(bonfire: Dictionary) -> void:
	var marker := Vector2(3, 4) if not show_labels else Vector2(5, 6)
	var pos: Vector2 = _marker_position(
		bonfire.get("cell", Vector2i(-1, -1)),
		bonfire.get("local", Vector2(0.5, 0.5)),
		marker
	)
	var base := Rect2(pos + Vector2(0, marker.y - 2), Vector2(marker.x, 2))
	draw_rect(base, UITokens.GOLD_9)
	draw_rect(Rect2(pos + Vector2(floor(marker.x * 0.5), 0), Vector2(1, marker.y - 1)), UITokens.GOLD_3)
	draw_rect(Rect2(pos + Vector2(floor(marker.x * 0.5) - 1, 1), Vector2(1, 2)), UITokens.GOLD)


func _draw_gate(gate: Dictionary) -> void:
	var marker := Vector2(7, 5) if not show_labels else Vector2(12, 12)
	var pos: Vector2 = _marker_position(
		gate.get("cell", Vector2i(-1, -1)),
		gate.get("local", Vector2(0.5, 0.5)),
		marker
	)
	var locked: bool = bool(gate.get("locked", false))
	var border: Color = UITokens.BLOOD_3 if locked else UITokens.STONE_3
	draw_rect(Rect2(pos, marker), Color(UITokens.VOID, 0.86))
	UIStyle.draw_frame(self, Rect2(pos, marker), 1, border)

	var ability: StringName = StringName(str(gate.get("required_ability", "")))
	var color: Color = ABILITY_COLORS.get(ability, UITokens.STONE_5)
	if show_labels:
		_draw_lock(Rect2(pos + Vector2(1, 3), Vector2(5, 5)), UITokens.GOLD_3)
		if ability != &"":
			_draw_pattern(
				Rect2(pos + Vector2(6, 3), Vector2(5, 5)),
				ABILITY_PATTERNS.get(ability, []),
				color
			)
	else:
		_draw_lock(Rect2(pos + Vector2(1, 1), Vector2(3, 3)), UITokens.GOLD_3)
		if ability != &"":
			# Миникарта: цветовая метка способности рядом с замком.
			draw_rect(Rect2(pos + Vector2(5, 1), Vector2(1, 3)), color)


func _draw_player() -> void:
	var player: Dictionary = _data.get("player", {})
	if not bool(player.get("valid", false)):
		return
	var marker := Vector2(3, 3) if not show_labels else Vector2(5, 5)
	var pos: Vector2 = _marker_position(
		player.get("cell", Vector2i(-1, -1)),
		player.get("local", Vector2(0.5, 0.5)),
		marker
	)
	# Ромб/стрелка «ты»: форма отличается от квадрата костра.
	var mid: float = floor(marker.x * 0.5)
	for row: int in int(marker.y):
		var half: int = int(mini(row + 1, int(marker.y) - row))
		var width: int = maxi(1, half * 2 - 1)
		draw_rect(
			Rect2(pos + Vector2(mid - floor(width * 0.5), row), Vector2(width, 1)),
			UITokens.GOLD_3
		)
	draw_rect(Rect2(pos + Vector2(mid, 1), Vector2(1, 1)), UITokens.VOID)


func _draw_lock(rect: Rect2, color: Color) -> void:
	var w: int = int(rect.size.x)
	var h: int = int(rect.size.y)
	var p: Vector2 = rect.position
	if w >= 5 and h >= 5:
		draw_rect(Rect2(p + Vector2(1, 0), Vector2(w - 2, 1)), color)
		draw_rect(Rect2(p + Vector2(0, 1), Vector2(1, 2)), color)
		draw_rect(Rect2(p + Vector2(w - 1, 1), Vector2(1, 2)), color)
		draw_rect(Rect2(p + Vector2(0, 3), Vector2(w, h - 3)), color)
	else:
		draw_rect(Rect2(p + Vector2(1, 0), Vector2(maxi(w - 2, 1), 1)), color)
		draw_rect(Rect2(p + Vector2(0, 1), Vector2(w, maxi(h - 1, 1))), color)


func _draw_pattern(rect: Rect2, pattern: Array, color: Color) -> void:
	if pattern.is_empty():
		return
	var rows: int = pattern.size()
	var cols: int = (pattern[0] as String).length()
	var step := Vector2(rect.size.x / float(cols), rect.size.y / float(rows))
	for y: int in rows:
		var row: String = pattern[y]
		for x: int in mini(row.length(), cols):
			if row[x] != "#":
				continue
			draw_rect(
				Rect2(
					rect.position + Vector2(float(x) * step.x, float(y) * step.y),
					Vector2(maxf(step.x, 1.0), maxf(step.y, 1.0))
				),
				color
			)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: int) -> void:
	var distance: float = from.distance_to(to)
	if distance <= 0.0:
		return
	var direction: Vector2 = (to - from) / distance
	var step: float = 3.0
	var position: float = 0.0
	while position < distance:
		var segment_end: float = minf(position + 1.5, distance)
		draw_line(
			from + direction * position,
			from + direction * segment_end,
			color,
			float(width)
		)
		position += step


func _marker_position(cell: Vector2i, local: Vector2, marker_size: Vector2) -> Vector2:
	var rect: Rect2 = cell_rect(cell)
	var travel: Vector2 = rect.size - marker_size
	return (rect.position + travel * local).round()


func _update_minimum_size() -> void:
	custom_minimum_size = Vector2(WorldMapModel.GRID_SIZE) * cell_size


func _rooms() -> Array:
	var rooms: Variant = _data.get("rooms", [])
	return rooms if rooms is Array else []


func _links() -> Array:
	var links: Variant = _data.get("links", [])
	return links if links is Array else []


func _gates() -> Array:
	var gates: Variant = _data.get("gates", [])
	return gates if gates is Array else []


func _bonfires() -> Array:
	var bonfires: Variant = _data.get("bonfires", [])
	return bonfires if bonfires is Array else []
