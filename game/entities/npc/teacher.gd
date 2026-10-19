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
## Fix-3a (N3): учителя размещены в мире (зона 1, хаб) и доступны по `interact`.
## Учитель сам показывает компактную панель прокачки (тот же ввод, что у
## остальных экранов: ↑/↓, Enter/A, Esc/B), поэтому AC-08.1/08.2 достижимы
## игровым потоком, а не только в GUT. UI живёт рядом с логикой учителя и не
## дублирует `ui/inventory` (T-21).
##
## Учитель не эмитит собственных сигналов: изменение характеристик/очков идёт
## через `EventBus` из `GameState` (`stat_changed`, `learning_points_changed`),
## получение навыка — `ability_acquired`.

const TEACHERS_DIR: String = "res://data/balance/teachers"
## Группа для QA/интеграции: `PlayerInteraction` ищет NPC отдельно, а учителя
## находятся одним запросом (`get_nodes_in_group("teachers")`).
const GROUP: StringName = &"teachers"
## Слой панели прокачки: поверх игрового UI (Main.UI=20), ниже pause-меню (50).
const PANEL_LAYER: int = 21

## Данные учителя; можно назначить в сцене или оставить пустым и задать
## `teacher_id` — тогда ресурс загрузится из `data/balance/teachers/`.
@export var teacher_data: TeacherData = null
@export var teacher_id: StringName = &""
## Радиус взаимодействия для NPC-контроллера (T-28), px.
@export var interaction_radius: float = 14.0
## Пауза на время панели прокачки (как у остальных модальных экранов).
@export var pause_on_open: bool = true
## Цвет силуэта-заглушки в мире до арта.
@export var placeholder_color: Color = Color(0.34, 0.29, 0.24, 1.0)

var _panel_layer: CanvasLayer
var _panel_root: Control
var _panel_title: Label
var _points_label: Label
var _rows_box: VBoxContainer
var _status_label: Label
var _close_button: AshenMenuItem
var _panel: AshenPanel
var _built: bool = false
var _pause_previous: bool = false
var _pause_owned: bool = false
var _rows: Array[AshenMenuItem] = []


func _ready() -> void:
	add_to_group(GROUP)
	# Панель должна принимать ввод и при `get_tree().paused = true`.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	queue_redraw()


func _exit_tree() -> void:
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false


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


## Взаимодействие из мира (контракт T-28): снимок учителя + доступность
## тренировки/навыков. Не меняет состояние — покупки делают `train()`/
## `learn_skill()` (их вызывает панель или диалог).
func interact() -> Dictionary:
	var info: Dictionary = get_interact_info()
	return {
		"ok": bool(info.get("can_interact", false)),
		"teacher_id": get_teacher_id(),
		"info": info,
		"training": get_training_info(),
		"skills": get_all_skill_infos(),
	}


## Полный снимок для диалога T-28 / QA:
## `{teacher_id, display_name, interaction_radius, can_interact, reason,
##   training, skills}`.
func get_interact_info() -> Dictionary:
	var data: TeacherData = get_data()
	var can_interact: bool = data != null and data.is_valid()
	return {
		"teacher_id": get_teacher_id(),
		"display_name": get_display_name(),
		"stat_id": get_trainable_stat(),
		"interaction_radius": interaction_radius,
		"can_interact": can_interact,
		"reason": "" if can_interact else tr("npc.teacher.not_found"),
		"training": get_training_info() if data != null else {},
		"skills": get_all_skill_infos() if data != null else [],
	}


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


func get_all_skill_infos() -> Array[Dictionary]:
	var skill_infos: Array[Dictionary] = []
	for skill_id: StringName in get_skill_ids():
		skill_infos.append(get_skill_info(skill_id))
	return skill_infos


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


# ------------------------------------------------------------------------------
# World interaction (N3): interact opens the compact training panel.
# ------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _panel_layer != null and _panel_layer.visible:
		if event.is_action_pressed(&"ui_cancel"):
			close()
			_consume_input()
		return
	if not event.is_action_pressed(&"interact"):
		return
	if not can_open() or not _player_in_range():
		return
	open()
	_consume_input()


## Доступен ли учитель для открытия (не в бою, не во время перехода/другого UI).
func can_open() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	if get_tree().paused:
		return false
	if not bool(get_interact_info().get("can_interact", false)):
		return false
	if GameState.in_combat:
		return false
	if SceneRouter.has_method(&"is_input_locked") and SceneRouter.is_input_locked():
		return false
	return true


func open() -> void:
	_ensure_ui()
	if _panel_layer == null or _panel_layer.visible:
		return
	_refresh(false)
	_panel_layer.visible = true
	_panel_root.visible = true
	_pause_previous = get_tree().paused
	_pause_owned = pause_on_open and not _pause_previous
	if pause_on_open:
		get_tree().paused = true
	_focus_first_row()


func close() -> void:
	if _panel_layer == null or not _panel_layer.visible:
		return
	_panel_layer.visible = false
	if _panel_root != null:
		_panel_root.visible = false
	if _pause_owned:
		get_tree().paused = _pause_previous
		_pause_owned = false
	_release_focus()


func is_open() -> bool:
	return _panel_layer != null and _panel_layer.visible


func _player_in_range() -> bool:
	if not is_inside_tree():
		return false
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null or not (player is Node2D):
		return false
	return global_position.distance_to((player as Node2D).global_position) <= interaction_radius


func _consume_input() -> void:
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------
# Panel UI
# ------------------------------------------------------------------------------

func _ensure_ui() -> void:
	if _built:
		return
	_built = true

	_panel_layer = CanvasLayer.new()
	_panel_layer.name = "TeacherPanel"
	_panel_layer.layer = PANEL_LAYER
	_panel_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel_layer.visible = false
	add_child(_panel_layer)

	_panel_root = Control.new()
	_panel_root.name = "Root"
	_panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_layer.add_child(_panel_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UITokens.VOID, 0.9)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(dim)

	_panel = AshenPanel.new()
	_panel.name = "Panel"
	_panel.variant = UIStyle.PanelVariant.GLASS
	_panel.padding = 8
	_panel_root.add_child(_panel)
	_panel.position = Vector2(48, 18)
	_panel.size = Vector2(384, 234)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)

	_panel_title = _make_label("", UITokens.GOLD_3, UITokens.FONT_H2)
	_panel_title.name = "Title"
	box.add_child(_panel_title)

	_points_label = _make_label("", UITokens.STEEL_3, UITokens.FONT_BODY)
	_points_label.name = "Points"
	box.add_child(_points_label)

	var separator := ColorRect.new()
	separator.color = UITokens.STONE_9
	separator.custom_minimum_size = Vector2(0, UITokens.BORDER_INNER)
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(separator)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.add_theme_constant_override("separation", 2)
	_rows_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_rows_box)

	_status_label = _make_label("", UITokens.BLOOD_3, UITokens.FONT_BODY, true)
	_status_label.name = "Status"
	box.add_child(_status_label)

	_close_button = AshenMenuItem.new()
	_close_button.name = "Close"
	_close_button.text = tr("ui.inv.close")
	_close_button.font_size = UITokens.FONT_BODY
	_close_button.pressed.connect(close)
	box.add_child(_close_button)


func _make_label(
	text: String,
	color: Color,
	size: int = UITokens.FONT_BODY,
	wrap: bool = false
) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIStyle.font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	)
	return label


func _refresh(keep_status: bool) -> void:
	if not _built:
		return
	var data: TeacherData = get_data()
	_panel_title.text = get_display_name() if not get_display_name().is_empty() else String(get_teacher_id())
	_points_label.text = "%s: %d" % [tr("ui.inv.learning_points"), GameState.learning_points]
	if _status_label != null and not keep_status:
		_status_label.text = ""

	for row: AshenMenuItem in _rows:
		row.free()
	_rows.clear()

	if data == null or not data.is_valid():
		_status_label.text = tr("npc.teacher.not_found")
		_focus_first_row()
		return

	var training: Dictionary = get_training_info()
	var stat_row := _make_action_row(
		"%s  %d → %d   [%d]" % [
			str(training.get("stat_name", "")),
			int(training.get("value", 0)),
			int(training.get("next_value", 0)),
			int(training.get("cost", 0)),
		],
		bool(training.get("available", false)),
		str(training.get("reason", ""))
	)
	stat_row.name = "Train_%s" % String(training.get("stat_id", &""))
	stat_row.pressed.connect(_on_train_pressed)
	_add_row(stat_row)

	for skill: Dictionary in get_all_skill_infos():
		var skill_row := _make_action_row(
			"%s   [%d]" % [
				str(skill.get("display_name", skill.get("skill_id", ""))),
				int(skill.get("cost", 0)),
			],
			bool(skill.get("available", false)),
			str(skill.get("reason", ""))
		)
		skill_row.name = "Skill_%s" % String(skill.get("skill_id", &""))
		skill_row.pressed.connect(_on_skill_pressed.bind(StringName(skill.get("skill_id", &""))))
		_add_row(skill_row)

	if _close_button != null:
		_close_button.text = tr("ui.inv.close")
	_focus_first_row()


func _make_action_row(text: String, available: bool, reason: String) -> AshenMenuItem:
	var row := AshenMenuItem.new()
	row.text = text
	row.font_size = UITokens.FONT_BODY
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.disabled = not available
	row.disabled_reason = reason
	return row


func _add_row(row: AshenMenuItem) -> void:
	_rows_box.add_child(row)
	_rows.append(row)


func _focus_first_row() -> void:
	if not is_open():
		return
	for row: AshenMenuItem in _rows:
		if not row.disabled:
			row.grab_focus()
			return
	if _close_button != null:
		_close_button.grab_focus()


func _release_focus() -> void:
	if get_viewport() == null:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and is_instance_valid(focus) and _panel_root != null \
			and _panel_root.is_ancestor_of(focus):
		focus.release_focus()


func _on_train_pressed() -> void:
	var result: Dictionary = train()
	if bool(result.get("ok", false)):
		_status_label.text = "+1  %s" % GameState.get_stat_name(get_trainable_stat())
	else:
		_status_label.text = str(result.get("reason", tr("npc.teacher.not_found")))
	_refresh(true)


func _on_skill_pressed(skill_id: StringName) -> void:
	var info: Dictionary = get_skill_info(skill_id)
	var result: Dictionary = learn_skill(skill_id)
	if bool(result.get("ok", false)):
		_status_label.text = "+  %s" % str(info.get("display_name", String(skill_id)))
	else:
		_status_label.text = str(result.get("reason", tr("npc.teacher.skill_not_found")))
	_refresh(true)


# ------------------------------------------------------------------------------
# World placeholder art
# ------------------------------------------------------------------------------

func _draw() -> void:
	# Капюшон и мантия 12×20 px в палитре stone/steel — до арта NPC.
	draw_rect(Rect2(-6, -20, 12, 4), placeholder_color.lightened(0.15))
	draw_rect(Rect2(-5, -16, 10, 3), placeholder_color.lightened(0.15))
	draw_rect(Rect2(-3, -16, 6, 5), UITokens.STONE_5)
	draw_rect(Rect2(-7, -11, 14, 11), placeholder_color)
	draw_rect(Rect2(-1, -9, 2, 9), placeholder_color.darkened(0.2))


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
