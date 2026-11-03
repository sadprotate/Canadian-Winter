// Timber with procedural grain (porch posts, mailbox posts, fences, furniture).
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.55, 0.36, 0.2);
uniform float snow_amount = 0.0;
global uniform float snow_cover;
varying vec3 v_local;
varying vec3 v_world;

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float g = cw_noise(vec2(v_local.x * 3.0 + v_local.z * 3.0, v_local.y * 0.6) * vec2(6.0, 1.0));
	float rings = sin((v_local.x + v_local.z) * 40.0 + g * 6.0) * 0.5 + 0.5;
	vec3 col = albedo * (0.82 + 0.18 * rings + 0.1 * g);
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float s = smoothstep(0.8, 0.95, wn.y) * clamp(snow_cover * snow_amount, 0.0, 1.0);
	ALBEDO = mix(col, vec3(0.94, 0.95, 1.0), s);
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
}
