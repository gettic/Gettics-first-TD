// Material for the KayKit models: their one palette texture, the owner's color
// and a soft rim light on the edges (no outlines).
shader_type spatial;

uniform sampler2D palette : source_color, filter_linear_mipmap, repeat_disable;
// The pack's blue team color is the palette cell at the bottom left. The red,
// yellow and green cells are next to it, so moving the blue parts' UVs right by
// 1/8 per step gives the owner's color (0 blue, 1 red, 2 yellow, 3 green).
uniform float team = 0.0;
uniform vec3 rim_color : source_color = vec3(1.0, 0.92, 0.78);
uniform float rim_strength = 0.3;
uniform float rim_power = 3.0;

void vertex() {
	if (UV.x < 0.125 && UV.y > 0.75) {
		UV.x += team * 0.125;
	}
}

void fragment() {
	vec3 col = texture(palette, UV).rgb;
	ALBEDO = col;
	ROUGHNESS = 0.6;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color * mix(vec3(1.0), col, 0.5) * rim * rim_strength;
}
