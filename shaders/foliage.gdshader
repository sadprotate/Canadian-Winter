// Evergreen needles / bark / generic props with snow settling on upward-facing surfaces.
shader_type spatial;
render_mode diffuse_lambert_wrap;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.12, 0.28, 0.2);
uniform float snow_amount = 1.0;     // per-material multiplier of the global snow cover
uniform float snow_threshold = 0.55; // normal.y above which snow starts
uniform float roughness = 0.85;
global uniform float snow_cover;
// Polish 8 §7: trees bend in strong wind and its gusts (wind_vec, m/s, set by WeatherFX). Only the
// tree materials set sway (needles, bark, the snow on the boughs); 0 everywhere else.
uniform float sway = 0.0;
global uniform vec2 wind_vec;
varying vec3 v_world;

// The bend at a vertex (model space; the mesh stands on its origin): more the higher it is, swaying
// slowly with a quicker flutter, the same for the needles and the snow on them.
vec3 sway_offset(vec3 v, mat4 model) {
	float ws = length(wind_vec);
	float k = sway * smoothstep(8.0, 20.0, ws);
	if (k <= 0.0) {
		return vec3(0.0);
	}
	vec3 base = model[3].xyz;
	float ph = base.x * 0.31 + base.z * 0.23;
	float h = max(v.y, 0.0);
	float bend = k * (0.012 * h * h * (0.75 + 0.25 * sin(TIME * 1.6 + ph)) + 0.004 * h * sin(TIME * 5.3 + ph * 3.0 + v.x * 2.0));
	mat3 m = mat3(model);
	vec3 wl = transpose(m) * vec3(wind_vec.x, 0.0, wind_vec.y) / (max(ws, 0.001) * max(dot(m[0], m[0]), 1e-4));
	return vec3(wl.x, 0.0, wl.z) * bend;
}

void vertex() {
	VERTEX += sway_offset(VERTEX, MODEL_MATRIX);
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
