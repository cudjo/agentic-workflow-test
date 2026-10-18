class_name ProgressionData
extends Resource
## ProgressionData — таблицы прогрессии персонажа (T-29, US-08).
## Файл: `data/balance/progression.tres`. В коде нет ни стартовых значений,
## ни стоимости шагов, ни порогов опыта — только загрузка и валидация.
##
## Характеристики: сила, ловкость, выносливость, здоровье. Значение
## характеристики — целое; повышение всегда на 1 (AC-08.1).
##
## Стоимость шага — явная таблица `step_costs`: id характеристики →
## массив цен. Индекс = текущее значение − `start_values[id]`, поэтому
## `step_costs[id][0]` — цена первого повышения. Стоимость строго растёт
## по таблице (AC-08.1), конец таблицы = максимальное значение.
##
## Опыт: `xp_thresholds` — накопленный опыт, необходимый для достижения
## уровней 2, 3, ... (индекс 0 — суммарный XP для уровня 2). Уровень 1
## начинается с 0 XP. `learning_points_per_level` начисляется за каждый
## новый уровень.
##
## Требования экипировки: `equipment_requirements` — id предмета →
## {stat_id: минимальное значение}. Контракт для инвентаря T-21:
## проверка живёт в `ProgressionRules`/`GameState`, данные — здесь.

@export_group("Stats")
## Порядок характеристик для UI (детерминированный).
@export var stat_ids: Array[StringName] = []
## id → читаемое имя (заглушка до T-36, потом ключ локализации).
@export var stat_names: Dictionary = {}
## id → стартовое значение новой игры.
@export var start_values: Dictionary = {}
## id → максимальное значение.
@export var max_values: Dictionary = {}
## id → таблица цен следующих шагов (PackedInt32Array или Array[int]).
@export var step_costs: Dictionary = {}
## Прирост максимального HP за каждую единицу здоровья сверх стартовой.
@export var health_per_point: float = 5.0
## Прирост максимальной выносливости за каждую единицу выносливости.
@export var stamina_per_point: float = 5.0

@export_group("Experience")
## Накопительные пороги XP для уровней 2..N (строго возрастают).
@export var xp_thresholds: PackedInt32Array = PackedInt32Array()
## Очки обучения за каждый новый уровень.
@export var learning_points_per_level: int = 2
## Опыт за врагов: enemy_id → XP (0/отсутствие — без награды).
@export var enemy_xp: Dictionary = {}
## Опыт за квесты: quest_id → XP (T-28 вызывает `GameState.award_quest_xp`).
@export var quest_xp: Dictionary = {}

@export_group("Equipment")
## Требования экипировки: item_id → {stat_id: минимум}. Пусто — предмет
## не имеет требований (T-21 показывает «ЕСТЬ»).
@export var equipment_requirements: Dictionary = {}


## Стартовое значение характеристики (0 для неизвестной).
func get_start_value(stat_id: StringName) -> int:
	return _as_int(start_values.get(stat_id, 0), 0)


## Максимальное значение характеристики (0 для неизвестной).
func get_max_value(stat_id: StringName) -> int:
	return _as_int(max_values.get(stat_id, 0), 0)


func get_stat_name(stat_id: StringName) -> String:
	return str(stat_names.get(stat_id, String(stat_id)))


func has_stat(stat_id: StringName) -> bool:
	return stat_ids.has(stat_id)


## Цена следующего шага от `current_value`. -1 — характеристика максимальна
## или неизвестна (повышение недоступно).
func get_step_cost(stat_id: StringName, current_value: int) -> int:
	if not has_stat(stat_id):
		return -1
	var start: int = get_start_value(stat_id)
	var maximum: int = get_max_value(stat_id)
	if current_value < start or current_value >= maximum:
		return -1
	var table_value: Variant = step_costs.get(stat_id)
	if not (table_value is Array or table_value is PackedInt32Array):
		return -1
	var index: int = current_value - start
	if table_value is PackedInt32Array:
		var packed: PackedInt32Array = table_value
		if index < 0 or index >= packed.size():
			return -1
		return packed[index]
	var table: Array = table_value
	if index < 0 or index >= table.size():
		return -1
	return _as_int(table[index], -1)


## Таблица цен характеристики для UI (копия, мутация не меняет данные).
func get_step_cost_table(stat_id: StringName) -> Array[int]:
	var result: Array[int] = []
	var table_value: Variant = step_costs.get(stat_id)
	if table_value is PackedInt32Array:
		for value: int in table_value:
			result.append(value)
	elif table_value is Array:
		for value: Variant in table_value:
			result.append(_as_int(value, 0))
	return result


## Накопленный XP, нужный для достижения `level`. 0 для уровня 1;
## -1 для уровня выше максимума.
func get_xp_required_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var index: int = level - 2
	if index >= xp_thresholds.size():
		return -1
	return xp_thresholds[index]


## Уровень по накопленному XP с учётом максимума.
func get_level_for_xp(total_xp: int) -> int:
	var safe_xp: int = maxi(total_xp, 0)
	var level: int = 1
	for threshold: int in xp_thresholds:
		if safe_xp < threshold:
			break
		level += 1
	return level


## Максимальный уровень (1 + число порогов).
func get_max_level() -> int:
	return xp_thresholds.size() + 1


## Опыт за врага по id (0 — награды нет).
func get_enemy_xp(enemy_id: StringName) -> int:
	return maxi(_as_int(enemy_xp.get(enemy_id, 0), 0), 0)


## Опыт за квест по id (0 — награды нет).
func get_quest_xp(quest_id: StringName) -> int:
	return maxi(_as_int(quest_xp.get(quest_id, 0), 0), 0)


## Требования предмета (копия). Пусто — требований нет.
func get_equipment_requirements(item_id: StringName) -> Dictionary:
	var raw: Variant = equipment_requirements.get(item_id)
	if not raw is Dictionary:
		return {}
	var copy: Dictionary = {}
	for key: Variant in (raw as Dictionary).keys():
		var stat_id: StringName = StringName(str(key))
		var value: Variant = (raw as Dictionary)[key]
		if stat_id == &"" or not (value is int or value is float):
			continue
		copy[stat_id] = int(value)
	return copy


## Валидация таблиц: ловит битый `.tres` до рантайма (Zero Dead Config).
func is_valid() -> bool:
	if stat_ids.is_empty():
		return false

	var seen: Dictionary = {}
	for stat_id: StringName in stat_ids:
		if stat_id == &"" or seen.has(stat_id):
			return false
		seen[stat_id] = true
		if get_stat_name(stat_id).is_empty():
			return false
		var start: int = get_start_value(stat_id)
		var maximum: int = get_max_value(stat_id)
		if start < 0 or maximum <= start:
			return false
		var costs: Array[int] = get_step_cost_table(stat_id)
		if costs.size() != maximum - start:
			return false
		var previous: int = 0
		for cost: int in costs:
			if cost <= previous:
				return false
			previous = cost

	if not equipment_requirements is Dictionary:
		return false
	for item_key: Variant in equipment_requirements.keys():
		if str(item_key).is_empty():
			return false
		var requirements: Variant = equipment_requirements[item_key]
		if not requirements is Dictionary:
			return false
		for stat_key: Variant in (requirements as Dictionary).keys():
			var stat_id: StringName = StringName(str(stat_key))
			var value: Variant = (requirements as Dictionary)[stat_key]
			if not seen.has(stat_id):
				return false
			if not (value is int or value is float) or int(value) <= 0:
				return false

	if health_per_point < 0.0 or stamina_per_point < 0.0:
		return false
	if learning_points_per_level < 0:
		return false

	if xp_thresholds.is_empty():
		return false
	var previous_threshold: int = 0
	for threshold: int in xp_thresholds:
		if threshold <= previous_threshold:
			return false
		previous_threshold = threshold

	for table: Variant in [enemy_xp, quest_xp]:
		if not table is Dictionary:
			return false
		for key: Variant in (table as Dictionary).keys():
			if str(key).is_empty():
				return false
			var value: Variant = (table as Dictionary)[key]
			if not (value is int or value is float) or int(value) <= 0:
				return false
	return true


static func _as_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and value.is_valid_int():
		return value.to_int()
	return fallback
