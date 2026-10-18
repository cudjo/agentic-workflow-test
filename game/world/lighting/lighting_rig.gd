class_name LightingRig
extends Node2D
## LightingRig — слой освещения зоны (T-35, PLAN §3.6, DESIGN §4.4/§8.7).
##
## Состав:
##   * `PostProcess` (CanvasLayer 2) — ColorRect с `posterize.gdshader`:
##     постеризация 6–8 ступеней, дизеринг Байера 4×4, виньетка;
##   * `Emissive` (CanvasLayer 1) — эмиссивные ядра (`EmissiveGlow`): пламя,
##     окна, костёр. Отдельный canvas не затемняется CanvasModulate зоны;
##   * flicker зарегистрированных PointLight2D (3 кадра × 140 мс, ±5 %).
##
## Z-order DESIGN §4.4: мир (canvas 0) → эмиссивные/свет (1) → пост-обработка
## освещения (2) → HUD (10) → меню (20) → тосты (30) → overlay (40).
## Ambient зоны остаётся на CanvasModulate T-13/T-16; меню получает собственный
## CanvasModulate 0.78 (создаётся только в menu-профиле).
##
## Режимы:
##   * `Config.silhouette_readability` — виньетка 0 (контур включает
##     `silhouette_outline.gdshader` на визуале игрока);
##   * `Config.no_flash` — мерцание света выключено (множитель 1.0).

const POSTERIZE_SHADER: Shader = preload("res://assets/shaders/posterize.gdshader")

## DESIGN §4.4: освещение выше мира, но ниже HUD=10.
const EMISSIVE_LAYER: int = 1
const POST_LAYER: int = 2
const HUD_LAYER: int = 10

## Тёплые источники получают эмиссивное ядро; луна/холодный свет — только Light2D.
const WARM_EMISSIVE_MAX_RADIUS: float = 100.0
const EMISSIVE_RADIUS_SCALE: float = 0.35
const EMISSIVE_MIN_RADIUS: float = 12.0

## Профиль освещения; задаётся до `add_child` (ZoneScene/меню).
@export var profile: LightingProfile
## Автоматически подхватывать `Lights/PointLight2D` и создавать эмиссивные ядра.
@export var auto_register_zone_lights: bool = true

var _post_layer: CanvasLayer
var _emissive_layer: CanvasLayer
var _screen: ColorRect
var _ambient: CanvasModulate
var _lights: Array[PointLight2D] = []
var _base_energy: Array[float] = []
var _time: float = 0.0


func _ready() -> void:
	_ensure_layer_nodes()
	if profile == null:
		profile = LightingProfile.new()
	_ensure_menu_ambient()
	if auto_register_zone_lights:
		_register_scene_lights()
		_spawn_scene_emissives()
	_apply_profile()
	var config := _config()
	if config != null and config.has_signal(&"visual_accessibility_changed"):
		if not config.visual_accessibility_changed.is_connected(_on_visual_settings_changed):
			config.visual_accessibility_changed.connect(_on_visual_settings_changed)


func _process(delta: float) -> void:
	tick(delta)


# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

## Один шаг мерцания; публичный для детерминированных тестов.
func tick(delta: float) -> void:
	_time += maxf(delta, 0.0)
	var multiplier: float = flicker_multiplier(_time)
	for index in _lights.size():
		var light: PointLight2D = _lights[index]
		if is_instance_valid(light):
			light.energy = _base_energy[index] * multiplier


## Множитель энергии/радиуса света: 1.0/1.05/0.95; no_flash → 1.0.
func flicker_multiplier(at_time: float) -> float:
	return LightingProfile.flame_multiplier(at_time, _is_no_flash())


## Регистрирует PointLight2D для мерцания (базовая энергия — текущая).
func register_light(light: PointLight2D, base_energy: float = -1.0) -> void:
	if light == null or _lights.has(light):
		return
	_lights.append(light)
	_base_energy.append(base_energy if base_energy >= 0.0 else light.energy)


## Добавляет эмиссивный CanvasItem на отдельный слой (не затемняется ambient).
func add_emissive(item: CanvasItem, keep_global_transform: bool = true) -> void:
	if item == null:
		return
	if item.get_parent() != null:
		item.reparent(_emissive_layer, keep_global_transform)
	else:
		_emissive_layer.add_child(item)


## Создаёт эмиссивное ядро (пламя/окно) на слое 1.
func spawn_emissive_glow(
	at: Vector2,
	color: Color,
	radius: float,
	flicker: bool = true
) -> EmissiveGlow:
	var glow := EmissiveGlow.new()
	glow.name = "Glow"
	glow.configure(color, maxf(radius, EMISSIVE_MIN_RADIUS), flicker)
	_emissive_layer.add_child(glow)
	glow.position = at - Vector2(glow.radius_px, glow.radius_px)
	return glow


func get_post_layer() -> CanvasLayer:
	return _post_layer


func get_emissive_layer() -> CanvasLayer:
	return _emissive_layer


func get_post_material() -> ShaderMaterial:
	if _screen == null:
		return null
	return _screen.material as ShaderMaterial


## Итоговая сила виньетки с учётом a11y-режима (0 — виньетки нет).
func get_vignette_strength() -> float:
	if profile == null:
		return 0.0
	if _is_silhouette_readability():
		return 0.0
	return profile.vignette_strength()


func is_vignette_active() -> bool:
	return get_vignette_strength() > 0.0


## Ambient меню/зоны (для тестов и экранов без ZoneScene).
func get_ambient_level() -> float:
	if _ambient != null:
		return _ambient.color.r
	return profile.effective_ambient() if profile != null else 0.0


func get_registered_light_count() -> int:
	return _lights.size()


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _ensure_layer_nodes() -> void:
	_emissive_layer = get_node_or_null("Emissive") as CanvasLayer
	if _emissive_layer == null:
		_emissive_layer = CanvasLayer.new()
		_emissive_layer.name = "Emissive"
		add_child(_emissive_layer)
	_emissive_layer.layer = EMISSIVE_LAYER

	_post_layer = get_node_or_null("PostProcess") as CanvasLayer
	if _post_layer == null:
		_post_layer = CanvasLayer.new()
		_post_layer.name = "PostProcess"
		add_child(_post_layer)
		_screen = ColorRect.new()
		_screen.name = "Screen"
		_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen.color = Color.WHITE
		var shader_material := ShaderMaterial.new()
		shader_material.shader = POSTERIZE_SHADER
		_screen.material = shader_material
		_post_layer.add_child(_screen)
		_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		_screen = _post_layer.get_node_or_null("Screen") as ColorRect
	_post_layer.layer = POST_LAYER


func _ensure_menu_ambient() -> void:
	if profile == null or not profile.menu_mode:
		return
	_ambient = get_node_or_null("Ambient") as CanvasModulate
	if _ambient == null:
		_ambient = CanvasModulate.new()
		_ambient.name = "Ambient"
		add_child(_ambient)
	var level: float = profile.effective_ambient()
	_ambient.color = Color(level, level, level, 1.0)


func _apply_profile() -> void:
	if profile == null:
		return
	var shader_material := get_post_material()
	if shader_material != null:
		shader_material.set_shader_parameter(&"levels", profile.effective_levels())
		shader_material.set_shader_parameter(&"dither_strength", profile.dither_strength)
		shader_material.set_shader_parameter(&"vignette_strength", get_vignette_strength())
		shader_material.set_shader_parameter(&"warmth_amount", 0.08)
	if _ambient != null:
		var level: float = profile.effective_ambient()
		_ambient.color = Color(level, level, level, 1.0)


func _register_scene_lights() -> void:
	var lights_root: Node = null
	if get_parent() != null:
		lights_root = get_parent().get_node_or_null("Lights")
	if lights_root == null:
		return
	for child: Node in lights_root.get_children():
		var light := child as PointLight2D
		if light != null:
			register_light(light)


## Тёплые локальные источники (факелы/окна/костёр) получают видимое ядро.
func _spawn_scene_emissives() -> void:
	var lights_root: Node = null
	if get_parent() != null:
		lights_root = get_parent().get_node_or_null("Lights")
	if lights_root == null:
		return
	for child: Node in lights_root.get_children():
		var light := child as PointLight2D
		if light == null:
			continue
		if light.color.r < light.color.b:
			continue
		var radius: float = float(light.get_meta(&"radius_px", EmissiveGlow.DEFAULT_RADIUS))
		if radius > WARM_EMISSIVE_MAX_RADIUS:
			continue
		var glow_radius: float = maxf(radius * EMISSIVE_RADIUS_SCALE, EMISSIVE_MIN_RADIUS)
		spawn_emissive_glow(light.position, light.color, glow_radius, true)


func _on_visual_settings_changed() -> void:
	_apply_profile()


func _config() -> Node:
	return get_node_or_null("/root/Config")


func _is_no_flash() -> bool:
	var config := _config()
	return config != null and bool(config.get("no_flash"))


func _is_silhouette_readability() -> bool:
	var config := _config()
	return config != null and bool(config.get("silhouette_readability"))
