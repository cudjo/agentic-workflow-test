class_name LoadingScreen
extends CanvasLayer
## LoadingScreen — экран перехода между зонами (T-17, DESIGN §5/§6.6).
##
## CanvasLayer 40 поверх HUD/UI/Toasts/Overlay: чёрный фон, название зоны
## (h2, золото), эпиграф зоны и спиннер из 4 шагов. Пока экран виден,
## ввод игнорируется (EC-12): физика игрока выключена SceneRouter'ом, а
## клавиатурные/геймпадные события поглощаются здесь.
##
## Сцена не решает, когда переключать зону, — это SceneRouter: он вызывает
## `show_loading()`/`hide_loading()` и держит экран не меньше `MIN_LOADING_TIME`.

## Период одного шага спиннера: 4 шага за FADE_TIME (DESIGN §4.5).
const SPINNER_STEP_TIME: float = UITokens.FADE_TIME / 4.0
const SPINNER_STEPS: int = 4

@onready var _background: ColorRect = %Background
@onready var _title: Label = %Title
@onready var _epigraph: Label = %Epigraph
@onready var _spinner: HBoxContainer = %Spinner

## Шаги спиннера (ColorRect), подсвечивается ровно один.
var _steps: Array[ColorRect] = []
## Текущий шаг спиннера, 0…3 (публичен для тестов/QA).
var spinner_step: int = 0
var _spinner_time: float = 0.0
var _shown: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_nodes()
	if not _shown:
		visible = false
		set_process(false)


func _process(delta: float) -> void:
	_spinner_time += delta
	var step: int = int(_spinner_time / SPINNER_STEP_TIME) % SPINNER_STEPS
	if step != spinner_step:
		spinner_step = step
		_paint_spinner()


## Показывает экран для зоны; `zone_display_name` — название из ZoneData,
## `epigraph_text` — атмосферная строка зоны (может быть пустой).
func show_loading(zone_display_name: String, epigraph_text: String = "") -> void:
	# Экран может быть показан в том же кадре, что и добавлен в дерево, — до
	# `_ready()`. Поэтому узлы разрешаются лениво, а не только через onready.
	_ensure_nodes()
	_title.text = zone_display_name.to_upper()
	_epigraph.text = epigraph_text
	_epigraph.visible = not epigraph_text.is_empty()
	spinner_step = 0
	_spinner_time = 0.0
	_paint_spinner()
	_shown = true
	visible = true
	set_process(true)


## Скрывает экран и останавливает спиннер; повторный вызов безопасен.
func hide_loading() -> void:
	_shown = false
	visible = false
	set_process(false)
	_spinner_time = 0.0


func is_shown() -> bool:
	return _shown


## Ввод во время загрузки не доходит до игровых систем (EC-12).
func _input(_event: InputEvent) -> void:
	if not _shown:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _ensure_nodes() -> void:
	if _title == null:
		_title = %Title
	if _epigraph == null:
		_epigraph = %Epigraph
	if _background == null:
		_background = %Background
	if _spinner == null:
		_spinner = %Spinner
	_collect_steps()
	_apply_tokens()


func _collect_steps() -> void:
	_steps.clear()
	if _spinner == null:
		return
	for child: Node in _spinner.get_children():
		var rect := child as ColorRect
		if rect != null:
			_steps.append(rect)


func _apply_tokens() -> void:
	_background.color = UITokens.VOID
	_title.add_theme_font_size_override(&"font_size", UITokens.FONT_H2)
	_title.add_theme_color_override(&"font_color", UITokens.GOLD_3)
	_epigraph.add_theme_font_size_override(&"font_size", UITokens.FONT_BODY)
	_epigraph.add_theme_color_override(&"font_color", UITokens.STONE_5)
	_paint_spinner()


func _paint_spinner() -> void:
	for index: int in _steps.size():
		_steps[index].color = UITokens.GOLD if index == spinner_step else UITokens.GOLD_9
