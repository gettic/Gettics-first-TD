extends Node3D
## Gettic's first TD - a small 3D tower defense game.
## Enemies walk a spiral path toward the portal in the middle.
## The game logic runs on a flat map measured in pixels (CELL pixels per tile).
## to3d() turns those positions into the 3D world, where one tile is one unit.
## The side panel, health bars and lightning are drawn in 2D on top (draw_hud).

const CELL := 40
const COLS := 24
const ROWS := 18
const SCREEN_W := 1280
const SCREEN_H := 720
const PANEL_LEFT := 960
const CAMERA_SPEED := 12.0  # tiles per second
const CAMERA_LIMIT := Vector2(9.0, 7.0)  # how far the camera can move from its start
const MAX_WAVE := 30
const START_GOLD := 150
const MAX_ALIVE := 50  # you lose when this many monsters are alive at once (a boss counts as 5)
const WAVE_INTERVAL := 25.0  # seconds between waves once the game has started

# The path in grid coordinates. Monsters come out of the portal in the middle,
# walk out to the square, then walk around the square clockwise forever.
const SPAWN_PATH := [Vector2i(12, 9), Vector2i(12, 15)]
const LOOP := [Vector2i(12, 15), Vector2i(2, 15), Vector2i(2, 2), Vector2i(21, 2), Vector2i(21, 15)]

# Tower stats per level (index 0 = level 1). "cost"[0] is the build price,
# the rest are upgrade prices.
const TOWER_TYPES := ["arrow", "cannon", "frost", "spark"]
const TOWERS := {
	"arrow": {
		"name": "Arrow", "color": Color(0.35, 0.85, 0.35),
		"desc": "Fast single-target shots",
		"cost": [50, 60, 130, 260],
		"damage": [10, 22, 48, 110],
		"range": [120.0, 130.0, 145.0, 165.0],
		"cooldown": [0.5, 0.45, 0.4, 0.32],
	},
	"cannon": {
		"name": "Cannon", "color": Color(1.0, 0.6, 0.2),
		"desc": "Slow shots, splash damage",
		"cost": [80, 90, 180, 360],
		"damage": [20, 45, 95, 210],
		"range": [110.0, 115.0, 125.0, 135.0],
		"cooldown": [1.4, 1.3, 1.2, 1.1],
		"splash": [55.0, 60.0, 70.0, 80.0],
	},
	"frost": {
		"name": "Frost", "color": Color(0.4, 0.85, 1.0),
		"desc": "Slows enemies down",
		"cost": [70, 70, 140, 280],
		"damage": [4, 8, 16, 32],
		"range": [110.0, 120.0, 130.0, 140.0],
		"cooldown": [0.9, 0.8, 0.7, 0.6],
		"slow": [0.6, 0.5, 0.4, 0.3],
	},
	"spark": {
		"name": "Spark", "color": Color(0.75, 0.5, 1.0),
		"desc": "Lightning that chains",
		"cost": [120, 120, 240, 480],
		"damage": [30, 60, 120, 250],
		"range": [140.0, 150.0, 165.0, 185.0],
		"cooldown": [1.2, 1.1, 1.0, 0.9],
		"chain": [3, 4, 5, 6],
	},
}

# Panel layout (screen pixels)
const PANEL_X := PANEL_LEFT + 16
const UPGRADE_RECT := Rect2(PANEL_X, 480, 140, 40)
const SELL_RECT := Rect2(PANEL_X + 148, 480, 140, 40)
const WAVE_RECT := Rect2(PANEL_X, 610, 200, 44)
const SPEED_RECT := Rect2(PANEL_X + 208, 610, 80, 44)
const UPDATE_RECT := Rect2(PANEL_X, 532, 288, 36)

# Update popup layout (screen pixels)
const DIALOG_RECT := Rect2(340, 140, 600, 440)
const DIALOG_YES_RECT := Rect2(380, 506, 250, 44)
const DIALOG_NO_RECT := Rect2(650, 506, 250, 44)

# Checked at startup to see if a newer release is on GitHub
const RELEASES_API := "https://api.github.com/repos/gettic/Gettics-first-TD/releases/latest"


class Enemy:
	var pos: Vector2
	var wp := 1
	var hp := 1.0
	var max_hp := 1.0
	var speed := 55.0
	var armor := 0.0
	var bounty := 1
	var weight := 1  # how much this monster counts toward MAX_ALIVE
	var radius := 10.0
	var color := Color.WHITE
	var slow_factor := 1.0
	var slow_time := 0.0
	var traveled := 0.0
	var dead := false
	var node: MeshInstance3D
	var mat: StandardMaterial3D
	var bob := 0.0


class Tower:
	var type: String
	var cell: Vector2i
	var pos: Vector2
	var level := 0
	var cooldown := 0.0
	var spent := 0
	var aim := Vector2.UP
	var node: Node3D
	var head: Node3D


class Shot:
	var pos: Vector2
	var target: Enemy
	var target_pos: Vector2
	var type: String
	var level := 0
	var speed := 420.0
	var done := false
	var node: MeshInstance3D


var path_cells := {}
var path_points: Array[Vector2] = []
var loop_start := 0  # index in path_points where the square loop starts
var enemies: Array[Enemy] = []
var towers := {}  # Vector2i -> Tower
var shots: Array[Shot] = []
var effects := []  # Dictionaries: bolts and explosions

var gold := 0
var next_wave_timer := 0.0
var wave := 0
var spawn_queue: Array[String] = []
var spawn_timer := 0.0
var spawn_hp := 0.0
var build_type := ""
var selected: Tower = null
var game_speed := 1
var state := "playing"  # "playing", "won" or "lost"
var paused := false
var message := ""
var message_time := 0.0
var font: Font
var time := 0.0
var version := ""
var update_version := ""  # set when GitHub has a newer release
var update_url := ""  # release page
var update_zip_url := ""  # the Windows .zip in the release
var update_notes := ""  # "What's new" from the release notes
var update_dialog := ""  # "", "ask", "downloading" or "failed"
var update_error := ""
var update_http: HTTPRequest

# 3D scene pieces
var camera: Camera3D
var camera_home: Vector3
var hud: Node2D
var portal: Node3D
var range_disc: MeshInstance3D
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var stone_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D
var gold_mat: StandardMaterial3D
var pip_mesh: SphereMesh
var boom_mesh: SphereMesh
var shot_mats := {}


func _ready() -> void:
	font = ThemeDB.fallback_font
	var corners: Array = SPAWN_PATH + LOOP.slice(1)
	for w in corners:
		path_points.append(cell_center(w))
	loop_start = SPAWN_PATH.size() - 1
	# Mark the path tiles, including the side that closes the square
	corners.append(LOOP[0])
	for i in range(corners.size() - 1):
		var a: Vector2i = corners[i]
		var b: Vector2i = corners[i + 1]
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var c := a
		while true:
			path_cells[c] = true
			if c == b:
				break
			c += step
	build_world()
	new_game()
	check_for_update()


# ---------------------------------------------------------------- updates

func check_for_update() -> void:
	version = str(ProjectSettings.get_setting("application/config/version", "0"))
	# Clean up the old game file left behind by the last update.
	if OS.has_feature("template"):
		DirAccess.remove_absolute(game_exe_path() + ".old")
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--remove-old="):
				remove_old_exe(arg.trim_prefix("--remove-old="))
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(_on_update_checked.bind(http))
	if http.request(RELEASES_API, ["User-Agent: GetticsFirstTD", "Accept: application/vnd.github+json"]) != OK:
		http.queue_free()


func _on_update_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	# No internet or GitHub not answering: just play without the update check.
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	var tag := str(data.get("tag_name", ""))
	if is_newer(tag, version):
		update_version = tag
		update_url = str(data.get("html_url", ""))
		var notes = data.get("body")
		update_notes = clean_notes(notes if notes is String else "")
		var assets = data.get("assets")
		if assets is Array:
			for asset in assets:
				if asset is Dictionary and str(asset.get("name", "")).ends_with("-windows.zip"):
					update_zip_url = str(asset.get("browser_download_url", ""))


# Keeps only the "What's new" part of the release notes and removes Markdown symbols.
func clean_notes(body: String) -> String:
	var cut := body.find("**How to play")
	if cut >= 0:
		body = body.substr(0, cut)
	var lines := PackedStringArray()
	for line in body.replace("\r", "").split("\n"):
		line = line.replace("**", "").replace("`", "").strip_edges()
		if line == "" or line.to_lower().begins_with("what's new"):
			continue
		if line.begins_with("- "):
			line = "•  " + line.substr(2)
		lines.append(line)
	return "\n".join(lines)


func game_exe_path() -> String:
	return OS.get_executable_path()


func start_update() -> void:
	# Running from the Godot editor (or no .zip in the release): open the download page instead.
	if not OS.has_feature("template") or update_zip_url == "":
		OS.shell_open(update_url)
		update_dialog = ""
		return
	download_update()


func download_update() -> void:
	update_dialog = "downloading"
	var zip_path := OS.get_user_data_dir().path_join("update.zip")
	update_http = HTTPRequest.new()
	update_http.download_file = zip_path
	add_child(update_http)
	update_http.request_completed.connect(_on_update_downloaded.bind(zip_path))
	if update_http.request(update_zip_url, ["User-Agent: GetticsFirstTD"]) != OK:
		update_failed("Could not start the download.")


func _on_update_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, zip_path: String) -> void:
	update_http.queue_free()
	update_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		update_failed("The download failed. Check your internet connection.")
		return
	var exe := game_exe_path()
	var result_text := install_update(zip_path, exe)
	DirAccess.remove_absolute(zip_path)
	if not result_text.ends_with(".exe"):
		update_failed(result_text)
		return
	restart_game(result_text, exe)


# Puts the new game file next to the old one, using the name from the download
# (like "Gettic's first TD v1.6.exe"). Returns the new file's path, or an error message.
func install_update(zip_path: String, exe: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "The downloaded file is damaged."
	var new_exe := PackedByteArray()
	var new_name := ""
	for file in zip.get_files():
		if file.to_lower().ends_with(".exe"):
			new_exe = zip.read_file(file)
			new_name = file.get_file()
			break
	zip.close()
	if new_exe.is_empty():
		return "The download doesn't contain the game."
	var target := exe.get_base_dir().path_join(new_name)
	if target.to_lower() == exe.to_lower():
		# Same name as the running game. Windows won't let a running program be
		# overwritten, but it can be renamed, so move it to .old first.
		var old := exe + ".old"
		DirAccess.remove_absolute(old)
		if DirAccess.rename_absolute(exe, old) != OK:
			return "Could not replace the game file."
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		if FileAccess.file_exists(exe + ".old") and not FileAccess.file_exists(exe):
			DirAccess.rename_absolute(exe + ".old", exe)
		return "Could not write the new game file."
	f.store_buffer(new_exe)
	f.close()
	return target


# Starts the new version and closes this one. The new version deletes this
# version's file once it has closed (see remove_old_exe).
func restart_game(new_exe: String, old_exe: String) -> void:
	var args := PackedStringArray()
	if new_exe.to_lower() != old_exe.to_lower():
		args = ["--", "--remove-old=" + old_exe]
	OS.create_process(new_exe, args)
	get_tree().quit()


# Deletes the previous version's game file after an update. Only files next to
# this game whose name starts like the game's own are ever deleted.
func remove_old_exe(path: String, tries := 10) -> void:
	var exe := game_exe_path()
	var name := path.get_file().to_lower()
	if path.get_base_dir() != exe.get_base_dir() or path.to_lower() == exe.to_lower() \
			or not name.ends_with(".exe") or not (name.begins_with("gettic's first td") or name.begins_with("getticsfirsttd")):
		return
	if not FileAccess.file_exists(path):
		return
	# The old version may still be closing, so try again a few times.
	if DirAccess.remove_absolute(path) != OK and tries > 1:
		await get_tree().create_timer(0.5).timeout
		remove_old_exe(path, tries - 1)


func update_failed(message: String) -> void:
	update_dialog = "failed"
	update_error = message


# Compares versions like "v1.10" and "1.2" number by number.
func is_newer(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func new_game() -> void:
	for e in enemies:
		e.node.queue_free()
	for t: Tower in towers.values():
		t.node.queue_free()
	for s in shots:
		s.node.queue_free()
	for fx in effects:
		if fx.has("node"):
			fx["node"].queue_free()
	enemies.clear()
	towers.clear()
	shots.clear()
	effects.clear()
	spawn_queue.clear()
	gold = START_GOLD
	wave = 0
	next_wave_timer = 0.0
	build_type = ""
	selected = null
	game_speed = 1
	state = "playing"
	paused = false
	flash("Build towers, then press SPACE to start")


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)


func to3d(p: Vector2, height := 0.0) -> Vector3:
	return Vector3(p.x / CELL, height, p.y / CELL)


func mouse_over_panel() -> bool:
	return get_viewport().get_mouse_position().x >= PANEL_LEFT


# Finds the map tile under the mouse by shooting a ray from the camera to the ground.
func mouse_cell() -> Vector2i:
	return screen_to_cell(get_viewport().get_mouse_position())


func screen_to_cell(mp: Vector2) -> Vector2i:
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return Vector2i(-100, -100)
	var hit := from + dir * (-from.y / dir.y)
	return Vector2i(floori(hit.x), floori(hit.z))


func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func can_build(c: Vector2i) -> bool:
	return in_map(c) and not path_cells.has(c) and not towers.has(c)


func flash(text: String) -> void:
	message = text
	message_time = 3.0


func tower_button_rect(i: int) -> Rect2:
	return Rect2(PANEL_X, 150 + i * 64, 288, 56)


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


func build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 40.0
	camera.position = Vector3(COLS / 2.0, 27.0, ROWS / 2.0 + 14.0)
	add_child(camera)
	camera.look_at(Vector3(COLS / 2.0, 0.0, ROWS / 2.0 + 0.3))
	# Shift the view so the map is centered in the area left of the side panel
	camera.h_offset = 4.4
	camera_home = camera.position

	# Ground: grass tiles, with the path sunk a little lower.
	# Tiles are slightly bigger than one unit so they overlap and no gaps show between them.
	# The two grass colors sit at very slightly different heights so the overlaps don't flicker.
	var tile := BoxMesh.new()
	tile.size = Vector3(1.01, 0.5, 1.01)
	var grass_a := mat(Color(0.11, 0.24, 0.09))
	var grass_b := mat(Color(0.13, 0.28, 0.11))
	var dirt := mat(Color(0.3, 0.2, 0.12))
	for x in COLS:
		for y in ROWS:
			if path_cells.has(Vector2i(x, y)):
				add_mesh(self, tile, dirt, Vector3(x + 0.5, -0.33, y + 0.5))
			elif (x + y) % 2 == 0:
				add_mesh(self, tile, grass_a, Vector3(x + 0.5, -0.25, y + 0.5))
			else:
				add_mesh(self, tile, grass_b, Vector3(x + 0.5, -0.252, y + 0.5))
	var base := BoxMesh.new()
	base.size = Vector3(COLS + 0.6, 1.0, ROWS + 0.6)
	add_mesh(self, base, mat(Color(0.16, 0.12, 0.09)), Vector3(COLS / 2.0, -0.85, ROWS / 2.0))

	# Portal at the end of the path
	portal = Node3D.new()
	portal.position = to3d(path_points[0])
	add_child(portal)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.28
	ring.outer_radius = 0.42
	var ring_node := add_mesh(portal, ring, mat(Color(0.75, 0.35, 1.0), 2.5), Vector3(0, 0.5, 0))
	ring_node.rotation_degrees.x = 90
	var core := SphereMesh.new()
	core.radius = 0.22
	core.height = 0.44
	add_mesh(portal, core, mat(Color(0.35, 0.1, 0.55), 1.5), Vector3(0, 0.5, 0))
	var portal_light := OmniLight3D.new()
	portal_light.light_color = Color(0.7, 0.35, 1.0)
	portal_light.omni_range = 3.0
	portal_light.light_energy = 1.5
	portal_light.position = Vector3(0, 0.8, 0)
	portal.add_child(portal_light)

	# Range circle and build preview
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 48
	range_disc = add_mesh(self, disc, mat(Color.WHITE, 0.0, 0.07))
	range_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	boom_mesh = SphereMesh.new()
	boom_mesh.radius = 1.0
	boom_mesh.height = 2.0

	# 2D layer for the panel, health bars and lightning
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Node2D.new()
	layer.add_child(hud)
	hud.draw.connect(draw_hud)


func build_tower_node(t: Tower) -> void:
	if t.node != null:
		t.node.queue_free()
	var col: Color = TOWERS[t.type]["color"]
	var root := Node3D.new()
	root.position = to3d(t.pos)
	add_child(root)
	var base := BoxMesh.new()
	base.size = Vector3(0.8, 0.3, 0.8)
	add_mesh(root, base, stone_mat, Vector3(0, 0.15, 0))
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
		"arrow":
			var box := BoxMesh.new()
			box.size = Vector3(0.34, 0.22, 0.34)
			add_mesh(head, box, mat(col))
			var barrel := BoxMesh.new()
			barrel.size = Vector3(0.07, 0.07, 0.4)
			add_mesh(head, barrel, dark_mat, Vector3(0, 0.02, -0.3))
		"cannon":
			var ball := SphereMesh.new()
			ball.radius = 0.24
			ball.height = 0.48
			add_mesh(head, ball, mat(col))
			var barrel := CylinderMesh.new()
			barrel.top_radius = 0.08
			barrel.bottom_radius = 0.1
			barrel.height = 0.45
			add_mesh(head, barrel, dark_mat, Vector3(0, 0.04, -0.28)).rotation_degrees.x = 90
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
	for i in t.level + 1:
		add_mesh(root, pip_mesh, gold_mat, Vector3(-0.3 + i * 0.2, 0.32, 0.36))
	t.node = root
	t.head = head


func update_visuals(delta: float) -> void:
	time += delta
	portal.rotation.y += delta * 1.5
	for e in enemies:
		var r := e.radius / CELL
		e.node.position = to3d(e.pos, -0.08 + r + absf(sin(time * 8.0 + e.bob)) * 0.06)
		e.mat.albedo_color = e.color.lerp(Color(0.55, 0.9, 1.0), 0.55) if e.slow_time > 0.0 else e.color
	for t: Tower in towers.values():
		if t.type == "arrow" or t.type == "cannon":
			t.head.rotation.y = atan2(-t.aim.x, -t.aim.y)
		else:
			t.head.rotation.y += delta * 2.0
	for s in shots:
		s.node.position = to3d(s.pos, 0.6)

	range_disc.visible = false
	ghost.visible = false
	if selected != null:
		show_range(selected.pos, TOWERS[selected.type]["range"][selected.level])
	elif build_type != "" and not mouse_over_panel() and state == "playing":
		var c := mouse_cell()
		if in_map(c):
			ghost.visible = true
			ghost.position = Vector3(c.x + 0.5, 0.05, c.y + 0.5)
			ghost_mat.albedo_color = Color(0.3, 1, 0.3, 0.4) if can_build(c) else Color(1, 0.2, 0.2, 0.4)
			show_range(cell_center(c), TOWERS[build_type]["range"][0])


func show_range(p: Vector2, rng: float) -> void:
	range_disc.visible = true
	range_disc.position = to3d(p, 0.02)
	var s := rng / CELL
	range_disc.scale = Vector3(s, 1, s)


# ---------------------------------------------------------------- waves

func kind_for_wave(w: int) -> String:
	if w % 10 == 0:
		return "boss"
	if w % 5 == 0:
		return "fast"
	if w % 3 == 0:
		return "armored"
	return "normal"


# Starts the next wave. Called by the wave timer, or early by the player (Space),
# which gives 1 bonus gold for every second skipped.
func start_wave() -> void:
	if state != "playing" or wave >= MAX_WAVE:
		return
	var early_bonus := int(maxf(next_wave_timer, 0.0)) if wave > 0 else 0
	wave += 1
	var income := 10 + wave * 2
	gold += income + early_bonus
	if early_bonus > 0:
		flash("Wave %d! +%d gold (+%d for calling early)" % [wave, income, early_bonus])
	else:
		flash("Wave %d! +%d gold" % [wave, income])
	next_wave_timer = WAVE_INTERVAL
	spawn_hp = 25.0 * pow(1.17, wave - 1)
	var kind := kind_for_wave(wave)
	var count := 8 + wave
	if kind == "boss":
		count = 1 + int(wave / 10.0)
	for i in count:
		spawn_queue.append(kind)


# The player calling a wave (Space or the button). Not allowed until every enemy
# of the current wave has spawned.
func call_wave() -> void:
	if not spawn_queue.is_empty():
		flash("Wait until the whole wave has spawned!")
		return
	start_wave()


func spawn_enemy(kind: String) -> void:
	var e := Enemy.new()
	e.pos = path_points[0]
	e.max_hp = spawn_hp
	e.bounty = 2 + int(wave / 4.0)
	e.color = Color(0.95, 0.5, 0.6)
	match kind:
		"fast":
			e.max_hp *= 0.6
			e.speed *= 1.7
			e.radius = 8.0
			e.color = Color(1.0, 0.9, 0.3)
		"armored":
			e.max_hp *= 1.3
			e.armor = 2.0 + wave * 0.6
			e.radius = 11.0
			e.color = Color(0.6, 0.65, 0.75)
		"boss":
			e.max_hp *= 15.0
			e.speed *= 0.7
			e.radius = 18.0
			e.bounty = 40 + wave * 4
			e.weight = 5
			e.color = Color(0.9, 0.15, 0.15)
	e.hp = e.max_hp

	var r := e.radius / CELL
	var ball := SphereMesh.new()
	ball.radius = r
	ball.height = r * 2.0
	e.mat = mat(e.color)
	if kind == "armored":
		e.mat.metallic = 0.8
		e.mat.roughness = 0.3
	e.node = add_mesh(self, ball, e.mat, to3d(e.pos, r))
	if kind == "boss":
		var crown := TorusMesh.new()
		crown.inner_radius = 0.1
		crown.outer_radius = 0.17
		add_mesh(e.node, crown, gold_mat, Vector3(0, r * 0.95, 0))
	e.bob = randf() * TAU
	enemies.append(e)


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	if paused or update_dialog != "":
		update_visuals(0.0)
		hud.queue_redraw()
		return
	message_time = maxf(message_time - delta, 0.0)
	update_effects(delta)
	if state == "playing":
		var dt := delta * game_speed
		if wave > 0 and wave < MAX_WAVE:
			next_wave_timer -= dt
			if next_wave_timer <= 0.0:
				start_wave()
		update_spawning(dt)
		update_enemies(dt)
		update_towers(dt)
		update_shots(dt)
		remove_dead()
		if alive_count() >= MAX_ALIVE:
			state = "lost"
		elif wave >= MAX_WAVE and spawn_queue.is_empty() and enemies.is_empty():
			state = "won"
	update_camera(delta)
	update_visuals(delta)
	hud.queue_redraw()


# Moves the camera with WASD (by key position, so it works on any keyboard layout).
func update_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		dir.y += 1
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1
	if dir == Vector2.ZERO:
		return
	var move := dir.normalized() * CAMERA_SPEED * delta
	camera.position.x = clampf(camera.position.x + move.x, camera_home.x - CAMERA_LIMIT.x, camera_home.x + CAMERA_LIMIT.x)
	camera.position.z = clampf(camera.position.z + move.y, camera_home.z - CAMERA_LIMIT.y, camera_home.z + CAMERA_LIMIT.y)


func alive_count() -> int:
	var n := 0
	for e in enemies:
		n += e.weight
	return n


func update_spawning(dt: float) -> void:
	if spawn_queue.is_empty():
		return
	spawn_timer -= dt
	if spawn_timer <= 0.0:
		var kind: String = spawn_queue.pop_front()
		spawn_enemy(kind)
		match kind:
			"boss": spawn_timer = 2.0
			"fast": spawn_timer = 0.45
			_: spawn_timer = 0.7


func update_enemies(dt: float) -> void:
	for e in enemies:
		if e.slow_time > 0.0:
			e.slow_time -= dt
			if e.slow_time <= 0.0:
				e.slow_factor = 1.0
		var move := e.speed * e.slow_factor * dt
		while move > 0.0:
			var target := path_points[e.wp]
			var d := e.pos.distance_to(target)
			if d <= move:
				e.pos = target
				e.traveled += d
				move -= d
				e.wp += 1
				# After the last corner, go around the square again
				if e.wp >= path_points.size():
					e.wp = loop_start
			else:
				e.pos += (target - e.pos) / d * move
				e.traveled += move
				move = 0.0


func update_towers(dt: float) -> void:
	for t: Tower in towers.values():
		t.cooldown -= dt
		if t.cooldown > 0.0:
			continue
		var data: Dictionary = TOWERS[t.type]
		var target := find_target(t.pos, data["range"][t.level])
		if target == null:
			continue
		t.aim = (target.pos - t.pos).normalized()
		t.cooldown = data["cooldown"][t.level]
		if t.type == "spark":
			fire_lightning(t, target)
		else:
			var s := Shot.new()
			s.pos = t.pos + t.aim * 14.0
			s.target = target
			s.target_pos = target.pos
			s.type = t.type
			s.level = t.level
			if t.type == "cannon":
				s.speed = 300.0
			if not shot_mats.has(t.type):
				shot_mats[t.type] = mat(data["color"], 2.0)
			var ball := SphereMesh.new()
			ball.radius = 0.12 if t.type == "cannon" else 0.07
			ball.height = ball.radius * 2.0
			s.node = add_mesh(self, ball, shot_mats[t.type], to3d(s.pos, 0.6))
			shots.append(s)


# Picks the enemy in range that is furthest along the path.
func find_target(from: Vector2, rng: float) -> Enemy:
	var best: Enemy = null
	for e in enemies:
		if not e.dead and e.pos.distance_to(from) <= rng:
			if best == null or e.traveled > best.traveled:
				best = e
	return best


func fire_lightning(t: Tower, first: Enemy) -> void:
	var data: Dictionary = TOWERS["spark"]
	var dmg: float = data["damage"][t.level]
	var hit: Array[Enemy] = [first]
	var points := PackedVector3Array([t.node.position + t.head.position + Vector3(0, 0.1, 0), first.node.position])
	damage_enemy(first, dmg)
	var current := first
	for i in range(data["chain"][t.level] - 1):
		dmg *= 0.8
		var next: Enemy = null
		var best_dist := 110.0
		for e in enemies:
			if e.dead or hit.has(e):
				continue
			var d := e.pos.distance_to(current.pos)
			if d < best_dist:
				best_dist = d
				next = e
		if next == null:
			break
		hit.append(next)
		points.append(next.node.position)
		damage_enemy(next, dmg)
		current = next
	effects.append({"kind": "bolt", "points": points, "time": 0.15, "max": 0.15})


func update_shots(dt: float) -> void:
	for s in shots:
		if s.target != null and not s.target.dead:
			s.target_pos = s.target.pos
		var to := s.target_pos - s.pos
		var step := s.speed * dt
		if to.length() <= step:
			s.pos = s.target_pos
			shot_hit(s)
			s.done = true
		else:
			s.pos += to.normalized() * step
	for i in range(shots.size() - 1, -1, -1):
		if shots[i].done:
			shots[i].node.queue_free()
			shots.remove_at(i)


func shot_hit(s: Shot) -> void:
	var data: Dictionary = TOWERS[s.type]
	var dmg: float = data["damage"][s.level]
	var alive := s.target != null and not s.target.dead
	match s.type:
		"cannon":
			var r: float = data["splash"][s.level]
			for e in enemies:
				if not e.dead and e.pos.distance_to(s.pos) <= r:
					damage_enemy(e, dmg)
			var m := mat(Color(1.0, 0.55, 0.15), 1.5, 0.5)
			var node := add_mesh(self, boom_mesh, m, to3d(s.pos, 0.2))
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.scale = Vector3.ZERO
			effects.append({"kind": "boom", "node": node, "mat": m, "radius": r, "time": 0.3, "max": 0.3})
		"frost":
			if alive:
				var slow: float = data["slow"][s.level]
				s.target.slow_factor = minf(s.target.slow_factor, slow)
				s.target.slow_time = 2.0
				damage_enemy(s.target, dmg)
		_:
			if alive:
				damage_enemy(s.target, dmg)


func damage_enemy(e: Enemy, amount: float) -> void:
	if e.dead:
		return
	# Armor removes a flat amount, but at least 25% of the hit always goes through.
	e.hp -= maxf(amount - e.armor, amount * 0.25)
	if e.hp <= 0.0:
		e.dead = true
		gold += e.bounty


func remove_dead() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].dead:
			enemies[i].node.queue_free()
			enemies.remove_at(i)


func update_effects(delta: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		var fx: Dictionary = effects[i]
		fx["time"] -= delta
		if fx["time"] <= 0.0:
			if fx.has("node"):
				fx["node"].queue_free()
			effects.remove_at(i)
		elif fx["kind"] == "boom":
			var a: float = fx["time"] / fx["max"]
			var size: float = fx["radius"] / CELL * (1.2 - a * 0.4)
			var node: MeshInstance3D = fx["node"]
			var m: StandardMaterial3D = fx["mat"]
			node.scale = Vector3(size, size * 0.6, size)
			m.albedo_color = Color(m.albedo_color, a * 0.5)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if update_dialog != "":
		dialog_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggle_pause()
		return
	if paused:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			build_type = ""
			selected = null
		elif event.button_index == MOUSE_BUTTON_LEFT:
			on_click(get_viewport().get_mouse_position())
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				choose_build(TOWER_TYPES[event.keycode - KEY_1])
			KEY_SPACE:
				call_wave()
			KEY_U:
				upgrade_selected()
			KEY_X, KEY_DELETE:
				sell_selected()
			KEY_F:
				toggle_speed()
			KEY_R:
				if state != "playing":
					new_game()


func on_click(p: Vector2) -> void:
	if state != "playing":
		return
	if p.x >= PANEL_LEFT:
		for i in TOWER_TYPES.size():
			if tower_button_rect(i).has_point(p):
				choose_build(TOWER_TYPES[i])
		if selected != null and UPGRADE_RECT.has_point(p):
			upgrade_selected()
		if selected != null and SELL_RECT.has_point(p):
			sell_selected()
		if WAVE_RECT.has_point(p):
			call_wave()
		if SPEED_RECT.has_point(p):
			toggle_speed()
		if update_version != "" and UPDATE_RECT.has_point(p):
			update_dialog = "ask"
			build_type = ""
		return
	var c := mouse_cell()
	if towers.has(c):
		selected = towers[c]
		build_type = ""
	elif build_type != "":
		try_build(c)
	else:
		selected = null


func dialog_input(event: InputEvent) -> void:
	if update_dialog == "downloading":
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		update_dialog = ""
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := get_viewport().get_mouse_position()
		if DIALOG_YES_RECT.has_point(p):
			if update_dialog == "ask":
				start_update()
			else:
				OS.shell_open(update_url)
				update_dialog = ""
		elif DIALOG_NO_RECT.has_point(p):
			update_dialog = ""


func choose_build(type: String) -> void:
	build_type = type
	selected = null


func try_build(c: Vector2i) -> void:
	if not can_build(c):
		return
	var cost: int = TOWERS[build_type]["cost"][0]
	if gold < cost:
		flash("Not enough gold")
		return
	var t := Tower.new()
	t.type = build_type
	t.cell = c
	t.pos = cell_center(c)
	t.spent = cost
	gold -= cost
	towers[c] = t
	build_tower_node(t)


func upgrade_selected() -> void:
	if selected == null:
		return
	if selected.level >= 3:
		flash("Already max level")
		return
	var cost: int = TOWERS[selected.type]["cost"][selected.level + 1]
	if gold < cost:
		flash("Not enough gold")
		return
	gold -= cost
	selected.spent += cost
	selected.level += 1
	build_tower_node(selected)


func sell_selected() -> void:
	if selected == null:
		return
	gold += int(selected.spent * 0.7)
	selected.node.queue_free()
	towers.erase(selected.cell)
	selected = null


func toggle_speed() -> void:
	game_speed = game_speed % 3 + 1


func toggle_pause() -> void:
	if state != "playing":
		return
	paused = not paused
	build_type = ""


# ---------------------------------------------------------------- 2D overlay

func draw_hud() -> void:
	draw_health_bars()
	for fx in effects:
		if fx["kind"] == "bolt":
			var pts := PackedVector2Array()
			for p in fx["points"]:
				pts.append(camera.unproject_position(p))
			var a: float = fx["time"] / fx["max"]
			hud.draw_polyline(pts, Color(0.75, 0.5, 1.0, a * 0.5), 7.0)
			hud.draw_polyline(pts, Color(0.95, 0.9, 1.0, a), 2.5)
	draw_panel()
	if state != "playing":
		draw_end_screen()
	elif paused:
		draw_pause_screen()
	if update_dialog != "":
		draw_update_dialog()


func draw_update_dialog() -> void:
	var d := DIALOG_RECT
	var left := d.position.x + 30
	hud.draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.6))
	hud.draw_rect(d, Color(0.12, 0.13, 0.17))
	hud.draw_rect(d, Color(0.45, 0.48, 0.55), false, 2.0)
	text(Vector2(left, d.position.y + 50), "New version %s is out!" % update_version, 28, Color(1, 0.85, 0.3))
	text(Vector2(left, d.position.y + 76), "You have v%s" % version, 15, Color(0.6, 0.6, 0.65))
	match update_dialog:
		"ask":
			text(Vector2(left, d.position.y + 116), "What's new", 18)
			var notes := update_notes if update_notes != "" else "No details for this update."
			hud.draw_multiline_string(font, Vector2(left, d.position.y + 146), notes, HORIZONTAL_ALIGNMENT_LEFT, d.size.x - 60, 16, 9, Color(0.85, 0.85, 0.9))
			text(Vector2(left, DIALOG_YES_RECT.position.y - 20), "Do you want to update now?", 18)
			button(DIALOG_YES_RECT, "Yes, update", true, true)
			button(DIALOG_NO_RECT, "No, not now")
		"downloading":
			var done := 0.0
			if update_http != null and update_http.get_body_size() > 0:
				done = float(update_http.get_downloaded_bytes()) / update_http.get_body_size()
			text(Vector2(left, d.position.y + 160), "Downloading update... %d%%" % int(done * 100), 20)
			var bar := Rect2(left, d.position.y + 185, d.size.x - 60, 20)
			hud.draw_rect(bar, Color(0.2, 0.2, 0.25))
			hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * done, bar.size.y)), Color(0.3, 0.75, 0.4))
			text(Vector2(left, d.position.y + 240), "The game will restart by itself when it's done.", 16, Color(0.7, 0.7, 0.75))
		"failed":
			text(Vector2(left, d.position.y + 150), "The update didn't work.", 20, Color(1, 0.45, 0.45))
			hud.draw_multiline_string(font, Vector2(left, d.position.y + 185), update_error, HORIZONTAL_ALIGNMENT_LEFT, d.size.x - 60, 16, 4, Color(0.85, 0.85, 0.9))
			text(Vector2(left, d.position.y + 260), "You can download it from GitHub instead.", 16, Color(0.7, 0.7, 0.75))
			button(DIALOG_YES_RECT, "Open download page", true, true)
			button(DIALOG_NO_RECT, "Close")


func draw_health_bars() -> void:
	for e in enemies:
		var r := e.radius / CELL
		var p := camera.unproject_position(e.node.position + Vector3(0, r + 0.25, 0))
		var w := e.radius * 2.4
		var bar := Vector2(p.x - w / 2.0, p.y)
		hud.draw_rect(Rect2(bar, Vector2(w, 4)), Color(0.3, 0, 0))
		hud.draw_rect(Rect2(bar, Vector2(w * e.hp / e.max_hp, 4)), Color(0.2, 0.9, 0.2))


func text(pos: Vector2, s: String, size := 16, col := Color.WHITE) -> void:
	hud.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func button(r: Rect2, label: String, enabled := true, active := false) -> void:
	var bg := Color(0.22, 0.24, 0.3)
	if active:
		bg = Color(0.3, 0.4, 0.55)
	elif not enabled:
		bg = Color(0.15, 0.15, 0.18)
	hud.draw_rect(r, bg)
	hud.draw_rect(r, Color(0.45, 0.48, 0.55), false, 1.0)
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var col := Color.WHITE if enabled else Color(0.5, 0.5, 0.5)
	text(r.position + Vector2((r.size.x - size.x) / 2.0, r.size.y / 2.0 + 6.0), label, 16, col)


func draw_panel() -> void:
	hud.draw_rect(Rect2(PANEL_LEFT, 0, SCREEN_W - PANEL_LEFT, SCREEN_H), Color(0.09, 0.09, 0.12))
	text(Vector2(PANEL_X, 36), "WAVE %d / %d" % [wave, MAX_WAVE], 26)
	text(Vector2(PANEL_X + 250, 34), "v" + version, 13, Color(0.5, 0.5, 0.55))
	# How close you are to losing: green when few monsters are alive, red near the limit
	var alive := alive_count()
	var danger := clampf(float(alive) / MAX_ALIVE, 0.0, 1.0)
	var danger_col := Color(0.4, 0.9, 0.4).lerp(Color(1, 0.3, 0.3), danger)
	text(Vector2(PANEL_X, 66), "Alive: %d / %d" % [alive, MAX_ALIVE], 20, danger_col)
	text(Vector2(PANEL_X + 170, 66), "Gold: %d" % gold, 20, Color(1, 0.85, 0.3))
	hud.draw_rect(Rect2(PANEL_X, 74, 288, 6), Color(0.2, 0.2, 0.25))
	hud.draw_rect(Rect2(PANEL_X, 74, 288 * danger, 6), danger_col)
	var next_text: String
	if wave == 0:
		next_text = "First wave: %s" % kind_for_wave(1).capitalize()
	elif wave < MAX_WAVE:
		next_text = "Next wave: %s in %ds" % [kind_for_wave(wave + 1).capitalize(), ceili(next_wave_timer)]
	else:
		next_text = "Last wave! Kill them all"
	text(Vector2(PANEL_X, 104), next_text, 16, Color(0.75, 0.75, 0.8))
	text(Vector2(PANEL_X, 136), "Build (keys 1-4)", 14, Color(0.6, 0.6, 0.65))

	for i in TOWER_TYPES.size():
		var type: String = TOWER_TYPES[i]
		var data: Dictionary = TOWERS[type]
		var r := tower_button_rect(i)
		var affordable: bool = gold >= data["cost"][0]
		hud.draw_rect(r, Color(0.3, 0.4, 0.55) if build_type == type else Color(0.17, 0.18, 0.23))
		hud.draw_rect(r, Color(0.45, 0.48, 0.55), false, 1.0)
		hud.draw_circle(r.position + Vector2(28, 28), 13.0, data["color"])
		var name_col := Color.WHITE if affordable else Color(0.55, 0.55, 0.55)
		text(r.position + Vector2(52, 24), "%d. %s" % [i + 1, data["name"]], 18, name_col)
		text(r.position + Vector2(220, 24), "%dg" % data["cost"][0], 18, Color(1, 0.85, 0.3) if affordable else Color(0.6, 0.4, 0.3))
		text(r.position + Vector2(52, 46), data["desc"], 14, Color(0.7, 0.7, 0.75))

	if selected != null:
		var data: Dictionary = TOWERS[selected.type]
		var lv := selected.level
		text(Vector2(PANEL_X, 418), "%s  -  Level %d" % [data["name"], lv + 1], 20, data["color"])
		text(Vector2(PANEL_X, 444), "Damage %d   Range %d   Speed %.2fs" % [data["damage"][lv], data["range"][lv], data["cooldown"][lv]], 14)
		if lv < 3:
			text(Vector2(PANEL_X, 466), "Next: Damage %d   Range %d" % [data["damage"][lv + 1], data["range"][lv + 1]], 14, Color(0.6, 0.9, 0.6))
			var cost: int = data["cost"][lv + 1]
			button(UPGRADE_RECT, "Upgrade %dg (U)" % cost, gold >= cost)
		else:
			button(UPGRADE_RECT, "Max level", false)
		button(SELL_RECT, "Sell %dg (X)" % int(selected.spent * 0.7))
	else:
		text(Vector2(PANEL_X, 430), "Click a tower to upgrade or sell it.", 14, Color(0.6, 0.6, 0.65))

	if update_version != "":
		button(UPDATE_RECT, "New version %s - Update" % update_version, true, true)

	if message_time > 0.0:
		text(Vector2(PANEL_X, 590), message, 16, Color(1, 1, 0.6, minf(message_time, 1.0)))

	var wave_label: String
	if wave == 0:
		wave_label = "Start (SPACE)"
	elif wave < MAX_WAVE and not spawn_queue.is_empty():
		wave_label = "Spawning... (%d left)" % spawn_queue.size()
	elif wave < MAX_WAVE:
		wave_label = "Send now +%dg (SPACE)" % int(maxf(next_wave_timer, 0.0))
	else:
		wave_label = "No more waves"
	button(WAVE_RECT, wave_label, wave < MAX_WAVE and state == "playing" and spawn_queue.is_empty())
	button(SPEED_RECT, "x%d (F)" % game_speed, true, game_speed > 1)
	text(Vector2(PANEL_X, 676), "WASD: move camera", 13, Color(0.55, 0.55, 0.6))
	text(Vector2(PANEL_X, 696), "Right-click: cancel   Esc: pause", 13, Color(0.55, 0.55, 0.6))


func draw_pause_screen() -> void:
	hud.draw_rect(Rect2(0, 0, PANEL_LEFT, SCREEN_H), Color(0, 0, 0, 0.5))
	var size := font.get_string_size("PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 64)
	text(Vector2((PANEL_LEFT - size.x) / 2.0, 340), "PAUSED", 64)
	size = font.get_string_size("Press Esc to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	text(Vector2((PANEL_LEFT - size.x) / 2.0, 385), "Press Esc to continue", 20, Color(0.8, 0.8, 0.8))


func draw_end_screen() -> void:
	hud.draw_rect(Rect2(0, 0, PANEL_LEFT, SCREEN_H), Color(0, 0, 0, 0.6))
	var title := "VICTORY!" if state == "won" else "GAME OVER"
	var sub := "You survived all %d waves." % MAX_WAVE if state == "won" else "Too many monsters! You reached wave %d." % wave
	var size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64)
	text(Vector2((PANEL_LEFT - size.x) / 2.0, 320), title, 64, Color(1, 0.85, 0.3) if state == "won" else Color(1, 0.35, 0.35))
	size = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	text(Vector2((PANEL_LEFT - size.x) / 2.0, 370), sub, 22)
	size = font.get_string_size("Press R to play again", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	text(Vector2((PANEL_LEFT - size.x) / 2.0, 410), "Press R to play again", 18, Color(0.8, 0.8, 0.8))
