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
var graphics_high := true  # Low/High in the Esc menu: only switches effects
var compat := false  # running on the Compatibility renderer (older PCs), which needs darker light
var env: Environment
var sun: DirectionalLight3D


func build_world() -> void:
	# Forward+ falls back to Compatibility by itself on PCs that can't run it
	compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Dark blue around the board. Set brighter than it looks: ACES and contrast
	# darken it, and the two renderers do that differently.
	env.background_color = Color(0.035, 0.041, 0.052) if compat else Color(0.13, 0.15, 0.19)
	# A sky only for the ambient light and reflections: the camera never sees it
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.45, 0.68)
	sky_mat.sky_horizon_color = Color(0.72, 0.68, 0.6)
	sky_mat.ground_bottom_color = Color(0.12, 0.1, 0.08)
	sky_mat.ground_horizon_color = Color(0.45, 0.4, 0.33)
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.45 if compat else 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.8 if compat else 1.05
	env.glow_enabled = true
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.15
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.0
	env.ssao_power = 1.6
	env.ssil_radius = 2.0
	env.ssil_intensity = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Warm sun from the side for long soft shadows, and a weak cool fill light
	# from the other side so the shadow sides aren't flat
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 1.0 if compat else 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_color = Color(0.55, 0.65, 0.9)
	fill.light_energy = 0.3 if compat else 0.35
	add_child(fill)
	load_settings()
	apply_graphics()

	camera = Camera3D.new()
	camera.fov = 40.0
	camera.position = Vector3(COLS / 2.0, 27.0, ROWS / 2.0 + 14.0)
	add_child(camera)
	camera_focus = Vector3(COLS / 2.0, 0.0, ROWS / 2.0 + 0.3)
	camera.look_at(camera_focus)
	camera.h_offset = CAMERA_H_OFFSET
	camera_home = camera.position

	# Ground: grass tiles, with the path sunk a little lower.
	# Tiles are slightly bigger than one unit so they overlap and no gaps show between them.
	# The two grass colors sit at very slightly different heights so the overlaps don't flicker.
	var tile := BoxMesh.new()
	tile.size = Vector3(1.01, 0.5, 1.01)
	var grass_a := mat(Color(0.11, 0.24, 0.09))
	var grass_b := mat(Color(0.13, 0.28, 0.11))
	var dirt := mat(Color(0.3, 0.2, 0.12))
	# One MultiMesh per color, so the whole ground is a few draw calls instead of 432
	var spots := {dirt: [], grass_a: [], grass_b: []}
	for x in COLS:
		for y in ROWS:
			if path_cells.has(Vector2i(x, y)):
				spots[dirt].append(Vector3(x + 0.5, -0.33, y + 0.5))
			elif (x + y) % 2 == 0:
				spots[grass_a].append(Vector3(x + 0.5, -0.25, y + 0.5))
			else:
				spots[grass_b].append(Vector3(x + 0.5, -0.252, y + 0.5))
	for m: Material in spots:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tile
		mm.instance_count = spots[m].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[m][i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		add_child(mmi)
	var base := BoxMesh.new()
	base.size = Vector3(COLS + 0.6, 1.0, ROWS + 0.6)
	add_mesh(self, base, mat(Color(0.16, 0.12, 0.09)), Vector3(COLS / 2.0, -0.85, ROWS / 2.0))

	for g in GATES.size():
		build_gate(g)

	# Range circle and build preview
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 48
	range_disc = add_mesh(self, disc, mat(Color.WHITE, 0.0, 0.07))
	range_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	build_markers_and_hud()


# Graphics High: ambient occlusion (dark contact shadows), bounced light, soft
# wide shadows and more glow. Low: plain shadows and less glow, for slower PCs.
# The Compatibility renderer has no ambient occlusion or bounced light anyway.
func apply_graphics() -> void:
	var high := graphics_high
	env.ssao_enabled = high and not compat
	env.ssil_enabled = high and not compat
	env.glow_intensity = 0.6 if high else 0.35
	sun.shadow_blur = 1.5 if high else 1.0
	sun.light_angular_distance = 1.5 if high else 0.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if high else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK and cfg.has_section_key("graphics", "high"):
		graphics_high = cfg.get_value("graphics", "high", true)
	else:
		# First run: Low on weaker PCs (built-in graphics, or the Compatibility
		# fallback), High otherwise. Saved, so the player's choice always wins after this.
		graphics_high = not (compat or weak_gpu())
		save_settings()


# True for graphics built into the processor, like most laptops have.
func weak_gpu() -> bool:
	return RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)  # keeps any other settings in it
	cfg.set_value("graphics", "high", graphics_high)
	cfg.save(SETTINGS_FILE)


# Stone gate with a green portal where one player's monsters come out. It faces
# along its stretch of path, so monsters walk straight out of it. A gem on top
# shows the player's color; the portal only shows while a player uses the gate.
func build_gate(g: int) -> void:
	var gate := Node3D.new()
	gate.position = to3d(routes[g][0])
	var out_dir: Vector2i = LOOP[g] - GATES[g]
	gate.rotation.y = atan2(out_dir.x, out_dir.y)
	add_child(gate)
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
	gate_parts.append({"surface": surface_node, "sparks": portal, "light": portal_light})


func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func build_markers_and_hud() -> void:
	range_disc.visible = false
	var ghost_mesh := BoxMesh.new()
	ghost_mesh.size = Vector3(0.95, 0.1, 0.95)
	ghost_mat = mat(Color.GREEN, 0.0, 0.4)
	ghost = add_mesh(self, ghost_mesh, ghost_mat)
	ghost.visible = false

	# Each player's area, shown while placing a tower in multiplayer
	var area_mesh := PlaneMesh.new()
	area_mesh.size = Vector2(COLS / 2.0, ROWS / 2.0)
	for slot in MAX_PLAYERS:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var right := slot >= 2
		var top := slot == 1 or slot == 2
		var pos := Vector3(COLS * (0.75 if right else 0.25), 0.04, ROWS * (0.25 if top else 0.75))
		var plane := add_mesh(self, area_mesh, m, pos)
		plane.visible = false
		area_planes.append(plane)

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
	if t.type == "arrow" or t.type == "cannon":
		var model_head: Node3D
		if t.type == "arrow":
			model_head = build_arrow_tower(root, t.level, t.owner)
		else:
			model_head = build_cannon_tower(root, t.level, t.owner)
		add_pips(root, t.level, Vector3(0, 0.06, 0.44))
		t.node = root
		t.head = model_head
		return
	# The base is tinted with the owner's color
	var base := BoxMesh.new()
	base.size = Vector3(0.8, 0.3, 0.8)
	add_mesh(root, base, mat(stone_mat.albedo_color.lerp(PLAYER_COLORS[t.owner], 0.45)), Vector3(0, 0.15, 0))
	# The tower gets taller with each level
	var h := 0.35 + t.level * 0.2
	var body := CylinderMesh.new()
	body.top_radius = 0.2
	body.bottom_radius = 0.28
	body.height = h
	add_mesh(root, body, mat(col.darkened(0.3)), Vector3(0, 0.3 + h / 2.0, 0))
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
			var crystal := mat(col, 1.2)
			add_mesh(head, cone, crystal, Vector3(0, 0.17, 0))
			add_mesh(head, cone, crystal, Vector3(0, -0.17, 0)).rotation_degrees.x = 180
		"spark":
			var orb := SphereMesh.new()
			orb.radius = 0.2
			orb.height = 0.4
			add_mesh(head, orb, mat(col, 2.0), Vector3(0, 0.1, 0))
			var ring := TorusMesh.new()
			ring.inner_radius = 0.26
			ring.outer_radius = 0.31
			add_mesh(head, ring, dark_mat, Vector3(0, 0.1, 0)).rotation_degrees.x = 60
	add_pips(root, t.level, Vector3(0, 0.32, 0.36))
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


# Colors and shared meshes for the code-built towers (the cannon tower)
const DW_STONE := Color(0.58, 0.5, 0.4)
const DW_STONE_DARK := Color(0.32, 0.31, 0.33)
const DW_METAL := Color(0.42, 0.45, 0.5)
const DW_IRON := Color(0.2, 0.2, 0.23)
const DW_BRASS := Color(0.85, 0.62, 0.22)
const DW_WOOD := Color(0.52, 0.32, 0.15)
const DW_WOOD_DARK := Color(0.32, 0.19, 0.09)
const DW_WOOD_LIGHT := Color(0.72, 0.52, 0.28)
const DW_STRING := Color(0.95, 0.92, 0.8)
const DW_SMOKE := Color(0.3, 0.3, 0.32)
var model_meshes := {}  # merged tower meshes by name
var model_mats := {}  # their materials by color


# Arrow tower: the KayKit stone towers as the pack has them (Kay Lousberg, CC0,
# see assets/CREDITS.md). Level 1 is the open tower with a crossbow on top,
# level 2 tower_A and levels 3 and 4 the bigger tower_B, with the crossbow out
# on the balcony (two at level 4). The crossbows turn to aim (their front is -Z),
# going round the balcony. The roof, banners and flag show the owner's color.
const PACK_SCALE := 0.65  # the pack is made for bigger hexagon tiles
const ARROW_MODELS := ["tower_base", "tower_A", "tower_B", "tower_B"]
const ARROW_HEAD_Y := [1.38, 1.5, 1.5, 1.5]  # where the crossbows sit, in pack units
const ARROW_REACH := [0.0, 0.5, 0.62, 0.62]  # how far out on the balcony
var pack_meshes := {}  # pack model -> [[mesh, transform], ...], loaded once
var pack_mats := {}  # shared pack materials by texture and owner
var pack_shader: Shader


func build_arrow_tower(root: Node3D, level: int, slot: int) -> Node3D:
	var model := Node3D.new()
	model.scale = Vector3.ONE * PACK_SCALE * (1.08 if level == 3 else 1.0)
	root.add_child(model)
	add_pack_model(model, "towers/building_%s_blue" % ARROW_MODELS[level], slot)
	if level == 0:
		# The open tower only has small banners, so a flag shows whose it is
		var flag := Node3D.new()
		flag.position = Vector3(0.3, 1.45, 0.2)
		flag.scale = Vector3.ONE * 1.8
		model.add_child(flag)
		add_pack_model(flag, "towers/flag_blue", slot)
	var head := Node3D.new()
	head.position = Vector3(0, ARROW_HEAD_Y[level], 0)
	model.add_child(head)
	var spots := [Vector3(0, 0, -ARROW_REACH[level])]
	if level == 3:
		spots = [Vector3(-0.3, 0, -0.55), Vector3(0.3, 0, -0.55)]
	for p: Vector3 in spots:
		var bow := Node3D.new()
		bow.position = p + (Vector3(0, 0.2, 0.3) if level == 0 else Vector3(0, 0.12, 0))
		bow.rotation_degrees.y = 180.0  # the pack's crossbow points at +Z
		bow.scale = Vector3.ONE * 0.5
		head.add_child(bow)
		add_pack_model(bow, "towers/Skeleton_Crossbow", 0)
	return head


# Adds a pack model's meshes under parent in the owner's color. The meshes are
# loaded once and shared by every model like it.
func add_pack_model(parent: Node3D, file: String, slot: int) -> void:
	if not pack_meshes.has(file):
		var parts := []
		var scene: Node = load("res://assets/%s.gltf" % file).instantiate()
		collect_meshes(scene, Transform3D.IDENTITY, parts)
		scene.free()
		pack_meshes[file] = parts
	for part: Array in pack_meshes[file]:
		var mi := add_mesh(parent, part[0], pack_mat(part[0], slot))
		mi.transform = part[1]


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


# Cannon tower: a dwarven mortar bunker. A squat eight-sided stone bunker with
# buttresses and a band in the owner's color, and a fat iron mortar between
# brass cheek plates that turns to aim (its front is -Z). Each level makes it
# taller and the mortar bigger, and adds: level 2 iron straps, level 3 two
# chimneys, level 4 spikes, smoke, glowing furnace slits and spare cannonballs.
# Merged and shared like the arrow tower.
const DW_FIRE := Color(1.0, 0.5, 0.1)
const DW_BORE := Color(0.03, 0.03, 0.03)


func build_cannon_tower(root: Node3D, level: int, slot: int) -> Node3D:
	var top := 0.12 + 0.22 + level * 0.12
	var body_key := "cannon body %d %d" % [level, slot]
	if not model_meshes.has(body_key):
		model_meshes[body_key] = merge_parts(cannon_body_parts(level, PLAYER_COLORS[slot]))
	var head_key := "cannon head %d" % level
	if not model_meshes.has(head_key):
		model_meshes[head_key] = merge_parts(cannon_head_parts(level))
	add_mesh(root, model_meshes[body_key], null)
	var head := Node3D.new()
	head.position = Vector3(0, top + 0.09, 0)
	root.add_child(head)
	add_mesh(head, model_meshes[head_key], null)
	return head


func cannon_body_parts(L: int, oc: Color) -> Node3D:
	var root := Node3D.new()
	var H := 0.22 + L * 0.12
	var top := 0.12 + H
	var oct := Vector3(0, 22.5, 0)
	part_box(root, Vector3(0.86, 0.12, 0.86), DW_STONE_DARK, Vector3(0, 0.06, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			part_box(root, Vector3(0.16, 0.16, 0.16), DW_METAL, Vector3(sx * 0.36, 0.08, sz * 0.36))
	part_cyl(root, 0.35, 0.4, H, DW_STONE, Vector3(0, 0.12 + H / 2.0, 0)).rotation_degrees = oct
	# Band in the owner's color
	part_cyl(root, 0.385, 0.395, 0.1, oc, Vector3(0, 0.12 + H * 0.4, 0)).rotation_degrees = oct
	# Buttresses with brass caps, spiked at level 4
	for k in 4:
		var f := part_node(root, Vector3.ZERO, Vector3(0, 45 + k * 90, 0))
		part_box(f, Vector3(0.14, H * 0.85, 0.14), DW_STONE_DARK, Vector3(0, 0.12 + H * 0.425, 0.37))
		part_box(f, Vector3(0.17, 0.05, 0.17), DW_BRASS, Vector3(0, 0.12 + H * 0.85, 0.37))
		if L >= 3:
			part_cyl(f, 0.0, 0.05, 0.16, DW_IRON, Vector3(0, 0.12 + H * 0.85 + 0.1, 0.37), 6)
	part_cyl(root, 0.42, 0.37, 0.08, DW_STONE_DARK, Vector3(0, top + 0.04, 0)).rotation_degrees = oct
	# Iron straps from level 2
	if L >= 1:
		for k in 4:
			var f := part_node(root, Vector3.ZERO, Vector3(0, k * 90, 0))
			part_box(f, Vector3(0.06, H, 0.03), DW_METAL, Vector3(0, 0.12 + H / 2.0, 0.37))
	# Chimneys from level 3, smoke and glowing furnace slits at level 4
	if L >= 2:
		for sx in [-1, 1]:
			part_cyl(root, 0.05, 0.06, 0.34, DW_IRON, Vector3(sx * 0.2, top + 0.17, -0.3))
			part_cyl(root, 0.07, 0.07, 0.04, DW_BRASS, Vector3(sx * 0.2, top + 0.34, -0.3))
	if L >= 3:
		for k in 3:
			part_ball(root, 0.045 + k * 0.017, DW_SMOKE, Vector3(-0.2 + k * 0.05, top + 0.42 + k * 0.09, -0.3 - k * 0.03))
		for sx in [-1, 1]:
			add_mesh(root, box(0.05, 0.1, 0.03), model_mat(DW_FIRE, 3.0), Vector3(sx * 0.1, 0.12 + H * 0.7, 0.36))
	return root


func cannon_head_parts(L: int) -> Node3D:
	var head := Node3D.new()
	part_cyl(head, 0.28, 0.3, 0.08, DW_IRON, Vector3(0, 0.04, 0), 10)
	# Stone cheek plates with brass tops, and the axle between them
	for sx in [-1, 1]:
		part_box(head, Vector3(0.06, 0.24, 0.3), DW_STONE_DARK, Vector3(sx * 0.19, 0.18, 0.02))
		part_box(head, Vector3(0.065, 0.04, 0.31), DW_BRASS, Vector3(sx * 0.19, 0.3, 0.02))
	part_cyl(head, 0.05, 0.05, 0.44, DW_IRON, Vector3(0, 0.2, 0.02)).rotation_degrees = Vector3(0, 0, 90)
	var s := 1.0 + L * 0.06
	part_mortar(head, Vector3(0, 0.2, 0.02), 40, 0.36 * s, 0.12 * s, 0.14 * s)
	# Spare cannonballs behind the mortar at level 4
	if L >= 3:
		for x in [-0.08, 0.08]:
			part_ball(head, 0.07, DW_IRON, Vector3(x, 0.15, 0.24))
		part_ball(head, 0.07, DW_IRON, Vector3(0, 0.26, 0.24))
	return head


# A fat mortar barrel pointing at -Z, tilted up by elev degrees: a breech ball and
# knob at the back, two brass bands, a flared brass muzzle and a dark bore
func part_mortar(p: Node3D, pos: Vector3, elev: float, length: float, rb: float, rf: float) -> Node3D:
	var n := part_node(p, pos, Vector3(elev, 0, 0))
	var back := length * 0.2
	var front := -length * 0.8
	var lie := Vector3(-90, 0, 0)
	part_cyl(n, rf, rb, length, DW_IRON, Vector3(0, 0, (back + front) / 2.0), 14).rotation_degrees = lie
	part_ball(n, rb, DW_IRON, Vector3(0, 0, back))
	part_ball(n, rb * 0.4, DW_BRASS, Vector3(0, 0, back + rb * 0.95))
	for f in [0.12, 0.5]:
		var r := lerpf(rb, rf, f) + 0.015
		part_cyl(n, r, r, 0.04, DW_BRASS, Vector3(0, 0, back - length * f), 14).rotation_degrees = lie
	part_cyl(n, rf * 1.3, rf * 1.12, 0.08, DW_BRASS, Vector3(0, 0, front + 0.04), 14).rotation_degrees = lie
	part_cyl(n, rf * 0.75, rf * 0.75, 0.012, DW_BORE, Vector3(0, 0, front - 0.002), 14).rotation_degrees = lie
	return n


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


func update_visuals(delta: float) -> void:
	time += delta
	for g in gate_parts.size():
		var in_use: bool = players[g] != null
		for part in gate_parts[g].values():
			part.visible = in_use
		gate_parts[g]["sparks"].rotation.z += delta * 2.0
	for e in enemies:
		var r := e.radius / CELL
		e.node.position = to3d(e.pos, -0.08 + r + absf(sin(time * 8.0 + e.bob)) * 0.06)
		# Slowed monsters use their kind's icy material
		var m: Material = enemy_mats[e.kind][1] if e.slow_time > 0.0 else e.mat
		if e.node.material_override != m:
			e.node.material_override = m
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

	# While placing a tower: your area glows in your color, other players' areas go dark
	for slot in MAX_PLAYERS:
		var plane: MeshInstance3D = area_planes[slot]
		plane.visible = showing_areas() and players[slot] != null
		var own := slot == local_slot
		plane.material_override.albedo_color = Color(PLAYER_COLORS[slot], 0.22) if own else Color(0, 0, 0, 0.5)
	range_disc.visible = false
	ghost.visible = false
	if selected != null:
		show_range(selected.pos, TOWERS[selected.type]["range"][selected.level])
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


var enemy_meshes := {}  # monster kind -> its ball
var enemy_mats := {}  # monster kind -> [normal, slowed] material
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

	var r := e.radius / CELL
	# The ball and its two materials (normal and slowed) are shared by every monster of a kind
	if not enemy_meshes.has(kind):
		var ball := SphereMesh.new()
		ball.radius = r
		ball.height = r * 2.0
		ball.radial_segments = 32
		ball.rings = 16
		enemy_meshes[kind] = ball
		var mats := [mat(e.color), mat(e.color.lerp(Color(0.55, 0.9, 1.0), 0.55))]
		if kind == "armored":
			for m: StandardMaterial3D in mats:
				m.metallic = 0.8
				m.roughness = 0.3
		enemy_mats[kind] = mats
	e.mat = enemy_mats[kind][0]
	e.node = add_mesh(self, enemy_meshes[kind], e.mat, to3d(e.pos, r))
	if kind == "boss":
		var crown := TorusMesh.new()
		crown.inner_radius = 0.1
		crown.outer_radius = 0.17
		add_mesh(e.node, crown, gold_mat, Vector3(0, r * 0.95, 0))
	e.bob = randf() * TAU
	return e


# A shot flying from tower t to the target. A visual shot is the other players'
# copy of the host's shot: it flies the same way but does no damage.
func launch_shot(t: Tower, target: Enemy, visual: bool) -> void:
	var s := Shot.new()
	s.pos = t.pos + t.aim * 14.0
	s.target = target
	s.target_pos = target.pos
	s.type = t.type
	s.level = t.level
	s.owner = t.owner
	s.visual = visual
	if t.type == "cannon":
		s.speed = 300.0
	if not shot_mats.has(t.type):
		shot_mats[t.type] = mat(TOWERS[t.type]["color"], 2.0)
		var ball := SphereMesh.new()
		ball.radius = 0.12 if t.type == "cannon" else 0.07
		ball.height = ball.radius * 2.0
		ball.radial_segments = 16
		ball.rings = 8
		shot_meshes[t.type] = ball
	s.node = add_mesh(self, shot_meshes[t.type], shot_mats[t.type], to3d(s.pos, 0.6))
	# Arrows start up at the crossbow and come down to the monster (just for looks)
	if t.type == "arrow":
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
