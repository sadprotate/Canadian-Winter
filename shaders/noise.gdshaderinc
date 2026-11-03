// Shared procedural noise helpers (no textures needed).
float cw_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Hash for large integer cell coordinates (sparkle cells are ~2 cm, so world coords reach
// ~10 000): the fract-multiply hash above loses precision there and lines the glints up in rows.
float cw_hash_cell(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float cw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = cw_hash(i);
	float b = cw_hash(i + vec2(1.0, 0.0));
	float c = cw_hash(i + vec2(0.0, 1.0));
	float d = cw_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float cw_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * cw_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}
