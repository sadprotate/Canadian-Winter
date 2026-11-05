// Polish 5 §6: hand tools and walk-behind blowers as seen in the world and in third person —
// plastic, aluminium, steel, wood, fibreglass or rubber with a little wear (tool_surface).
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://shaders/tool_surface.gdshaderinc"

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 col;
	float r;
	float m;
	float s;
	tool_surface(v_local, UV, col, r, m, s);
	ALBEDO = col;
	ROUGHNESS = r;
	METALLIC = m;
	SPECULAR = s;
}
