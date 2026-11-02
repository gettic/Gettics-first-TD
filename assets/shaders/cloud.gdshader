// Poison clouds: a swirling green haze lying on the ground, all clouds in one
// MultiMesh (see show_cloud() in game_world.gd). Each cloud's INSTANCE_CUSTOM:
// x when it was made, y how long it lasts (seconds on the clouds' clock "now"),
// z a random seed, w the path (0 plain, 1 Venom, 2 Miasma).
// With puffs = true it draws the puffs above the haze instead: soft blobs that
// always face the camera and drift and swirl.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float now = 0.0;
uniform bool puffs = false;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float strength = 1.0;  // overall thickness (lower on Compatibility, which blends brighter)
uniform vec3 plain_lit : source_color = vec3(0.55, 1.0, 0.25);
uniform vec3 plain_dark : source_color = vec3(0.1, 0.38, 0.05);
uniform vec3 venom_lit : source_color = vec3(0.85, 1.0, 0.25);
uniform vec3 venom_dark : source_color = vec3(0.3, 0.5, 0.0);
uniform vec3 miasma_lit : source_color = vec3(0.45, 0.58, 0.3);
uniform vec3 miasma_dark : source_color = vec3(0.13, 0.14, 0.12);

varying float fade;
varying float seed;
varying float path;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float age = now - c.x;
	fade = smoothstep(0.0, 0.45, age) * clamp((c.y - age) / 1.2, 0.0, 1.0);
	seed = c.z;
	path = c.w;
	float grow = mix(0.5, 1.0, smoothstep(0.0, 0.6, age));
	if (puffs) {
		// Billboard: the quad turns to the camera, keeps the instance's size,
		// and drifts round its spot, rising a little as the cloud ages
		vec3 center = MODEL_MATRIX[3].xyz;
		float size = length(MODEL_MATRIX[0].xyz) * grow;
		float t = now * 0.35 + seed * 6.28;
		center += vec3(cos(t), 0.0, sin(t * 1.3)) * size * 0.18;
		center.y += size * (0.1 + 0.12 * clamp(age / max(c.y, 0.1), 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2], vec4(center, 1.0));
	} else {
		VERTEX.xz *= grow;
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float t = now * 0.04;
	vec2 q = UV * 0.7 + seed;
	// Two layers of noise sliding past each other: the haze swirls
	float n1 = texture(noise, q + vec2(t, -t * 0.7)).r;
	float n2 = texture(noise, q * 2.1 - vec2(t * 1.6, t * 0.5)).r;
	float n = n1 * 0.62 + n2 * 0.38;
	vec3 lit = plain_lit;
	vec3 dark = plain_dark;
	float thick = 0.56;
	if (path > 1.5) {
		lit = miasma_lit;
		dark = miasma_dark;
		thick = 0.68;
	} else if (path > 0.5) {
		lit = venom_lit;
		dark = venom_dark;
		thick = 0.58;
	}
	float a;
	if (puffs) {
		a = (1.0 - smoothstep(0.25, 1.0, d + (n - 0.5) * 0.5)) * (0.25 + 0.75 * n) * 0.3;
	} else {
		// Thick in the middle, a ragged edge
		a = (1.0 - smoothstep(0.45, 1.0, d + (n - 0.5) * 0.55)) * (0.45 + 0.55 * n);
	}
	ALBEDO = mix(dark, lit * 1.2, smoothstep(0.2, 0.85, n + (1.0 - d) * 0.25));
	ALPHA = clamp(a * thick * fade * strength, 0.0, 1.0);
}
