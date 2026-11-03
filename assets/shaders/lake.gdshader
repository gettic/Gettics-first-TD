// Stylized lake: an oval pond with painted wave streaks, a dark wet bank
// at the shore (no bright ring) and glints. Opaque, so it costs little.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec2 center = vec2(8.0, -5.0);
uniform vec2 radius = vec2(4.0, 2.2);
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.2);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.3, 0.32);
uniform vec3 foam_color : source_color = vec3(0.6, 0.72, 0.75);
uniform vec3 shore_color : source_color = vec3(0.1, 0.17, 0.15);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// A random number per grid corner (see ground.gdshader for why not fract(sin(...)))
float hash(vec2 p) {
	vec3 p3 = fract(vec3(mod(p, 512.0).xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float ripples(vec2 p, float t) {
	return sin(p.x * 2.1 + p.y * 0.7 + t * 0.9) * 0.5 + sin(p.y * 2.6 - p.x * 1.1 - t * 0.7) * 0.5
		+ sin((p.x + p.y) * 4.3 + t * 1.4) * 0.3;
}

void fragment() {
	vec2 q = (wpos.xz - center) / radius;
	float r = length(q) + (noise(wpos.xz * 1.3) - 0.5) * 0.25;
	if (r > 1.0) {
		discard;
	}
	float depth = smoothstep(1.0, 0.25, r);
	vec3 col = mix(shallow_color, deep_color, depth);
	// Painted wave streaks drifting across
	float w = sin(wpos.x * 2.5 + wpos.z * 1.2 + TIME * 1.1 + noise(wpos.xz * 1.7) * 5.0);
	col = mix(col, foam_color, smoothstep(0.93, 1.0, w) * 0.2);
	// A dark wet bank at the shore, breathing in and out
	float f = smoothstep(0.9, 0.97, r + sin(TIME * 1.4 + noise(wpos.xz * 3.0) * 6.0) * 0.035);
	col = mix(col, shore_color, f * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.3;
	SPECULAR = 0.45;
	vec2 p = wpos.xz * 1.6;
	float rr = ripples(p, TIME);
	float gx = ripples(p + vec2(0.05, 0.0), TIME) - rr;
	float gy = ripples(p + vec2(0.0, 0.05), TIME) - rr;
	NORMAL_MAP = normalize(vec3(-gx * 0.8, -gy * 0.8, 1.0)) * 0.5 + 0.5;
}
