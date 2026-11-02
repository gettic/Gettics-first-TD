// Monster shields: a glowing bubble, bright at its rim with a slow shimmer, all
// bubbles in one MultiMesh (see special_fx() in game_world.gd).
// INSTANCE_CUSTOM.x: 0 while it holds, then 0-1 as it cracks and breaks apart;
// y: a random seed.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.45, 0.75, 1.0);
uniform float energy = 1.0;
uniform float now = 0.0;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

varying float brk;
varying float seed;

void vertex() {
	brk = INSTANCE_CUSTOM.x;
	seed = INSTANCE_CUSTOM.y;
	VERTEX *= 1.0 + brk * 0.25;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float n = texture(noise, UV * vec2(3.0, 1.5) + vec2(now * 0.04, seed)).r;
	float a = rim * 0.9 + 0.08 + 0.12 * n;
	if (brk > 0.0) {
		// Cracks run where the noise crosses the middle, then it all fades
		float crack = 1.0 - smoothstep(0.0, 0.035, abs(n - 0.5));
		a = (a + crack * 2.5 * (1.0 - brk * 0.5)) * (1.0 - brk);
	}
	ALBEDO = tint * energy;
	ALPHA = clamp(a * 0.75, 0.0, 1.0);
}
