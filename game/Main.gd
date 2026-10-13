extends Node
## Main — корневая сцена: текущая зона (WorldRoot) + слои UI (PLAN §2.3, DESIGN §4.4).
## Переход зоны (T-17) заменяет только WorldRoot; слои постоянны:
##   HUD=10, UI=20, Toasts=30, Overlay=40 (затемнения/смерть/загрузка).
