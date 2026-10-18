class_name WeaponData
extends Resource
## WeaponData — данные типа оружия (T-10). Файлы: `data/weapons/*.tres`.
##
## Тайминги удара не дублируются: длительность шага =
## `balancing.tres.t_attack * attack_speed`, окно связки и активная фаза
## хитбокса — из `balancing.tres`. Здесь живут только боевые характеристики
## и структура комбо (2–3 удара).

enum WeaponType {
	LIGHT,
	ONE_HANDED,
	TWO_HANDED,
}

@export var id: StringName = &""
## Ключ локализации (`tr()` в T-36); не отображается в коде.
@export var display_name_key: String = ""
@export var weapon_type: WeaponType = WeaponType.ONE_HANDED
## Базовый урон первого удара; далее умножается на множитель шага.
@export var damage: float = 10.0
## Сила отбрасывания до множителя `balancing.tres.knockback_scale`.
@export var knockback: float = 100.0
## Множитель длительности удара относительно `t_attack` (0.7 — быстрее).
@export var attack_speed: float = 1.0
## Множители урона по ударам комбо: 2–3 значения.
@export var combo_multipliers: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])


func get_combo_length() -> int:
	return combo_multipliers.size()


func get_step_multiplier(index: int) -> float:
	if index < 0 or index >= combo_multipliers.size():
		return 1.0
	return combo_multipliers[index]


func is_valid() -> bool:
	var length: int = get_combo_length()
	if length < 2 or length > 3:
		return false
	if damage < 0.0 or attack_speed <= 0.0:
		return false
	for multiplier: float in combo_multipliers:
		if multiplier <= 0.0:
			return false
	return true
