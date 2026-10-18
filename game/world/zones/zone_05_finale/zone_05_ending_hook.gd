extends Area2D
## Точка выхода в концовку финала (T-16): хук для T-32/T-27, не сама концовка.
##
## По TASKS T-16 финальная последовательность и текст концовки — задача T-32.
## Здесь только:
##   * `EndingExit` (Area2D) с дочерним `Marker2D` `ending_exit` — точка/маркер;
##   * сигнал `ending_requested(faction_id, zone_id, ending_id)` для будущей
##     последовательности;
##   * чтение фракции из `FactionManager` (T-27). Сейчас менеджер — заглушка,
##     поэтому вызов защищён `has_method`: пока метода нет, faction_id = &"".
##
## `gate_on_boss_id` — id финального босса (T-32). Пока пусто, выход открыт:
## на момент T-16 босса ещё нет, но контракт для T-32 уже на месте. Когда
## T-32 выставит id, проход откроется только после победы (EC-09/GameState).
##
## Area2D не перехватывает ввод и не блокирует движение: только сигнал.

signal ending_requested(faction_id: StringName, zone_id: StringName, ending_id: StringName)

@export var zone_id: StringName = &"zone_05_finale"
@export var ending_id: StringName = &"ending"
## Пусто — выход не заперт боссом (T-32 выставит id финального босса).
@export var gate_on_boss_id: StringName = &""
## Один запрос за вход; повторно — только после `reset_hook()`.
@export var one_shot: bool = true

var _requested: bool = false

@onready var marker: Marker2D = get_node_or_null("ending_exit") as Marker2D


func _ready() -> void:
	add_to_group(&"ending_hook")
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group(&"player"):
		return
	request_ending()


## Возвращает faction_id, с которым запрошена концовка (&"" — запрос отклонён
## или фракция ещё не выбрана). Сама последовательность — T-32.
func request_ending() -> StringName:
	if not is_unlocked():
		return &""
	if one_shot and _requested:
		return &""
	_requested = true
	var faction := resolve_faction()
	ending_requested.emit(faction, zone_id, ending_id)
	return faction


## Выход в концовку открыт: либо босс ещё не привязан (T-16), либо побеждён.
func is_unlocked() -> bool:
	if gate_on_boss_id == &"":
		return true
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null and game_state.has_method(&"is_boss_defeated"):
		return bool(game_state.call(&"is_boss_defeated", gate_on_boss_id))
	return false


func is_requested() -> bool:
	return _requested


## Позиция маркера выхода (T-32 использует для телепорта/эффектов).
func get_ending_marker() -> Marker2D:
	return marker


func reset_hook() -> void:
	_requested = false


## Фракция из FactionManager (T-27). Заглушка менеджера — &"".
func resolve_faction() -> StringName:
	var manager := get_node_or_null("/root/FactionManager")
	if manager == null:
		return &""
	for method: StringName in [&"get_selected_faction", &"get_current_faction", &"get_faction_id"]:
		if manager.has_method(method):
			return StringName(str(manager.call(method)))
	var value: Variant = manager.get(&"selected_faction")
	if value != null:
		return StringName(str(value))
	return &""
