// Snow carried on a first-person blade (polish 2 §5): soft white snow that, like the blade itself
// (viewmodel_clip), is hidden where it would really be under the snow surface.
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

global uniform vec3 vm_eye;
global uniform float vm_snow_y;
const float VM_SCALE = 0.12;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 real_pos = vm_eye + (v_world - vm_eye) / VM_SCALE;
	if (real_pos.y < vm_snow_y) {
		discard;
	}
	ALBEDO = vec3(0.95, 0.96, 1.0);
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.18, 0.2, 0.26);
}
