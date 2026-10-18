class_name EndingSequence
extends CanvasLayer
## EndingSequence — финальная последовательность (T-32).
##
## Слушает `EndingExit.ending_requested(faction_id, zone_id, ending_id)`,
## затемняет мир, показывает экран концовки по фракции и после подтверждения
## переходит к титрам. Пока `FactionManager` — заглушка T-27, фракция пустая
## и каталог отдаёт нейтральную концовку — без вылетов и блокировки.
##
## Последовательность не грузит сцены и не трогает HUD: она живёт в финальной
## зоне, отключает физику игрока и после титров остаётся в состоянии FINISHED
## (решение о возврате в меню — за будущим T-17/меню).

signal sequence_started(faction_id: StringName, ending_id: StringName)
signal ending_started(ending_id: StringName)
signal credits_started
signal credits_finished

enum State { IDLE, FADE, ENDING, CREDITS, FINISHED }

const PLAYER_GROUP: StringName = &"player"

## Путь к хуку концовки; по умолчанию — сосед `EndingExit` в сцене финала.
@export var ending_hook_path: NodePath = ^"../EndingExit"
## Затемнение мира перед текстом; ступенчатое, как остальные переходы.
@export var fade_duration: float = UITokens.FADE_TIME

var _state: State = State.IDLE
var _pending: EndingText
var _faction_id: StringName = &""

var _fade: ColorRect
var _ending_screen: EndingScreen
var _credits_screen: CreditsScreen
var _fade_elapsed: float = 0.0


func _ready() -> void:
	layer = maxi(layer, 20)
	_build()
	_connect_hook()


# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

## Запускает концовку для фракции (пустая — читается из FactionManager).
func play_ending(faction_id: StringName = &"", faction_name: String = "") -> bool:
	if _state != State.IDLE:
		return false
	_ensure_built()

	if faction_id == &"":
		var manager := get_node_or_null("/root/FactionManager")
		faction_id = EndingCatalog.read_selected_faction(manager)
		if faction_name.is_empty() and manager != null:
			faction_name = EndingCatalog.read_faction_name(manager, faction_id)

	_faction_id = faction_id
	_pending = EndingCatalog.resolve(faction_id, faction_name)
	_disable_player()
	_state = State.FADE
	_fade_elapsed = 0.0
	_fade.color = Color(UITokens.VOID, 0.0)
	_fade.visible = true
	sequence_started.emit(_faction_id, _pending.id)

	if fade_duration <= 0.0:
		_show_ending_now()
	return true


## Подтверждение на экране концовки (ui_accept/кнопка) — переход к титрам.
func advance() -> void:
	match _state:
		State.ENDING:
			_ending_screen.hide_ending()
			_state = State.CREDITS
			_credits_screen.show_credits()
			credits_started.emit()
		State.CREDITS:
			_credits_screen.finish()
		_:
			pass


func get_state() -> State:
	return _state


func get_state_name() -> StringName:
	match _state:
		State.FADE:
			return &"fade"
		State.ENDING:
			return &"ending"
		State.CREDITS:
			return &"credits"
		State.FINISHED:
			return &"finished"
		_:
			return &"idle"


func get_faction_id() -> StringName:
	return _faction_id


func get_ending_id() -> StringName:
	return _pending.id if _pending != null else &""


func is_ending_visible() -> bool:
	return _state == State.ENDING and _ending_screen.visible


func is_credits_visible() -> bool:
	return _state == State.CREDITS and _credits_screen.visible


func is_finished() -> bool:
	return _state == State.FINISHED


func get_ending_screen() -> EndingScreen:
	_ensure_built()
	return _ending_screen


func get_credits_screen() -> CreditsScreen:
	_ensure_built()
	return _credits_screen


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _build() -> void:
	if _fade != null:
		return

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(UITokens.VOID, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_ending_screen = EndingScreen.new()
	_ending_screen.advance_requested.connect(advance)
	add_child(_ending_screen)

	_credits_screen = CreditsScreen.new()
	_credits_screen.credits_finished.connect(_on_credits_finished)
	add_child(_credits_screen)


func _ensure_built() -> void:
	if _fade == null:
		_build()


func _connect_hook() -> void:
	var hook := get_node_or_null(ending_hook_path)
	if hook == null or not hook.has_signal(&"ending_requested"):
		return
	if not hook.is_connected(&"ending_requested", _on_ending_requested):
		hook.connect(&"ending_requested", _on_ending_requested)


func _on_ending_requested(
	faction_id: StringName,
	_zone_id: StringName,
	_ending_id: StringName
) -> void:
	play_ending(faction_id)


func _process(delta: float) -> void:
	if _state != State.FADE:
		return
	if fade_duration <= 0.0:
		_show_ending_now()
		return
	_fade_elapsed += delta
	var progress: float = clampf(_fade_elapsed / fade_duration, 0.0, 1.0)
	# Ступенчатое затемнение (DESIGN §4.5: без плавных твинов).
	var steps: int = maxi(UITokens.FADE_STEPS, 1)
	_fade.color = Color(
		UITokens.VOID,
		ceilf(progress * float(steps)) / float(steps)
	)
	if progress >= 1.0:
		_show_ending_now()


func _show_ending_now() -> void:
	if _state != State.FADE or _pending == null:
		return
	_fade.visible = false
	_state = State.ENDING
	_ending_screen.show_ending(_pending, _faction_id)
	ending_started.emit(_pending.id)


func _on_credits_finished() -> void:
	if _state == State.FINISHED:
		return
	_state = State.FINISHED
	credits_finished.emit()


func _disable_player() -> void:
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group(PLAYER_GROUP)
	if player == null:
		return
	player.set_physics_process(false)
	player.set_process_input(false)
	GameState.set_in_combat(false)
