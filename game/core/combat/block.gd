class_name Block
extends RefCounted
## Block — логика блока и парирования игрока (T-11, AC-03.2/AC-03.3).
##
## Контракт:
##   * блок действует только в передней дуге (`arc_degrees`, по умолчанию 120°);
##   * первые `T_parry` секунд после входа в блок — окно парирования: урон
##     полностью гасится, парирование расходуется (одно на нажатие) и
##     открывает контратаку (`Player.on_parry_success()`);
##   * после окна — обычный блок: урон снижается на `P_block` процентов;
##   * значения приходят из `data/balance/balancing.tres` (`t_parry`,
##     `p_block`, `block_arc_degrees`), в коде чисел баланса нет.
##
## Класс не знает про сцены/ноды: чистые вычисления, тестируемые GUT.
## Стоимость `E_block` списывается при входе в блок (`Player.try_block()`),
## а не за каждое попадание: удержание блока — одна оплата на активацию.

## Дуга блока по умолчанию: 120° (по 60° в каждую сторону от взгляда).
const DEFAULT_ARC_DEGREES: float = 120.0
## Допустимые границы дуги: уже 1° бессмысленна, 360° — блок со всех сторон.
const MIN_ARC_DEGREES: float = 1.0
const MAX_ARC_DEGREES: float = 360.0
const MAX_PERCENT: float = 100.0

## Окно парирования с момента входа в блок, s (T_parry).
var parry_window: float = 0.18
## Доля поглощённого урона обычным блоком, % (P_block).
var damage_reduction_percent: float = 80.0
## Ширина передней дуги блока, градусы.
var arc_degrees: float = DEFAULT_ARC_DEGREES
## Стоимость активации блока, E_block (списывает `Player.try_block()`).
var stamina_cost: float = 0.0

## Блок удерживается прямо сейчас.
var active: bool = false
## Остаток окна парирования, s.
var parry_time_left: float = 0.0

## Счётчики для QA/тестов и HUD-фидбека.
var parry_count: int = 0
var blocked_count: int = 0


## Настраивает тайминги/проценты из `balancing.tres`.
func setup(
	t_parry: float,
	p_block: float,
	block_arc_degrees: float = DEFAULT_ARC_DEGREES,
	e_block: float = 0.0
) -> void:
	parry_window = maxf(t_parry, 0.0)
	damage_reduction_percent = clampf(p_block, 0.0, MAX_PERCENT)
	arc_degrees = clampf(block_arc_degrees, MIN_ARC_DEGREES, MAX_ARC_DEGREES)
	stamina_cost = maxf(e_block, 0.0)
	parry_count = 0
	blocked_count = 0
	end()


## Хватает ли выносливости на активацию блока (AC-03.3: при 0 — недоступен).
func can_activate(current_stamina: float) -> bool:
	return current_stamina >= stamina_cost


## Вход в блок: окно парирования открывается заново на каждое нажатие.
func begin() -> void:
	active = true
	parry_time_left = parry_window


## Выход из блока (отпускание, hurt, смерть, смена состояния).
func end() -> void:
	active = false
	parry_time_left = 0.0


## Тик окна парирования по physics-кадрам.
func update(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	parry_time_left = maxf(parry_time_left - delta, 0.0)


func is_active() -> bool:
	return active


## Окно парирования ещё открыто (внутри T_parry после входа в блок).
func is_parry_window_open() -> bool:
	return active and parry_time_left > 0.0


func get_parry_time_left() -> float:
	return parry_time_left


## Парирование израсходовано: дальнейшие удары в этом удержании — обычный блок.
func consume_parry() -> void:
	parry_time_left = 0.0


## Урон после снижения на `P_block` %.
func reduce_damage(amount: float) -> float:
	return reduced_amount(amount, damage_reduction_percent)


## Статическая формула снижения урона (удобна для тестов/HUD-подсказок).
static func reduced_amount(amount: float, percent: float) -> float:
	var safe_amount: float = maxf(amount, 0.0)
	var safe_percent: float = clampf(percent, 0.0, MAX_PERCENT)
	return safe_amount * (1.0 - safe_percent / MAX_PERCENT)


## Направленная дуга: попадание пришло в переднюю полусферу блока.
## Нулевой вектор до источника считается фронтальным (неизвестное направление).
func is_in_arc(
	source_position: Vector2,
	blocker_position: Vector2,
	facing: int
) -> bool:
	if arc_degrees >= MAX_ARC_DEGREES:
		return true
	var to_source: Vector2 = source_position - blocker_position
	if to_source.is_zero_approx():
		return true
	var forward := Vector2(float(1 if facing >= 0 else -1), 0.0)
	var half_angle_cos: float = cos(deg_to_rad(arc_degrees * 0.5))
	return to_source.normalized().dot(forward) >= half_angle_cos


## Разрешает входящее попадание с учётом блока/парирования.
##
## Возвращает `{active, in_arc, blocked, parried, amount, absorbed}`:
##   * `blocked` — удар пришёл в дугу и блок активен;
##   * `parried` — попадание внутри окна `T_parry` (урон 0, окно расходуется);
##   * `amount` — урон после снижения (0 для парирования);
##   * `absorbed` — сколько урона поглощено.
func resolve_incoming(
	amount: float,
	source_position: Vector2,
	blocker_position: Vector2,
	facing: int
) -> Dictionary:
	var safe_amount: float = maxf(amount, 0.0)
	var result: Dictionary = {
		"active": active,
		"in_arc": false,
		"blocked": false,
		"parried": false,
		"amount": safe_amount,
		"absorbed": 0.0,
	}
	if not active:
		return result

	var in_arc: bool = is_in_arc(source_position, blocker_position, facing)
	result["in_arc"] = in_arc
	if not in_arc:
		return result

	result["blocked"] = true
	blocked_count += 1

	if is_parry_window_open():
		parry_count += 1
		consume_parry()
		result["parried"] = true
		result["amount"] = 0.0
		result["absorbed"] = safe_amount
		return result

	var reduced: float = reduce_damage(safe_amount)
	result["amount"] = reduced
	result["absorbed"] = safe_amount - reduced
	return result
