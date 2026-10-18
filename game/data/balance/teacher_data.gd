class_name TeacherData
extends Resource
## TeacherData — данные учителя (T-29, US-08/AC-08.2).
## Файлы: `data/balance/teachers/<teacher_id>.tres`.
##
## Учитель повышает одну характеристику на 1 за очки обучения (AC-08.1)
## и обучает навыкам с предусловиями по характеристикам (AC-08.2).
##
## `skills` — словарь skill_id → {
##   display_name: String,          # имя для диалога (T-28)
##   ability_id: StringName,        # id в GameState.abilities (по умолчанию skill_id)
##   cost: int,                     # стоимость в очках обучения
##   requires: {stat_id: int},      # предусловия (сила/ловкость/...)
## }.
## Навык считается изученным, если его ability_id уже есть в
## `GameState.abilities` — так он персистится существующим полем сейва (v3).
##
## Логика (проверка предусловий, трата очков) — в `entities/npc/teacher.gd`,
## правила характеристик — в `core/progression/progression_rules.gd`.

@export var id: StringName = &""
## Ключ локализации (`tr()` в T-36).
@export var display_name_key: String = ""
## Читаемое имя (заглушка до T-36).
@export var display_name: String = ""
## Характеристика, которую повышает учитель (id из ProgressionData).
@export var stat_id: StringName = &""
## Навыки: skill_id → {display_name, ability_id, cost, requires}.
@export var skills: Dictionary = {}


func get_skill_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: Variant in skills.keys():
		var skill_id: StringName = StringName(str(key))
		if skill_id != &"":
			result.append(skill_id)
	result.sort()
	return result


func has_skill(skill_id: StringName) -> bool:
	return skill_id != &"" and skills.has(skill_id)


## Нормализованное описание навыка; пусто для неизвестного id.
## `{skill_id, display_name, ability_id, cost, requires}`.
func get_skill(skill_id: StringName) -> Dictionary:
	if not has_skill(skill_id):
		return {}
	var raw: Variant = skills[skill_id]
	var entry: Dictionary = raw if raw is Dictionary else {}
	var ability_text: String = str(entry.get("ability_id", String(skill_id)))
	if ability_text.is_empty():
		ability_text = String(skill_id)
	return {
		"skill_id": skill_id,
		"display_name": str(entry.get("display_name", String(skill_id))),
		"ability_id": StringName(ability_text),
		"cost": maxi(_as_int(entry.get("cost", 0), 0), 0),
		"requires": EquipmentRequirements.normalize(entry.get("requires", {})),
	}


## Валидация данных учителя. Проверка соответствия stat_id каталогу
## характеристик делается в `ProgressionRules`/`GameState` при загрузке.
func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or display_name_key.is_empty():
		return false
	if stat_id == &"":
		return false
	if skills.is_empty():
		return false

	var ability_ids: Dictionary = {}
	for skill_id: StringName in get_skill_ids():
		var skill: Dictionary = get_skill(skill_id)
		if skill.is_empty():
			return false
		if str(skill.get("display_name", "")).is_empty():
			return false
		var ability_id: StringName = skill.get("ability_id", &"")
		if ability_id == &"" or ability_ids.has(ability_id):
			return false
		ability_ids[ability_id] = true
		if int(skill.get("cost", 0)) <= 0:
			return false
		var requires: Dictionary = skill.get("requires", {})
		if requires.is_empty():
			return false
		for stat_key: Variant in requires.keys():
			if _as_int(requires[stat_key], 0) <= 0:
				return false
	return true


static func _as_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	return fallback
