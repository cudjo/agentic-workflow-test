class_name Teacher
extends Node2D
## Teacher — учитель характеристик и навыков (T-29, US-08, AC-08.1/08.2).
##
## Учитель повышает одну характеристику на 1 за очки обучения; стоимость
## следующего шага берётся из `data/balance/progression.tres` и растёт по
## таблице (AC-08.1). Навыки имеют предусловия по характеристикам: если
## сила/ловкость ниже требуемой, навык недоступен, а причина содержит
## требуемое и текущее значение (AC-08.2).
##
## Состояние — только `GameState` (`stats`, `learning_points`, `abilities`),
## поэтому загрузка сейва сразу согласована с учителем. Навыки хранятся в
## `GameState.abilities` по `ability_id` — существующее поле сейва v3,
## отдельного поля не требуется.
##
## Контракт для T-28 (диалоги NPC):
##   * `get_interact_info()` — имя, повышение характеристики и список навыков;
##   * `train()` — повысить характеристику (возвращает результат GameState);
##   * `get_skill_info(skill_id)` / `learn_skill(skill_id)` — карточка навыка
##     и покупка (ok/reason/missing/cost).
##
## Учитель не рисует UI и не эмитит собственных сигналов: изменение
## характеристик/очков идёт через `EventBus` из `GameState`
## (`stat_changed`, `learning_points_changed`), получение навыка —
## `ability_acquired`.

const TEACHERS_DIR: String = "res://data/balance/teachers"

## Данные учителя; можно назначить в сцене или оставить пустым и задать
## `teacher_id` — тогда ресурс загрузится из `data/balance/teachers/`.
@export var teacher_data: TeacherData = null
@export var teacher_id: StringName = &""
## Радиус взаимодействия для будущего NPC-контроллера (T-28), px.
@export var interaction_radius: float = 16.0


## Подмена данных в тестах/сценах без загрузки с диска.
func configure(data: TeacherData) -> void:
	teacher_data = data
	teacher_id = data.id if data != null else &""


func get_data() -> TeacherData:
	if teacher_data == null:
		teacher_data = _load_teacher(teacher_id)
	return teacher_data


func get_teacher_id() -> StringName:
	var data: TeacherData = get_data()
	return data.id if data != null else teacher_id


func get_display_name() -> String:
	var data: TeacherData = get_data()
	return data.display_name if data != null else ""


# ------------------------------------------------------------------------------
# Stat training (AC-08.1)
# ------------------------------------------------------------------------------

## id повышаемой характеристики; пусто, если данных нет.
func get_trainable_stat() -> StringName:
	var data: TeacherData = get_data()
	return data.stat_id if data != null else &""


## Карточка повышения для диалога/инвентаря:
## `{stat_id, stat_name, value, next_value, cost, cost_after, learning_points,
##   can_afford, maxed, available, reason}`.
func get_training_info() -> Dictionary:
	var data: TeacherData = get_data()
	if data == null:
		return {
			"stat_id": &"",
			"stat_name": "",
			"value": 0,
			"next_value": 0,
			"cost": -1,
			"cost_after": -1,
			"learning_points": GameState.learning_points,
			"can_afford": false,
			"maxed": true,
			"available": false,
			"reason": tr("npc.teacher.not_found"),
		}

	var stat_id: StringName = data.stat_id
	var value: int = GameState.get_stat(stat_id)
	var cost: int = GameState.get_training_cost(stat_id)
	var maxed: bool = cost < 0
	var can_afford: bool = not maxed and GameState.learning_points >= cost
	var reason: String = ""
	if maxed:
		reason = tr("npc.teacher.maxed")
	elif not can_afford:
		reason = tr("npc.teacher.not_enough_points") % [
			cost,
			GameState.learning_points,
		]
	return {
		"stat_id": stat_id,
		"stat_name": GameState.get_stat_name(stat_id),
		"value": value,
		"next_value": value + 1 if not maxed else value,
		"cost": cost,
		"cost_after": GameState.get_training_cost(stat_id, value + 1),
		"learning_points": GameState.learning_points,
		"can_afford": can_afford,
		"maxed": maxed,
		"available": not maxed and can_afford,
		"reason": reason,
	}


## Повышает характеристику учителя на 1, списывая очки обучения по таблице.
## Возвращает результат `GameState.train_stat()` (ok/reason/cost_paid/...).
func train() -> Dictionary:
	var data: TeacherData = get_data()
	if data == null:
		return {
			"ok": false,
			"reason": "no_data",
			"stat_id": &"",
			"cost": -1,
			"learning_points": GameState.learning_points,
		}
	var result: Dictionary = GameState.train_stat(data.stat_id)
	result["teacher_id"] = data.id
	return result


# ------------------------------------------------------------------------------
# Skills (AC-08.2)
# ------------------------------------------------------------------------------

func get_skill_ids() -> Array[StringName]:
	var data: TeacherData = get_data()
	return data.get_skill_ids() if data != null else []


## Карточка навыка с предусловиями (AC-08.2):
## `{skill_id, display_name, ability_id, cost, learned, prerequisites_met,
##   affordable, available, requires, missing, reason}`.
func get_skill_info(skill_id: StringName) -> Dictionary:
	var data: TeacherData = get_data()
	if data == null:
		return _unavailable_skill(skill_id, tr("npc.teacher.not_found"))
	var skill: Dictionary = data.get_skill(skill_id)
	if skill.is_empty():
		return _unavailable_skill(skill_id, tr("npc.teacher.skill_not_found"))

	var ability_id: StringName = skill.get("ability_id", skill_id)
	var cost: int = int(skill.get("cost", 0))
	var learned: bool = GameState.has_ability(ability_id)
	var requirements: Dictionary = skill.get("requires", {})
	var checks: Dictionary = GameState.check_requirements(requirements)
	var prerequisites_met: bool = bool(checks.get("met", true))
	var affordable: bool = GameState.learning_points >= cost

	var reason: String = ""
	if learned:
		reason = tr("npc.teacher.skill_learned")
	elif not prerequisites_met:
		reason = str(checks.get("reason", ""))
	elif not affordable:
		reason = tr("npc.teacher.not_enough_points") % [
			cost,
			GameState.learning_points,
		]

	return {
		"skill_id": skill_id,
		"display_name": skill.get("display_name", String(skill_id)),
		"ability_id": ability_id,
		"cost": cost,
		"learned": learned,
		"prerequisites_met": prerequisites_met,
		"affordable": affordable,
		"available": not learned and prerequisites_met and affordable,
		"requires": requirements.duplicate(true),
		"missing": checks.get("missing", []),
		"reason": reason,
	}


func can_learn_skill(skill_id: StringName) -> bool:
	return bool(get_skill_info(skill_id).get("available", false))


## Изучает навык: проверяет предусловия, списывает очки и выдаёт ability_id
## в `GameState.abilities`. Недоступный навык ничего не меняет (AC-08.2).
func learn_skill(skill_id: StringName) -> Dictionary:
	var info: Dictionary = get_skill_info(skill_id)
	if not bool(info.get("available", false)):
		return {
			"ok": false,
			"reason": info.get("reason", "unavailable"),
			"skill_id": skill_id,
			"ability_id": info.get("ability_id", &""),
			"cost": info.get("cost", 0),
			"missing": info.get("missing", []),
			"learning_points": GameState.learning_points,
		}

	var cost: int = int(info.get("cost", 0))
	var ability_id: StringName = info.get("ability_id", skill_id)
	if not GameState.spend_learning_points(cost):
		return {
			"ok": false,
			"reason": "not_enough_points",
			"skill_id": skill_id,
			"ability_id": ability_id,
			"cost": cost,
			"missing": [],
			"learning_points": GameState.learning_points,
		}
	if not GameState.add_ability(ability_id):
		# Гонка/повтор: очки не должны пропасть.
		GameState.add_learning_points(cost)
		return {
			"ok": false,
			"reason": "already_learned",
			"skill_id": skill_id,
			"ability_id": ability_id,
			"cost": cost,
			"missing": [],
			"learning_points": GameState.learning_points,
		}

	return {
		"ok": true,
		"reason": "",
		"skill_id": skill_id,
		"ability_id": ability_id,
		"cost": cost,
		"missing": [],
		"learning_points": GameState.learning_points,
	}


## Полный снимок для диалога T-28.
func get_interact_info() -> Dictionary:
	var data: TeacherData = get_data()
	var skill_infos: Array[Dictionary] = []
	for skill_id: StringName in get_skill_ids():
		skill_infos.append(get_skill_info(skill_id))
	return {
		"teacher_id": get_teacher_id(),
		"display_name": get_display_name(),
		"training": get_training_info(),
		"skills": skill_infos,
	}


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _unavailable_skill(skill_id: StringName, reason: String) -> Dictionary:
	return {
		"skill_id": skill_id,
		"display_name": "",
		"ability_id": &"",
		"cost": 0,
		"learned": false,
		"prerequisites_met": false,
		"affordable": false,
		"available": false,
		"requires": {},
		"missing": [],
		"reason": reason,
	}


## Загрузка данных по id: сначала `<id>.tres`, затем поиск по полю `id`.
## Некорректный ресурс не используется — учитель остаётся недоступным.
func _load_teacher(id: StringName) -> TeacherData:
	if id == &"":
		return null
	var direct_path: String = TEACHERS_DIR.path_join("%s.tres" % String(id))
	if ResourceLoader.exists(direct_path):
		var direct: TeacherData = load(direct_path) as TeacherData
		if direct != null and direct.is_valid() and direct.id == id:
			return direct

	var directory: DirAccess = DirAccess.open(TEACHERS_DIR)
	if directory == null:
		push_warning("Teacher: cannot open %s" % TEACHERS_DIR)
		return null
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var path: String = TEACHERS_DIR.path_join(file_name)
		var candidate: TeacherData = load(path) as TeacherData
		if candidate != null and candidate.id == id and candidate.is_valid():
			return candidate
	push_warning("Teacher: teacher '%s' not found in %s" % [id, TEACHERS_DIR])
	return null
