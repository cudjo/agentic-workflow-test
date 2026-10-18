class_name ProgressionRules
extends RefCounted
## ProgressionRules — чистая логика прогрессии (T-29, US-08).
##
## Оборачивает `ProgressionData` и сравнивает таблицы с текущими
## характеристиками. Не читает и не пишет `GameState`: состоянием владеет
## автолоад, поэтому правила тестируются без сцены и без сохранений.
##
## Контракт для T-19/T-21:
##   * `get_step_cost(stat_id, current)` — цена следующего шага (−1 — максимум);
##   * `get_start_stats()` — стартовый набор новой игры;
##   * `get_level_for_xp(total_xp)`, `get_xp_to_next_level(level, total_xp)`;
##   * `check_requirements({stat_id: min})` — `{requirements, met, missing, reason}`
##     для предусловий навыков (AC-08.2) и требований экипировки (T-21).

var data: ProgressionData = null


func _init(progression_data: ProgressionData = null) -> void:
	data = progression_data


# ------------------------------------------------------------------------------
# Stats
# ------------------------------------------------------------------------------

func get_stat_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	if data != null:
		result.assign(data.stat_ids)
	return result


func has_stat(stat_id: StringName) -> bool:
	return data != null and data.has_stat(stat_id)


func get_stat_name(stat_id: StringName) -> String:
	return data.get_stat_name(stat_id) if data != null else String(stat_id)


## Имена характеристик для текстов причин (`СИЛА`, `ЛОВКОСТЬ`, ...).
func get_stat_labels() -> Dictionary:
	var labels: Dictionary = {}
	for stat_id: StringName in get_stat_ids():
		labels[stat_id] = get_stat_name(stat_id)
	return labels


func get_start_value(stat_id: StringName) -> int:
	return data.get_start_value(stat_id) if data != null else 0


func get_max_value(stat_id: StringName) -> int:
	return data.get_max_value(stat_id) if data != null else 0


## Стартовый набор характеристик новой игры.
func get_start_stats() -> Dictionary:
	var stats: Dictionary = {}
	for stat_id: StringName in get_stat_ids():
		stats[stat_id] = get_start_value(stat_id)
	return stats


## Цена следующего шага; -1 — характеристика максимальна/неизвестна.
func get_step_cost(stat_id: StringName, current_value: int) -> int:
	if data == null:
		return -1
	return data.get_step_cost(stat_id, current_value)


func can_increase(stat_id: StringName, current_value: int) -> bool:
	return get_step_cost(stat_id, current_value) > 0


## Приводит снимок характеристик к валидному состоянию: известные id,
## значения в [start, max], отсутствующие — стартовые. Неизвестные id
## отбрасываются, чтобы старый/ручной сейв не ломал загрузку.
func normalize_stats(raw: Dictionary) -> Dictionary:
	var stats: Dictionary = get_start_stats()
	if raw == null:
		return stats
	for stat_id: StringName in get_stat_ids():
		var value: Variant = raw.get(stat_id)
		if not (value is int or value is float):
			continue
		stats[stat_id] = clampi(
			int(value),
			get_start_value(stat_id),
			get_max_value(stat_id)
		)
	return stats


# ------------------------------------------------------------------------------
# Experience / levels
# ------------------------------------------------------------------------------

func get_max_level() -> int:
	return data.get_max_level() if data != null else 1


## Максимальный уровень, если данных нет (безопасный fallback).
func get_learning_points_per_level() -> int:
	return data.learning_points_per_level if data != null else 0


func get_level_for_xp(total_xp: int) -> int:
	if data == null:
		return 1
	return data.get_level_for_xp(total_xp)


## Сколько XP осталось до следующего уровня (0 на максимуме).
func get_xp_to_next_level(level: int, total_xp: int) -> int:
	if data == null:
		return 0
	var required: int = data.get_xp_required_for_level(level + 1)
	if required < 0:
		return 0
	return maxi(required - maxi(total_xp, 0), 0)


## Накопленный XP для достижения уровня (-1 выше максимума).
func get_xp_required_for_level(level: int) -> int:
	return data.get_xp_required_for_level(level) if data != null else 0


## Очки обучения за переход между уровнями (0, если уровень не вырос).
func get_learning_points_awarded(from_level: int, to_level: int) -> int:
	var gained: int = maxi(to_level, 1) - maxi(from_level, 1)
	if gained <= 0:
		return 0
	return gained * get_learning_points_per_level()


## Ограничение уровня диапазоном [1, max_level].
func clamp_level(level: int) -> int:
	return clampi(level, 1, maxi(get_max_level(), 1))


# ------------------------------------------------------------------------------
# Requirements (skills AC-08.2, equipment T-21)
# ------------------------------------------------------------------------------

## Проверка требований `{stat_id: min}` против снимка характеристик.
## Возвращает `{requirements, met, missing, reason}`; reason содержит
## требуемое значение и текущее (AC-08.2).
func check_requirements(raw: Dictionary, stats: Dictionary) -> Dictionary:
	return EquipmentRequirements.describe(raw, stats, get_stat_labels())


## Требования предмета из данных (`equipment_requirements`).
func get_equipment_requirements(item_id: StringName) -> Dictionary:
	return data.get_equipment_requirements(item_id) if data != null else {}


## Описание требований предмета для слота инвентаря (T-21):
## `{item_id, requirements, met, missing, reason}`.
func get_equipment_info(item_id: StringName, stats: Dictionary) -> Dictionary:
	var info: Dictionary = check_requirements(get_equipment_requirements(item_id), stats)
	info["item_id"] = item_id
	return info


func meets_equipment_requirements(item_id: StringName, stats: Dictionary) -> bool:
	return bool(get_equipment_info(item_id, stats).get("met", false))
