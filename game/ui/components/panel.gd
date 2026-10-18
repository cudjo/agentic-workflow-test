class_name AshenPanel
extends PanelContainer
## AshenPanel — 9-slice панель (DESIGN §5, §6).
##
## Варианты: solid (фон night-9), glass (фон void 82%), inset (вставка void,
## без заклёпок), danger (рамка blood-3 + заклёпки blood-3).
## Рамка: внешняя stone-3 2 px, внутренняя void 1 px + stone-9 1 px,
## угловые «заклёпки» 3×3 gold-9 (DESIGN §4.3).
##
## Панель — чистый контейнер: не интерактивна, не забирает фокус.

@export_enum("solid", "glass", "inset", "danger") var variant: int = 0:
	set(value):
		variant = clampi(value, 0, 3)
		_apply_style()

## Внутренний отступ от рамки: 6 px по умолчанию, 8 px для меню/диалога.
@export var padding: int = UITokens.PANEL_PADDING:
	set(value):
		padding = maxi(0, value)
		_apply_style()

## Отдельные отступы (нужны тостам: 12 px по горизонтали, 6 px по вертикали).
@export var padding_horizontal: int = -1:
	set(value):
		padding_horizontal = value
		_apply_style()

@export var padding_vertical: int = -1:
	set(value):
		padding_vertical = value
		_apply_style()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_style()


func _ready() -> void:
	_apply_style()


## Возвращает StyleBox 9-slice, собранный из токенов (для тестов/a11y-аудита).
func get_panel_style() -> StyleBoxTexture:
	return get_theme_stylebox("panel") as StyleBoxTexture


## true для варианта с заклёпками (inset их не рисует — DESIGN §4.3).
func has_rivets() -> bool:
	return variant != UIStyle.PanelVariant.INSET


func get_variant_name() -> String:
	return ["solid", "glass", "inset", "danger"][variant]


func _apply_style() -> void:
	add_theme_stylebox_override(
		"panel",
		UIStyle.panel_style(variant, padding, padding_horizontal, padding_vertical)
	)
