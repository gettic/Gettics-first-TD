// The thick grass tufts (built in code, see build_life() in game_world.gd): vertex
// colours (alpha = height up the blade), a little wind at the tips, lit like the
// ground under them so the blades' backs never go black. Tufts on a tower's tile
// close to the tower's middle shrink away (tower_mask, one pixel per tile), so
// towers never stand in grass. Frosted tips for the Frostfall Fair.
shader_type spatial;
render_mode cull_disabled;

uniform float wind = 1.0;
uniform float tip_light = 0.25;
uniform sampler2D tower_mask : filter_nearest, repeat_disable;
uniform vec2 map_size = vec2(24.0, 18.0);
global uniform float fest_snow;
uniform float frost = 0.0;  // the snow weather (see mood_light())
varying float tip;
varying vec3 wp;

void vertex() {
	tip = COLOR.a;
	wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 cell = floor(wp.xz);
	if (all(greaterThanEqual(cell, vec2(0.0))) && all(lessThan(cell, map_size))
			&& texture(tower_mask, (cell + 0.5) / map_size).r > 0.5 && length(wp.xz - cell - 0.5) < 0.45) {
		VERTEX = vec3(0.0);
	}
	float s = sin(TIME * 1.7 + wp.x * 0.8 + wp.z * 0.55) * 0.05 * tip * tip * wind;
	VERTEX.x += s;
	VERTEX.z += s * 0.6;
	NORMAL = mix(vec3(0.0, 1.0, 0.0), NORMAL, 0.25);
}

void fragment() {
	// a slow patchy colour shift, so the meadow isn't one green
	float n = sin(wp.x * 0.37 + sin(wp.z * 0.21) * 2.0) * 0.5 + 0.5;
	vec3 c = COLOR.rgb * mix(vec3(0.92, 1.0, 0.85), vec3(1.12, 1.04, 0.8), n);
	c *= 1.0 + tip * tip_light;
	c = mix(c, vec3(0.85, 0.9, 0.96), max(fest_snow, frost * 0.8) * smoothstep(0.4, 1.0, tip));
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.35, 0.4, 0.15) * tip;
}
