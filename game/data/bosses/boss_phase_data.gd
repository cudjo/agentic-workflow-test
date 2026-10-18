class_name BossPhaseData
extends Resource
## BossPhaseData — одна фаза босса (T-30, AC-03.4).
##
## Фаза хранит порог HP (`hp_threshold_ratio`), id паттерна и все тайминги
## атаки. Босс не хардкодит поведение: при переходе на фазу он берёт
## `pattern_id` и параметры отсюда, а конкретную реализацию паттерна даёт
## подкласс (`zone_01`, `zone_02`, ...).
##
## Пороги дизайна (см. `BossData.PHASE_TWO_THRESHOLD` / `PHASE_THREE_THRESHOLD`):
##   фаза I   — 100..66% HP (`hp_threshold_ratio = 1.0`)
##   фаза II  — 66..33% HP  (`hp_threshold_ratio = 0.66`)
##   фаза III — 33..0% HP   (`hp_threshold_ratio = 0.33`)
## Значения параметризованы: другой босс может иметь 2 фазы и иной порог.
##
## Зоны опасности окружения (T-31) описаны группой `hazard_*`: сколько зон
## срабатывает за атаку, их telegraph/active-окна, урон и отбрасывание.
## Конкретную геометрию (колонны шахт / руны на полу) задаёт подкласс босса.

@export_group("Identity")
## Человекочитаемое имя фазы для HUD-баннера («ФАЗА II»).
@export var title: String = "ФАЗА I"
## Паттерн атаки: `cleave`, `lunge`, `frenzy`, `bolt`, `volley`, `summon`...
## Реализация выбирается подклассом BossBase по этому id.
@export var pattern_id: StringName = &""
## Фаза начинается, когда HP-доля опускается до этого значения и ниже.
@export_range(0.0, 1.0, 0.01) var hp_threshold_ratio: float = 1.0

@export_group("Movement")
## Скорость сближения/отхода, px/s.
@export var move_speed: float = 40.0
## Желаемая дистанция до игрока; 0 — ближний бой без отхода.
@export var preferred_distance: float = 0.0
## Горизонтальный рывок в активной фазе атаки, px/s; 0 — стоять.
@export var lunge_speed: float = 0.0

@export_group("Attack")
## Дистанция, с которой босс начинает атаку, px.
@export var attack_range: float = 28.0
## Пауза между атаками, s.
@export var attack_cooldown: float = 1.4
## Telegraph перед активной фазой, s.
@export var windup: float = 0.45
## Активная фаза хитбокса/выстрела, s.
@export var active: float = 0.16
## Восстановление после атаки, s.
@export var recovery: float = 0.3
## Урон одной атаки (до формулы/множителей баланса).
@export var attack_damage: float = 8.0
## Сила отбрасывания до множителя `balancing.knockback_scale`.
@export var attack_knockback: float = 120.0
## Размер хитбокса ближней атаки, px.
@export var attack_size: Vector2 = Vector2(28.0, 24.0)
## Смещение хитбокса вперёд по facing, px.
@export var attack_offset: Vector2 = Vector2(16.0, 0.0)

@export_group("Projectiles and summons")
## Сколько снарядов выпускается за атаку; 0 — паттерн без выстрела.
@export var projectile_count: int = 0
## Скорость снаряда, px/s.
@export var projectile_speed: float = 100.0
## Максимальное время жизни снаряда, s.
@export var projectile_lifetime: float = 2.0
## Угол между соседними снарядами веера, градусы (0 — один/параллельно).
@export var projectile_spread_degrees: float = 0.0
## Сколько вызовов (врагов) появляется за атаку; 0 — паттерн без вызовов.
@export var summon_count: int = 0

@export_group("Zone hazards")
## Сколько зон опасности (камнепад в шахтах / руны-ловушки) срабатывает
## за атаку; 0 — паттерн без опасностей окружения (T-31).
@export var hazard_count: int = 0
## Telegraph зоны опасности до срабатывания, s (читаемость удара).
@export var hazard_telegraph: float = 0.5
## Активное окно зоны опасности, s.
@export var hazard_active: float = 0.3
## Урон зоны опасности (до формулы/множителей баланса).
@export var hazard_damage: float = 8.0
## Сила отбрасывания зоны опасности до `balancing.knockback_scale`.
@export var hazard_knockback: float = 100.0


## Полная длительность цикла атаки (windup + active + recovery).
func get_attack_total_time() -> float:
	return maxf(windup, 0.0) + maxf(active, 0.0) + maxf(recovery, 0.0)


## Проверка данных фазы: ловит битые `.tres` до рантайма (Zero Dead Config).
func is_valid() -> bool:
	if title.is_empty() or pattern_id == &"":
		return false
	if hp_threshold_ratio < 0.0 or hp_threshold_ratio > 1.0:
		return false
	if move_speed < 0.0 or preferred_distance < 0.0 or lunge_speed < 0.0:
		return false
	if attack_range <= 0.0 or attack_cooldown < 0.0:
		return false
	if windup < 0.0 or active <= 0.0 or recovery < 0.0:
		return false
	if attack_damage < 0.0 or attack_knockback < 0.0:
		return false
	if attack_size.x <= 0.0 or attack_size.y <= 0.0:
		return false
	if projectile_count < 0 or projectile_speed <= 0.0 or projectile_lifetime <= 0.0:
		return false
	if projectile_spread_degrees < 0.0 or summon_count < 0:
		return false
	if hazard_count < 0 or hazard_damage < 0.0 or hazard_knockback < 0.0:
		return false
	if hazard_count > 0 and (hazard_telegraph <= 0.0 or hazard_active <= 0.0):
		return false
	return true
