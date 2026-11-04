// Polish 5 §6: the surface of the hand tools and blowers — plastic, aluminium, painted or bare
// steel, wood, fibreglass and rubber — with a little wear, all procedural (no textures). Shared by
// shaders/tool.gdshader (the world and third person) and shaders/viewmodel_clip.gdshader (the
// first-person parts, which also hide what is under the snow).
//
// Wear: sparse scuffs and scratches from noise, more towards the front edge of a blade
// (`edge_wear`: the meshes give blade surfaces UV.y = 0 at the edge that scrapes the ground).
#include "res://shaders/noise.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.8;
uniform float metallic = 0.0;
// 0 plain (the old flat look), 1 plastic, 2 aluminium, 3 painted steel, 4 bare steel, 5 wood,
// 6 fibreglass, 7 rubber / foam
uniform int finish = 0;
uniform float wear = 0.3;
uniform float edge_wear = 0.0;
// The direction of the grain / brushing / fibres in the mesh's own space (a shaft's axis).
uniform vec3 grain_axis = vec3(0.0, -0.819, -0.574);

float tool_n3(vec3 p) {
	// Cheap 3D value noise from two 2D lookups (enough for scuffs and mottling).
	return 0.5 * (cw_noise(p.xy + p.z * 1.7) + cw_noise(p.zx * 1.13 + p.y * 2.3 + vec2(31.7, 11.3)));
}

// Short scratches: thin streaks along `dir` scattered at random.
float tool_scratch(vec3 p, vec3 dir, float density) {
	vec3 d = normalize(dir);
	float along = dot(p, d);
	vec3 perp = p - d * along;
	float cross_c = perp.x * 0.83 + perp.y * 1.31 + perp.z * 0.57;
	vec2 cell = vec2(along * 6.0, cross_c * 260.0);
	float line = cw_hash(floor(cell));
	float keep = step(1.0 - density, line);
	float fade = cw_noise(vec2(along * 24.0, cross_c * 9.0));
	return keep * smoothstep(0.45, 0.8, fade);
}

void tool_surface(vec3 lp, vec2 uv, inout vec3 col, inout float rough, inout float metal, inout float spec) {
	col = albedo.rgb;
	rough = roughness;
	metal = metallic;
	spec = 0.5;
	if (finish == 0) {
		return;
	}
	float edge = edge_wear * (1.0 - smoothstep(0.0, 0.22, uv.y));
	float mott = tool_n3(lp * 7.0);
	float fine = tool_n3(lp * 61.0);
	float scuff = smoothstep(0.62, 0.86, tool_n3(lp * 23.0 + vec3(5.1, 2.7, 9.3))) * wear;
	scuff = clamp(scuff + edge * wear * 1.6 * smoothstep(0.3, 0.7, fine + 0.25), 0.0, 1.0);
	if (finish == 1) {
		// Moulded plastic: a satin sheen, faint mottling, whitened scuffs and fine scratches.
		col *= 0.95 + 0.08 * mott;
		float sc = tool_scratch(lp, vec3(0.0, 0.3, 1.0), 0.05) * wear;
		col = mix(col, mix(col, vec3(0.86), 0.45), clamp(scuff * 0.75 + sc * 0.5, 0.0, 1.0));
		rough = clamp(rough + 0.06 * (fine - 0.5) + 0.25 * scuff, 0.05, 1.0);
		spec = 0.45;
	} else if (finish == 2) {
		// Brushed aluminium: streaks along the axis, a few darker scratches.
		vec3 a = normalize(grain_axis);
		vec3 perp = lp - a * dot(lp, a);
		float c = perp.x * 0.91 + perp.y * 1.23 + perp.z * 0.71;
		float brush = cw_noise(vec2(dot(lp, a) * 2.0, c * 900.0));
		col *= 0.9 + 0.12 * brush;
		rough = clamp(rough + 0.12 * (brush - 0.5), 0.05, 1.0);
		float sc = tool_scratch(lp, vec3(0.6, 0.3, 0.7), 0.08) * wear;
		col *= 1.0 - 0.25 * sc;
		col *= 1.0 - 0.18 * scuff;
	} else if (finish == 3) {
		// Painted steel: chips and worn edges show the bare metal underneath.
		col *= 0.94 + 0.08 * mott;
		float chip = smoothstep(0.55, 0.62, scuff + 0.25 * fine * wear);
		col = mix(col, vec3(0.5, 0.5, 0.52), chip);
		metal = mix(metal, 0.85, chip);
		rough = mix(rough + 0.05 * (fine - 0.5), 0.42, chip);
	} else if (finish == 4) {
		// Bare steel (wear strips, cutting edges, rivets, ferrules): scraped bright where it rubs,
		// darker and a touch rusty elsewhere.
		float sc = tool_scratch(lp, vec3(0.0, 0.0, 1.0), 0.18);
		col *= 0.82 + 0.18 * mott;
		col = mix(col, col * vec3(0.78, 0.6, 0.45), 0.35 * smoothstep(0.6, 0.85, tool_n3(lp * 13.0)) * wear);
		col = mix(col, vec3(0.82, 0.83, 0.85), clamp(sc * 0.6 + edge * 0.5, 0.0, 1.0));
		rough = clamp(rough + 0.1 * (fine - 0.5) - 0.12 * sc, 0.05, 1.0);
	} else if (finish == 5) {
		// Varnished wood: grain along the axis, a darker handled patina.
		vec3 a = normalize(grain_axis);
		float t = dot(lp, a);
		vec3 perp = lp - a * t;
		float c = perp.x * 1.17 + perp.y * 0.79 + perp.z * 1.03;
		float g = cw_noise(vec2(t * 3.0, c * 55.0));
		float rings = sin(c * 140.0 + g * 7.0 + t * 1.3) * 0.5 + 0.5;
		col *= 0.8 + 0.16 * rings + 0.1 * g;
		col = mix(col, col * 0.78, 0.4 * scuff);
		rough = clamp(rough + 0.08 * (g - 0.5), 0.05, 1.0);
		spec = 0.4;
	} else if (finish == 6) {
		// Fibreglass: glossy, with faint fibres along the axis showing through.
		vec3 a = normalize(grain_axis);
		float t = dot(lp, a);
		vec3 perp = lp - a * t;
		float c = perp.x * 1.09 + perp.y * 0.87 + perp.z * 1.21;
		float fib = cw_noise(vec2(t * 4.0, c * 420.0));
		col *= 0.92 + 0.14 * fib;
		col = mix(col, col * 0.85 + vec3(0.06), 0.5 * scuff);
		rough = clamp(rough + 0.08 * fib + 0.2 * scuff, 0.05, 1.0);
		spec = 0.55;
	} else {
		// Rubber / foam: matte, with fine pores.
		col *= 0.88 + 0.2 * fine;
		rough = clamp(rough + 0.06 * fine, 0.05, 1.0);
		spec = 0.25;
	}
}
