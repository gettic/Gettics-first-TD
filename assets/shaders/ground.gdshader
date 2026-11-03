// Ground: grass and dirt textures laid out by world position, so they run across
// the tiles without seams. A tiny image with one pixel per cell marks the path,
// and its smooth filtering gives the ragged dirt edge next to the path.
// Painted look on top: big warm and cool color patches, soft brush strokes, a
// trampled darker band beside the path, a lighter worn middle on the path, and
// the land outside the board (outer = 1) fading darker.
shader_type spatial;
render_mode diffuse_lambert_wrap;

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
uniform vec3 grass_color : source_color = vec3(0.195, 0.34, 0.085);  // a little olive
uniform vec3 dirt_color : source_color = vec3(0.45, 0.29, 0.14);
uniform float detail = 0.6;  // 0 = flat color, 1 = the texture's full contrast
uniform float is_path = 0.0;
uniform float grid = 0.0;  // grid lines, faded in while placing a tower
uniform bool use_normals = false;  // Graphics High
// Painted look
uniform float paint = 1.0;
uniform vec3 warm : source_color = vec3(1.34, 1.11, 0.6);
uniform vec3 cool : source_color = vec3(0.6, 0.8, 0.98);
uniform float worn = 0.3;      // lighter middle of the path
uniform float trample = 0.25;  // darker grass beside the path
uniform float outer = 0.0;     // 1: the land around the board
uniform float outer_dark = 0.6;

varying vec3 wpos;
varying float up;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}

// A random number per grid corner. Not the usual fract(sin(...) * 43758): the GPU
// can round neighbouring cells' corners differently, and that big multiplier
// turned it into hard-edged blocks in the painted patches.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(mod(p, 512.0).xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
	// so the averages have to be in sRGB too, or the ground comes out 2-3x too bright.
	// max(): pow of a negative number is NaN (white specks)
	vec3 g_avg = pow(max(grass_avg, vec3(0.0)), vec3(1.0 / 2.2));
	vec3 d_avg = pow(max(dirt_avg, vec3(0.0)), vec3(1.0 / 2.2));
#else
	vec3 g_avg = grass_avg;
	vec3 d_avg = dirt_avg;
#endif
	vec3 g = grass_color * mix(vec3(1.0), texture(grass_tex, uv).rgb / g_avg, detail);
	vec3 d = dirt_color * mix(vec3(1.0), texture(dirt_tex, uv).rgb / d_avg, detail);

	// Big warm and cool patches, and soft brush strokes running one way
	float big = noise(wpos.xz * 0.16) * 0.6 + noise(wpos.xz * 0.4 + 7.0) * 0.4;
	g *= mix(vec3(1.0), mix(cool, warm, smoothstep(0.2, 0.8, big)), paint);
	float stroke = noise(vec2(wpos.x * 1.1 + wpos.z * 0.5, wpos.z * 4.5 - wpos.x * 0.8));
	g *= 1.0 + (stroke - 0.5) * 0.25 * paint;
	d *= 1.0 + (noise(wpos.xz * 2.3) - 0.5) * 0.2 * paint;

	// How much dirt: sides are soil; on top, the path mask with a little noise
	float raw = outer > 0.5 ? 0.0 : texture(path_mask, wpos.xz / map_size).r;
	float n = noise(wpos.xz * 3.0) * 0.65 + noise(wpos.xz * 9.0) * 0.35 - 0.5;
	float m = raw + n * 0.35;
	// The grass tiles' sides keep a thin grass rim at the top (the grass top is at height 0),
	// so no soil peeks out where neighbor tiles overlap
	float dirt = is_path < 0.5 && wpos.y > -0.02 ? 0.0 : 1.0;
	if (up > 0.5) {
		// Grass tiles get a ragged dirt fringe; path tiles keep a few grass tufts at their edges
		dirt = is_path > 0.5 ? smoothstep(0.5, 0.6, m) : smoothstep(0.5, 0.62, m);
	}
	// Path: a lighter, dusty middle and a darker rim where it meets the grass
	d *= mix(1.0 - 0.25 * paint, 1.0 + worn * paint, smoothstep(0.6, 0.95, raw + n * 0.2));
	// Grass beside the path: trampled, a bit darker and yellower
	float near = smoothstep(0.15, 0.5, m) * paint;
	g *= mix(vec3(1.0), vec3(0.95, 0.9, 0.7) * (1.0 - trample), near);
	vec3 col = mix(g, d, dirt);

	// The land around the board gets darker further out
	if (outer > 0.5) {
		vec2 out_d = max(max(-wpos.xz, wpos.xz - map_size), vec2(0.0));
		col *= mix(1.0, outer_dark, smoothstep(0.0, 7.0, length(out_d)));
	}

	// Grid lines on the grass tops
	if (grid > 0.0) {
		vec2 e = min(fract(wpos.xz), 1.0 - fract(wpos.xz));
		float w = fwidth(wpos.x) + fwidth(wpos.z);
		float line = 1.0 - smoothstep(0.01, 0.01 + w, min(e.x, e.y));
		col *= 1.0 - grid * 0.35 * line * (1.0 - dirt) * step(0.5, up);
	}

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	if (use_normals) {
		NORMAL_MAP = mix(texture(grass_nrm, uv).rgb, texture(dirt_nrm, uv).rgb, dirt);
		NORMAL_MAP_DEPTH = 0.6;
	}
}
