class_name InventoryItemSlot
extends AshenSlot
## InventoryItemSlot — ячейка инвентаря T-21 на базе `AshenSlot` (DESIGN §6.2).
##
## `AshenSlot` умеет рисовать одно состояние за раз. Инвентарю нужно
## комбинировать их: предмет может быть одновременно выбран и надет, а
## выбранный предмет с невыполненными требованиями обязан сохранить красный
## «!» (DESIGN §6.2). Поэтому «выбран» и «надет» — независимые флаги, которые
## дорисовываются поверх базового состояния:
##
##   * `selected` — золотая рамка 2 px + внутренняя `gold-9` (форма + цвет);
##   * `equipped` — золотой маркер-квадрат 3×3 в левом верхнем углу.
##
## Базовое состояние (`state`) отвечает за обычный/пустой/недоступный слот и
## требования. Фокус рисует `AshenSlot` (золотые уголковые скобки), поэтому
## выбранный и сфокусированный слот различимы формой, а не только цветом.

## Выбранный предмет (золотая рамка). Может совпадать с `state == SELECTED`
## для обычного предмета; для предмета с требованиями/замком рисуется поверх.
@export var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

## Надет ли предмет (золотой маркер, DESIGN §6.2).
@export var equipped: bool = false:
	set(value):
		equipped = value
		queue_redraw()

## id предмета из `GameState.inventory` (пусто — пустая ячейка).
var item_id: StringName = &""
## Читаемое имя для подсказки/тестов.
var item_name: String = ""
## «НЕТ · ещё N» / «ЕСТЬ» / пусто (DESIGN §6.2, AC-08.2).
var requirement_summary: String = ""
## Причина недоступности (замок): способность не открыта и т.п.
var unavailable_reason: String = ""
## Подпись слота экипировки для пустой ячейки («ШЛЕМ», «КОЛЬЦО 1»).
var slot_hint: String = ""
## Вид процедурной иконки (арт-ассеты появятся позже): sword/axe/dagger/
## shield/helm/armor/ring/potion/herb/shard/charm/relic/misc.
var icon_kind: String = "misc"


func _draw() -> void:
	super._draw()
	if size.x <= 0.0 or size.y <= 0.0:
		return

	# Маркер «надет» — отдельно от состояния: он сохраняется и на выбранном,
	# и на предмете с невыполненными требованиями (DESIGN §6.2).
	if equipped:
		draw_rect(
			Rect2(Vector2(2, 2), Vector2(UITokens.RIVET_SIZE, UITokens.RIVET_SIZE)),
			UITokens.GOLD
		)

	# Выбор поверх требования/замка: золотая рамка + внутренняя gold-9.
	# Для обычного выбранного предмета это уже сделал `AshenSlot`.
	if selected and state != State.SELECTED:
		var rect := Rect2(Vector2.ZERO, size)
		UIStyle.draw_frame(self, rect, UITokens.BORDER_SLOT, UITokens.GOLD)
		UIStyle.draw_frame(
			self,
			rect.grow(-float(UITokens.BORDER_SLOT)),
			UITokens.BORDER_INNER,
			UITokens.GOLD_9
		)


## Заполняет ячейку одним вызовом (используется экраном инвентаря).
func apply_item(
	new_item_id: StringName,
	new_item_name: String,
	new_state: State,
	is_equipped: bool,
	requirements_text: String,
	locked_reason: String = "",
	new_icon_kind: String = "misc"
) -> void:
	item_id = new_item_id
	item_name = new_item_name
	equipped = is_equipped
	requirement_summary = requirements_text
	unavailable_reason = locked_reason
	icon_kind = new_icon_kind
	state = new_state
	_update_tooltip()


## Строковое имя состояния — для тестов/QA и читаемых assert'ов.
func get_state_name() -> String:
	match state:
		State.SELECTED:
			return "selected"
		State.EQUIPPED:
			return "equipped"
		State.UNAVAILABLE:
			return "unavailable"
		State.EMPTY:
			return "empty"
		State.REQUIREMENTS:
			return "requirements"
		_:
			return "normal"


func is_selected() -> bool:
	return selected or state == State.SELECTED


func is_requirement_blocked() -> bool:
	return state == State.REQUIREMENTS


func is_locked() -> bool:
	return state == State.UNAVAILABLE


## Маркер «надет» рисуется золотым квадратом (DESIGN §6.2) — и для состояния
## EQUIPPED, и для независимого флага.
func has_equipped_marker() -> bool:
	return equipped or super.has_equipped_marker()


func get_equipped_marker_color() -> Color:
	return UITokens.GOLD


## Снимок визуального состояния для GUT/QA.
func get_visual_state() -> Dictionary:
	return {
		"state": get_state_name(),
		"selected": is_selected(),
		"equipped": has_equipped_marker(),
		"requirements": has_requirement_marker(),
		"locked": has_lock_marker(),
		"empty": is_empty(),
		"item_id": item_id,
		"requirement_summary": requirement_summary,
	}


## Процедурные иконки 12×12 до появления `assets/sprites/items/*`. Формы
## различаются силуэтом, поэтому сетку можно читать без цвета (DESIGN §9.1).
func _draw_icon(inner: Rect2) -> void:
	if item_icon != null or icon_kind == "misc":
		super._draw_icon(inner)
		return
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	var alpha: float = 1.0
	if state == State.UNAVAILABLE:
		alpha = 0.45
	elif state == State.REQUIREMENTS:
		alpha = 0.55
	var icon_size: float = float(UITokens.ICON)
	var origin: Vector2 = (
		inner.position + (inner.size - Vector2(icon_size, icon_size)) * 0.5
	)
	var p: Vector2 = origin

	match icon_kind:
		"sword":
			_rect(p + Vector2(5, 0), Vector2(2, 7), UITokens.STEEL_3, alpha)
			_rect(p + Vector2(3, 6), Vector2(6, 1), UITokens.GOLD_9, alpha)
			_rect(p + Vector2(5, 7), Vector2(2, 3), UITokens.BROWN_3, alpha)
			_rect(p + Vector2(4, 10), Vector2(4, 1), UITokens.STONE_5, alpha)
		"axe":
			_rect(p + Vector2(5, 1), Vector2(2, 10), UITokens.BROWN_3, alpha)
			_rect(p + Vector2(2, 1), Vector2(4, 4), UITokens.STEEL_3, alpha)
			_rect(p + Vector2(6, 2), Vector2(2, 2), UITokens.STEEL_3, alpha)
			_rect(p + Vector2(2, 1), Vector2(1, 4), UITokens.BONE, alpha)
		"dagger":
			_rect(p + Vector2(5, 2), Vector2(2, 5), UITokens.STEEL_3, alpha)
			_rect(p + Vector2(4, 6), Vector2(4, 1), UITokens.GOLD_9, alpha)
			_rect(p + Vector2(5, 7), Vector2(2, 3), UITokens.BROWN_3, alpha)
		"shield":
			UIStyle.draw_frame(
				self,
				Rect2(p + Vector2(2, 1), Vector2(8, 10)),
				1,
				_icon_color(UITokens.STEEL_3, alpha)
			)
			_rect(p + Vector2(4, 3), Vector2(4, 6), UITokens.STEEL_9, alpha)
			_rect(p + Vector2(5, 5), Vector2(2, 2), UITokens.GOLD_9, alpha)
		"helm":
			_rect(p + Vector2(3, 2), Vector2(6, 4), UITokens.STONE_5, alpha)
			_rect(p + Vector2(2, 6), Vector2(8, 2), UITokens.STEEL_9, alpha)
			_rect(p + Vector2(4, 4), Vector2(4, 1), UITokens.VOID, alpha)
		"armor":
			_rect(p + Vector2(2, 2), Vector2(8, 2), UITokens.STEEL_9, alpha)
			_rect(p + Vector2(4, 3), Vector2(4, 7), UITokens.STEEL_3, alpha)
			_rect(p + Vector2(3, 8), Vector2(6, 1), UITokens.GOLD_9, alpha)
		"ring":
			_rect(p + Vector2(4, 2), Vector2(4, 1), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(4, 9), Vector2(4, 1), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(2, 4), Vector2(1, 4), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(9, 4), Vector2(1, 4), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(3, 3), Vector2(1, 1), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(8, 3), Vector2(1, 1), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(3, 8), Vector2(1, 1), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(8, 8), Vector2(1, 1), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(5, 5), Vector2(2, 2), UITokens.BLOOD_3, alpha)
		"potion":
			_rect(p + Vector2(5, 0), Vector2(2, 1), UITokens.BROWN_3, alpha)
			_rect(p + Vector2(5, 1), Vector2(2, 2), UITokens.BONE, alpha)
			UIStyle.draw_frame(
				self,
				Rect2(p + Vector2(3, 3), Vector2(6, 8)),
				1,
				_icon_color(UITokens.BONE, alpha)
			)
			_rect(p + Vector2(4, 5), Vector2(4, 5), UITokens.BLOOD_3, alpha)
		"herb":
			_rect(p + Vector2(6, 3), Vector2(1, 8), UITokens.GREEN_3, alpha)
			_rect(p + Vector2(3, 3), Vector2(3, 2), UITokens.GREEN_3, alpha)
			_rect(p + Vector2(6, 2), Vector2(3, 2), UITokens.GREEN_3, alpha)
			_rect(p + Vector2(3, 6), Vector2(2, 2), UITokens.GREEN_3, alpha)
			_rect(p + Vector2(7, 6), Vector2(2, 2), UITokens.GREEN_3, alpha)
			_rect(p + Vector2(5, 8), Vector2(2, 2), UITokens.BLOOD_3, alpha)
		"shard":
			_rect(p + Vector2(5, 1), Vector2(2, 2), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(4, 3), Vector2(4, 2), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(3, 5), Vector2(6, 2), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(4, 7), Vector2(4, 2), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(5, 9), Vector2(2, 2), UITokens.GOLD_3, alpha)
			_rect(p + Vector2(5, 3), Vector2(1, 3), UITokens.GOLD, alpha)
		"charm":
			_rect(p + Vector2(4, 2), Vector2(4, 2), UITokens.BONE, alpha)
			_rect(p + Vector2(5, 4), Vector2(2, 5), UITokens.BONE, alpha)
			_rect(p + Vector2(3, 5), Vector2(2, 2), UITokens.BONE, alpha)
			_rect(p + Vector2(7, 5), Vector2(2, 2), UITokens.BONE, alpha)
			_rect(p + Vector2(4, 3), Vector2(1, 1), UITokens.VOID, alpha)
			_rect(p + Vector2(7, 3), Vector2(1, 1), UITokens.VOID, alpha)
		"relic":
			UIStyle.draw_frame(
				self,
				Rect2(p + Vector2(2, 2), Vector2(8, 8)),
				1,
				_icon_color(UITokens.GOLD_9, alpha)
			)
			_rect(p + Vector2(3, 3), Vector2(6, 6), UITokens.BLOOD_9, alpha)
			_rect(p + Vector2(5, 5), Vector2(2, 2), UITokens.GOLD, alpha)
			_rect(p + Vector2(3, 5), Vector2(6, 1), UITokens.GOLD_9, alpha)
		_:
			super._draw_icon(inner)


func _rect(pos: Vector2, rect_size: Vector2, color: Color, alpha: float) -> void:
	draw_rect(Rect2(pos, rect_size), _icon_color(color, alpha))


func _icon_color(color: Color, alpha: float) -> Color:
	return Color(color, alpha)


func _update_tooltip() -> void:
	var parts: Array[String] = []
	if item_name != "":
		parts.append(item_name)
	elif slot_hint != "" and state == State.EMPTY:
		parts.append(tr("ui.inv.slot_empty_short") % slot_hint)
	if requirement_summary != "":
		parts.append(requirement_summary)
	if unavailable_reason != "":
		parts.append(unavailable_reason)
	if parts.is_empty():
		super._update_tooltip()
		return
	tooltip_text = " · ".join(parts)
