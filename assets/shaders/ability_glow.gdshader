// Glowing marks on the ground for the abilities: a ring with a soft disc inside
// (Meteor's aim and its shock wave), and for Freeze all a frost pattern that a
// wave carries out from the middle. Added on top of the ground, so it only lights.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float energy = 1.0;
uniform float ring = 0.95;  // the ring's distance from the middle (1: the plane's edge)
uniform float width = 0.04;
uniform float fill = 0.0;  // the soft disc inside the ring
uniform float frost = 0.0;  // ice crystals inside the ring (Freeze all)
uniform vec2 aspect = vec2(1.0);  // the plane's sides compared to its longest, so rings stay round
uniform float tiles = 30.0;  // the plane's longest side in tiles (the frost's size)
uniform float alpha = 1.0;

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

// Thin bright lines in three directions, bent a little by noise: like cracks in ice
float crystals(vec2 p) {
	p += vec2(noise(p * 0.7), noise(p * 0.7 + 9.1)) * 1.4;
	float f = 0.0;
	for (int i = 0; i < 3; i++) {
		float a = float(i) * 2.094 + 0.4;
		float s = dot(p, vec2(cos(a), sin(a)));
		f = max(f, 1.0 - abs(fract(s) - 0.5) * 2.0);
	}
	return pow(f, 10.0);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0 * aspect;
	float d = length(q);
	float a = exp(-pow((d - ring) / width, 2.0));
	float inside = 1.0 - smoothstep(ring - 0.02, ring + 0.02, d);
	a += fill * inside * (0.35 + 0.65 * d / max(ring, 0.01));
	if (frost > 0.0) {
		vec2 w = UV * aspect * tiles;
		// Tiny glints: a few random cells, each a round dot
		vec2 g = w * 6.0;
		float glint = step(0.993, hash(floor(g))) * (1.0 - smoothstep(0.1, 0.4, length(fract(g) - 0.5)));
		a += frost * inside * (crystals(w) + glint * 1.5 + 0.1);
	}
	ALBEDO = tint.rgb * energy;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
