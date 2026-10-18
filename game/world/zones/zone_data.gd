class_name ZoneData
extends Resource
## ZoneData — данные зоны (T-13): идентификатор, название, палитра, ambient-уровень,
## тайлсет, точки входа и выходы/связи. Хранится в data/zones/*.tres (не хардкод).
##
## Потребитель — ZoneScene: применяет все поля к сцене зоны. Полей-заглушек нет:
##   id/display_name -> EventBus.zone_entered (баннер/загрузка, T-14/T-17)
##   palette        -> фон, modulate тайлов, пламя костра
##   ambient_level  -> CanvasModulate
##   tileset        -> все TileMapLayer зоны
##   entry_points   -> Marker2D-точки входа
##   exits          -> Area2D-триггеры и адреса переходов
##   map_rooms      -> клетки карты мира/миникарты (T-33)
##   map_bonfires   -> костры на карте (мировые координаты зоны)

@export var id: StringName = &"zone_template"
@export var display_name: String = ""
## Атмосферная строка для экрана загрузки (T-17, DESIGN §5). Пустая — экран
## показывает только название зоны.
@export var epigraph: String = ""
@export var palette: ZonePalette
@export_range(0.0, 1.0, 0.01) var ambient_level: float = 0.42
@export var tileset: TileSet
@export var entry_points: Array[ZoneEntryPoint] = []
@export var exits: Array[ZoneExit] = []
## Комнаты зоны на карте (T-33, AC-04.2). Пусто — зона не отображается на карте.
@export var map_rooms: Array[ZoneRoom] = []
## Костры в мировых координатах зоны; карта привязывает их к комнате.
@export var map_bonfires: Array[Vector2] = []


## Локализованное имя зоны (`zone.<id>.name`), fallback — `display_name`.
func get_display_name() -> String:
	return LocaleText.lookup("zone.%s.name" % String(id), display_name)


## Локализованная атмосферная строка (`zone.<id>.epigraph`).
func get_epigraph() -> String:
	return LocaleText.lookup("zone.%s.epigraph" % String(id), epigraph)


## Проверка целостности данных зоны. Возвращает список проблем (пусто — данные валидны).
## Вызывается ZoneScene при загрузке, чтобы битые .tres не падали молча.
func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	if id == &"":
		issues.append("id is empty")
	if display_name.is_empty():
		issues.append("display_name is empty")
	if palette == null:
		issues.append("palette is not set")
	if tileset == null:
		issues.append("tileset is not set")
	if ambient_level < 0.0 or ambient_level > 1.0:
		issues.append("ambient_level must be within [0, 1]")

	var entry_ids: Dictionary = {}
	for entry: ZoneEntryPoint in entry_points:
		if entry == null:
			issues.append("entry_points contains null")
			continue
		if entry.id == &"":
			issues.append("entry point id is empty")
		elif entry_ids.has(entry.id):
			issues.append("duplicate entry point id '%s'" % entry.id)
		entry_ids[entry.id] = true

	var exit_ids: Dictionary = {}
	for exit_def: ZoneExit in exits:
		if exit_def == null:
			issues.append("exits contains null")
			continue
		if exit_def.id == &"":
			issues.append("exit id is empty")
		elif exit_ids.has(exit_def.id):
			issues.append("duplicate exit id '%s'" % exit_def.id)
		exit_ids[exit_def.id] = true
		if exit_def.target_zone_id == &"":
			issues.append("exit '%s' has no target_zone_id" % exit_def.id)
		if exit_def.target_entry_id == &"":
			issues.append("exit '%s' has no target_entry_id" % exit_def.id)
		if exit_def.size.x <= 0.0 or exit_def.size.y <= 0.0:
			issues.append("exit '%s' has non-positive size" % exit_def.id)

	var room_ids: Dictionary = {}
	for room: ZoneRoom in map_rooms:
		if room == null:
			issues.append("map_rooms contains null")
			continue
		if room.id == &"":
			issues.append("map room id is empty")
		elif room_ids.has(room.id):
			issues.append("duplicate map room id '%s'" % room.id)
		room_ids[room.id] = true
		if room.grid_position.x < 0 or room.grid_position.y < 0:
			issues.append("map room '%s' has negative grid position" % room.id)
		if room.world_rect.size.x <= 0.0 or room.world_rect.size.y <= 0.0:
			issues.append("map room '%s' has non-positive world rect" % room.id)

	for bonfire_position: Vector2 in map_bonfires:
		if map_rooms.is_empty():
			break
		var inside: bool = false
		for room: ZoneRoom in map_rooms:
			if room != null and room.world_rect.has_point(bonfire_position):
				inside = true
				break
		if not inside:
			issues.append("bonfire %s is outside every map room" % str(bonfire_position))
	return issues
