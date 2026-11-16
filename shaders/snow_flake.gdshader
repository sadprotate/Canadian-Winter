// Polish 8 §7: falling snow, streaks and blowing snow (WeatherFX's particle layers).
// One frame of the procedural atlas per particle (crystals, a soft flake, a streak), drawn as a
// camera-facing billboard (turning with the particle) or, with `stretch`, as a streak along the
// particle's velocity (ParticleProcessMaterial's align-Y flag) turned to face the camera.
// No flake shows inside a building: a particle whose centre is inside a hide volume (a Buildings
// footprint, x0 z0 x1 z1, below its eaves `hide_cut`) is discarded, as snow_ground.gdshader does
// with its hide uniforms; one near a building is tested pixel by pixel, so a streak passing a wall
// never pokes through it. At night flakes near a lamp (street lamps, porch lanterns) catch its
// light and glint.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform int frames_h = 4;
uniform int frames_v = 2;
uniform int frame_lo = 0;
uniform int frame_hi = 5;
uniform float alpha = 0.9;
uniform bool stretch = false;
uniform float stretch_len = 0.6;     // m, a streak's length (± 40 % per particle)
uniform float flutter = 0.0;         // m, sideways flutter of a falling flake
uniform float near_fade = 0.6;       // m: closer to the camera than this, a particle fades out
uniform float gust = 0.0;            // 0..1: a gust shows as denser, brighter snow
uniform vec4 hide_rects[64];
uniform float hide_cut[64];
uniform int hide_count = 0;
uniform vec4 lamps[16];              // xyz, radius (m)
uniform int lamp_count = 0;
global uniform float night_factor;

varying float v_hide;
varying float v_near;
varying vec3 v_wpos;
varying float v_alpha;
varying vec3 v_color;

bool hidden_at(vec3 p) {
	for (int i = 0; i < hide_count; i++) {
		vec4 r = hide_rects[i];
		if (p.x > r.x && p.x < r.z && p.z > r.y && p.z < r.w && p.y < hide_cut[i]) {
			return true;
		}
	}
	return false;
}

// Within m of a hide volume (the particle may reach into it).
bool near_any(vec3 p, float m) {
	for (int i = 0; i < hide_count; i++) {
		vec4 r = hide_rects[i];
		if (p.x > r.x - m && p.x < r.z + m && p.z > r.y - m && p.z < r.w + m && p.y < hide_cut[i] + m) {
			return true;
		}
	}
	return false;
}

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float seed = INSTANCE_CUSTOM.z;
	float sc = length(MODEL_MATRIX[0].xyz);
	v_hide = hidden_at(c) ? 1.0 : 0.0;
	// A falling flake drifts from side to side as it falls.
	float ph = seed * 61.0;
	c += vec3(sin(TIME * 1.3 + ph), 0.0, cos(TIME * 1.1 + ph * 1.7)) * flutter;
	vec3 to_cam = CAMERA_POSITION_WORLD - c;
	float dist = length(to_cam);
	vec3 wp;
	if (stretch) {
		vec3 axis = normalize(MODEL_MATRIX[1].xyz);
		vec3 side = cross(axis, to_cam / max(dist, 0.001));
		side = length(side) > 0.001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
		float len = stretch_len * (0.6 + 0.8 * fract(seed * 7.31)) * (1.0 + 0.5 * gust);
		wp = c + side * VERTEX.x * sc + axis * VERTEX.y * len;
	} else {
		float a = INSTANCE_CUSTOM.x;
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 up = INV_VIEW_MATRIX[1].xyz;
		vec2 q = vec2(VERTEX.x * cos(a) - VERTEX.y * sin(a), VERTEX.x * sin(a) + VERTEX.y * cos(a)) * sc;
		wp = c + right * q.x + up * q.y;
	}
	float reach = stretch ? stretch_len * 1.4 * (1.0 + 0.5 * gust) * 0.5 + sc : sc * 0.75;
	v_near = (v_hide < 0.5 && near_any(c, reach + 0.2)) ? 1.0 : 0.0;
	v_wpos = wp;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_cam, 0.0)).xyz);
	// The frame (fixed per particle).
	int total = max(frame_hi - frame_lo + 1, 1);
	float fr = float(frame_lo) + min(floor(seed * float(total)), float(total - 1));
	UV = UV / vec2(float(frames_h), float(frames_v)) + vec2(mod(fr, float(frames_h)) / float(frames_h), floor((fr + 0.5) / float(frames_h)) / float(frames_v));
	// Fade in and out over the particle's life, and close to the camera.
	float life = INSTANCE_CUSTOM.y;
	v_alpha = smoothstep(0.0, 0.06, life) * (1.0 - smoothstep(0.85, 1.0, life)) * smoothstep(near_fade * 0.4, near_fade, dist);
	v_alpha *= 1.0 + 0.35 * gust;
	// Light: white by day, dim at night except near a lamp, where it glints.
	vec3 col = mix(vec3(0.97, 0.98, 1.0), vec3(0.5, 0.53, 0.62), night_factor);
	vec3 glow = vec3(0.0);
	for (int i = 0; i < lamp_count; i++) {
		float d = distance(c, lamps[i].xyz);
		float k = 1.0 - smoothstep(0.0, lamps[i].w, d);
		glow += vec3(1.0, 0.82, 0.55) * k * k;
	}
	float twinkle = 0.55 + 0.45 * sin(TIME * 9.0 + seed * 97.0);
	v_color = col + glow * twinkle * 1.4 * night_factor;
}

void fragment() {
	if (v_hide > 0.5 || (v_near > 0.5 && hidden_at(v_wpos))) {
		discard;
	}
	float a = texture(atlas, UV).a * alpha * v_alpha;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = v_color;
	ALPHA = clamp(a, 0.0, 1.0);
}
