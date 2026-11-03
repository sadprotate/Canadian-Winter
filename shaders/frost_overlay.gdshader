// Cold warning overlay: frosty vignette, desaturation and a slow pulse when critical.
shader_type canvas_item;
#include "res://shaders/noise.gdshaderinc"

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	if (amount <= 0.001) {
		discard;
	}
	vec3 scr = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float grey = dot(scr, vec3(0.3, 0.59, 0.11));
	vec3 cold = mix(scr, vec3(grey) * vec3(0.85, 0.92, 1.1), amount * 0.85);
	vec2 c = UV - 0.5;
	float r = length(c * vec2(1.6, 1.0));
	float n = cw_fbm(UV * 9.0) * 0.5 + cw_noise(UV * 40.0) * 0.5;
	float edge = smoothstep(0.75 - amount * 0.45, 1.05, r + n * 0.25);
	float p = pulse * (0.5 + 0.5 * sin(TIME * 5.0)) * 0.15;
	vec3 frostc = vec3(0.88, 0.94, 1.0);
	COLOR = vec4(mix(cold, frostc, clamp(edge * amount + p * amount, 0.0, 0.92)), 1.0);
}
