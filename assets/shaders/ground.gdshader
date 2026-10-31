// Ground: grass and dirt textures laid out by world position, so they run across
// the tiles without seams. A tiny image with one pixel per cell marks the path,
// and its smooth filtering gives the ragged dirt edge next to the path.
shader_type spatial;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_mask : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(24.0, 18.0);
uniform float tex_scale = 0.4;  // texture repeats per tile (0.4 = once every 2.5 tiles)
// The textures' average colors (linear), so they can be tinted to the game's own green and brown
uniform vec3 grass_avg = vec3(0.1619, 0.2498, 0.08);
uniform vec3 dirt_avg = vec3(0.1362, 0.0958, 0.0494);
uniform vec3 grass_color : source_color = vec3(0.12, 0.26, 0.1);
uniform vec3 dirt_color : source_color = vec3(0.3, 0.2, 0.12);
uniform float detail = 0.85;  // 0 = flat color, 1 = the texture's full contrast
uniform float is_path = 0.0;
uniform float grid = 0.0;  // grid lines, faded in while placing a tower
uniform bool use_normals = false;  // Graphics High

varying vec3 wpos;
varying float up;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// Tops use X/Z; the sides (path edges, board edge) use the height instead
	vec2 uv = (up > 0.5 ? wpos.xz : vec2(wpos.x + wpos.z, wpos.y)) * tex_scale;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// The Compatibility renderer works with colors as stored (sRGB, not linear),
	// so the averages have to be in sRGB too, or the ground comes out 2-3x too bright
	vec3 g_avg = pow(grass_avg, vec3(1.0 / 2.2));
	vec3 d_avg = pow(dirt_avg, vec3(1.0 / 2.2));
#else
	vec3 g_avg = grass_avg;
	vec3 d_avg = dirt_avg;
#endif
	vec3 g = grass_color * mix(vec3(1.0), texture(grass_tex, uv).rgb / g_avg, detail);
	vec3 d = dirt_color * mix(vec3(1.0), texture(dirt_tex, uv).rgb / d_avg, detail);

	// How much dirt: sides are soil; on top, the path mask with a little noise
	float n = noise(wpos.xz * 3.0) * 0.65 + noise(wpos.xz * 9.0) * 0.35 - 0.5;
	float m = texture(path_mask, wpos.xz / map_size).r + n * 0.35;
	// The grass tiles' sides keep a thin grass rim at the top (the grass top is at height 0),
	// so no soil peeks out where neighbor tiles overlap
	float dirt = is_path < 0.5 && wpos.y > -0.02 ? 0.0 : 1.0;
	if (up > 0.5) {
		// Grass tiles get a ragged dirt fringe; path tiles keep a few grass tufts at their edges
		dirt = is_path > 0.5 ? smoothstep(0.5, 0.6, m) : smoothstep(0.5, 0.62, m);
	}
	vec3 col = mix(g, d, dirt);

	// Grid lines on the grass tops
	if (grid > 0.0) {
		vec2 e = min(fract(wpos.xz), 1.0 - fract(wpos.xz));
		float w = fwidth(wpos.x) + fwidth(wpos.z);
		float line = 1.0 - smoothstep(0.01, 0.01 + w, min(e.x, e.y));
		col *= 1.0 - grid * 0.35 * line * (1.0 - dirt) * step(0.5, up);
	}

	ALBEDO = col;
	ROUGHNESS = 0.92;
	if (use_normals) {
		NORMAL_MAP = mix(texture(grass_nrm, uv).rgb, texture(dirt_nrm, uv).rgb, dirt);
		NORMAL_MAP_DEPTH = 0.8;
	}
}
