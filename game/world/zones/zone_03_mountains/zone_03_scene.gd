extends ZoneScene
## Корень зоны 3 «Горный перевал» (T-15).
##
## Наследует контракт ZoneScene (T-13) и поправляет одну деталь палитры:
## accent зоны 3 — холодный steel-3 (уступы/лёд), но пламя костра остаётся
## тёплым gold-3, иначе чекпоинт не читается как огонь (DESIGN §8.6).

func _apply_zone_data() -> void:
	super._apply_zone_data()
	var bonfire := get_node_or_null("Props/Bonfire") as Bonfire
	if bonfire != null:
		bonfire.flame_color = UITokens.GOLD_3
