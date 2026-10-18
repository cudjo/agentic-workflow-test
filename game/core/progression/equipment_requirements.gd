class_name EquipmentRequirements
extends RefCounted
## EquipmentRequirements — контракт требований экипировки (T-29 → T-21).
##
## Требования — словарь `{stat_id: минимальное значение}`. Это чистый
## формат данных: инвентарь T-21 получает его из `ProgressionData`
## (`equipment_requirements`) через `GameState.get_equipment_requirements()`
## и проверяет текущие характеристики игрока.
##
## `missing` — список `{stat_id, required, current, deficit}`. UI показывает
## требуемое значение («НЕТ · ещё N») и не блокирует выбор предмета вручную:
## решение об экипировке остаётся за инвентарём.
##
## Класс не хранит состояние игрока и не меняет `GameState` — только
## нормализует данные и сравнивает со снимком характеристик.

## Нормализует сырые требования: пустые id и нечисловые значения
## пропускаются, значения приводятся к int и не опускаются ниже 0.
static func normalize(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not raw is Dictionary:
		return result
	for key: Variant in (raw as Dictionary).keys():
		var stat_id: StringName = StringName(str(key))
		if stat_id == &"":
			continue
		var value: Variant = (raw as Dictionary)[key]
		if not (value is int or value is float):
			continue
		result[stat_id] = maxi(int(value), 0)
	return result


## Характеристики, которых не хватает для требований.
static func get_missing(requirements: Dictionary, stats: Dictionary) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	var normalized: Dictionary = normalize(requirements)
	for stat_id: StringName in normalized.keys():
		var required: int = int(normalized[stat_id])
		var current: int = _stat_value(stats, stat_id)
		if current < required:
			missing.append({
				"stat_id": stat_id,
				"required": required,
				"current": current,
				"deficit": required - current,
			})
	return missing


## Выполнены ли все требования (пустые требования — всегда да).
static func is_met(requirements: Dictionary, stats: Dictionary) -> bool:
	return get_missing(requirements, stats).is_empty()


## Полное описание для UI: `{requirements, met, missing, reason}`.
## `labels` — необязательный словарь stat_id → имя для текста причины.
static func describe(
	requirements: Dictionary,
	stats: Dictionary,
	labels: Dictionary = {}
) -> Dictionary:
	var normalized: Dictionary = normalize(requirements)
	var missing: Array[Dictionary] = get_missing(normalized, stats)
	return {
		"requirements": normalized,
		"met": missing.is_empty(),
		"missing": missing,
		"reason": "" if missing.is_empty() else format_missing(missing, labels),
	}


## Причина отказа с требуемой величиной (AC-08.2): «ТРЕБУЕТСЯ: СИЛА 9
## (у вас 6)». Несколько требований перечисляются через «; ».
static func format_missing(missing: Array[Dictionary], labels: Dictionary = {}) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in missing:
		var stat_id: StringName = StringName(str(entry.get("stat_id", "")))
		var label: String = str(labels.get(stat_id, stat_id))
		parts.append(
			LocaleText.current("ui.inv.requires_item", [
				label.to_upper(),
				int(entry.get("required", 0)),
				int(entry.get("current", 0)),
			])
		)
	if parts.is_empty():
		return ""
	return LocaleText.current("ui.inv.requires") + "; ".join(parts)


static func _stat_value(stats: Dictionary, stat_id: StringName) -> int:
	var value: Variant = stats.get(stat_id)
	if value is int:
		return value
	if value is float:
		return int(value)
	return 0
