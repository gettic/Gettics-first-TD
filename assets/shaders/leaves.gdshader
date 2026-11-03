// The Quaternius leaf cards (trees near the board, bushes): the card texture only
// gives the leaves' shape (alpha); the colour comes from leaves.gdshaderinc.
shader_type spatial;
render_mode diffuse_lambert_wrap, cull_disabled;
#include "res://assets/shaders/leaves.gdshaderinc"

void fragment() {
	ALPHA = texture(leaf_tex, UV).a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	vec3 c = leaf_snow(leaf_color(1.0), (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.5;
	EMISSION = leaf_rim(c, NORMAL, VIEW);
}
