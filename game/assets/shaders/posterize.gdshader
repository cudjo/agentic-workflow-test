shader_type canvas_item;
render_mode unshaded;
// T-35, DESIGN §8.7: постеризация + дизеринг Байера 4×4 для всей сцены.
//
// Накладывается ColorRect'ом на CanvasLayer освещения (Layer 0 мир → 1
// эмиссивные объекты → 2 пост-обработка → 10 HUD). Плавных градиентов нет:
// яркость квантуется на `levels` ступеней (6–8), а граница между ступенями
// размывается только 4×4-матрицей Байера. Виньетка тоже квантуется на 4 шага,
// чтобы не появлялось мягкое радиальное затемнение.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform int levels : hint_range(2, 16) = 8;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.5;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.28;
uniform float warmth_amount : hint_range(0.0, 1.0) = 0.08;
uniform vec4 warmth_color : source_color = vec4(1.0, 0.86, 0.66, 1.0);

// 4×4 Bayer (рекурсивная 2×2-матрица), значения 0…15/16.
float bayer4(vec2 pixel) {
	vec2 p1 = mod(pixel, 2.0);
	vec2 p2 = mod(floor(pixel * 0.5), 2.0);
	float index = p1.x + 2.0 * p1.y + 4.0 * p2.x + 8.0 * p2.y;
	return (index + 0.5) / 16.0 - 0.5;
}

void fragment() {
	vec3 src = texture(screen_texture, SCREEN_UV).rgb;

	// Квантование по яркости с дизерингом; оттенок сохраняется масштабом.
	float luma = dot(src, vec3(0.2126, 0.7152, 0.0722));
	float bias = bayer4(FRAGCOORD.xy) * (dither_strength / float(levels));
	float banded_luma = floor(luma * float(levels) + 0.5 + bias) / float(levels);
	float scale = banded_luma / max(luma, 1.0 / 255.0);
	vec3 color = clamp(src * scale, vec3(0.0), vec3(1.0));

	// Тёплый сдвиг только в освещённых ступенях — ступенькой, не градиентом.
	float warm = step(0.25, banded_luma) * warmth_amount;
	color = mix(color, color * warmth_color.rgb, warm);

	// Виньетка: 4 дискретных ступени, чтобы край не «плыл».
	vec2 centered = SCREEN_UV - vec2(0.5);
	centered.x *= 1.7777778; // 480 / 270
	float falloff = clamp(length(centered) * 1.35, 0.0, 1.0);
	float vignette = floor(falloff * 4.0 + 0.5) / 4.0;
	color *= 1.0 - vignette * vignette_strength;

	COLOR = vec4(color, 1.0);
}
