class_name AbilityBase
extends Resource
## AbilityBase — контракт способности-метроидвании (T-06, PLAN §3.3).
##
## Разделение ответственности:
##   * данные/идентичность способности — ресурс (`data/abilities/*.tres`);
##   * получение способности в забеге — `GameState.abilities`;
##   * поведение — FSM игрока (`entities/player/states/*`) и наследники этого
##     класса (T-07 dash, T-08 wall climb переопределяют `activate()` при
##     необходимости, но обязаны вызывать `super.activate(player)`).
##
## Runtime-разблокировка: `activate()` ставит на игроке флаг с `id`
## способности, `deactivate()` снимает его. Игрок проверяет флаги
## (`Player.has_ability_flag()`), а `GameState.has_ability()` остаётся
## источником истины для сохранений, ability gates (T-09) и HUD (T-19).
##
## Контракт для T-07/T-08/T-09:
##   * `id` — уникальный StringName (совпадает с ключом GameState.abilities);
##   * `display_name` — RU-название для подсказки «Нужно: …» (AC-02.4);
##   * `activate(player) -> bool` — включить поведение (false при ошибке);
##   * `deactivate(player) -> void` — выключить поведение;
##   * `player_flags() -> Dictionary` — множество флагов, которые ставит
##     способность (id -> true).

## Уникальный идентификатор способности; ключ в GameState.abilities.
@export var id: StringName = &""
## Название для HUD/подсказок (RU; локализация — T-36 по ключу id).
@export var display_name: String = ""
## Описание для инвентаря/подсказок (T-21/T-09).
@export_multiline var description: String = ""


## Включает поведение способности на игроке. Базовая реализация ставит флаг
## с id способности; наследники расширяют её под свои параметры.
func activate(player: Node) -> bool:
	if player == null or id == &"":
		return false
	if not player.has_method(&"set_ability_flag"):
		push_error(
			"AbilityBase.activate: '%s' requires set_ability_flag() on the player" % id
		)
		return false
	player.call(&"set_ability_flag", id, true)
	return true


## Выключает поведение (новый забег, отладка, принудительное лишение).
func deactivate(player: Node) -> void:
	if player == null or id == &"":
		return
	if player.has_method(&"set_ability_flag"):
		player.call(&"set_ability_flag", id, false)


## Флаги, которые способность ставит на игроке. Потребители: T-09/HUD.
func player_flags() -> Dictionary:
	if id == &"":
		return {}
	return {id: true}
