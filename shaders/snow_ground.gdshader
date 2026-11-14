// Terrain snow heightfield. UV.x = snow depth (m), UV.y = surface code + 0.4 + convexity.
// Stylized "pillowy" look from the reference images: soft wrap lighting, cool blue shadows in
// hollows and on steep bank faces, bright rounded tops, procedural lumps and tiny sparkles.
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 snow_color : source_color = vec3(0.96, 0.965, 1.0);
uniform vec3 shade_color : source_color = vec3(0.66, 0.72, 0.96);
uniform vec3 packed_color : source_color = vec3(0.80, 0.80, 0.84);
uniform float sparkle_strength = 0.8;
uniform float frost_depth = 0.022;
uniform float lump_strength = 0.55;
global uniform float night_factor;
// Polish 3 §3: footprints of the two houses you can walk into (x0, z0, x1, z1 in world space).
// The ground snow next to a wall is drawn up to the wall's centre line (banks meet walls flush),
// which put a sliver of it through the front door and into the doorway; inside these rects the
// snow mesh is never drawn. Outside them nothing changes.
global uniform vec4 snow_hide_a;
global uniform vec4 snow_hide_b;
// Polish 8 §15: the player's garage (its footprint), the same way.
global uniform vec4 snow_hide_c;

varying float v_depth;
varying float v_surf;
varying float v_cav;
varying vec3 v_world;

void vertex() {
	v_depth = UV.x;
	v_surf = floor(UV.y);
	v_cav = fract(UV.y) - 0.4;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float lumps(vec2 p) {
	return cw_noise(p * 0.9) * 0.65 + cw_noise(p * 2.3 + vec2(7.1, 3.3)) * 0.35;
}

bool in_rect(vec4 r, vec2 p) {
	return p.x > r.x && p.x < r.z && p.y > r.y && p.y < r.w;
}

void fragment() {
	if (in_rect(snow_hide_a, v_world.xz) || in_rect(snow_hide_b, v_world.xz) || in_rect(snow_hide_c, v_world.xz)) {
		discard;
	}
	float n1 = cw_noise(v_world.xz * 2.7);
	float n2 = cw_noise(v_world.xz * 13.0);
	float n = n1 * 0.6 + n2 * 0.4;
	// Thin layers break up into frosty speckles at the edge of cleared pavement.
	float thin = clamp(v_depth / frost_depth, 0.0, 1.0);
	if (thin < 0.999 && n2 * 0.7 + n1 * 0.3 > thin * 1.15 + 0.02) {
		discard;
	}
	// Soft procedural lumps (normal perturbation only; deeper snow is lumpier).
	float e = 0.18;
	float h0 = lumps(v_world.xz);
	float hx = lumps(v_world.xz + vec2(e, 0.0));
	float hz = lumps(v_world.xz + vec2(0.0, e));
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// Banks (steeper faces) get chunkier "cauliflower" clumps, flat fresh snow stays soft.
	float amp = lump_strength * clamp(v_depth * 3.0, 0.0, 1.0) * (1.0 + 1.6 * (1.0 - clamp(wn.y, 0.0, 1.0)));
	vec3 bump_w = normalize(vec3((h0 - hx) / e * amp * 0.35, 1.0, (h0 - hz) / e * amp * 0.35));
	// Blend the bump into the geometric normal (tilted surfaces keep their own direction).
	vec3 tangent_up = normalize(wn + (bump_w - vec3(0.0, 1.0, 0.0)) * (0.5 + 0.5 * clamp(wn.y, 0.0, 1.0)));
	NORMAL = normalize((VIEW_MATRIX * vec4(tangent_up, 0.0)).xyz);
	float up = clamp(tangent_up.y, 0.0, 1.0);

	vec3 col = snow_color * (0.95 + 0.05 * n);
	// Steep faces of banks and hollows pick up the cool tint seen in the references.
	float hollow = clamp(-v_cav * 6.0, 0.0, 1.0);
	float crest = clamp(v_cav * 6.0, 0.0, 1.0);
	col = mix(col, shade_color, clamp((1.0 - up) * 0.55 + hollow * 0.35, 0.0, 0.75));
	col *= 1.0 + crest * 0.05;
	// Road snow gets packed and slightly grey from traffic.
	float is_road = 1.0 - step(0.5, abs(v_surf - 1.0));
	col = mix(col, packed_color, is_road * 0.35 * clamp(1.0 - v_depth * 4.0, 0.0, 1.0));
	// Thin frost is greyer / translucent looking.
	col = mix(col * vec3(0.78, 0.8, 0.86), col, thin);
	ALBEDO = col;
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
	AO = 1.0 - hollow * 0.35;
	AO_LIGHT_AFFECT = 0.4;
	// Soft rim brightening (powdery edges glow against the sky).
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// Sparkle: tiny view-dependent glints.
	vec3 vw = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	float g = cw_hash_cell(floor(v_world.xz * 55.0 + vec2(v_world.y * 41.0, v_world.y * 29.0)) + floor(vw.xz * 9.0));
	float glint = step(0.9965, g) * smoothstep(0.75, 0.95, up) * sparkle_strength;
	EMISSION = (vec3(glint) + vec3(0.06, 0.07, 0.1) * rim) * mix(1.0, 0.25, night_factor);
	BACKLIGHT = vec3(0.18, 0.2, 0.26);
}
