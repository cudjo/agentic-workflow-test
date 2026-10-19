class_name EnemyOutlineSprite
extends Sprite2D
## Контур врага в режиме «Читаемость силуэтов» (Fix-3a/N4, DESIGN §9.1).
##
## Скрипт висит на `Enemy/Visual`, поэтому контурный материал применяется к
## тому же спрайту, что и тело врага, а не к CharacterBody2D. Тумблер общий с
## героем — `Config.silhouette_readability` (T-35). QA/интеграция находят
## `is_silhouette_outline_enabled()` на потомке Enemy (как у PlayerAnimation).

var _outline_material: ShaderMaterial


func _ready() -> void:
	_outline_material = SilhouetteOutline.create_material()
	material = _outline_material
	if not Config.visual_accessibility_changed.is_connected(_apply_outline):
		Config.visual_accessibility_changed.connect(_apply_outline)
	_apply_outline()


func _exit_tree() -> void:
	if Config.visual_accessibility_changed.is_connected(_apply_outline):
		Config.visual_accessibility_changed.disconnect(_apply_outline)


func get_outline_material() -> ShaderMaterial:
	return _outline_material


func is_silhouette_outline_enabled() -> bool:
	return SilhouetteOutline.is_enabled(_outline_material)


func _apply_outline() -> void:
	SilhouetteOutline.set_enabled(_outline_material, Config.silhouette_readability)
