// Ground: photo-scanned CC0 grass and path (Poly Haven, see assets/CREDITS.md) laid
// out by world position, so they run across the tiles without seams. The scans are
// graded to the game's colours: grass keeps the scan's light and dark with only a
// little of its own hue, the path keeps more of its stones and tufts. Their AO is
// baked into the colour maps. A tiny image with one pixel per cell marks the path,
// and its smooth filtering gives the soft, ragged path edge.
// Painted look on top: big warm and cool patches, a trampled band beside the path,
// a lighter worn middle on the path. The land around the board (outer = 1) turns to
// forest floor further out, with a sandy, rocky bank round the lake.
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bank_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bank_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D far_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_mask : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(24.0, 18.0);
uniform float tex_scale = 0.4;  // texture repeats per tile (0.4 = once every 2.5 tiles)
// No visible repeat: on the tops the textures are laid in soft-edged hexagons, each
// turned and shifted at random; the scans' own big light and dark patches (which made
// a square grid) are evened out, and come back as big, unrepeated patches (macro)
uniform float hex_size = 0.55;  // hexagon spacing, in texture repeats
uniform float hex_sharp = 6.0;  // higher = narrower blend between hexagons
uniform float flatten = 0.65;   // how much of the grass scan's big patches is evened out
uniform float dirt_flatten = 0.35;  // ...and the path's (its stains are part of its look)
uniform float macro = 0.8;      // the big, unrepeated patches on the grass
uniform float macro_scale = 0.14;
// The textures' average colors (linear, from build_ground_tex.py), for the grading
uniform vec3 grass_avg = vec3(0.1173, 0.0850, 0.0200);
uniform vec3 dirt_avg = vec3(0.2482, 0.2033, 0.1203);
uniform vec3 bank_avg = vec3(0.0690, 0.0566, 0.0279);
uniform vec3 far_avg = vec3(0.1379, 0.0986, 0.0584);
uniform vec3 grass_color : source_color = vec3(0.22, 0.38, 0.09);
uniform vec3 dirt_color : source_color = vec3(0.37, 0.27, 0.17);
uniform vec3 bank_color : source_color = vec3(0.26, 0.24, 0.16);
uniform vec3 far_color : source_color = vec3(0.16, 0.2, 0.08);
uniform float detail = 0.75;     // 0 = flat color, 1 = the scan's full contrast
uniform float grass_hue = 0.2;   // how much of the scan's own hue the grass keeps
uniform float dirt_hue = 0.35;
uniform float is_path = 0.0;
uniform float grid = 0.0;  // grid lines, faded in while placing a tower
uniform bool use_normals = false;  // Graphics High
// Painted look
uniform float paint = 0.8;
uniform vec3 warm : source_color = vec3(1.34, 1.11, 0.6);
uniform vec3 cool : source_color = vec3(0.6, 0.8, 0.98);
uniform float worn = 0.25;     // lighter middle of the path
uniform float trample = 0.2;   // darker grass beside the path
uniform float outer = 0.0;     // 1: the land around the board
uniform float outer_dark = 0.6;
uniform vec2 lake_center = vec2(-1000.0);
uniform vec2 lake_radius = vec2(1.0);

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

// The scan graded to a colour: its light and dark, and some of its own hue
vec3 grade(vec3 tex, vec3 avg, vec3 col, float hue) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Compatibility works with colors as stored (sRGB, not linear), so the average
	// has to be sRGB too, or the ground comes out 2-3x too bright. max(): no NaN.
	avg = pow(max(avg, vec3(0.0)), vec3(1.0 / 2.2));
#endif
	const vec3 W = vec3(0.2126, 0.7152, 0.0722);
	float l = dot(tex, W) / max(dot(avg, W), 1e-4);
	vec3 rel = mix(vec3(l), tex / max(avg, vec3(1e-4)), hue);
	return col * mix(vec3(1.0), rel, detail);
}

// The hexagon grid (Heitz and Neyret's triangle grid): the 3 hexagon centres around
// p and how much each one counts here
void hex_grid(vec2 p, out vec3 w, out vec2 v1, out vec2 v2, out vec2 v3) {
	vec2 sk = vec2(p.x - 0.57735 * p.y, 1.1547 * p.y) * 3.4641;
	vec2 base = floor(sk);
	vec3 t = vec3(fract(sk), 0.0);
	t.z = 1.0 - t.x - t.y;
	if (t.z > 0.0) {
		w = vec3(t.z, t.y, t.x);
		v1 = base;
		v2 = base + vec2(0.0, 1.0);
		v3 = base + vec2(1.0, 0.0);
	} else {
		w = vec3(-t.z, 1.0 - t.y, 1.0 - t.x);
		v1 = base + vec2(1.0);
		v2 = base + vec2(1.0, 0.0);
		v3 = base + vec2(0.0, 1.0);
	}
	w = pow(w, vec3(hex_sharp));
	w /= w.x + w.y + w.z;
}

// A hexagon's random turn
mat2 hex_turn(vec2 v) {
	float a = hash(v) * 6.2832;
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// One hexagon's look of a texture: turned, shifted, its big patches evened out
vec3 hex_color(sampler2D tex, vec2 uv, vec2 dx, vec2 dy, vec2 v, mat2 r, float even) {
	vec2 p = r * uv + vec2(hash(v + 17.3), hash(v + 41.7));
	vec3 c = textureGrad(tex, p, r * dx, r * dy).rgb;
	vec3 all_avg = textureLod(tex, p, 12.0).rgb;  // the whole texture's average (works in both renderers)
	vec3 low = textureLod(tex, p, 5.0).rgb;       // its big patches
	return c * all_avg / max(mix(all_avg, low, even), vec3(1e-4));
}

// One hexagon's normal, turned back to the world's X/Z (GL normal map: +Y is up the image)
vec2 hex_normal(sampler2D tex, vec2 uv, vec2 dx, vec2 dy, vec2 v, mat2 r) {
	vec2 p = r * uv + vec2(hash(v + 17.3), hash(v + 41.7));
	vec2 n = textureGrad(tex, p, r * dx, r * dy).rg * 2.0 - 1.0;
	return transpose(r) * vec2(n.x, -n.y);
}

void fragment() {
	// Tops use X/Z; the sides (path edges, board edge) use the height instead
	bool top = up > 0.5;
	vec2 uv = (top ? wpos.xz : vec2(wpos.x + wpos.z, wpos.y)) * tex_scale;

	// How much dirt: sides are soil; on top, the path mask with a little noise
	float raw = outer > 0.5 ? 0.0 : texture(path_mask, wpos.xz / map_size).r;
	float n = noise(wpos.xz * 3.0) * 0.65 + noise(wpos.xz * 9.0) * 0.35 - 0.5;
	float m = raw + n * 0.35;
	// The grass tiles' sides keep a thin grass rim at the top (the grass top is at height 0),
	// so no soil peeks out where neighbor tiles overlap
	float dirt = is_path < 0.5 && wpos.y > -0.02 ? 0.0 : 1.0;
	if (up > 0.5) {
		// A wide, soft edge: the path's tufts and stones fade into the grass
		dirt = is_path > 0.5 ? smoothstep(0.42, 0.66, m) : smoothstep(0.45, 0.7, m);
	}
	// The scans: on the tops through the hexagons (each texture only where it shows),
	// on the sides plain
	vec3 g = vec3(0.0);
	vec3 d = vec3(0.0);
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (top) {
		vec3 w;
		vec2 v1, v2, v3;
		hex_grid(uv / hex_size, w, v1, v2, v3);
		mat2 r1 = hex_turn(v1);
		mat2 r2 = hex_turn(v2);
		mat2 r3 = hex_turn(v3);
		vec2 dx = dFdx(uv);
		vec2 dy = dFdy(uv);
		vec2 pn = vec2(0.0);
		if (dirt < 0.999) {
			g = hex_color(grass_tex, uv, dx, dy, v1, r1, flatten) * w.x + hex_color(grass_tex, uv, dx, dy, v2, r2, flatten) * w.y + hex_color(grass_tex, uv, dx, dy, v3, r3, flatten) * w.z;
			// Big, unrepeated patches: the scan's own patches, much bigger and turned
			vec2 mp = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * macro_scale + 0.37;
			vec3 mc = textureLod(grass_tex, mp, 4.0).rgb / max(textureLod(grass_tex, mp, 12.0).rgb, vec3(1e-4));
			g *= mix(vec3(1.0), mc, macro);
			if (use_normals) {
				pn = (hex_normal(grass_nrm, uv, dx, dy, v1, r1) * w.x + hex_normal(grass_nrm, uv, dx, dy, v2, r2) * w.y + hex_normal(grass_nrm, uv, dx, dy, v3, r3) * w.z) * (1.0 - dirt);
			}
		}
		if (dirt > 0.001) {
			d = hex_color(dirt_tex, uv, dx, dy, v1, r1, dirt_flatten) * w.x + hex_color(dirt_tex, uv, dx, dy, v2, r2, dirt_flatten) * w.y + hex_color(dirt_tex, uv, dx, dy, v3, r3, dirt_flatten) * w.z;
			if (use_normals) {
				pn += (hex_normal(dirt_nrm, uv, dx, dy, v1, r1) * w.x + hex_normal(dirt_nrm, uv, dx, dy, v2, r2) * w.y + hex_normal(dirt_nrm, uv, dx, dy, v3, r3) * w.z) * dirt;
			}
		}
		// World X/Z -> the surface's own tangent frame
		vec3 tw = (INV_VIEW_MATRIX * vec4(TANGENT, 0.0)).xyz;
		vec3 bw = (INV_VIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz;
		nm = vec3(vec2(dot(pn, tw.xz), dot(pn, bw.xz)) * 0.5 + 0.5, 1.0);
	} else {
		g = texture(grass_tex, uv).rgb;
		d = texture(dirt_tex, uv).rgb;
		nm = mix(texture(grass_nrm, uv).rgb, texture(dirt_nrm, uv).rgb, dirt);
	}
	g = grade(g, grass_avg, grass_color, grass_hue);
	d = grade(d, dirt_avg, dirt_color, dirt_hue);
	// Big warm and cool patches
	float big = noise(wpos.xz * 0.16) * 0.6 + noise(wpos.xz * 0.4 + 7.0) * 0.4;
	g *= mix(vec3(1.0), mix(cool, warm, smoothstep(0.2, 0.8, big)), paint);

	// Path: a lighter, dusty middle and a darker rim where it meets the grass
	d *= mix(1.0 - 0.2 * paint, 1.0 + worn * paint, smoothstep(0.6, 0.95, raw + n * 0.2));
	// Grass beside the path: trampled, a bit darker and yellower
	float near = smoothstep(0.15, 0.5, m) * paint;
	g *= mix(vec3(1.0), vec3(0.95, 0.9, 0.7) * (1.0 - trample), near);
	vec3 col = mix(g, d, dirt);

	if (outer > 0.5) {
		// Forest floor further out, the lake's bank, and darker toward the edge
		vec2 out_d = max(max(-wpos.xz, wpos.xz - map_size), vec2(0.0));
		float far = smoothstep(2.0, 7.0, length(out_d));
		col = mix(col, grade(texture(far_tex, uv * 0.8).rgb, far_avg, far_color, 0.5), far);
		float r = length((wpos.xz - lake_center) / lake_radius);
		float bank = 1.0 - smoothstep(0.95, 1.45, r);
		col = mix(col, grade(texture(bank_tex, uv * 1.4).rgb, bank_avg, bank_color, 0.7), bank);
		nm = mix(nm, texture(bank_nrm, uv * 1.4).rgb, bank);
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
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	if (use_normals) {
		NORMAL_MAP = nm;
		NORMAL_MAP_DEPTH = 1.0;
	}
}
