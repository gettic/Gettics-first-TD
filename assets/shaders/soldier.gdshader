// Barracks soldiers: the painted look (see painted.gdshader) drawn with
// MultiMeshes. Each soldier's owner color comes in its custom data and tints
// the team parts (marked in the vertex color's alpha: tabard, plume, shield).
// Its alpha 0 means Black: the team parts get a strong silver rim to show.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform float saturation = 1.15;
uniform vec3 rim_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float rim_strength = 0.35;
uniform float grad_low = 0.75;
uniform float grad_high = 1.15;
uniform float grad_top = 0.5;
uniform float top_light = 0.2;
global uniform vec4 mood_rim;  // the weather's rim (see painted.gdshader)
varying float wy;
varying vec3 team;
varying float mask;
varying float dark;

void vertex() {
	wy = VERTEX.y;
	team = INSTANCE_CUSTOM.rgb;
	mask = COLOR.a;
	dark = 1.0 - INSTANCE_CUSTOM.a;
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;
	col = mix(col, col * team, clamp(mask, 0.0, 1.0));
	col = mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, saturation);
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	col *= mix(grad_low, grad_high, clamp(wy / grad_top, 0.0, 1.0));
	col *= 1.0 + top_light * max(wn.y, 0.0);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	float rim = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 rc = mood_rim.a > 0.0 ? mood_rim.rgb : rim_color;
	float rs = mood_rim.a > 0.0 ? rim_strength * mood_rim.a : rim_strength;
	rc = mix(rc, vec3(0.82, 0.88, 1.0), dark * mask);
	rs *= 1.0 + 4.0 * dark * clamp(mask, 0.0, 1.0);
	EMISSION = rc * mix(vec3(1.0), col, 0.5) * rim * rs;
}
