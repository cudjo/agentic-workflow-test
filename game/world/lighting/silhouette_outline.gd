class_name SilhouetteOutline
extends RefCounted
## Фабрика материала контура героя (T-35, DESIGN §9.1, AC-07.1).
##
## `silhouette_outline.gdshader` на AnimatedSprite2D игрока: в обычном режиме —
## слабый rim-light, в режиме «Читаемость силуэтов» — 1-px контур bone 60 %.
## Материал общий для всех кадров/анимаций.

const SHADER: Shader = preload("res://assets/shaders/silhouette_outline.gdshader")
const OUTLINE_ALPHA: float = 0.6
const DEFAULT_RIM_STRENGTH: float = 0.15


## Создаёт материал с выключенным контуром (обычный режим).
static func create_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"enabled", false)
	material.set_shader_parameter(&"outline_color", Color(UITokens.BONE, OUTLINE_ALPHA))
	material.set_shader_parameter(&"outline_width", 1.0)
	material.set_shader_parameter(&"rim_strength", DEFAULT_RIM_STRENGTH)
	return material


## Включает/выключает контур (a11y-режим).
static func set_enabled(material: ShaderMaterial, enabled: bool) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"enabled", enabled)


static func is_enabled(material: ShaderMaterial) -> bool:
	if material == null:
		return false
	return bool(material.get_shader_parameter(&"enabled"))
