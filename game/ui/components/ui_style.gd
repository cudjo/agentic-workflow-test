class_name UIStyle
extends RefCounted
## UIStyle — фабрика стилей и рисования для UI-компонентов.
##
## Единая точка, где токены UITokens превращаются в StyleBox/пиксельные
## примитивы. Компоненты не содержат «магических» цветов и размеров:
## всё приходит отсюда (DESIGN §4).
##
## Panel реализован как настоящий 9-slice: текстура 20×20 генерируется из
## токенов, маргины 6 px сохраняют рамку и заклёпки при любом размере.

enum PanelVariant { SOLID, GLASS, INSET, DANGER }

const PANEL_TEXTURE_SIZE := 16
const PANEL_MARGIN := 6

static var _theme: Theme
static var _font: Font
static var _font_size: int = UITokens.FONT_BODY
static var _empty_style: StyleBoxEmpty
static var _panel_textures: Dictionary = {}
static var _panel_base_styles: Dictionary = {}


# ------------------------------------------------------------------------------
# Тема и шрифт
# ------------------------------------------------------------------------------

static func theme() -> Theme:
	if _theme == null and ResourceLoader.exists(UITokens.THEME_PATH):
		_theme = load(UITokens.THEME_PATH) as Theme
	return _theme


## Шрифт темы (Press Start 2P + fallback Tiny5 для символов вроде ✓ □ ○ △).
static func font() -> Font:
	if _font == null:
		var th: Theme = theme()
		if th != null and th.default_font != null:
			_font = th.default_font
		else:
			_font = load(UITokens.FONT_PATH) as Font
	return _font


static func font_size() -> int:
	if _font_size == UITokens.FONT_BODY:
		var th: Theme = theme()
		if th != null and th.default_font_size > 0:
			_font_size = th.default_font_size
	return _font_size


static func text_width(text: String, size: int = UITokens.FONT_BODY) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func text_height(size: int = UITokens.FONT_BODY) -> float:
	return font().get_height(size)


static func baseline_y(size: int = UITokens.FONT_BODY) -> float:
	return font().get_ascent(size)


# ------------------------------------------------------------------------------
# Стили
# ------------------------------------------------------------------------------

static func empty_style() -> StyleBoxEmpty:
	if _empty_style == null:
		_empty_style = StyleBoxEmpty.new()
		_empty_style.content_margin_left = 0
		_empty_style.content_margin_top = 0
		_empty_style.content_margin_right = 0
		_empty_style.content_margin_bottom = 0
	return _empty_style


## Скрывает встроенную отрисовку Button: компоненты рисуют себя сами.
static func make_custom_button(button: Button) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(style_name, empty_style())
	button.add_theme_color_override("font_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_focus_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)


## 9-slice StyleBox панели. `padding` — внутренний отступ от рамки.
static func panel_style(
	variant: int,
	padding: int = UITokens.PANEL_PADDING,
	h_padding: int = -1,
	v_padding: int = -1
) -> StyleBoxTexture:
	var base: StyleBoxTexture = _panel_base_styles.get(variant)
	if base == null:
		base = StyleBoxTexture.new()
		base.texture = _panel_texture(variant)
		base.set_texture_margin_all(PANEL_MARGIN)
		base.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		base.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		_panel_base_styles[variant] = base

	var style: StyleBoxTexture = base.duplicate() as StyleBoxTexture
	var horizontal: int = padding if h_padding < 0 else h_padding
	var vertical: int = padding if v_padding < 0 else v_padding
	style.content_margin_left = float(PANEL_MARGIN + horizontal)
	style.content_margin_right = float(PANEL_MARGIN + horizontal)
	style.content_margin_top = float(PANEL_MARGIN + vertical)
	style.content_margin_bottom = float(PANEL_MARGIN + vertical)
	return style


## Текстура 9-slice: кольца void → stone-3 → void → stone-9 и заклёпки 3×3.
static func _panel_texture(variant: int) -> ImageTexture:
	if _panel_textures.has(variant):
		return _panel_textures[variant]

	var bg: Color = UITokens.NIGHT_9
	var border: Color = UITokens.STONE_3
	var inner: Color = UITokens.STONE_9
	var rivet: Color = UITokens.GOLD_9
	var with_rivets: bool = true

	match variant:
		PanelVariant.GLASS:
			bg = Color(UITokens.VOID, UITokens.GLASS_ALPHA)
		PanelVariant.INSET:
			bg = UITokens.VOID
			border = UITokens.STONE_9
			inner = UITokens.VOID
			with_rivets = false
		PanelVariant.DANGER:
			border = UITokens.BLOOD_3
			rivet = UITokens.BLOOD_3
		_:
			pass

	var image := Image.create(PANEL_TEXTURE_SIZE, PANEL_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in PANEL_TEXTURE_SIZE:
		for x in PANEL_TEXTURE_SIZE:
			var distance: int = mini(
				mini(x, y),
				mini(PANEL_TEXTURE_SIZE - 1 - x, PANEL_TEXTURE_SIZE - 1 - y)
			)
			var pixel: Color = bg
			if distance == 0:
				pixel = UITokens.VOID
			elif distance <= UITokens.BORDER_PANEL:
				pixel = border
			elif distance == UITokens.BORDER_PANEL + 1:
				pixel = UITokens.VOID
			elif distance == UITokens.BORDER_PANEL + 2:
				pixel = inner
			image.set_pixel(x, y, pixel)

	if with_rivets:
		var rivet_positions := [
			Vector2i(2, 2),
			Vector2i(PANEL_TEXTURE_SIZE - 2 - UITokens.RIVET_SIZE, 2),
			Vector2i(2, PANEL_TEXTURE_SIZE - 2 - UITokens.RIVET_SIZE),
			Vector2i(
				PANEL_TEXTURE_SIZE - 2 - UITokens.RIVET_SIZE,
				PANEL_TEXTURE_SIZE - 2 - UITokens.RIVET_SIZE
			),
		]
		for corner in rivet_positions:
			for ry in UITokens.RIVET_SIZE:
				for rx in UITokens.RIVET_SIZE:
					image.set_pixel(corner.x + rx, corner.y + ry, rivet)

	var texture := ImageTexture.create_from_image(image)
	_panel_textures[variant] = texture
	return texture


# ------------------------------------------------------------------------------
# Рисование
# ------------------------------------------------------------------------------

## Рисует строку шрифтом темы. `pos` — позиция baseline.
static func draw_text(
	canvas: CanvasItem,
	pos: Vector2,
	text: String,
	color: Color,
	size: int = UITokens.FONT_BODY,
	width: float = -1.0,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	shadow: bool = false
) -> void:
	if shadow:
		canvas.draw_string(font(), pos + Vector2(1, 1), text, align, width, size, UITokens.VOID)
	canvas.draw_string(font(), pos, text, align, width, size, color)


## Пиксельная рамка толщиной `thickness` внутри `rect` (без сглаживания).
static func draw_frame(canvas: CanvasItem, rect: Rect2, thickness: int, color: Color) -> void:
	if thickness <= 0:
		return
	var x: float = rect.position.x
	var y: float = rect.position.y
	var w: float = rect.size.x
	var h: float = rect.size.y
	var t: float = float(thickness)
	canvas.draw_rect(Rect2(x, y, w, t), color)
	canvas.draw_rect(Rect2(x, y + h - t, w, t), color)
	canvas.draw_rect(Rect2(x, y + t, t, h - t * 2.0), color)
	canvas.draw_rect(Rect2(x + w - t, y + t, t, h - t * 2.0), color)


## Пунктирная рамка (пустой слот, недоступная зона).
static func draw_dashed_frame(
	canvas: CanvasItem,
	rect: Rect2,
	thickness: int,
	color: Color,
	dash: int = 2,
	gap: int = 2
) -> void:
	var step: int = dash + gap
	var x: int = int(rect.position.x)
	var y: int = int(rect.position.y)
	var w: int = int(rect.size.x)
	var h: int = int(rect.size.y)
	var i: int = 0
	while i < w:
		var length: int = mini(dash, w - i)
		canvas.draw_rect(Rect2(x + i, y, length, thickness), color)
		canvas.draw_rect(Rect2(x + i, y + h - thickness, length, thickness), color)
		i += step
	i = 0
	while i < h:
		var length: int = mini(dash, h - i)
		canvas.draw_rect(Rect2(x, y + i, thickness, length), color)
		canvas.draw_rect(Rect2(x + w - thickness, y + i, thickness, length), color)
		i += step


## Уголковые скобки фокуса (форма, а не только цвет).
static func draw_focus_brackets(
	canvas: CanvasItem,
	rect: Rect2,
	color: Color,
	arm: int = 4,
	thickness: int = 2
) -> void:
	var x: float = rect.position.x
	var y: float = rect.position.y
	var w: float = rect.size.x
	var h: float = rect.size.y
	var a: float = float(arm)
	var t: float = float(thickness)
	# левый верх
	canvas.draw_rect(Rect2(x, y, a, t), color)
	canvas.draw_rect(Rect2(x, y, t, a), color)
	# правый верх
	canvas.draw_rect(Rect2(x + w - a, y, a, t), color)
	canvas.draw_rect(Rect2(x + w - t, y, t, a), color)
	# левый низ
	canvas.draw_rect(Rect2(x, y + h - t, a, t), color)
	canvas.draw_rect(Rect2(x, y + h - a, t, a), color)
	# правый низ
	canvas.draw_rect(Rect2(x + w - a, y + h - t, a, t), color)
	canvas.draw_rect(Rect2(x + w - t, y + h - a, t, a), color)


## Галочка (успех) — 12×12, рисуется пикселями.
static func draw_check(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var p: Vector2 = rect.position
	canvas.draw_rect(Rect2(p + Vector2(2, 6), Vector2(2, 2)), color)
	canvas.draw_rect(Rect2(p + Vector2(4, 8), Vector2(2, 2)), color)
	canvas.draw_rect(Rect2(p + Vector2(6, 6), Vector2(2, 2)), color)
	canvas.draw_rect(Rect2(p + Vector2(8, 4), Vector2(2, 2)), color)
	canvas.draw_rect(Rect2(p + Vector2(6, 4), Vector2(2, 2)), color)
	canvas.draw_rect(Rect2(p + Vector2(8, 2), Vector2(2, 2)), color)


## Замок — 9×10: дужка + корпус (недоступный слот/способность).
static func draw_lock(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var p: Vector2 = rect.position
	canvas.draw_rect(Rect2(p + Vector2(2, 0), Vector2(5, 2)), color)
	canvas.draw_rect(Rect2(p + Vector2(1, 2), Vector2(2, 3)), color)
	canvas.draw_rect(Rect2(p + Vector2(6, 2), Vector2(2, 3)), color)
	canvas.draw_rect(Rect2(p + Vector2(0, 5), Vector2(9, 5)), color)
	canvas.draw_rect(Rect2(p + Vector2(4, 6), Vector2(1, 2)), UITokens.VOID)


## Значок «!» — квадрат с восклицательным знаком (опасность/требования).
static func draw_bang(canvas: CanvasItem, rect: Rect2, background: Color, foreground: Color) -> void:
	canvas.draw_rect(rect, background)
	UIStyle.draw_frame(canvas, rect, 1, foreground)
	var p: Vector2 = rect.position
	canvas.draw_rect(Rect2(p + Vector2(3, 2), Vector2(1, 4)), foreground)
	canvas.draw_rect(Rect2(p + Vector2(3, 7), Vector2(1, 1)), foreground)
