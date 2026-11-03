// The painted look (see painted.gdshader) for the code-built trees and bushes:
// their colors come from the mesh (dark in the crevices, light at the edges),
// with a painted leaf texture laid over from three sides, so no UVs are needed.
// The trunks (color alpha 0) get no leaves. See add_trees() in game_world.gd.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float leaf_scale = 2.2;
uniform float leaf_amount = 1.0;
uniform vec3 rim_color : source_color = vec3(1.0, 0.9, 0.75);
uniform float rim_strength = 0.3;
uniform float rim_power = 3.0;
uniform float grad_low = 0.7;    // brightness at the foot (height 0)
uniform float grad_high = 1.1;   // brightness at grad_top
uniform float grad_top = 1.2;    // world height
uniform float top_light = 0.15;  // extra light on surfaces that face up
global uniform vec4 mood_rim;  // the weather's rim (see painted.gdshader)
global uniform float fest_snow;  // Frostfall Fair: snow on the leaves' tops (0-1, see apply_festival())
varying float wy;
varying vec3 vcol;
varying float leafy;
varying vec3 lp;
varying vec3 ln;

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	vcol = COLOR.rgb;  // with the MultiMesh's per-tree color
	leafy = COLOR.a;
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 w = pow(abs(normalize(ln)), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = lp * leaf_scale;
	vec3 leaf = texture(leaf_tex, p.zy).rgb * w.x + texture(leaf_tex, p.xz).rgb * w.y + texture(leaf_tex, p.xy).rgb * w.z;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 col = vcol;
#else
	vec3 col = pow(max(vcol, vec3(0.0)), vec3(2.2));  // MSAA edge samples can go below 0: pow would give NaN
#endif
	col *= mix(vec3(1.0), leaf * 1.85, leaf_amount * clamp(leafy, 0.0, 1.0));
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	col *= mix(grad_low, grad_high, clamp(wy / grad_top, 0.0, 1.0));
	col *= 1.0 + top_light * max(wn.y, 0.0);
	float snow = fest_snow * clamp(leafy, 0.0, 1.0) * smoothstep(0.74, 0.9, wn.y + (dot(leaf, vec3(0.333)) - 0.32) * 0.5);
	col = mix(col, vec3(0.86, 0.9, 0.97) * (0.8 + 0.25 * clamp(wy / grad_top, 0.0, 1.0)), snow);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	float rim = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	vec3 rc = mood_rim.a > 0.0 ? mood_rim.rgb : rim_color;
	float rs = mood_rim.a > 0.0 ? rim_strength * mood_rim.a : rim_strength;
	EMISSION = rc * mix(vec3(1.0), col, 0.5) * rim * rs;
}
