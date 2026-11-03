extends "res://game_audio.gd"
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
const WEATHER_SETTINGS := ["random", "day"]  # Settings row "Weather": a random mood each game, or always day
var weather_setting := "random"  # one of WEATHER_SETTINGS (this PC's choice; in multiplayer the host's pick wins)
var compat := false  # running on the Compatibility renderer (older PCs), which needs darker light
var env: Environment
var sun: DirectionalLight3D
var ground_mats: Array[ShaderMaterial] = []  # grass and path
var grid_fade := 0.0  # grid lines on the grass, shown while placing a tower


func build_world() -> void:
	# Forward+ falls back to Compatibility by itself on PCs that can't run it
	compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	add_mood_globals()
	# The painted look: warm late-afternoon light, a soft haze far away, and colors
	# a little stronger. Compatibility renders brighter and more colorful, so it
	# gets its own, lower values. The light's colors and strengths are set by the
	# weather and time of day (see mood_light()).
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	# A sky only for the ambient light and reflections: the camera never sees it
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.ground_bottom_color = Color(0.12, 0.1, 0.08)
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_bloom = 0.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
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
	env.fog_density = 1.0
	env.fog_sky_affect = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Warm sun from the side for long soft shadows, and a cool fill light
	# from the other side so the shadow sides aren't flat
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-30, 150, 0)
	add_child(fill_light)
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
	load_kit_models()
	load_barracks_models()


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
	tree_near = []
	pollen = null
	weather_root = null
	torches = []
	fest_root = null


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
	# The haze starts beyond the board, also on big maps (set in mood_light(), called by apply_graphics())

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
	apply_mood(mood)


# Graphics High: ambient occlusion (dark contact shadows), bounced light, soft
# wide shadows and more glow. Low: plain shadows and less glow, for slower PCs.
# The Compatibility renderer has no ambient occlusion or bounced light anyway.
func apply_graphics() -> void:
	var high := graphics_high
	env.ssao_enabled = high and not compat
	env.ssil_enabled = high and not compat
	# Half the floating pollen on Low
	if pollen != null:
		pollen.amount = POLLEN if high else POLLEN / 2
	sun.shadow_blur = 1.5 if high else 1.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if high else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	# The ground's normal maps (light catching the painted bumps) only on High
	for m in ground_mats:
		m.set_shader_parameter("use_normals", high and not compat)
	# The trees near the board: detailed only on High
	for t: Array in tree_near:
		t[0].mesh = t[1] if high else t[2]
	# Monsters cast shadows only on High (hundreds of them can be walking)
	for e in enemies:
		e.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if high else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The poison cauldrons' motes and the clouds' puffs only on High
	for t: Tower in towers.values():
		if t.type == "poison" and t.head != null:
			var motes := t.head.get_node_or_null("Motes")
			if motes != null:
				motes.visible = high
	if cloud_puffs != null:
		cloud_puffs.visible = high
	# The open gates' purple haze only on High
	for gp: Variant in gate_parts:
		if gp != null:
			gp["mist"].visible = gp["lit"] and high
	# The weather's glow and soft sun, and fewer raindrops and snowflakes on Low
	mood_light()
	if weather_root != null:
		mood_fx()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var found := cfg.load(SETTINGS_FILE) == OK
	load_audio_settings(cfg)
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
	weather_setting = str(cfg.get_value("graphics", "weather", "random"))
	if not weather_setting in WEATHER_SETTINGS:
		weather_setting = "random"
	story_on = bool(cfg.get_value("story", "cards", true))
	festivals_on = bool(cfg.get_value("graphics", "festivals", true))
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
	cfg.set_value("graphics", "weather", weather_setting)
	cfg.set_value("graphics", "festivals", festivals_on)
	cfg.set_value("story", "cards", story_on)
	save_audio_settings(cfg)
	cfg.save(SETTINGS_FILE)


# Stone gate with a green portal where one player's monsters come out. It faces
# along its stretch of path, so monsters walk straight out of it. A gem on top
# shows the player's color; the portal only shows while a player uses the gate.
# It fits inside its own tile, so towers next to it don't cut into it.
const GATE_W := 0.8  # the gate's width compared to its first size (festival decorations too)


#
# The Bone Choir's crypt gate (assets/gates/gate.glb, made for this game): a cracked
# stone frame under a horned skull with the owner's gem, iron-bound doors, and
# behind it a closed crypt, so the portal never shows from behind. Its parts:
# Front, Back (when the tile behind is off the board, with the doors) or Short (a
# wall, when the tile behind is on the board), Runes (glows), Portal, DoorL/DoorR.
# The doors swing open and the portal fades in while a player uses the gate.
const GATE_SCALE := 0.25  # the model's metres to tiles (it's 0.96 tiles wide, like GATE_W)
var gate_models := {}  # part name -> {"parts": [[mesh, transform], ...], "at": transform} (loaded once)
var gate_mats := {}
var gate_glows: Array = []  # [mesh instance, surface, "Rune"/"Crack"] of the gate being built


func gate_model() -> Dictionary:
	if gate_models.is_empty():
		var scene: Node3D = load("res://assets/gates/gate.glb").instantiate()
		var top := scene.find_child("Front", true, false).get_parent()
		for c in top.get_children():
			var parts := []
			collect_meshes(c, Transform3D.IDENTITY, parts)
			gate_models[String(c.name)] = {"parts": parts, "at": (c as Node3D).transform}
		scene.free()
	return gate_models


# The gate's materials, made once (the gem's per player slot). "Off" glows are
# the dim ones while nobody uses the gate.
func gate_mat(name: String, slot: int) -> Material:
	var key := name + (" %d" % slot if name == "TeamColor" else "")
	if not gate_mats.has(key):
		var m: Material
		match name:
			"TeamColor":
				var s := StandardMaterial3D.new()
				s.vertex_color_use_as_albedo = true
				s.albedo_texture = load("res://assets/towers/cannon/cannon_team.jpg")
				s.albedo_color = PLAYER_COLORS[slot]
				s.emission_enabled = true
				s.emission = PLAYER_COLORS[slot]
				s.emission_energy_multiplier = 0.35
				m = painted(s)
			"BoneP":
				# The sculpted skulls and horns: no texture, their look is painted into the vertex colors
				var s := StandardMaterial3D.new()
				s.vertex_color_use_as_albedo = true
				s.roughness = 0.8
				m = painted(s)
			"Crack", "CrackOff", "Seep", "Rune", "RuneOff":
				var s := StandardMaterial3D.new()
				s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				s.albedo_color = {"Crack": Color(1.3, 0.5, 2.0), "CrackOff": Color(0.32, 0.12, 0.45), "Seep": Color(0.45, 0.2, 0.7),
					"Rune": Color(0.45, 1.5, 0.65), "RuneOff": Color(0.06, 0.16, 0.1)}[name]
				m = s
			"Portal":
				var p := ShaderMaterial.new()
				p.shader = load("res://assets/shaders/gate_portal.gdshader")
				p.set_shader_parameter("center", Vector2(0.5, 0.5))
				p.set_shader_parameter("stretch", Vector2(1.0, 1.66))
				p.set_shader_parameter("deep", Color(0.06, 0.0, 0.08))
				p.set_shader_parameter("mid", Color(0.32, 0.12, 0.45))
				p.set_shader_parameter("glow", Color(0.6, 1.0, 0.3))
				p.set_shader_parameter("core", Color(0.85, 1.0, 0.6))
				p.set_shader_parameter("energy", 1.7)
				m = p
			_:
				m = kit_mat("cannon", "Atlas", 0)
		gate_mats[key] = m
	return gate_mats[key]


# One part of the gate model under parent (meshes shared by every gate)
func add_gate_part(parent: Node3D, part: String, slot: int) -> Node3D:
	var d: Dictionary = gate_model()[part]
	var n := Node3D.new()
	n.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * GATE_SCALE), (d["at"] as Transform3D).origin * GATE_SCALE)
	parent.add_child(n)
	for p: Array in d["parts"]:
		var mesh: Mesh = p[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = (d["at"] as Transform3D).affine_inverse() * (p[1] as Transform3D)
		n.add_child(mi)
		for s in mesh.get_surface_count():
			var nm := mesh.surface_get_material(s).resource_name
			mi.set_surface_override_material(s, gate_mat(nm + ("Off" if nm == "Rune" or nm == "Crack" else ""), slot))
			if nm == "Rune" or nm == "Crack":
				gate_glows.append([mi, s, nm])
		if part == "Portal" or part == "Runes":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func build_gate(g: int) -> void:
	var gate := Node3D.new()
	gate.position = to3d(routes[g][0])
	var out_dir: Vector2 = routes[g][1] - routes[g][0]
	gate.rotation.y = atan2(out_dir.x, out_dir.y)
	map_root.add_child(gate)
	# The tile behind: on the board a wall closes the back, off it the crypt and the doors
	var behind: Vector2i = gate_cells[g] - Vector2i(out_dir.normalized().round())
	gate_glows = []
	add_gate_part(gate, "Front", g)
	add_gate_part(gate, "Short" if in_map(behind) else "Back", g)
	add_gate_part(gate, "Runes", g)
	var surface := add_gate_part(gate, "Portal", g)
	surface.visible = false
	var doors := []
	if not in_map(behind):
		for nm in ["DoorL", "DoorR"]:
			doors.append(add_gate_part(gate, nm, g))
	# The portal's light shines out of the front only (never onto the tiles behind)
	var portal_light := SpotLight3D.new()
	portal_light.light_color = Color(0.65, 1.0, 0.45)
	portal_light.spot_range = 2.6
	portal_light.spot_angle = 55.0
	portal_light.position = Vector3(0, 0.55, 0)
	portal_light.rotation.y = PI
	portal_light.visible = false
	gate.add_child(portal_light)
	# Purple motes rising in front of the portal
	var motes := add_motes(gate)
	motes.position = Vector3(0, 0.45, 0.08)
	var mpm := motes.process_material as ParticleProcessMaterial
	mpm.emission_box_extents = Vector3(0.25, 0.3, 0.05)
	mpm.color = Color(1.6, 0.8, 2.2)
	motes.lifetime = 1.1
	motes.visible = false
	# Faint purple haze spilling out low over the ground while the doors are open
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.22, 0.03, 0.05)
	pm.direction = Vector3(0, 0.05, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.12
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.05
	pm.damping_max = 0.1
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.color = Color(0.5, 0.25, 0.7, 0.35)
	pm.color_ramp = fade_ramp()
	var mist := particles(gate, 14, 3.0, 0.4, pm)
	mist.position = Vector3(0, 0.06, -0.08)
	mist.visible = false
	gate_parts.append({"surface": surface, "light": portal_light, "motes": motes, "mist": mist, "doors": doors,
		"glows": gate_glows.duplicate(), "open": 0.0, "lit": false})


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


# Rocks (KayKit Forest Nature Pack, scaled to fit one tile), trees (built in code,
# see add_trees()) and water.
const ROCK_MODELS := [["Rock_1_E", 0.55], ["Rock_3_F", 0.6], ["Rock_3_C", 0.8], ["Rock_2_C", 0.45]]
var nature_mats := {}  # "r" -> the rocks' material


# The pack material for rocks, with less color and darker so they sit with the
# painted grass. Shared by all of a kind.
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
	land_trees = []
	for c: Vector2i in blocked:
		var kind: String = blocked[c]
		if kind == "w":
			water.append(c)
			continue
		var h := tile_hash(c)
		if kind == "t":
			# Painted trees (see add_trees()), always the detailed mesh on the board
			land_trees.append([Vector3(c.x + 0.5, 0.0, c.y + 0.5), deg_to_rad((h >> 9) % 360), 0.8 + (h >> 4) % 16 * 0.01, h, false, false])
			continue
		var pick: Array = ROCK_MODELS[h % ROCK_MODELS.size()]
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
# One MultiMesh; each stone's tilt and height come from tile_hash(). Where a gate
# stands on the edge the curb stops at its pillars (stones there are cut short).
func build_border() -> void:
	var stone := BoxMesh.new()
	stone.size = Vector3(0.42, 0.2, 0.16)
	var xf: Array[Transform3D] = []
	var k := 0
	var gates: Array[Vector3] = []
	for g in gate_cells.size():
		if gate_cells[g] != null:
			gates.append(to3d(routes[g][0]))
	var half := 0.5 * GATE_W + 0.12  # the gate's half width, to the pillars' outsides
	for side in 4:
		var along_x := side < 2
		var length := map_cols if along_x else map_rows
		var count := int(ceil(length / 0.45))
		var line := (-0.08 if side % 2 == 0 else (map_rows if along_x else map_cols) + 0.08)
		for i in count:
			var t := (i + 0.5) * length / count
			var h := tile_hash(Vector2i(k, side * 1000))
			k += 1
			# The stone's ends along the edge, cut back from any gate on this edge
			var a0 := t - 0.21
			var a1 := t + 0.21
			for gp: Vector3 in gates:
				var c := gp.x if along_x else gp.z
				if absf((gp.z if along_x else gp.x) - line) > 0.6 or a1 <= c - half or a0 >= c + half:
					continue
				if a0 < c - half:
					a1 = c - half
				elif a1 > c + half:
					a0 = c + half
				else:
					a1 = a0
			if a1 - a0 < 0.1:
				continue
			t = (a0 + a1) / 2.0
			var pos: Vector3
			if along_x:
				pos = Vector3(t, -0.04, line)
			else:
				pos = Vector3(line, -0.04, t)
			pos.y += (h % 7) * 0.006
			var turn := (0.0 if along_x else PI / 2) + ((h >> 3) % 9 - 4) * 0.03
			xf.append(Transform3D(Basis(Vector3.UP, turn) * Basis.from_scale(Vector3((a1 - a0) / 0.42, 1, 1)), pos))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stone
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = painted(mat(Color(0.62, 0.56, 0.48)))
	mmi.material_override.set_shader_parameter("snow_cap", 1.0)  # Frostfall Fair (see apply_festival())
	map_root.add_child(mmi)


# The land around the board: painted grass fading darker further out, a lake
# beside the board, and forest, bushes, rocks and grass tufts, denser further
# out. All from the map's size, gates and tile_hash(), so every player sees the
# same, on every map size.
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
			# Nothing on the land round a gate (its crypt stands there)
			if near_gate:
				continue
			var dist := maxf(maxf(maxf(-x, x - map_cols + 1), maxf(-y, y - map_rows + 1)), 0)
			var tree_chance := clampf((dist - 1.5) / 3.0, 0.0, 0.7)
			pos.y = -0.12
			# Trees and bushes further out than TREE_FAR use the simpler mesh
			if r < tree_chance:
				land_trees.append([pos, turn, 1.15 + (h >> 7) % 10 * 0.05, h, false, dist > TREE_FAR])
			elif r < tree_chance + 0.12:
				land_trees.append([pos, turn, 1.0 + (h >> 7) % 10 * 0.05, h, true, dist > TREE_FAR])
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
			var kind := "g" if file.begins_with("Grass") else "r"
			mmi.material_override = outer_mat(part[0], kind)
			if kind == "g":
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			map_root.add_child(mmi)
	add_trees()


func put_model(by_model: Dictionary, file: String, pos: Vector3, turn: float, size: float) -> void:
	if not by_model.has(file):
		by_model[file] = []
	by_model[file].append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), pos))


# The painted material of the land's rocks ("r") and grass tufts ("g"), made once
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
		p.set_shader_parameter("grad_top", 0.3)
		p.set_shader_parameter("saturation", 0.92)
		p.set_shader_parameter("tint", Color(0.66, 0.66, 0.64) if kind == "r" else Color(0.6, 0.66, 0.48))
		if kind == "r":
			p.set_shader_parameter("snow_cap", 1.0)  # Frostfall Fair (see apply_festival())
		outer_mats[kind] = p
	return outer_mats[kind]


# ---------------------------------------------------------------- painted trees

# The land's trees and bushes, built in code: lumpy leaf clumps on a bent trunk,
# one mesh each, with painted colors (dark in the crevices, light at the top and
# edges) and a painted leaf texture (assets/shaders/painted_leaves.gdshader).
# One MultiMesh per variant, so hundreds of trees are a few draw calls. Each
# variant has a detailed mesh (near the board, on High) and a simple one (far
# away, shadows, and everything on Low). Picked with tile_hash(), so every
# player sees the same forest.
const TREE_FAR := 2.0  # outer trees further than this from the board use the simple mesh
const LEAF_GREENS := [
	[Color(0.06, 0.14, 0.08), Color(0.18, 0.34, 0.12), Color(0.52, 0.62, 0.22)],
	[Color(0.05, 0.13, 0.10), Color(0.15, 0.31, 0.15), Color(0.42, 0.56, 0.24)],
]
const BARK := [Color(0.16, 0.11, 0.08), Color(0.34, 0.23, 0.15), Color(0.50, 0.38, 0.26)]
const TREE_WEIGHTS := [3.0, 2.0, 2.0, 1.0, 1.0]  # how common each shape is (see tree_mesh())
var land_trees: Array = []  # [pos, turn, size, hash, bush, far], from build_decor() and build_outer()
var tree_kinds: Array = []  # [detailed mesh, simple mesh, weight]; the last two are bushes
var tree_near: Array = []  # [MultiMesh, detailed, simple]: switch with Graphics High/Low
var tree_mat: ShaderMaterial
var tree_noise: FastNoiseLite
var ico_spheres := {}


# A mesh being built: points with normals and colors, and triangles
class TreeMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	func add(p: Vector3, nn: Vector3, col: Color) -> int:
		v.append(p)
		n.append(nn)
		c.append(col)
		return v.size() - 1

	# Godot's front faces are clockwise: order the corners so the face looks along out
	func tri(a: int, b: int, d: int, out: Vector3) -> void:
		if (v[b] - v[a]).cross(v[d] - v[a]).dot(out) > 0.0:
			idx.append_array([a, d, b])
		else:
			idx.append_array([a, b, d])

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


# Places the trees and bushes build_decor() and build_outer() collected
func add_trees() -> void:
	if tree_kinds.is_empty():
		make_tree_kinds()
	var n := tree_kinds.size() - 2
	var total := 0.0
	for i in n:
		total += tree_kinds[i][2]
	var groups := {}  # variant (+100 when far) -> [tree, ...]
	for t: Array in land_trees:
		var h: int = t[3]
		var pick := 0
		if t[4]:
			pick = n + h % 2
		else:
			var r := ((h >> 3) % 1000) / 1000.0 * total
			while pick < n - 1 and r >= tree_kinds[pick][2]:
				r -= tree_kinds[pick][2]
				pick += 1
		if t[5]:
			pick += 100
		if not groups.has(pick):
			groups[pick] = []
		groups[pick].append(t)
	for pick: int in groups:
		var kind: Array = tree_kinds[pick % 100]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = kind[0] if pick < 100 and graphics_high else kind[1]
		mm.instance_count = groups[pick].size()
		for i in mm.instance_count:
			var t: Array = groups[pick][i]
			var h: int = t[3]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, t[1]).scaled(Vector3.ONE * t[2]), t[0]))
			# A little lighter or darker per tree
			var k := 0.88 + ((h >> 13) % 100) / 100.0 * 0.22
			mm.set_instance_color(i, Color(k, k * (0.97 + ((h >> 17) % 7) * 0.01), k * 0.97))
		if pick < 100:
			tree_near.append([mm, kind[0], kind[1]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = tree_mat
		map_root.add_child(mmi)
	land_trees = []


# The tree variants (5 shapes in 2 greens) and 2 bushes, and their material, made once
func make_tree_kinds() -> void:
	tree_noise = FastNoiseLite.new()
	tree_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tree_noise.frequency = 1.0
	tree_noise.seed = 7
	for shape in 5:
		for g in 2:
			tree_kinds.append([tree_mesh(shape, LEAF_GREENS[g], g + 1, 2), tree_mesh(shape, LEAF_GREENS[g], g + 1, 1),
				TREE_WEIGHTS[shape] * (1.0 if g == 0 else 0.7)])
	for b in 2:
		tree_kinds.append([tree_mesh(5, LEAF_GREENS[0], 40 + b, 2), tree_mesh(5, LEAF_GREENS[0], 40 + b, 1), 0.0])
	# Shadows always come from the simple mesh
	for kind: Array in tree_kinds:
		(kind[0] as ArrayMesh).shadow_mesh = kind[1]
	tree_mat = ShaderMaterial.new()
	tree_mat.shader = load("res://assets/shaders/painted_leaves.gdshader")
	tree_mat.set_shader_parameter("leaf_tex", leaf_texture())
	# A faint green rim: just enough to keep the clumps apart (a stronger warm one glowed)
	tree_mat.set_shader_parameter("rim_strength", 0.08)
	tree_mat.set_shader_parameter("rim_color", Color(0.7, 0.85, 0.5))
	tree_mat.set_shader_parameter("grad_low", 0.75)
	tree_mat.set_shader_parameter("grad_high", 1.1)
	tree_mat.set_shader_parameter("grad_top", 1.3)
	tree_mat.set_shader_parameter("top_light", 0.25)


# A tree (shapes 0-4) or a bush (5), one tile tall, in the greens pal.
# sub: the clumps' detail (2: detailed, 1: simple).
func tree_mesh(shape: int, pal: Array, sd: int, sub: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd * 1013 + shape
	var b := TreeMesh.new()
	var h := 0.5  # trunk height
	var cc := Vector3(0, 0.88, 0)  # the crown's middle
	var cr := 0.5  # and its size
	var blobs: Array = []  # [middle, size]
	var bend := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
	match shape:
		0:  # big round crown
			blobs.append([cc, Vector3(0.40, 0.34, 0.40)])
			for i in 4:
				var a := TAU * i / 4 + rng.randf() * 0.8
				blobs.append([cc + Vector3(cos(a) * 0.24, rng.randf_range(-0.08, 0.06), sin(a) * 0.24), Vector3.ONE * rng.randf_range(0.24, 0.29)])
			blobs.append([cc + Vector3(0.02, 0.2, -0.03), Vector3.ONE * 0.24])
		1:  # tall oval crown
			h = 0.55
			cc = Vector3(0, 1.0, 0)
			cr = 0.55
			blobs.append([Vector3(0, 0.78, 0), Vector3(0.33, 0.27, 0.33)])
			blobs.append([Vector3(0.03, 1.05, -0.02), Vector3(0.29, 0.26, 0.29)])
			blobs.append([Vector3(-0.02, 1.3, 0.02), Vector3(0.2, 0.2, 0.2)])
			for i in 3:
				var a := TAU * i / 3 + rng.randf()
				blobs.append([Vector3(cos(a) * 0.2, rng.randf_range(0.8, 1.1), sin(a) * 0.2), Vector3.ONE * 0.2])
		2:  # wide crown on a forked trunk
			h = 0.42
			cc = Vector3(0, 0.78, 0)
			cr = 0.6
			for s: float in [-1.0, 1.0]:
				var side := Vector3(0.24 * s, 0, rng.randf_range(-0.06, 0.06))
				tree_trunk(b, Vector3(0, 0.3, 0), cc + side + Vector3(0, -0.12, 0), 0.04, 0.025, Vector3.ZERO, 5, 3)
				blobs.append([cc + side, Vector3(0.3, 0.26, 0.3)])
				blobs.append([cc + side * 1.5 + Vector3(0, -0.06, 0.12 * s), Vector3.ONE * 0.2])
			blobs.append([cc + Vector3(0, 0.12, 0), Vector3(0.28, 0.24, 0.28)])
			blobs.append([cc + Vector3(0, -0.02, 0.2), Vector3.ONE * 0.21])
			blobs.append([cc + Vector3(0, -0.02, -0.2), Vector3.ONE * 0.21])
		3:  # young tree
			h = 0.36
			cc = Vector3(0, 0.6, 0)
			cr = 0.32
			blobs.append([cc, Vector3(0.25, 0.23, 0.25)])
			blobs.append([cc + Vector3(0.1, 0.13, 0.05), Vector3.ONE * 0.16])
			blobs.append([cc + Vector3(-0.12, -0.02, -0.06), Vector3.ONE * 0.16])
		4:  # leaning tree with an uneven crown
			bend = Vector3(0.1, 0, 0.04)
			cc = Vector3(0.14, 0.86, 0.05)
			blobs.append([cc, Vector3(0.36, 0.3, 0.33)])
			blobs.append([cc + Vector3(0.22, -0.07, 0.04), Vector3.ONE * 0.24])
			blobs.append([cc + Vector3(-0.2, 0.05, -0.08), Vector3.ONE * 0.22])
			blobs.append([cc + Vector3(0.0, 0.18, 0.1), Vector3.ONE * 0.22])
		5:  # bush: low clumps, no trunk
			h = 0.0
			cc = Vector3(0, 0.12, 0)
			cr = 0.36
			blobs.append([cc, Vector3(0.3, 0.22, 0.3)])
			for i in 3:
				var a := TAU * i / 3 + rng.randf()
				blobs.append([cc + Vector3(cos(a) * 0.2, rng.randf_range(-0.04, 0.04), sin(a) * 0.2), Vector3(0.19, 0.16, 0.19)])
	if h > 0.0:
		tree_trunk(b, Vector3.ZERO, Vector3(cc.x, h + 0.15, cc.z), 0.065, 0.04, bend)
	var i := 0
	for bl: Array in blobs:
		i += 1
		leaf_clump(b, bl[0], bl[1], cc, cr, pal, sd * 31 + i, sub)
	return b.mesh()


# A unit ball made of triangles (an icosphere split sub times): [points, corner indices]
func ico_sphere(sub: int) -> Array:
	if ico_spheres.has(sub):
		return ico_spheres[sub]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces: Array = [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	for s in sub:
		var mids := {}
		var split: Array = []
		for f in range(0, faces.size(), 3):
			var m: Array[int] = []
			for e in 3:
				var a: int = faces[f + e]
				var b: int = faces[f + (e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mids.has(key):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					mids[key] = verts.size() - 1
				m.append(mids[key])
			split.append_array([faces[f], m[0], m[2], faces[f + 1], m[1], m[0], faces[f + 2], m[2], m[1], m[0], m[1], m[2]])
		faces = split
	ico_spheres[sub] = [verts, faces]
	return ico_spheres[sub]


# A lumpy leaf clump. Its normals lean out from the crown's middle (cc), so the whole
# crown shades like one soft ball; it's darker in the crevices and underneath.
func leaf_clump(b: TreeMesh, center: Vector3, rad: Vector3, cc: Vector3, cr: float, pal: Array, sd: int, sub: int) -> void:
	var ball: Array = ico_sphere(sub)
	var verts: Array = ball[0]
	var faces: Array = ball[1]
	var pos: Array[Vector3] = []
	var fine: Array[float] = []
	var off := Vector3(sd * 7.31, sd * 3.17, sd * 5.53)
	for d: Vector3 in verts:
		var dd := d
		if dd.y < 0.0:
			dd.y *= 0.75  # flatter underneath
		var f := tree_noise.get_noise_3dv(d * 4.5 + off * 1.3)
		fine.append(f)
		pos.append(center + dd * rad * (1.0 + 0.28 * tree_noise.get_noise_3dv(d * 1.7 + off) + 0.07 * f))
	var sn: Array[Vector3] = []
	sn.resize(pos.size())
	sn.fill(Vector3.ZERO)
	for i in range(0, faces.size(), 3):
		var a: int = faces[i]
		var p: int = faces[i + 1]
		var q: int = faces[i + 2]
		var fn := (pos[p] - pos[a]).cross(pos[q] - pos[a])
		if fn.dot(pos[a] - center) < 0.0:
			fn = -fn
		sn[a] += fn
		sn[p] += fn
		sn[q] += fn
	var base := b.v.size()
	for i in pos.size():
		var cn := (pos[i] - cc).normalized()
		var occ := clampf((pos[i] - cc).length() / cr, 0.0, 1.2)
		var k := occ * 0.75 + (0.5 + 0.5 * cn.y) * 0.4 - 0.3 + fine[i] * 0.2
		b.add(pos[i], (sn[i].normalized() * 0.32 + cn * 0.68 + Vector3.UP * 0.1).normalized(), tree_color(pal, k))
	for i in range(0, faces.size(), 3):
		var a: int = base + faces[i]
		b.tri(a, base + faces[i + 1], base + faces[i + 2], b.v[a] - center)


# A tapered, slightly bent trunk with a root flare. Its color's alpha is 0, so it gets no leaf texture.
func tree_trunk(b: TreeMesh, foot: Vector3, top: Vector3, r0: float, r1: float, bend: Vector3, sides := 7, rings := 5) -> void:
	var base := b.v.size()
	for k in rings + 1:
		var t := float(k) / rings
		var mid := foot.lerp(top, t) + bend * sin(t * PI * 0.8)
		var r := lerpf(r0, r1, t) * (1.0 + 0.9 * pow(1.0 - t, 5.0))
		for s in sides:
			var ang := TAU * s / sides + t * 0.6
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var stripe := tree_noise.get_noise_2d(s * 3.0, t * 2.0)
			b.add(mid + dir * r * (1.0 + 0.1 * stripe), (dir + Vector3.UP * 0.15).normalized(),
				Color(tree_color(BARK, 0.25 + t * 0.55 + stripe * 0.2), 0.0))
	for k in rings:
		for s in sides:
			var a := base + k * sides + s
			var b2 := base + k * sides + (s + 1) % sides
			var out := (b.v[a] + b.v[b2]) * 0.5 - foot.lerp(top, float(k) / rings)
			out.y = 0.0
			b.tri(a, b2, a + sides, out)
			b.tri(b2, b2 + sides, a + sides, out)


# Dark, middle and light color of pal, k from 0 to 1
func tree_color(pal: Array, k: float) -> Color:
	k = clampf(k, 0.0, 1.0)
	if k < 0.5:
		return (pal[0] as Color).lerp(pal[1], k * 2.0)
	return (pal[1] as Color).lerp(pal[2], k * 2.0 - 1.0)


# A grey, tileable texture of painted leaves (the trees' colors give its green)
func leaf_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color(0.36, 0.36, 0.36))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 750:
		var at := Vector2i(rng.randi() % n, rng.randi() % n)
		var ang := rng.randf_range(0.6, 2.5)
		var ln := rng.randf_range(8.0, 14.0)
		var wd := ln * rng.randf_range(0.38, 0.5)
		var light := rng.randf_range(0.45, 0.95)
		var dir := Vector2(cos(ang), sin(ang))
		var side := dir.orthogonal()
		var r := int(ln) + 1
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var q := Vector2(x, y)
				var a := q.dot(dir) / ln
				var b := q.dot(side) / wd
				var prof := 1.0 - a * a
				if prof <= 0.0 or absf(b) > prof * (1.0 + 0.3 * a):
					continue
				# Lighter toward the tip, a darker middle vein
				var shade := light * (0.7 + 0.4 * (0.5 - a * 0.5)) * (1.0 - 0.2 * absf(b))
				if absf(b) < 0.1 and a > -0.8:
					shade *= 0.82
				img.set_pixel(posmod(at.x + x, n), posmod(at.y + y, n), Color(shade, shade, shade))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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


# ---------------------------------------------------------------- weather and time of day

# The mood: the light, sky, haze and ground colors, and the weather's particles.
# Only looks, so it can change at any time; every player sees the same when the
# mood is sent to all (see apply_mood()).
const MOODS := ["day", "evening", "night", "rain", "fog", "snow"]
var mood := "day"  # one of MOODS
var fill_light: DirectionalLight3D  # the cool light from the other side
var weather_root: Node3D  # the mood's rain, snow, leaves, mist or torches (under map_root)
var torches: Array[OmniLight3D] = []  # the night's torch lights (they flicker, see update_visuals())
var weather_mats := {}  # the weather's meshes and materials, made once


# Values shared by every painted shader, so a mood changes all models in one go:
# mood_rim is the rim light's color (rgb) and strength (a, times each material's
# own; 0: the material's own color and strength), mood_rough caps the roughness (wet).
func add_mood_globals() -> void:
	RenderingServer.global_shader_parameter_add(&"mood_rim", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(1, 1, 1, 0))
	RenderingServer.global_shader_parameter_add(&"mood_rough", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	RenderingServer.global_shader_parameter_add(&"fest_snow", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


# Changes the weather and time of day to m (one of MOODS; anything else is "day").
# The festival (see apply_festival()) is picked here too: again for a new game
# (wave 0), kept during one.
func apply_mood(m: String) -> void:
	mood = m if m in MOODS else "day"
	mood_light()
	if wave == 0 or not festival_picked:
		festival_picked = true
		apply_festival(festival_today())
	if map_root != null:
		mood_fx()


# The mood's light, sky, haze, ground colors and rim light. Day is the game's
# normal look; the others change it from there.
func mood_light() -> void:
	var sky: ProceduralSkyMaterial = env.sky.sky_material
	var high := graphics_high
	var s := view_scale
	# Day: warm late-afternoon sun from the side, a cool fill light from the other side
	sun.rotation_degrees = Vector3(-40, -40, 0)
	sun.light_color = Color(1.0, 0.8, 0.58)
	sun.light_energy = 1.3 if compat else 1.75
	sun.shadow_opacity = 1.0
	sun.light_angular_distance = 1.5 if high else 0.0
	fill_light.light_color = Color(0.5, 0.62, 1.0)
	fill_light.light_energy = 0.4 if compat else 0.5
	sky.sky_top_color = Color(0.35, 0.52, 0.8)
	sky.sky_horizon_color = Color(0.85, 0.75, 0.6)
	sky.ground_horizon_color = Color(0.85, 0.75, 0.6).darkened(0.3)
	env.background_color = Color(0.62, 0.6, 0.55)
	env.ambient_light_energy = 0.48 if compat else 0.6
	env.tonemap_exposure = 0.72 if compat else 1.0
	env.adjustment_saturation = 1.02 if compat else 1.2
	env.glow_intensity = 0.75 if high else 0.45
	env.glow_hdr_threshold = 0.85
	env.fog_light_color = Color(0.75, 0.68, 0.55)
	env.fog_depth_begin = 30.0 * s
	env.fog_depth_end = 80.0 * s
	env.fog_depth_curve = 1.5
	var warm: Variant = null  # the ground's tints (null: the ground shader's own)
	var cool: Variant = null
	var snow := false
	var rim := Vector4(1, 1, 1, 0)
	var rough := 1.0
	var bugs := Color(1.4, 1.25, 0.9, 0.8)  # the pollen's color (alpha 0: none)
	var bug_size := 1.0
	match mood:
		"evening":
			# Low golden sun from the left: long shadows, warm haze, cool violet fill
			sun.rotation_degrees = Vector3(-30, -62, 0)
			sun.light_color = Color(1.0, 0.7, 0.45)
			sun.light_energy = 1.45 if compat else 2.1
			fill_light.light_color = Color(0.45, 0.45, 0.95)
			fill_light.light_energy = 0.5
			sky.sky_top_color = Color(0.3, 0.35, 0.65)
			sky.sky_horizon_color = Color(1.0, 0.72, 0.5)
			env.ambient_light_energy = 0.55 if compat else 0.72
			env.fog_light_color = Color(0.9, 0.65, 0.45)
			env.background_color = Color(0.7, 0.5, 0.38)
			warm = Color(1.2, 1.05, 0.7)
			cool = Color(0.8, 0.82, 0.95)
			rim = Vector4(1.0, 0.65, 0.35, 1.3)
			bugs = Color(1.6, 1.0, 0.45, 0.9)
			bug_size = 1.3
		"rain":
			# Overcast: soft grey-blue light, faint shadows, wet shine
			sun.rotation_degrees = Vector3(-55, -30, 0)
			sun.light_color = Color(0.82, 0.88, 1.0)
			sun.light_energy = 0.7 if compat else 0.95
			sun.shadow_opacity = 0.55
			fill_light.light_color = Color(0.6, 0.68, 0.85)
			fill_light.light_energy = 0.35
			sky.sky_top_color = Color(0.5, 0.56, 0.64)
			sky.sky_horizon_color = Color(0.6, 0.63, 0.67)
			env.ambient_light_energy = 0.8 if compat else 1.05
			env.adjustment_saturation = 0.95 if compat else 1.05
			env.fog_light_color = Color(0.5, 0.55, 0.6)
			env.fog_depth_begin = 22.0 * s
			env.fog_depth_end = 60.0 * s
			env.background_color = Color(0.45, 0.48, 0.52)
			warm = Color(1.05, 1.05, 0.9)
			cool = Color(0.75, 0.85, 0.95)
			rim = Vector4(0.75, 0.85, 1.0, 1.15)
			rough = 0.45
			bugs.a = 0.0
		"fog":
			# Misty morning: pale low sun, thick haze over the land
			sun.rotation_degrees = Vector3(-28, -20, 0)
			sun.light_color = Color(1.0, 0.92, 0.82)
			sun.light_energy = 1.0 if compat else 1.35
			sun.shadow_opacity = 0.75
			fill_light.light_color = Color(0.7, 0.78, 0.9)
			sky.sky_top_color = Color(0.62, 0.68, 0.75)
			sky.sky_horizon_color = Color(0.85, 0.85, 0.82)
			env.ambient_light_energy = 0.7 if compat else 0.9
			env.adjustment_saturation = 0.95 if compat else 1.05
			env.fog_light_color = Color(0.78, 0.8, 0.8)
			env.fog_depth_begin = 27.0 * s
			env.fog_depth_end = 55.0 * s
			env.fog_depth_curve = 1.0
			env.background_color = Color(0.75, 0.77, 0.77)
			warm = Color(1.15, 1.08, 0.8)
			cool = Color(0.75, 0.85, 0.9)
			rim = Vector4(0.9, 0.92, 0.95, 1.15)
			bugs.a = 0.0
		"night":
			# Moonlight: cool and dim but still clear, glowing shots, fireflies, and a
			# cold rim on everything so monsters stand out
			sun.rotation_degrees = Vector3(-50, 25, 0)
			sun.light_color = Color(0.55, 0.68, 1.0)
			sun.light_energy = 0.8 if compat else 1.1
			fill_light.light_color = Color(0.35, 0.4, 0.7)
			fill_light.light_energy = 0.25
			sky.sky_top_color = Color(0.12, 0.18, 0.35)
			sky.sky_horizon_color = Color(0.22, 0.28, 0.45)
			sky.ground_horizon_color = Color(0.1, 0.12, 0.18)
			env.ambient_light_energy = 0.8 if compat else 1.1
			env.tonemap_exposure = 0.85 if compat else 1.15
			env.adjustment_saturation = 0.95 if compat else 1.05
			env.fog_light_color = Color(0.08, 0.1, 0.18)
			env.background_color = Color(0.06, 0.07, 0.12)
			env.glow_intensity = 1.0 if high else 0.65
			env.glow_hdr_threshold = 0.7
			warm = Color(1.1, 1.15, 1.1)
			cool = Color(0.9, 1.0, 1.2)
			rim = Vector4(0.6, 0.75, 1.0, 2.15)
			bugs = Color(0.9, 1.4, 0.25, 1.0)
			bug_size = 1.6
		"snow":
			# Winter: white ground, cold bright light
			sun.rotation_degrees = Vector3(-35, -40, 0)
			sun.light_color = Color(1.0, 0.93, 0.85)
			sun.light_energy = 1.1 if compat else 1.4
			fill_light.light_color = Color(0.55, 0.65, 1.0)
			sky.sky_top_color = Color(0.55, 0.65, 0.8)
			sky.sky_horizon_color = Color(0.85, 0.87, 0.9)
			env.ambient_light_energy = 0.5 if compat else 0.65
			env.adjustment_saturation = 0.95 if compat else 1.05
			env.fog_light_color = Color(0.8, 0.83, 0.88)
			env.background_color = Color(0.8, 0.82, 0.86)
			warm = Color(1.05, 1.03, 1.0)
			cool = Color(0.88, 0.94, 1.05)
			snow = true
			rim = Vector4(0.8, 0.88, 1.0, 1.15)
			bugs.a = 0.0
	for gm in ground_mats:
		gm.set_shader_parameter("warm", warm)
		gm.set_shader_parameter("cool", cool)
		gm.set_shader_parameter("grass_color", Color(0.62, 0.66, 0.72) if snow else null)
		gm.set_shader_parameter("detail", 0.3 if snow else null)
		gm.set_shader_parameter("dirt_color", Color(0.4, 0.33, 0.28) if snow else null)
	RenderingServer.global_shader_parameter_set(&"mood_rim", rim)
	RenderingServer.global_shader_parameter_set(&"mood_rough", rough)
	if pollen != null:
		pollen.visible = bugs.a > 0.0
		(pollen.process_material as ParticleProcessMaterial).color = bugs
		(pollen.draw_pass_1 as QuadMesh).size = Vector2(0.045, 0.045) * bug_size


# The mood's particles (rain, snow, falling leaves, mist) or the night's torches,
# made again when the map or Graphics Low/High changes. Bigger maps get more, so
# the weather is as thick everywhere.
func mood_fx() -> void:
	if weather_root != null:
		weather_root.free()
	torches = []
	weather_root = Node3D.new()
	map_root.add_child(weather_root)
	var high := graphics_high
	var k := clampf(map_cols * map_rows / (24.0 * 18.0), 1.0, 2.0)
	match mood:
		"evening":
			add_leaves(int((90 if high else 45) * k))
		"rain":
			add_rain(int((1600 if high else 700) * k))
		"fog":
			add_mist(int((36 if high else 18) * k))
		"night":
			add_torches()
		"snow":
			add_snow(int((1200 if high else 500) * k))
	festival_decor()


# Weather falling or drifting over the whole board, from a box at height y
func weather_particles(amount: int, life: float, pm: ParticleProcessMaterial, mesh: Mesh, y: float) -> GPUParticles3D:
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(map_cols / 2.0 + 3, 0.2, map_rows / 2.0 + 3)
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(map_cols / 2.0, y, map_rows / 2.0)
	p.visibility_aabb = AABB(Vector3(-map_cols, -y - 2, -map_rows), Vector3(map_cols * 2, y + 8, map_rows * 2))
	p.preprocess = life
	weather_root.add_child(p)
	return p


# A soft dot drawn over what's behind it (not added like the glowing dots)
func weather_dot(size: Vector2) -> QuadMesh:
	var m: StandardMaterial3D = dot_mat.duplicate()
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var q := QuadMesh.new()
	q.size = size
	q.material = m
	return q


# A thin vertical streak, see-through at both ends
func streak_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.7, Color(1, 1, 1, 1))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 4
	tex.height = 32
	return tex


# Rain streaks, and small rings that grow and fade where drops hit the ground
func add_rain(amount: int) -> void:
	if not weather_mats.has("rain"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		m.albedo_texture = streak_tex()
		m.albedo_color = Color(0.8, 0.88, 1.0, 0.32)
		var q := QuadMesh.new()
		q.size = Vector2(0.018, 0.5)
		q.material = m
		weather_mats["rain"] = q
		var sq := QuadMesh.new()
		sq.size = Vector2(0.09, 0.09)
		sq.orientation = PlaneMesh.FACE_Y
		var sm: StandardMaterial3D = dot_mat.duplicate()
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		sq.material = sm
		weather_mats["splash"] = sq
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.08, -1, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 13.0
	pm.gravity = Vector3.ZERO
	# Falls 9 units in 0.75 s: from y 9 to the ground
	weather_particles(amount, 0.75, pm, weather_mats["rain"], 9.0)
	var sp := ParticleProcessMaterial.new()
	sp.gravity = Vector3.ZERO
	sp.color = Color(0.75, 0.85, 1.0, 0.5)
	sp.color_ramp = fade_ramp()
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1))
	var ct := CurveTexture.new()
	ct.curve = curve
	sp.scale_curve = ct
	weather_particles(int(amount / 4.0), 0.3, sp, weather_mats["splash"], 0.03)


# Slow snowflakes drifting down
func add_snow(amount: int) -> void:
	if not weather_mats.has("snow"):
		weather_mats["snow"] = weather_dot(Vector2(0.06, 0.06))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.2, -1, 0.1)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.color = Color(1.0, 1.0, 1.0, 0.9)
	pm.color_ramp = fade_ramp()
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	weather_particles(amount, 8.0, pm, weather_mats["snow"], 8.0)


# Orange and red leaves tumbling down in the evening
func add_leaves(amount: int) -> void:
	if not weather_mats.has("leaf"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = soft_dot()
		var q := QuadMesh.new()
		q.size = Vector2(0.11, 0.06)
		q.material = m
		weather_mats["leaf"] = q
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.6, -1, 0.2)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.1, -0.2, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_scale = 2.0
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.2
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -180.0
	pm.angular_velocity_max = 180.0
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.45, 0.12))
	g.set_color(1, Color(0.95, 0.8, 0.25))
	g.add_point(0.5, Color(0.8, 0.25, 0.1))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	weather_particles(amount, 9.0, pm, weather_mats["leaf"], 6.0)


# Big soft patches of mist drifting low over the board
func add_mist(amount: int) -> void:
	if not weather_mats.has("mist"):
		weather_mats["mist"] = weather_dot(Vector2(3.0, 3.0))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0, 0.2)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3.ZERO
	pm.color = Color(0.92, 0.94, 0.95, 0.07)
	pm.color_ramp = fade_ramp()
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	weather_particles(amount, 14.0, pm, weather_mats["mist"], 0.5)
	pm.emission_box_extents.y = 0.3


# A torch on each side of every gate: a post, a flame and a warm light (no shadows)
func add_torches() -> void:
	if not weather_mats.has("post"):
		weather_mats["post"] = box(0.08, 0.7, 0.08)
		weather_mats["wood"] = painted(mat(Color(0.3, 0.2, 0.12)))
	for g in gate_cells.size():
		if gate_cells[g] == null:
			continue
		var at := to3d(routes[g][0])
		var out_dir: Vector2 = (routes[g][1] - routes[g][0]).normalized()
		var side := Vector3(out_dir.y, 0, -out_dir.x)
		for k in [-1.0, 1.0]:
			# In front of the gate's pillars, inside its own tile
			var p: Vector3 = at + side * (0.5 * GATE_W + 0.05) * k + Vector3(out_dir.x, 0, out_dir.y) * 0.3
			add_mesh(weather_root, weather_mats["post"], weather_mats["wood"], p + Vector3(0, 0.35, 0))
			var pm := ParticleProcessMaterial.new()
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.04
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 10.0
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 0.6
			pm.gravity = Vector3.ZERO
			pm.color = Color(2.4, 1.2, 0.4)
			pm.color_ramp = fade_ramp()
			var fl := particles(weather_root, 16, 0.5, 0.14, pm)
			fl.position = p + Vector3(0, 0.75, 0)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.omni_range = 3.5
		l.light_energy = 2.2
		l.position = at + Vector3(out_dir.x, 0, out_dir.y) * 0.6 + Vector3(0, 0.9, 0)
		weather_root.add_child(l)
		torches.append(l)


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
	make_ability_fx()
	make_cloud_fx()
	make_special_fx()
	# Grimwhistle's death: a purple blast as he falls, bone shards when he lands
	var blast := burst(60, 0.9, 0.09, 4.0)
	(blast.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.5, 0)
	var shards := burst(70, 1.2, 0.06, 2.4)
	(shards.process_material as ParticleProcessMaterial).spread = 70.0
	grim_bursts = [blast, shards]


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
	sound_hit(s)
	if s.type == "cannon":
		return
	var col := Color(0.8, 1.6, 2.4) if s.type == "frost" else Color(1.6, 1.3, 0.7)
	var y := 0.35
	if s.type == "poison":
		col = Color(0.9, 2.4, 0.4)  # a green splash where the glob lands
		y = 0.2
	fire_burst(hit_pool[hit_next % hit_pool.size()], to3d(s.target_pos, y), col)
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
	if t.type == "barracks":
		t.head = build_barracks_tower(root, t)
		add_pips(root, look, Vector3(0, 0.06, 0.44))
		paint_tree(root)
		t.node = root
		return
	if t.type == "arrow" or KIT_FILES.has(t.type):
		var model_head: Node3D
		if t.type == "arrow":
			model_head = build_arrow_tower(root, t.level, t.path, t.owner)
		else:
			model_head = build_kit_tower(t.type, root, t.level, t.path, t.owner)
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


# Towers made for this game with the model kit (see assets/CREDITS.md), loaded
# the same way: one model per look, each loaded once and shared by every tower
# of its kind. Levels 1-4 have a look each, then each path gets a new model at
# levels 5, 10, 15, 20, 30 and 40. A turret turns to aim (front -Z). The models
# have no textures of their own: all share the stone and metal atlas, and each
# kind has its team cloth (in the owner's color) and glow.
#
# Cannon: a dwarven mortar bunker. An eight-sided stone bunker with a furnace, a
# banner and a fat mortar on the turret; Big Bomb's mortar grows, Cluster's
# mortars match its bomblets (3, then 4 at level 20 and 5 at level 40).
#
# Poison: a plague cauldron. A round stone tower on timber props, brew spilling
# down its walls and out of a sluice at the front, and a cauldron on a turning
# yoke, tipped toward its target. Stills with glowing bulbs from level 3. Venom
# grows a crown of fangs and brews bright acid; Miasma gets smokestacks, more
# vats and a murky brew. Green motes rise from the cauldron on High.
const KIT_FILES := {"cannon": "res://assets/towers/cannon/cannon_%d_%d.glb",
		"poison": "res://assets/towers/poison/poison_%d_%d.glb"}
const KIT_WIDTH := {"cannon": 0.8, "poison": 0.86}  # L1's width on a 1-unit tile
var kit_parts := {}  # tower type -> Vector2i(path, look) -> {"body", "head": [[mesh, transform], ...], "pivot", "pot"}
var kit_mats := {}  # shared materials by type and name (the team cloth also by owner)
var kit_scale := {}  # tower type -> the scale of all its looks (from L1)
var mote_process: ParticleProcessMaterial  # the poison cauldron's motes, shared


func build_kit_tower(type: String, root: Node3D, level: int, path: int, slot: int) -> Node3D:
	var d := kit_model(type, kit_look(level, path))
	var sc: float = kit_scale[type]
	var model := Node3D.new()
	model.scale = Vector3.ONE * sc
	root.add_child(model)
	add_kit_part(type, model, d["body"], slot)
	# The turret turns round its own axis; the model's front is +Z, the game's -Z
	var pivot: Transform3D = d["pivot"]
	var head := Node3D.new()
	head.position = pivot.origin * sc
	root.add_child(head)
	var turn := Node3D.new()
	turn.transform = Transform3D(Basis(Vector3.UP, PI) * pivot.basis.scaled(Vector3.ONE * sc), Vector3.ZERO)
	head.add_child(turn)
	add_kit_part(type, turn, d["head"], slot)
	if type == "poison":
		add_brew_motes(head, Basis(Vector3.UP, PI) * pivot.basis * (d["pot"] as Vector3) * sc)
	return head


# Which model a level shows: Vector2i(path, look), looks 1-4, then 5-10 per path
func kit_look(level: int, path: int) -> Vector2i:
	var look := arrow_look(level)
	if look <= 4 or path <= 0:
		return Vector2i(0, mini(look, 4))
	return Vector2i(path, look)


# Loads all the models at the start, so upgrading never stutters
func load_kit_models() -> void:
	for type: String in KIT_FILES:
		for look in range(1, 5):
			kit_model(type, Vector2i(0, look))
		for path in [1, 2]:
			for look in range(5, 11):
				kit_model(type, Vector2i(path, look))


func kit_model(type: String, k: Vector2i) -> Dictionary:
	if not kit_parts.has(type):
		kit_parts[type] = {}
	var store: Dictionary = kit_parts[type]
	if not store.has(k):
		var scene: Node3D = load(KIT_FILES[type] % [k.x, k.y]).instantiate()
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
		# The cauldron's brew, in turret space (the motes rise from there)
		var pot := Vector3.ZERO
		var pot_node := scene.find_child("Pot", true, false) as Node3D
		if pot_node != null:
			pot = pot_node.position + pot_node.basis * Vector3(0, 0.3, 0)
		scene.free()
		store[k] = {"body": body, "head": head, "pivot": pivot, "pot": pot}
		# All looks use L1's size, so higher levels can grow
		if not kit_scale.has(type):
			var box := AABB()
			for p: Array in body:
				box = box.merge(p[1] * (p[0] as Mesh).get_aabb())
			kit_scale[type] = KIT_WIDTH[type] / maxf(box.size.x, box.size.z)
	return store[k]


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


func add_kit_part(type: String, parent: Node3D, parts: Array, slot: int) -> void:
	for p: Array in parts:
		var mesh: Mesh = p[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = p[1]
		parent.add_child(mi)
		for s in mesh.get_surface_count():
			mi.set_surface_override_material(s, kit_mat(type, mesh.surface_get_material(s).resource_name, slot))


# The models' three materials: "Atlas" (stone, iron, brass, wood; the same for
# every kind), "TeamColor" (cloth in the owner's color, seen from both sides) and
# "Glow" (the cannon's furnaces, the poison tower's brew, see brew.gdshader).
# The baked shading is in the models' vertex colors.
func kit_mat(type: String, name: String, slot: int) -> Material:
	var key := "Atlas"
	if name == "TeamColor":
		key = "%s %s %d" % [type, name, slot]
	elif name == "Glow":
		key = "%s %s" % [type, name]
	if not kit_mats.has(key):
		var folder := "res://assets/towers/%s/%s_" % [type, type]
		if name == "Glow" and type == "poison":
			var b := ShaderMaterial.new()
			b.shader = load("res://assets/shaders/brew.gdshader")
			b.set_shader_parameter("tex", load(folder + "glow.jpg"))
			b.set_shader_parameter("energy", 0.8 if compat else 1.1)
			kit_mats[key] = b
			return b
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		match name:
			"TeamColor":
				m.albedo_texture = load(folder + "team.jpg")
				m.albedo_color = PLAYER_COLORS[slot]
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			"Glow":
				m.albedo_texture = load(folder + "glow.jpg")
				m.emission_enabled = true
				m.emission = Color(1.0, 0.75, 0.45)
			_:
				m.albedo_texture = load("res://assets/towers/cannon/cannon_atlas.jpg")
		kit_mats[key] = painted(m)
	return kit_mats[key]


# Green motes bubbling up out of the poison cauldron (High only, see apply_graphics())
func add_brew_motes(head: Node3D, at: Vector3) -> void:
	if mote_process == null:
		mote_process = ParticleProcessMaterial.new()
		mote_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mote_process.emission_sphere_radius = 0.1
		mote_process.direction = Vector3(0, 1, 0)
		mote_process.spread = 20.0
		mote_process.initial_velocity_min = 0.15
		mote_process.initial_velocity_max = 0.35
		mote_process.gravity = Vector3.ZERO
		mote_process.color = Color(0.7, 1.6, 0.4, 0.8)
		mote_process.color_ramp = fade_ramp()
		mote_process.scale_min = 0.5
		mote_process.scale_max = 1.3
	var p := particles(head, 8, 1.4, 0.04, mote_process)
	p.name = "Motes"
	p.position = at
	p.visible = graphics_high
	p.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))


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


# ---------------------------------------------------------------- Barracks

# Barracks: a guard hall made with the model kit (see assets/CREDITS.md), one
# model per look like the cannon's: levels 1-4, then Knights (a stone keep) and
# Militia (a wooden camp) at levels 5, 10, 15, 20, 30 and 40. Nothing turns: the
# whole model faces its rally point, where a small flag stands.
const BARRACKS_FILE := "res://assets/towers/barracks/barracks_%d_%d.glb"
const BARRACKS_WIDTH := 0.9  # L1's width on a 1-unit tile
const BARRACKS_REACH := 0.48  # how far from its tile's middle the hall may reach
var barracks_parts := {}  # Vector2i(path, look) -> [[mesh, transform], ...]
var barracks_box := {}  # Vector2i(path, look) -> the model's box before scaling
var barracks_scale := 0.0
var barracks_mats := {}


func build_barracks_tower(root: Node3D, t: Tower) -> Node3D:
	var model := Node3D.new()
	var parts: Array = barracks_model(kit_look(t.level, t.path))
	model.scale = Vector3.ONE * barracks_scale
	root.add_child(model)
	for p: Array in parts:
		var mesh: Mesh = p[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = p[1]
		model.add_child(mi)
		for s in mesh.get_surface_count():
			mi.set_surface_override_material(s, barracks_mat(mesh.surface_get_material(s).resource_name, t.owner))
	# The door faces the rally point; a small flag stands at its edge
	var r := t.rally
	if r.x < 0.0:
		r = rally_point(t.cell, TOWERS["barracks"]["range"][0])
	if r.x >= 0.0:
		var d := r - t.pos
		root.rotation.y = atan2(d.x, d.y)
		var flag := add_mesh(root, rally_flag(t.owner), null)
		flag.position = root.basis.inverse() * (to3d(r - d.normalized() * CELL * 0.4) - root.position)
	# Turned towards its rally point, the hall stays inside its own tile, so it
	# never cuts into a gate, the board's edge or the next tower
	var box: AABB = barracks_box[kit_look(t.level, t.path)]
	var turn := Basis(Vector3.UP, root.rotation.y)
	var reach := 0.0
	for i in 4:
		var corner := turn * Vector3(box.position.x if i % 2 == 0 else box.end.x, 0, box.position.z if i < 2 else box.end.z) * barracks_scale
		reach = maxf(reach, maxf(absf(corner.x), absf(corner.z)))
	if reach > BARRACKS_REACH:
		model.scale *= BARRACKS_REACH / reach
	return model


# Loads all the models at the start, so building and upgrading never stutter
func load_barracks_models() -> void:
	for look in range(1, 5):
		barracks_model(Vector2i(0, look))
	for path in [1, 2]:
		for look in range(5, 11):
			barracks_model(Vector2i(path, look))
	load_soldiers()


func barracks_model(k: Vector2i) -> Array:
	if not barracks_parts.has(k):
		var scene: Node3D = load(BARRACKS_FILE % [k.x, k.y]).instantiate()
		var parts := []
		collect_meshes(scene, Transform3D.IDENTITY, parts)
		scene.free()
		barracks_parts[k] = parts
		var b := AABB()
		for p: Array in parts:
			b = b.merge(p[1] * (p[0] as Mesh).get_aabb())
		barracks_box[k] = b
		# All looks use L1's size, so higher levels can grow
		if barracks_scale == 0.0:
			var box := AABB()
			for p: Array in parts:
				box = box.merge(p[1] * (p[0] as Mesh).get_aabb())
			barracks_scale = BARRACKS_WIDTH / maxf(box.size.x, box.size.z)
	return barracks_parts[k]


# The cannon's atlas and fire glow, its own team cloth, and team roof shingles
# (a little greyer, like the arrow tower's roof)
func barracks_mat(name: String, slot: int) -> Material:
	if name == "Atlas" or name == "Glow":
		return kit_mat("cannon", name, slot)
	var key := "%s %d" % [name, slot]
	if not barracks_mats.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		var col: Color = PLAYER_COLORS[slot]
		if name == "TeamRoof":
			m.albedo_texture = load("res://assets/towers/barracks/barracks_roof.jpg")
			m.albedo_color = col.lerp(Color(0.5, 0.5, 0.5), 0.25)
		else:
			m.albedo_texture = load("res://assets/towers/barracks/barracks_team.jpg")
			m.albedo_color = col
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		barracks_mats[key] = painted(m)
	return barracks_mats[key]


# A small pole with a pennant in the owner's color, one shared mesh per owner
func rally_flag(slot: int) -> Mesh:
	var key := "rally %d" % slot
	if not model_meshes.has(key):
		var parts := Node3D.new()
		part_cyl(parts, 0.07, 0.09, 0.05, Color(0.55, 0.52, 0.47), Vector3(0, 0.025, 0), 7)
		part_cyl(parts, 0.012, 0.016, 0.55, Color(0.4, 0.27, 0.15), Vector3(0, 0.3, 0), 6)
		part_ball(parts, 0.028, Color(1.0, 0.78, 0.3), Vector3(0, 0.58, 0))
		var tri := PrismMesh.new()
		tri.size = Vector3(0.16, 0.24, 0.012)
		part_put(parts, tri, PLAYER_COLORS[slot], Vector3(0.12, 0.47, 0), Vector3(0, 0, -90))
		model_meshes[key] = merge_parts(parts)
	return model_meshes[key]


# Soldiers: puppets made with the model kit (assets/units/soldier_*.glb), posed
# a few times per animation at the start like the monsters. Every pose is one
# MultiMesh for all players (the owner's color is in each soldier's custom
# data, see soldier.gdshader), so 40 soldiers are a handful of draw calls.
const SOLDIER_FILE := "res://assets/units/soldier_%s.glb"
const SOLDIER_KINDS := {"footman": 0.46, "knight": 0.5, "militia": 0.44}  # kind -> height
const SOLDIER_ANIMS := ["Idle", "Fight", "Walk", "Fall"]
const SOLDIER_FRAMES := 8  # poses per animation
const SOLDIER_SPEED := 1.6  # tiles a second, walking out of the door and to their monster
var soldier_poses := {}  # "kind anim" -> [MultiMeshInstance3D per pose]
var soldier_len := {}  # anim -> seconds
var soldier_vis := {}  # Tower -> per soldier {"p": Vector3, "turn": float, "fall": float}
var soldier_need := {}  # MultiMeshInstance3D -> instances it lacked last frame (it grows)
var soldier_bars: Array = []  # hurt soldiers this frame: [3D point over the head, health share 0-1, owner] (for the ui's health bars)


func load_soldiers() -> void:
	if not soldier_poses.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/soldier.gdshader")
	mat.set_shader_parameter("albedo_tex", load("res://assets/units/soldier.jpg"))
	for kind: String in SOLDIER_KINDS:
		var root: Node3D = load(SOLDIER_FILE % kind).instantiate()
		add_child(root)
		var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		player.play("Idle")
		# Pose 0 unscaled first, to fit the height and put the feet on the ground
		var probe := soldier_pose(root, player, 0.0, Transform3D.IDENTITY)
		var box := AABB(probe.v[0], Vector3.ZERO)
		for v: Vector3 in probe.v:
			box = box.expand(v)
		var s: float = SOLDIER_KINDS[kind] / box.size.y
		var top := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(0, -box.position.y * s, 0))
		for anim: String in SOLDIER_ANIMS:
			var a := player.get_animation(anim)
			soldier_len[anim] = a.length
			player.play(anim)
			var list := []
			for f in SOLDIER_FRAMES:
				var at := a.length * f / (SOLDIER_FRAMES - 1.0 if anim == "Fall" else float(SOLDIER_FRAMES))
				list.append(fx_multimesh(pose_mesh(soldier_pose(root, player, at, top)), mat, 48))
			soldier_poses["%s %s" % [kind, anim]] = list
		root.free()


# Like glb_pose(), keeping the vertex colors (their alpha marks the team parts)
func soldier_pose(root: Node3D, player: AnimationPlayer, t: float, top: Transform3D) -> Dictionary:
	player.seek(t, true)
	var parts := new_parts()
	var back := root.global_transform.affine_inverse()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := top * back * mi.global_transform
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(s)
			var base: int = parts.v.size()
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var uvs = a[Mesh.ARRAY_TEX_UV]
			var cs = a[Mesh.ARRAY_COLOR]
			for k in vs.size():
				parts.v.append(xf * vs[k])
				parts.n.append((nb * ns[k]).normalized())
				parts.uv.append(uvs[k] if uvs != null else Vector2.ZERO)
				parts.c.append(cs[k] if cs != null else Color(1, 1, 1, 0))
			for k: int in a[Mesh.ARRAY_INDEX]:
				parts.i.append(base + k)
		if festival == "frostfall" and mi.name == "Head":
			soldier_scarf(parts, xf)
	return parts


# Each frame, before main.gd's update_visuals() calls show_soldiers(): every pose
# MultiMesh starts empty, and grows if it ran out of room last frame.
func start_soldiers() -> void:
	soldier_bars.clear()
	for node: MultiMeshInstance3D in soldier_need:
		node.multimesh.instance_count = soldier_need[node] + 16
	soldier_need.clear()
	# Shadows only on Graphics High, like the monsters'
	var shade := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if graphics_high else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for list: Array in soldier_poses.values():
		for node: MultiMeshInstance3D in list:
			node.multimesh.visible_instance_count = 0
			node.cast_shadow = shade
			fx_box(node.multimesh)
	for t: Tower in soldier_vis.keys():
		if towers.get(t.cell) != t:
			soldier_vis.erase(t)


# One Barracks' soldiers, from soldier_look (every computer has it): a byte per
# soldier, its health share 1-127 (0: fallen), + 128 while it holds a monster.
# A holding soldier fights the monster nearest the rally point (every computer
# knows where the monsters are). Fallen soldiers fall, lie a moment and sink
# away; back, they walk out of the door.
func show_soldiers(t: Tower) -> void:
	if soldier_poses.is_empty() or t.node == null or t.rally.x < 0.0:
		return
	var kind := "footman"
	if t.level >= PATH_LEVEL and t.path > 0:
		kind = "knight" if t.path == 1 else "militia"
	var home := to3d(t.rally)
	var face := t.node.rotation.y
	var door := t.node.position + Vector3(sin(face), 0, cos(face)) * 0.4
	var n := t.soldier_look.size()
	var looks: Array = soldier_vis.get(t, [])
	while looks.size() < n:
		looks.append({"p": door, "turn": face, "fall": -1.0})
	looks.resize(n)
	soldier_vis[t] = looks
	var reach := ENGAGE_R * (2.0 if kind == "militia" else 1.0) * 1.6
	var taken := []
	var delta := get_process_delta_time()
	for i in n:
		var s: Dictionary = looks[i]
		var b: int = t.soldier_look[i]
		var hp := (b & 127) / 127.0
		var anim := "Idle"
		var ph: float = time / soldier_len["Idle"] + i * 0.37
		var y := 0.0
		if hp <= 0.0:
			if s.fall < 0.0:
				s.fall = 0.0
			s.fall += delta
			if s.fall > 2.2:
				s.p = door
				continue
			anim = "Fall"
			ph = minf(s.fall / soldier_len["Fall"], 1.0) * (SOLDIER_FRAMES - 1.0) / SOLDIER_FRAMES
			y = -clampf((s.fall - 1.4) / 0.8, 0.0, 1.0) * 0.3
		else:
			if s.fall >= 0.0:
				s.fall = -1.0
				s.p = door
			# Its spot round the rally point, or next to the monster it holds
			var spot := home
			if n > 1:
				var a := face + TAU * i / n + 0.4
				spot += Vector3(sin(a), 0, cos(a)) * (0.13 + 0.035 * n)
			var want := face
			var goal := spot
			var foe: Enemy = null
			if b & 128:
				var best := reach * reach
				for e in enemies:
					if e.dead or e.node == null or e in taken:
						continue
					var d := e.pos.distance_squared_to(t.rally)
					if d < best:
						best = d
						foe = e
			if foe != null:
				taken.append(foe)
				var ep := foe.node.position
				var away := spot - ep
				away.y = 0.0
				if away.length() < 0.01:
					away = Vector3(sin(face), 0, cos(face))
				goal = ep + away.normalized() * (0.2 + foe.radius / CELL)
				want = atan2(ep.x - goal.x, ep.z - goal.z)
			var to: Vector3 = goal - s.p
			to.y = 0.0
			if to.length() > 0.05:
				s.p += to.limit_length(SOLDIER_SPEED * delta)
				anim = "Walk"
				ph = time / soldier_len["Walk"] + i * 0.37
				want = atan2(to.x, to.z)
			elif foe != null:
				anim = "Fight"
				ph = time / soldier_len["Fight"] + i * 0.29
			s.turn = lerp_angle(s.turn, want, minf(1.0, delta * 10.0))
			if hp < 0.99:
				soldier_bars.append([s.p + Vector3(0, SOLDIER_KINDS[kind] + 0.1, 0), hp, t.owner])
		var node: MultiMeshInstance3D = soldier_poses["%s %s" % [kind, anim]][int(ph * SOLDIER_FRAMES) % SOLDIER_FRAMES]
		var mm := node.multimesh
		var k := mm.visible_instance_count
		if k >= mm.instance_count:
			soldier_need[node] = maxi(soldier_need.get(node, 0), k + 1)
			continue
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, s.turn), s.p + Vector3(0, y, 0)))
		mm.set_instance_custom_data(k, PLAYER_COLORS[t.owner])
		mm.visible_instance_count = k + 1


const AREA_TINT_COMPAT := 0.42  # other players' area tint on Compatibility (0.2 on Forward+)


func update_visuals(delta: float) -> void:
	time += delta
	update_audio(delta)
	# Keeps the map above the bottom console at every zoom and map size:
	# the shift grows with the camera's distance
	camera.v_offset = CAMERA_V_OFFSET * zoom * view_scale
	update_ability_fx(delta)
	# The night's torches flicker
	for i in torches.size():
		torches[i].light_energy = 2.2 + sin(time * 13.0 + i) * 0.15 + sin(time * 7.3 + i * 2.0) * 0.15
	for g in gate_parts.size():
		if gate_parts[g] == null:
			continue
		# The doors swing open and the portal fades in while a player uses the gate
		var gp: Dictionary = gate_parts[g]
		var want := 1.0 if players[g] != null else 0.0
		if gp["open"] == want:
			continue
		gp["open"] = move_toward(gp["open"], want, delta * 0.6)
		var o: float = gp["open"]
		var ease_o := o * o * (3.0 - 2.0 * o)
		gp["surface"].visible = o > 0.01
		gp["light"].visible = o > 0.01
		gp["light"].light_energy = 2.0 * ease_o
		var on := o > 0.5
		gp["motes"].visible = on
		gp["mist"].visible = on and graphics_high
		for i in gp["doors"].size():
			gp["doors"][i].rotation.y = (1.0 if i == 0 else -1.0) * deg_to_rad(95.0) * ease_o
		# The cracks, eyes and runes glow bright while it's open
		if gp["lit"] != on:
			gp["lit"] = on
			for gl: Array in gp["glows"]:
				(gl[0] as MeshInstance3D).set_surface_override_material(gl[1], gate_mat(gl[2] if on else gl[2] + "Off", g))
	var turn := minf(1.0, delta * 12.0)
	# Room in the ice MultiMesh for every monster (grows only, so rarely)
	var ice := ice_shards.multimesh
	if ice.instance_count < enemies.size():
		ice.instance_count = enemies.size() + 128
	var frozen := 0
	# The replay's monsters that got past (main.gd's replay_past), while it plays
	var past: Variant = get("replay_past") if get("replay_on") == true else null
	if past != null and (past as Dictionary).is_empty():
		past = null
	show_clouds()
	# Other players don't know which monsters are poisoned: theirs look poisoned
	# while they stand in a cloud their own game shows
	var cloud_look := net_mode == "client" and not cloud_list.is_empty()
	if cloud_look and cloud_cells_dirty:
		fill_cloud_cells()
	start_specials()
	for e in enemies:
		# Splitters, splitlings and healers have their own looks (see special_fx())
		if e.special != "" and e.node.get_meta("sp", "") != e.special:
			special_look(e)
		var mob: Array = e.node.get_meta("mob")
		# Turn toward the way it walks (not on a jump, like a new monster's first move)
		var p := to3d(e.pos)
		var d := p - e.node.position
		var moved := d.x * d.x + d.z * d.z
		if moved > 1e-7 and moved < 1.0:
			e.node.rotation.y = lerp_angle(e.node.rotation.y, atan2(d.x, d.z), turn)
		e.node.position = p
		# The walk pose for this moment; bob puts each monster at its own point in the
		# step. Frozen monsters stop mid-step.
		if e.freeze_time <= 0.0:
			var poses: Array = mob[0]
			var mesh: Mesh = poses[int((time / mob[2] + e.bob) * poses.size()) % poses.size()]
			if e.node.mesh != mesh:
				e.node.mesh = mesh
		# Slowed monsters use their look's icy material, frozen ones the frozen one
		# and ice around their feet (shrinking as they thaw)
		var m: Material = mob[1][0]
		if e.freeze_time > 0.0:
			m = mob[1][2]
			if frozen < ice.instance_count:
				var s := e.radius / 10.0 * clampf(e.freeze_time / 0.25, 0.0, 1.0)
				ice.set_instance_transform(frozen, Transform3D(Basis(Vector3.UP, e.bob * TAU).scaled(Vector3(s, s, s)), p))
				frozen += 1
		elif e.poisoned > 0.0 or (cloud_look and in_cloud(e.pos)):
			# Poisoned: sickly green (and icy green when also slowed)
			m = mob[1][5] if e.slow_time > 0.0 else mob[1][4]
		elif e.slow_time > 0.0:
			m = mob[1][1]
		# The replay: monsters that got past glow red
		if past != null and past.has(e):
			m = mob[1][3]
		if e.node.material_override != m:
			e.node.material_override = m
		if e.special != "" or e.max_shield > 0.0:
			special_fx(e, p, mob[3] * e.node.scale.y)
	ice.visible_instance_count = frozen
	end_specials(delta)
	update_corpses(delta)
	update_crescendo(delta)
	update_festival_looks()
	start_soldiers()
	for t: Tower in towers.values():
		if t.type == "barracks":
			pass  # nothing turns
		elif t.type == "arrow" or KIT_FILES.has(t.type):
			t.head.rotation.y = atan2(-t.aim.x, -t.aim.y)
		else:
			t.head.rotation.y += delta * 2.0
	for s in shots:
		var y := 0.6
		if s.node.has_meta("lob_y"):
			# An arc, higher for longer throws, the glob wobbling as it flies
			var dist: float = s.node.get_meta("from_dist")
			var k := 1.0 - clampf(s.pos.distance_to(s.target_pos) / dist, 0.0, 1.0)
			y = lerpf(s.node.get_meta("lob_y"), 0.2, k) + sin(k * PI) * (0.2 + dist / CELL * 0.12)
			var w := sin(time * 22.0 + s.node.get_instance_id() % 97) * 0.14
			s.node.scale = Vector3(1.0 + w, 1.0 - w, 1.0 + w)
		elif s.node.has_meta("from_y"):
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
			elif build_type == "barracks" and not barracks_fits(c):
				ghost_mat.albedo_color = Color(1, 0.2, 0.2, 0.4)  # no path in reach
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
	e.node.set_meta("look", look)
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

const SPLIT_TINT := Color(0.8, 0.6, 1.0)  # splitters and splitlings: purple bones...
const SPLIT_GLOW := Color(0.5, 0.15, 0.9)  # ...glowing faintly
const SPLIT_HEAD := Vector3(0.3, -0.14, -0.03)  # where the splitter's second skull sits, from the first (model units)

# Look -> [walk poses (one shared mesh each), its materials (see mob_mats()),
# seconds per step, height, death poses (empty: the monster just vanishes)].
# The specials' looks are "<look> split", "<look> splitling" and "<look> heal".
var mobs := {}
var mob_base := {}  # look -> its material before painting (the specials' looks start from it)
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
	# The specials (waves from 31 are skeleton warriors, see special_look()):
	# splitters purple with a second skull, splitlings purple, healers golden
	for look: String in ["minion", "warrior"]:
		var h := BONE_WARRIOR_HEIGHT * (1.1 if look == "warrior" else 1.0)
		var tint: Color = mob_base[look].albedo_color
		add_glb_monster(look + " split", BONE_WARRIOR, h * 1.06, tint * SPLIT_TINT, SPLIT_GLOW, mobs[look][4])
		add_mob_variant(look, "splitling", SPLIT_TINT, SPLIT_GLOW)
		add_mob_variant(look, "heal", Color(1.0, 0.9, 0.6), Color(1.0, 0.72, 0.25))
	add_skeleton("mage", "Skeleton_Mage", "Walking_C", SKELETON_SIZE * 1.8,
			[["Skeleton_Staff", "handslot.r"]], Color(1.0, 0.75, 0.75))
	mob_shapes()
	add_creature("unicorn", unicorn_pose, 0.7)
	add_creature("spider", spider_pose, 0.35)
	# Grimwhistle (the boss with special "conductor", see special_look()) and his Crescendo pose
	add_grim("mage conductor", false)
	add_grim("mage conductor cast", true)


# The shapes the code-built monsters and decorations are made of, made once
func mob_shapes() -> void:
	if mob_ball != null:
		return
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


# The painted materials of a look: normal, icy for slowed monsters, frozen solid
# (whiter, with a cold glow) for Deep Freeze, glowing red for the replay's
# monsters that got past, sickly green for poisoned ones, and poisoned and slowed
func mob_mats(base: StandardMaterial3D) -> Array:
	var icy := base.duplicate() as StandardMaterial3D
	icy.albedo_color = base.albedo_color * Color(0.6, 0.85, 1.3)
	var frozen := base.duplicate() as StandardMaterial3D
	frozen.albedo_color = base.albedo_color * Color(0.8, 1.0, 1.45)
	frozen.emission_enabled = true
	frozen.emission = Color(0.35, 0.65, 1.0)
	frozen.emission_energy_multiplier = 0.45
	var past := base.duplicate() as StandardMaterial3D
	past.albedo_color = base.albedo_color * Color(1.4, 0.45, 0.4)
	past.emission_enabled = true
	past.emission = Color(1.0, 0.15, 0.08)
	past.emission_energy_multiplier = 0.6
	var sick := base.duplicate() as StandardMaterial3D
	sick.albedo_color = base.albedo_color * Color(0.8, 1.0, 0.66)
	sick.emission_enabled = true
	sick.emission = Color(0.3, 0.85, 0.08)
	sick.emission_energy_multiplier = 0.22
	var sick_icy := sick.duplicate() as StandardMaterial3D
	sick_icy.albedo_color = base.albedo_color * Color(0.55, 0.95, 0.85)
	return [painted(base), painted(icy), painted(frozen), painted(past), painted(sick), painted(sick_icy)]


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
# glow: a faint glow in that color (black: none). falls: another look's death
# poses to share; then this look is a splitter, with a second skull.
func add_glb_monster(look: String, file: String, height: float, tint: Color, glow := Color.BLACK, falls := []) -> void:
	var root: Node3D = load(file).instantiate()
	add_child(root)
	var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var walk := player.get_animation("Walk")
	var death := player.get_animation("Death")
	player.play("Walk")
	# Pose 0 unscaled first, to fit the height and put the feet on the ground
	var probe := glb_pose(root, player, 0.0, Transform3D.IDENTITY, false, false)
	var box := AABB(probe.v[0], Vector3.ZERO)
	for v: Vector3 in probe.v:
		box = box.expand(v)
	var s := height / box.size.y
	var top := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(0, -box.position.y * s, 0))
	var two_heads := not falls.is_empty()
	var poses := []
	for f in 16:
		poses.append(pose_mesh(glb_pose(root, player, walk.length * f / 16.0, top, two_heads)))
	if falls.is_empty():
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
	m.vertex_color_use_as_albedo = festival == "lantern"  # the pumpkin hats' colors
	glow_mat(m, glow)
	mob_base[look] = m
	mobs[look] = [poses, mob_mats(m), walk.length, poses[0].get_aabb().end.y, falls]


# A faint glow in color glow (black: none)
func glow_mat(m: StandardMaterial3D, glow: Color) -> void:
	if glow != Color.BLACK:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 0.22


# Another look of a monster: the same poses with its own tint and glow
func add_mob_variant(look: String, special: String, tint: Color, glow: Color) -> void:
	var m := mob_base[look].duplicate() as StandardMaterial3D
	m.albedo_color = m.albedo_color * tint
	glow_mat(m, glow)
	var from: Array = mobs[look]
	mobs[look + " " + special] = [from[0], mob_mats(m), from[2], from[3], from[4]]


# Every mesh of the model at time t of the playing animation, in one set of parts.
# two_heads: a second, smaller skull grows out of the left shoulder (splitters).
# hat: in Lantern Night, a pumpkin on the skull (not while measuring the height).
func glb_pose(root: Node3D, player: AnimationPlayer, t: float, top: Transform3D, two_heads := false, hat := true) -> Dictionary:
	player.seek(t, true)
	var parts := new_parts()
	var back := root.global_transform.affine_inverse()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			add_part(parts, mi.mesh, top * back * mi.global_transform)
			if two_heads and mi.name == "Skull":
				var lean := Transform3D(Basis(Vector3.UP, 0.6) * Basis(Vector3.BACK, -0.35) * Basis.from_scale(Vector3.ONE * 0.78), Vector3.ZERO)
				add_part(parts, mi.mesh, top * Transform3D(Basis(), SPLIT_HEAD) * back * mi.global_transform * lean)
			if hat and festival == "lantern" and mi.name == "Skull":
				pumpkin_hat(parts, top * back * mi.global_transform)
	return parts


# A killed monster falls apart where it stood (its look's death poses), sinks
# into the ground and is gone after about a second. Only for looks: the
# monster is already out of the game. Looks without a death just vanish.
const CORPSE_FALL := 0.9  # seconds of the fall
const CORPSE_SINK := 0.5  # then seconds of sinking
var corpses: Array[MeshInstance3D] = []


func drop_corpse(e: Enemy) -> void:
	sound_death(e)
	paint_splash(e)
	var falls: Array = e.node.get_meta("mob")[4]
	if falls.is_empty():
		e.node.queue_free()
		return
	e.node.set_meta("dead_time", 0.0)
	e.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	corpses.append(e.node)
	if e.special == "conductor":
		# Grimwhistle: a purple blast as he falls, his bones crumble when he lands
		grim_burst(0, e.node.position + Vector3(0, 0.9, 0))
		e.node.set_meta("crumble", true)


func update_corpses(delta: float) -> void:
	for i in range(corpses.size() - 1, -1, -1):
		var node := corpses[i]
		var t: float = node.get_meta("dead_time") + delta
		node.set_meta("dead_time", t)
		var falls: Array = node.get_meta("mob")[4]
		node.mesh = falls[mini(int(t / CORPSE_FALL * falls.size()), falls.size() - 1)]
		if t > CORPSE_FALL * 0.7 and node.has_meta("crumble"):
			node.remove_meta("crumble")
			grim_burst(1, node.position + Vector3(0, 0.25, 0))
		if t > CORPSE_FALL:
			node.position.y = -0.3 * (t - CORPSE_FALL) / CORPSE_SINK
		if t > CORPSE_FALL + CORPSE_SINK:
			node.queue_free()
			corpses.remove_at(i)


# The corpses go with the monsters when the game is cleared, and so do the
# abilities' effects
func clear_world() -> void:
	for node in corpses:
		node.queue_free()
	corpses.clear()
	for r: Dictionary in meteor_rigs:
		end_meteor(r)
	if not freeze_rig.is_empty():
		freeze_rig["t"] = -1.0
		freeze_rig["plane"].visible = false
	freeze_flash = 0.0
	shake = 0.0
	# The clouds go with the effects
	cloud_list.clear()
	if cloud_ground != null:
		cloud_ground.multimesh.visible_instance_count = 0
		cloud_puffs.multimesh.visible_instance_count = 0
	cloud_cells_dirty = true
	bubble_breaks.clear()
	soldier_vis.clear()
	soldier_bars.clear()
	for list: Array in soldier_poses.values():
		for node: MultiMeshInstance3D in list:
			node.multimesh.visible_instance_count = 0
	# Grimwhistle's Crescendos and the paint splats go too
	cresc.clear()
	hasted.clear()
	splat_next = 0
	if splat_mm != null:
		splat_mm.multimesh.visible_instance_count = 0
	super()


# Adds a skinned mesh in the skeleton's current pose (the skinning is done here, once)
# gp: the bones' poses from bone_globals() (empty: the skeleton's own).
func add_skinned(parts: Dictionary, mi: MeshInstance3D, skel: Skeleton3D, top: Transform3D, gp: Array[Transform3D] = []) -> void:
	var skin := mi.skin
	var bind := []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		bind.append((skel.get_bone_global_pose(bone) if gp.is_empty() else gp[bone]) * skin.get_bind_pose(b))
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
		if t.type == "poison":
			# A glob of glowing green brew
			ball.radius = 0.09
			shot_mats[t.type] = mat(Color(0.5, 1.0, 0.22), 1.2 if compat else 2.4)
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
	# Poison globs are lobbed up out of the cauldron and splash down on the monster
	elif t.type == "poison":
		s.node.set_meta("lob_y", t.head.global_position.y + 0.22)
		s.node.set_meta("from_dist", maxf(s.pos.distance_to(target.pos), 1.0))
	shots.append(s)
	sound_shot(t.type, s.pos)


func add_bolt(points: PackedVector3Array) -> void:
	effects.append({"kind": "bolt", "points": points, "time": 0.15, "max": 0.15})
	sound_bolt(points)


func add_boom(pos: Vector2, r: float) -> void:
	play_sound("cannon_boom", pos)
	var m := mat(Color(1.0, 0.55, 0.15), 1.5, 0.5)
	var node := add_mesh(self, boom_mesh, m, to3d(pos, 0.2))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3.ZERO
	effects.append({"kind": "boom", "node": node, "mat": m, "radius": r, "time": 0.3, "max": 0.3})
	# and a burst of sparks and fire
	fire_burst(boom_pool[boom_next % boom_pool.size()], to3d(pos, 0.2), Color(2.4, 1.2, 0.4))
	boom_next += 1


# ---------------------------------------------------------------- abilities

# Meteor: a burning rock falls (the damage is already done when it's used, so the
# fall is short), bursts in fire and rocks with a shock wave, and leaves burnt
# ground with glowing cracks. Freeze all: a frost wave sweeps over the map with ice
# sparkles, the screen's edge frosts over (game_ui.gd) and frozen monsters stand
# in ice (see update_visuals()). Everything is made once at the start and reused.
const METEOR_FALL := 0.15  # seconds from the sky to the ground
const METEOR_FROM := Vector3(-3.2, 6.5, 1.2)  # where it falls from, seen from where it hits (from the upper left on screen)
const SCORCH_TIME := 9.0  # seconds the burnt ground stays
const FREEZE_WAVE := 1.1  # seconds of the frost wave over the map
const FREEZE_EDGE := 1.4  # seconds of the frosty screen edge
var meteor_rigs: Array[Dictionary] = []  # per player slot: their Meteor's nodes
var freeze_rig := {}
var ice_shards: MultiMeshInstance3D  # ice at frozen monsters' feet, one draw call for all
var shake := 0.0  # seconds of camera shake left
var freeze_flash := 0.0  # seconds of the frosty screen edge left


func make_ability_fx() -> void:
	var glow_shader: Shader = load("res://assets/shaders/ability_glow.gdshader")
	var scorch_shader: Shader = load("res://assets/shaders/scorch.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)  # scaled by the radius
	# Shared by every Meteor: the rock, its halo and the hot debris
	var rock := SphereMesh.new()
	rock.radius = 0.3
	rock.height = 0.55
	rock.radial_segments = 7
	rock.rings = 4
	var rock_mat := mat(Color(0.3, 0.14, 0.07), 2.0)
	rock_mat.emission = Color(1.0, 0.38, 0.08)
	var halo := QuadMesh.new()
	halo.size = Vector2(1.5, 1.5)
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.albedo_texture = soft_dot()
	halo_mat.albedo_color = Color(1.0, 0.5, 0.15)
	halo.material = halo_mat
	var dome := SphereMesh.new()
	dome.radius = 1.0
	dome.height = 2.0
	dome.radial_segments = 24
	dome.rings = 8
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.09, 0.07, 0.08)
	chunk.material = mat(Color(0.22, 0.12, 0.07), 1.2)
	(chunk.material as StandardMaterial3D).emission = Color(1.0, 0.35, 0.05)
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.albedo_texture = soft_dot()
	for slot in MAX_PLAYERS:
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		var r := {"root": root, "t": -1.0, "hit": false, "at": Vector3.ZERO}
		r["rock"] = add_mesh(root, rock, rock_mat)
		add_mesh(r["rock"], halo, null)
		r["warn"] = ground_fx(root, plane, glow_shader)
		r["shock"] = ground_fx(root, plane, glow_shader)
		r["scorch"] = ground_fx(root, plane, scorch_shader)
		r["dome"] = add_mesh(root, dome, mat(Color(1.0, 0.42, 0.1), 0.0, 0.35))
		r["dome"].material_override.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		r["dome"].material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r["dome"].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The fire trail stays where it was made (not local), so it streaks behind the rock
		var pm := fire_process(0.15, 0.3, 1.0)
		pm.gravity = Vector3(0, 1.5, 0)
		r["trail"] = particles(root, 70, 0.32, 0.4, pm)
		r["trail"].emitting = false
		r["trail"].fixed_fps = 0
		r["trail"].local_coords = false
		r["trail"].visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 14, 12))
		pm = fire_process(0.45, 2.5, 8.0)
		pm.spread = 80.0
		pm.gravity = Vector3(0, -3, 0)
		pm.damping_min = 3.0
		pm.damping_max = 6.0
		r["burst"] = one_shot(particles(root, 120, 0.9, 0.26, pm))
		# Hot rocks thrown out
		pm = ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 55.0
		pm.initial_velocity_min = 3.5
		pm.initial_velocity_max = 7.0
		pm.gravity = Vector3(0, -20, 0)
		pm.scale_min = 0.6
		pm.scale_max = 1.6
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.3
		var debris := GPUParticles3D.new()
		debris.amount = 18
		debris.lifetime = 0.75
		debris.process_material = pm
		debris.draw_pass_1 = chunk
		root.add_child(debris)
		r["debris"] = one_shot(debris)
		# Smoke rising after the blast (High only)
		pm = ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.8
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 25.0
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.0
		pm.gravity = Vector3(0.15, 0.2, 0)
		pm.damping_min = 0.3
		pm.damping_max = 0.6
		pm.scale_min = 0.7
		pm.scale_max = 1.6
		pm.color = Color(0.16, 0.13, 0.11, 0.55)
		pm.color_ramp = fade_ramp()
		r["smoke"] = particles(root, 22, 2.4, 0.9, pm)
		r["smoke"].draw_pass_1.material = smoke_mat
		r["smoke"].one_shot = true
		r["smoke"].explosiveness = 0.7
		r["smoke"].emitting = false
		r["smoke"].visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.omni_range = 6.0
		light.visible = false
		root.add_child(light)
		r["light"] = light
		meteor_rigs.append(r)

	# Freeze all: one frost plane over the map and ice sparkles
	var froot := Node3D.new()
	add_child(froot)
	var fplane := PlaneMesh.new()
	fplane.size = Vector2(1, 1)  # scaled to the map
	# Compatibility adds light in sRGB, which turns ice on grass green: there the
	# frost is laid over the ground instead of added to it
	var frost_shader := glow_shader
	if compat:
		frost_shader = Shader.new()
		frost_shader.code = glow_shader.code.replace("blend_add", "blend_mix")
	freeze_rig = {"t": -1.0, "plane": ground_fx(froot, fplane, frost_shader)}
	freeze_rig["plane"].visible = false
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.direction = Vector3(0, 1, 0)
	spm.spread = 30.0
	spm.initial_velocity_min = 0.2
	spm.initial_velocity_max = 1.0
	spm.gravity = Vector3.ZERO
	spm.color = Color(1.4, 2.0, 2.8)
	spm.color_ramp = fade_ramp()
	spm.scale_min = 0.5
	spm.scale_max = 1.5
	freeze_rig["sparkles"] = one_shot(particles(froot, 300, 1.4, 0.07, spm))
	freeze_rig["sparkles"].explosiveness = 0.5

	# Ice shards around a frozen monster's feet, leaning out
	var parts := Node3D.new()
	for i in 7:
		var a := i * TAU / 7.0
		var out := Vector3(cos(a), 0, sin(a))
		var h := 0.2 + 0.09 * ((i * 5) % 3)
		var foot := out * (0.1 + 0.03 * (i % 3)) - Vector3(0, 0.05, 0)
		part_beam(parts, foot, foot + out * h * 0.5 + Vector3(0, h, 0), 0.05 + 0.012 * (i % 2), 0.0, Color.WHITE, 5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = merge_parts(parts)
	mm.instance_count = 256
	mm.visible_instance_count = 0
	ice_shards = MultiMeshInstance3D.new()
	ice_shards.multimesh = mm
	var ice := mat(Color(0.7, 0.9, 1.0), 0.0, 0.72)
	ice.emission_enabled = true
	ice.emission = Color(0.3, 0.6, 1.0)
	ice.emission_energy_multiplier = 0.9
	ice.roughness = 0.1
	ice.rim_enabled = true
	ice.rim = 0.6
	ice_shards.material_override = ice
	ice_shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ice_shards)


# A flat effect on the ground with its own copy of the shader's settings
func ground_fx(parent: Node3D, plane: Mesh, shader: Shader) -> MeshInstance3D:
	var m := ShaderMaterial.new()
	m.shader = shader
	var node := add_mesh(parent, plane, m)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	return node


# Fire: hot yellow, then orange, red and gone
func fire_process(spread_r: float, v_min: float, v_max: float) -> ParticleProcessMaterial:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	g.set_color(1, Color(0.35, 0.06, 0.02, 0.0))
	g.add_point(0.25, Color(1.0, 0.6, 0.2, 1.0))
	g.add_point(0.6, Color(0.85, 0.25, 0.06, 0.7))
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = spread_r
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	pm.color = Color(1.5, 1.5, 1.5)
	pm.color_ramp = ramp
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.3))
	var shrink := CurveTexture.new()
	shrink.curve = curve
	pm.scale_curve = shrink
	return pm


func one_shot(p: GPUParticles3D) -> GPUParticles3D:
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-5, -2, -5), Vector3(10, 8, 10))
	return p


# Every computer: the look of an ability being used (see ABILITIES)
func show_ability(slot: int, ability: String, at: Vector2) -> void:
	play_sound(ability, at)
	if ability == "meteor":
		start_meteor(meteor_rigs[clampi(slot, 0, meteor_rigs.size() - 1)], to3d(at))
	elif ability == "freeze":
		start_freeze()


func start_meteor(r: Dictionary, at: Vector3) -> void:
	var high := graphics_high
	r["t"] = 0.0
	r["hit"] = false
	r["at"] = at
	r["root"].visible = true
	r["rock"].visible = true
	r["rock"].position = at + METEOR_FROM
	r["trail"].amount = 110 if high else 56
	r["trail"].position = r["rock"].position
	r["trail"].emitting = true
	var size: float = ABILITIES["meteor"]["radius"] / CELL
	for k: String in ["warn", "shock", "scorch"]:
		var n: MeshInstance3D = r[k]
		n.position = at + Vector3(0, 0.03 + (0.01 if k != "scorch" else 0.0), 0)
		n.scale = Vector3(size, 1, size) * (1.25 if k == "scorch" else 1.0)
		n.visible = k == "warn"
	var warn: ShaderMaterial = r["warn"].material_override
	warn.set_shader_parameter("tint", Color(1.0, 0.42, 0.12))
	warn.set_shader_parameter("ring", 0.96)
	warn.set_shader_parameter("width", 0.03)
	warn.set_shader_parameter("fill", 0.14)
	warn.set_shader_parameter("energy", 1.2)
	var shock: ShaderMaterial = r["shock"].material_override
	shock.set_shader_parameter("tint", Color(1.0, 0.62, 0.3))
	shock.set_shader_parameter("energy", 1.6)
	shock.set_shader_parameter("fill", 0.12)
	r["scorch"].material_override.set_shader_parameter("seed", randf() * 10.0)
	r["dome"].visible = false
	r["burst"].amount = 120 if high else 60
	r["smoke"].visible = high
	r["light"].visible = false


func end_meteor(r: Dictionary) -> void:
	r["t"] = -1.0
	r["root"].visible = false
	r["trail"].emitting = false
	r["light"].visible = false


func update_meteor(r: Dictionary, delta: float) -> void:
	var t: float = r["t"] + delta
	r["t"] = t
	var at: Vector3 = r["at"]
	var size: float = ABILITIES["meteor"]["radius"] / CELL
	var warn: ShaderMaterial = r["warn"].material_override
	if t < METEOR_FALL:
		# Falling faster and faster, tumbling, the aim ring glowing up under it
		var fell := t / METEOR_FALL
		var rock: MeshInstance3D = r["rock"]
		rock.position = at + METEOR_FROM * (1.0 - fell * fell) + Vector3(0, 0.25, 0) * fell
		rock.rotate(Vector3(1, 0, 1).normalized(), delta * 9.0)
		r["trail"].position = rock.position
		warn.set_shader_parameter("alpha", 0.35 + 0.65 * fell)
		return
	var u := t - METEOR_FALL  # since it hit
	if not r["hit"]:
		r["hit"] = true
		r["rock"].visible = false
		r["trail"].emitting = false
		for part: String in ["burst", "debris", "smoke"]:
			var p: GPUParticles3D = r[part]
			p.position = at + Vector3(0, 0.15, 0)
			p.restart()
		r["shock"].visible = true
		r["scorch"].visible = true
		r["dome"].visible = true
		r["dome"].position = at
		r["light"].visible = graphics_high and not compat
		r["light"].position = at + Vector3(0, 1.2, 0)
		shake = maxf(shake, 0.4)
	warn.set_shader_parameter("alpha", clampf(1.0 - u / 0.15, 0.0, 1.0))
	r["warn"].visible = u < 0.15
	# Shock wave running out to the edge of the hit area
	var k := clampf(u / 0.45, 0.0, 1.0)
	var shock: ShaderMaterial = r["shock"].material_override
	shock.set_shader_parameter("ring", lerpf(0.1, 1.05, 1.0 - pow(1.0 - k, 3.0)))
	shock.set_shader_parameter("width", lerpf(0.12, 0.04, k))
	shock.set_shader_parameter("alpha", 1.0 - k)
	r["shock"].visible = k < 1.0
	# A ball of fire swelling and fading
	k = clampf(u / 0.4, 0.0, 1.0)
	var s := size * lerpf(0.3, 0.95, 1.0 - pow(1.0 - k, 2.0))
	r["dome"].scale = Vector3(s, s * 0.55, s)
	r["dome"].material_override.albedo_color = Color(1.0, 0.42, 0.1, 0.35 * (1.0 - k))
	r["dome"].visible = k < 1.0
	r["light"].light_energy = 3.5 * clampf(1.0 - u / 0.45, 0.0, 1.0)
	if u > 0.45:
		r["light"].visible = false
	# Burnt ground: the cracks cool down, then it fades
	var scorch: ShaderMaterial = r["scorch"].material_override
	scorch.set_shader_parameter("embers", clampf(1.0 - u / 3.0, 0.0, 1.0))
	scorch.set_shader_parameter("alpha", clampf(u / 0.08, 0.0, 1.0) * clampf((SCORCH_TIME - u) / 3.0, 0.0, 1.0))
	if u > SCORCH_TIME:
		end_meteor(r)


func start_freeze() -> void:
	var f := freeze_rig
	f["t"] = 0.0
	var w := map_cols + 2.0
	var h := map_rows + 2.0
	var plane: MeshInstance3D = f["plane"]
	plane.visible = true
	plane.position = Vector3(map_cols / 2.0, 0.05, map_rows / 2.0)
	plane.scale = Vector3(w, 1, h)
	var m: ShaderMaterial = plane.material_override
	m.set_shader_parameter("tint", Color(0.72, 0.88, 1.0) if compat else Color(0.55, 0.8, 1.0))
	m.set_shader_parameter("aspect", Vector2(w, h) / maxf(w, h))
	m.set_shader_parameter("tiles", maxf(w, h) * 0.45)
	m.set_shader_parameter("energy", 1.0 if compat else 0.55)
	var sp: GPUParticles3D = f["sparkles"]
	var pm := sp.process_material as ParticleProcessMaterial
	pm.emission_box_extents = Vector3(map_cols / 2.0, 0.4, map_rows / 2.0)
	sp.amount = 300 if graphics_high else 110
	sp.position = Vector3(map_cols / 2.0, 0.3, map_rows / 2.0)
	sp.visibility_aabb = AABB(-pm.emission_box_extents - Vector3(1, 1, 1), pm.emission_box_extents * 2.0 + Vector3(2, 4, 2))
	sp.restart()
	freeze_flash = FREEZE_EDGE


func update_freeze(delta: float) -> void:
	var f := freeze_rig
	var t: float = f["t"] + delta
	f["t"] = t
	var m: ShaderMaterial = f["plane"].material_override
	# The wave runs from the middle past the corners; frost stays behind it, fading
	var k := clampf(t / FREEZE_WAVE, 0.0, 1.0)
	m.set_shader_parameter("ring", 1.5 * minf(t / (FREEZE_WAVE * 0.55), 1.0))
	m.set_shader_parameter("width", 0.05)
	m.set_shader_parameter("fill", 0.1)
	m.set_shader_parameter("frost", 0.7)
	m.set_shader_parameter("alpha", 1.0 - k * k)
	if t >= FREEZE_WAVE:
		f["t"] = -1.0
		f["plane"].visible = false


func update_ability_fx(delta: float) -> void:
	for r in meteor_rigs:
		if r["t"] >= 0.0:
			update_meteor(r, delta)
	if not freeze_rig.is_empty() and freeze_rig["t"] >= 0.0:
		update_freeze(delta)
	freeze_flash = maxf(freeze_flash - delta, 0.0)
	# A short shake when a Meteor hits
	if shake > 0.0:
		shake = maxf(shake - delta, 0.0)
		camera.v_offset += sin(time * 75.0) * 0.18 * shake * zoom * view_scale


# ---------------------------------------------------------------- poison clouds

# Every computer: a poison cloud where a glob landed (see main.gd), radius r
# (map pixels), gone after seconds. A swirling green haze on the ground with
# puffs drifting over it (High only): Venom's brighter, Miasma's murkier and
# thicker. All clouds are two MultiMeshes (one draw each, however many there
# are), and each cloud fades in and out on the graphics card from when it was
# made (see cloud.gdshader), so nothing is updated per cloud each frame. The
# clouds keep their own clock, which follows the effects' time (so they pause
# with the replay).
const CLOUD_PUFFS := 5  # puffs per cloud
const CLOUD_REBASE := 100.0  # seconds before the clock starts again from 0 (keeps the times precise)
var cloud_ground: MultiMeshInstance3D
var cloud_puffs: MultiMeshInstance3D
var cloud_list: Array[Dictionary] = []  # the clouds shown, in MultiMesh order
var cloud_clock := 0.0
var cloud_cells := PackedByteArray()  # other players: 1 for the tiles in a cloud (see in_cloud())
var cloud_cells_dirty := true
var fx_noise: ImageTexture  # soft tiling noise for the clouds and shields


func make_cloud_fx() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.03
	n.fractal_octaves = 3
	var img := n.get_seamless_image(128, 128)
	img.generate_mipmaps()
	fx_noise = ImageTexture.create_from_image(img)
	var shader: Shader = load("res://assets/shaders/cloud.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)  # scaled by the radius
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var ground := ShaderMaterial.new()
	ground.shader = shader
	ground.set_shader_parameter("noise", fx_noise)
	# Compatibility blends brighter: a thinner haze there
	ground.set_shader_parameter("strength", 0.8 if compat else 1.0)
	var puffs := ground.duplicate() as ShaderMaterial
	puffs.set_shader_parameter("puffs", true)
	cloud_ground = fx_multimesh(plane, ground, 64)
	cloud_puffs = fx_multimesh(quad, puffs, 64 * CLOUD_PUFFS)
	cloud_puffs.visible = graphics_high


# A MultiMesh of mesh for effects, with custom data per instance, none shown yet
func fx_multimesh(mesh: Mesh, material: Material, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


# The whole board, so effects MultiMeshes never need their size worked out
func fx_box(mm: MultiMesh) -> void:
	var box := AABB(Vector3(-4, -1, -4), Vector3(map_cols + 8, 8, map_rows + 8))
	if mm.custom_aabb != box:
		mm.custom_aabb = box


func show_cloud(pos: Vector2, r: float, seconds: float, path: int) -> void:
	# In the effects list for its time (main.gd counts it down); no node to free
	var fx := {"kind": "cloud", "time": seconds, "max": seconds, "pos": pos, "r": r, "path": path,
			"born": cloud_clock, "seed": randf()}
	effects.append(fx)
	var i := cloud_list.size()
	cloud_list.append(fx)
	var gm := cloud_ground.multimesh
	var pm := cloud_puffs.multimesh
	if gm.instance_count <= i:
		# More room: that clears them, so all are written again
		gm.instance_count = i * 2
		pm.instance_count = i * 2 * CLOUD_PUFFS
		for k in i:
			write_cloud(k)
	fx_box(gm)
	fx_box(pm)
	write_cloud(i)
	gm.visible_instance_count = cloud_list.size()
	pm.visible_instance_count = cloud_list.size() * CLOUD_PUFFS
	cloud_cells_dirty = true


# Puts cloud i of cloud_list into the MultiMeshes
func write_cloud(i: int) -> void:
	var fx: Dictionary = cloud_list[i]
	var r: float = fx["r"] / CELL
	var seed: float = fx["seed"]
	var path: int = fx["path"]
	var at := to3d(fx["pos"], 0.04 + 0.003 * (i % 8))
	var gm := cloud_ground.multimesh
	gm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, seed * TAU).scaled(Vector3(r * 1.2, 1.0, r * 1.2)), at))
	gm.set_instance_custom_data(i, Color(fx["born"], fx["max"], seed, path))
	var pm := cloud_puffs.multimesh
	var big := 1.2 if path == 2 else 1.0
	for j in CLOUD_PUFFS:
		var h := fposmod(seed * 7.31 + j * 0.618, 1.0)
		var a := seed * TAU + j * TAU / CLOUD_PUFFS + h
		var off := Vector3(cos(a), 0.0, sin(a)) * r * (0.1 + 0.4 * h)
		var size := r * (0.5 + 0.3 * h) * big
		pm.set_instance_transform(i * CLOUD_PUFFS + j, Transform3D(Basis.from_scale(Vector3.ONE * size), at + off + Vector3(0, 0.08, 0)))
		pm.set_instance_custom_data(i * CLOUD_PUFFS + j, Color(fx["born"], fx["max"], fposmod(seed + j * 0.37, 1.0), path))


# Takes cloud i out: the last one moves into its place
func remove_cloud(i: int) -> void:
	var last := cloud_list.size() - 1
	cloud_list[i] = cloud_list[last]
	cloud_list.pop_back()
	if i < last:
		write_cloud(i)
	cloud_ground.multimesh.visible_instance_count = cloud_list.size()
	cloud_puffs.multimesh.visible_instance_count = cloud_list.size() * CLOUD_PUFFS
	cloud_cells_dirty = true


func show_clouds() -> void:
	if cloud_list.is_empty():
		cloud_clock = 0.0
		return
	var first: Dictionary = cloud_list[0]
	cloud_clock = first["born"] + first["max"] - first["time"]
	for i in range(cloud_list.size() - 1, -1, -1):
		if cloud_list[i]["time"] <= 0.0:
			remove_cloud(i)
	# Now and then the clock starts again from 0, and every cloud is written again
	if cloud_clock > CLOUD_REBASE:
		for fx in cloud_list:
			fx["born"] -= cloud_clock
		cloud_clock = 0.0
		for i in cloud_list.size():
			write_cloud(i)
	(cloud_ground.material_override as ShaderMaterial).set_shader_parameter("now", cloud_clock)
	(cloud_puffs.material_override as ShaderMaterial).set_shader_parameter("now", cloud_clock)


# Other players: marks the tiles whose middle is in a cloud
func fill_cloud_cells() -> void:
	cloud_cells_dirty = false
	cloud_cells.resize(map_cols * map_rows)
	cloud_cells.fill(0)
	for fx in cloud_list:
		var at: Vector2 = fx["pos"]
		var r: float = fx["r"] + CELL * 0.3
		for y in range(maxi(int((at.y - r) / CELL), 0), mini(int((at.y + r) / CELL), map_rows - 1) + 1):
			for x in range(maxi(int((at.x - r) / CELL), 0), mini(int((at.x + r) / CELL), map_cols - 1) + 1):
				if cell_center(Vector2i(x, y)).distance_squared_to(at) <= r * r:
					cloud_cells[y * map_cols + x] = 1


func in_cloud(p: Vector2) -> bool:
	var x := int(p.x / CELL)
	var y := int(p.y / CELL)
	if x < 0 or y < 0 or x >= map_cols or y >= map_rows:
		return false
	return cloud_cells[y * map_cols + x] == 1


# ---------------------------------------------------------------- monster specials

# Splitters have purple bones and a second skull, their splitlings are smaller
# and purple (see build_monsters()). Healers are golden with a halo, and send a
# golden ring out to the heal's reach every HEAL_EVERY seconds (timed on each
# computer: just a look). A shield is a glowing bubble while it holds; it cracks
# and bursts when it breaks. The halos, rings and bubbles are three MultiMeshes,
# filled each frame from update_visuals().
const HEAL_PULSE := 0.9  # seconds a healer's ring takes to run out
const BUBBLE_BREAK := 0.35  # seconds a broken shield takes to burst
var halo_mm: MultiMeshInstance3D
var ring_mm: MultiMeshInstance3D
var bubble_mm: MultiMeshInstance3D
var bubble_breaks: Array = []  # broken shields bursting: [Transform3D, seconds since]
var halos := 0  # instances filled this frame
var rings := 0
var bubbles := 0


func make_special_fx() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.07
	torus.outer_radius = 0.095
	torus.rings = 20
	torus.ring_segments = 6
	halo_mm = fx_multimesh(torus, mat(Color(1.0, 0.8, 0.3), 1.2 if compat else 2.6), 32)
	var ring_shader: Shader = load("res://assets/shaders/heal_ring.gdshader")
	var shield_shader: Shader = load("res://assets/shaders/shield.gdshader")
	# Compatibility adds light in sRGB (see make_ability_fx()): there they're laid over instead
	if compat:
		for s: Shader in [ring_shader, shield_shader]:
			var c := Shader.new()
			c.code = s.code.replace("blend_add", "blend_mix")
			if s == ring_shader:
				ring_shader = c
			else:
				shield_shader = c
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)  # scaled by the heal's reach
	var rm := ShaderMaterial.new()
	rm.shader = ring_shader
	ring_mm = fx_multimesh(plane, rm, 32)
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 20
	ball.rings = 10
	var bm := ShaderMaterial.new()
	bm.shader = shield_shader
	bm.set_shader_parameter("noise", fx_noise)
	bm.set_shader_parameter("energy", 0.8 if compat else 1.0)
	bubble_mm = fx_multimesh(ball, bm, 64)


# Before the monsters: room for every monster's halo, ring and bubble
func start_specials() -> void:
	halos = 0
	rings = 0
	bubbles = 0
	var need := enemies.size() + bubble_breaks.size()
	for node: MultiMeshInstance3D in [halo_mm, ring_mm, bubble_mm]:
		var mm := node.multimesh
		if mm.instance_count < need:
			mm.instance_count = need + 64
		fx_box(mm)
	(bubble_mm.material_override as ShaderMaterial).set_shader_parameter("now", time)


# A splitter's, splitling's or healer's look, once its special is known
func special_look(e: Enemy) -> void:
	e.node.set_meta("sp", e.special)
	var key := "%s %s" % [e.node.get_meta("look", ""), e.special]
	if e.special == "conductor":
		key = "mage conductor"  # Grimwhistle, whatever boss he was
	if mobs.has(key):
		e.node.set_meta("mob", mobs[key])
	e.node.scale = Vector3.ONE * (0.75 if e.special == "splitling" else 1.0)


# A special monster's halo, ring and shield at p; h is its height
func special_fx(e: Enemy, p: Vector3, h: float) -> void:
	if e.special == "heal":
		var bob := sin(time * 3.0 + e.bob * TAU) * 0.015
		halo_mm.multimesh.set_instance_transform(halos, Transform3D(Basis(Vector3.RIGHT, 0.25), p + Vector3(0, h + 0.06 + bob, 0)))
		halos += 1
		var t := fposmod(time + e.bob * HEAL_EVERY, HEAL_EVERY)
		if t < HEAL_PULSE:
			var s := HEAL_RANGE / CELL
			ring_mm.multimesh.set_instance_transform(rings, Transform3D(Basis.from_scale(Vector3(s, 1, s)), p + Vector3(0, 0.05 + 0.002 * (rings % 8), 0)))
			ring_mm.multimesh.set_instance_custom_data(rings, Color(t / HEAL_PULSE, 0, 0, 0))
			rings += 1
	if e.max_shield > 0.0:
		var up := e.shield > 0.0
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * h * 1.1), p + Vector3(0, h * 0.5, 0))
		if up and bubbles < bubble_mm.multimesh.instance_count:
			bubble_mm.multimesh.set_instance_transform(bubbles, xf)
			bubble_mm.multimesh.set_instance_custom_data(bubbles, Color(0, e.bob, 0, 0))
			bubbles += 1
		var was: bool = e.node.get_meta("shield", false)
		if was != up:
			e.node.set_meta("shield", up)
			if was:
				# It broke: the bubble cracks and bursts, with a spray of shards
				bubble_breaks.append([xf, 0.0])
				fire_burst(hit_pool[hit_next % hit_pool.size()], xf.origin, Color(1.0, 1.7, 2.6))
				hit_next += 1


# After the monsters: the bursting bubbles, then how many of each to show
func end_specials(delta: float) -> void:
	var mm := bubble_mm.multimesh
	for i in range(bubble_breaks.size() - 1, -1, -1):
		var b: Array = bubble_breaks[i]
		b[1] += delta
		if b[1] >= BUBBLE_BREAK:
			bubble_breaks.remove_at(i)
		elif bubbles < mm.instance_count:
			mm.set_instance_transform(bubbles, b[0])
			mm.set_instance_custom_data(bubbles, Color(maxf(b[1] / BUBBLE_BREAK, 0.01), 0.3, 0, 0))
			bubbles += 1
	halo_mm.multimesh.visible_instance_count = halos
	ring_mm.multimesh.visible_instance_count = rings
	mm.visible_instance_count = bubbles


# ================================================================ holiday festivals
# Looks only: on top of the weather (see apply_mood()), each computer dresses the
# valley for today's festival (festival_today() in game_base.gd, picked when a
# game starts). Frostfall Fair: snow on the trees and rocks, garlands on the
# gates, string lights round the towers, scarves on the soldiers. Lantern Night:
# glowing pumpkins on towers, gates and the board's edge, fireflies, pumpkin hats
# on the bone warriors. Spring Paint Day: bunting, eggs under the trees, painted
# gates, and monsters burst into paint where they fall.
var festival := ""  # "", "frostfall", "lantern" or "paint"
var festival_picked := false
var baked_fest := ""  # the festival the monsters' and soldiers' poses were made with
var fest_root: Node3D  # the festival's decorations (under weather_root, see festival_decor())
var fest_mesh := {}  # shared meshes and materials, made once
var lantern_mm: MultiMeshInstance3D  # Lantern Night: a pumpkin on every tower, gate and the edge
var lights_mm: MultiMeshInstance3D  # Frostfall: string lights round the tower bases
var fest_towers := -1  # tower count the MultiMeshes were filled for
var splat_mm: MultiMeshInstance3D  # Paint Day: paint splats where monsters fell
var splat_next := 0
var paint_pool: Array[GPUParticles3D] = []
var paint_next := 0


# Picks festival f (one of FESTIVALS, or "" for none). Hats and scarves are baked
# into the poses, so those are made again when the festival changes.
func apply_festival(f: String) -> void:
	festival = f if f in FESTIVALS else ""
	RenderingServer.global_shader_parameter_set(&"fest_snow", 1.0 if festival == "frostfall" else 0.0)
	if festival == baked_fest:
		return
	baked_fest = festival
	if not mobs.is_empty():
		mobs.clear()
		mob_base.clear()
		build_monsters()
	if not soldier_poses.is_empty():
		for list: Array in soldier_poses.values():
			for node: MultiMeshInstance3D in list:
				node.free()
		soldier_poses.clear()
		soldier_vis.clear()
		soldier_need.clear()
		load_soldiers()


# The festival's decorations, made again with the weather (see mood_fx())
func festival_decor() -> void:
	fest_root = null
	lantern_mm = null
	lights_mm = null
	splat_mm = null
	fest_towers = -1
	if festival == "" or weather_root == null:
		return
	fest_root = Node3D.new()
	weather_root.add_child(fest_root)
	for g in gate_cells.size():
		if gate_cells[g] != null:
			fest_gate(g)
	match festival:
		"frostfall":
			lights_mm = color_mm(fest_ball(), fest_glow_mat())
		"lantern":
			var lm := lantern_mat()
			lm.set_shader_parameter("glow", 6.0 if mood in ["night", "evening"] else 3.5)
			lantern_mm = color_mm(lantern_mesh(), lm)
			lantern_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_fireflies()
		"paint":
			add_eggs()
			add_border_bunting()
			var q := QuadMesh.new()
			q.size = Vector2(1, 1)
			q.orientation = PlaneMesh.FACE_Y
			splat_mm = color_mm(q, splat_mat())
			splat_mm.multimesh.instance_count = 96
			splat_mm.multimesh.visible_instance_count = 0
			splat_next = 0
			if paint_pool.is_empty():
				for i in 12:
					var p := burst(18, 0.6, 0.06, 2.6)
					var pm := p.process_material as ParticleProcessMaterial
					pm.color_initial_ramp = pastel_ramp()
					paint_pool.append(p)


# Each frame: the tower decorations follow the towers, the splats fade
func update_festival_looks() -> void:
	if fest_root == null:
		return
	if fest_towers != towers.size():
		fest_towers = towers.size()
		fill_fest_towers()
	if splat_mm != null:
		(splat_mm.material_override as ShaderMaterial).set_shader_parameter("now", time)


# Whether p is within r of a gate (on the ground, any height)
func near_gate(p: Vector3, r: float) -> bool:
	for g in gate_cells.size():
		if gate_cells[g] != null:
			var c := to3d(routes[g][0])
			if Vector2(p.x - c.x, p.z - c.z).length() < r:
				return true
	return false


# A MultiMesh with a color (and custom data) per instance, under fest_root
func color_mm(mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fest_root.add_child(node)
	fx_box(mm)
	return node


func pastel(i: int) -> Color:
	return [Color(1.0, 0.6, 0.75), Color(0.6, 0.85, 1.0), Color(0.7, 0.95, 0.6), Color(1.0, 0.9, 0.5), Color(0.8, 0.65, 1.0), Color(1.0, 0.72, 0.5)][posmod(i, 6)]


func pastel_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.17, 0.33, 0.5, 0.67, 0.83])
	var cols := PackedColorArray()
	for i in 6:
		cols.append(pastel(i) * 1.6)
	g.colors = cols
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


# A vertex-colored painted material, shared by the decorations
func fest_vcol() -> Material:
	if not fest_mesh.has("vcol"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.7
		fest_mesh["vcol"] = painted(m)
	return fest_mesh["vcol"]


func fest_ball() -> SphereMesh:
	if not fest_mesh.has("ball"):
		var b := SphereMesh.new()
		b.radius = 0.5
		b.height = 1.0
		b.radial_segments = 8
		b.rings = 4
		fest_mesh["ball"] = b
	return fest_mesh["ball"]


func fest_glow_mat() -> StandardMaterial3D:
	if not fest_mesh.has("glow"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		fest_mesh["glow"] = m
	return fest_mesh["glow"]


# ---------------------------------------------------------------- gates

# Gate g's decorations, one mesh
func fest_gate(g: int) -> void:
	var parts := new_parts()
	mob_shapes()
	match festival:
		"frostfall":
			# Snow on the lintel and the gem's seat
			for p: Array in [[Vector3(0, 1.43, 0), Vector3(1.4, 0.07, 0.4)], [Vector3(-0.4, 1.45, 0.04), Vector3(0.45, 0.08, 0.32)], [Vector3(0.36, 1.45, -0.03), Vector3(0.5, 0.075, 0.34)]]:
				shape(parts, mob_ball, p[0], p[1], Color(0.95, 0.97, 1.0))
			for side: float in [-1.0, 1.0]:
				# A pine garland sagging over each face, with red and gold baubles
				var z := 0.21 * side
				for i in 25:
					var k := i / 24.0
					var x := lerpf(-0.62, 0.62, k)
					var y := 1.27 - sin(k * PI) * 0.13
					shape(parts, mob_ball, Vector3(x, y, z), Vector3(0.09, 0.08, 0.08), Color(0.12, 0.32, 0.14) if i % 2 == 0 else Color(0.18, 0.42, 0.18))
					if i % 4 == 2:
						shape(parts, mob_ball, Vector3(x, y - 0.065, z + 0.02 * side), Vector3.ONE * 0.055, Color(0.85, 0.1, 0.1) if i % 8 == 2 else Color(1.0, 0.78, 0.2))
				# A red bow in the middle
				for s: float in [-1.0, 1.0]:
					shape(parts, mob_ball, Vector3(0.08 * s, 1.31, z + 0.03 * side), Vector3(0.12, 0.08, 0.04), Color(0.8, 0.08, 0.1), Vector3(0, 0, 0.5 * s))
					rod(parts, Vector3(0.02 * s, 1.27, z + 0.03 * side), Vector3(0.06 * s, 1.12, z + 0.03 * side), 0.015, Color(0.8, 0.08, 0.1))
				shape(parts, mob_ball, Vector3(0, 1.3, z + 0.04 * side), Vector3.ONE * 0.05, Color(1.0, 0.8, 0.25))
			# Red and gold ribbon wound round both pillars
			for px: float in [-0.5, 0.5]:
				for i in 7:
					var y := 0.12 + i * 0.16
					for side: float in [-1.0, 1.0]:
						shape(parts, mob_rod, Vector3(px, y, 0.155 * side), Vector3(0.05, 0.25, 0.012), Color(0.82, 0.1, 0.12) if i % 2 == 0 else Color(1.0, 0.8, 0.25), Vector3(PI / 2, 0, 0.9 * side))
		"paint":
			# Pastel bunting over both faces of the lintel
			for side: float in [-1.0, 1.0]:
				var z := 0.215 * side
				var pts := []
				for i in 6:
					var k := i / 5.0
					pts.append(Vector3(lerpf(-0.66, 0.66, k), 1.41 - sin(k * PI) * 0.08, z))
				for i in 5:
					rod(parts, pts[i], pts[i + 1], 0.008, Color(0.95, 0.95, 0.9))
					fest_flag(parts, pts[i].lerp(pts[i + 1], 0.1), pts[i].lerp(pts[i + 1], 0.9), 0.25, pastel(i + g), side)
			# Painted dots climbing the pillars
			for px: float in [-0.5, 0.5]:
				for i in 6:
					var y := 0.15 + i * 0.19
					for side: float in [-1.0, 1.0]:
						shape(parts, mob_ball, Vector3(px + (0.05 if i % 2 else -0.05), y, 0.15 * side), Vector3(0.07, 0.07, 0.02), pastel(i + int(px * 4) + 3))
			# A nest of eggs in front of each pillar's foot
			for px: float in [-0.5, 0.5]:
				for i in 3:
					shape(parts, mob_ball, Vector3(px + (i - 1) * 0.07, 0.05, 0.24 + (i % 2) * 0.06), Vector3(0.07, 0.095, 0.07), pastel(i * 2 + g), Vector3(0.3 * (i - 1), 0, 0.2))
	if parts.v.is_empty():
		return
	var gate := Node3D.new()
	gate.position = to3d(routes[g][0])
	var out_dir: Vector2 = routes[g][1] - routes[g][0]
	gate.rotation.y = atan2(out_dir.x, out_dir.y)
	# Made for the first gate: moved back and sized onto the crypt gate's pillars and lintel
	gate.position -= Vector3(out_dir.x, 0, out_dir.y).normalized() * 0.235
	gate.scale = Vector3(0.95 * GATE_W, 0.78, 1.45)
	fest_root.add_child(gate)
	add_mesh(gate, pose_mesh(parts), fest_vcol())


# A triangle flag hanging from a to b, its tip depth below, facing side
func fest_flag(parts: Dictionary, a: Vector3, b: Vector3, depth: float, col: Color, side: float) -> void:
	var base: int = parts.v.size()
	var tip := (a + b) * 0.5 + Vector3(0, -depth, 0.01 * side)
	for p in [a, b, tip]:
		parts.v.append(p)
		parts.n.append(Vector3(0, 0, side))
		parts.uv.append(Vector2.ZERO)
		parts.c.append(col)
	parts.i.append_array([base, base + 1, base + 2, base, base + 2, base + 1])


# ---------------------------------------------------------------- pumpkins

# A ribbed pumpkin, radius 1, its UVs all on uv (a plain spot of a texture)
func pumpkin_body(uv := Vector2.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	var segs := 24
	var pts := []
	for i in rings + 1:
		var th := PI * i / rings
		var row := []
		for j in segs + 1:
			var ph := TAU * j / segs
			var r := 1.0 - 0.13 * pow(absf(cos(ph * 4.0)), 6.0)
			# A dimple at the top and bottom
			var y := cos(th) * 0.72 - signf(cos(th)) * 0.12 * (1.0 - smoothstep(0.0, 0.5, sin(th)))
			row.append(Vector3(sin(th) * cos(ph) * r, y, sin(th) * sin(ph) * r))
		pts.append(row)
	st.set_smooth_group(0)
	for i in rings:
		for j in segs:
			var q: Array = [pts[i][j], pts[i + 1][j], pts[i + 1][j + 1], pts[i][j + 1]]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uv)
				st.set_color(Color.WHITE)
				st.add_vertex(q[k])
	st.index()
	st.generate_normals()
	return st.commit()


func pumpkin_stem(uv := Vector2.ZERO) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.09
	c.bottom_radius = 0.16
	c.height = 0.4
	c.radial_segments = 6
	c.rings = 1
	var st := SurfaceTool.new()
	st.create_from(c, 0)
	var arr := st.commit_to_arrays()
	var uvs := PackedVector2Array()
	uvs.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	uvs.fill(uv)
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# The lantern: body (color alpha 1: the carved face glows) and stem
func lantern_mesh() -> ArrayMesh:
	if not fest_mesh.has("lantern"):
		var parts := new_parts()
		add_part(parts, pumpkin_body(), Transform3D.IDENTITY, Color(0.95, 0.45, 0.08, 1.0))
		add_part(parts, pumpkin_stem(), Transform3D(Basis(Vector3.BACK, 0.25), Vector3(0.03, 0.72, 0)), Color(0.3, 0.38, 0.12, 0.0))
		fest_mesh["lantern"] = pose_mesh(parts)
	return fest_mesh["lantern"]


# The carved face is worked out from the position, so the mesh needs no UVs
const LANTERN_SHADER := """
shader_type spatial;
render_mode diffuse_lambert_wrap;
uniform float glow = 3.0;
global uniform vec4 mood_rim;
varying vec3 lp;
varying vec4 vc;
void vertex() { lp = VERTEX; vc = COLOR; }
float tri(vec2 p, vec2 c, float s) {
	vec2 d = p - c;
	return step(-0.45 * s, d.y) * step(d.y, 0.55 * s - 1.6 * abs(d.x));
}
void fragment() {
	vec3 col = pow(vc.rgb, vec3(2.2));
	float m = 0.0;
	if (vc.a > 0.5 && lp.z > 0.25) {
		vec2 p = lp.xy;
		m = max(tri(p, vec2(-0.36, 0.16), 0.32), tri(p, vec2(0.36, 0.16), 0.32));
		m = max(m, tri(p, vec2(0.0, -0.02), 0.14));
		float yc = -0.3 + 0.35 * p.x * p.x;
		float teeth = step(0.5, fract(p.x * 3.0 + 0.25)) * step(abs(p.x), 0.3);
		float mouth = step(abs(p.x), 0.6) * step(abs(lp.y - yc - 0.02), 0.11 - 0.12 * p.x * p.x) * (1.0 - teeth * step(lp.y, yc - 0.02));
		m = max(m, mouth);
	}
	ALBEDO = mix(col, vec3(0.03, 0.01, 0.0), m);
	ROUGHNESS = 0.7;
	float rim = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 rc = mood_rim.a > 0.0 ? mood_rim.rgb : vec3(1.0, 0.85, 0.6);
	EMISSION = vec3(1.0, 0.5, 0.1) * glow * m + col * vc.a * 0.12 * glow + rc * col * rim * 0.4;
}
"""


func lantern_mat() -> ShaderMaterial:
	if not fest_mesh.has("lantern mat"):
		var sh := Shader.new()
		sh.code = LANTERN_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		fest_mesh["lantern mat"] = m
	return fest_mesh["lantern mat"]


# Orange and purple fireflies over the board
func add_fireflies() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(map_cols / 2.0 + 2, 0.5, map_rows / 2.0 + 2)
	pm.color_ramp = fade_ramp()
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.set_color(0, Color(2.2, 0.9, 0.2))
	g.set_color(1, Color(1.3, 0.5, 2.2))
	g.set_offset(1, 0.6)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	pm.turbulence_enabled = true
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.1
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.15
	pm.spread = 180.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var p := particles(fest_root, 140 if graphics_high else 70, 6.0, 0.07, pm)
	p.position = Vector3(map_cols / 2.0, 0.8, map_rows / 2.0)
	p.visibility_aabb = AABB(-pm.emission_box_extents - Vector3(2, 2, 2), pm.emission_box_extents * 2 + Vector3(4, 6, 4))
	p.preprocess = 6.0


# Lantern Night: bone warriors wear a pumpkin (baked into their poses, see glb_pose())
func pumpkin_hat(parts: Dictionary, skull: Transform3D) -> void:
	if not fest_mesh.has("hat"):
		# On the bone texture's plain spot
		fest_mesh["hat"] = pumpkin_body(Vector2(0.2, 0.06))
		fest_mesh["hat stem"] = pumpkin_stem(Vector2(0.2, 0.06))
	var hat := skull * Transform3D(Basis(Vector3.BACK, 0.18).scaled(Vector3(0.3, 0.28, 0.3)), Vector3(0.02, 0.62, -0.02))
	add_part(parts, fest_mesh["hat"], hat, Color(1.0, 0.5, 0.12))
	add_part(parts, fest_mesh["hat stem"], hat * Transform3D(Basis(), Vector3(0, 0.75, 0)), Color(0.3, 0.42, 0.15))


# ---------------------------------------------------------------- Paint Day

# Pastel bunting on posts round the board's edge
func add_border_bunting() -> void:
	mob_shapes()
	var parts := new_parts()
	var corners := [Vector3(-0.15, 0, -0.15), Vector3(map_cols + 0.15, 0, -0.15), Vector3(map_cols + 0.15, 0, map_rows + 0.15), Vector3(-0.15, 0, map_rows + 0.15)]
	var k := 0
	for side in 4:
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var n := maxi(int(a.distance_to(b) / 3.0), 1)
		for i in n:
			var p0 := a.lerp(b, float(i) / n)
			var p1 := a.lerp(b, float(i + 1) / n)
			# Posts and flags stop at the gates
			if not near_gate(p0, 0.5 * GATE_W + 0.2):
				rod(parts, p0, p0 + Vector3(0, 0.6, 0), 0.02, Color(0.55, 0.4, 0.28))
			var pts := []
			for j in 5:
				var u := j / 4.0
				pts.append(p0.lerp(p1, u) + Vector3(0, 0.57 - sin(u * PI) * 0.12, 0))
			for j in 4:
				if near_gate((pts[j] + pts[j + 1]) / 2.0, 0.5 * GATE_W + 0.45):
					continue
				rod(parts, pts[j], pts[j + 1], 0.006, Color(0.95, 0.95, 0.9))
				fest_flag(parts, pts[j].lerp(pts[j + 1], 0.1), pts[j].lerp(pts[j + 1], 0.9), 0.24, pastel(k), 1.0)
				k += 1
	var mi := add_mesh(fest_root, pose_mesh(parts), fest_vcol())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Painted eggs in the grass under the trees near the board
func add_eggs() -> void:
	if not fest_mesh.has("egg"):
		var egg := SphereMesh.new()
		egg.radius = 0.5
		egg.height = 1.3
		egg.radial_segments = 10
		egg.rings = 6
		fest_mesh["egg"] = egg
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.5
		fest_mesh["egg mat"] = painted(m)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for tr: Array in land_trees:
		var h: int = tr[3]
		var pos: Vector3 = tr[0]
		var x := floori(pos.x)
		var y := floori(pos.z)
		var dist := maxi(maxi(maxi(-x, x - map_cols + 1), maxi(-y, y - map_rows + 1)), 0)
		if dist > 3 or (h >> 11) % 3 == 0:
			continue
		for k in 1 + (h >> 13) % 2:
			var a := ((h >> (5 + k * 3)) % 360) * PI / 180.0
			var r := 0.32 + ((h >> 17) % 5) * 0.05
			var p := pos + Vector3(cos(a) * r, 0.05, sin(a) * r)
			var s := 0.09 + ((h >> 19) % 3) * 0.01
			xf.append(Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.4).scaled(Vector3(s, s, s)), p))
			cols.append(pastel((h >> 7) + k))
	var mmi := color_mm(fest_mesh["egg"], fest_mesh["egg mat"])
	var mm := mmi.multimesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# A paint splat on the ground (born: INSTANCE_CUSTOM.x), fading after 8 seconds
const SPLAT_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D splat : filter_linear_mipmap;
uniform float now;
varying vec4 col;
varying float born;
void vertex() { col = COLOR; born = INSTANCE_CUSTOM.x; }
void fragment() {
	float age = now - born;
	float a = texture(splat, UV).r * (1.0 - smoothstep(8.0, 11.0, age)) * smoothstep(0.0, 0.08, age);
	ALBEDO = col.rgb * 0.85;
	ALPHA = a * 0.85;
}
"""


# The splat's shape is drawn here: a blob with drops round it
func splat_mat() -> ShaderMaterial:
	if not fest_mesh.has("splat"):
		var img := Image.create(64, 64, false, Image.FORMAT_L8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var blobs := [[Vector2(32, 32), 15.0]]
		for i in 9:
			var a := rng.randf() * TAU
			var d := rng.randf_range(14, 27)
			blobs.append([Vector2(32, 32) + Vector2(cos(a), sin(a)) * d, rng.randf_range(2.0, 6.0)])
		for y in 64:
			for x in 64:
				var v := 0.0
				for b: Array in blobs:
					var dd: float = (Vector2(x, y) - b[0]).length()
					v = maxf(v, clampf((b[1] - dd) / 1.5 + 0.5, 0.0, 1.0))
				img.set_pixel(x, y, Color(v, v, v))
		img.generate_mipmaps()
		var sh := Shader.new()
		sh.code = SPLAT_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("splat", ImageTexture.create_from_image(img))
		fest_mesh["splat"] = m
	return fest_mesh["splat"]


# Paint Day: a killed monster bursts into pastel paint (see drop_corpse())
func paint_splash(e: Enemy) -> void:
	if splat_mm == null or e.node == null:
		return
	var at := e.node.position
	var p := paint_pool[paint_next % paint_pool.size()]
	paint_next += 1
	p.position = at + Vector3(0, 0.3, 0)
	p.restart()
	var mm := splat_mm.multimesh
	var i := splat_next % mm.instance_count
	splat_next += 1
	var s := 0.5 + e.radius / CELL * 0.8
	mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, 1, s)), at + Vector3(0, 0.03 + (i % 8) * 0.001, 0)))
	mm.set_instance_color(i, pastel(splat_next))
	mm.set_instance_custom_data(i, Color(time, 0, 0, 0))
	mm.visible_instance_count = mini(splat_next, mm.instance_count)


# ---------------------------------------------------------------- Frostfall scarves

# Soldiers wear a scarf in their Warden's color with white ends (baked into
# their poses, see soldier_pose()); head: the head mesh's transform
func soldier_scarf(parts: Dictionary, head: Transform3D) -> void:
	mob_shapes()
	if not fest_mesh.has("scarf"):
		var tor := TorusMesh.new()
		tor.inner_radius = 0.17
		tor.outer_radius = 0.31
		tor.rings = 12
		tor.ring_segments = 6
		fest_mesh["scarf"] = tor
	scarf_part(parts, fest_mesh["scarf"], head * Transform3D(Basis.from_scale(Vector3(1.0, 0.9, 1.0)), Vector3(0, -0.02, 0)), 1.0)
	# Two tails down the back
	for s: float in [-1.0, 1.0]:
		var tail := head * Transform3D(Basis(Vector3.RIGHT, 0.35) * Basis(Vector3.BACK, 0.12 * s), Vector3(0.06 * s, -0.16, -0.25))
		scarf_part(parts, mob_rod, tail * Transform3D(Basis.from_scale(Vector3(0.1, 0.26, 0.04)), Vector3.ZERO), 1.0)
		scarf_part(parts, mob_rod, tail * Transform3D(Basis.from_scale(Vector3(0.11, 0.07, 0.05)), Vector3(0, -0.15, 0)), 0.0)


# mask 1: the owner's color (soldier.gdshader); 0: the texture's white cloth
func scarf_part(parts: Dictionary, mesh: Mesh, xf: Transform3D, mask: float) -> void:
	var from: int = parts.v.size()
	add_part(parts, mesh, xf, Color(1, 1, 1, mask))
	for k in range(from, parts.v.size()):
		parts.uv[k] = Vector2(0.37, 0.37)


# ---------------------------------------------------------------- tower decorations

# Lantern Night's pumpkins and Frostfall's string lights, filled again when towers change
func fill_fest_towers() -> void:
	if lantern_mm != null:
		var mm := lantern_mm.multimesh
		var list: Array[Transform3D] = []
		for tw: Tower in towers.values():
			list.append(Transform3D((Basis(Vector3.UP, -0.3) * Basis(Vector3.RIGHT, -0.45)).scaled(Vector3.ONE * 0.18), to3d(tw.pos) + Vector3(0.27, 0.13, 0.32)))
		for g in gate_cells.size():
			if gate_cells[g] == null:
				continue
			var at := to3d(routes[g][0])
			var out_dir: Vector2 = routes[g][1] - routes[g][0]
			var b := Basis(Vector3.UP, atan2(out_dir.x, out_dir.y))
			# On the lintel, between its spikes, their faces toward the camera whichever way the gate looks
			for s: float in [-0.45 * GATE_W, 0.45 * GATE_W]:
				list.append(Transform3D((Basis(Vector3.UP, s * 0.6) * Basis(Vector3.RIGHT, -0.45)).scaled(Vector3.ONE * 0.155), at + b * Vector3(s, 1.23, -0.3)))
		# And one on the board's edge every 2 tiles
		# (not in front of a gate)
		var tilt := Basis(Vector3.RIGHT, -0.45).scaled(Vector3.ONE * 0.17)
		var edge: Array[Transform3D] = []
		for x in range(1, map_cols - 1, 2):
			edge.append(Transform3D(Basis(Vector3.UP, 0.3 * (x % 3 - 1)) * tilt, Vector3(x + 0.5, 0.21, map_rows + 0.08)))
			edge.append(Transform3D(Basis(Vector3.UP, 0.3 * (x % 3 - 1)) * tilt, Vector3(x + 0.5, 0.21, -0.08)))
		for y in range(1, map_rows - 1, 2):
			edge.append(Transform3D(Basis(Vector3.UP, 0.3 * (y % 3 - 1)) * tilt, Vector3(-0.08, 0.21, y + 0.5)))
			edge.append(Transform3D(Basis(Vector3.UP, 0.3 * (y % 3 - 1)) * tilt, Vector3(map_cols + 0.08, 0.21, y + 0.5)))
		for e: Transform3D in edge:
			if not near_gate(e.origin, 0.5 * GATE_W + 0.3):
				list.append(e)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, Color.WHITE)
	if lights_mm != null:
		var mm := lights_mm.multimesh
		var cols := [Color(3.0, 0.5, 0.4), Color(3.0, 2.2, 0.6), Color(0.6, 2.6, 0.8), Color(0.7, 1.4, 3.0)]
		mm.instance_count = towers.size() * 16
		var i := 0
		for tw: Tower in towers.values():
			var c := to3d(tw.pos)
			for k in 16:
				# Round the base's edge, sagging between posts
				var u := (k % 4 + 0.5) / 4.0
				var off := Basis(Vector3.UP, (k / 4) * PI / 2) * Vector3(lerpf(-0.42, 0.42, u), 0, 0.42)
				var y := 0.2 - sin(u * PI) * 0.06
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.035), c + off + Vector3(0, y, 0)))
				mm.set_instance_color(i, cols[(k + tw.cell.x) % 4])
				i += 1


# ================================================================ Grimwhistle
# The wave-300 boss (special "conductor"): the boss mage 1.4 times bigger, in a
# purple robe, with a bone crown and collar and a bone baton he beats time with
# as he walks. "mage conductor cast" is his Crescendo pose (both arms up).
# His death: he topples backwards flinging his arms up, and his bones crumble
# into a heap (see grim_fall() and drop_corpse()).
const CROWN_Y := 0.8


func add_grim(look: String, cast: bool) -> void:
	var root: Node3D = load("res://assets/monsters/Skeleton_Mage.glb").instantiate()
	add_child(root)
	var skel: Skeleton3D = root.find_child("Skeleton3D")
	var player := AnimationPlayer.new()
	root.add_child(player)
	player.add_animation_library("", walk_anims)
	var anim := walk_anims.get_animation("Walking_C")
	var top := Transform3D(Basis.from_scale(Vector3.ONE * SKELETON_SIZE * 1.8 * 1.4), Vector3.ZERO)
	var ua_r := skel.find_bone("upperarm.r")
	var la_r := skel.find_bone("lowerarm.r")
	var ua_l := skel.find_bone("upperarm.l")
	var hand := skel.find_bone("handslot.r")
	var head := skel.find_bone("head")
	var chest := skel.find_bone("chest")
	var base_mat: StandardMaterial3D
	var poses := []
	var falls := []
	player.play("Walking_C")
	var frames := 8 if cast else 16
	var white := Vector2(0.94, 0.52)  # the texture's plain white spot
	var crown := Color(0.95, 0.85, 0.55)
	# The walk (or cast), then (not for the cast: it shares them) the fall
	for f in frames + (0 if cast else DEATH_POSES):
		var ph := TAU * f / frames
		var dying := f >= frames
		var dk := (f - frames) / (DEATH_POSES - 1.0)  # moment of the fall
		player.seek(0.0 if dying else anim.length * f / frames, true)
		if dying:
			# Both arms flung up as he falls
			for b: Array in [[ua_r, -1.0], [ua_l, 1.0]]:
				var q := skel.get_bone_pose_rotation(b[0])
				skel.set_bone_pose_rotation(b[0], Quaternion(Vector3(1, 0, 0), -2.3 * minf(dk * 2.0, 1.0)) * Quaternion(Vector3(0, 0, 1), b[1] * 0.8 * dk) * q)
		elif cast:
			# Both arms raised high
			for b: Array in [[ua_r, -1.0], [ua_l, 1.0]]:
				var q := skel.get_bone_pose_rotation(b[0])
				skel.set_bone_pose_rotation(b[0], Quaternion(Vector3(1, 0, 0), -2.9 - sin(ph) * 0.15) * Quaternion(Vector3(0, 0, 1), b[1] * 0.55) * q)
		else:
			# The baton arm raised, beating time (two beats a step)
			var q := skel.get_bone_pose_rotation(ua_r)
			skel.set_bone_pose_rotation(ua_r, Quaternion(Vector3(1, 0, 0), -1.7 - sin(ph * 2.0) * 0.4) * Quaternion(Vector3(0, 0, 1), -0.3) * q)
			var q2 := skel.get_bone_pose_rotation(la_r)
			skel.set_bone_pose_rotation(la_r, Quaternion(Vector3(1, 0, 0), -0.3 - cos(ph * 2.0) * 0.25) * q2)
		var gp := bone_globals(skel)
		var parts := new_parts()
		for c in skel.get_children():
			if c is MeshInstance3D:
				if base_mat == null:
					base_mat = c.get_active_material(0)
				var from: int = parts.v.size()
				add_skinned(parts, c, skel, top, gp)
				# The robe: the maroon cloth becomes deep purple
				for k in range(from, parts.v.size()):
					var uv: Vector2 = parts.uv[k]
					if int(uv.x * 8) == 2 and int(uv.y * 4) == 2:
						parts.uv[k] = uv + Vector2(-0.125, 0.0)
						parts.c[k] = Color(1.0, 0.36, 0.62)
		# Bone crown with a gem, a high stiff collar, the baton
		var hx := top * gp[head]
		grim_part(parts, mob_rod, hx * Transform3D(Basis.from_scale(Vector3(0.56, 0.08, 0.56)), Vector3(0, CROWN_Y, 0.0)), crown, white)
		for k in 7:
			var a := TAU * k / 7.0
			var tall := 0.32 if k == 0 else 0.22
			grim_part(parts, mob_cone, hx * Transform3D(Basis(Vector3(cos(a + PI / 2), 0, sin(a + PI / 2)), 0.25) * Basis.from_scale(Vector3(0.09, tall, 0.09)), Vector3(cos(a + PI / 2) * 0.26, CROWN_Y + 0.04 + tall / 2.0, sin(a + PI / 2) * 0.3)), crown, white)
		grim_part(parts, mob_ball, hx * Transform3D(Basis.from_scale(Vector3.ONE * 0.11), Vector3(0, CROWN_Y + 0.05, 0.29)), Color(0.75, 0.3, 1.0), white)
		var cx := top * gp[chest]
		grim_part(parts, mob_cone, cx * Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3(1.0, 0.45, 0.85)), Vector3(0, 0.62, -0.05)), Color(0.32, 0.12, 0.45), white)
		grim_part(parts, mob_rod, cx * Transform3D(Basis.from_scale(Vector3(0.62, 0.05, 0.55)), Vector3(0, 0.5, -0.03)), crown, white)
		var bx := top * gp[hand]
		grim_part(parts, mob_rod, bx * Transform3D(Basis(Vector3.RIGHT, -PI / 2).scaled(Vector3(0.035, 0.9, 0.035)), Vector3(0, 0.05, 0.45)), Color(0.96, 0.94, 0.85), white)
		grim_part(parts, mob_ball, bx * Transform3D(Basis.from_scale(Vector3.ONE * 0.12), Vector3(0, 0.05, -0.02)), crown, white)
		grim_part(parts, mob_ball, bx * Transform3D(Basis.from_scale(Vector3.ONE * 0.07), Vector3(0, 0.05, 0.9)), Color(1.0, 0.85, 1.0), white)
		if dying:
			grim_fall(parts, dk, poses[0].get_aabb().end.y)
			falls.append(pose_mesh(parts))
		else:
			poses.append(pose_mesh(parts))
	root.free()
	if cast and mobs.has("mage conductor"):
		falls = mobs["mage conductor"][4]
	var m := base_mat.duplicate() as StandardMaterial3D
	m.albedo_texture = load("res://assets/monsters/skeleton_texture.png")
	m.albedo_color = Color(1.0, 0.97, 1.0)
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(0.45, 0.12, 0.8)
	m.emission_energy_multiplier = 0.05
	mobs[look] = [poses, mob_mats(m), anim.length * (1.0 if cast else 1.15), poses[0].get_aabb().end.y, falls]


var grim_bursts: Array[GPUParticles3D] = []  # his death: [purple blast, bone shards] (see make_effects())


# Grimwhistle's death burst i at p (0: purple blast, 1: crumbling bones)
func grim_burst(i: int, p: Vector3) -> void:
	fire_burst(grim_bursts[i], p, Color(1.6, 0.5, 2.6) if i == 0 else Color(1.15, 1.1, 0.95))


# Moment k (0-1) of his fall, on a pose of height h: he topples backwards (lying
# by k 0.7), then his bones slump into a flat heap.
func grim_fall(parts: Dictionary, k: float, h: float) -> void:
	var p := pow(minf(k / 0.7, 1.0), 2.0)
	var crumble := smoothstep(0.65, 1.0, k)
	# Turning round the heels (a little behind the feet), lifted so his back stays above ground
	var pivot := Vector3(0, 0, -0.1 * h)
	var turn := Basis(Vector3.RIGHT, -1.45 * p)
	var heap := Basis.from_scale(Vector3(1.0 + 0.3 * crumble, 1.0 - 0.6 * crumble, 1.0 + 0.15 * crumble))
	var xf := Transform3D(heap, Vector3.ZERO) * Transform3D(turn, pivot + Vector3(0, sin(1.45 * p) * 0.14 * h, 0)) * Transform3D(Basis(), -pivot)
	var nb := xf.basis.inverse().transposed()
	for i in parts.v.size():
		parts.v[i] = xf * parts.v[i]
		parts.n[i] = (nb * parts.n[i]).normalized()


# Every bone's pose in the skeleton, from the local poses (the skeleton's own
# global poses aren't updated yet after set_bone_pose_rotation())
func bone_globals(skel: Skeleton3D) -> Array[Transform3D]:
	var gp: Array[Transform3D] = []
	gp.resize(skel.get_bone_count())
	for b in skel.get_bone_count():
		var par := skel.get_bone_parent(b)
		gp[b] = skel.get_bone_pose(b) if par < 0 else gp[par] * skel.get_bone_pose(b)
	return gp


func grim_part(parts: Dictionary, mesh: Mesh, xf: Transform3D, col: Color, uv: Vector2) -> void:
	var from: int = parts.v.size()
	add_part(parts, mesh, xf, col)
	for k in range(from, parts.v.size()):
		parts.uv[k] = uv


# ---------------------------------------------------------------- Crescendo
# A purple ring sweeps out to his reach, music notes spiral out from his baton,
# and every monster in reach gets a small bouncing note while its haste lasts.
# Two notes always circle his crown.
const CRESC_LIFE := 1.6  # seconds of the ring and the notes
const CRESC_NOTES := 18
var cresc: Array = []  # [Enemy, Vector3 where, seconds since]
var hasted := {}  # Enemy -> seconds of its haste note left (looks only, from where he stood)
var cresc_ring: MultiMeshInstance3D
var note_mm: MultiMeshInstance3D

const NOTE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D notes : source_color, filter_linear_mipmap;
varying vec4 col;
varying float pick;
void vertex() {
	col = COLOR;
	pick = INSTANCE_CUSTOM.x;
	// Faces the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec4 n = texture(notes, vec2((UV.x + floor(pick)) * 0.5, UV.y));
	ALBEDO = mix(vec3(0.1, 0.03, 0.16), col.rgb * 1.3, n.r);
	ALPHA = n.a * col.a;
}
"""


# Two music notes side by side (a quaver and two beamed ones), white with a dark rim
func note_texture() -> ImageTexture:
	var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 128:
			var p := Vector2(x % 64, y)
			var d := 99.0
			if x < 64:
				d = note_dist(p, [Vector2(24, 46)], [Vector2(33, 44), Vector2(33, 10)])
				# The flag
				for k in 8:
					var q := Vector2(33, 10) + Vector2(k * 1.6, k * 2.2 + sin(k * 0.6) * 2.0)
					d = minf(d, p.distance_to(q) - 2.2)
			else:
				d = note_dist(p, [Vector2(16, 48), Vector2(44, 42)], [Vector2(25, 46), Vector2(25, 14), Vector2(53, 40), Vector2(53, 8)])
				d = minf(d, seg_dist(p, Vector2(25, 15), Vector2(53, 9)) - 3.5)
			var inner := clampf(0.5 - d, 0.0, 1.0)
			var outer := clampf(0.5 - (d - 2.5), 0.0, 1.0)
			img.set_pixel(x, y, Color(inner, inner, inner, outer))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func note_dist(p: Vector2, heads: Array, stems: Array) -> float:
	var d := 99.0
	for h: Vector2 in heads:
		var q := (p - h).rotated(0.45)
		d = minf(d, Vector2(q.x / 1.35, q.y).length() - 7.0)
	for i in range(0, stems.size(), 2):
		d = minf(d, seg_dist(p, stems[i], stems[i + 1]) - 1.8)
	return d


func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var k := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * k)


func make_cresc_fx() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	var rm := ShaderMaterial.new()
	rm.shader = load("res://assets/shaders/heal_ring.gdshader")
	rm.set_shader_parameter("tint", Color(0.7, 0.3, 1.0))
	rm.set_shader_parameter("energy", 1.6)
	cresc_ring = fx_multimesh(plane, rm, 8)
	var q := QuadMesh.new()
	q.size = Vector2(0.39, 0.195)
	var sh := Shader.new()
	sh.code = NOTE_SHADER
	var nm := ShaderMaterial.new()
	nm.shader = sh
	nm.set_shader_parameter("notes", note_texture())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = 256
	mm.visible_instance_count = 0
	note_mm = MultiMeshInstance3D.new()
	note_mm.multimesh = mm
	note_mm.material_override = nm
	note_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(note_mm)
	fx_box(mm)


# Every computer: Grimwhistle e does his Crescendo (only the look here)
func crescendo_fx(e: Enemy) -> void:
	super(e)
	if e.node == null or not mobs.has("mage conductor cast"):
		return
	if cresc_ring == null:
		make_cresc_fx()
	cresc.append([e, e.node.position, 0.0])
	e.node.set_meta("cast", 1.0)
	e.node.set_meta("mob", mobs["mage conductor cast"])
	for o in enemies:
		if o.pos.distance_to(e.pos) <= CRESCENDO_RANGE:
			hasted[o] = CRESCENDO_TIME


func update_crescendo(delta: float) -> void:
	if cresc_ring == null:
		return
	var rings := 0
	var notes := 0
	var mm := note_mm.multimesh
	var tints := [Color(0.8, 0.45, 1.0), Color(1.0, 0.55, 0.9), Color(1.0, 0.85, 0.4)]
	var s := CRESCENDO_RANGE / CELL
	for i in range(cresc.size() - 1, -1, -1):
		var c: Array = cresc[i]
		c[2] += delta
		var k: float = c[2] / CRESC_LIFE
		if k >= 1.0:
			cresc.remove_at(i)
			continue
		var at: Vector3 = c[1]
		if rings < cresc_ring.multimesh.instance_count:
			cresc_ring.multimesh.set_instance_transform(rings, Transform3D(Basis.from_scale(Vector3(s, 1, s)), at + Vector3(0, 0.06, 0)))
			cresc_ring.multimesh.set_instance_custom_data(rings, Color(minf(k * 1.4, 0.99), 0, 0, 0))
			rings += 1
		# Notes burst from his baton and spiral out to the ring's edge
		for n in CRESC_NOTES:
			if notes >= mm.instance_count:
				break
			var a := TAU * n / CRESC_NOTES + k * 2.0
			var r := s * (1.0 - pow(1.0 - k, 2.0)) * (0.55 + 0.45 * float(n % 3) / 2.0)
			var p := at + Vector3(cos(a) * r, 0.9 + sin(k * PI) * 0.5 + (n % 3) * 0.12, sin(a) * r)
			var sc := 1.0 + 0.4 * (n % 2)
			mm.set_instance_transform(notes, Transform3D(Basis.from_scale(Vector3(sc, sc * 2.0, 1)), p))
			var col: Color = tints[n % 3]
			col.a = clampf((1.0 - k) * 2.0, 0.0, 1.0)
			mm.set_instance_color(notes, col)
			mm.set_instance_custom_data(notes, Color(n % 2, 0, 0, 0))
			notes += 1
	for e in enemies:
		if e.special != "conductor" or e.node == null:
			continue
		# The cast pose for a moment, then his walk again
		if e.node.has_meta("cast"):
			var left: float = e.node.get_meta("cast") - delta
			if left <= 0.0:
				e.node.remove_meta("cast")
				e.node.set_meta("mob", mobs["mage conductor"])
			else:
				e.node.set_meta("cast", left)
		# Two notes always circle his crown
		if notes + 2 <= mm.instance_count:
			var h: float = mobs["mage conductor"][3]
			for n in 2:
				var a := time * 1.6 + n * PI
				var p := e.node.position + Vector3(cos(a) * 0.32, h + 0.08 + sin(time * 3.0 + n) * 0.05, sin(a) * 0.32)
				mm.set_instance_transform(notes, Transform3D(Basis.from_scale(Vector3(0.8, 1.6, 1)), p))
				mm.set_instance_color(notes, Color(0.8, 0.45, 1.0, 0.9))
				mm.set_instance_custom_data(notes, Color(n, 0, 0, 0))
				notes += 1
	# Hasted monsters: a small bouncing note over their heads while it lasts
	for o: Enemy in hasted.keys():
		hasted[o] -= delta
		if hasted[o] <= 0.0 or o.dead or o.node == null or not enemies.has(o):
			hasted.erase(o)
			continue
		if notes >= mm.instance_count or o.special == "conductor":
			continue
		var h2: float = o.node.get_meta("mob")[3] * o.node.scale.y
		var p := o.node.position + Vector3(0, h2 + 0.12 + absf(sin(time * 8.0 + o.bob * 6.0)) * 0.06, 0)
		mm.set_instance_transform(notes, Transform3D(Basis.from_scale(Vector3(0.6, 1.2, 1)), p))
		mm.set_instance_color(notes, Color(1.0, 0.6, 1.0, clampf(hasted[o], 0.0, 1.0)))
		mm.set_instance_custom_data(notes, Color(0, 0, 0, 0))
		notes += 1
	cresc_ring.multimesh.visible_instance_count = rings
	mm.visible_instance_count = notes
