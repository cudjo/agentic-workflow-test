class_name AbilityGateData
extends Resource
## AbilityGateData — одна запись списка ability gates (T-09, PLAN §3.3).
##
## Данные, не логика: какую способность требует конкретный проход и (опционально)
## как подписать её в подсказке. Сами проходы — узлы `AbilityGate` в сценах зон;
## они ищут запись по `id` (`gate_id`) в `data/ability_gates.tres`.
##
## `ability_id` — ключ `GameState.abilities`/`AbilityRegistry` (`double_jump`,
## `dash`, `wall_climb`). `hint_label` — необязательный RU-оверрайд имени
## способности для подсказки «Нужно: …»; пусто — имя берётся из реестра.
## `proof_zone_id` — зона, посещение которой доказывает, что проход уже пройден
## другим маршрутом (EC-10): тогда gate не блокирует даже без способности.

@export var id: StringName = &""
@export var ability_id: StringName = &""
@export var hint_label: String = ""
@export var proof_zone_id: StringName = &""


## Запись пригодна: есть id и зарегистрированная способность.
func is_valid() -> bool:
	return id != &"" and ability_id != &"" and AbilityRegistry.has_ability(ability_id)
