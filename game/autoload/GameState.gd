extends Node
## GameState — состояние забега: HP, выносливость, инвентарь, способности, репутация,
## прогресс (PLAN §2.2). T-04 добавляет выносливость (перекат тратит E_roll);
## остальные поля наполняются задачами T-06/T-10/T-25/T-27/T-29.
## Уведомления — через EventBus, персистентность — через SaveManager (T-25).

const BALANCE_PATH: String = "res://data/balance/balancing.tres"

var balance: BalancingParams
var stamina_max: float = 0.0
var stamina: float = 0.0


func _ready() -> void:
	balance = load(BALANCE_PATH) as BalancingParams
	if balance != null:
		stamina_max = balance.stamina_max
	stamina = stamina_max


## Spend `amount` stamina. Returns false (and spends nothing) when it is not enough.
func try_spend_stamina(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if stamina < amount:
		return false
	stamina -= amount
	EventBus.stamina_changed.emit(stamina, stamina_max)
	return true


## Restore stamina, clamped to the maximum.
func restore_stamina(amount: float) -> void:
	stamina = minf(stamina + maxf(amount, 0.0), stamina_max)
	EventBus.stamina_changed.emit(stamina, stamina_max)


## Restore full stamina (respawn / start of a run / tests).
func reset_stamina() -> void:
	stamina = stamina_max
	EventBus.stamina_changed.emit(stamina, stamina_max)
