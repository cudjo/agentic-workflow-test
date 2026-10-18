class_name AbilityRegistry
extends RefCounted
## AbilityRegistry — реестр способностей (T-06, PLAN §3.3): единственная точка,
## где id способности связывается с её данными.
##
## Данные — `data/abilities/*.tres` (AbilityBase-наследники), поведение —
## `core/abilities/*.gd` и FSM игрока. T-07/T-08 добавляют свои ресурсы в
## `ABILITY_PATHS`; T-09 (gates) и HUD (T-19) читают `display_name`/наличие
## способности отсюда, не хардкодя пути в логике.
##
## Ресурсы грузятся лениво и кешируются на время сессии.

const ABILITY_PATHS: Array[String] = [
	"res://data/abilities/double_jump.tres",
]

static var _cache: Dictionary = {}


## Данные способности по id; null, если способность не зарегистрирована.
static func get_ability(ability_id: StringName) -> AbilityBase:
	_ensure_loaded()
	return _cache.get(ability_id) as AbilityBase


## Зарегистрирована ли способность с таким id.
static func has_ability(ability_id: StringName) -> bool:
	return get_ability(ability_id) != null


## Все известные id в детерминированном (отсортированном) порядке.
static func all_ids() -> Array[StringName]:
	_ensure_loaded()
	var ids: Array[StringName] = []
	for key: Variant in _cache.keys():
		ids.append(StringName(key))
	ids.sort()
	return ids


## Все данные способностей (T-09: список gates; HUD: слоты способностей).
static func all() -> Array[AbilityBase]:
	_ensure_loaded()
	var result: Array[AbilityBase] = []
	for ability_id: StringName in all_ids():
		result.append(_cache[ability_id] as AbilityBase)
	return result


static func _ensure_loaded() -> void:
	if not _cache.is_empty():
		return
	for path: String in ABILITY_PATHS:
		var ability: AbilityBase = load(path) as AbilityBase
		if ability == null:
			push_error("AbilityRegistry: cannot load ability at %s" % path)
			continue
		if ability.id == &"":
			push_error("AbilityRegistry: ability at %s has an empty id" % path)
			continue
		_cache[ability.id] = ability
