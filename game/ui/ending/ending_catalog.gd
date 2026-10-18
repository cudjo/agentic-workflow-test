class_name EndingCatalog
extends RefCounted
## EndingCatalog — концовки по фракции (T-32, US-06).
##
## `FactionManager` пока заглушка (T-27): при пустой фракции отдаётся
## нейтральная концовка. Для выбранной фракции строится отдельный текст,
## поэтому финал зависит от решения игрока даже до появления данных T-27:
## известные роли (`order`/`free`/`ash`) получают собственные эпилоги,
## остальные id — безопасный фолбэк с именем фракции.
##
## Чтение менеджера защищено (`has_method`/проверка поля): отсутствие API
## T-27 не роняет финальную последовательность.

const NEUTRAL_ID: StringName = &"ending_neutral"
const FACTION_PREFIX: String = "ending_"

const NEUTRAL_TITLE: String = "ui.ending.neutral_title"
const NEUTRAL_BODY: String = "ui.ending.neutral_body"


## Текст концовки для фракции. `faction_name` — отображаемое имя из
## FactionManager (если T-27 его предоставляет).
static func resolve(
	faction_id: StringName,
	faction_name: String = ""
) -> EndingText:
	if faction_id == &"":
		return EndingText.create(
			NEUTRAL_ID,
			LocaleText.current("ui.ending.neutral_kicker"),
			LocaleText.current(NEUTRAL_TITLE),
			LocaleText.current(NEUTRAL_BODY),
			LocaleText.current("ui.ending.faction_none"),
			Color("#e0b56a")
		)

	var display: String = faction_name if not faction_name.is_empty() else String(faction_id)
	var flavor: String = _flavor_for(faction_id, display)
	return EndingText.create(
		StringName("%s%s" % [FACTION_PREFIX, faction_id]),
		LocaleText.current("ui.ending.faction_kicker"),
		LocaleText.current("ui.ending.legacy") % display.to_upper(),
		flavor,
		LocaleText.current("ui.ending.faction_line") % display,
		Color("#c08a3e")
	)


## Безопасно читает выбранную фракцию из FactionManager (T-27).
static func read_selected_faction(manager: Node) -> StringName:
	if manager == null or not is_instance_valid(manager):
		return &""
	for method: StringName in [&"get_selected_faction", &"get_current_faction", &"get_faction_id"]:
		if manager.has_method(method):
			return StringName(str(manager.call(method)))
	var value: Variant = manager.get(&"selected_faction")
	if value != null:
		return StringName(str(value))
	return &""


## Безопасно читает отображаемое имя фракции (если в T-27 оно появится).
static func read_faction_name(manager: Node, faction_id: StringName) -> String:
	if manager == null or not is_instance_valid(manager) or faction_id == &"":
		return ""
	for method: StringName in [&"get_faction_name", &"get_display_name", &"get_name_for"]:
		if manager.has_method(method):
			var value: Variant = manager.call(method, faction_id)
			if value != null:
				return str(value)
	return ""


## Эпилог роли фракции; неизвестная фракция получает собственный текст,
## поэтому две разные фракции никогда не дают одинаковую концовку.
static func _flavor_for(faction_id: StringName, display: String) -> String:
	var key: String = String(faction_id).to_lower()
	if key.contains("order") or key.contains("watch") or key.contains("guard"):
		return LocaleText.current("ui.ending.order_body")
	if key.contains("free") or key.contains("march") or key.contains("wild"):
		return LocaleText.current("ui.ending.free_body")
	if key.contains("ash") or key.contains("cult") or key.contains("flame"):
		return LocaleText.current("ui.ending.ash_body")
	return LocaleText.current("ui.ending.unknown_body") % display
