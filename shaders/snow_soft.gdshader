// Soft pillowy snow for roofs, tree caps, vehicle loads, banks on props and particles' clumps.
// Bright rounded tops, cool blue undersides and a gentle powdery rim, as in the references.
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 snow_color : source_color = vec3(0.96, 0.965, 1.0);
uniform vec3 shade_color : source_color = vec3(0.68, 0.73, 0.96);
global uniform float night_factor;
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
