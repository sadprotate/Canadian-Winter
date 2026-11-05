// Polish 5 §5: house numbers — a painted plate (with a painted border) and its digits, matte. At
// night the porch lantern just above the plate lights it: its light is added in proportion to the
// paint's own colour and fades with the distance from the lantern, so the light digits read and
// the dark plate stays dark — nothing glows on its own (no real light is added).
shader_type spatial;

uniform vec3 albedo : source_color = vec3(0.08, 0.09, 0.11);
uniform vec3 border_color : source_color = vec3(0.9, 0.86, 0.74);
uniform vec2 border = vec2(0.0);        // border width in UV (each face spans 0..1); 0 = none
uniform float roughness = 0.6;
uniform vec3 lamp_color : source_color = vec3(1.0, 0.78, 0.45);
uniform float lamp = 0.0;               // the lantern's light on the plate at full night; 0 = no lantern
uniform vec3 lamp_pos = vec3(0.0, 0.4, 0.1);   // the lantern, in the plate's own space (AddressSigns: 0.4 m above its centre)
uniform float lamp_range = 1.2;
global uniform float night_factor;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 e = min(UV, vec2(1.0) - UV);
	float b = (border.x > 0.0 && (e.x < border.x || e.y < border.y)) ? 1.0 : 0.0;
	vec3 col = mix(albedo, border_color, b);
	ALBEDO = col;
	ROUGHNESS = roughness;
	float fall = clamp(1.0 - distance(local_pos, lamp_pos) / lamp_range, 0.0, 1.0);
	EMISSION = col * lamp_color * (lamp * night_factor * fall);
}
