class_name ZoneParallax
extends Node2D
## Параллакс гор и ветра зоны 3 «Горный перевал» (T-15, DESIGN §8.6).
##
## Три слоя хребтов двигаются с разной скоростью относительно камеры
## (scroll_factors 0.08 / 0.18 / 0.32). Если камеры нет (headless, редактор),
## слои живут лёгким «дыханием» ветра — сцена не выглядит статичной.
##
## Поверх рисуются штрихи ветра: 18 коротких линий, позиция которых зависит
## только от времени. Бюджет: один _draw за кадр, без аллокаций в _process;
## полноценный перф-пасс — T-37.

const VIEW_WIDTH := 480.0
const VIEW_HEIGHT := 270.0
const HORIZON := 200.0
const WIND_STREAK_COUNT := 18

@export var scroll_factors: Array[float] = [0.08, 0.18, 0.32]
@export var wind_speed: float = 26.0

var _camera_shift: Vector2 = Vector2.ZERO
var _wind_time: float = 0.0
var _streaks: Array[Vector2] = []


func _ready() -> void:
	_build_streaks()
	queue_redraw()


func _process(delta: float) -> void:
	_wind_time += delta
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		_camera_shift = camera.global_position - Vector2(VIEW_WIDTH, VIEW_HEIGHT) * 0.5
	else:
		# Без камеры — едва заметный ветровой дрейф, чтобы слои не были мёртвыми.
		_camera_shift = Vector2(sin(_wind_time * 0.11) * 2.0, 0.0)
	queue_redraw()


func _draw() -> void:
	_draw_sky()
	_draw_moon()
	_draw_ridge(0, 150.0, 38.0, 0.030, 0.4, UITokens.NIGHT_3, true)
	_draw_ridge(1, 170.0, 28.0, 0.045, 1.7, UITokens.STEEL_9, true)
	_draw_ridge(2, 188.0, 18.0, 0.062, 3.1, UITokens.STONE_9, true)
	_draw_wind()


## Смещение слоя parallax для текущей камеры (px). Публично — для тестов.
func layer_offset(layer_index: int) -> Vector2:
	if scroll_factors.is_empty():
		return Vector2.ZERO
	var factor := scroll_factors[clampi(layer_index, 0, scroll_factors.size() - 1)]
	return _camera_shift * factor


## Накопленное время ветра: тест проверяет, что анимация живёт.
func get_wind_time() -> float:
	return _wind_time


func _draw_sky() -> void:
	var bands: Array[Color] = [UITokens.NIGHT_9, UITokens.NIGHT, UITokens.NIGHT_3]
	var band_height := HORIZON / float(bands.size())
	for index in bands.size():
		draw_rect(
			Rect2(0.0, band_height * index, VIEW_WIDTH, band_height + 1.0),
			bands[index]
		)


func _draw_moon() -> void:
	# Холодная луна (steel-3), параллакс дальнего слоя.
	var offset := layer_offset(0)
	var center := Vector2(388.0, 44.0) + offset * 0.4
	draw_circle(center, 12.0, Color(UITokens.STEEL_9, 0.55))
	draw_circle(center, 8.0, UITokens.BONE)
	draw_circle(center + Vector2(3.0, -2.0), 6.0, UITokens.NIGHT_9)
	draw_rect(Rect2(center.x - 4.0, center.y + 3.0, 3.0, 1.0), UITokens.STONE_5)


func _draw_ridge(
	layer_index: int,
	base_y: float,
	amplitude: float,
	frequency: float,
	phase: float,
	color: Color,
	snow: bool
) -> void:
	var offset := layer_offset(layer_index).x
	for x in range(0, int(VIEW_WIDTH), 2):
		var top := base_y - amplitude * (0.5 + 0.5 * sin((float(x) + offset) * frequency + phase))
		draw_rect(Rect2(float(x), top, 2.0, HORIZON - top), color)
		if snow and layer_index > 0:
			# Непрерывная снеговая кромка: 1 px, а не «пунктир» из точек.
			var snow_color := UITokens.BONE if layer_index == 2 else UITokens.STONE_5
			draw_rect(Rect2(float(x), top, 2.0, 1.0), snow_color)
			if layer_index == 2 and _hash(x + layer_index * 31, layer_index + 7) > 0.86:
				draw_rect(Rect2(float(x), top + 1.0, 2.0, 1.0), UITokens.STONE_5)
		# Скальная тень у основания хребта.
		if int(top) % 9 == 0:
			draw_rect(Rect2(float(x), top + 6.0, 1.0, 4.0), UITokens.NIGHT_9)


func _draw_wind() -> void:
	var span := VIEW_WIDTH + 40.0
	for index in _streaks.size():
		var seed := _streaks[index]
		var speed := 0.6 + seed.y
		var x := fposmod(seed.x + _wind_time * wind_speed * speed, span) - 20.0
		var y := 26.0 + seed.y * 118.0 + sin(_wind_time * 1.3 + seed.x) * 2.0
		var length := 6.0 + seed.y * 9.0
		draw_line(Vector2(x, y), Vector2(x - length, y - 1.0), Color(UITokens.STEEL_3, 0.35), 1.0)
		if index % 5 == 0:
			draw_rect(Rect2(x + 2.0, y - 2.0, 1.0, 1.0), Color(UITokens.BONE, 0.5))


func _build_streaks() -> void:
	for index in WIND_STREAK_COUNT:
		var x := _hash(index, 101) * VIEW_WIDTH
		var y := 0.15 + _hash(index, 103) * 0.8
		_streaks.append(Vector2(x, y))


func _hash(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0
