// Soft pillowy snow for roofs, tree caps, vehicle loads, banks on props and particles' clumps.
// Bright rounded tops, cool blue undersides and a gentle powdery rim, as in the references.
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 snow_color : source_color = vec3(0.96, 0.965, 1.0);
uniform vec3 shade_color : source_color = vec3(0.68, 0.73, 0.96);
global uniform float night_factor;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float up = clamp(wn.y * 0.5 + 0.5, 0.0, 1.0);
	float n = cw_noise(v_world.xz * 3.1 + v_world.y * 2.0);
	vec3 col = mix(shade_color, snow_color, smoothstep(0.12, 0.8, up)) * (0.95 + 0.05 * n);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	AO = mix(0.75, 1.0, smoothstep(0.2, 0.7, up));
	AO_LIGHT_AFFECT = 0.3;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 vw = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	float g = cw_hash_cell(floor(v_world.xz * 50.0 + v_world.y * 30.0) + floor(vw.xz * 9.0));
	EMISSION = (vec3(step(0.997, g) * 0.5) + vec3(0.06, 0.07, 0.1) * rim) * mix(1.0, 0.25, night_factor);
	BACKLIGHT = vec3(0.16, 0.18, 0.24);
}
