class_name EmissiveGlow
extends ColorRect
## Эмиссивное ядро источника (T-35, DESIGN §8.7): пламя факела, тёплое окно,
## костёр. Рисуется `dither_light.gdshader` — ступенчатый радиальный спад с
## дизерингом Байера 4×4, без гладких градиентов/неона.
##
## Живёт на CanvasLayer освещения (`LightingRig.emissive_layer`) — отдельный
## canvas, поэтому CanvasModulate зоны его не затемняет.
##
## Мерцание: 3 кадра × 140 мс, радиус ±5 % (DESIGN §4.5). В режиме
## `Config.no_flash` мерцание отключено (радиус постоянный).

const SHADER: Shader = preload("res://assets/shaders/dither_light.gdshader")
const DEFAULT_RADIUS: float = 46.0
const DEFAULT_STEPS: int = 6
const DEFAULT_INTENSITY: float = 0.45

## Цвет пламени/окна (gold/gold-3 из палитры зоны).
var glow_color: Color = Color("#e0b56a")
## Базовый радиус свечения в пикселях (DESIGN §8.6: факел ≈ 90 px).
var radius_px: float = DEFAULT_RADIUS
## Число ступеней квантования (6–8, DESIGN §8.7).
var steps: int = DEFAULT_STEPS
## Максимальная альфа свечения: низкая, чтобы не было «неона».
var intensity: float = DEFAULT_INTENSITY
## Мерцание разрешено (дополнительно гасится Config.no_flash).
var flicker_enabled: bool = true

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_ensure_material()
	_apply_params()


## Настраивает свечение до добавления в дерево (LightingRig).
func configure(color: Color, radius: float, flicker: bool = true) -> void:
	glow_color = color
	radius_px = maxf(radius, 1.0)
	flicker_enabled = flicker
	if is_inside_tree():
		_apply_params()


## Один шаг мерцания; публичный для детерминированных GUT-тестов.
func tick(delta: float) -> void:
	if flicker_enabled and not _is_no_flash():
		_time += maxf(delta, 0.0)
	else:
		_time = 0.0
	_apply_params()


func _process(delta: float) -> void:
	tick(delta)


## Текущий множитель радиуса (для тестов).
func get_flicker_multiplier() -> float:
	return LightingProfile.flame_multiplier(_time, _is_no_flash() or not flicker_enabled)


func get_glow_material() -> ShaderMaterial:
	return material as ShaderMaterial


func _ensure_material() -> void:
	if material is ShaderMaterial and (material as ShaderMaterial).shader == SHADER:
		return
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	material = shader_material


func _apply_params() -> void:
	var shader_material := get_glow_material()
	if shader_material == null:
		return
	var multiplier: float = get_flicker_multiplier()
	var effective_radius: float = radius_px * multiplier
	var side: float = effective_radius * 2.0
	size = Vector2(side, side)
	shader_material.set_shader_parameter(&"glow_color", glow_color)
	shader_material.set_shader_parameter(&"radius_px", effective_radius)
	shader_material.set_shader_parameter(&"size_px", Vector2(side, side))
	shader_material.set_shader_parameter(&"steps", LightingProfile.levels_for(steps))
	shader_material.set_shader_parameter(&"intensity", clampf(intensity, 0.0, 1.0))


func _is_no_flash() -> bool:
	var config := get_node_or_null("/root/Config")
	return config != null and bool(config.get("no_flash"))
