extends CanvasLayer
## Туман болота (T-15): низкая видимость в зоне 2 «Болото».
##
## Дешёвый программный эффект без шейдеров и партиклов: 2 полупрозрачных
## покрывала (steel-9) + 5 дрейфующих мягких клубов (радиальный градиент).
## Слой 4 — выше мира (0) и Foreground, ниже HUD (10) и баннера (15),
## поэтому интерфейс остаётся читаемым. Ввод не перехватывается.
##
## Бюджет: 7 узлов, никаких аллокаций в _process — только сдвиг позиций.
## Полноценный перф-пасс с рендером — T-37 (здесь headless-замер).

const VIEW_WIDTH := 480.0
const VIEW_HEIGHT := 270.0
const FOG_LAYER := 4
const BAND_COUNT := 5

@export var tint: Color = Color("#2f4350")
@export var drift_speed: float = 7.0
@export var veil_alpha: float = 0.07
@export var band_alpha: float = 0.12

var _bands: Array[TextureRect] = []
var _band_base_x: Array[float] = []
var _band_phase: Array[float] = []
var _band_speed: Array[float] = []
var _time: float = 0.0


func _ready() -> void:
	layer = FOG_LAYER
	_build()


func _process(delta: float) -> void:
	_time += delta
	for index in _bands.size():
		var band := _bands[index]
		var width := band.size.x
		var travel := _band_base_x[index] + _time * drift_speed * _band_speed[index]
		travel += sin(_time * 0.7 + _band_phase[index]) * 18.0
		band.position.x = fposmod(travel, VIEW_WIDTH + width) - width


## Количество полос тумана (для тестов и настройки).
func get_band_count() -> int:
	return _bands.size()


## Текущий x полосы — тестам нужен факт дрейфа, а не конкретная реализация.
func get_band_x(index: int) -> float:
	if index < 0 or index >= _bands.size():
		return 0.0
	return _bands[index].position.x


func _build() -> void:
	var veil_top := _make_veil("VeilTop", Vector2(0.0, 0.0), Vector2(VIEW_WIDTH, VIEW_HEIGHT * 0.62))
	veil_top.color = Color(tint, veil_alpha)
	var veil_bottom := _make_veil("VeilBottom", Vector2(0.0, VIEW_HEIGHT * 0.45), Vector2(VIEW_WIDTH, VIEW_HEIGHT * 0.55))
	veil_bottom.color = Color(tint, veil_alpha * 1.4)

	var texture := _make_fog_texture()
	var heights := [52.0, 64.0, 76.0, 48.0, 68.0]
	var widths := [320.0, 400.0, 440.0, 280.0, 360.0]
	for index in BAND_COUNT:
		var y := 38.0 + float(index) * 42.0
		var band := TextureRect.new()
		band.name = "FogBand%d" % index
		band.texture = texture
		band.position = Vector2(-float(index) * 90.0, y)
		band.size = Vector2(widths[index], heights[index])
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		band.stretch_mode = TextureRect.STRETCH_SCALE
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.modulate = Color(tint, band_alpha + float(index % 3) * 0.015)
		add_child(band)
		_bands.append(band)
		_band_base_x.append(-float(index) * 90.0)
		_band_phase.append(float(index) * 1.37)
		_band_speed.append(0.6 + float(index) * 0.12)


func _make_veil(rect_name: String, at: Vector2, size: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = rect_name
	rect.position = at
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


func _make_fog_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.width = 128
	texture.height = 48
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
