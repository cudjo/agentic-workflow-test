class_name AbilityGateCatalog
extends Resource
## AbilityGateCatalog — список ability gates из `data/ability_gates.tres` (T-09).
##
## Единственный источник требований проходов: сцены зон ставят только `gate_id`,
## а требуемая способность и подпись подсказки читаются отсюда. Логика гейта
## (`world/props/AbilityGate.gd`) не хардкодит id способностей и пути.
##
## Идентификаторы записей должны совпадать с `gate_id` узлов `AbilityGate`
## в сценах зон; `validate()` ловит пустые/дублирующиеся id и неизвестные
## способности (реестр — `AbilityRegistry` T-06).

@export var gates: Array[AbilityGateData] = []


## Запись по id прохода; null — проход не описан данными.
func get_gate(gate_id: StringName) -> AbilityGateData:
	if gate_id == &"":
		return null
	for gate: AbilityGateData in gates:
		if gate != null and gate.id == gate_id:
			return gate
	return null


func has_gate(gate_id: StringName) -> bool:
	return get_gate(gate_id) != null


## Требуемая способность прохода; `&""` — проход не описан.
func get_ability_id(gate_id: StringName) -> StringName:
	var gate: AbilityGateData = get_gate(gate_id)
	return gate.ability_id if gate != null else &""


## RU-подпись способности из данных; пусто — использовать реестр.
func get_hint_label(gate_id: StringName) -> String:
	var gate: AbilityGateData = get_gate(gate_id)
	return gate.hint_label if gate != null else ""


## Зона-доказательство пройденного маршрута (EC-10); `&""` — нет.
func get_proof_zone_id(gate_id: StringName) -> StringName:
	var gate: AbilityGateData = get_gate(gate_id)
	return gate.proof_zone_id if gate != null else &""


## Уникальные id проходов в порядке данных (для тестов/карты).
func get_gate_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for gate: AbilityGateData in gates:
		if gate != null and gate.id != &"" and not ids.has(gate.id):
			ids.append(gate.id)
	return ids


## Уникальные требуемые способности в порядке данных.
func get_ability_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for gate: AbilityGateData in gates:
		if gate != null and gate.ability_id != &"" and not ids.has(gate.ability_id):
			ids.append(gate.ability_id)
	return ids


## Проблемы данных: пустые/дублирующиеся id, неизвестные способности.
## Пустой массив — данные валидны.
func validate() -> PackedStringArray:
	var issues: PackedStringArray = []
	var seen: Dictionary = {}
	for index: int in gates.size():
		var gate: AbilityGateData = gates[index]
		if gate == null:
			issues.append("gate #%d is null" % index)
			continue
		if gate.id == &"":
			issues.append("gate #%d has empty id" % index)
		elif seen.has(gate.id):
			issues.append("duplicate gate id '%s'" % gate.id)
		else:
			seen[gate.id] = true
		if gate.ability_id == &"":
			issues.append("gate '%s' has empty ability_id" % gate.id)
		elif not AbilityRegistry.has_ability(gate.ability_id):
			issues.append(
				"gate '%s' requires unknown ability '%s'" % [gate.id, gate.ability_id]
			)
		if (
			gate.proof_zone_id != &""
			and not ResourceLoader.exists("res://data/zones/%s.tres" % gate.proof_zone_id)
		):
			issues.append(
				"gate '%s' references unknown proof zone '%s'"
				% [gate.id, gate.proof_zone_id]
			)
	return issues
