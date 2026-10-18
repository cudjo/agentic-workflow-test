extends GutTest
## T-18: тесты токенов, темы, шрифта RU+EN и контраста (DESIGN §4, §9.1).

const THEME_PATH := "res://ui/theme/main_theme.tres"

const RU_EN_SAMPLE := (
	"ПЕПЕЛЬНЫЙ БАСТИОН · ASHEN BASTION · НЕТ СИЛ · ФАЗА II · СОХРАНЕНО · СЛОТ 1 "
	+ "· УР7 · ОП 3 · «Здесь тонут даже тени» — ЁёЙйЪъЫыЬьЭэЮюЯя 0123456789!?%№+-/"
)


func test_palette_has_exactly_27_unique_colors() -> void:
	assert_eq(UITokens.COLORS.size(), 27, "DESIGN §4.1: 27 UI-цветов")
	var unique := {}
	for token_name in UITokens.COLORS:
		var value: Color = UITokens.COLORS[token_name]
		unique[value.to_html(false)] = true
	assert_eq(unique.size(), 27, "все 27 токенов должны быть различимы")


func test_key_token_hex_values() -> void:
	assert_eq(UITokens.VOID.to_html(false), "0b0c10")
	assert_eq(UITokens.NIGHT_9.to_html(false), "10131c")
	assert_eq(UITokens.BONE.to_html(false), "d6c9a8")
	assert_eq(UITokens.GOLD.to_html(false), "c08a3e")
	assert_eq(UITokens.BLOOD.to_html(false), "7a2a24")
	assert_eq(UITokens.BLOOD_5.to_html(false), "cf6a5c")
	assert_eq(UITokens.STEEL_3.to_html(false), "7f9aa8")


func test_typography_has_four_sizes() -> void:
	assert_eq(UITokens.FONT_SIZES, [8, 16, 24, 32], "DESIGN §4.2: body/h2/h1/title")
	assert_eq(UITokens.LINE_HEIGHTS, [12, 16, 24, 32])
	assert_eq(UITokens.FONT_BODY, 8, "минимальный размер текста — 8 px")


func test_spacing_borders_and_sizes() -> void:
	assert_eq(UITokens.SPACING, [2, 4, 8, 12, 16, 24], "DESIGN §4.3: sp-1…sp-6")
	assert_eq(UITokens.SAFE_MARGIN, 8)
	assert_eq(UITokens.BORDER_PANEL, 2)
	assert_eq(UITokens.BORDER_SLOT, 2)
	assert_eq(UITokens.BORDER_FOCUS, 2, "a11y §9.2: толщина фокуса ≥ 2 px")
	assert_eq(UITokens.BAR_HP_SIZE, Vector2(112, 10))
	assert_eq(UITokens.BAR_STAMINA_SIZE, Vector2(96, 8))
	assert_eq(UITokens.BAR_BOSS_SIZE, Vector2(248, 8))
	assert_eq(UITokens.SLOT_HUD, 22)
	assert_eq(UITokens.SLOT_INV, 28)
	assert_eq(UITokens.TYPE_SPEED, 0.022, "DESIGN §4.5: 22 мс/символ")


func test_eight_pixel_text_contrast_meets_aa() -> void:
	var pairs := [
		[UITokens.BONE, UITokens.NIGHT_9, "основной текст на панели"],
		[UITokens.BONE, UITokens.VOID, "основной текст на void"],
		[UITokens.GOLD_3, UITokens.NIGHT_9, "заголовки"],
		[UITokens.GOLD, UITokens.NIGHT_9, "рамка/значок фокуса"],
		[UITokens.STONE_5, UITokens.NIGHT_9, "вторичный текст"],
		[UITokens.STONE_5, UITokens.NIGHT_3, "hover-строка"],
		[UITokens.STEEL_3, UITokens.NIGHT_9, "сталь/успех"],
		[UITokens.BLOOD_5, UITokens.NIGHT_9, "текст опасности"],
		[UITokens.BONE, UITokens.BLOOD, "текст на опасности"],
		[UITokens.VOID, UITokens.GOLD, "активный пункт меню"],
	]
	for pair in pairs:
		var ratio: float = UITokens.contrast_ratio(pair[0], pair[1])
		assert_true(ratio >= 4.5, "%s: %.2f:1 < 4.5:1" % [pair[2], ratio])


func test_focus_ring_contrast_is_at_least_three() -> void:
	var ratio: float = UITokens.contrast_ratio(UITokens.GOLD, UITokens.NIGHT_9)
	assert_true(ratio >= 3.0, "фокусная рамка gold на night-9: %.2f:1" % ratio)


func test_blood_fill_is_not_used_as_text_color() -> void:
	var ratio: float = UITokens.contrast_ratio(UITokens.BLOOD, UITokens.NIGHT_9)
	assert_true(ratio < 4.5, "DESIGN §4.1: blood запрещён для 8-px текста (%.2f:1)" % ratio)


func test_theme_loads_with_single_source_font() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_not_null(theme, "main_theme.tres должен существовать")
	assert_eq(theme.default_font_size, UITokens.FONT_BODY)
	var font := theme.default_font
	assert_not_null(font)
	assert_true(font is FontVariation, "шрифт темы — FontVariation с fallback-цепочкой")
	var variation := font as FontVariation
	assert_not_null(variation.base_font, "базовый шрифт — Press Start 2P")
	assert_eq(variation.base_font.resource_path, UITokens.FONT_PATH)
	assert_gt(variation.fallbacks.size(), 0, "fallback Tiny5 для символов вне PS2P")


func test_theme_declares_all_four_type_sizes() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_eq(theme.get_font_size("font_size", "H2Label"), UITokens.FONT_H2)
	assert_eq(theme.get_font_size("font_size", "H1Label"), UITokens.FONT_H1)
	assert_eq(theme.get_font_size("font_size", "TitleLabel"), UITokens.FONT_TITLE)
	assert_eq(theme.get_font_size("font_size", "Label"), UITokens.FONT_BODY)
	assert_eq(theme.get_type_variation_base("H2Label"), &"Label")
	assert_eq(theme.get_color("font_color", "DangerLabel").to_html(false), UITokens.BLOOD_5.to_html(false))


func test_press_start_2p_covers_russian_and_english() -> void:
	var font := load(UITokens.FONT_PATH) as Font
	assert_not_null(font)
	for index in RU_EN_SAMPLE.length():
		var codepoint: int = RU_EN_SAMPLE.unicode_at(index)
		if codepoint == 32:
			continue
		assert_true(
			font.has_char(codepoint),
			"нет глифа U+%04X в Press Start 2P" % codepoint
		)


func test_theme_font_resolves_ru_en_with_fallback() -> void:
	var theme := load(THEME_PATH) as Theme
	var font := theme.default_font
	for index in RU_EN_SAMPLE.length():
		var codepoint: int = RU_EN_SAMPLE.unicode_at(index)
		if codepoint == 32:
			continue
		assert_true(font.has_char(codepoint), "нет глифа U+%04X в теме" % codepoint)


func test_fallback_font_covers_symbols_missing_in_press_start() -> void:
	var fallback := load(UITokens.FONT_FALLBACK_PATH) as Font
	assert_not_null(fallback)
	for codepoint in [0x2713, 0x25A1, 0x25CB, 0x25B3]:
		assert_true(fallback.has_char(codepoint), "Tiny5: нет U+%04X" % codepoint)


func test_panel_is_a_nine_slice_built_from_tokens() -> void:
	var panel := AshenPanel.new()
	panel.variant = UIStyle.PanelVariant.SOLID
	panel.padding = UITokens.PANEL_PADDING
	var style := panel.get_panel_style()
	assert_not_null(style)
	assert_true(style is StyleBoxTexture, "Panel — 9-slice StyleBoxTexture")
	assert_almost_eq(style.texture_margin_left, float(UIStyle.PANEL_MARGIN), 0.001)
	assert_almost_eq(
		style.content_margin_left,
		float(UIStyle.PANEL_MARGIN + UITokens.PANEL_PADDING),
		0.001
	)
	assert_eq(panel.get_variant_name(), "solid")
	panel.free()


func test_panel_variants_change_border_and_glass_alpha() -> void:
	var vertical := 10
	var solid := AshenPanel.new()
	solid.variant = UIStyle.PanelVariant.SOLID
	var solid_texture := solid.get_panel_style().texture.get_image()
	assert_eq(solid_texture.get_pixel(1, vertical), UITokens.STONE_3)

	var danger := AshenPanel.new()
	danger.variant = UIStyle.PanelVariant.DANGER
	var danger_texture := danger.get_panel_style().texture.get_image()
	assert_eq(danger_texture.get_pixel(1, vertical), UITokens.BLOOD_3)

	var glass := AshenPanel.new()
	glass.variant = UIStyle.PanelVariant.GLASS
	var glass_texture := glass.get_panel_style().texture.get_image()
	assert_almost_eq(
		glass_texture.get_pixel(10, 10).a,
		UITokens.GLASS_ALPHA,
		0.01,
		"glass: фон void 82%"
	)

	var inset := AshenPanel.new()
	inset.variant = UIStyle.PanelVariant.INSET
	assert_false(inset.has_rivets(), "inset без угловых заклёпок")
	assert_eq(inset.get_panel_style().texture.get_image().get_pixel(10, 10), UITokens.VOID)

	solid.free()
	danger.free()
	glass.free()
	inset.free()
