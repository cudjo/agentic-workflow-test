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

## Игрок получил новую способность (T-06, AC-02.1). Потребители: Player
## (ставит runtime-флаг через AbilityBase.activate), ability gates (T-09),
## HUD (T-19, слот способности больше не «закрыт»).
signal ability_acquired(ability_id: StringName)

## Зона загружена и ZoneData применён (T-13). Потребители: баннер зоны (T-14),
## экран загрузки/переходы (T-17), HUD (T-19).
signal zone_entered(zone_id: StringName, display_name: String)

## Слот записан успешно (T-25). Потребитель: подтверждение сохранения у костра /
## меню слотов (T-22/T-23), AC-05.1 (подтверждение ≤ 1 с).
signal save_completed(slot: int)
## Слот не записан (ошибка диска/некорректный номер, EC-14). UI показывает
## сообщение; старый слот при этом цел.
signal save_failed(slot: int, reason: String)
## Слот повреждён/обрезан/несовместим по schema_version и НЕ загружен (EC-07).
## UI предлагает выбрать другой слот; причина — `SaveManager.LOAD_*`.
signal slot_corrupted(slot: int, reason: String)

## Враг погиб окончательно (T-12). Потребители: EnemySpawner (encounter clear),
## прогрессия/опыт (T-29), звук/субтитры (T-34). Возрождение нежити событие
## не отправляет — только окончательная смерть.
signal enemy_died(enemy_id: StringName, at_position: Vector2)
