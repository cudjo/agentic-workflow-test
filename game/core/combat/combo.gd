class_name ComboTracker
extends RefCounted
## ComboTracker — окно связки ближнего боя (T-10, DESIGN §7).
##
## Данные оружия задают только количество/множители ударов; длительность шага
## и окно связки берутся из `balancing.tres` (`t_attack * attack_speed`,
## `combo_link_window`), активная фаза хитбокса — доли
## `combo_hit_start_ratio`/`combo_hit_end_ratio`.
##
## Жизненный цикл: `start()` → удары идут по времени; в конце шага открывается
## окно связки `[duration - link_window, duration]`. Нажатие атаки в этом окне
## (`try_link()`) переключает на следующий удар; без связки шаг завершается и
## комбо сбрасывается.

signal step_started(index: int)

var step_count: int = 0
var step_duration: float = 0.0
var link_window: float = 0.0
## Индекс текущего удара; -1 — комбо неактивно.
var step_index: int = -1
var time_in_step: float = 0.0


func setup(count: int, duration: float, window: float) -> void:
	step_count = maxi(count, 0)
	step_duration = maxf(duration, 0.0)
	link_window = maxf(window, 0.0)
	reset()


## Начинает комбо с первого удара; возвращает индекс (-1, если ударов нет).
func start() -> int:
	if step_count <= 0:
		reset()
		return -1
	step_index = 0
	time_in_step = 0.0
	step_started.emit(step_index)
	return step_index


func is_active() -> bool:
	return step_index >= 0


func has_next_step() -> bool:
	return step_index >= 0 and step_index + 1 < step_count


## Окно связки открыто (последние `link_window` секунд удара).
func can_link() -> bool:
	if not has_next_step():
		return false
	return time_in_step >= maxf(step_duration - link_window, 0.0)


## Переход на следующий удар, если окно открыто.
func try_link() -> bool:
	if not can_link():
		return false
	step_index += 1
	time_in_step = 0.0
	step_started.emit(step_index)
	return true


## Продвигает время удара. true — шаг завершился и комбо сброшено.
func advance(delta: float) -> bool:
	if not is_active():
		return true
	time_in_step += maxf(delta, 0.0)
	if time_in_step >= step_duration:
		reset()
		return true
	return false


## Активная фаза хитбокса текущего удара (доли длительности).
func is_hit_active(start_ratio: float, end_ratio: float) -> bool:
	if not is_active():
		return false
	var start_time: float = clampf(start_ratio, 0.0, 1.0) * step_duration
	var end_time: float = clampf(end_ratio, 0.0, 1.0) * step_duration
	return time_in_step >= start_time and time_in_step < end_time


func reset() -> void:
	step_index = -1
	time_in_step = 0.0
