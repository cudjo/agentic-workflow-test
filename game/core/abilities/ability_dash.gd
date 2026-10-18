class_name AbilityDash
extends AbilityBase
## «Рывок» (T-07, SPEC US-02 / AC-02.2).
##
## Контракт поведения:
##   * рывок длиной `D_dash` за `T_dash` — значения из `balancing.tres`;
##   * неуязвимость (i-frames) на всё время рывка;
##   * кулдаун `C_dash` не больше `MAX_COOLDOWN_SEC` (1 с), стартует при входе
##     в рывок и тикает по physics-кадрам;
##   * доступен на земле и в воздухе; без способности
##     (`GameState.has_ability(&"dash")`) рывок недоступен.
##
## Реализация поведения — `entities/player/states/dash.gd` и
## `Player.try_dash()`. Этот ресурс — данные/идентичность для
## `GameState.abilities`, ability gates (T-09) и HUD (T-19: слот способности
## и полоса кулдауна через `EventBus.ability_cooldown_changed`).

const ID: StringName = &"dash"
const DISPLAY_NAME: String = "Рывок"
## Жёсткий предел кулдауна из AC-02.2. Само значение `C_dash` — в
## `balancing.tres`; Player зажимает его этим пределом.
const MAX_COOLDOWN_SEC: float = 1.0


func _init() -> void:
	# Значения по умолчанию для new(); .tres может переопределить их.
	if id == &"":
		id = ID
	if display_name.is_empty():
		display_name = DISPLAY_NAME
