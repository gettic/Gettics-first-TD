// Water: calm ponds on the map's water tiles. A tiny image with one pixel per
// water cell (like the path mask) gives the soft, ragged edge into the muddy bank.
shader_type spatial;

uniform sampler2D water_mask : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(24.0, 18.0);
uniform vec3 deep_color : source_color = vec3(0.09, 0.25, 0.29);
uniform vec3 shallow_color : source_color = vec3(0.2, 0.34, 0.3);
uniform vec3 crest_color : source_color = vec3(0.3, 0.45, 0.45);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Slow ripples: a few sine waves running different ways (about -1.5 to 1.5).
// Smooth everywhere, so the light on them has no seams.
float ripples(vec2 p, float t) {
	return sin(p.x * 2.1 + p.y * 0.7 + t * 0.9) * 0.5
		+ sin(p.y * 2.6 - p.x * 1.1 - t * 0.7) * 0.5
		+ sin((p.x + p.y) * 4.3 + t * 1.4) * 0.3
		+ sin((p.x - p.y) * 5.1 - t * 1.1) * 0.2;
}

void fragment() {
	float m = texture(water_mask, wpos.xz / map_size).r;
	float n = noise(wpos.xz * 3.0) * 0.65 + noise(wpos.xz * 9.0) * 0.35 - 0.5;
	// 0 at the bank, 1 inside the pond
	float edge = smoothstep(0.5, 0.72, m + n * 0.3);
	vec2 p = wpos.xz * 1.6;
	float r = ripples(p, TIME);
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.65, 1.0, m));
	// Lighter where the waves crest, broken up a little by slow noise
	float crest = smoothstep(0.7, 1.2, r) * (0.5 + noise(wpos.xz * 1.3 + TIME * 0.1) * 0.5);
	col = mix(col, crest_color, crest * 0.45);
	ALBEDO = col;
	ALPHA = edge * 0.88;
	ROUGHNESS = 0.4;
	SPECULAR = 0.4;
	// The ripples' slope tilts the surface a little, so the sun glints on them
	float gx = ripples(p + vec2(0.05, 0.0), TIME) - r;
	float gy = ripples(p + vec2(0.0, 0.05), TIME) - r;
	NORMAL_MAP = normalize(vec3(-gx * 0.8, -gy * 0.8, 1.0)) * 0.5 + 0.5;
}