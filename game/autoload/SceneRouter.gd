extends Node
## SceneRouter — переходы между зонами и экран загрузки (T-17).
## Заглушка каркаса (T-01): загрузка сцены зоны ≤3 с, сохранение позиции по точкам входа,
## ввод игнорируется до конца загрузки (EC-12). Реализация — задача T-17.
##
## T-13: минимальный контракт загрузки шаблона зоны. Полные переходы, экран загрузки
## и управление WorldRoot остаются за T-17; здесь только проверка совместимости сцены.

## Загружает и инстанцирует сцену зоны, совместимую с WorldRoot (PLAN §2.3).
## Корень обязан быть ZoneScene с заполненным ZoneData. В дерево не добавляет —
## размещением в Main.WorldRoot управляет T-17.
## Возвращает null (и пишет ошибку) при нарушении контракта.
func instantiate_zone(scene_path: String) -> ZoneScene:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("SceneRouter: не удалось загрузить сцену зоны '%s'" % scene_path)
		return null

	var instance := packed.instantiate()
	if not instance is ZoneScene:
		push_error("SceneRouter: корень зоны '%s' должен быть ZoneScene (Node2D)" % scene_path)
		instance.free()
		return null

	var zone := instance as ZoneScene
	if zone.zone_data == null:
		push_error("SceneRouter: у сцены зоны '%s' не задан zone_data" % scene_path)
		zone.free()
		return null
	return zone
