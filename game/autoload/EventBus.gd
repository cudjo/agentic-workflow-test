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
## Текущее HP игрока изменилось (T-26). Потребитель: HUD (T-19).
signal player_health_changed(current: float, maximum: float)
## Игрок возрождён у костра после смерти (T-26, AC-05.2). Потребители:
## экран смерти (T-22), камера/загрузка (T-17).
signal player_respawned(zone_id: StringName, position: Vector2)
## Бюджет смерти `t_death` истёк: экран смерти может открываться (T-22).
## `info` — снимок метки гибели (`GameState.get_corpse_info()` + `previous_lost`).
signal death_screen_requested(info: Dictionary)
## Инвентарь/валюта выложены в corpse-метку на месте гибели (T-26, AC-05.2).
signal corpse_dropped(zone_id: StringName, position: Vector2, items: Array, currency: int)
## Предыдущая corpse-метка потеряна навсегда: игрок умер повторно до подбора
## (T-26, EC-05). Потребители: экран смерти/карта (T-22/T-33).
signal corpse_lost(zone_id: StringName, position: Vector2)
## Corpse-метка подобрана по контакту; инвентарь/валюта вернулись игроку.
signal corpse_collected(items: Array, currency: int)
## Костёр активирован как точка возрождения (T-26). Потребители: HUD/тост,
## карта (T-33).
signal checkpoint_activated(zone_id: StringName, bonfire_id: StringName)
## Флаг боя изменился (T-26, EC-06): сохранение у костра запрещено.
signal combat_state_changed(in_combat: bool)
## Слот успешно загружен и применён к GameState (T-25/T-26, EC-04).
## Потребитель: DeathHandler — разрешает отложенную смерть из сейва.
signal save_loaded(slot: int)

## Игрок получил новую способность (T-06, AC-02.1). Потребители: Player
## (ставит runtime-флаг через AbilityBase.activate), ability gates (T-09),
## HUD (T-19, слот способности больше не «закрыт»).
signal ability_acquired(ability_id: StringName)

## Кулдаун способности изменился (T-07 → HUD T-19, AC-02.2).
## `remaining`/`duration` — секунды; `duration = 0` или `remaining = 0` —
## способность снова готова, полоса кулдауна скрыта.
signal ability_cooldown_changed(ability_id: StringName, remaining: float, duration: float)
## Игрок вошёл/вышел из зоны ability gate (T-09 → HUD T-19, AC-02.4).
## `required = true` — показать подсказку «Нужно: …», false — скрыть.
signal ability_hint_changed(ability_id: StringName, required: bool)

## Репутация с фракцией изменилась (T-27, AC-06.1). Потребители: UI фракций
## и журнал (T-24), диалоги NPC (T-28), HUD-тосты.
signal faction_reputation_changed(faction_id: StringName, value: int)
## Доступ к территории/торговцу фракции изменился при пересечении порога
## (T-27, AC-06.2). `granted` — доступ открыт/закрыт.
signal faction_access_changed(faction_id: StringName, granted: bool)
## Квест/действие изменило репутацию (T-27, AC-06.1). `reaction` — отношение
## NPC (`hostile`/`wary`/`neutral`/`friendly`/`trusted`) для диалога T-28.
signal faction_quest_completed(
	quest_id: StringName,
	faction_id: StringName,
	delta: int,
	reaction: StringName
)
## Игрок выбрал фракцию (T-27, US-06). `faction_id` — стабильный id для
## концовки T-32; `display_name` — имя для UI.
signal faction_chosen(faction_id: StringName, display_name: String)

## Зона загружена и ZoneData применён (T-13). Потребители: баннер зоны (T-14),
## экран загрузки/переходы (T-17), HUD (T-19).
signal zone_entered(zone_id: StringName, display_name: String)
## Переход завершён: новая зона активна, игрок стоит на точке входа, экран
## загрузки скрыт (T-17, AC-04.1). Потребитель — AudioManager (T-34): запускает
## кроссфейд музыки зоны ≤ 1 с (AC-07.2). Эмитится после `zone_entered`.
signal zone_loaded(zone_id: StringName, display_name: String)

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

## Бой с боссом начался (T-30). HUD (T-19) строит панель босса: имя, HP и
## метки фаз (`phase_thresholds` — пороги 66%/33% из данных босса).
signal boss_fight_started(
	boss_id: StringName,
	display_name: String,
	max_hp: float,
	phase_thresholds: PackedFloat32Array
)
## HP босса изменился (T-30). Потребитель: панель босса HUD (T-19).
signal boss_health_changed(boss_id: StringName, current: float, maximum: float)
## Босс перешёл в новую фазу (T-30, AC-03.4). `phase_title` — «ФАЗА II» и т.п.
## для уведомления HUD; `phase_index` — 0-based индекс новой фазы.
signal boss_phase_changed(boss_id: StringName, phase_index: int, phase_title: String)
## Босс побеждён (T-30, EC-09). Флаг и награда уже учтены в GameState.
signal boss_defeated(boss_id: StringName, zone_id: StringName, at_position: Vector2)
## Награда за босса выдана игроку (T-30, EC-09). Потребители: тост/журнал,
## прогрессия (T-29).
signal boss_reward_granted(boss_id: StringName, reward_id: StringName, gold: int)
