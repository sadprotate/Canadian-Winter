// Asphalt / concrete pavement. Cleared pavement reads as dark, slightly wet grey.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.28, 0.29, 0.31);
uniform float speckle = 0.08;
uniform float slab_size = 0.0;   // >0: concrete slab joints every slab_size meters
uniform float wetness = 0.5;
uniform bool lane_marks = false;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float n = cw_noise(p * 9.0) * 0.6 + cw_noise(p * 37.0) * 0.4;
	vec3 col = albedo * (1.0 - speckle + speckle * 2.0 * n);
	float joint = 0.0;
	if (slab_size > 0.0) {
		vec2 g = abs(fract(p / slab_size + 0.5) - 0.5) * slab_size;
		joint = 1.0 - smoothstep(0.008, 0.025, min(g.x, g.y));
		col *= 1.0 - joint * 0.35;
	}
	// Wet patches: darker and glossier.
	float wet = smoothstep(0.45, 0.75, cw_noise(p * 0.35)) * wetness;
	col *= 1.0 - wet * 0.25;
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.35, wet);
	SPECULAR = 0.4;
}
