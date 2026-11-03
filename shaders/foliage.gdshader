// Evergreen needles / bark / generic props with snow settling on upward-facing surfaces.
shader_type spatial;
render_mode diffuse_lambert_wrap;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.12, 0.28, 0.2);
uniform float snow_amount = 1.0;     // per-material multiplier of the global snow cover
uniform float snow_threshold = 0.55; // normal.y above which snow starts
uniform float roughness = 0.85;
global uniform float snow_cover;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float n = cw_noise(v_world.xz * 4.0 + v_world.y * 3.0);
	vec3 base = albedo * (0.85 + 0.3 * n);
	float cover = clamp(snow_cover * snow_amount, 0.0, 1.0);
	float thr = mix(1.05, snow_threshold, cover);
	float s = smoothstep(thr, thr + 0.12, wn.y + (n - 0.5) * 0.25);
	ALBEDO = mix(base, vec3(0.94, 0.95, 1.0), s);
	ROUGHNESS = mix(roughness, 0.85, s);
	SPECULAR = 0.3;
}
