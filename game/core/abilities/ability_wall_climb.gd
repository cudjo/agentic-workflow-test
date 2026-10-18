class_name AbilityWallClimb
extends AbilityBase
## «Карабканье по стенам» (T-08, SPEC US-02 / AC-02.3).
##
## Контракт поведения:
##   * удержание на стене при нажатом направлении в её сторону; скорость
##     скольжения не выше `V_wall_slide` из `balancing.tres`;
##   * прыжок от стены (wall kick) сообщает горизонтальный импульс
##     `V_wall_kick` в сторону, противоположную стене (AC-02.3);
##   * без способности (`GameState.has_ability(&"wall_climb")`) удержание на
##     стене невозможно — падение идёт с обычной гравитацией.
##
## Реализация поведения — `entities/player/states/wall_slide.gd`,
## `states/wall_kick.gd` и `Player.try_wall_slide()`/`Player.try_wall_kick()`.
## Этот ресурс — данные/идентичность для `GameState.abilities`, ability gates
## (T-09) и HUD (T-19: третий слот способностей).

const ID: StringName = &"wall_climb"
const DISPLAY_NAME: String = "Карабканье по стенам"
## Насколько нормаль столкновения должна быть горизонтальной, чтобы считать
## поверхность вертикальной стеной (у тайлов она строго ±1 по X).
const MIN_WALL_NORMAL_X: float = 0.7


func _init() -> void:
	# Значения по умолчанию для new(); .tres может переопределить их.
	if id == &"":
		id = ID
	if display_name.is_empty():
		display_name = DISPLAY_NAME


## Направление от игрока к стене по нормали столкновения:
## 1 — стена справа, -1 — слева, 0 — поверхность не вертикальная.
## Нормаль указывает от стены к игроку, поэтому знак инвертируется.
static func wall_dir_from_normal(normal: Vector2) -> int:
	if absf(normal.x) < MIN_WALL_NORMAL_X:
		return 0
	return -1 if normal.x > 0.0 else 1


## Игрок прижимается к стене: ввод направлен в её сторону (AC-02.3).
static func is_holding_into_wall(move_axis: float, wall_dir: int) -> bool:
	if wall_dir == 0:
		return false
	return move_axis * float(wall_dir) > 0.0
