extends Node
## Main — корневая сцена: текущая зона (WorldRoot) + слои UI (PLAN §2.3, DESIGN §4.4).
## Переход зоны (T-17) заменяет только WorldRoot; слои постоянны:
##   HUD=10, UI=20, Toasts=30, Overlay=40 (затемнения/смерть/загрузка).
##
## T-18: тема UI назначается окну в рантайме (а не через gui/theme/custom),
## чтобы `--headless --import` на чистом клоне не пытался загрузить шрифты до
## их импорта. Все Control под Main наследуют тему от Window.

const THEME_PATH := "res://ui/theme/main_theme.tres"


func _ready() -> void:
	var window := get_window()
	if window == null:
		return
	var ui_theme := load(THEME_PATH) as Theme
	if ui_theme != null:
		window.theme = ui_theme
