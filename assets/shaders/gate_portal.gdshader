// A gate's portal: a slow purple and green swirl of the Hollow's light, turning
// inward, with a bright heart. Drawn in the gate's opening (see build_gate()).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 deep : source_color = vec3(0.01, 0.07, 0.04);
uniform vec3 mid : source_color = vec3(0.1, 0.55, 0.25);
uniform vec3 glow : source_color = vec3(0.45, 1.0, 0.55);
uniform vec3 core : source_color = vec3(0.9, 1.0, 0.75);
uniform float energy = 1.25;
uniform vec2 center = vec2(0.5, 0.58);
uniform vec2 stretch = vec2(1.0, 1.25);
uniform float open = 1.0;  // 0: closed (dark), 1: open

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

mat2 rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

void fragment() {
	vec2 p = (UV - center) * stretch;
	float r = length(p);
	float t = TIME;
	// Turned more near the middle: the swirl
	vec2 q = rot(t * 0.9 + 1.6 / (r + 0.18)) * p;
	float n = noise(q * 5.0 + 3.1) * 0.6 + noise(q * 11.0 - 1.7) * 0.4;
	float arms = 0.5 + 0.5 * sin(atan(q.y, q.x) * 3.0 + r * 9.0);
	float v = clamp(n * 0.7 + arms * 0.55 - 0.15, 0.0, 1.0);
	// Painted bands: a few flat steps of color, like brush strokes
	v = floor(v * 4.0 + 0.5) / 4.0;
	vec3 col = mix(deep, mid, smoothstep(0.0, 0.5, v));
	col = mix(col, glow, smoothstep(0.5, 1.0, v));
	col += core * smoothstep(0.2, 0.0, r) * 0.6;
	// Darker toward the stone edge
	col *= mix(1.0, 0.45, smoothstep(0.25, 0.62, r));
	ALBEDO = col * energy * open;
	ALPHA = mix(0.0, 0.94, open);
}
