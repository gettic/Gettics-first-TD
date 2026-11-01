// Painted look for models (towers, monsters, gates, trees): soft wrapped light,
// a warm rim, tops catching more light, and darker toward the ground, like the
// baked light in hand-painted textures. The game makes one from each model
// material (see painted() in game_world.gd).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform bool use_vcol = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool use_normal = false;
uniform float normal_depth = 1.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float saturation = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 rim_color : source_color = vec3(1.0, 0.9, 0.75);
uniform float rim_strength = 0.3;
uniform float rim_power = 3.0;
uniform float grad_low = 0.7;    // brightness at the foot (height 0)
uniform float grad_high = 1.1;   // brightness at grad_top
uniform float grad_top = 1.2;    // world height
uniform float top_light = 0.15;  // extra light on surfaces that face up
uniform float rough = 0.8;
varying float wy;
varying vec3 vcol;

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	vcol = COLOR.rgb;
}

void fragment() {
	vec3 col = albedo.rgb * texture(albedo_tex, UV).rgb;
	if (use_vcol) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		col *= vcol;
#else
		col *= pow(max(vcol, vec3(0.0)), vec3(2.2));  // MSAA edge samples can go below 0: pow would give NaN
#endif
	}
	col = mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, saturation) * tint;
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	col *= mix(grad_low, grad_high, clamp(wy / grad_top, 0.0, 1.0));
	col *= 1.0 + top_light * max(wn.y, 0.0);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	float rim = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = emission * emission_energy + rim_color * mix(vec3(1.0), col, 0.5) * rim * rim_strength;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
}
