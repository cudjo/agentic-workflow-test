extends ZoneScene
## Корень зоны 4 «Руины-храм» (T-16, DESIGN §8.6, PLAN §3.6).
##
## Наследует контракт ZoneScene (T-13). Единственная поправка — тёплый
## жёлто-красный ambient: `ZoneData.ambient_level` (0.26 — «внутри руин у
## костра», DESIGN §8.7) остаётся базой, но CanvasModulate получает тёплый
## сдвиг. Это и есть «приглушённый жёлтый/красный отсвет» зоны 4; точечные
## источники (`Lights/Bonfire`, `Lights/AltarGlow`) добавляют локальные
## пятна огня. Гнетущая тишина — источников ровно два, без «гирлянд».

## Тёплый сдвиг ambient: R > G > B, база — ambient_level.
const WARM_SHIFT := Vector3(1.15, 0.82, 0.58)


func _apply_zone_data() -> void:
	super._apply_zone_data()
	if zone_data == null:
		return
	var level := zone_data.ambient_level
	ambient.color = Color(
		clampf(level * WARM_SHIFT.x, 0.0, 1.0),
		clampf(level * WARM_SHIFT.y, 0.0, 1.0),
		clampf(level * WARM_SHIFT.z, 0.0, 1.0),
		1.0
	)
