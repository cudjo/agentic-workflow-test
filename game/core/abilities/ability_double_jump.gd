class_name AbilityDoubleJump
extends AbilityBase
## «Двойной прыжок» (T-06, SPEC US-02/AC-02.1).
##
## Контракт поведения (AC-02.1):
##   * ровно `AIR_JUMPS` (1) прыжок в воздухе до приземления;
##   * высота второго прыжка = `h_double_factor * H_jump` (≥ 0.8·H_jump),
##     начальная скорость — `BalancingParams.get_double_jump_velocity()`;
##   * счётчик воздушных прыжков сбрасывается при приземлении
##     (`Player.on_landed()` из `states/land.gd`);
##   * без способности второй прыжок невозможен.
##
## Реализация поведения — `states/double_jump.gd` + проверки в
## `states/jump.gd` / `states/fall.gd`. Этот ресурс — данные/идентичность для
## `GameState.abilities`, ability gates (T-09) и HUD (T-19).

const ID: StringName = &"double_jump"
const DISPLAY_NAME: String = "Двойной прыжок"
## Сколько прыжков в воздухе доступно до приземления (AC-02.1).
const AIR_JUMPS: int = 1
## Минимальная доля H_jump для второго прыжка (AC-02.1).
const MIN_HEIGHT_FACTOR: float = 0.8


func _init() -> void:
	# Значения по умолчанию для new(); .tres может переопределить их.
	if id == &"":
		id = ID
	if display_name.is_empty():
		display_name = DISPLAY_NAME
