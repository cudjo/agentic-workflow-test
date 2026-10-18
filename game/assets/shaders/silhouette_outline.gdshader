shader_type canvas_item;
// T-35, DESIGN §9.1 / AC-07.1: читаемость силуэта героя.
//
// `enabled = true` (режим «Читаемость силуэтов») рисует 1-px контур цветом
// bone 60 % поверх прозрачных пикселей, соседних с телом спрайта.
// В обычном режиме остаётся слабый rim-light (`rim_strength`), чтобы силуэт
// героя не терялся на тёмном фоне при яркости по умолчанию (AC-07.1).
// Режим также отключает виньетку — это делает LightingRig.

uniform bool enabled = false;
uniform vec4 outline_color : source_color = vec4(0.839, 0.788, 0.659, 0.6);
uniform float outline_width : hint_range(1.0, 2.0) = 1.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	vec4 base = COLOR;
	vec2 texel = TEXTURE_PIXEL_SIZE * outline_width;

	float neighbor_alpha = max(
		max(texture(TEXTURE, UV + vec2(texel.x, 0.0)).a,
			texture(TEXTURE, UV - vec2(texel.x, 0.0)).a),
		max(texture(TEXTURE, UV + vec2(0.0, texel.y)).a,
			texture(TEXTURE, UV - vec2(0.0, texel.y)).a)
	);

	if (base.a < 0.5 && neighbor_alpha > 0.5) {
		if (enabled) {
			COLOR = vec4(outline_color.rgb, outline_color.a);
		} else {
			COLOR = vec4(outline_color.rgb, outline_color.a * rim_strength);
		}
	} else if (base.a > 0.5) {
		// Верхняя кромка: в a11y-режиме — полный контур, иначе слабый rim-light,
		// который удерживает силуэт читаемым на тёмном фоне (AC-07.1).
		float top_alpha = texture(TEXTURE, UV - vec2(0.0, texel.y)).a;
		if (top_alpha < 0.5) {
			if (enabled) {
				COLOR = vec4(outline_color.rgb, max(base.a, outline_color.a));
			} else {
				COLOR = vec4(
					mix(base.rgb, outline_color.rgb, rim_strength),
					base.a
				);
			}
		} else {
			COLOR = base;
		}
	} else {
		COLOR = base;
	}
}
