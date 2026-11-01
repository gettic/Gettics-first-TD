extends "res://game_updates.gd"
## The 3D world: map, gates, tower models, monsters, shots and effects.

# ---------------------------------------------------------------- 3D world

func mat(col: Color, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func add_mesh(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


const SETTINGS_FILE := "user://settings.cfg"  # this PC's settings, like Graphics Low/High
var graphics_high := true  # Low/High in the Settings box: only switches effects
var fullscreen := false  # borderless over the whole screen (F11, Alt+Enter)
var fullscreen_chosen := false  # saved, or picked this run
var render_scale := 1.0  # the 3D's resolution compared to the screen's
var aa_mode := "msaa2"  # anti-aliasing: one of AA_MODES
const RENDER_SCALES := [1.0, 0.85, 0.75, 0.5]
const AA_MODES := ["msaa2", "msaa4", "fxaa", "off"]
const AA_NAMES := ["MSAA 2x", "MSAA 4x", "FXAA", "Off"]
var compat := false  # running on the Compatibility renderer (older PCs), which needs darker light
var env: Environment
var sun: DirectionalLight3D
var ground_mats: Array[ShaderMaterial] = []  # grass and path
var grid_fade := 0.0  # grid lines on the grass, shown while placing a tower


func build_world() -> void:
	# Forward+ falls back to Compatibility by itself on PCs that can't run it
	compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	# The painted look: warm late-afternoon light, a soft haze far away, and colors
	# a little stronger. Compatibility renders brighter and more colorful, so it
	# gets its own, lower values.
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.6, 0.55)
	# A sky only for the ambient light and reflections: the camera never sees it
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.52, 0.8)
	sky_mat.sky_horizon_color = Color(0.85, 0.75, 0.6)
	sky_mat.ground_bottom_color = Color(0.12, 0.1, 0.08)
	sky_mat.ground_horizon_color = Color(0.85, 0.75, 0.6).darkened(0.3)
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.48 if compat else 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.72 if compat else 1.0
	env.glow_enabled = true
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.85
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.02 if compat else 1.2
	# Shadows a little cool, highlights a little warm
	env.adjustment_color_correction = split_tone(0.5)
	env.ssao_radius = 0.8
	env.ssao_intensity = 2.5
	env.ssao_power = 1.6
	env.ssao_light_affect = 0.2
	env.ssil_radius = 2.0
	env.ssil_intensity = 0.8
	# Haze over the land far around the board (see build_map() for its distance)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.75, 0.68, 0.55)
	env.fog_density = 1.0
	env.fog_depth_curve = 1.5
	env.fog_sky_affect = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Warm sun from the side for long soft shadows, and a cool fill light
	# from the other side so the shadow sides aren't flat
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -40, 0)
	sun.light_color = Color(1.0, 0.8, 0.58)
	sun.light_energy = 1.3 if compat else 1.75
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_color = Color(0.5, 0.62, 1.0)
	fill.light_energy = 0.4 if compat else 0.5
	add_child(fill)
	load_settings()
	make_effects()
	apply_graphics()

	camera = Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.h_offset = CAMERA_H_OFFSET
	camera.v_offset = CAMERA_V_OFFSET

	# Range circle and build preview
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 48
	range_disc = add_mesh(self, disc, mat(Color.WHITE, 0.0, 0.07))
	range_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	build_markers_and_hud()
	build_map()
	build_monsters()  # at the start, so the first wave doesn't stutter
	load_arrow_models()  # and upgrades don't either
	load_cannon_models()


# A 3D color table for env.adjustment_color_correction: shadows a little cool,
# highlights a little warm (amount 0 = no change)
func split_tone(amount: float) -> ImageTexture3D:
	var n := 17
	var imgs: Array[Image] = []
	var shadow := Color(0.94, 0.98, 1.08).lerp(Color.WHITE, 1.0 - amount)
	var light := Color(1.06, 1.01, 0.9).lerp(Color.WHITE, 1.0 - amount)
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				var c := Color(r / (n - 1.0), g / (n - 1.0), b / (n - 1.0))
				var lum := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
				var k := Color.WHITE.lerp(shadow, clampf(1.0 - lum * 2.0, 0.0, 1.0)).lerp(light, clampf(lum * 2.0 - 1.0, 0.0, 1.0))
				img.set_pixel(r, g, Color(clampf(c.r * k.r, 0, 1), clampf(c.g * k.g, 0, 1), clampf(c.b * k.b, 0, 1)))
		imgs.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, imgs)
	return tex


# ---------------------------------------------------------------- painted look

# Model materials get the painted shader (see assets/shaders/painted.gdshader):
# one copy per material, shared by everything that uses it.
var painted_shader: Shader
var painted_shader_2s: Shader  # the same, drawn from both sides (banners, flags)
var painted_cache := {}


func painted(m: Material) -> Material:
	if not (m is StandardMaterial3D):
		return m
	var s := m as StandardMaterial3D
	# See-through, unshaded and glowing-texture materials keep their own look
	if s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or s.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return m
	if s.emission_enabled and s.emission_texture != null:
		return m
	if painted_cache.has(s):
		return painted_cache[s]
	load_painted()
	var p := ShaderMaterial.new()
	p.shader = painted_shader_2s if s.cull_mode == BaseMaterial3D.CULL_DISABLED else painted_shader
	p.set_shader_parameter("albedo", s.albedo_color)
	if s.albedo_texture != null:
		p.set_shader_parameter("albedo_tex", s.albedo_texture)
	p.set_shader_parameter("use_vcol", s.vertex_color_use_as_albedo)
	if s.normal_enabled and s.normal_texture != null:
		p.set_shader_parameter("normal_tex", s.normal_texture)
		p.set_shader_parameter("use_normal", true)
		p.set_shader_parameter("normal_depth", s.normal_scale)
	if s.emission_enabled:
		p.set_shader_parameter("emission", s.emission)
		p.set_shader_parameter("emission_energy", s.emission_energy_multiplier)
	p.set_shader_parameter("saturation", 1.15)
	p.set_shader_parameter("rim_strength", 0.35)
	p.set_shader_parameter("rim_color", Color(1.0, 0.85, 0.6))
	p.set_shader_parameter("grad_low", 0.62)
	p.set_shader_parameter("grad_high", 1.15)
	p.set_shader_parameter("top_light", 0.2)
	painted_cache[s] = p
	return p


func load_painted() -> void:
	if painted_shader == null:
		painted_shader = load("res://assets/shaders/painted.gdshader")
		painted_shader_2s = Shader.new()
		painted_shader_2s.code = painted_shader.code.replace("render_mode ", "render_mode cull_disabled, ")


# Gives every model under n the painted look (see painted())
func paint_tree(n: Node) -> void:
	if n is MeshInstance3D and n != ghost and n != range_disc:
		var mi := n as MeshInstance3D
		if mi.material_override != null:
			mi.material_override = painted(mi.material_override)
		elif mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i)
				if m == null:
					m = mi.mesh.surface_get_material(i)
				if m != null:
					mi.set_surface_override_material(i, painted(m))
	for c in n.get_children():
		paint_tree(c)


const VIEW_TILES := Vector2(24, 18)  # the map size the camera's normal distance is made for
var view_scale := 1.0  # the camera's distance compared to the Default map's (see build_map())
var map_root: Node3D  # the map's ground, base, gates and areas (see build_map())
var area_centers: Array = []  # per player slot: the middle of that player's area (null: no tiles)


# Removes everything build_map() made, so the map can change.
func clear_map() -> void:
	if map_root != null:
		map_root.free()
		map_root = null
	gate_parts = []
	area_planes = []
	area_centers = []
	ground_mats = []
	pollen = null


# Builds the map being played (see use_map()): ground, path, base, gates and areas.
# Can be called again after the map changes.
func build_map() -> void:
	clear_map()
	map_root = Node3D.new()
	add_child(map_root)
	# The camera looks at the map's middle, from further away on bigger maps
	var s := maxf(maxf(map_cols / VIEW_TILES.x, map_rows / VIEW_TILES.y), 0.75)
	view_scale = s
	camera_focus = Vector3(map_cols / 2.0, 0.0, map_rows / 2.0 + 0.3)
	camera_home = camera_focus + Vector3(0, 26.5, 19.1) * s
	camera_pan = Vector2.ZERO
	camera.position = camera_home
	camera.look_at(camera_focus)
	sun.directional_shadow_max_distance = 60.0 * maxf(s, 1.0)
	# The haze starts beyond the board, also on big maps
	env.fog_depth_begin = 30.0 * s
	env.fog_depth_end = 80.0 * s

	# Ground: grass tiles, with the path sunk a little lower.
	# Tiles are slightly bigger than one unit so they overlap and no gaps show between them.
	# All grass tiles share one height: the textures follow the world position,
	# so where tiles overlap they draw the same pixels and nothing flickers.
	var tile := BoxMesh.new()
	tile.size = Vector3(1.01, 0.5, 1.01)
	# Painted grass and dirt textures (see assets/shaders/ground.gdshader). A small
	# image with one white pixel per path cell lets the shader blend the path's edge.
	# Water tiles count as path here: sunk lower, with a muddy bank around the water.
	var mask := Image.create(map_cols, map_rows, false, Image.FORMAT_L8)
	for c: Vector2i in path_cells:
		if in_map(c):
			mask.set_pixel(c.x, c.y, Color.WHITE)
	for c: Vector2i in blocked:
		if blocked[c] == "w" and in_map(c):
			mask.set_pixel(c.x, c.y, Color.WHITE)
	var grass := ShaderMaterial.new()
	grass.shader = load("res://assets/shaders/ground.gdshader")
	grass.set_shader_parameter("grass_tex", load("res://assets/terrain/grass.png"))
	grass.set_shader_parameter("dirt_tex", load("res://assets/terrain/dirt.png"))
	grass.set_shader_parameter("grass_nrm", load("res://assets/terrain/grass_normal.png"))
	grass.set_shader_parameter("dirt_nrm", load("res://assets/terrain/dirt_normal.png"))
	grass.set_shader_parameter("path_mask", ImageTexture.create_from_image(mask))
	grass.set_shader_parameter("map_size", Vector2(map_cols, map_rows))
	var dirt: ShaderMaterial = grass.duplicate()
	dirt.set_shader_parameter("is_path", 1.0)
	grass.set_shader_parameter("grid", grid_fade)
	ground_mats = [grass, dirt]
	apply_graphics()
	# One MultiMesh for the grass and one for the path, so the whole ground is 2 draw calls instead of 432
	var spots := {-0.33: [], -0.25: []}
	for x in map_cols:
		for y in map_rows:
			var c := Vector2i(x, y)
			var h := -0.33 if path_cells.has(c) or blocked.get(c, "") == "w" else -0.25
			spots[h].append(Vector3(x + 0.5, h, y + 0.5))
	for h: float in spots:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tile
		mm.instance_count = spots[h].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[h][i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = dirt if h == -0.33 else grass
		map_root.add_child(mmi)
	var base := BoxMesh.new()
	base.size = Vector3(map_cols + 0.6, 1.0, map_rows + 0.6)
	add_mesh(map_root, base, mat(Color(0.16, 0.12, 0.09)), Vector3(map_cols / 2.0, -0.85, map_rows / 2.0))
	build_decor()
	build_border()

	# A gate only where the map has one; gate_parts stays one entry per player slot
	for g in gate_cells.size():
		if gate_cells[g] == null:
			gate_parts.append(null)
		else:
			build_gate(g)
	paint_tree(map_root)
	build_outer()
	build_areas()
	add_pollen()


# Graphics High: ambient occlusion (dark contact shadows), bounced light, soft
# wide shadows and more glow. Low: plain shadows and less glow, for slower PCs.
# The Compatibility renderer has no ambient occlusion or bounced light anyway.
func apply_graphics() -> void:
	var high := graphics_high
	env.ssao_enabled = high and not compat
	env.ssil_enabled = high and not compat
	env.glow_intensity = 0.75 if high else 0.45
	# Half the floating pollen on Low
	if pollen != null:
		pollen.amount = POLLEN if high else POLLEN / 2
	sun.shadow_blur = 1.5 if high else 1.0
	sun.light_angular_distance = 1.5 if high else 0.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if high else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	# The ground's normal maps (light catching the painted bumps) only on High
	for m in ground_mats:
		m.set_shader_parameter("use_normals", high and not compat)
	# Monsters cast shadows only on High (hundreds of them can be walking)
	for e in enemies:
		e.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if high else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var found := cfg.load(SETTINGS_FILE) == OK
	if found and cfg.has_section_key("graphics", "high"):
		graphics_high = cfg.get_value("graphics", "high", true)
	else:
		# First run: Low on weaker PCs (built-in graphics, or the Compatibility
		# fallback), High otherwise. Saved, so the player's choice always wins after this.
		graphics_high = not (compat or weak_gpu())
	# Display: files from before 1.28 don't have these, so they get the first-run choices
	var big_screen := DisplayServer.screen_get_size().y > 1080
	fullscreen_chosen = cfg.has_section_key("display", "fullscreen")
	fullscreen = bool(cfg.get_value("display", "fullscreen", release_build()))
	render_scale = float(cfg.get_value("display", "render_scale", 0.75 if weak_gpu() and big_screen else 1.0))
	if not render_scale in render_scales():
		render_scale = 1.0
	aa_mode = str(cfg.get_value("display", "aa", "msaa2"))
	if not aa_mode in AA_MODES:
		aa_mode = "msaa2"
	if not found or not cfg.has_section_key("graphics", "high") or not cfg.has_section_key("display", "aa"):
		save_settings()
	apply_display()
	# The debug build and test runs stay in a normal window (the debug log sits next to it)
	if release_build():
		set_fullscreen(fullscreen)


# The exported game the players get (not the debug build, the editor or tests).
func release_build() -> bool:
	return OS.has_feature("template") and not is_debug_game() and DisplayServer.get_name() != "headless"


# Fullscreen: a borderless window over the whole screen. Windowed: maximized.
func set_fullscreen(on: bool) -> void:
	fullscreen = on
	fullscreen_chosen = true
	if DisplayServer.get_name() == "headless":
		return
	var w := get_window()
	if on:
		w.mode = Window.MODE_FULLSCREEN
	elif w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN or release_build():
		w.mode = Window.MODE_MAXIMIZED


# F11 and Alt+Enter.
func toggle_fullscreen() -> void:
	set_fullscreen(get_window().mode != Window.MODE_FULLSCREEN)
	save_settings()


# 3D resolution (FSR 1 upscales it; Compatibility can only stretch it) and anti-aliasing.
# The 2D overlay always uses the screen's full resolution.
func apply_display() -> void:
	var vp := get_viewport()
	vp.scaling_3d_scale = render_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 1.0 and not compat else Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_4X if aa_mode == "msaa4" else (Viewport.MSAA_2X if aa_mode == "msaa2" else Viewport.MSAA_DISABLED)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa_mode == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED


func render_scales() -> Array:
	return [1.0, 0.75] if compat else RENDER_SCALES


# True for graphics built into the processor, like most laptops have.
func weak_gpu() -> bool:
	return RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU


func save_settings() -> void:
	# Headless runs (error checks, tests) never write the player's settings
	if DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)  # keeps any other settings in it
	cfg.set_value("graphics", "high", graphics_high)
	# Fullscreen only once it's chosen or on the release build, so a test or debug
	# run doesn't decide how the real game starts
	if fullscreen_chosen or release_build():
		cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "render_scale", render_scale)
	cfg.set_value("display", "aa", aa_mode)
	cfg.save(SETTINGS_FILE)


# Stone gate with a green portal where one player's monsters come out. It faces
# along its stretch of path, so monsters walk straight out of it. A gem on top
# shows the player's color; the portal only shows while a player uses the gate.
func build_gate(g: int) -> void:
	var gate := Node3D.new()
	gate.position = to3d(routes[g][0])
	var out_dir: Vector2 = routes[g][1] - routes[g][0]
	gate.rotation.y = atan2(out_dir.x, out_dir.y)
	map_root.add_child(gate)
	var stone := mat(Color(0.42, 0.42, 0.46))
	var pillar := BoxMesh.new()
	pillar.size = Vector3(0.22, 1.3, 0.3)
	add_mesh(gate, pillar, stone, Vector3(-0.5, 0.57, 0))
	add_mesh(gate, pillar, stone, Vector3(0.5, 0.57, 0))
	var lintel := BoxMesh.new()
	lintel.size = Vector3(1.34, 0.26, 0.38)
	add_mesh(gate, lintel, stone, Vector3(0, 1.3, 0))
	var cap := BoxMesh.new()
	cap.size = Vector3(0.3, 0.1, 0.4)
	add_mesh(gate, cap, stone, Vector3(-0.5, -0.03, 0))
	add_mesh(gate, cap, stone, Vector3(0.5, -0.03, 0))
	var gem := add_mesh(gate, box(0.2, 0.2, 0.2), mat(PLAYER_COLORS[g], 1.2), Vector3(0, 1.55, 0))
	gem.rotation_degrees = Vector3(45, 0, 45)

	# The portal surface filling the arch, visible from both sides
	var green := Color(0.25, 1.0, 0.4)
	var surface := QuadMesh.new()
	surface.size = Vector2(0.78, 1.12)
	var surface_mat := mat(green, 1.6, 0.7)
	surface_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var surface_node := add_mesh(gate, surface, surface_mat, Vector3(0, 0.6, 0))
	surface_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Glowing sparks that swirl inside the portal
	var portal := Node3D.new()
	portal.position = Vector3(0, 0.6, 0.02)
	gate.add_child(portal)
	var spark := SphereMesh.new()
	spark.radius = 0.05
	spark.height = 0.1
	var spark_mat := mat(Color(0.75, 1.0, 0.8), 3.0)
	for i in 6:
		var a := TAU * i / 6.0
		add_mesh(portal, spark, spark_mat, Vector3(cos(a), sin(a), 0) * 0.28)

	var portal_light := OmniLight3D.new()
	portal_light.light_color = green
	portal_light.omni_range = 3.0
	portal_light.light_energy = 1.8
	portal_light.position = Vector3(0, 0.7, 0.4)
	gate.add_child(portal_light)
	gate_parts.append({"surface": surface_node, "sparks": portal, "light": portal_light, "motes": add_motes(gate)})


func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


# Each player's area, shown while placing a tower in multiplayer: one MultiMesh
# of tile squares per player (see area_of), so any shape costs one draw call.
func build_areas() -> void:
	var square := PlaneMesh.new()
	square.size = Vector2(1, 1)
	var cells: Array = [[], [], [], []]
	for c: Vector2i in area_of:
		var slot: int = area_of[c]
		if slot >= 0 and slot < MAX_PLAYERS:
			cells[slot].append(c)
	for slot in MAX_PLAYERS:
		# Water isn't covered: it can't be built on, and the tint would change its color
		var spots: Array[Vector3] = []
		var sum := Vector2.ZERO
		for c: Vector2i in cells[slot]:
			if blocked.get(c, "") != "w":
				spots.append(Vector3(c.x + 0.5, 0.04, c.y + 0.5))
			sum += Vector2(c) + Vector2(0.5, 0.5)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = square
		mm.instance_count = spots.size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		map_root.add_child(mmi)
		area_planes.append(mmi)
		# Its label goes in the middle of its tiles
		var n: int = cells[slot].size()
		if n > 0:
			area_centers.append(Vector3(sum.x / n, 0.04, sum.y / n))
		else:
			area_centers.append(null)


# Rocks and trees (KayKit Forest Nature Pack, scaled to fit one tile) and water.
const ROCK_MODELS := [["Rock_1_E", 0.55], ["Rock_3_F", 0.6], ["Rock_3_C", 0.8], ["Rock_2_C", 0.45]]
const TREE_MODELS := [["Tree_1_A", 0.3], ["Tree_2_A", 0.33], ["Tree_3_A", 0.3], ["Tree_4_A", 0.36]]
var nature_mats := {}  # "r" or "t" -> the rocks' or trees' material


# The pack material for rocks and trees, with less color and darker so they sit
# with the painted grass (rocks a bit darker still). Shared by all of a kind.
func nature_mat(mesh: Mesh, kind: String) -> ShaderMaterial:
	if not nature_mats.has(kind):
		var m: ShaderMaterial = pack_mat(mesh, 0).duplicate()
		m.set_shader_parameter("saturation", 0.8)
		m.set_shader_parameter("tint", Color(0.62, 0.63, 0.6) if kind == "r" else Color(0.7, 0.74, 0.66))
		m.set_shader_parameter("rim_strength", 0.15)
		nature_mats[kind] = m
	return nature_mats[kind]


# A number made from a tile's position: the same on every computer, so a map's
# rocks and trees always look the same, for every player.
func tile_hash(c: Vector2i) -> int:
	var h := (c.x * 73856093) ^ (c.y * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


# The map's rocks, trees and water (see blocked). Each tile gets a model, a turn and
# a size from tile_hash(); one MultiMesh per model, so they cost a few draw calls
# however many there are.
func build_decor() -> void:
	var by_model := {}  # model file -> [Transform3D, ...]
	var water: Array[Vector2i] = []
	for c: Vector2i in blocked:
		var kind: String = blocked[c]
		if kind == "w":
			water.append(c)
			continue
		var models: Array = ROCK_MODELS if kind == "r" else TREE_MODELS
		var h := tile_hash(c)
		var pick: Array = models[h % models.size()]
		var s: float = pick[1] * (0.9 + (h >> 4) % 21 / 100.0)
		var turn := deg_to_rad((h >> 9) % 360)
		var nudge := Vector3(((h >> 18) % 11 - 5) * 0.015, 0.0, ((h >> 22) % 11 - 5) * 0.015)
		var tr := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * s), Vector3(c.x + 0.5, 0.0, c.y + 0.5) + nudge)
		var file := "nature/%s_Color1" % pick[0]
		if not by_model.has(file):
			by_model[file] = []
		by_model[file].append(tr)
	for file: String in by_model:
		for part: Array in pack_parts(file):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = by_model[file].size()
			for i in mm.instance_count:
				mm.set_instance_transform(i, by_model[file][i] * part[1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = nature_mat(part[0], "r" if file.contains("Rock") else "t")
			map_root.add_child(mmi)
	if water.is_empty():
		return
	# Water: one square per tile just under the grass, drawn by water.gdshader.
	# Its own small mask (one pixel per water cell) gives the soft edge.
	var mask := Image.create(map_cols, map_rows, false, Image.FORMAT_L8)
	for c in water:
		if in_map(c):
			mask.set_pixel(c.x, c.y, Color.WHITE)
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/water.gdshader")
	m.set_shader_parameter("water_mask", ImageTexture.create_from_image(mask))
	m.set_shader_parameter("map_size", Vector2(map_cols, map_rows))
	var square := PlaneMesh.new()
	square.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = square
	mm.instance_count = water.size()
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(water[i].x + 0.5, -0.03, water[i].y + 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_root.add_child(mmi)


# A low curb of chunky stones along the board's edge, so the buildable area is clear.
# One MultiMesh; each stone's tilt and height come from tile_hash().
func build_border() -> void:
	var stone := BoxMesh.new()
	stone.size = Vector3(0.42, 0.2, 0.16)
	var xf: Array[Transform3D] = []
	var k := 0
	for side in 4:
		var along_x := side < 2
		var length := map_cols if along_x else map_rows
		var count := int(ceil(length / 0.45))
		for i in count:
			var t := (i + 0.5) * length / count
			var h := tile_hash(Vector2i(k, side * 1000))
			k += 1
			var pos: Vector3
			if along_x:
				pos = Vector3(t, -0.04, -0.08 if side == 0 else map_rows + 0.08)
			else:
				pos = Vector3(-0.08 if side == 2 else map_cols + 0.08, -0.04, t)
			pos.y += (h % 7) * 0.006
			var turn := (0.0 if along_x else PI / 2) + ((h >> 3) % 9 - 4) * 0.03
			xf.append(Transform3D(Basis(Vector3.UP, turn), pos))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stone
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = painted(mat(Color(0.62, 0.56, 0.48)))
	map_root.add_child(mmi)


# The land around the board: painted grass fading darker further out, a lake
# beside the board, and forest, bushes, rocks and grass tufts, denser further
# out. All from the map's size, gates and tile_hash(), so every player sees the
# same, on every map size.
const OUTER_TREES := ["Tree_1_A", "Tree_2_A", "Tree_4_A", "Tree_3_A"]
const OUTER_BUSHES := ["Bush_1_B", "Bush_2_C", "Bush_3_A"]
const OUTER_ROCKS := ["Rock_1_E", "Rock_3_C", "Rock_2_C"]
const OUTER_TUFTS := ["Grass_1_B", "Grass_2_B"]


func build_outer() -> void:
	var s := view_scale
	var ground: ShaderMaterial = ground_mats[0].duplicate()
	ground.set_shader_parameter("outer", 1.0)
	ground.set_shader_parameter("grid", 0.0)
	ground_mats.append(ground)
	var plane := PlaneMesh.new()
	plane.size = Vector2(map_cols, map_rows) + Vector2(60, 50) * s
	add_mesh(map_root, plane, ground, Vector3(map_cols / 2.0, -0.12, map_rows / 2.0))

	# The lake: beside the board's left or right edge (the one with fewer gates),
	# sized by the map. Its square is big enough that the shore is never cut.
	var k := clampf(map_rows / VIEW_TILES.y, 0.75, 2.0)
	var radius := Vector2(2.4, 4.2) * k
	var left := 0
	var right := 0
	for g in gate_cells:
		if g != null:
			if g.x <= 1:
				left += 1
			elif g.x >= map_cols - 2:
				right += 1
	var lake_x := -(radius.x + 1.6 * k) if left <= right else map_cols + radius.x + 1.6 * k
	var lake_c := Vector2(lake_x, map_rows * 0.53)
	var lake := ShaderMaterial.new()
	lake.shader = load("res://assets/shaders/lake.gdshader")
	lake.set_shader_parameter("center", lake_c)
	lake.set_shader_parameter("radius", radius)
	var lp := PlaneMesh.new()
	lp.size = radius * 2.6
	var lmi := add_mesh(map_root, lp, lake, Vector3(lake_c.x, -0.1, lake_c.y))
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Trees, bushes, rocks and grass tufts; none in the lake or in front of a gate
	var gates: Array[Vector2] = []
	for g in gate_cells:
		if g != null:
			gates.append(Vector2(g) + Vector2(0.5, 0.5))
	var by_model := {}
	var mx := int(ceil(10 * s))
	for x in range(-mx, map_cols + mx):
		for y in range(-int(ceil(11 * s)), map_rows + int(ceil(4 * s))):
			var c := Vector2i(x, y)
			var h := tile_hash(c + Vector2i(500, 500))
			var r := (h % 1000) / 1000.0
			var pos := Vector3(x + 0.5 + ((h >> 10) % 7 - 3) * 0.08, 0.0, y + 0.5 + ((h >> 14) % 7 - 3) * 0.08)
			var turn := deg_to_rad((h >> 4) % 360)
			if in_map(c):
				# Grass tufts on the board's grass (not on the path, water, rocks or trees)
				if r < 0.3 and not path_cells.has(c) and not blocked.has(c):
					put_model(by_model, OUTER_TUFTS[h % 2], pos, turn, 0.18 + (h >> 8) % 10 * 0.01)
				continue
			# Round the lake, with a little room for its shore
			if ((Vector2(x + 0.5, y + 0.5) - lake_c) / (radius + Vector2(0.9, 0.9))).length() < 1.0:
				continue
			var near_gate := false
			for g in gates:
				if g.distance_to(Vector2(x + 0.5, y + 0.5)) < 2.2:
					near_gate = true
			var dist := maxf(maxf(maxf(-x, x - map_cols + 1), maxf(-y, y - map_rows + 1)), 0)
			var tree_chance := 0.0 if near_gate else clampf((dist - 1.5) / 3.0, 0.0, 0.7)
			pos.y = -0.12
			if r < tree_chance:
				put_model(by_model, OUTER_TREES[h % OUTER_TREES.size()], pos, turn, 0.27 + (h >> 7) % 10 * 0.017)
			elif r < tree_chance + 0.12:
				put_model(by_model, OUTER_BUSHES[h % OUTER_BUSHES.size()], pos, turn, 0.35 + (h >> 7) % 10 * 0.02)
			elif r < tree_chance + 0.17:
				put_model(by_model, OUTER_ROCKS[h % OUTER_ROCKS.size()], pos, turn, 0.35 + (h >> 7) % 10 * 0.02)
			elif r < tree_chance + 0.5:
				put_model(by_model, OUTER_TUFTS[h % 2], pos, turn, 0.45)
	for file: String in by_model:
		for part: Array in pack_parts("nature/%s_Color1" % file):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = by_model[file].size()
			for i in mm.instance_count:
				mm.set_instance_transform(i, by_model[file][i] * part[1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			var kind := "t" if file.begins_with("Tree") else ("g" if file.begins_with("Grass") else "r")
			mmi.material_override = outer_mat(part[0], kind)
			if kind == "g":
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			map_root.add_child(mmi)


func put_model(by_model: Dictionary, file: String, pos: Vector3, turn: float, size: float) -> void:
	if not by_model.has(file):
		by_model[file] = []
	by_model[file].append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), pos))


# The painted material of the land's trees ("t"), rocks ("r") and grass tufts ("g"), made once
var outer_mats := {}


func outer_mat(mesh: Mesh, kind: String) -> ShaderMaterial:
	if not outer_mats.has(kind):
		load_painted()
		var p := ShaderMaterial.new()
		p.shader = painted_shader
		p.set_shader_parameter("albedo_tex", (mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture)
		p.set_shader_parameter("rim_strength", 0.35)
		p.set_shader_parameter("rim_color", Color(1.0, 0.85, 0.6))
		p.set_shader_parameter("grad_low", 0.62)
		p.set_shader_parameter("grad_high", 1.15)
		p.set_shader_parameter("top_light", 0.2)
		p.set_shader_parameter("grad_top", 1.0 if kind == "t" else 0.3)
		p.set_shader_parameter("saturation", 0.92)
		p.set_shader_parameter("tint", Color(0.66, 0.66, 0.64) if kind == "r" else Color(0.6, 0.66, 0.48))
		outer_mats[kind] = p
	return outer_mats[kind]


# ---------------------------------------------------------------- particles and effects

const POLLEN := 260  # floating pollen over the board on High (half on Low)
var pollen: GPUParticles3D
var dot_mat: StandardMaterial3D  # a soft glowing dot, shared by all particles
var hit_pool: Array[GPUParticles3D] = []  # sparks where arrows, frost and spark shots hit
var hit_next := 0
var boom_pool: Array[GPUParticles3D] = []  # fire bursts of the cannon's blasts
var boom_next := 0
var arrow_mesh: Mesh  # a glowing arrow streak


# A soft round dot (white in the middle, see-through at the edge)
func soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	return tex


# Particles fading in and out over their life
func fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 1))
	g.add_point(0.75, Color(1, 1, 1, 1))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


func particles(parent: Node3D, amount: int, life: float, size: float, pm: ParticleProcessMaterial) -> GPUParticles3D:
	if dot_mat == null:
		dot_mat = StandardMaterial3D.new()
		dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dot_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		dot_mat.vertex_color_use_as_albedo = true
		dot_mat.albedo_texture = soft_dot()
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = dot_mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


# Warm pollen drifting over the board
func add_pollen() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(map_cols / 2.0 + 4, 0.6, map_rows / 2.0 + 4)
	pm.color_ramp = fade_ramp()
	pm.turbulence_enabled = true
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.direction = Vector3(0.3, 1, 0.1)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.1
	pm.gravity = Vector3(0.05, 0.02, 0)
	pm.color = Color(1.4, 1.25, 0.9, 0.8)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pollen = particles(map_root, POLLEN if graphics_high else POLLEN / 2, 9.0, 0.045, pm)
	pollen.position = Vector3(map_cols / 2.0, 0.9, map_rows / 2.0)
	pollen.visibility_aabb = AABB(-pm.emission_box_extents - Vector3(2, 2, 2), pm.emission_box_extents * 2 + Vector3(4, 6, 4))
	pollen.preprocess = 10.0


# Green motes rising out of a gate's portal
func add_motes(gate: Node3D) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.35, 0.5, 0.1)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3.ZERO
	pm.color = Color(0.8, 2.5, 1.0)
	pm.color_ramp = fade_ramp()
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var p := particles(gate, 40, 1.6, 0.08, pm)
	p.position = Vector3(0, 0.6, 0)
	return p


# The shared effects, made once: the glowing arrow and pools of spark and fire
# bursts that are reused round-robin (no new nodes while playing)
func make_effects() -> void:
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.03
	tip.height = 0.38
	tip.radial_segments = 6
	tip.rings = 1
	var parts := Node3D.new()
	add_mesh(parts, tip, mat(Color(1.0, 0.85, 0.5), 4.0)).rotation_degrees = Vector3(-90, 0, 0)  # points at -Z
	arrow_mesh = merge_parts(parts)
	for i in 24:
		hit_pool.append(burst(10, 0.35, 0.05, 2.5))
	for i in 8:
		boom_pool.append(burst(36, 0.7, 0.12, 4.0))


func burst(amount: int, life: float, size: float, speed: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -6, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.color_ramp = fade_ramp()
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var p := particles(self, amount, life, size, pm)
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	return p


func fire_burst(p: GPUParticles3D, pos: Vector3, col: Color) -> void:
	p.position = pos
	(p.process_material as ParticleProcessMaterial).color = col
	p.restart()


# Sparks where a shot hits (cannon shots burst in add_boom() instead)
func shot_spark(s: Shot) -> void:
	if s.type == "cannon":
		return
	var col := Color(0.8, 1.6, 2.4) if s.type == "frost" else Color(1.6, 1.3, 0.7)
	fire_burst(hit_pool[hit_next % hit_pool.size()], to3d(s.target_pos, 0.35), col)
	hit_next += 1


func build_markers_and_hud() -> void:
	range_disc.visible = false
	var ghost_mesh := BoxMesh.new()
	ghost_mesh.size = Vector3(0.95, 0.1, 0.95)
	ghost_mat = mat(Color.GREEN, 0.0, 0.4)
	ghost = add_mesh(self, ghost_mesh, ghost_mat)
	ghost.visible = false

	# Shared materials and meshes
	stone_mat = mat(Color(0.35, 0.35, 0.4))
	dark_mat = mat(Color(0.15, 0.15, 0.18))
	gold_mat = mat(Color(1.0, 0.85, 0.3), 1.0)
	pip_mesh = SphereMesh.new()
	pip_mesh.radius = 0.05
	pip_mesh.height = 0.1
	pip_mesh.radial_segments = 12  # tiny, so few triangles are enough
	pip_mesh.rings = 6
	boom_mesh = SphereMesh.new()
	boom_mesh.radius = 1.0
	boom_mesh.height = 2.0


func build_tower_node(t: Tower) -> void:
	if t.node != null:
		t.node.queue_free()
	var col: Color = TOWERS[t.type]["color"]
	var root := Node3D.new()
	root.position = to3d(t.pos)
	add_child(root)
	# Levels after 4 keep the level 4 look (the level shows on a badge, see draw_level_badges())
	var look := mini(t.level, 3)
	if t.type == "arrow" or t.type == "cannon":
		var model_head: Node3D
		if t.type == "arrow":
			model_head = build_arrow_tower(root, t.level, t.path, t.owner)
		else:
			model_head = build_cannon_tower(root, t.level, t.path, t.owner)
		add_pips(root, look, Vector3(0, 0.06, 0.44))
		paint_tree(root)
		t.node = root
		t.head = model_head
		return
	# The base is tinted with the owner's color
	var base := BoxMesh.new()
	base.size = Vector3(0.8, 0.3, 0.8)
	add_mesh(root, base, model_mat(stone_mat.albedo_color.lerp(PLAYER_COLORS[t.owner], 0.45)), Vector3(0, 0.15, 0))
	# The tower gets taller with each level
	var h := 0.35 + look * 0.2
	var body := CylinderMesh.new()
	body.top_radius = 0.2
	body.bottom_radius = 0.28
	body.height = h
	add_mesh(root, body, model_mat(col.darkened(0.3)), Vector3(0, 0.3 + h / 2.0, 0))
	var head := Node3D.new()
	head.position = Vector3(0, 0.3 + h + 0.15, 0)
	root.add_child(head)
	match t.type:
		"frost":
			# Two four-sided cones make a crystal
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.18
			cone.height = 0.35
			cone.radial_segments = 4
			cone.rings = 1
			var crystal := model_mat(col, 1.2)
			add_mesh(head, cone, crystal, Vector3(0, 0.17, 0))
			add_mesh(head, cone, crystal, Vector3(0, -0.17, 0)).rotation_degrees.x = 180
		"spark":
			var orb := SphereMesh.new()
			orb.radius = 0.2
			orb.height = 0.4
			add_mesh(head, orb, model_mat(col, 2.0), Vector3(0, 0.1, 0))
			var ring := TorusMesh.new()
			ring.inner_radius = 0.26
			ring.outer_radius = 0.31
			add_mesh(head, ring, dark_mat, Vector3(0, 0.1, 0)).rotation_degrees.x = 60
	add_pips(root, look, Vector3(0, 0.32, 0.36))
	paint_tree(root)
	t.node = root
	t.head = head


# A gold pip per level, merged into one mesh per level and shared by every tower
func add_pips(root: Node3D, level: int, pos: Vector3) -> void:
	var key := "pips %d" % level
	if not model_meshes.has(key):
		var parts := Node3D.new()
		for i in level + 1:
			add_mesh(parts, pip_mesh, gold_mat, Vector3(-0.3 + i * 0.2, 0, 0))
		model_meshes[key] = merge_parts(parts)
	add_mesh(root, model_meshes[key], null, pos)


# Shared meshes and materials for the code-built parts (pips, frost and spark towers)
var model_meshes := {}  # merged tower meshes by name
var model_mats := {}  # their materials by color


# Arrow tower: Gettic's archer tower 0.02 (made by Gettic with an AI tool, see
# assets/CREDITS.md), one model per look (L1-L10), each loaded once and shared by
# every arrow tower. The roof tiles, the archer's cape, the banners and the flag
# show the owner's color. The archer stands on the hoarding under the roof and
# walks round it to aim (the head turns, its front is -Z). Levels 1-4 use L1-L4,
# then a new model at levels 5, 10, 15, 20, 30 and 40 (see ARROW_FROM). From level
# 5 the Volley path has three archers, Sniper one.
const ARROW_FILE := "res://assets/towers/arrow/archer_tower_L%d.glb"
const ARROW_MODELS := 10
const ARROW_FROM := [9, 14, 19, 29, 39]  # level index where L6, L7, L8, L9 and L10 start
const ARROW_SCALE := 0.21  # L1 is about 3.5 units wide, a tile is 1
const ARROW_BOW := 0.87  # the archer's bow above his feet, in model units
var arrow_parts := {}  # model 1-10 -> {"Tower", "Archer", "Banner": [[mesh, transform], ...], "feet": Vector3}
var arrow_base := {}  # L1's materials by name (the other models are imported without textures)
var arrow_mats := {}  # team-colored copies of the materials, by name and owner
var pack_meshes := {}  # pack model -> [[mesh, transform], ...], loaded once
var pack_mats := {}  # shared pack materials by texture and owner
var pack_shader: Shader


func build_arrow_tower(root: Node3D, level: int, path: int, slot: int) -> Node3D:
	var d := arrow_model(arrow_look(level))
	var model := Node3D.new()
	model.scale = Vector3.ONE * ARROW_SCALE
	root.add_child(model)
	add_arrow_part(model, d["Tower"], slot)
	add_arrow_part(model, d["Banner"], slot)
	# The head turns at the archer's bow height (higher from L6)
	var feet: Vector3 = d["feet"]
	var head := Node3D.new()
	head.position = Vector3(0, (feet.y + ARROW_BOW) * ARROW_SCALE, 0)
	root.add_child(head)
	var n := 3 if level >= PATH_LEVEL and path == 2 else 1
	for i in n:
		# More archers stand side by side round the hoarding
		var turn := Node3D.new()
		turn.scale = Vector3.ONE * ARROW_SCALE
		turn.rotation.y = (i - (n - 1) / 2.0) * 0.75
		head.add_child(turn)
		var man := Node3D.new()
		man.position = Vector3(0, -ARROW_BOW, -feet.z)
		man.rotation_degrees.y = 180.0  # the model's archer looks at +Z
		turn.add_child(man)
		add_arrow_part(man, d["Archer"], slot)
	return head


# Which model (1-10) a level index shows
func arrow_look(level: int) -> int:
	if level < 4:
		return level + 1
	for i in ARROW_FROM.size():
		if level < ARROW_FROM[i]:
			return 5 + i
	return ARROW_MODELS


# Loads all the models at the start, so upgrading never stutters
func load_arrow_models() -> void:
	for k in range(1, ARROW_MODELS + 1):
		arrow_model(k)


# One model's parts, loaded once. L1 is loaded first: its materials are the shared ones.
func arrow_model(k: int) -> Dictionary:
	if k != 1 and arrow_base.is_empty():
		arrow_model(1)
	if not arrow_parts.has(k):
		var scene: Node = load(ARROW_FILE % k).instantiate()
		var d := {}
		for n in ["Tower", "Archer", "Banner"]:
			var parts := []
			var found: Node3D = scene.find_child(n, true, false)
			# The archer is placed by the code, the others keep their place
			var tr: Transform3D = found.transform.affine_inverse() if n == "Archer" else Transform3D.IDENTITY
			collect_meshes(found, tr, parts)
			d[n] = parts
			if n == "Archer":
				d["feet"] = found.position
		if k == 1:
			for p: Array in d["Tower"] + d["Archer"] + d["Banner"]:
				for s in p[0].get_surface_count():
					var m: Material = p[0].surface_get_material(s)
					arrow_base[m.resource_name] = m
		scene.free()
		arrow_parts[k] = d
	return arrow_parts[k]


# Adds one part of an arrow tower model under parent, with the owner's colors.
func add_arrow_part(parent: Node3D, parts: Array, slot: int) -> void:
	for p: Array in parts:
		var mesh: Mesh = p[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = p[1]
		parent.add_child(mi)
		for s in mesh.get_surface_count():
			mi.set_surface_override_material(s, arrow_mat(mesh.surface_get_material(s).resource_name, slot))


# L1's material of that name, shared by every model; the roof, cape and flags
# as a shared copy in the owner's color.
func arrow_mat(name: String, slot: int) -> Material:
	var team := name == "TeamColor" or name == "RoofTiles"
	if not team:
		return arrow_base[name]
	var key := "%s %d" % [name, slot]
	if not arrow_mats.has(key):
		var c: StandardMaterial3D = arrow_base[name].duplicate()
		var col: Color = PLAYER_COLORS[slot]
		# The roof a little greyer, so it doesn't outshine the map
		c.albedo_color = col.lerp(Color(0.5, 0.5, 0.5), 0.25) if name == "RoofTiles" else col
		arrow_mats[key] = c
	return arrow_mats[key]


# A pack model's meshes (rocks and trees), [[mesh, transform], ...], loaded once.
func pack_parts(file: String) -> Array:
	if not pack_meshes.has(file):
		var parts := []
		var scene: Node = load("res://assets/%s.gltf" % file).instantiate()
		collect_meshes(scene, Transform3D.IDENTITY, parts)
		scene.free()
		pack_meshes[file] = parts
	return pack_meshes[file]


func collect_meshes(n: Node, tr: Transform3D, out: Array) -> void:
	if n is Node3D:
		tr = tr * n.transform
	if n is MeshInstance3D:
		out.append([n.mesh, tr])
	for c in n.get_children():
		collect_meshes(c, tr, out)


# The pack's texture with the owner's color and the rim light (pack_model.gdshader),
# made once per texture and owner.
func pack_mat(mesh: Mesh, slot: int) -> ShaderMaterial:
	var tex: Texture2D = (mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture
	var key := "%d %d" % [tex.get_instance_id(), slot]
	if not pack_mats.has(key):
		if pack_shader == null:
			pack_shader = load("res://assets/shaders/pack_model.gdshader")
		var m := ShaderMaterial.new()
		m.shader = pack_shader
		m.set_shader_parameter("palette", tex)
		m.set_shader_parameter("team", float(slot))
		pack_mats[key] = m
	return pack_mats[key]


# Cannon tower: a dwarven mortar bunker (made for this game with the model kit,
# see assets/CREDITS.md). An eight-sided stone bunker with a furnace, a banner in
# the owner's color and a fat mortar on a turret that turns to aim (front -Z).
# One model per look, like the arrow tower: levels 1-4, then Big Bomb and
# Cluster each get a new model at levels 5, 10, 15, 20, 30 and 40 (Cluster's
# mortars match its bomblets: 3, then 4 at level 20 and 5 at level 40). The
# models have no textures of their own: all share the stone and metal atlas,
# the team cloth (in the owner's color) and the furnace glow.
const CANNON_FILE := "res://assets/towers/cannon/cannon_%d_%d.glb"  # path, look
const CANNON_WIDTH := 0.8  # L1's width on a 1-unit tile
var cannon_parts := {}  # Vector2i(path, look) -> {"body", "head": [[mesh, transform], ...], "pivot": Transform3D}
var cannon_mats := {}  # shared painted materials by name (the team cloth also by owner)
var cannon_scale := 0.0


func build_cannon_tower(root: Node3D, level: int, path: int, slot: int) -> Node3D:
	var d := cannon_model(cannon_look(level, path))
	var model := Node3D.new()
	model.scale = Vector3.ONE * cannon_scale
	root.add_child(model)
	add_cannon_part(model, d["body"], slot)
	# The turret turns round its own axis; the model's front is +Z, the game's -Z
	var pivot: Transform3D = d["pivot"]
	var head := Node3D.new()
	head.position = pivot.origin * cannon_scale
	root.add_child(head)
	var turn := Node3D.new()
	turn.transform = Transform3D(Basis(Vector3.UP, PI) * pivot.basis.scaled(Vector3.ONE * cannon_scale), Vector3.ZERO)
	head.add_child(turn)
	add_cannon_part(turn, d["head"], slot)
	return head


# Which model a level shows: Vector2i(path, look), looks 1-4, then 5-10 per path
func cannon_look(level: int, path: int) -> Vector2i:
	var look := arrow_look(level)
	if look <= 4 or path <= 0:
		return Vector2i(0, mini(look, 4))
	return Vector2i(path, look)


# Loads all the models at the start, so upgrading never stutters
func load_cannon_models() -> void:
	for look in range(1, 5):
		cannon_model(Vector2i(0, look))
	for path in [1, 2]:
		for look in range(5, 11):
			cannon_model(Vector2i(path, look))


func cannon_model(k: Vector2i) -> Dictionary:
	if not cannon_parts.has(k):
		var scene: Node3D = load(CANNON_FILE % [k.x, k.y]).instantiate()
		var turret: Node3D = scene.find_child("Turret", true, false)
		var body := []
		var head := []
		collect_except(scene, Transform3D.IDENTITY, body, turret)
		var pivot := Transform3D.IDENTITY
		var up: Node = turret
		while up != scene:
			pivot = (up as Node3D).transform * pivot
			up = up.get_parent()
		collect_meshes(turret, turret.transform.affine_inverse(), head)
		scene.free()
		cannon_parts[k] = {"body": body, "head": head, "pivot": pivot}
		# All looks use L1's size, so higher levels can grow
		if cannon_scale == 0.0:
			var box := AABB()
			for p: Array in body:
				box = box.merge(p[1] * (p[0] as Mesh).get_aabb())
			cannon_scale = CANNON_WIDTH / maxf(box.size.x, box.size.z)
	return cannon_parts[k]


# Like collect_meshes(), but leaves out the node skip and what's under it
func collect_except(n: Node, tr: Transform3D, out: Array, skip: Node) -> void:
	if n == skip:
		return
	if n is Node3D:
		tr = tr * n.transform
	if n is MeshInstance3D:
		out.append([n.mesh, tr])
	for c in n.get_children():
		collect_except(c, tr, out, skip)


func add_cannon_part(parent: Node3D, parts: Array, slot: int) -> void:
	for p: Array in parts:
		var mesh: Mesh = p[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = p[1]
		parent.add_child(mi)
		for s in mesh.get_surface_count():
			mi.set_surface_override_material(s, cannon_mat(mesh.surface_get_material(s).resource_name, slot))


# The models' three materials: "Atlas" (stone, iron, brass, wood), "TeamColor"
# (cloth in the owner's color, seen from both sides) and "Glow" (the furnaces).
# The baked shading is in the models' vertex colors.
func cannon_mat(name: String, slot: int) -> Material:
	var key := "%s %d" % [name, slot] if name == "TeamColor" else name
	if not cannon_mats.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		match name:
			"TeamColor":
				m.albedo_texture = load("res://assets/towers/cannon/cannon_team.jpg")
				m.albedo_color = PLAYER_COLORS[slot]
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			"Glow":
				m.albedo_texture = load("res://assets/towers/cannon/cannon_glow.jpg")
				m.emission_enabled = true
				m.emission = Color(1.0, 0.75, 0.45)
			_:
				m.albedo_texture = load("res://assets/towers/cannon/cannon_atlas.jpg")
		cannon_mats[key] = painted(m)
	return cannon_mats[key]
# Helpers that build model parts under a temporary node, for merge_parts()
func part_node(p: Node3D, pos: Vector3, rot: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot
	p.add_child(n)
	return n


func part_put(p: Node3D, mesh: Mesh, col: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := add_mesh(p, mesh, model_mat(col), pos)
	mi.rotation_degrees = rot
	return mi


func part_box(p: Node3D, size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return part_put(p, box(size.x, size.y, size.z), col, pos, rot)


func part_cyl(p: Node3D, rt: float, rb: float, h: float, col: Color, pos: Vector3, seg := 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return part_put(p, c, col, pos)


func part_ball(p: Node3D, r: float, col: Color, pos: Vector3) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return part_put(p, s, col, pos)


func part_torus(p: Node3D, ri: float, ro: float, col: Color, pos: Vector3) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = ri
	t.outer_radius = ro
	t.rings = 16
	t.ring_segments = 6
	return part_put(p, t, col, pos)


# A cylinder (a cone when rb != ra) from point a to point b
func part_beam(p: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, col: Color, seg: int) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = ra
	c.top_radius = rb
	c.height = a.distance_to(b)
	c.radial_segments = seg
	c.rings = 1
	var mi := part_put(p, c, col, Vector3.ZERO)
	var y := (b - a).normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) / 2.0)
	return mi


func model_mat(col: Color, glow := 0.0) -> StandardMaterial3D:
	var key: Variant = col if glow == 0.0 else "%s %s" % [col, glow]
	if not model_mats.has(key):
		model_mats[key] = mat(col, glow)
	return model_mats[key]


# Merges all the parts under a temporary node into one mesh with a surface per
# material, then frees the parts.
func merge_parts(parts: Node3D) -> ArrayMesh:
	var tools := {}
	var todo: Array[Node] = [parts]
	while not todo.is_empty():
		var n: Node = todo.pop_back()
		todo.append_array(n.get_children())
		if n is MeshInstance3D:
			var m: Material = n.material_override
			if not tools.has(m):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[m] = st
			# Its transform relative to the temporary node
			var tr: Transform3D = n.transform
			var up := n.get_parent() as Node3D
			while up != parts:
				tr = up.transform * tr
				up = up.get_parent() as Node3D
			tools[m].append_from(n.mesh, 0, tr)
	var mesh := ArrayMesh.new()
	for m: Material in tools:
		tools[m].commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	parts.free()
	return mesh


const AREA_TINT_COMPAT := 0.42  # other players' area tint on Compatibility (0.2 on Forward+)


func update_visuals(delta: float) -> void:
	time += delta
	# Keeps the map above the bottom console at every zoom and map size:
	# the shift grows with the camera's distance
	camera.v_offset = CAMERA_V_OFFSET * zoom * view_scale
	for g in gate_parts.size():
		if gate_parts[g] == null:
			continue
		var in_use: bool = players[g] != null
		for part in gate_parts[g].values():
			part.visible = in_use
		gate_parts[g]["sparks"].rotation.z += delta * 2.0
	var turn := minf(1.0, delta * 12.0)
	for e in enemies:
		var mob: Array = e.node.get_meta("mob")
		# Turn toward the way it walks (not on a jump, like a new monster's first move)
		var p := to3d(e.pos)
		var d := p - e.node.position
		var moved := d.x * d.x + d.z * d.z
		if moved > 1e-7 and moved < 1.0:
			e.node.rotation.y = lerp_angle(e.node.rotation.y, atan2(d.x, d.z), turn)
		e.node.position = p
		# The walk pose for this moment; bob puts each monster at its own point in the step
		var poses: Array = mob[0]
		var mesh: Mesh = poses[int((time / mob[2] + e.bob) * poses.size()) % poses.size()]
		if e.node.mesh != mesh:
			e.node.mesh = mesh
		# Slowed monsters use their look's icy material, frozen ones the frozen one
		var m: Material = mob[1][0]
		if e.freeze_time > 0.0:
			m = mob[1][2]
		elif e.slow_time > 0.0:
			m = mob[1][1]
		if e.node.material_override != m:
			e.node.material_override = m
	update_corpses(delta)
	for t: Tower in towers.values():
		if t.type == "arrow" or t.type == "cannon":
			t.head.rotation.y = atan2(-t.aim.x, -t.aim.y)
		else:
			t.head.rotation.y += delta * 2.0
	for s in shots:
		var y := 0.6
		if s.node.has_meta("from_y"):
			var left := clampf(s.pos.distance_to(s.target_pos) / s.node.get_meta("from_dist"), 0.0, 1.0)
			y = lerpf(0.6, s.node.get_meta("from_y"), left)
		s.node.position = to3d(s.pos, y)
		# Arrows point where they fly
		if s.type == "arrow":
			var to := to3d(s.target_pos, 0.35)
			if Vector2(to.x - s.node.position.x, to.z - s.node.position.z).length() > 0.02:
				s.node.look_at(to, Vector3.UP)

	# While placing a tower: your area goes dark, other players' areas glow in their color.
	# Compatibility blends colors in sRGB, which makes the same alpha look much fainter.
	var tint := AREA_TINT_COMPAT if compat else 0.2
	for slot in area_planes.size():
		var plane: MultiMeshInstance3D = area_planes[slot]
		plane.visible = showing_areas() and players[slot] != null
		var own := slot == local_slot
		plane.material_override.albedo_color = Color(0, 0, 0, 0.5) if own else Color(PLAYER_COLORS[slot], tint)
	# Grid lines fade in on the grass while placing a tower
	var want := 1.0 if build_type != "" and state == "playing" else 0.0
	if grid_fade != want:
		grid_fade = move_toward(grid_fade, want, delta * 5.0)
		if not ground_mats.is_empty():
			ground_mats[0].set_shader_parameter("grid", grid_fade)
	range_disc.visible = false
	ghost.visible = false
	if selected != null:
		show_range(selected.pos, tower_data(selected.type, selected.path, selected.level)["range"][selected.level])
	elif build_type != "" and not mouse_over_panel() and state == "playing":
		var c := mouse_cell()
		if in_map(c):
			ghost.visible = true
			ghost.position = Vector3(c.x + 0.5, 0.05, c.y + 0.5)
			var owner := area_owner(c)
			if not can_build(c):
				ghost_mat.albedo_color = Color(1, 0.2, 0.2, 0.4)
			elif owner >= 0 and owner != local_slot:
				ghost_mat.albedo_color = Color(1, 0.6, 0.1, 0.5)  # needs the other player's yes
			else:
				ghost_mat.albedo_color = Color(0.3, 1, 0.3, 0.4)
			show_range(cell_center(c), TOWERS[build_type]["range"][0])


func showing_areas() -> bool:
	return build_type != "" and state == "playing" and player_count() > 1


func show_range(p: Vector2, rng: float) -> void:
	range_disc.visible = true
	range_disc.position = to3d(p, 0.02)
	var s := rng / CELL
	range_disc.scale = Vector3(s, 1, s)


var shot_meshes := {}  # tower type -> its shot's ball


# A monster's looks, used both by the host and by the other players' copies.
func make_enemy(kind: String) -> Enemy:
	var e := Enemy.new()
	e.kind = kind
	e.color = Color(0.95, 0.5, 0.6)
	match kind:
		"fast":
			e.radius = 8.0
			e.color = Color(1.0, 0.9, 0.3)
		"armored":
			e.radius = 11.0
			e.color = Color(0.6, 0.65, 0.75)
		"boss":
			e.radius = 18.0
			e.weight = 5
			e.color = Color(0.9, 0.15, 0.15)

	build_monsters()
	var look: String = MONSTER_LOOKS[kind]
	if kind == "normal" and wave <= 1:
		look = "unicorn"
	var mob: Array = mobs[look]
	e.mat = mob[1][0]
	e.node = add_mesh(self, mob[0][0], e.mat, to3d(e.pos))
	e.node.set_meta("mob", mob)
	if not graphics_high:
		e.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.bob = randf()
	return e


# ---------------------------------------------------------------- monster models

# Monster kind -> its look. Normal and armored monsters are the skeleton warrior
# (made for this game, assets/monsters/bone_warrior.glb; armored a bit bigger and
# cooler), the boss is a KayKit skeleton mage, the others are built from simple
# shapes here.
const MONSTER_LOOKS := {"normal": "minion", "armored": "warrior", "fast": "spider", "boss": "mage"}
const SKELETON_SIZE := 0.31  # KayKit skeletons are about 2.2 tall: about 0.7 in the game
const BONE_WARRIOR := "res://assets/monsters/bone_warrior.glb"
const BONE_WARRIOR_HEIGHT := 0.68  # like the KayKit skeletons
const DEATH_POSES := 12  # the fall when a monster dies (see drop_corpse())
const MOB_WHITE := Color(0.97, 0.96, 1.0)
const RAINBOW := [Color(1.0, 0.55, 0.7), Color(1.0, 0.72, 0.4), Color(1.0, 0.93, 0.45), Color(0.55, 0.9, 0.6), Color(0.5, 0.75, 1.0), Color(0.75, 0.55, 1.0)]

# Look -> [walk poses (one shared mesh each), [normal, slowed, frozen] material,
# seconds per step, height, death poses (empty: the monster just vanishes)]
var mobs := {}
var walk_anims: AnimationLibrary
var mob_ball: SphereMesh
var mob_rod: CylinderMesh
var mob_cone: CylinderMesh


# Walking monsters stay cheap: each look's walk is posed a few times once, and
# every monster just shows the pose for its moment in the step. Monsters with
# the same pose share one mesh, so Godot draws them together.
func build_monsters() -> void:
	if not mobs.is_empty():
		return
	walk_anims = load("res://assets/monsters/monster_walks.res")
	add_glb_monster("minion", BONE_WARRIOR, BONE_WARRIOR_HEIGHT, Color.WHITE)
	add_glb_monster("warrior", BONE_WARRIOR, BONE_WARRIOR_HEIGHT * 1.1, Color(0.85, 0.9, 1.0))
	add_skeleton("mage", "Skeleton_Mage", "Walking_C", SKELETON_SIZE * 1.8,
			[["Skeleton_Staff", "handslot.r"]], Color(1.0, 0.75, 0.75))
	mob_ball = SphereMesh.new()
	mob_ball.radius = 0.5
	mob_ball.height = 1.0
	mob_ball.radial_segments = 12
	mob_ball.rings = 6
	mob_rod = CylinderMesh.new()
	mob_rod.top_radius = 0.5
	mob_rod.bottom_radius = 0.5
	mob_rod.height = 1.0
	mob_rod.radial_segments = 8
	mob_rod.rings = 1
	mob_cone = mob_rod.duplicate()
	mob_cone.top_radius = 0.0
	add_creature("unicorn", unicorn_pose, 0.7)
	add_creature("spider", spider_pose, 0.35)


# The three painted materials of a look: normal, icy for slowed monsters, and
# frozen solid (whiter, with a cold glow) for Deep Freeze
func mob_mats(base: StandardMaterial3D) -> Array:
	var icy := base.duplicate() as StandardMaterial3D
	icy.albedo_color = base.albedo_color * Color(0.6, 0.85, 1.3)
	var frozen := base.duplicate() as StandardMaterial3D
	frozen.albedo_color = base.albedo_color * Color(0.8, 1.0, 1.45)
	frozen.emission_enabled = true
	frozen.emission = Color(0.35, 0.65, 1.0)
	frozen.emission_energy_multiplier = 0.45
	return [painted(base), painted(icy), painted(frozen)]


# One mesh from the collected parts, with simpler versions for far away
func pose_mesh(parts: Dictionary) -> ArrayMesh:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = parts.v
	a[Mesh.ARRAY_NORMAL] = parts.n
	a[Mesh.ARRAY_TEX_UV] = parts.uv
	a[Mesh.ARRAY_COLOR] = parts.c
	a[Mesh.ARRAY_INDEX] = parts.i
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, a)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


func new_parts() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}


# Adds mesh to parts, moved by xf and colored col
func add_part(parts: Dictionary, mesh: Mesh, xf: Transform3D, col := Color.WHITE) -> void:
	var nb := xf.basis.inverse().transposed()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var base: int = parts.v.size()
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uvs = a[Mesh.ARRAY_TEX_UV]
		for k in vs.size():
			parts.v.append(xf * vs[k])
			parts.n.append((nb * ns[k]).normalized())
			parts.uv.append(uvs[k] if uvs != null else Vector2.ZERO)
			parts.c.append(col)
		for k: int in a[Mesh.ARRAY_INDEX]:
			parts.i.append(base + k)


# A KayKit skeleton walking: 16 poses of its walk, with weapons on the hand bones
func add_skeleton(look: String, file: String, walk: String, size: float, weapons: Array, tint: Color) -> void:
	var root: Node3D = load("res://assets/monsters/%s.glb" % file).instantiate()
	add_child(root)
	var skel: Skeleton3D = root.find_child("Skeleton3D")
	var player := AnimationPlayer.new()
	root.add_child(player)
	player.add_animation_library("", walk_anims)
	var anim := walk_anims.get_animation(walk)
	var held := []
	for w in weapons:
		var scene: Node = load("res://assets/monsters/%s.gltf" % w[0]).instantiate()
		for c in scene.get_children():
			if c is MeshInstance3D:
				held.append([c.mesh, c.transform, skel.find_bone(w[1])])
		scene.free()
	var top := Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3.ZERO)
	var base_mat: StandardMaterial3D
	var poses := []
	player.play(walk)
	for f in 16:
		player.seek(anim.length * f / 16.0, true)
		var parts := new_parts()
		for c in skel.get_children():
			if c is MeshInstance3D:
				if base_mat == null:
					base_mat = c.get_active_material(0)
				add_skinned(parts, c, skel, top)
			elif c is BoneAttachment3D:
				var bone := skel.find_bone(c.bone_name)
				for m in c.get_children():
					if m is MeshInstance3D:
						add_part(parts, m.mesh, top * skel.get_bone_global_pose(bone) * m.transform)
		for h in held:
			add_part(parts, h[0], top * skel.get_bone_global_pose(h[2]) * h[1])
		poses.append(pose_mesh(parts))
	root.free()
	var m := base_mat.duplicate() as StandardMaterial3D
	# The .glb files' own copies of the texture aren't imported: all share this one
	m.albedo_texture = load("res://assets/monsters/skeleton_texture.png")
	m.albedo_color = tint
	mobs[look] = [poses, mob_mats(m), anim.length, poses[0].get_aabb().end.y, []]


# A monster from one .glb with its own "Walk" and "Death": 16 poses of the walk
# and DEATH_POSES of the death, each one shared mesh, feet on the ground.
func add_glb_monster(look: String, file: String, height: float, tint: Color) -> void:
	var root: Node3D = load(file).instantiate()
	add_child(root)
	var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var walk := player.get_animation("Walk")
	var death := player.get_animation("Death")
	player.play("Walk")
	# Pose 0 unscaled first, to fit the height and put the feet on the ground
	var probe := glb_pose(root, player, 0.0, Transform3D.IDENTITY)
	var box := AABB(probe.v[0], Vector3.ZERO)
	for v: Vector3 in probe.v:
		box = box.expand(v)
	var s := height / box.size.y
	var top := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(0, -box.position.y * s, 0))
	var poses := []
	for f in 16:
		poses.append(pose_mesh(glb_pose(root, player, walk.length * f / 16.0, top)))
	var falls := []
	player.play("Death")
	for f in DEATH_POSES:
		falls.append(pose_mesh(glb_pose(root, player, death.length * f / (DEATH_POSES - 1.0), top)))
	var base: StandardMaterial3D = null
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null and base == null:
			base = mi.get_active_material(0)
	root.free()
	var m := base.duplicate() as StandardMaterial3D
	m.albedo_color = tint
	mobs[look] = [poses, mob_mats(m), walk.length, poses[0].get_aabb().end.y, falls]


# Every mesh of the model at time t of the playing animation, in one set of parts
func glb_pose(root: Node3D, player: AnimationPlayer, t: float, top: Transform3D) -> Dictionary:
	player.seek(t, true)
	var parts := new_parts()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			add_part(parts, mi.mesh, top * root.global_transform.affine_inverse() * mi.global_transform)
	return parts


# A killed monster falls apart where it stood (its look's death poses), sinks
# into the ground and is gone after about a second. Only for looks: the
# monster is already out of the game. Looks without a death just vanish.
const CORPSE_FALL := 0.9  # seconds of the fall
const CORPSE_SINK := 0.5  # then seconds of sinking
var corpses: Array[MeshInstance3D] = []


func drop_corpse(e: Enemy) -> void:
	var falls: Array = e.node.get_meta("mob")[4]
	if falls.is_empty():
		e.node.queue_free()
		return
	e.node.set_meta("dead_time", 0.0)
	e.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	corpses.append(e.node)


func update_corpses(delta: float) -> void:
	for i in range(corpses.size() - 1, -1, -1):
		var node := corpses[i]
		var t: float = node.get_meta("dead_time") + delta
		node.set_meta("dead_time", t)
		var falls: Array = node.get_meta("mob")[4]
		node.mesh = falls[mini(int(t / CORPSE_FALL * falls.size()), falls.size() - 1)]
		if t > CORPSE_FALL:
			node.position.y = -0.3 * (t - CORPSE_FALL) / CORPSE_SINK
		if t > CORPSE_FALL + CORPSE_SINK:
			node.queue_free()
			corpses.remove_at(i)


# The corpses go with the monsters when the game is cleared
func clear_world() -> void:
	for node in corpses:
		node.queue_free()
	corpses.clear()
	super()


# Adds a skinned mesh in the skeleton's current pose (the skinning is done here, once)
func add_skinned(parts: Dictionary, mi: MeshInstance3D, skel: Skeleton3D, top: Transform3D) -> void:
	var skin := mi.skin
	var bind := []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		bind.append(skel.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	for s in mi.mesh.get_surface_count():
		var a := mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / vs.size()
		var base: int = parts.v.size()
		for k in vs.size():
			var v := Vector3.ZERO
			var n := Vector3.ZERO
			for j in per:
				var w := ws[k * per + j]
				if w > 0.0:
					var t: Transform3D = bind[bones[k * per + j]]
					v += (t * vs[k]) * w
					n += (t.basis * ns[k]) * w
			parts.v.append(top * v)
			parts.n.append((top.basis * n).normalized())
			parts.uv.append(uvs[k])
			parts.c.append(Color.WHITE)
		for k: int in a[Mesh.ARRAY_INDEX]:
			parts.i.append(base + k)


# A creature built from shapes: 8 poses of its walk, colored per part
func add_creature(look: String, pose: Callable, step: float) -> void:
	var poses := []
	for f in 8:
		var parts := new_parts()
		pose.call(parts, TAU * f / 8.0)
		poses.append(pose_mesh(parts))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.6
	mobs[look] = [poses, mob_mats(m), step, poses[0].get_aabb().end.y, []]


func shape(parts: Dictionary, mesh: Mesh, pos: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	add_part(parts, mesh, Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos), col)


# A rod from a to b
func rod(parts: Dictionary, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var dir := b - a
	var q := Quaternion(Vector3.UP, dir.normalized())
	add_part(parts, mob_rod, Transform3D(Basis(q) * Basis.from_scale(Vector3(r * 2, dir.length(), r * 2)), (a + b) * 0.5), col)


# Wave 1: a cute white unicorn with a golden horn and a rainbow mane, trotting
func unicorn_pose(parts: Dictionary, ph: float) -> void:
	var s := 1.3
	var up := Vector3(0, absf(sin(ph)) * 0.03, 0)
	for leg in [[-1, 1, 0.0], [1, -1, 0.0], [1, 1, PI], [-1, -1, PI]]:
		var swing := sin(ph + leg[2]) * 0.55
		var hip := Vector3(leg[0] * 0.08, 0.2, leg[1] * 0.12) * s
		var foot := hip + Basis(Vector3.RIGHT, swing) * Vector3(0, -0.17 * s, 0)
		rod(parts, hip + up, foot, 0.045 * s, MOB_WHITE)
		shape(parts, mob_rod, foot + Vector3(0, 0.015, 0), Vector3(0.1, 0.04, 0.1) * s, Color(0.95, 0.75, 0.9))
	shape(parts, mob_ball, Vector3(0, 0.26, -0.01) * s + up, Vector3(0.26, 0.24, 0.36) * s, MOB_WHITE)
	shape(parts, mob_ball, Vector3(0, 0.38, 0.13) * s + up, Vector3(0.14, 0.18, 0.14) * s, MOB_WHITE)
	shape(parts, mob_ball, Vector3(0, 0.5, 0.2) * s + up, Vector3(0.24, 0.22, 0.24) * s, MOB_WHITE)
	shape(parts, mob_ball, Vector3(0, 0.46, 0.31) * s + up, Vector3(0.15, 0.12, 0.11) * s, Color(1.0, 0.82, 0.88))
	for x in [-1, 1]:
		shape(parts, mob_ball, Vector3(x * 0.085, 0.53, 0.29) * s + up, Vector3(0.055, 0.065, 0.04) * s, Color(0.12, 0.08, 0.2))
		shape(parts, mob_ball, Vector3(x * 0.095, 0.55, 0.305) * s + up, Vector3(0.02, 0.02, 0.015) * s, Color.WHITE)
		shape(parts, mob_cone, Vector3(x * 0.075, 0.63, 0.15) * s + up, Vector3(0.05, 0.09, 0.035) * s, MOB_WHITE, Vector3(-0.2, 0, -x * 0.35))
		shape(parts, mob_ball, Vector3(x * 0.1, 0.475, 0.29) * s + up, Vector3(0.04, 0.025, 0.02) * s, Color(1.0, 0.6, 0.7))
	shape(parts, mob_cone, Vector3(0, 0.67, 0.25) * s + up, Vector3(0.055, 0.2, 0.055) * s, Color(1.0, 0.82, 0.3), Vector3(0.4, 0, 0))
	for i in 6:
		var k := i / 5.0
		shape(parts, mob_ball, Vector3(0, lerpf(0.64, 0.32, k), lerpf(0.14, -0.05, k)) * s + up, Vector3.ONE * 0.1 * s, RAINBOW[i])
	for i in 5:
		var sway := sin(ph - i * 0.7) * 0.025 * i
		shape(parts, mob_ball, Vector3(sway, 0.31 - i * 0.04, -0.33 - i * 0.035) * s + up, Vector3.ONE * (0.1 - i * 0.01) * s, RAINBOW[i])


# Fast monsters: a bone spider scuttling on 8 legs
func spider_pose(parts: Dictionary, ph: float) -> void:
	var s := 1.3
	var bone := Color(0.92, 0.88, 0.78)
	var dark := Color(0.35, 0.22, 0.4)
	var up := Vector3(0, absf(sin(ph * 2.0)) * 0.015, 0)
	shape(parts, mob_ball, Vector3(0, 0.2, -0.12) * s + up, Vector3(0.28, 0.22, 0.32) * s, bone)
	shape(parts, mob_ball, Vector3(0, 0.28, -0.12) * s + up, Vector3(0.16, 0.08, 0.2) * s, dark)
	shape(parts, mob_ball, Vector3(0, 0.17, 0.09) * s + up, Vector3(0.17, 0.14, 0.17) * s, bone)
	for x in [-1, 1]:
		shape(parts, mob_ball, Vector3(x * 0.04, 0.2, 0.17) * s + up, Vector3.ONE * 0.05 * s, Color(1.0, 0.15, 0.1))
		shape(parts, mob_cone, Vector3(x * 0.035, 0.1, 0.19) * s + up, Vector3(0.03, 0.08, 0.03) * s, dark, Vector3(PI * 0.85, 0, 0))
		for i in 4:
			var p := ph + (PI if (i + (x + 1) / 2) % 2 == 0 else 0.0)
			var lift := maxf(0.0, sin(p)) * 0.06
			var hip := Vector3(x * 0.07, 0.18, 0.08 - i * 0.065) * s + up
			var b := Basis(Vector3.UP, cos(p) * 0.3 * x + (i - 1.5) * -0.5 * x)
			var knee := hip + b * Vector3(x * 0.17, 0.14 + lift, 0) * s
			var foot := hip + b * Vector3(x * 0.32, -0.18 + lift, 0) * s
			rod(parts, hip, knee, 0.024 * s, dark)
			rod(parts, knee, foot, 0.018 * s, bone)


# A shot flying from tower t to the target. A visual shot is the other players'
# copy of the host's shot: it flies the same way but does no damage.
func launch_shot(t: Tower, target: Enemy, visual: bool) -> void:
	var s := Shot.new()
	s.pos = t.pos + t.aim * 14.0
	s.target = target
	s.target_pos = target.pos
	s.type = t.type
	s.level = t.level
	s.path = t.path
	s.owner = t.owner
	s.tower = t
	s.visual = visual
	if t.type == "cannon":
		s.speed = 300.0
	if t.path > 0 and t.level >= PATH_LEVEL:
		s.speed *= PATHS[t.type][t.path - 1].get("shot_speed", 1.0)
	if not shot_mats.has(t.type):
		shot_mats[t.type] = mat(TOWERS[t.type]["color"], 2.0)
		var ball := SphereMesh.new()
		ball.radius = 0.12 if t.type == "cannon" else 0.07
		ball.height = ball.radius * 2.0
		ball.radial_segments = 16
		ball.rings = 8
		shot_meshes[t.type] = ball
	s.node = add_mesh(self, shot_meshes[t.type], shot_mats[t.type], to3d(s.pos, 0.6))
	s.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Arrows are glowing streaks that start up at the archer and come down to the monster (just for looks)
	if t.type == "arrow":
		s.node.mesh = arrow_mesh
		s.node.material_override = null
		s.node.set_meta("from_y", t.head.global_position.y + 0.08)
		s.node.set_meta("from_dist", maxf(s.pos.distance_to(target.pos), 1.0))
	shots.append(s)


func add_bolt(points: PackedVector3Array) -> void:
	effects.append({"kind": "bolt", "points": points, "time": 0.15, "max": 0.15})


func add_boom(pos: Vector2, r: float) -> void:
	var m := mat(Color(1.0, 0.55, 0.15), 1.5, 0.5)
	var node := add_mesh(self, boom_mesh, m, to3d(pos, 0.2))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3.ZERO
	effects.append({"kind": "boom", "node": node, "mat": m, "radius": r, "time": 0.3, "max": 0.3})
	# and a burst of sparks and fire
	fire_burst(boom_pool[boom_next % boom_pool.size()], to3d(pos, 0.2), Color(2.4, 1.2, 0.4))
	boom_next += 1
