class_name ToastHost
extends Control
## ToastHost — приёмник «субтитров звуков» (T-34, DESIGN §9.4).
##
## Живёт на CanvasLayer Toasts (30) в Main.tscn. AudioManager не рисует UI:
## он лишь отдаёт `subtitle_requested(text, danger)`, а хост показывает
## AshenToast (info/danger) в нижней безопасной зоне. Так ключевые звуковые
## события (босс рядом, удар, смена фазы) доступны без слуха.

## Сколько субтитр висит на экране, с.
const SUBTITLE_DURATION: float = 1.6
## Высота строки субтитров (текст 8 px + паддинг панели).
const ROW_HEIGHT: float = 24.0

var _row: HBoxContainer
var _toast: AshenToast


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_row = HBoxContainer.new()
	_row.name = "SubtitleRow"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_row.offset_top = -(ROW_HEIGHT + UITokens.SAFE_MARGIN)
	_row.offset_bottom = -UITokens.SAFE_MARGIN
	add_child(_row)

	_toast = AshenToast.new()
	_toast.name = "SubtitleToast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_toast)

	if AudioManager.has_signal(&"subtitle_requested"):
		if not AudioManager.subtitle_requested.is_connected(show_subtitle):
			AudioManager.subtitle_requested.connect(show_subtitle)


## Показать субтитр. `danger` — значимое/опасное событие (смерть, фаза).
func show_subtitle(text: String, danger: bool = false) -> void:
	if text.is_empty():
		return
	if _toast == null:
		return
	var kind: AshenToast.Kind = AshenToast.Kind.DANGER if danger else AshenToast.Kind.INFO
	_toast.show_message(text, kind, SUBTITLE_DURATION)


func get_toast() -> AshenToast:
	return _toast


func get_last_message() -> String:
	return "" if _toast == null else _toast.get_message()


func is_showing() -> bool:
	return _toast != null and _toast.visible
