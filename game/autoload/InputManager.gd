extends Node
## InputManager — InputMap-действия, ремап, буфер ввода, активное устройство (PLAN §2.2).
## Заглушка каркаса (T-01). Действия заданы в project.godot [input]:
##   move_left/move_right/move_up/move_down, jump, attack, block, roll, dash, interact, ui_*.
## Реализация API (is_pressed/just_pressed, буфер 150 мс, coyote, device_changed,
## ремап в user://settings.cfg) — задача T-03. Клавиши в логике не хардкодить.
