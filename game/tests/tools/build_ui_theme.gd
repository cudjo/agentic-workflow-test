extends SceneTree
## Генератор game/ui/theme/main_theme.tres из токенов UITokens.
##
## Запуск (headless, из game/):
##   godot --headless --path game --script res://tests/tools/build_ui_theme.gd
##
## Theme — производная от tokens.gd: цвета, размеры и шрифт не задаются здесь
## вручную. Скрипт идемпотентен: повторный запуск пересобирает ресурс.
## 9-slice панели генерируются в рантайме (UIStyle.panel_style), т.к.
## ImageTexture не сериализуется в .tres.

const THEME_PATH := "res://ui/theme/main_theme.tres"


func _initialize() -> void:
	var primary := load(UITokens.FONT_PATH) as FontFile
	var fallback := load(UITokens.FONT_FALLBACK_PATH) as FontFile
	if primary == null or fallback == null:
		push_error("build_ui_theme: fonts are missing (import first: godot --headless --path game --import)")
		quit(1)
		return

	var font_variation := FontVariation.new()
	font_variation.base_font = primary
	var fallbacks: Array[Font] = [fallback]
	font_variation.fallbacks = fallbacks

	var theme := Theme.new()
	theme.default_font = font_variation
	theme.default_font_size = UITokens.FONT_BODY

	_configure_labels(theme, font_variation)
	_configure_buttons(theme, font_variation)
	_configure_rich_text(theme, font_variation)
	_configure_containers(theme)
	_configure_tooltip(theme)

	var error: Error = ResourceSaver.save(theme, THEME_PATH)
	if error != OK:
		push_error("build_ui_theme: failed to save %s (error %d)" % [THEME_PATH, error])
		quit(1)
		return
	print("build_ui_theme: saved %s (27 colors, font %s + fallback %s)" % [
		THEME_PATH,
		UITokens.FONT_PATH.get_file(),
		UITokens.FONT_FALLBACK_PATH.get_file(),
	])
	quit(0)


func _configure_labels(theme: Theme, font: Font) -> void:
	theme.set_font("font", "Label", font)
	theme.set_font_size("font_size", "Label", UITokens.FONT_BODY)
	theme.set_color("font_color", "Label", UITokens.BONE)
	theme.set_color("font_shadow_color", "Label", UITokens.VOID)
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	var variations := {
		"H1Label": [UITokens.FONT_H1, UITokens.GOLD_3],
		"H2Label": [UITokens.FONT_H2, UITokens.GOLD_3],
		"TitleLabel": [UITokens.FONT_TITLE, UITokens.GOLD_3],
		"MutedLabel": [UITokens.FONT_BODY, UITokens.STONE_5],
		"GoldLabel": [UITokens.FONT_BODY, UITokens.GOLD_3],
		"DangerLabel": [UITokens.FONT_BODY, UITokens.BLOOD_5],
		"SteelLabel": [UITokens.FONT_BODY, UITokens.STEEL_3],
	}
	for variation_name in variations:
		var spec: Array = variations[variation_name]
		theme.set_type_variation(variation_name, "Label")
		theme.set_font("font", variation_name, font)
		theme.set_font_size("font_size", variation_name, spec[0])
		theme.set_color("font_color", variation_name, spec[1])


func _configure_buttons(theme: Theme, font: Font) -> void:
	theme.set_font("font", "Button", font)
	theme.set_font_size("font_size", "Button", UITokens.FONT_BODY)
	theme.set_color("font_color", "Button", UITokens.STONE_5)
	theme.set_color("font_hover_color", "Button", UITokens.BONE)
	theme.set_color("font_pressed_color", "Button", UITokens.VOID)
	theme.set_color("font_focus_color", "Button", UITokens.BONE)
	theme.set_color("font_disabled_color", "Button", UITokens.STONE_3)

	theme.set_stylebox("normal", "Button", _flat(
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, UITokens.SP_3, UITokens.SP_1
	))
	theme.set_stylebox("hover", "Button", _flat(
		UITokens.NIGHT_3, Color(0, 0, 0, 0), 0, UITokens.SP_3, UITokens.SP_1
	))
	theme.set_stylebox("pressed", "Button", _flat(
		UITokens.GOLD, Color(0, 0, 0, 0), 0, UITokens.SP_3, UITokens.SP_1
	))
	theme.set_stylebox("disabled", "Button", _flat(
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, UITokens.SP_3, UITokens.SP_1
	))
	theme.set_stylebox("focus", "Button", _flat(
		Color(0, 0, 0, 0), UITokens.GOLD, UITokens.BORDER_FOCUS, UITokens.SP_3, UITokens.SP_1
	))


func _configure_rich_text(theme: Theme, font: Font) -> void:
	for item in ["normal_font", "bold_font", "italics_font", "mono_font"]:
		theme.set_font(item, "RichTextLabel", font)
	theme.set_font_size("normal_font_size", "RichTextLabel", UITokens.FONT_BODY)
	theme.set_font_size("bold_font_size", "RichTextLabel", UITokens.FONT_BODY)
	theme.set_font_size("italics_font_size", "RichTextLabel", UITokens.FONT_BODY)
	theme.set_font_size("mono_font_size", "RichTextLabel", UITokens.FONT_BODY)
	theme.set_color("default_color", "RichTextLabel", UITokens.BONE)


func _configure_containers(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", _flat(
		UITokens.NIGHT_9,
		UITokens.STONE_3,
		UITokens.BORDER_PANEL,
		UITokens.PANEL_PADDING,
		UITokens.PANEL_PADDING
	))
	theme.set_stylebox("panel", "Panel", _flat(
		UITokens.NIGHT_9,
		UITokens.STONE_3,
		UITokens.BORDER_PANEL,
		UITokens.PANEL_PADDING,
		UITokens.PANEL_PADDING
	))
	theme.set_stylebox("panel", "PopupMenu", _flat(
		UITokens.NIGHT_9,
		UITokens.STONE_3,
		UITokens.BORDER_PANEL,
		UITokens.SP_2,
		UITokens.SP_2
	))


func _configure_tooltip(theme: Theme) -> void:
	theme.set_stylebox("panel", "TooltipPanel", _flat(
		UITokens.NIGHT_9,
		UITokens.STONE_3,
		UITokens.BORDER_INNER,
		UITokens.SP_2,
		UITokens.SP_1
	))
	theme.set_color("font_color", "TooltipLabel", UITokens.BONE)
	theme.set_font_size("font_size", "TooltipLabel", UITokens.FONT_BODY)


func _flat(
	background: Color,
	border: Color,
	border_width: int,
	margin_horizontal: int,
	margin_vertical: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.anti_aliasing = false
	style.content_margin_left = float(margin_horizontal)
	style.content_margin_right = float(margin_horizontal)
	style.content_margin_top = float(margin_vertical)
	style.content_margin_bottom = float(margin_vertical)
	return style
