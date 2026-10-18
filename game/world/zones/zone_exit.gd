class_name ZoneExit
extends Resource
## Выход/связь зоны: прямоугольник-триггер и адрес перехода (target zone + entry).
## Данные используются ZoneScene (создаёт Area2D) и SceneRouter (T-17) при переходе.
##
## T-33: `required_ability` отмечает проход, закрытый способностью (AC-04.2).
## Это данные карты: маркер прохода рисуется, пока способность не получена.

@export var id: StringName = &"exit"
@export var position: Vector2 = Vector2.ZERO
@export var size: Vector2 = Vector2(16, 32)
@export var target_zone_id: StringName = &""
@export var target_entry_id: StringName = &""
## Пусто — проход открыт без способности.
@export var required_ability: StringName = &""
