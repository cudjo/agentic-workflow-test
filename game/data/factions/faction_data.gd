class_name FactionData
extends Resource
## FactionData — данные фракции (T-27). Файлы: `data/factions/*.tres`.
##
## Один ресурс описывает фракцию целиком: имя/лор, шкалу репутации, порог
## доступа, причины отказа (AC-06.2), таблицу `Δ` за действия/квесты
## (AC-06.1), список квестов (T-28) и союзную фракцию — альтернативный путь,
## если текущая враждебна (EC-11).
##
## Логика (начисление репутации, проверка порогов, выбор фракции) живёт в
## `autoload/FactionManager.gd`; здесь только данные и их валидация.
## Причины отказа — шаблоны с подстановками `{faction}`, `{reputation}`,
## `{threshold}`, `{territory}` (форматирует FactionManager).

@export_group("Identity")
@export var id: StringName = &""
## Ключ локализации (`tr()` в T-36).
@export var display_name_key: String = ""
## Читаемое имя (заглушка до T-36), используется UI фракций/журналом.
@export var display_name: String = ""
## Лор для вкладки «Фракции» (T-24): 2–4 строки.
@export_multiline var lore: String = ""
## Акцентный цвет фракции (не единственный носитель смысла, DESIGN §9.2).
@export var color: Color = Color(0.75, 0.54, 0.24, 1.0)

@export_group("Reputation")
## Минимум шкалы репутации (знак «−» дублирует цвет, DESIGN §8.4).
@export var reputation_min: int = -100
## Максимум шкалы репутации.
@export var reputation_max: int = 100
## Порог доступа к территории/торговцу/квестам фракции (AC-06.2).
## Репутация ниже порога закрывает доступ с объяснением причины.
@export var access_threshold: int = 0
## Название территории — для объяснения отказа и карты (T-33).
@export var territory_name: String = ""

@export_group("Access denial")
## Причина отказа во входе на территорию (AC-06.2, EC-11).
@export_multiline var territory_denied_reason: String = ""
## Причина отказа в торговле (AC-06.2). Пусто — общий шаблон менеджера.
@export_multiline var trade_denied_reason: String = ""
## Причина недоступности квеста (EC-11). Пусто — общий шаблон менеджера.
@export_multiline var quest_denied_reason: String = ""
## Союзная фракция, через которую можно получить доступ/квест (EC-11).
## Пусто — альтернативы нет.
@export var alternative_faction_id: StringName = &""

@export_group("Actions and quests")
## Таблица `Δ` (AC-06.1): event_id (квест `quest_*` или действие `action_*`)
## -> изменение репутации. Ноль в таблицу не пишется.
@export var reputation_events: Dictionary = {}
## Квесты фракции (id из `data/quests/*.tres`, T-28). Владелец квеста —
## фракция, в чьём списке он лежит; доступ проверяется по порогу.
@export var quests: Array[StringName] = []


## Δ репутации за событие/квест; 0 — событие на фракцию не влияет.
func get_reputation_delta(event_id: StringName) -> int:
	if event_id == &"":
		return 0
	var value: Variant = reputation_events.get(String(event_id), 0)
	if value is int:
		return value
	if value is float:
		return int(value)
	return 0


func has_quest(quest_id: StringName) -> bool:
	return quest_id != &"" and quests.has(quest_id)


## Ограничение репутации шкалой фракции.
func clamp_reputation(value: int) -> int:
	return clampi(value, reputation_min, reputation_max)


## Порог доступа пройден (AC-06.2).
func grants_access(reputation: int) -> bool:
	return reputation >= access_threshold


## Проверка данных: ловит битые `.tres` до рантайма (Zero Dead Config).
func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or display_name_key.is_empty():
		return false
	if lore.is_empty():
		return false
	if reputation_min >= reputation_max:
		return false
	if access_threshold < reputation_min or access_threshold > reputation_max:
		return false
	if color.a <= 0.0:
		return false
	if territory_name.is_empty() or territory_denied_reason.is_empty():
		return false
	if alternative_faction_id == id:
		return false

	var quest_ids: Dictionary = {}
	for quest_id: StringName in quests:
		if quest_id == &"":
			return false
		if quest_ids.has(quest_id):
			return false
		quest_ids[quest_id] = true
	if quests.is_empty():
		return false

	if reputation_events.is_empty():
		return false
	for key: Variant in reputation_events.keys():
		if String(key).is_empty():
			return false
		var value: Variant = reputation_events[key]
		if not (value is int or value is float):
			return false
		if int(value) == 0:
			return false
	return true
