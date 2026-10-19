class_name WorldMapModel
extends RefCounted
## WorldMapModel — чистая модель карты мира (T-33, AC-04.2).
##
## Источник данных — `ZoneData` (`map_rooms`, `map_bonfires`, `exits`),
## состояние — посещённые зоны (`SceneRouter.visited_zone_ids`), текущая зона
## (`GameState.current_zone_id`), позиция игрока и набор способностей.
##
## Модель не рисует и не читает autoload'ы напрямую: `build()` получает снимок
## состояния аргументами. Поэтому полная карта (`WorldMap`) и миникарта HUD
## строят одинаковый снимок из одних и тех же данных — это гарантия
## «миникарта совпадает с полной картой» (acceptance T-33).
##
## Скрытая информация — ровно один уровень: комната непосещённой зоны не
## раскрывается, но проход к ней виден маркером. Если проход требует
## способность, маркер показывает её иконку/замок, пока способность не получена.

const ZONE_DIR: String = "res://data/zones"
const ZONE_TEMPLATE_FILE: String = "zone_template.tres"
## Явный манифест зон (шаблон `zone_template.tres` в него не входит).
## В экспорте ресурсы лежат как `*.tres.remap`, перебор каталога их не видит.
const ZONE_PATHS: Array[String] = [
	"res://data/zones/zone_01_village.tres",
	"res://data/zones/zone_02_swamp.tres",
	"res://data/zones/zone_03_mountains.tres",
	"res://data/zones/zone_04_ruins.tres",
	"res://data/zones/zone_05_finale.tres",
]
## Сетка миникарты 96x54 при комнате 8x6 (DESIGN §4.3).
const GRID_SIZE := Vector2i(12, 9)
const FALLBACK_ROOM_ID: StringName = &"room"
const FALLBACK_WORLD_RECT := Rect2(0, 0, 480, 270)

const ABILITY_LABELS: Dictionary = {
	&"double_jump": "ability.double_jump.name",
	&"dash": "ability.dash.name",
	&"wall_climb": "ability.wall_climb.name",
}

var zones: Array[ZoneData] = []
var _zones_by_id: Dictionary = {}
var _loaded: bool = false


# ------------------------------------------------------------------------------
# Загрузка ZoneData
# ------------------------------------------------------------------------------

## Читает `data/zones/*.tres`, кроме шаблона. Список зон — данные, не хардкод.
func reload() -> void:
	zones.clear()
	_zones_by_id.clear()
	_loaded = true

	for path: String in ZONE_PATHS:
		var data := load(path) as ZoneData
		if data == null or data.id == &"":
			push_error("WorldMapModel: cannot load zone data at %s" % path)
			continue
		zones.append(data)
		_zones_by_id[data.id] = data
	zones.sort_custom(_sort_zones)


func is_loaded() -> bool:
	return _loaded


func get_zone(zone_id: StringName) -> ZoneData:
	if not _loaded:
		reload()
	return _zones_by_id.get(zone_id) as ZoneData


func get_zone_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for data: ZoneData in zones:
		ids.append(data.id)
	return ids


# ------------------------------------------------------------------------------
# Снимок для отрисовки
# ------------------------------------------------------------------------------

## Собирает данные карты. Аргументы — снимок состояния, без обращения к
## autoload'ам (тестируемо и одинаково для HUD/полной карты).
##
## `player_position` — мировые координаты игрока в `current_zone_id`.
## Возвращает словарь:
##   rooms    — посещённые комнаты: zone_id, zone_name, room_id, cell, rect,
##              index, current;
##   links    — связи между посещёнными зонами: from/to zone, cell, anchors,
##              required_ability, locked;
##   gates    — проходы: маркер в комнате, required_ability, locked, owned,
##              target_visited; имя непосещённой цели не раскрывается;
##   bonfires — костры: zone_id, cell, local;
##   player   — текущая комната/локальная позиция (valid=false — вне комнат);
##   player_room — совместимость с API HUD T-19 (Vector2i).
func build(
	visited_ids: Array,
	current_zone_id: StringName,
	player_position: Vector2,
	owned_ability_ids: Array
) -> Dictionary:
	if not _loaded:
		reload()

	var visited: Dictionary = {}
	for value: Variant in visited_ids:
		var zone_id: StringName = StringName(str(value))
		if zone_id != &"":
			visited[zone_id] = true
	# Текущая зона всегда видима, даже если трекер ещё не успел её записать.
	if current_zone_id != &"":
		visited[current_zone_id] = true

	var owned: Dictionary = {}
	for value: Variant in owned_ability_ids:
		var ability_id: StringName = StringName(str(value))
		if ability_id != &"":
			owned[ability_id] = true

	var rooms: Array[Dictionary] = []
	var room_by_zone: Dictionary = {}
	for data: ZoneData in zones:
		if not visited.has(data.id):
			continue
		var room: ZoneRoom = first_room(data)
		if room == null:
			continue
		var entry: Dictionary = {
			"zone_id": data.id,
			"zone_name": data.get_display_name(),
			"room_id": room.id,
			"cell": room.grid_position,
			"world_rect": room.world_rect,
			"palette": data.palette,
			"current": data.id == current_zone_id,
			"index": rooms.size() + 1,
		}
		rooms.append(entry)
		room_by_zone[data.id] = entry

	var links: Array[Dictionary] = []
	var gates: Array[Dictionary] = []
	var bonfires: Array[Dictionary] = []
	var link_keys: Dictionary = {}
	var player: Dictionary = {
		"zone_id": &"",
		"cell": Vector2i(-1, -1),
		"local": Vector2.ZERO,
		"valid": false,
	}

	for data: ZoneData in zones:
		if not visited.has(data.id):
			continue
		var source: Dictionary = room_by_zone.get(data.id, {})
		if source.is_empty():
			continue
		var source_rect: Rect2 = source["world_rect"]

		if data.id == current_zone_id:
			player = _player_snapshot(data.id, source, source_rect, player_position)

		for bonfire_position: Vector2 in data.map_bonfires:
			bonfires.append({
				"zone_id": data.id,
				"cell": source["cell"],
				"local": _local_in_rect(bonfire_position, source_rect),
			})

		for exit_def: ZoneExit in data.exits:
			if exit_def == null:
				continue
			var target := get_zone(exit_def.target_zone_id)
			var target_room: ZoneRoom = first_room(target) if target != null else null
			var target_visited: bool = target != null and visited.has(target.id)
			var required: StringName = exit_def.required_ability
			var locked: bool = required != &"" and not owned.has(required)
			var source_anchor: Vector2 = _local_in_rect(exit_def.position, source_rect)

			if target_visited and target_room != null:
				var key: String = _pair_key(data.id, target.id)
				if not link_keys.has(key):
					link_keys[key] = true
					var target_entry: Vector2 = _entry_position(target, exit_def.target_entry_id)
					links.append({
						"from_zone": data.id,
						"to_zone": target.id,
						"from_cell": source["cell"],
						"to_cell": target_room.grid_position,
						"from_local": source_anchor,
						"to_local": _local_in_rect(target_entry, target_room.world_rect),
						"required_ability": required,
						"locked": locked,
					})

			# Маркер нужен для закрытого прохода (даже если цель посещена)
			# и для любого прохода в непосещённую зону (один уровень тайны).
			if locked or not target_visited:
				gates.append({
					"zone_id": data.id,
					"exit_id": exit_def.id,
					"cell": source["cell"],
					"local": source_anchor,
					"required_ability": required,
					"owned": required == &"" or owned.has(required),
					"locked": locked,
					"target_visited": target_visited,
					# Имя цели непосещённой зоны не раскрываем (AC-04.2).
					"to_zone_id": target.id if target_visited else &"",
					"zone_index": source["index"],
				})

	return {
		"rooms": rooms,
		"links": links,
		"gates": gates,
		"bonfires": bonfires,
		"player": player,
		"player_room": player["cell"],
		"current_zone_id": current_zone_id,
		"visited_zone_ids": visited.keys(),
		"grid_size": GRID_SIZE,
	}


# ------------------------------------------------------------------------------
# Геометрия
# ------------------------------------------------------------------------------

## Первая комната зоны; null — в ZoneData нет карты.
static func first_room(data: ZoneData) -> ZoneRoom:
	if data == null or data.map_rooms.is_empty():
		return null
	return data.map_rooms[0]


## Позиция точки входа в мировых координатах зоны.
static func entry_position(data: ZoneData, entry_id: StringName) -> Vector2:
	if data == null:
		return Vector2.ZERO
	for entry: ZoneEntryPoint in data.entry_points:
		if entry != null and entry.id == entry_id:
			return entry.position
	if not data.entry_points.is_empty() and data.entry_points[0] != null:
		return data.entry_points[0].position
	return Vector2.ZERO


## Имя способности для маркеров/легенды (реестр, затем fallback UI).
static func ability_label(ability_id: StringName) -> String:
	if ability_id == &"":
		return ""
	var key: String = "ability.%s.name" % String(ability_id)
	var translated: String = TranslationServer.translate(key)
	if translated != key:
		return translated.to_upper()
	if AbilityRegistry.has_ability(ability_id):
		var ability: AbilityBase = AbilityRegistry.get_ability(ability_id)
		if ability != null and not ability.display_name.is_empty():
			return ability.display_name.to_upper()
	return TranslationServer.translate(str(ABILITY_LABELS.get(ability_id, String(ability_id)))).to_upper()


# ------------------------------------------------------------------------------
# Внутренние помощники
# ------------------------------------------------------------------------------

func _sort_zones(a: ZoneData, b: ZoneData) -> bool:
	var a_room: ZoneRoom = first_room(a)
	var b_room: ZoneRoom = first_room(b)
	var a_cell: Vector2i = a_room.grid_position if a_room != null else Vector2i(999, 999)
	var b_cell: Vector2i = b_room.grid_position if b_room != null else Vector2i(999, 999)
	if a_cell.y == b_cell.y:
		return a_cell.x < b_cell.x
	return a_cell.y < b_cell.y


static func _player_snapshot(
	zone_id: StringName,
	source: Dictionary,
	source_rect: Rect2,
	player_position: Vector2
) -> Dictionary:
	return {
		"zone_id": zone_id,
		"cell": source["cell"],
		"local": _local_in_rect(player_position, source_rect),
		"valid": source_rect.has_point(player_position),
	}


static func _local_in_rect(position: Vector2, rect: Rect2) -> Vector2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var local := Vector2(
		(position.x - rect.position.x) / rect.size.x,
		(position.y - rect.position.y) / rect.size.y
	)
	return Vector2(clampf(local.x, 0.0, 1.0), clampf(local.y, 0.0, 1.0))


static func _entry_position(data: ZoneData, entry_id: StringName) -> Vector2:
	return entry_position(data, entry_id)


static func _pair_key(a: StringName, b: StringName) -> String:
	if String(a) <= String(b):
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]
