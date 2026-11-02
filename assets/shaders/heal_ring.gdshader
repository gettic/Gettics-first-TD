// A healer's pulse: a golden ring running out over the ground to the heal's
// reach, with a soft glow behind it. All rings in one MultiMesh (see
// special_fx() in game_world.gd). INSTANCE_CUSTOM.x: 0-1 through the pulse.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.82, 0.35);
uniform float energy = 0.9;

varying float k;

void vertex() {
	k = INSTANCE_CUSTOM.x;
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float r = 1.0 - (1.0 - k) * (1.0 - k);
	float a = exp(-pow((d - r) / 0.05, 2.0)) + (1.0 - smoothstep(r - 0.1, r, d)) * 0.12 * d;
	ALBEDO = tint * energy;
	ALPHA = clamp(a * (1.0 - k) * 0.75, 0.0, 1.0);
}
