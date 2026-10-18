class_name FlashGovernor
extends RefCounted
## Ограничитель вспышек (DESIGN §4.5, §9.3): не более 3 вспышек за скользящую
## секунду на цель. Используется Hurtbox/Enemy, чтобы серия попаданий не давала
## эпилептический стробоскоп; в режиме «Без мигания» вспышки отключаются вовсе
## (проверка Config.no_flash — на стороне вызывающего).
##
## Время передаётся снаружи (`now`), поэтому поведение детерминировано в GUT
## без ожидания реальных секунд.

const MAX_FLASHES_PER_SEC: int = 3
const WINDOW_SEC: float = 1.0

var _times: Array[float] = []


## true, если в окне `now - 1 s … now` меньше трёх вспышек.
func can_flash(now: float) -> bool:
	_prune(now)
	return _times.size() < MAX_FLASHES_PER_SEC


## Регистрирует вспышку; false — лимит исчерпан и вспышку показывать нельзя.
func try_flash(now: float) -> bool:
	if not can_flash(now):
		return false
	_times.append(now)
	return true


## Число вспышек в окне (для тестов/отладки).
func count(now: float) -> int:
	_prune(now)
	return _times.size()


func reset() -> void:
	_times.clear()


func _prune(now: float) -> void:
	var cutoff: float = now - WINDOW_SEC
	while not _times.is_empty() and _times[0] <= cutoff:
		_times.remove_at(0)
