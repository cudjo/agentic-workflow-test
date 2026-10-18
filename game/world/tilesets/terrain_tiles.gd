class_name TerrainTiles
extends RefCounted
## Контракт placeholder-атласа тайлсета 16×16 (T-13).
## Раскладка: строки 0–4 — solid-варианты зон (16 side-масок), строка 5 — one-way
## платформы (3 части × 5 зон), строка 6 — лестницы, строка 7 — hazard.
## Сам арт — grayscale-заглушка; цвет задаёт ZonePalette через modulate.
## При замене арта сохраняются source id, размер тайла и atlas-координаты.

const SOURCE_ID := 0
const TILE_SIZE := Vector2i(16, 16)
const ZONE_COUNT := 5
const GROUND_ROW_START := 0
const PLATFORM_ROW := 5
const LADDER_ROW := 6
const HAZARD_ROW := 7
const ATLAS_COLUMNS := 16
const ATLAS_ROWS := 8

enum Side {
	RIGHT = 1,
	BOTTOM = 2,
	LEFT = 4,
	TOP = 8,
}

enum PlatformPart {
	LEFT_END = 0,
	MIDDLE = 1,
	RIGHT_END = 2,
}

const PEERING_BIT_BY_SIDE := {
	Side.RIGHT: TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	Side.BOTTOM: TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	Side.LEFT: TileSet.CELL_NEIGHBOR_LEFT_SIDE,
	Side.TOP: TileSet.CELL_NEIGHBOR_TOP_SIDE,
}


static func ground_atlas(zone_index: int, side_mask: int = 0) -> Vector2i:
	return Vector2i(clampi(side_mask, 0, 15), GROUND_ROW_START + clampi(zone_index, 0, ZONE_COUNT - 1))


static func platform_atlas(zone_index: int, part: PlatformPart) -> Vector2i:
	return Vector2i(clampi(zone_index, 0, ZONE_COUNT - 1) * 3 + int(part), PLATFORM_ROW)


static func ladder_atlas(zone_index: int) -> Vector2i:
	return Vector2i(clampi(zone_index, 0, ZONE_COUNT - 1), LADDER_ROW)


static func hazard_atlas(zone_index: int) -> Vector2i:
	return Vector2i(clampi(zone_index, 0, ZONE_COUNT - 1), HAZARD_ROW)


static func platform_side_mask(part: PlatformPart) -> int:
	match part:
		PlatformPart.LEFT_END:
			return Side.RIGHT
		PlatformPart.MIDDLE:
			return Side.LEFT | Side.RIGHT
		_:
			return Side.LEFT
