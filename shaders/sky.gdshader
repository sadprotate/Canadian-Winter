// Stylized winter sky: purple-blue zenith, pink/orange dusk band, soft clouds, stars at night.
shader_type sky;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 zenith : source_color = vec3(0.36, 0.38, 0.72);
uniform vec3 horizon : source_color = vec3(0.78, 0.66, 0.82);
uniform vec3 dusk : source_color = vec3(1.0, 0.62, 0.55);
uniform float dusk_strength = 0.8;
uniform vec3 ground : source_color = vec3(0.62, 0.62, 0.75);
uniform vec3 cloud_lit : source_color = vec3(0.98, 0.78, 0.82);
uniform vec3 cloud_dark : source_color = vec3(0.55, 0.52, 0.72);
uniform float cloud_cover = 0.35;
uniform float overcast = 0.0;
uniform vec3 overcast_color : source_color = vec3(0.62, 0.63, 0.7);
uniform float stars = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.1, -1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.8, 0.6);
uniform float time_offset = 0.0;

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = mix(horizon, zenith, smoothstep(-0.02, 0.55, y));
	vec3 sd = normalize(sun_dir);
	float toward = dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sd.x, 0.0, sd.z))) * 0.5 + 0.5;
	col = mix(col, dusk, dusk_strength * exp(-max(y, 0.0) * 7.0) * (0.35 + 0.65 * toward));
	float sdot = max(dot(d, sd), 0.0);
	col += sun_color * (pow(sdot, 900.0) * 3.0 + pow(sdot, 12.0) * 0.25) * (1.0 - overcast);
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.12);
		float c = cw_fbm(uv * 0.55 + vec2(time_offset * 0.004, time_offset * 0.0015));
		float m = smoothstep(1.0 - cloud_cover - 0.15, 1.0 - cloud_cover + 0.35, c) * smoothstep(0.0, 0.12, y);
		vec3 cc = mix(cloud_dark, cloud_lit, smoothstep(0.35, 0.8, cw_fbm(uv * 1.3 + 3.0)) * (0.4 + 0.6 * toward));
		col = mix(col, cc, m * 0.85);
		float st = step(0.9975, cw_hash(floor(d.xz / (y + 0.3) * 160.0)));
		col += vec3(st) * stars * (1.0 - m) * smoothstep(0.05, 0.3, y);
	}
	col = mix(col, overcast_color, overcast);
	if (y < 0.0) {
		col = mix(col, ground, smoothstep(0.0, -0.25, y));
	}
	COLOR = col;
}
