// Polish 5 §3: the finished interior walls of the two enterable houses. Painted drywall with a
// faint roller texture (a fine orange-peel stipple and the soft vertical lanes a paint roller
// leaves), and a subtle striped wallpaper on the bedroom's walls. Every variation averages out to
// the plain paint colour the walls had before, so the rooms light exactly as they did.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.86, 0.8, 0.7);
uniform float roughness_v = 0.9;
// The house's centre (world XZ): noise is taken relative to it, so it stays precise.
uniform vec2 origin = vec2(0.0);
// World XZ rect (x0, z0, x1, z1) of the room whose walls are papered (none if empty).
uniform vec4 paper_rect = vec4(0.0);
// The wallpaper's two tones (each as bright as the paint).
uniform vec3 paper_a : source_color = vec3(0.875, 0.8, 0.7);
uniform vec3 paper_b : source_color = vec3(0.825, 0.815, 0.715);
uniform float stripe = 0.16;      // stripe period (m)

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 rel = v_world.xz - origin;
	// Coordinates in the wall's plane: u along the wall, v up.
	float u = abs(v_wn.x) > 0.5 ? rel.y : rel.x;
	float v = v_world.y;
	// The room a face belongs to is the one just in front of it (a partition is papered on its
	// bedroom side only).
	vec2 front = v_world.xz + v_wn.xz * 0.05;
	bool paper = paper_rect.z > paper_rect.x && front.x > paper_rect.x && front.x < paper_rect.z
		&& front.y > paper_rect.y && front.y < paper_rect.w && abs(v_wn.y) < 0.5;
	vec3 col;
	if (paper) {
		// Soft alternating stripes (a cosine: exactly half of each tone over a period), a thin
		// darker pinstripe at each stripe edge, and a faint paper grain.
		float f = fract(u / stripe);
		float s = 0.5 + 0.5 * cos(f * 6.2831853);
		vec3 base = mix(paper_b, paper_a, s);
		float pin = 1.0 - smoothstep(0.004, 0.012, abs(f - 0.5) * stripe);
		float pin_mean = 0.016 / stripe;      // the pinstripe's share of a period (approx.)
		float grain = cw_noise(vec2(u, v) * 60.0) - 0.5;
		col = base * (1.0 - 0.04 * (pin - pin_mean) + 0.025 * grain);
	} else {
		// Roller: a fine stipple, a coarser one, and soft lanes about a roller wide (23 cm) running
		// up the wall, each a percent or two either way.
		float stip = cw_noise(vec2(u, v) * 85.0) - 0.5;
		float stip2 = cw_noise(vec2(u, v) * 31.0 + vec2(13.1, 7.7)) - 0.5;
		float lane = cw_noise(vec2(u * 4.35, v * 0.4) + vec2(3.3, 1.9)) - 0.5;
		col = albedo * (1.0 + 0.045 * stip + 0.025 * stip2 + 0.03 * lane);
	}
	ALBEDO = col;
	ROUGHNESS = roughness_v;
}
