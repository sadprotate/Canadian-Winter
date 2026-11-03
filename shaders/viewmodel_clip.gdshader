// First-person tool parts (polish 2 §5). The viewmodel is drawn shrunk toward the eye so it never
// clips into walls; that also put a blade pushed into deep snow on top of the snow. This shader
// works out where each fragment would really be (un-shrinking it about the eye) and hides the
// part that is under the snow surface at the blade, with a thin white rim where it goes in.
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.8;
uniform float metallic = 0.0;
global uniform vec3 vm_eye;
global uniform float vm_snow_y;
const float VM_SCALE = 0.12;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 real_pos = vm_eye + (v_world - vm_eye) / VM_SCALE;
	float under = vm_snow_y - real_pos.y;
	if (under > 0.0) {
		discard;
	}
	float rim = 1.0 - smoothstep(0.0, 0.035, -under);
	ALBEDO = mix(albedo.rgb, vec3(0.95, 0.96, 1.0), rim * 0.85);
	ROUGHNESS = mix(roughness, 0.9, rim);
	METALLIC = metallic * (1.0 - rim);
}
