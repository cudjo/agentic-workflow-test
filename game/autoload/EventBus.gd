extends Node
## EventBus — глобальные типизированные сигналы между системами (PLAN §2.2).
## Автолоад не рисует UI и не хранит состояние забега — только сигналы.
##
## T-04: события игрока, которые потребляют HUD (T-19), анимации (T-05)
## и смерть/corpse run (T-26).

## Состояние FSM игрока изменилось (idle/run/jump/...).
signal player_state_changed(state_name: StringName)
## Выносливость игрока изменилась (HUD, AC-03.3).
signal stamina_changed(current: float, maximum: float)
## HP игрока достиг HP = 0; смерть обрабатывается T-26.
signal player_died
