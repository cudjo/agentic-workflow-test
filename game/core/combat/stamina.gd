class_name Stamina
extends RefCounted
## Stamina — логика выносливости игрока (T-10, AC-03.3).
##
## Значения (максимум, задержка/скорость восстановления) приходят из
## `data/balance/balancing.tres`; `GameState` владеет экземпляром и
## транслирует сигналы в `EventBus`. Флаг `exhausted` — «НЕТ СИЛ» для HUD.
##
## Восстановление начинается только в покое (`update(delta, resting)`)
## и не раньше, чем через `regen_delay` секунд после последней траты.

signal changed(current: float, maximum: float)
signal exhausted_changed(exhausted: bool)

var maximum: float = 0.0
var current: float = 0.0
var regen_delay: float = 0.0
var regen_rate: float = 0.0
var exhausted: bool = false

var _time_since_spend: float = 0.0


func setup(maximum_value: float, delay: float, rate: float) -> void:
	maximum = maxf(maximum_value, 0.0)
	regen_delay = maxf(delay, 0.0)
	regen_rate = maxf(rate, 0.0)
	reset()


## Тратит `amount`. Возвращает false и ничего не списывает, если не хватает.
func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if current < amount:
		return false
	current = maxf(current - amount, 0.0)
	_time_since_spend = 0.0
	_refresh_exhausted()
	changed.emit(current, maximum)
	return true


func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	var new_value: float = minf(current + amount, maximum)
	if is_equal_approx(new_value, current):
		return
	current = new_value
	_refresh_exhausted()
	changed.emit(current, maximum)


## Прямая установка (загрузка сейва, тесты) с пересчётом флага и сигналом.
func set_current(value: float) -> void:
	current = clampf(value, 0.0, maximum)
	_time_since_spend = 0.0
	_refresh_exhausted()
	changed.emit(current, maximum)


## Прямая установка максимума (бонус характеристики «выносливость», T-29).
## `grant_delta` — прибавка к текущему значению на тот же размер (повышение
## характеристики не «съедает» текущую выносливость); иначе текущее
## зажимается под новый максимум (загрузка сейва).
func set_maximum(value: float, grant_delta: bool = false) -> void:
	var previous: float = maximum
	maximum = maxf(value, 0.0)
	if grant_delta and maximum > previous:
		current = minf(current + (maximum - previous), maximum)
	else:
		current = minf(current, maximum)
	_refresh_exhausted()
	changed.emit(current, maximum)


func reset() -> void:
	current = maximum
	_time_since_spend = 0.0
	_refresh_exhausted()
	changed.emit(current, maximum)


func can_spend(amount: float) -> bool:
	return amount <= 0.0 or current >= amount


func is_exhausted() -> bool:
	return exhausted


## Тик восстановления. `resting` — игрок не в атаке/блоке/перекате/рывке.
## Регенерируется только время, прошедшее после `regen_delay`.
func update(delta: float, resting: bool) -> void:
	if delta <= 0.0:
		return
	_time_since_spend += delta
	if not resting or _time_since_spend < regen_delay or current >= maximum:
		return
	var regen_time: float = minf(delta, _time_since_spend - regen_delay)
	if regen_time <= 0.0:
		return
	current = minf(current + regen_rate * regen_time, maximum)
	_refresh_exhausted()
	changed.emit(current, maximum)


func _refresh_exhausted() -> void:
	var is_now_exhausted: bool = current <= 0.0
	if is_now_exhausted == exhausted:
		return
	exhausted = is_now_exhausted
	exhausted_changed.emit(exhausted)
