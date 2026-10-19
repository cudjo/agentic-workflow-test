extends Node
## Main — корневая сцена: текущая зона (WorldRoot) + слои UI (PLAN §2.3, DESIGN §4.4).
## Переход зоны (T-17) заменяет только WorldRoot; слои постоянны:
##   HUD=10, UI=20, Toasts=30, Overlay=40 (затемнения/смерть/загрузка).
##
## T-18: тема UI назначается окну в рантайме (а не через gui/theme/custom),
## чтобы `--headless --import` на чистом клоне не пытался загрузить шрифты до
## их импорта. Все Control под Main наследуют тему от Window.
##
## Fix-1: сюжетный триггер выбора фракции (US-06) и EC-13 — пауза при потере
## фокуса окна. Оба поведения живут здесь, потому что Main переживает смену зон
## и не вмешивается в UI-экраны (`ui/**`).
##
## Fix-3a (N1): отмена `FactionChoice` (Esc/B) больше не «съедает» выбор
## навсегда. Экран сообщает о закрытии сигналом `closed`; если фракция так и не
## выбрана, запрос снимается и может быть повторён следующим сюжетным событием
## (`quest_completed`) или закрытием диалога. Подтверждённый выбор не сбрасывается.
##
## Fix-4a:
##   * B-04 — «В главное меню» на экране смерти: Main слушает сигнал DeathScreen,
##     снимает death-состояние, сбрасывает SceneRouter и грузит MainMenu.tscn
##     (раньше сигнал никто не слушал → soft-lock).
##   * MINOR-05 — присяга открывается только по сюжетному квесту
##     (`FACTION_OATH_QUEST`), а не по завершению любого квеста.

const THEME_PATH := "res://ui/theme/main_theme.tres"
## Слой паузы — поверх любого игрового слоя (Overlay=40), поэтому 50.
const PAUSE_LAYER: int = 50
## Узел экрана выбора фракции монтируется в Main.tscn (T-24).
const FACTION_CHOICE_PATH := "FactionChoice"
## Экран смерти лежит в постоянном Overlay-слое Main.tscn (layer 40).
const DEATH_SCREEN_PATH := "Overlay/DeathScreen"
const MAIN_MENU_SCENE_PATH := "res://ui/menus/MainMenu.tscn"
## MINOR-05: единственный сюжетный квест, завершение которого означает присягу
## (квест старейшины в хабе). Остальные квесты меняют репутацию (AC-06.1), но
## не открывают выбор фракции: иначе экран присяги всплывал бы после любого
## побочного квеста. Новый сюжетный триггер — добавить id сюда (или вызвать
## `EventBus.faction_choice_requested` из кат-сцены).
const FACTION_OATH_QUEST: StringName = &"quest_free_smuggle"

## Квест завершён, но экран выбора фракции ещё не показан (ждём закрытия диалога).
var _faction_choice_pending: bool = false
## Выбор уже запрошен в этом забеге — второй раз не открываем.
var _faction_choice_requested: bool = false

var _faction_choice_screen: Node = null
var _pause_menu: CanvasLayer = null
var _pause_owned: bool = false
## B-04: защита от повторного запроса меню (смена сцены асинхронна).
var _returning_to_menu: bool = false
## Хук для GUT/интеграции: подменяет `change_scene_to_file` (смена current_scene
## внутри GUT уничтожила бы раннер). В игре пуст — грузится MainMenu.tscn.
var menu_scene_loader: Callable = Callable()


func _ready() -> void:
	var window := get_window()
	if window != null:
		var ui_theme := load(THEME_PATH) as Theme
		if ui_theme != null:
			window.theme = ui_theme

	_connect_flow_events()
	_connect_death_screen()

	# T-17: первый вход в зону. Синхронно — это инициализация мира, дальше все
	# переходы идут фоновым потоком через SceneRouter.change_zone().
	if SceneRouter.has_method(&"bootstrap"):
		SceneRouter.bootstrap()


func _exit_tree() -> void:
	if EventBus.quest_completed.is_connected(_on_quest_completed):
		EventBus.quest_completed.disconnect(_on_quest_completed)
	if EventBus.dialogue_finished.is_connected(_on_dialogue_finished):
		EventBus.dialogue_finished.disconnect(_on_dialogue_finished)
	_disconnect_faction_choice()
	_disconnect_death_screen()
	if _pause_owned:
		get_tree().paused = false
		_pause_owned = false


# ------------------------------------------------------------------------------
# Faction choice trigger (US-06, T-28 → T-24)
# ------------------------------------------------------------------------------

func _connect_flow_events() -> void:
	if not EventBus.quest_completed.is_connected(_on_quest_completed):
		EventBus.quest_completed.connect(_on_quest_completed)
	if not EventBus.dialogue_finished.is_connected(_on_dialogue_finished):
		EventBus.dialogue_finished.connect(_on_dialogue_finished)
	_connect_faction_choice()


## Экран выбора фракции живёт в Main.tscn; сигнал `closed` нужен, чтобы отличить
## подтверждение от отмены и не блокировать US-06 после Esc/B (N1).
func _connect_faction_choice() -> void:
	_faction_choice_screen = get_node_or_null(FACTION_CHOICE_PATH)
	if _faction_choice_screen == null:
		return
	if not _faction_choice_screen.has_signal(&"closed"):
		return
	var callback := Callable(self, &"_on_faction_choice_closed")
	if not _faction_choice_screen.is_connected(&"closed", callback):
		_faction_choice_screen.connect(&"closed", callback)


func _disconnect_faction_choice() -> void:
	if _faction_choice_screen == null or not is_instance_valid(_faction_choice_screen):
		_faction_choice_screen = null
		return
	var callback := Callable(self, &"_on_faction_choice_closed")
	if _faction_choice_screen.has_signal(&"closed") \
			and _faction_choice_screen.is_connected(&"closed", callback):
		_faction_choice_screen.disconnect(&"closed", callback)
	_faction_choice_screen = null


## Ключевой квест завершён: после закрытия диалога сюжет требует присяги.
## Выбор уже сделан — сигнал не нужен (концовка T-32 не переспрашивает).
## MINOR-05: только `FACTION_OATH_QUEST`; побочные квесты меняют репутацию, но
## присягу не открывают (раньше триггер срабатывал на любом `quest_completed`).
func _on_quest_completed(quest_id: StringName, _title: String) -> void:
	if quest_id != FACTION_OATH_QUEST:
		return
	if _faction_choice_requested or FactionManager.is_faction_chosen():
		return
	_faction_choice_pending = true
	if not _is_dialogue_open():
		_request_faction_choice.call_deferred()


func _on_dialogue_finished(_dialogue_id: StringName, _npc_id: StringName) -> void:
	if _faction_choice_pending:
		_request_faction_choice.call_deferred()


## Отмена/закрытие экрана без присяги: снимаем флаг, чтобы повторный
## `quest_completed` (или закрытие следующего диалога) снова открыл выбор.
## После подтверждения `FactionManager.is_faction_chosen()` уже true — флаг
## остаётся, повторный запрос не возникает.
func _on_faction_choice_closed() -> void:
	if FactionManager.is_faction_chosen():
		return
	_faction_choice_requested = false
	# Выбор остаётся доступен и без нового квеста: достаточно поговорить с NPC
	# (экран откроется после `dialogue_finished`), а не сразу после Esc.
	_faction_choice_pending = true


## Открывает `FactionChoice` через шину событий. Пока диалог открыт, запрос
## откладывается до `dialogue_finished`, чтобы экран не открылся под диалогом.
func _request_faction_choice() -> void:
	if not _faction_choice_pending or _faction_choice_requested:
		return
	if _is_dialogue_open():
		return
	_faction_choice_pending = false
	if FactionManager.is_faction_chosen():
		return
	_faction_choice_requested = true
	EventBus.faction_choice_requested.emit("")


func _is_dialogue_open() -> bool:
	var screen := get_node_or_null("DialogueScreen")
	return (
		screen != null
		and screen.has_method(&"is_open")
		and bool(screen.call(&"is_open"))
	)


# ------------------------------------------------------------------------------
# B-04: экран смерти → «В главное меню»
# ------------------------------------------------------------------------------

## DeathScreen эмитит `main_menu_requested`, но раньше его никто не слушал:
## кнопка скрывала экран, игра оставалась мёртвой (hp=0, death_active) без
## ввода — soft-lock. Main — постоянная сцена, поэтому связываем здесь.
func _connect_death_screen() -> void:
	var death_screen := get_node_or_null(DEATH_SCREEN_PATH)
	if death_screen == null or not death_screen.has_signal(&"main_menu_requested"):
		return
	var callback := Callable(self, &"_on_main_menu_requested")
	if not death_screen.is_connected(&"main_menu_requested", callback):
		death_screen.connect(&"main_menu_requested", callback)


func _disconnect_death_screen() -> void:
	var death_screen := get_node_or_null(DEATH_SCREEN_PATH)
	if death_screen == null or not is_instance_valid(death_screen):
		return
	var callback := Callable(self, &"_on_main_menu_requested")
	if death_screen.has_signal(&"main_menu_requested") \
			and death_screen.is_connected(&"main_menu_requested", callback):
		death_screen.disconnect(&"main_menu_requested", callback)


## Завершает забег в памяти и открывает главное меню. Сейвы на диске не
## трогаются: «Продолжить»/«Загрузить» восстановят последний слот (включая
## death-автосейв EC-04). Сбрасываем death-состояние, чтобы новая сцена Main не
## унаследовала hp=0/`death_active`; SceneRouter освобождает игрока и зону.
func _on_main_menu_requested() -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
	if _pause_owned:
		get_tree().paused = false
		_pause_owned = false
	GameState.reset_death_state(false)
	GameState.set_in_combat(false)
	if SceneRouter.has_method(&"reset"):
		SceneRouter.reset()
	_open_main_menu()


func _open_main_menu() -> void:
	if menu_scene_loader.is_valid():
		menu_scene_loader.call()
		return
	var error: Error = get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		_returning_to_menu = false
		push_error(
			"Main: не удалось открыть главное меню '%s' (%s)"
			% [MAIN_MENU_SCENE_PATH, error_string(error)]
		)


# ------------------------------------------------------------------------------
# EC-13: фокус окна потерян — пауза + меню
# ------------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_focus_lost()


func _on_focus_lost() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	# Уже стоим на паузе (открыт диалог/инвентарь/выбор фракции) — не плодим меню.
	if get_tree().paused:
		return
	_open_pause_menu()


func _open_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.visible = true
	else:
		_pause_menu = _build_pause_menu()
		# Потеря фокуса может прийти во время рассылки notification по дереву —
		# добавление узла откладываем, чтобы не попасть в «parent is busy».
		add_child.call_deferred(_pause_menu)
	_pause_owned = true
	get_tree().paused = true
	_focus_pause_resume.call_deferred()


func _focus_pause_resume() -> void:
	if _pause_menu == null or not is_instance_valid(_pause_menu):
		return
	if not _pause_menu.is_inside_tree():
		return
	var resume := _pause_menu.get_node_or_null("Root/Center/Panel/Box/Resume") as Button
	if resume != null:
		resume.grab_focus()


func _build_pause_menu() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "PauseMenu"
	layer.layer = PAUSE_LAYER
	# Экран должен принимать ввод и при `get_tree().paused = true`.
	layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.06, 0.09, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := AshenPanel.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(240, 88)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.text = "ПАУЗА / PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var resume := AshenMenuItem.new()
	resume.name = "Resume"
	resume.text = "ПРОДОЛЖИТЬ / RESUME"
	resume.pressed.connect(_on_pause_resume_pressed)
	box.add_child(resume)
	return layer


func _on_pause_resume_pressed() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.visible = false
	if _pause_owned:
		get_tree().paused = false
		_pause_owned = false
