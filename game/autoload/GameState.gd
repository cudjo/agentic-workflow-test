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


func set_weapon(new_weapon: WeaponData) -> void:
	weapon = new_weapon


func _on_stamina_changed(current: float, maximum: float) -> void:
	EventBus.stamina_changed.emit(current, maximum)
