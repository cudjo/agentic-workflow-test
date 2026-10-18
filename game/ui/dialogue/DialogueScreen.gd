class_name DialogueScreen
extends CanvasLayer
## DialogueScreen — диалоговый экран NPC (T-28, DESIGN §6.4).
##
## Переиспользует `AshenDialog` T-18: портрет 52×52, имя gold-3 + фракция
## stone-5, печать 1 символ / 22 мс, ответы 2×2 с тегом `[Фракция±N]`.
## Экран только связывает UI и `DialogueRunner`: последствия (репутация,
## квесты, журнал) применяет движок, UI показывает результат.
##
## Управление: ↑/↓/←/→ или D-pad — фокус по ответам (соседи задаются явно,
## чтобы сетка 2×2 навигировалась и без мыши), Enter/Space/A — выбрать,
## Esc/B — закрыть. На не последней странице Enter/A перелистывает текст,
## поэтому длинная RU/EN-реплика не переполняет бокс.

signal dialogue_opened(dialogue_id: StringName)
signal dialogue_closed(dialogue_id: StringName, effects: Array)
signal answer_selected(index: int, effects: Array)

const LAYER: int = 20
const DIALOG_POSITION := Vector2(8, 166)
const HINT_POSITION := Vector2(8, 150)
const FINISH_TEXT: String = "ui.dialogue.finish"
const NEXT_PAGE_TEXT: String = "ui.dialogue.next"

var _ui_root: Control
var _dialog: AshenDialog
var _next_hint: AshenPrompt
var _runner: DialogueRunner = null
var _portrait: Texture2D = null
var _language: String = "ru"
var _showing: bool = false
var _synthetic_finish: bool = false
var _effects: Array[Dictionary] = []
var _built: bool = false


func _init() -> void:
	name = "DialogueScreen"
	layer = LAYER
	visible = false


func _ready() -> void:
	_build()
	_apply_accessibility()
	if not Config.visual_accessibility_changed.is_connected(_apply_accessibility):
		Config.visual_accessibility_changed.connect(_apply_accessibility)


func _exit_tree() -> void:
	if Config.visual_accessibility_changed.is_connected(_apply_accessibility):
		Config.visual_accessibility_changed.disconnect(_apply_accessibility)


# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

## Открыть диалог по данным. `language` пусто — язык системы ("ru"/"en").
func open_dialogue(dialogue: DialogueData, language: String = "") -> bool:
	_build()
	if dialogue == null or not dialogue.is_valid():
		return false
	_language = _resolve_language(language)
	_runner = DialogueRunner.new(dialogue, _language)
	_portrait = dialogue.portrait
	var snapshot: Dictionary = _runner.start()
	return _show(snapshot)


## Открыть диалог NPC (портрет/имя берутся из NPC).
func open_npc(npc: DialogueNpc, language: String = "") -> bool:
	_build()
	if npc == null:
		return false
	var runner: DialogueRunner = npc.create_runner(_resolve_language(language))
	if runner == null:
		return false
	_runner = runner
	_language = runner.language
	_portrait = npc.get_portrait()
	var snapshot: Dictionary = runner.get_snapshot()
	return _show(snapshot)


func close() -> void:
	if not _showing:
		visible = false
		if _ui_root != null:
			_ui_root.visible = false
		return
	_showing = false
	visible = false
	if _ui_root != null:
		_ui_root.visible = false
	var dialogue_id: StringName = _runner.data.id if _runner != null and _runner.data != null else &""
	EventBus.dialogue_finished.emit(
		dialogue_id,
		_runner.data.npc_id if _runner != null and _runner.data != null else &""
	)
	dialogue_closed.emit(dialogue_id, _effects.duplicate(true))


## Esc/B.
func back() -> void:
	close()


func is_open() -> bool:
	return _showing


## Программный выбор ответа (геймпад/тесты); индекс — как в снимке движка.
func select_answer(index: int) -> Dictionary:
	if not _showing or _runner == null:
		return {"ok": false, "reason": "closed"}
	if _synthetic_finish:
		close()
		return {"ok": true, "ended": true, "reason": "finished"}

	var result: Dictionary = _runner.select_answer(index)
	if not bool(result.get("ok", false)):
		return result

	var effects: Array = result.get("effects", [])
	_effects.append_array(effects)
	answer_selected.emit(index, effects)

	if bool(result.get("ended", false)):
		close()
	else:
		_render(result.get("snapshot", {}))
	return result


## Перелистнуть длинную реплику (Enter/A на не последней странице).
func advance_page() -> bool:
	if _runner == null or not _runner.has_next_page():
		return false
	_runner.next_page()
	_render(_runner.get_snapshot())
	return true


func get_dialog() -> AshenDialog:
	return _dialog


func get_runner() -> DialogueRunner:
	return _runner


func get_language() -> String:
	return _language


func get_last_effects() -> Array[Dictionary]:
	return _effects.duplicate(true)


# ------------------------------------------------------------------------------
# Input
# ------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _showing:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		if _dialog != null and _dialog.is_typing():
			return
		if advance_page():
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------
# Rendering
# ------------------------------------------------------------------------------

func _show(snapshot: Dictionary) -> bool:
	if _runner == null:
		return false
	_showing = true
	visible = true
	_ui_root.visible = true
	_render(snapshot)
	var dialogue: DialogueData = _runner.data
	var dialogue_id: StringName = dialogue.id if dialogue != null else &""
	var npc_id: StringName = dialogue.npc_id if dialogue != null else &""
	EventBus.dialogue_started.emit(dialogue_id, npc_id)
	dialogue_opened.emit(dialogue_id)
	return true


func _render(snapshot: Dictionary) -> void:
	if _dialog == null:
		return
	_synthetic_finish = false

	var answers: Array = []
	var raw_answers: Array = snapshot.get("answers", [])
	for entry: Dictionary in raw_answers:
		var disabled: bool = bool(entry.get("disabled", false))
		answers.append({
			"text": str(entry.get("text", "")),
			# Недоступный ответ не несёт последствия: тег скрыт, чтобы
			# длинная причина отказа поместилась в ячейку 2×2.
			"tag": "" if disabled else str(entry.get("tag", "")),
			"disabled": disabled,
			"reason": str(entry.get("reason", "")),
		})

	var has_next_page: bool = bool(snapshot.get("has_next_page", false))
	var ended: bool = bool(snapshot.get("ended", false))
	if answers.is_empty() and not has_next_page and not ended:
		# Терминальный узел без ответов: даём явный выход, чтобы диалог
		# закрывался клавиатурой/геймпадом, а не «зависал».
		answers.append({"text": tr(FINISH_TEXT)})
		_synthetic_finish = true

	_dialog.instant_text = Config.no_flash
	_dialog.setup(
		str(snapshot.get("speaker", "")),
		str(snapshot.get("text", "")),
		answers,
		str(snapshot.get("faction", ""))
	)
	_dialog.set_portrait(_portrait)
	_link_focus(answers.size())
	_update_hint(has_next_page)


func _update_hint(has_next_page: bool) -> void:
	if _next_hint == null:
		return
	_next_hint.visible = has_next_page
	if has_next_page:
		_next_hint.label_text = tr(NEXT_PAGE_TEXT)


## Явные соседи фокуса для сетки 2×2: отключённые ответы пропускаются,
## вертикаль заворачивается. Без этого Godot может увести фокус за пределы
## диалога, и геймпад «теряет» курсор.
func _link_focus(count: int) -> void:
	if _dialog == null:
		return
	for index: int in count:
		var item: AshenMenuItem = _dialog.get_answer_item(index)
		if item == null:
			continue
		# Горизонталь — линейно по доступным ответам: отключённая ячейка не
		# ловит фокус и не создаёт «тупик» для D-pad.
		item.focus_neighbor_left = _linear_neighbor_path(index, count, -1)
		item.focus_neighbor_right = _linear_neighbor_path(index, count, 1)
		item.focus_neighbor_top = _vertical_neighbor_path(index, count, -1)
		item.focus_neighbor_bottom = _vertical_neighbor_path(index, count, 1)


func _linear_neighbor_path(index: int, count: int, step: int) -> NodePath:
	var cursor: int = index + step
	while cursor >= 0 and cursor < count:
		if _answer_enabled(cursor):
			return _dialog.get_answer_item(cursor).get_path()
		cursor += step
	return NodePath()


func _vertical_neighbor_path(index: int, count: int, step: int) -> NodePath:
	var col: int = index % 2
	var row: int = index / 2
	var rows: int = (count + 1) / 2
	var target_row: int = row + step
	if target_row < 0 or target_row >= rows:
		target_row = rows - 1 if step < 0 else 0
	var target: int = target_row * 2 + col
	if target >= count:
		target = target - 1
	if target == index or target < 0 or target >= count:
		return NodePath()
	if _answer_enabled(target):
		return _dialog.get_answer_item(target).get_path()
	# Вторая колонка того же ряда — запасной путь, если целевая отключена.
	var other: int = target_row * 2 + (1 - col)
	if (
		other != index
		and other >= 0
		and other < count
		and _answer_enabled(other)
	):
		return _dialog.get_answer_item(other).get_path()
	return NodePath()


func _answer_enabled(index: int) -> bool:
	var item: AshenMenuItem = _dialog.get_answer_item(index)
	return item != null and not item.disabled


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true

	_ui_root = Control.new()
	_ui_root.name = "Root"
	_ui_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_ui_root)
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_dialog = AshenDialog.new()
	_dialog.name = "Dialog"
	_dialog.focus_answers_on_finish = true
	_ui_root.add_child(_dialog)
	_dialog.position = DIALOG_POSITION
	_dialog.size = UITokens.DIALOG_SIZE
	_dialog.choice_selected.connect(_on_choice_selected)

	_next_hint = AshenPrompt.new()
	_next_hint.name = "NextPageHint"
	_next_hint.setup(&"ui_accept", tr(NEXT_PAGE_TEXT))
	_ui_root.add_child(_next_hint)
	_next_hint.position = HINT_POSITION

	_ui_root.visible = false


func _on_choice_selected(index: int) -> void:
	if _synthetic_finish:
		close()
		return
	select_answer(index)


func _apply_accessibility() -> void:
	if _dialog != null:
		_dialog.instant_text = Config.no_flash


func _resolve_language(language: String) -> String:
	if not language.strip_edges().is_empty():
		return DialogueText.normalize_language(language)
	return DialogueText.normalize_language(TranslationServer.get_locale())



