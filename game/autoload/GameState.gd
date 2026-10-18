extends Node
## GameState — состояние забега: HP, выносливость, инвентарь, способности,
## текущее оружие, репутация, прогресс (PLAN §2.2).
##
## T-04 добавил выносливость; T-10 вынес её логику в `core/combat/stamina.gd`
## (трата/восстановление/флаг «НЕТ СИЛ», AC-03.3) и добавил текущее оружие
## как ссылку на данные `data/weapons/*.tres`.
## Уведомления — через EventBus (`stamina_changed`); флаг «НЕТ СИЛ» HUD читает
## через `is_stamina_exhausted()` (AC-03.3), не заводя отдельного сигнала.
##
## T-06 добавил набор полученных способностей `abilities` (PLAN §3.3):
## типизированный список id — источник истины для FSM игрока, ability gates
## (T-09), HUD (T-19) и сейвов (T-25).

const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const DEFAULT_WEAPON_PATH: String = "res://data/weapons/one_handed_sword.tres"

var balance: BalancingParams
var weapon: WeaponData
var stamina_state: Stamina

## Полученные способности (id из AbilityRegistry), в порядке получения.
## Типизированный набор; дубликаты невозможны (см. `add_ability`).
var abilities: Array[StringName] = []

## Побеждённые боссы (id, T-30). Источник истины для «босс остаётся мёртвым»
## (EC-09) и персистентности через SaveManager.
var bosses_defeated: Array[StringName] = []
## Отложенные награды: boss_id -> {zone_id, reward_id, gold}. Награда ждёт
## следующего входа в зону, если игрок погиб до её получения (EC-09).
var boss_rewards_pending: Dictionary = {}
## Валюта игрока; награды боссов добавляются сюда.
var currency: int = 0

## Текущий максимум выносливости (из balancing.tres).
var stamina_max: float:
	get:
		return stamina_state.maximum if stamina_state != null else 0.0

## Текущая выносливость; setter нужен загрузке сейва/T-04-тестам.
var stamina: float:
	get:
		return stamina_state.current if stamina_state != null else 0.0
	set(value):
		if stamina_state != null:
			stamina_state.set_current(value)


func _ready() -> void:
	balance = load(BALANCE_PATH) as BalancingParams
	if balance == null:
		push_error("GameState: balancing resource is missing at %s" % BALANCE_PATH)
	else:
		stamina_state = Stamina.new()
		stamina_state.changed.connect(_on_stamina_changed)
		stamina_state.setup(
			balance.stamina_max,
			balance.stamina_regen_delay,
			balance.stamina_regen_rate
		)
	weapon = load(DEFAULT_WEAPON_PATH) as WeaponData


## Spend `amount` stamina. Returns false (and spends nothing) when it is not enough.
func try_spend_stamina(amount: float) -> bool:
	if stamina_state == null:
		return false
	return stamina_state.spend(amount)


## Restore stamina, clamped to the maximum.
func restore_stamina(amount: float) -> void:
	if stamina_state != null:
		stamina_state.restore(amount)


## Restore full stamina (respawn / start of a run / tests).
func reset_stamina() -> void:
	if stamina_state != null:
		stamina_state.reset()


## Per-physics-tick regeneration; `resting` = no attack/block/roll/dash now.
func update_stamina(delta: float, resting: bool) -> void:
	if stamina_state != null:
		stamina_state.update(delta, resting)


## HUD flag: stamina is empty, attacks are refused (AC-03.3).
func is_stamina_exhausted() -> bool:
	return stamina_state != null and stamina_state.is_exhausted()


# ------------------------------------------------------------------------------
# Abilities (T-06)
# ------------------------------------------------------------------------------

## Получена ли способность в этом забеге (AC-02.1, AC-04.3).
func has_ability(ability_id: StringName) -> bool:
	return abilities.has(ability_id)


## Добавляет способность один раз; true — только при первом получении.
## Эмитит `EventBus.ability_acquired`, чтобы живые системы (FSM игрока,
## ability gates, HUD) разблокировали поведение сразу.
func add_ability(ability_id: StringName) -> bool:
	if ability_id == &"":
		push_warning("GameState.add_ability: empty ability id")
		return false
	if abilities.has(ability_id):
		return false
	abilities.append(ability_id)
	EventBus.ability_acquired.emit(ability_id)
	return true


## Копия набора для UI/gates/сейвов: мутация результата не меняет забег.
func get_abilities() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(abilities)
	return copy


## Очищает набор (новая игра, загрузка сейва перед повторной выдачей).
## Флаги на живом игроке снимаются через `AbilityBase.deactivate()`.
func clear_abilities() -> void:
	abilities.clear()


# ------------------------------------------------------------------------------
# Boss progress and rewards (T-30, EC-09)
# ------------------------------------------------------------------------------

## Побеждён ли босс в этом забеге/сохранении (EC-09).
func is_boss_defeated(boss_id: StringName) -> bool:
	return bosses_defeated.has(boss_id)


## Фиксирует победу один раз. Возвращает true только при первом вызове.
func mark_boss_defeated(boss_id: StringName) -> bool:
	if boss_id == &"" or bosses_defeated.has(boss_id):
		return false
	bosses_defeated.append(boss_id)
	return true


func get_bosses_defeated() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(bosses_defeated)
	return copy


## Ставит награду в очередь. Идемпотентно: повторная запись того же босса
## не дублирует награду (важно при повторном входе в зону, EC-09).
func queue_boss_reward(
	boss_id: StringName,
	zone_id: StringName,
	reward_id: StringName,
	gold: int
) -> void:
	if boss_id == &"" or boss_rewards_pending.has(boss_id):
		return
	boss_rewards_pending[boss_id] = {
		"zone_id": String(zone_id),
		"reward_id": String(reward_id),
		"gold": maxi(gold, 0),
	}


## Выдаёт отложенную награду: добавляет золото и эмитит
## `EventBus.boss_reward_granted`. Возвращает false, если награды нет.
func claim_boss_reward(boss_id: StringName) -> bool:
	if not boss_rewards_pending.has(boss_id):
		return false
	var entry: Variant = boss_rewards_pending[boss_id]
	boss_rewards_pending.erase(boss_id)
	var data: Dictionary = entry if entry is Dictionary else {}
	var gold: int = maxi(int(data.get("gold", 0)), 0)
	var reward_id: StringName = StringName(str(data.get("reward_id", "")))
	currency += gold
	EventBus.boss_reward_granted.emit(boss_id, reward_id, gold)
	return true


## Выдаёт все награды, ожидающие указанной зоны (вход в зону, EC-09).
## Возвращает число выданных наград.
func claim_pending_boss_rewards(zone_id: StringName) -> int:
	var pending_ids: Array[StringName] = []
	for key: Variant in boss_rewards_pending.keys():
		var entry: Variant = boss_rewards_pending[key]
		var data: Dictionary = entry if entry is Dictionary else {}
		if StringName(str(data.get("zone_id", ""))) == zone_id:
			pending_ids.append(StringName(str(key)))
	var claimed: int = 0
	for boss_id: StringName in pending_ids:
		if claim_boss_reward(boss_id):
			claimed += 1
	return claimed


## Копия очереди наград (тесты/сейв): мутация результата не меняет забег.
func get_pending_boss_rewards() -> Dictionary:
	return boss_rewards_pending.duplicate(true)


## Очищает прогресс боссов (новая игра/тесты).
func reset_boss_progress() -> void:
	bosses_defeated.clear()
	boss_rewards_pending.clear()
	currency = 0


## Восстанавливает прогресс из сейва без побочных сигналов (T-25/T-30).
func restore_boss_progress(
	defeated: Array,
	pending: Dictionary,
	currency_value: int
) -> void:
	bosses_defeated.clear()
	for value: Variant in defeated:
		var boss_id: StringName = StringName(str(value))
		if boss_id != &"" and not bosses_defeated.has(boss_id):
			bosses_defeated.append(boss_id)

	boss_rewards_pending.clear()
	for key: Variant in pending.keys():
		var entry: Variant = pending[key]
		if not entry is Dictionary:
			continue
		boss_rewards_pending[StringName(str(key))] = (entry as Dictionary).duplicate(true)

	currency = maxi(currency_value, 0)


func set_weapon(new_weapon: WeaponData) -> void:
	weapon = new_weapon


func _on_stamina_changed(current: float, maximum: float) -> void:
	EventBus.stamina_changed.emit(current, maximum)
