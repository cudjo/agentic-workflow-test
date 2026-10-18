class_name Campfire
extends CanvasLayer
## Костёр: диалог и сохранение (T-23, DESIGN §6.4/§8.5, SPEC US-05/AC-05.1,
## Q3/EC-06, EC-14; макет `docs/mockups/campfire.html`).
##
## Слои (DESIGN §4.4): диалог — CanvasLayer 20 (меню/диалоги), тост — вложенный
## CanvasLayer 40, чтобы подтверждение/ошибка читались поверх любого экрана.
## Сцена скрыта до `open()`; `Main.tscn` держит её как единую точку сохранения.
##
## Поток:
##   TALK   — реплика печатается 1 символ / 22 мс (AshenDialog), фокус
##            «Сохранить игру»; в бою пункт отключён с причиной (EC-06).
##   SLOTS  — 3 карточки из `SaveManager.get_slot_metadata`: занят (зона,
##            уровень, время, «Перезапись») / пуст.
##   SAVED  — тост «СОХРАНЕНО · СЛОТ N» ≤ 1 с, «Продолжить путь».
##   ERROR  — тост опасности «Нет места на диске. Прежняя запись цела.»
##            (EC-14) и варианты Повторить / Другой слот / Отмена.
##
## Сохранение идёт только через `Bonfire.save_to_slot()` (T-26) — единственную
## точку записи. Fallback на `SaveManager.save_slot()` оставлен для сцен без
## костра (тесты/меню слотов), при этом EC-06 проверяется и здесь.
##
## Ответ с последствием помечен тегом `[Фракция±N]`; выбор применяет
## `FactionManager.apply_reputation_event()` (AC-06.1). Величина в теге берётся
## из таблицы Δ данных, а не хардкодится.

signal opened
signal closed
signal saved(slot: int)
signal save_error(slot: int, reason: String)

enum State { TALK, SLOTS, SAVED, ERROR }
enum Action { SAVE, ABOUT, OATH, LEAVE, CONTINUE, RETRY, ANOTHER_SLOT, CANCEL }

const LAYER: int = 20
const TOAST_LAYER: int = 40

const SPEAKER_NAME: String = "Хранитель Огня"
const SPEAKER_FACTION_FALLBACK: String = "Орден Пепла"
const SPEAKER_FACTION_ID: StringName = &"order"
const OATH_FACTION: StringName = &"order"
## Событие таблицы Δ, которым помечен ответ «Клятва» (данные T-27/T-23):
## +1 Ордену, без побочных квестовых последствий.
const OATH_EVENT: StringName = &"action_campfire_oath"

const TALK_TEXT: String = (
	"Пламя помнит тех, кто возвращается. Дать ему запомнить и тебя?"
)
const SLOTS_TEXT: String = "Выбери, где огонь оставит твой след. Старая запись угаснет."
const SAVED_TEXT: String = "Огонь запомнил тебя. Иди, пока он не погас."
## Полная причина видна в реплике и тосте; в списке — короткая подпись,
## потому что 27 символов не помещаются в колонку 2×2 при 8 px (a11y).
const COMBAT_REASON_FULL: String = "Сохранение в бою запрещено"
const COMBAT_TEXT: String = (
	"Не здесь, путник. Пока рядом враги. Сохранение в бою запрещено."
)
const ERROR_TEXT: String = "Огонь гаснет... запись не легла. Но прежняя цела."
const CORRUPTED_TEXT: String = "Огонь не узнаёт эту запись. Выбери другой слот."
const ABOUT_TEXT: String = "Болото помнит мёртвых. Оно не отдаёт своих без платы."
const OATH_ALREADY_TEXT: String = "Клятва уже принесена."

const SAVE_ANSWER: String = "Сохранить игру"
const ABOUT_ANSWER: String = "О Болоте"
const OATH_ANSWER: String = "Клятва"
const LEAVE_ANSWER: String = "Уйти  Esc"
const CONTINUE_ANSWER: String = "Продолжить путь"
const RETRY_ANSWER: String = "Повторить"
const ANOTHER_SLOT_ANSWER: String = "Другой слот"
const CANCEL_ANSWER: String = "Отмена  Esc"
const SLOT_HEADING: String = "СОХРАНИТЬ В СЛОТ"
const EMPTY_SLOT_TEXT: String = "— Пусто —"
const DAMAGED_SLOT_TEXT: String = "! Слот повреждён"

## EC-06: короткая причина в списке и полная — в тосте/реплике.
const COMBAT_REASON: String = "В бою нельзя"
const COMBAT_TOAST: String = COMBAT_REASON_FULL
## EC-14: старый слот цел — атомарная запись SaveManager (T-25).
const DISK_ERROR_TOAST: String = "Нет места на диске. Прежняя запись цела."
const CORRUPTED_TOAST: String = "Слот повреждён. Прежняя запись цела."

## Подтверждение сохранения ≤ 1 с (AC-05.1). 0.9 с оставляет запас.
const SUCCESS_TOAST_DURATION: float = 0.9
## Ошибку/запрет читаем дольше: это не подтверждение, ограничения ≤1 с нет.
const DANGER_TOAST_DURATION: float = 1.8

const SLOTS_PANEL_POSITION := Vector2(96, 22)
const SLOTS_PANEL_WIDTH: int = 288
const SLOT_CARD_HEIGHT: int = 28
const SLOT_CARD_GAP: int = 2
const DIALOG_POSITION := Vector2(8, 166)
const TOAST_TOP: int = 20
const TOAST_ROW_HEIGHT: int = 32

var _ui_root: Control
var _dialog: AshenDialog
var _slots_panel: AshenPanel
var _slot_cards: Array[Button] = []
var _slot_hint: HBoxContainer
var _toast_layer: CanvasLayer
var _toast_row: HBoxContainer
var _toast: AshenToast

var _state: State = State.TALK
var _answer_actions: Array[int] = []
var _selected_slot: int = 1
var _pending_slot: int = 1
var _error_corrupted: bool = false
var _oath_taken: bool = false
var _bonfire: Bonfire
var _showing: bool = false
var _built: bool = false


func _init() -> void:
	name = "Campfire"
	layer = LAYER
	visible = false


func _ready() -> void:
	_build()
	_apply_accessibility()
	if not EventBus.save_completed.is_connected(_on_save_completed):
		EventBus.save_completed.connect(_on_save_completed)
	if not EventBus.save_failed.is_connected(_on_save_failed):
		EventBus.save_failed.connect(_on_save_failed)
	if not EventBus.slot_corrupted.is_connected(_on_slot_corrupted):
		EventBus.slot_corrupted.connect(_on_slot_corrupted)
	if not EventBus.combat_state_changed.is_connected(_on_combat_state_changed):
		EventBus.combat_state_changed.connect(_on_combat_state_changed)
	if not Config.visual_accessibility_changed.is_connected(_apply_accessibility):
		Config.visual_accessibility_changed.connect(_apply_accessibility)


func _exit_tree() -> void:
	if EventBus.save_completed.is_connected(_on_save_completed):
		EventBus.save_completed.disconnect(_on_save_completed)
	if EventBus.save_failed.is_connected(_on_save_failed):
		EventBus.save_failed.disconnect(_on_save_failed)
	if EventBus.slot_corrupted.is_connected(_on_slot_corrupted):
		EventBus.slot_corrupted.disconnect(_on_slot_corrupted)
	if EventBus.combat_state_changed.is_connected(_on_combat_state_changed):
		EventBus.combat_state_changed.disconnect(_on_combat_state_changed)
	if Config.visual_accessibility_changed.is_connected(_apply_accessibility):
		Config.visual_accessibility_changed.disconnect(_apply_accessibility)


# ------------------------------------------------------------------------------
# Публичный API (интеграция с костром/миром и тесты)
# ------------------------------------------------------------------------------

## Открывает диалог. Без аргумента ищет костёр из группы `bonfires` (по
## `GameState.respawn_bonfire`, иначе первый). Возвращает true, если открыт.
func open(bonfire: Bonfire = null) -> bool:
	_build()
	if bonfire != null:
		_bonfire = bonfire
	elif _bonfire == null or not is_instance_valid(_bonfire):
		_bonfire = _find_bonfire()

	_selected_slot = _initial_slot()
	_pending_slot = _selected_slot
	_error_corrupted = false
	_oath_taken = false
	_apply_accessibility()
	_refresh_slot_cards()

	_showing = true
	visible = true
	_ui_root.visible = true
	_toast_layer.visible = true
	_set_state(State.TALK)
	if GameState.in_combat:
		_show_danger(COMBAT_TOAST)
	opened.emit()
	return true


func close() -> void:
	if not _showing:
		visible = false
		if _toast_layer != null:
			_toast_layer.visible = false
		return
	_showing = false
	if _toast != null:
		_toast.hide_message()
	_release_focus()
	visible = false
	if _ui_root != null:
		_ui_root.visible = false
	if _toast_layer != null:
		_toast_layer.visible = false
	_state = State.TALK
	closed.emit()


func is_open() -> bool:
	return _showing


func back() -> void:
	_handle_back()


## Программный выбор ответа (геймпад/тесты); индексы — как в диалоге.
func select_answer(index: int) -> void:
	_on_answer_selected(index)


## Программный выбор слота (Enter на карточке).
func select_slot(slot: int) -> void:
	if not SaveManager.is_valid_slot(slot):
		return
	_selected_slot = slot
	_save_to_slot(slot)


## Перемещение фокуса по карточкам слотам (↑/↓, с заворотом).
func move_slot_focus(step: int) -> void:
	if _slot_cards.is_empty():
		return
	var index: int = wrapi((_selected_slot - 1) + step, 0, _slot_cards.size())
	_selected_slot = index + 1
	var card: Button = _slot_cards[index]
	if card != null and card.visible and card.is_inside_tree():
		card.grab_focus()


func get_state() -> State:
	return _state


func get_state_name() -> String:
	return ["talk", "slots", "saved", "error"][_state]


func get_dialog() -> AshenDialog:
	return _dialog


func get_toast() -> AshenToast:
	return _toast


func get_toast_layer() -> CanvasLayer:
	return _toast_layer


func get_slots_panel() -> AshenPanel:
	return _slots_panel


func get_slot_card_count() -> int:
	return _slot_cards.size()


func get_slot_card(index: int) -> Button:
	if index < 0 or index >= _slot_cards.size():
		return null
	return _slot_cards[index]


## То, что реально нарисовано на карточке (для тестов/QA).
func get_slot_card_data(index: int) -> Dictionary:
	if index < 0 or index >= _slot_cards.size():
		return {}
	return (_slot_cards[index] as _SlotCard).get_view_data()


func get_selected_slot() -> int:
	return _selected_slot


func get_answer_action(index: int) -> int:
	if index < 0 or index >= _answer_actions.size():
		return -1
	return _answer_actions[index]


func get_bonfire() -> Bonfire:
	return _bonfire


## Метаданные карточки без открытия диалога (чистая функция + SaveManager).
func get_slot_view(slot: int) -> Dictionary:
	return build_slot_view(SaveManager.get_slot_metadata(slot), slot)


# ------------------------------------------------------------------------------
# Построение UI
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

	_build_dialog()
	_build_slots_panel()
	_build_toast()

	_ui_root.visible = false
	_toast_layer.visible = false


func _build_dialog() -> void:
	_dialog = AshenDialog.new()
	_dialog.name = "Dialog"
	_dialog.focus_answers_on_finish = true
	_ui_root.add_child(_dialog)
	_dialog.position = DIALOG_POSITION
	_dialog.size = UITokens.DIALOG_SIZE
	_dialog.choice_selected.connect(_on_answer_selected)


func _build_slots_panel() -> void:
	_slots_panel = AshenPanel.new()
	_slots_panel.name = "SlotPanel"
	_slots_panel.variant = UIStyle.PanelVariant.SOLID
	_slots_panel.padding = UITokens.PANEL_PADDING
	_ui_root.add_child(_slots_panel)
	_slots_panel.position = SLOTS_PANEL_POSITION
	_slots_panel.custom_minimum_size = Vector2(float(SLOTS_PANEL_WIDTH), 0)

	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", SLOT_CARD_GAP)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	_slots_panel.add_child(box)

	var heading := _make_label(SLOT_HEADING, UITokens.GOLD_3)
	heading.name = "Heading"
	heading.custom_minimum_size = Vector2(0, UITokens.LINE_BODY)
	box.add_child(heading)

	for index in SaveManager.SLOT_MAX:
		var slot: int = index + 1
		var card := _SlotCard.new()
		card.name = "Slot%d" % slot
		card.slot_number = slot
		card.custom_minimum_size = Vector2(0, float(SLOT_CARD_HEIGHT))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(_on_slot_card_pressed.bind(slot))
		card.focus_entered.connect(_on_slot_card_focused.bind(slot))
		box.add_child(card)
		_slot_cards.append(card)

	_build_slot_hint(box)
	_slots_panel.size = Vector2(
		float(SLOTS_PANEL_WIDTH),
		_slots_panel.get_combined_minimum_size().y
	)
	_slots_panel.visible = false


func _build_slot_hint(box: VBoxContainer) -> void:
	_slot_hint = HBoxContainer.new()
	_slot_hint.name = "Hint"
	_slot_hint.add_theme_constant_override("separation", UITokens.SP_1)
	_slot_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_slot_hint)

	var up := AshenKbd.new()
	up.action = &"ui_up"
	_slot_hint.add_child(up)
	var down := AshenKbd.new()
	down.action = &"ui_down"
	_slot_hint.add_child(down)

	var slot_label := _make_label("Слот", UITokens.STONE_5)
	slot_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slot_hint.add_child(slot_label)

	var accept := AshenPrompt.new()
	accept.setup(&"ui_accept", "Сохранить")
	_slot_hint.add_child(accept)

	var cancel := AshenPrompt.new()
	cancel.setup(&"ui_cancel", "Назад")
	_slot_hint.add_child(cancel)

	# Подсказка не должна задавать ширину панели: при 200% UI текст переносится
	# в настройках T-20, а сейчас важен порядок клавиш, не перенос.
	_slot_hint.clip_contents = true


func _build_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.name = "Overlay"
	_toast_layer.layer = TOAST_LAYER
	add_child(_toast_layer)

	_toast_row = HBoxContainer.new()
	_toast_row.name = "ToastRow"
	_toast_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_layer.add_child(_toast_row)
	_toast_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast_row.offset_top = float(TOAST_TOP)
	_toast_row.offset_bottom = float(TOAST_TOP + TOAST_ROW_HEIGHT)

	_toast = AshenToast.new()
	_toast.name = "SaveToast"
	_toast.duration = SUCCESS_TOAST_DURATION
	_toast.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toast_row.add_child(_toast)


func _make_label(title: String, color: Color) -> Label:
	var label := Label.new()
	label.text = title
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIStyle.font())
	label.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


# ------------------------------------------------------------------------------
# Состояния и ответы
# ------------------------------------------------------------------------------

func _set_state(state: State) -> void:
	_state = state
	var view: Dictionary = _build_view(state)
	var answers: Array = view.get("answers", [])
	var actions: Array = view.get("actions", [])

	_answer_actions.clear()
	for action: Variant in actions:
		_answer_actions.append(int(action))

	_dialog.setup(
		SPEAKER_NAME,
		str(view.get("text", TALK_TEXT)),
		answers,
		_speaker_faction()
	)

	_slots_panel.visible = state == State.SLOTS
	if state == State.SLOTS:
		_refresh_slot_cards()
		call_deferred(&"_focus_current_slot")
	else:
		_release_slot_focus()


func _build_view(state: State) -> Dictionary:
	match state:
		State.SLOTS:
			return {"text": SLOTS_TEXT, "answers": [], "actions": []}
		State.SAVED:
			return {
				"text": SAVED_TEXT,
				"answers": [{"text": CONTINUE_ANSWER}],
				"actions": [Action.CONTINUE],
			}
		State.ERROR:
			return _error_view()
		_:
			return _talk_view()


func _talk_view() -> Dictionary:
	var in_combat: bool = GameState.in_combat
	var save_answer: Dictionary = {"text": SAVE_ANSWER}
	if in_combat:
		# EC-06: пункт не просто серый — причина видна строкой под ним.
		save_answer["disabled"] = true
		save_answer["reason"] = COMBAT_REASON
	return {
		"text": COMBAT_TEXT if in_combat else TALK_TEXT,
		"answers": [
			save_answer,
			{"text": ABOUT_ANSWER},
			_oath_answer(),
			{"text": LEAVE_ANSWER},
		],
		"actions": [Action.SAVE, Action.ABOUT, Action.OATH, Action.LEAVE],
	}


func _error_view() -> Dictionary:
	if _error_corrupted:
		return {
			"text": CORRUPTED_TEXT,
			"answers": [{"text": ANOTHER_SLOT_ANSWER}, {"text": CANCEL_ANSWER}],
			"actions": [Action.ANOTHER_SLOT, Action.CANCEL],
		}
	return {
		"text": ERROR_TEXT,
		"answers": [
			{"text": RETRY_ANSWER},
			{"text": ANOTHER_SLOT_ANSWER},
			{"text": CANCEL_ANSWER},
		],
		"actions": [Action.RETRY, Action.ANOTHER_SLOT, Action.CANCEL],
	}


func _oath_answer() -> Dictionary:
	var tag: String = _oath_tag()
	var answer: Dictionary = {"text": OATH_ANSWER}
	if not tag.is_empty():
		answer["tag"] = tag
	return answer


## Тег последствия из таблицы Δ T-27: «[Орден+10]», а не хардкод.
func _oath_tag() -> String:
	var delta: int = FactionManager.get_action_delta(OATH_FACTION, OATH_EVENT)
	if delta == 0:
		return ""
	var faction_name: String = FactionManager.get_faction_name(OATH_FACTION)
	if faction_name.is_empty():
		faction_name = SPEAKER_FACTION_FALLBACK
	# Тег макета короткий: «[Орден+10]», а не «[Орден Пепла+10]».
	var space: int = faction_name.find(" ")
	if space > 0:
		faction_name = faction_name.substr(0, space)
	var sign_text: String = "+" if delta > 0 else ""
	return "[%s%s%d]" % [faction_name, sign_text, delta]


func _speaker_faction() -> String:
	var faction_name: String = FactionManager.get_faction_name(SPEAKER_FACTION_ID)
	return SPEAKER_FACTION_FALLBACK if faction_name.is_empty() else faction_name


func _on_answer_selected(index: int) -> void:
	if index < 0 or index >= _answer_actions.size():
		return
	match _answer_actions[index]:
		Action.SAVE:
			_request_save()
		Action.ABOUT:
			_show_info(ABOUT_TEXT)
		Action.OATH:
			_take_oath()
		Action.LEAVE, Action.CONTINUE:
			close()
		Action.RETRY:
			_retry_save()
		Action.ANOTHER_SLOT:
			_set_state(State.SLOTS)
		Action.CANCEL:
			_set_state(State.TALK)


func _request_save() -> void:
	if not GameState.can_save():
		_show_danger(COMBAT_TOAST)
		_set_state(State.TALK)
		return
	_set_state(State.SLOTS)


func _take_oath() -> void:
	if _oath_taken:
		_show_info(OATH_ALREADY_TEXT)
		return
	_oath_taken = true
	var results: Array[Dictionary] = FactionManager.apply_reputation_event(OATH_EVENT)
	var message: String = "Клятва принята."
	for result: Dictionary in results:
		if StringName(str(result.get("faction_id", ""))) != OATH_FACTION:
			continue
		var delta: int = int(result.get("delta", 0))
		var sign_text: String = "+" if delta > 0 else ""
		message = "Клятва принята · %s %s%d" % [_speaker_faction(), sign_text, delta]
		break
	_show_info(message)


func _handle_back() -> void:
	match _state:
		State.SLOTS, State.ERROR:
			_set_state(State.TALK)
		_:
			close()


func _input(event: InputEvent) -> void:
	if not _showing:
		return
	if _state == State.SLOTS:
		if event.is_action_pressed(&"ui_up", true):
			move_slot_focus(-1)
			_consume_input()
			return
		if event.is_action_pressed(&"ui_down", true):
			move_slot_focus(1)
			_consume_input()
			return
	if event.is_action_pressed(&"ui_cancel"):
		_handle_back()
		_consume_input()


func _consume_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


# ------------------------------------------------------------------------------
# Сохранение (Bonfire T-26 + SaveManager T-25)
# ------------------------------------------------------------------------------

func _on_slot_card_pressed(slot: int) -> void:
	select_slot(slot)


func _on_slot_card_focused(slot: int) -> void:
	_selected_slot = slot


func _save_to_slot(slot: int) -> void:
	_pending_slot = slot
	_selected_slot = slot
	var metadata: Dictionary = _build_save_metadata()
	if _bonfire != null and is_instance_valid(_bonfire):
		_bonfire.save_to_slot(slot, metadata)
	else:
		SaveManager.save_slot(slot, metadata)


func _retry_save() -> void:
	if not GameState.can_save():
		_show_danger(COMBAT_TOAST)
		_set_state(State.TALK)
		return
	_save_to_slot(_pending_slot)


func _build_save_metadata() -> Dictionary:
	var zone_id: StringName = GameState.current_zone_id
	if zone_id == &"" and _bonfire != null and is_instance_valid(_bonfire):
		zone_id = _bonfire.zone_id
	if zone_id == &"":
		return {}
	return {
		"zone_id": String(zone_id),
		"zone_name": zone_display_name(zone_id),
	}


func _on_save_completed(slot: int) -> void:
	if not _showing:
		return
	_selected_slot = slot
	_pending_slot = slot
	_refresh_slot_cards()
	_show_success(slot)
	_set_state(State.SAVED)
	saved.emit(slot)


func _on_save_failed(slot: int, reason: String) -> void:
	if not _showing:
		return
	save_error.emit(slot, reason)
	_pending_slot = slot
	if reason == Bonfire.SAVE_REASON_IN_COMBAT:
		_show_danger(COMBAT_TOAST)
		_set_state(State.TALK)
		return
	_error_corrupted = false
	_show_danger(DISK_ERROR_TOAST)
	_set_state(State.ERROR)


func _on_slot_corrupted(slot: int, _reason: String) -> void:
	if not _showing:
		return
	_pending_slot = slot
	_error_corrupted = true
	_show_danger(CORRUPTED_TOAST)
	_set_state(State.ERROR)


func _on_combat_state_changed(in_combat: bool) -> void:
	if not _showing:
		return
	if _state == State.TALK:
		_set_state(State.TALK)
		if in_combat:
			_show_danger(COMBAT_TOAST)
	elif in_combat and _state == State.SLOTS:
		_show_danger(COMBAT_TOAST)
		_set_state(State.TALK)


# ------------------------------------------------------------------------------
# Слоты
# ------------------------------------------------------------------------------

func _initial_slot() -> int:
	if SaveManager.is_valid_slot(GameState.active_slot):
		return GameState.active_slot
	return 1


func _refresh_slot_cards() -> void:
	for index in _slot_cards.size():
		var card := _slot_cards[index] as _SlotCard
		if card == null:
			continue
		card.apply_view(build_slot_view(SaveManager.get_slot_metadata(index + 1), index + 1))


func _focus_current_slot() -> void:
	if not _showing or _state != State.SLOTS or _slot_cards.is_empty():
		return
	var index: int = clampi(_selected_slot - 1, 0, _slot_cards.size() - 1)
	var card: Button = _slot_cards[index]
	if card != null and card.visible:
		card.grab_focus()


func _release_slot_focus() -> void:
	var owner: Control = _focus_owner()
	if owner == null:
		return
	for card: Button in _slot_cards:
		if owner == card:
			owner.release_focus()
			return


func _release_focus() -> void:
	var owner: Control = _focus_owner()
	if owner != null and _ui_root != null and _ui_root.is_ancestor_of(owner):
		owner.release_focus()


func _focus_owner() -> Control:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	return viewport.gui_get_focus_owner()


## Представление одной карточки слота. Чистая функция — проверяется GUT.
static func build_slot_view(metadata: Dictionary, slot: int) -> Dictionary:
	var exists: bool = bool(metadata.get("exists", false))
	var valid: bool = bool(metadata.get("valid", false))
	if not exists:
		return {
			"slot": slot,
			"occupied": false,
			"empty": true,
			"corrupted": false,
			"title": EMPTY_SLOT_TEXT,
			"details": "",
			"overwrite": false,
			"tooltip": "Слот %d: пусто" % slot,
		}

	if not valid:
		var reason: String = str(metadata.get("reason", ""))
		return {
			"slot": slot,
			"occupied": true,
			"empty": false,
			"corrupted": true,
			"title": DAMAGED_SLOT_TEXT,
			"details": "Перезапись заменит запись",
			"overwrite": true,
			"tooltip": "Слот %d: повреждён (%s)" % [slot, reason],
		}

	var zone_name: String = str(metadata.get("zone_name", ""))
	var zone_id: String = str(metadata.get("zone_id", ""))
	var zone_label: String = zone_name if not zone_name.is_empty() else zone_id
	if zone_label.is_empty():
		zone_label = "Неизвестная зона"
	var details: String = "УР%d · %s" % [
		int(metadata.get("level", 0)),
		format_play_time(float(metadata.get("play_time", 0.0))),
	]
	return {
		"slot": slot,
		"occupied": true,
		"empty": false,
		"corrupted": false,
		"title": zone_label,
		"details": details,
		"overwrite": true,
		"tooltip": "Слот %d: %s, %s" % [slot, zone_label, details],
	}


## Игровое время слота в формате макета: 22320 с → «6ч 12м».
static func format_play_time(seconds: float) -> String:
	var total: int = maxi(int(seconds), 0)
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	return "%dч %02dм" % [hours, minutes]


## Читаемое имя зоны из `data/zones/*.tres` (метаданные сейва/T-23).
static func zone_display_name(zone_id: StringName) -> String:
	if zone_id == &"":
		return ""
	var path: String = "res://data/zones/%s.tres" % String(zone_id)
	if not ResourceLoader.exists(path):
		return ""
	var data: ZoneData = load(path) as ZoneData
	return data.display_name if data != null else ""


func _find_bonfire() -> Bonfire:
	if not is_inside_tree():
		return null
	var first: Bonfire = null
	var key: StringName = GameState.respawn_bonfire
	for node: Node in get_tree().get_nodes_in_group(&"bonfires"):
		var fire := node as Bonfire
		if fire == null:
			continue
		if first == null:
			first = fire
		if key == &"":
			continue
		var fire_key: StringName = fire.bonfire_id
		if fire.zone_id != &"":
			fire_key = StringName("%s/%s" % [fire.zone_id, fire.bonfire_id])
		if fire_key == key:
			return fire
	return first


# ------------------------------------------------------------------------------
# Тосты
# ------------------------------------------------------------------------------

func _apply_accessibility() -> void:
	if _dialog == null:
		return
	_dialog.instant_text = Config.no_flash
	if Config.no_flash and _dialog.is_typing():
		_dialog.reveal_all()


func _show_success(slot: int) -> void:
	_toast.show_message(
		"СОХРАНЕНО · СЛОТ %d" % slot,
		AshenToast.Kind.SUCCESS,
		SUCCESS_TOAST_DURATION
	)


func _show_danger(message: String) -> void:
	_toast.show_message(message, AshenToast.Kind.DANGER, DANGER_TOAST_DURATION)


func _show_info(message: String) -> void:
	_toast.show_message(message, AshenToast.Kind.INFO, DANGER_TOAST_DURATION)


# ------------------------------------------------------------------------------
# Карточка слота (широкая строка макета, не квадрат инвентаря)
# ------------------------------------------------------------------------------

class _SlotCard:
	extends Button

	const OVERWRITE_LABEL: String = "Перезапись"

	var slot_number: int = 1
	var card_title: String = ""
	var card_details: String = ""
	var overwrite: bool = false
	var empty: bool = false
	var corrupted: bool = false

	func _init() -> void:
		UIStyle.make_custom_button(self)
		mouse_entered.connect(_on_mouse_entered)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func apply_view(view: Dictionary) -> void:
		slot_number = int(view.get("slot", slot_number))
		card_title = str(view.get("title", ""))
		card_details = str(view.get("details", ""))
		overwrite = bool(view.get("overwrite", false))
		empty = bool(view.get("empty", false))
		corrupted = bool(view.get("corrupted", false))
		tooltip_text = str(view.get("tooltip", ""))
		queue_redraw()

	func get_view_data() -> Dictionary:
		return {
			"slot": slot_number,
			"title": card_title,
			"details": card_details,
			"empty": empty,
			"corrupted": corrupted,
			"overwrite": overwrite,
			"focused": has_focus(),
		}

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		var focused: bool = has_focus()
		draw_rect(rect, UITokens.VOID)

		if empty:
			UIStyle.draw_dashed_frame(
				self,
				rect,
				UITokens.BORDER_SLOT,
				UITokens.STONE_9
			)
		else:
			var border: Color = UITokens.STONE_9
			if corrupted:
				border = UITokens.BLOOD_3
			if focused:
				border = UITokens.GOLD
			UIStyle.draw_frame(self, rect, UITokens.BORDER_SLOT, border)

		if focused and not empty:
			UIStyle.draw_frame(
				self,
				Rect2(Vector2(3, 3), size - Vector2(6, 6)),
				UITokens.BORDER_INNER,
				UITokens.GOLD_9
			)

		var number_color: Color = UITokens.BONE
		if empty:
			number_color = UITokens.STONE_5
		elif corrupted:
			number_color = UITokens.BLOOD_5
		elif focused:
			number_color = UITokens.GOLD_3
		var number_baseline: float = 3.0 + UIStyle.baseline_y(UITokens.FONT_H2)
		UIStyle.draw_text(
			self,
			Vector2(4, number_baseline),
			str(slot_number),
			number_color,
			UITokens.FONT_H2
		)

		var text_x: float = 4.0 + float(UITokens.FONT_H2) + 4.0
		var overwrite_width: float = 0.0
		if overwrite:
			overwrite_width = UIStyle.text_width(OVERWRITE_LABEL, UITokens.FONT_BODY)
		var title_width: float = size.x - text_x - 4.0
		if overwrite:
			title_width -= overwrite_width + 8.0

		var title_color: Color = UITokens.BONE
		if empty:
			title_color = UITokens.STONE_5
		elif corrupted:
			title_color = UITokens.BLOOD_5

		var baseline_first: float = 3.0 + UIStyle.baseline_y(UITokens.FONT_BODY)
		var baseline_second: float = (
			3.0 + float(UITokens.LINE_BODY) + UIStyle.baseline_y(UITokens.FONT_BODY)
		)
		UIStyle.draw_text(
			self,
			Vector2(text_x, baseline_first),
			_fit_text(card_title, title_width, UITokens.FONT_BODY),
			title_color,
			UITokens.FONT_BODY
		)
		UIStyle.draw_text(
			self,
			Vector2(text_x, baseline_second),
			_fit_text(
				card_details,
				size.x - text_x - 4.0,
				UITokens.FONT_BODY
			),
			UITokens.STONE_5,
			UITokens.FONT_BODY
		)

		if overwrite:
			UIStyle.draw_text(
				self,
				Vector2(4, baseline_first),
				OVERWRITE_LABEL,
				UITokens.GOLD_3,
				UITokens.FONT_BODY,
				size.x - 8.0,
				HORIZONTAL_ALIGNMENT_RIGHT
			)

	func _fit_text(text: String, max_width: float, font_size: int) -> String:
		if max_width <= 0.0:
			return ""
		if UIStyle.text_width(text, font_size) <= max_width:
			return text
		var trimmed: String = text
		while trimmed.length() > 0:
			if UIStyle.text_width(trimmed + "..", font_size) <= max_width:
				break
			trimmed = trimmed.substr(0, trimmed.length() - 1)
		return trimmed + ".."

	func _on_mouse_entered() -> void:
		if is_inside_tree():
			grab_focus()
