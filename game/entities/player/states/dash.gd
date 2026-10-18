extends PlayerState
## Dash — рывок длиной D_dash за T_dash (T-07, SPEC AC-02.2).
##
## Поведение:
##   * горизонтальная скорость `D_dash / T_dash` на всё время `T_dash`;
##   * i-frames на весь рывок (урон игнорируется `Player.apply_damage`);
##   * кулдаун `C_dash` запускается при входе (`Player.begin_dash_cooldown`)
##     и отдаётся HUD сигналом `EventBus.ability_cooldown_changed`;
##   * доступен на земле и в воздухе — вход через `Player.try_dash()` из
##     idle/run/land/jump/fall/double_jump.
##
## Гейт способности: без `GameState.has_ability(&"dash")` рывок недоступен.
## Проверка в `enter()` — defence-in-depth для принудительных переходов
## (`force_state`): состояние не даёт i-frames и выходит на первом тике.

var _allowed: bool = false


func enter(previous: StringName) -> void:
	super.enter(previous)
	_allowed = player.has_ability(AbilityDash.ID)
	if not _allowed:
		return
	player.velocity.x = float(player.facing) * (player.balance.d_dash / player.balance.t_dash)
	player.begin_dash_cooldown()


func physics_update(_delta: float) -> void:
	if not _allowed:
		finish_to_locomotion()
		return
	player.velocity.x = float(player.facing) * (player.balance.d_dash / player.balance.t_dash)
	if time_in_state >= player.balance.t_dash:
		finish_to_locomotion()


func is_invulnerable() -> bool:
	return _allowed
