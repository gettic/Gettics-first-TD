// Burnt ground where a Meteor hit: a dark patch with a ragged edge and glowing
// cracks that cool down (embers 1 to 0), then the whole patch fades (alpha).
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform float alpha = 1.0;
uniform float embers = 1.0;
uniform float seed = 0.0;  // a different patch each time

// No sin(): it loses precision on some graphics cards and the noise gets blocky
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	vec2 s = vec2(seed * 7.3, seed * 3.1);
	float n = noise(q * 3.0 + s) * 0.6 + noise(q * 8.0 - s) * 0.4;
	float edge = 0.62 + n * 0.38;  // ragged
	float burn = 1.0 - smoothstep(edge - 0.4, edge, d);
	vec3 col = mix(vec3(0.1, 0.075, 0.05), vec3(0.015, 0.01, 0.008), smoothstep(0.2, 0.8, burn));
	// Cracks: where slow noise crosses the middle, more toward the center
	float c = abs(noise(q * 6.0 + s * 2.0) - 0.5);
	float crack = (1.0 - smoothstep(0.0, 0.045, c)) * smoothstep(0.35, 0.9, burn);
	float hot = embers * (crack * 1.5 + smoothstep(0.5, 0.0, d) * 0.6 * embers);
	ALBEDO = col + vec3(1.0, 0.32, 0.06) * hot * 4.0;
	ALPHA = clamp((burn * 0.88 + crack * embers * 0.5) * alpha, 0.0, 1.0);
}
