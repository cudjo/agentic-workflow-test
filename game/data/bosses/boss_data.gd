class_name BossData
extends Resource
## BossData — параметры босса (T-30). Файлы: `data/bosses/*.tres`.
##
## Один ресурс описывает босса целиком: HP, тело, 2–3 фазы, награду и
## сцены снарядов/вызовов. Пороги фаз — константы дизайна 66%/33%
## (`PHASE_TWO_THRESHOLD` / `PHASE_THREE_THRESHOLD`), но каждая фаза хранит
## свой `hp_threshold_ratio`: другой босс может иметь 2 фазы, а порядок
## порогов проверяется в `is_valid()`.
##
## Общие боевые тайминги (вспышка попадания, отшатывание, длительность
## смерти, переход фазы) — `data/balance/balancing.tres`; здесь только
## характеристики конкретного босса.

## Порог начала второй фазы (AC-03.4, HUD-метка 66%).
const PHASE_TWO_THRESHOLD: float = 0.66
## Порог начала третьей фазы (AC-03.4, HUD-метка 33%).
const PHASE_THREE_THRESHOLD: float = 0.33
## Допустимое число фаз у босса (TASKS T-30: 2–3).
const MIN_PHASES: int = 2
const MAX_PHASES: int = 3

@export_group("Identity")
@export var id: StringName = &""
## Ключ локализации (`tr()` в T-36); босс сам UI не рисует.
@export var display_name_key: String = ""
## Читаемое имя (заглушка до T-36), используется HUD-панелью босса.
@export var display_name: String = ""
## Зона, в которой стоит босс (ключ EC-09: награда выдаётся при входе в неё).
@export var zone_id: StringName = &""

@export_group("Stats")
@export var max_hp: float = 240.0
## Порог прерывания: урон меньше poise не переводит босса в Hurt.
@export_range(0.0, 1.0, 0.01) var knockback_resistance: float = 0.8
## 0 — любой урон сбивает с атаки.
@export var poise: float = 0.0

@export_group("Body")
@export var body_size: Vector2 = Vector2(24.0, 36.0)
@export var hurtbox_size: Vector2 = Vector2(22.0, 34.0)
## Цвет программной заглушки (арт заменится без изменения логики).
@export var body_color: Color = Color(0.62, 0.42, 0.27, 1.0)

@export_group("Phases")
## Фазы по возрастанию порога: первая всегда 1.0, последняя — самая низкая.
@export var phases: Array[BossPhaseData] = []

@export_group("Projectiles and summons")
## Снаряд для дальних паттернов (переиспользует боевое ядро T-10/T-12).
@export var projectile_scene: PackedScene
## Сцена призываемого врага (паттерны `summon`).
@export var summon_scene: PackedScene

@export_group("Reward")
@export var reward: BossRewardData


## Индекс фазы для HP-доли: последняя фаза, порог которой уже достигнут.
func get_phase_index_for_ratio(ratio: float) -> int:
	if phases.is_empty():
		return 0
	var clamped: float = clampf(ratio, 0.0, 1.0)
	for index: int in range(phases.size() - 1, -1, -1):
		var phase: BossPhaseData = phases[index]
		if phase != null and clamped <= phase.hp_threshold_ratio + 0.0001:
			return index
	return 0


func get_phase(index: int) -> BossPhaseData:
	if index < 0 or index >= phases.size():
		return null
	return phases[index]


func get_phase_count() -> int:
	return phases.size()


## Метки фаз для панели босса HUD (T-19), от старшей к младшей.
func get_display_name() -> String:
	return LocaleText.lookup(display_name_key, display_name)


func get_phase_thresholds() -> PackedFloat32Array:
	var marks := PackedFloat32Array()
	for index: int in range(1, phases.size()):
		var phase: BossPhaseData = phases[index]
		if phase != null:
			marks.append(phase.hp_threshold_ratio)
	return marks


## Цвет заглушки с непрозрачностью 1 (для сброса после вспышки/смерти).
func get_body_color() -> Color:
	var color := body_color
	color.a = 1.0
	return color


## Проверка данных: ловит битые `.tres` до рантайма (T-30, Zero Dead Config).
func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or zone_id == &"":
		return false
	if max_hp <= 0.0 or poise < 0.0:
		return false
	if knockback_resistance < 0.0 or knockback_resistance > 1.0:
		return false
	if body_size.x <= 0.0 or body_size.y <= 0.0:
		return false
	if hurtbox_size.x <= 0.0 or hurtbox_size.y <= 0.0:
		return false
	if phases.size() < MIN_PHASES or phases.size() > MAX_PHASES:
		return false
	if reward == null or not reward.is_valid():
		return false
	if body_color.a <= 0.0:
		return false

	var previous_threshold: float = 1.0
	for index: int in phases.size():
		var phase: BossPhaseData = phases[index]
		if phase == null or not phase.is_valid():
			return false
		if index == 0:
			if not is_equal_approx(phase.hp_threshold_ratio, 1.0):
				return false
		elif phase.hp_threshold_ratio >= previous_threshold:
			return false
		previous_threshold = phase.hp_threshold_ratio
		if phase.projectile_count > 0 and projectile_scene == null:
			return false
		if phase.summon_count > 0 and summon_scene == null:
			return false
	return true
