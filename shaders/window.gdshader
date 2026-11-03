// Warm lit window pane with a soft interior gradient and mullions (exterior-only houses).
shader_type spatial;
render_mode unshaded;

uniform vec3 warm : source_color = vec3(1.0, 0.72, 0.38);
uniform vec3 cool : source_color = vec3(0.35, 0.4, 0.5);
uniform float lit = 1.0;
uniform vec2 panes = vec2(2.0, 2.0);
global uniform float night_factor;

void fragment() {
	vec2 uv = UV;
	vec2 g = abs(fract(uv * panes) - 0.5);
	float frame = step(0.46, max(g.x, g.y));
	float glow = mix(0.55, 1.25, night_factor) * lit;
	vec3 inside = warm * (0.75 + 0.35 * (1.0 - uv.y)) * glow;
	vec3 col = mix(cool * 0.6, inside, clamp(lit * (0.45 + night_factor), 0.0, 1.0));
	col = mix(col, vec3(0.16, 0.16, 0.18), frame);
	ALBEDO = col;
}
