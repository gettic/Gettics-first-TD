// The board's wall: CC0 stone scans (Poly Haven) laid on from three sides in world
// space, graded to a grey stone colour (the scan's light and dark, a little of its
// hue). Grey stone took on the cool fill light's violet in the shade, so here cool
// lights are partly greyed: the shade stays cool and dark, not violet; the sun stays
// warm. Snow on top for the Frostfall Fair.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 avg = vec3(0.0862, 0.0721, 0.0498);  // the scan's linear average (build_ground_tex.py)
uniform vec3 stone : source_color = vec3(0.41, 0.4, 0.38);
uniform float hue = 0.3;
uniform float detail = 0.9;
uniform float scale = 1.3;
uniform bool use_normals = true;
uniform float cool_grey = 0.7;  // how much of a cool light's colour is taken out
global uniform float fest_snow;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2D s, vec3 w) {
	return texture(s, wpos.zy * scale) * w.x + texture(s, wpos.xz * scale) * w.y + texture(s, wpos.xy * scale) * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 a = avg;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	a = pow(max(a, vec3(0.0)), vec3(1.0 / 2.2));
#endif
	vec3 t = tri(albedo_tex, w).rgb;
	const vec3 W = vec3(0.2126, 0.7152, 0.0722);
	vec3 rel = mix(vec3(dot(t, W) / max(dot(a, W), 1e-4)), t / max(a, vec3(1e-4)), hue);
	vec3 col = stone * mix(vec3(1.0), rel, detail);
	col = mix(col, vec3(0.88, 0.92, 0.98), fest_snow * smoothstep(0.6, 0.85, wnrm.y));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
	if (use_normals) {
		NORMAL_MAP = tri(normal_tex, w).rgb;
		NORMAL_MAP_DEPTH = 0.8;
	}
}

void light() {
	vec3 c = LIGHT_COLOR;
	float cool = clamp((c.b - c.r) / max(c.b, 0.001) * 2.0, 0.0, 1.0);
	c = mix(c, vec3(dot(c, vec3(0.3, 0.45, 0.25))), cool * cool_grey);
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * c / PI;
}
