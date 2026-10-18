class_name TraderNpc
extends DialogueNpc
## TraderNpc — торговец с ограничением по репутации (T-28, AC-06.2).
##
## Доступ проверяется `FactionManager.can_trade()`; при низкой репутации
## возвращается причина отказа из данных фракции (тот же текст, что в
## диалоге через `DialogueCondition.require_trade_access`) и альтернативная
## фракция — путь EC-11.
##
## Ассортимент и цены — данные сцены (`stock`, `prices`), валюта и инвентарь —
## `GameState`. Торговец не рисует UI: экран торговли (T-21) читает
## `get_trade_info()`.

const DEFAULT_PRICE: int = 20

## Товары торговца (id предметов).
@export var stock: Array[StringName] = []
## Цена по id; отсутствующий id стоит `DEFAULT_PRICE`.
@export var prices: Dictionary = {}


func get_price(item_id: StringName) -> int:
	var value: Variant = prices.get(String(item_id), DEFAULT_PRICE)
	if value is int:
		return maxi(value, 0)
	if value is float:
		return maxi(int(value), 0)
	return DEFAULT_PRICE


func can_trade() -> bool:
	return FactionManager.can_trade(get_faction_id())


## Снимок лавки для UI:
## `{npc_id, npc_name, faction_id, faction_name, allowed, can_trade, reason,
##   reputation, threshold, alternative_faction_id, alternative_allowed,
##   currency, items: [{id, price, affordable}]}`.
func get_trade_info(language: String = "ru") -> Dictionary:
	var faction_id: StringName = get_faction_id()
	var info: Dictionary = FactionManager.get_access_info(
		faction_id,
		FactionManager.AccessKind.TRADER
	)
	info["npc_id"] = get_npc_id()
	info["npc_name"] = get_display_name(language)
	info["faction_name"] = get_faction_name()
	info["can_trade"] = bool(info.get("allowed", false))
	info["currency"] = GameState.currency
	info["items"] = get_trade_items()
	return info


## Товары с ценой и доступностью по валюте.
func get_trade_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for item_id: StringName in stock:
		var price: int = get_price(item_id)
		items.append({
			"id": item_id,
			"price": price,
			"affordable": GameState.currency >= price,
		})
	return items


## Покупка: при отказе доступа/нехватке валюты ничего не меняет.
## Результат: `{ok, item_id, price, currency, reason, message}`.
func buy(item_id: StringName, language: String = "ru") -> Dictionary:
	var access: Dictionary = FactionManager.get_access_info(
		get_faction_id(),
		FactionManager.AccessKind.TRADER
	)
	if not bool(access.get("allowed", false)):
		return {
			"ok": false,
			"item_id": item_id,
			"price": get_price(item_id),
			"currency": GameState.currency,
			"reason": "no_access",
			"message": str(access.get("reason", "")),
		}
	if not stock.has(item_id):
		return {
			"ok": false,
			"item_id": item_id,
			"price": 0,
			"currency": GameState.currency,
			"reason": "not_in_stock",
			"message": (
				"The trader does not sell this."
				if DialogueText.is_english(language)
				else "Такого товара у торговца нет."
			),
		}

	var price: int = get_price(item_id)
	if GameState.currency < price:
		return {
			"ok": false,
			"item_id": item_id,
			"price": price,
			"currency": GameState.currency,
			"reason": "not_enough_currency",
			"message": (
				"Not enough coin: %d required." % price
				if DialogueText.is_english(language)
				else "Не хватает монет: нужно %d." % price
			),
		}

	GameState.currency -= price
	GameState.add_item(item_id)
	return {
		"ok": true,
		"item_id": item_id,
		"price": price,
		"currency": GameState.currency,
		"reason": "",
		"message": "",
	}
