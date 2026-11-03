// Shared by leaves.gdshader (the Quaternius leaf cards) and crown.gdshader (the
// far forest's solid stand-in crowns): the colour comes from the painted crown AO in
// the vertex colours (dark inside and underneath, light at the crown's top and
// edges, see build_nature.py) through three greens, with a slow shift per tree.
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap;
uniform vec3 dark : source_color = vec3(0.05, 0.12, 0.07);
uniform vec3 mid : source_color = vec3(0.14, 0.29, 0.11);
uniform vec3 top_col : source_color = vec3(0.42, 0.54, 0.19);
uniform float lo = 0.35;
uniform float hi = 0.98;
uniform float sway = 1.0;
uniform vec3 rim_color : source_color = vec3(0.7, 0.85, 0.5);
uniform float rim_strength = 0.1;
global uniform vec4 mood_rim;  // the weather's rim (see painted.gdshader)
global uniform float fest_snow;  // Frostfall Fair: snow on the crowns' tops
uniform float frost = 0.0;  // the snow weather: a lighter dusting (see mood_light())
varying float ao;
varying vec3 wp;
varying vec3 lp;  // the model's own position (crown.gdshader's leaf pattern)

void vertex() {
	ao = COLOR.g;
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// A slow sway, more toward the top (the model's metres, before its scale)
	VERTEX.x += sin(TIME * 1.3 + wp.x * 0.7 + wp.z * 0.4 + VERTEX.y * 0.6) * 0.03 * sway * max(VERTEX.y - 1.0, 0.0);
}

vec3 leaf_color(float detail) {
	float k = clamp((ao - lo) / (hi - lo), 0.0, 1.0) * detail;
	float v = sin(wp.x * 1.7 + wp.z * 2.3) * 0.5 + 0.5;
	vec3 c = k < 0.5 ? mix(dark, mid, k * 2.0) : mix(mid, top_col, (k - 0.5) * 2.0);
	return c * mix(vec3(0.9, 1.0, 0.92), vec3(1.08, 1.02, 0.86), v);
}

// Snow on the tops (wn: world normal) and the rim's light (in view space)
vec3 leaf_snow(vec3 c, vec3 wn) {
	return mix(c, vec3(0.86, 0.9, 0.97), max(fest_snow, frost * 0.7) * smoothstep(0.55, 0.85, wn.y));
}

vec3 leaf_rim(vec3 c, vec3 normal, vec3 view) {
	float rim = pow(clamp(1.0 - dot(normal, view), 0.0, 1.0), 3.0);
	vec3 rc = mood_rim.a > 0.0 ? mood_rim.rgb : rim_color;
	float rs = mood_rim.a > 0.0 ? rim_strength * mood_rim.a : rim_strength;
	return rc * c * rim * rs;
}
