// The Poison tower's glowing brew (the cauldron, drips, sluice and stills):
// its painted texture glowing, slowly pulsing, each spot a little out of step.
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float energy = 1.4;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float pulse = 0.82 + 0.18 * sin(TIME * 2.2 + wp.x * 2.7 + wp.z * 1.9 + wp.y * 3.1);
	ALBEDO = c * 0.35;
	ROUGHNESS = 0.35;
	EMISSION = c * energy * pulse;
}
