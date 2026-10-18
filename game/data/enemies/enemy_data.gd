class_name EnemyData
extends Resource
## EnemyData — параметры типа врага (T-12). Файлы: `data/enemies/*.tres`.
##
## Общие тайминги боя (вспышка попадания, отшатывание, длительность анимации
## смерти, сила отбрасывания) берутся из `data/balance/balancing.tres`.
## Здесь живут только характеристики конкретного типа: HP, скорость, урон,
## радиусы обнаружения/атаки/зоны и тайминги патруля/атаки (TASKS T-12).
##
## `archetype` — не жёсткая ветка поведения, а декларация паттерна: сцены
## `swift/`, `heavy/`, `ranged/`, `undead/` наследуют базовую и добавляют
## свой сигнатурный шаг (рывок, супер-армор, снаряд, возрождение).

enum Archetype {
	SWIFT,
	HEAVY,
	RANGED,
	UNDEAD,
}

@export var id: StringName = &""
## Ключ локализации (`tr()` в T-36); враг сам UI не рисует.
@export var display_name_key: String = ""
@export var archetype: Archetype = Archetype.SWIFT

@export_group("Stats")
## Максимальное здоровье.
@export var max_hp: float = 20.0
## Урон одной атаки (плоское значение; formula для игрока — T-10).
@export var attack_damage: float = 5.0
## Порог прерывания: урон меньше poise не переводит врага в Hurt.
## 0 — любой урон причиняет боль.
@export var poise: float = 0.0
## Доля гасимого отбрасывания: 0 — полное, 1 — полный иммунитет.
@export var knockback_resistance: float = 0.0

@export_group("Movement")
## Скорость патруля, px/s.
@export var patrol_speed: float = 20.0
## Скорость преследования, px/s.
@export var chase_speed: float = 45.0
## Половина ширины патрульной зоны от точки спавна, px.
@export var patrol_range: float = 48.0
## Пауза после разворота на краю/стене, s.
@export var patrol_pause: float = 0.45
## Жёсткая граница зоны от точки спавна, px: дальше враг не уходит.
@export var leash_radius: float = 96.0

@export_group("Detection")
## Радиус обнаружения игрока по горизонтали, px.
@export var detect_radius: float = 80.0
## Допустимое вертикальное расхождение с игроком, px.
@export var vertical_detect_radius: float = 24.0
## Дистанция, с которой открывается атака, px.
@export var attack_radius: float = 20.0
## Желаемая дистанция для ranged-паттерна; 0 — ближний бой.
@export var preferred_distance: float = 0.0

@export_group("Attack")
## Telegraph перед активной фазой, s.
@export var attack_windup: float = 0.25
## Активная фаза хитбокса/выстрела, s.
@export var attack_active: float = 0.12
## Восстановление после атаки, s.
@export var attack_recovery: float = 0.25
## Пауза между атаками, s.
@export var attack_cooldown: float = 1.0
## Сила отбрасывания атаки до множителя `knockback_scale`.
@export var attack_knockback: float = 90.0
## Горизонтальный рывок в активной фазе (swift), px/s; 0 — стоять.
@export var attack_lunge_speed: float = 0.0

@export_group("Body")
@export var body_size: Vector2 = Vector2(12.0, 20.0)
@export var hurtbox_size: Vector2 = Vector2(12.0, 20.0)
@export var attack_size: Vector2 = Vector2(18.0, 18.0)
## Смещение хитбокса атаки вперёд по facing, px.
@export var attack_offset: Vector2 = Vector2(12.0, 0.0)
## Цвет программной заглушки (арт заменится без изменения логики).
@export var body_color: Color = Color(0.6, 0.5, 0.4, 1.0)

@export_group("Projectile")
## Сцена снаряда; обязательна для archetype == RANGED.
@export var projectile_scene: PackedScene
## Скорость снаряда, px/s.
@export var projectile_speed: float = 90.0
## Максимальное время жизни снаряда, s.
@export var projectile_lifetime: float = 1.5

@export_group("Undead")
## Сколько раз враг поднимается после смерти; 0 — обычная смерть.
@export var revive_count: int = 0
## Доля HP при возрождении.
@export var revive_hp_ratio: float = 0.5
## Дополнительное время «лежания» перед возрождением, s.
@export var revive_delay: float = 0.35


## Полная длительность боевого цикла атаки (windup + active + recovery).
func get_attack_total_time() -> float:
	return maxf(attack_windup, 0.0) + maxf(attack_active, 0.0) + maxf(attack_recovery, 0.0)


## Цвет заглушки с непрозрачностью 1 (для сброса после вспышки/смерти).
func get_body_color() -> Color:
	var color := body_color
	color.a = 1.0
	return color


## Проверка данных: ловит битые .tres до рантайма (T-12, Zero Dead Config).
func is_valid() -> bool:
	if id == &"":
		return false
	if max_hp <= 0.0 or attack_damage < 0.0:
		return false
	if knockback_resistance < 0.0 or knockback_resistance > 1.0:
		return false
	if poise < 0.0:
		return false
	if patrol_speed < 0.0 or chase_speed <= 0.0:
		return false
	if patrol_range < 0.0 or leash_radius < patrol_range:
		return false
	if patrol_pause < 0.0:
		return false
	if detect_radius <= 0.0 or vertical_detect_radius <= 0.0 or attack_radius <= 0.0:
		return false
	if preferred_distance < 0.0:
		return false
	if attack_windup < 0.0 or attack_active <= 0.0 or attack_recovery < 0.0:
		return false
	if attack_cooldown < 0.0 or attack_lunge_speed < 0.0:
		return false
	if attack_knockback < 0.0:
		return false
	if body_size.x <= 0.0 or body_size.y <= 0.0:
		return false
	if hurtbox_size.x <= 0.0 or hurtbox_size.y <= 0.0:
		return false
	if attack_size.x <= 0.0 or attack_size.y <= 0.0:
		return false
	if archetype == Archetype.RANGED:
		if projectile_scene == null or projectile_speed <= 0.0 or projectile_lifetime <= 0.0:
			return false
	if revive_count < 0 or revive_hp_ratio <= 0.0 or revive_hp_ratio > 1.0:
		return false
	return true
