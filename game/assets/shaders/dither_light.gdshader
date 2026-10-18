shader_type canvas_item;
render_mode unshaded;
// T-35, DESIGN §8.7: эмиссивное свечение источника (пламя/окно) с дизерингом.
//
// Используется EmissiveGlow на отдельном CanvasLayer: CanvasModulate зоны его
// не затемняет. Радиальный спад квантуется на `steps` ступеней и размывается
// только матрицей Байера 4×4 — никаких гладких градиентов и «неона».

uniform vec4 glow_color : source_color = vec4(0.878, 0.71, 0.416, 1.0);
uniform float radius_px = 46.0;
uniform vec2 size_px = vec2(92.0, 92.0);
uniform int steps : hint_range(2, 8) = 6;
uniform float intensity : hint_range(0.0, 1.0) = 0.5;

float bayer4(vec2 pixel) {
	vec2 p1 = mod(pixel, 2.0);
	vec2 p2 = mod(floor(pixel * 0.5), 2.0);
	float index = p1.x + 2.0 * p1.y + 4.0 * p2.x + 8.0 * p2.y;
	return (index + 0.5) / 16.0 - 0.5;
}

void fragment() {
	vec2 local = (UV - vec2(0.5)) * size_px;
	float distance = length(local) / max(radius_px, 1.0);
	float energy = clamp(1.0 - distance, 0.0, 1.0);

	float bias = (bayer4(FRAGCOORD.xy) * 0.5) / float(steps);
	float band = floor(energy * float(steps) + 0.5 + bias) / float(steps);
	float alpha = band * intensity;

	COLOR = vec4(glow_color.rgb, alpha);
}
