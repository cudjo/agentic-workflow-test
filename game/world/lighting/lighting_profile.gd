class_name LightingProfile
extends Resource
## LightingProfile — значения освещения/атмосферы (T-35, PLAN §3.6, DESIGN §8.7).
##
## Единственный источник чисел для LightingRig и EmissiveGlow:
##   ambient 0.26–0.5 (мир), 0.78 (меню);
##   постеризация на 6–8 ступеней + дизеринг Байера 4×4 (без плавных градиентов);
##   мерцание огня 3 кадра × 140 мс, радиус ±5 % (DESIGN §4.5).
##
## Данные зон (ZoneData.ambient_level) остаются источником истины T-13/T-16;
## профиль только валидирует/ограничивает их и задаёт общие параметры слоя.

## DESIGN §8.7: ambient мира не светлее 0.5 и не темнее 0.26.
const AMBIENT_MIN: float = 0.26
const AMBIENT_MAX: float = 0.5
## DESIGN §8.7: меню всегда читаемое, отдельный светлый ambient.
const AMBIENT_MENU: float = 0.78

## DESIGN §8.7: квантование на 6–8 ступеней.
const DITHER_LEVELS_MIN: int = 6
const DITHER_LEVELS_MAX: int = 8
const DITHER_LEVELS_DEFAULT: int = 8
## Сила дизеринга Байера 4×4 (0 — чистая постеризация, 1 — максимальный шум).
const DITHER_STRENGTH_DEFAULT: float = 0.5
## DESIGN §8.7: лёгкая виньетка; в режиме «читаемость силуэтов» — 0.
const VIGNETTE_STRENGTH: float = 0.28
## DESIGN §4.5: пламя — 3 кадра по 140 мс, мерцание радиуса ±5 %.
const FLAME_FRAME_SEC: float = 0.14
const FLAME_RADIUS_STEPS: Array[float] = [1.0, 1.05, 0.95]

## Базовый ambient зоны; для меню применяется через `menu_mode`.
@export_range(0.0, 1.0, 0.01) var ambient_level: float = 0.42
## Меню/инвентарь: ambient 0.78 и без виньетки (DESIGN §8.7).
@export var menu_mode: bool = false
## Виньетка включена (в меню всегда выключена, в a11y-режиме гасится рантаймом).
@export var vignette_enabled: bool = true
@export_range(6, 8, 1) var dither_levels: int = DITHER_LEVELS_DEFAULT
@export_range(0.0, 1.0, 0.01) var dither_strength: float = DITHER_STRENGTH_DEFAULT


## Итоговый ambient: меню 0.78, мир ограничен 0.26…0.5.
func effective_ambient() -> float:
	if menu_mode:
		return AMBIENT_MENU
	return world_ambient(ambient_level)


## Количество ступеней постеризации (всегда 6–8).
func effective_levels() -> int:
	return levels_for(dither_levels)


## Сила виньетки до учёта Config.silhouette_readability.
func vignette_strength() -> float:
	if menu_mode or not vignette_enabled:
		return 0.0
	return VIGNETTE_STRENGTH


## Профиль из данных зоны T-13/T-16.
static func from_zone(data: ZoneData) -> LightingProfile:
	var result := LightingProfile.new()
	if data != null:
		result.ambient_level = data.ambient_level
	return result


## Профиль меню: светлый ambient 0.78, без виньетки.
static func menu_profile() -> LightingProfile:
	var result := LightingProfile.new()
	result.menu_mode = true
	result.ambient_level = AMBIENT_MENU
	result.vignette_enabled = false
	return result


## Ограничение ambient мира диапазоном DESIGN §8.7.
static func world_ambient(level: float) -> float:
	return clampf(level, AMBIENT_MIN, AMBIENT_MAX)


## Ограничение ступеней постеризации.
static func levels_for(value: int) -> int:
	return clampi(value, DITHER_LEVELS_MIN, DITHER_LEVELS_MAX)


## Ступенчатое мерцание огня: 1.0 / 1.05 / 0.95 (3 кадра × 140 мс).
## В режиме «Без мигания» всегда 1.0 — свет не мерцает.
static func flame_multiplier(at_time: float, no_flash: bool = false) -> float:
	if no_flash:
		return 1.0
	# +epsilon: 0.42 s — ровно 3 кадра, но 0.42/0.14 во float чуть меньше 3.
	var frame: int = int(floor(maxf(at_time, 0.0) / FLAME_FRAME_SEC + 0.0001)) % FLAME_RADIUS_STEPS.size()
	return FLAME_RADIUS_STEPS[frame]
