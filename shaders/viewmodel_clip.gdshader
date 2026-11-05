// First-person tool parts (polish 2 §5). The viewmodel is drawn shrunk toward the eye so it never
// clips into walls; that also put a blade pushed into deep snow on top of the snow. This shader
// works out where each fragment would really be (un-shrinking it about the eye) and hides the
// part that is under the snow surface at the blade, with a thin white rim where it goes in.
// Polish 5 §6: the same surfaces as the tools in the world (tool_surface; `finish` 0 is the old
// plain colour), so the first-person parts read as plastic, aluminium, steel, wood…
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://shaders/tool_surface.gdshaderinc"

global uniform vec3 vm_eye;
global uniform float vm_snow_y;
const float VM_SCALE = 0.12;

varying vec3 v_world;
varying vec3 v_local;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX;
}

void fragment() {
	vec3 real_pos = vm_eye + (v_world - vm_eye) / VM_SCALE;
	float under = vm_snow_y - real_pos.y;
	if (under > 0.0) {
		discard;
	}
	vec3 col;
	float r;
	float m;
	float s;
	tool_surface(v_local, UV, col, r, m, s);
	float rim = 1.0 - smoothstep(0.0, 0.035, -under);
	ALBEDO = mix(col, vec3(0.95, 0.96, 1.0), rim * 0.85);
	ROUGHNESS = mix(r, 0.9, rim);
	METALLIC = m * (1.0 - rim);
	SPECULAR = s;
}
