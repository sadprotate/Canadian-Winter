// Horizontal lap siding with subtle board variation.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.56, 0.57, 0.58);
uniform float board = 0.18;
varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float f = fract(v_local.y / board);
	float lip = smoothstep(0.0, 0.12, f);
	float shade = mix(0.72, 1.0, lip) - 0.05 * smoothstep(0.75, 1.0, f);
	float row = floor(v_local.y / board);
	float grain = cw_noise(vec2((v_local.x + v_local.z) * 1.3, row * 7.0)) * 0.06;
	ALBEDO = albedo * (shade + grain - 0.03);
	ROUGHNESS = 0.78;
	SPECULAR = 0.25;
}
