// The far forest's stand-in crowns (and every tree on Graphics Low): one closed,
// solid shell per crown, so no see-through leaf cards to sort and test. Same colours
// as the leaf cards (leaves.gdshaderinc), with the leaf texture laid on from above
// as a soft light-and-dark pattern, so the shell doesn't read as plastic.
shader_type spatial;
render_mode diffuse_lambert_wrap;
#include "res://assets/shaders/leaves.gdshaderinc"

void fragment() {
	float a = texture(leaf_tex, lp.xz * 0.35 + lp.y * 0.2).a;
	vec3 c = leaf_snow(leaf_color(1.0) * mix(0.8, 1.1, a), (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	EMISSION = leaf_rim(c, NORMAL, VIEW);
}
