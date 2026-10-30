extends Node3D
## Gettic's first TD - a small 3D tower defense game.
## Monsters come out of a gate at each player's corner and walk around a square.
## Up to 4 players can play together over the network (see "multiplayer").
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
const CAMERA_H_OFFSET := 4.4  # shifts the view so the map is centered left of the side panel
const ZOOM_MIN := 0.35  # closest zoom (fraction of the starting distance)
const ZOOM_MAX := 1.3   # furthest zoom
const ZOOM_STEP := 0.1  # how much one scroll-wheel notch zooms
const MAX_WAVE := 30
const START_GOLD := 150
const MAX_ALIVE := 50  # per player: you lose when this many monsters are alive at once (a boss counts as 5)
const WAVE_INTERVAL := 25.0  # seconds between waves once the game has started

# The path in grid coordinates. The square's corners, clockwise. Monsters walk
# around the square forever.
const LOOP := [Vector2i(2, 15), Vector2i(2, 2), Vector2i(21, 2), Vector2i(21, 15)]
# Each player has a gate just outside one corner of the square (player 1 uses
# GATES[0]). Its monsters walk from the gate into that corner, then join the loop.
const GATES := [Vector2i(2, 17), Vector2i(0, 2), Vector2i(21, 0), Vector2i(23, 15)]
const MAX_PLAYERS := 4
const PLAYER_NAMES := ["Blue", "Red", "Yellow", "Pink"]
const PLAYER_COLORS := [Color(0.3, 0.55, 1.0), Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.8)]
const ENEMY_KINDS := ["normal", "fast", "armored", "boss"]

# Multiplayer: the host's game runs everything, the others send it their actions
const NET_PORT := 24750
const SEARCH_PORT := 24751  # the host listens here for players looking for its short code
const SNAPSHOT_RATE := 15.0  # monster updates per second sent to the other players
const CODE_LETTERS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # for invite codes (no I, L, O or U)

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

# Esc menu layout (screen pixels)
const MENU_RECT := Rect2(230, 60, 500, 620)
const HOST_RECT := Rect2(270, 198, 420, 44)
const JOIN_INPUT_RECT := Rect2(270, 292, 290, 40)
const JOIN_BUTTON_RECT := Rect2(570, 292, 120, 40)
const COPY_RECT := Rect2(570, 226, 120, 40)
const COPY_LONG_RECT := Rect2(570, 330, 120, 32)
const STOP_RECT := Rect2(270, 560, 420, 40)
const RESUME_RECT := Rect2(270, 616, 420, 44)

# Update popup layout (screen pixels)
const DIALOG_RECT := Rect2(340, 140, 600, 440)
const DIALOG_YES_RECT := Rect2(380, 506, 250, 44)
const DIALOG_NO_RECT := Rect2(650, 506, 250, 44)

# Checked at startup to see if a newer release is on GitHub
const RELEASES_API := "https://api.github.com/repos/gettic/Gettics-first-TD/releases/latest"


class Enemy:
	var id := 0  # the same on every player's computer
	var kind := "normal"
	var pos: Vector2
	var net_pos: Vector2  # other players: latest position from the host, pos glides toward it
	var route: Array[Vector2]  # this monster's gate, then the square's corners from where it joins
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
	var owner := 0  # player slot (0-3) that built it and gets the gold for its kills
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
	var owner := 0
	var visual := false  # other players' copy of a host's shot: just for show, does no damage
	var speed := 420.0
	var done := false
	var node: MeshInstance3D


class Player:
	var peer := 1  # network id; the host is always 1
	var slot := 0  # 0-3: which gate and color
	var gold := 0


var path_cells := {}
var routes: Array = []  # per gate: Array[Vector2] of points, gate first
var enemies: Array[Enemy] = []
var enemy_by_id := {}
var next_enemy_id := 1
var towers := {}  # Vector2i -> Tower
var shots: Array[Shot] = []
var effects := []  # Dictionaries: bolts and explosions

var players: Array = [null, null, null, null]  # Player per slot, null = free
var local_slot := 0  # this computer's player
# This computer's gold
var gold: int:
	get:
		return players[local_slot].gold if players[local_slot] != null else 0
	set(value):
		if players[local_slot] != null:
			players[local_slot].gold = value
var next_wave_timer := 0.0
var wave := 0
var spawn_queues: Array = [[], [], [], []]  # monster kinds still to come out of each gate
var spawn_timers := [0.0, 0.0, 0.0, 0.0]
var spawn_hp := 0.0
var net_spawn_left := 0  # other players: monsters still to spawn, from the host
var build_type := ""
var selected: Tower = null
var game_speed := 1
var state := "playing"  # "playing", "won" or "lost"
var menu_open := false  # the Esc menu; it only pauses the game when playing alone

# Multiplayer
var net_mode := ""  # "" alone, "host", "searching", "connecting" or "client"
var net_addresses: Array = []  # client: the host's addresses, tried in order
var net_connect_time := 0.0
var net_status := ""  # shown in the menu
var short_code := ""  # host: 5 letters, found by searching the local network
var invite_code := ""  # host: long code with the internet address, if the router allowed it
var search_peer: PacketPeerUDP  # host: answers searches; player: sends them
var search_time := 0.0
var search_send_timer := 0.0
var search_code := ""
var search_found: Array = []  # addresses of hosts that answered
var snapshot_timer := 0.0
var upnp: UPNP  # host: the router port opening, removed again when hosting stops
var upnp_thread: Thread
var code_input: LineEdit
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
var camera_focus: Vector3       # the ground point the camera looks at when not moved
var camera_pan := Vector2.ZERO  # how far WASD has moved the camera
var zoom := 1.0
var target_zoom := 1.0
var hud: Node2D
var gate_parts: Array = []  # per gate: the portal pieces that only show while a player uses that gate
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
	# Each gate's route: the gate, then all four corners starting where it joins the square
	for g in GATES.size():
		var route: Array[Vector2] = [cell_center(GATES[g])]
		for i in LOOP.size():
			route.append(cell_center(LOOP[(g + i) % LOOP.size()]))
		routes.append(route)
		mark_path(GATES[g], LOOP[g])
	for i in LOOP.size():
		mark_path(LOOP[i], LOOP[(i + 1) % LOOP.size()])
	build_world()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_host)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_host_left)
	play_alone()
	check_for_update()


# Marks the tiles on a straight line from a to b as path.
func mark_path(a: Vector2i, b: Vector2i) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var c := a
	while true:
		path_cells[c] = true
		if c == b:
			break
		c += step


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
	clear_world()
	for p in players:
		if p != null:
			p.gold = START_GOLD
	wave = 0
	next_wave_timer = 0.0
	game_speed = 1
	state = "playing"
	menu_open = false
	send_all("net_reset", [])
	flash("Build towers, then press SPACE to start")


# Removes all towers, monsters and effects.
func clear_world() -> void:
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
	enemy_by_id.clear()
	towers.clear()
	shots.clear()
	effects.clear()
	for q in spawn_queues:
		q.clear()
	build_type = ""
	selected = null


# A fresh single-player game (at startup, or after leaving a multiplayer game).
func play_alone() -> void:
	players = [null, null, null, null]
	var me := Player.new()
	players[0] = me
	local_slot = 0
	new_game()


func player_count() -> int:
	return MAX_PLAYERS - players.count(null)


# The loss limit grows with the number of players, like the waves do.
func max_alive() -> int:
	return MAX_ALIVE * player_count()


func monsters_left_to_spawn() -> int:
	if net_mode == "client":
		return net_spawn_left
	var n := 0
	for q in spawn_queues:
		n += q.size()
	return n


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

	# Text box in the Esc menu for typing an invite code
	code_input = LineEdit.new()
	code_input.position = JOIN_INPUT_RECT.position
	code_input.size = JOIN_INPUT_RECT.size
	code_input.placeholder_text = "Invite code"
	code_input.max_length = 40
	code_input.add_theme_font_size_override("font_size", 18)
	code_input.visible = false
	code_input.text_submitted.connect(func(_t: String) -> void: join_game())
	layer.add_child(code_input)


func build_tower_node(t: Tower) -> void:
	if t.node != null:
		t.node.queue_free()
	var col: Color = TOWERS[t.type]["color"]
	var root := Node3D.new()
	root.position = to3d(t.pos)
	add_child(root)
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
	for g in gate_parts.size():
		var in_use: bool = players[g] != null
		for part in gate_parts[g].values():
			part.visible = in_use
		gate_parts[g]["sparks"].rotation.z += delta * 2.0
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
	# Every player gets the wave income, and every player's gate sends a full wave
	for p in players:
		if p != null:
			p.gold += income + early_bonus
	var text := "Wave %d! +%d gold" % [wave, income]
	if early_bonus > 0:
		text = "Wave %d! +%d gold (+%d for calling early)" % [wave, income, early_bonus]
	flash(text)
	send_all("net_message", [text])
	next_wave_timer = WAVE_INTERVAL
	spawn_hp = 25.0 * pow(1.17, wave - 1)
	var kind := kind_for_wave(wave)
	var count := 8 + wave
	if kind == "boss":
		count = 1 + int(wave / 10.0)
	for g in MAX_PLAYERS:
		if players[g] != null:
			for i in count:
				spawn_queues[g].append(kind)


# A player calling the next wave early (Space or the button). Not allowed until
# every monster of the current wave has spawned. Returns an error message, or "".
func call_wave() -> String:
	if monsters_left_to_spawn() > 0:
		return "Wait until the whole wave has spawned!"
	start_wave()
	return ""


# Host: a new monster at gate g.
func spawn_enemy(kind: String, g: int) -> void:
	var e := make_enemy(kind)
	e.id = next_enemy_id
	next_enemy_id += 1
	e.route = routes[g]
	e.pos = e.route[0]
	e.max_hp = spawn_hp
	e.bounty = 2 + int(wave / 4.0)
	match kind:
		"fast":
			e.max_hp *= 0.6
			e.speed *= 1.7
		"armored":
			e.max_hp *= 1.3
			e.armor = 2.0 + wave * 0.6
		"boss":
			e.max_hp *= 15.0
			e.speed *= 0.7
			e.bounty = 40 + wave * 4
			e.weight = 5
	e.hp = e.max_hp
	enemies.append(e)
	enemy_by_id[e.id] = e


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
	return e


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	code_input.visible = menu_open and net_mode == ""
	if net_mode == "searching":
		update_search(delta)
	elif net_mode == "connecting":
		net_connect_time += delta
		if net_connect_time > 4.0:
			try_next_address()
	elif net_mode == "host" and search_peer != null:
		answer_searches()
	# Playing alone, the menu and the update popup pause the game. In multiplayer it keeps going.
	if (menu_open and net_mode == "") or (update_dialog != "" and net_mode == ""):
		update_visuals(0.0)
		hud.queue_redraw()
		return
	message_time = maxf(message_time - delta, 0.0)
	update_effects(delta)
	var dt := delta * game_speed
	if net_mode == "client":
		# The host runs the game. Here monsters just glide to where the host says
		# they are, and shots fly for show.
		if state == "playing" and wave > 0:
			next_wave_timer = maxf(next_wave_timer - dt, 0.0)
		for e in enemies:
			e.pos = e.pos.lerp(e.net_pos, minf(delta * 12.0, 1.0))
		update_shots(dt)
	elif state == "playing":
		if wave > 0 and wave < MAX_WAVE:
			next_wave_timer -= dt
			if next_wave_timer <= 0.0:
				start_wave()
		update_spawning(dt)
		update_enemies(dt)
		update_towers(dt)
		update_shots(dt)
		remove_dead()
		if alive_count() >= max_alive():
			state = "lost"
		elif wave >= MAX_WAVE and monsters_left_to_spawn() == 0 and enemies.is_empty():
			state = "won"
	if net_mode == "host":
		snapshot_timer -= delta
		if snapshot_timer <= 0.0:
			snapshot_timer = 1.0 / SNAPSHOT_RATE
			send_snapshot()
	update_camera(delta)
	update_visuals(delta)
	hud.queue_redraw()


# Moves the camera with WASD (by key position, so it works on any keyboard layout)
# and glides it toward the zoom level set with the scroll wheel.
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
	if dir != Vector2.ZERO:
		# Move slower when zoomed in, so it doesn't feel too fast up close
		camera_pan += dir.normalized() * CAMERA_SPEED * zoom * delta
		camera_pan = camera_pan.clamp(-CAMERA_LIMIT, CAMERA_LIMIT)
	zoom = lerpf(zoom, target_zoom, 1.0 - exp(-12.0 * delta))
	# Zooming slides the camera along the line it looks down, so the angle stays the same
	var pan := Vector3(camera_pan.x, 0.0, camera_pan.y)
	camera.position = camera_focus + pan + (camera_home - camera_focus) * zoom
	camera.h_offset = CAMERA_H_OFFSET * zoom


func zoom_camera(steps: float) -> void:
	target_zoom = clampf(target_zoom + steps * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


func alive_count() -> int:
	var n := 0
	for e in enemies:
		n += e.weight
	return n


func update_spawning(dt: float) -> void:
	for g in MAX_PLAYERS:
		var queue: Array = spawn_queues[g]
		if queue.is_empty():
			continue
		spawn_timers[g] -= dt
		if spawn_timers[g] <= 0.0:
			var kind: String = queue.pop_front()
			spawn_enemy(kind, g)
			match kind:
				"boss": spawn_timers[g] = 2.0
				"fast": spawn_timers[g] = 0.45
				_: spawn_timers[g] = 0.7


func update_enemies(dt: float) -> void:
	for e in enemies:
		if e.slow_time > 0.0:
			e.slow_time -= dt
			if e.slow_time <= 0.0:
				e.slow_factor = 1.0
		var move := e.speed * e.slow_factor * dt
		while move > 0.0:
			var target := e.route[e.wp]
			var d := e.pos.distance_to(target)
			if d <= move:
				e.pos = target
				e.traveled += d
				move -= d
				e.wp += 1
				# After the last corner, go around the square again (route[1] is the first corner)
				if e.wp >= e.route.size():
					e.wp = 1
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
			launch_shot(t, target, false)
			send_all("net_shot", [t.cell, target.id])


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
	damage_enemy(first, dmg, t.owner)
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
		damage_enemy(next, dmg, t.owner)
		current = next
	add_bolt(points)
	send_all("net_bolt", [points])


func add_bolt(points: PackedVector3Array) -> void:
	effects.append({"kind": "bolt", "points": points, "time": 0.15, "max": 0.15})


func update_shots(dt: float) -> void:
	for s in shots:
		if s.target != null and not s.target.dead:
			s.target_pos = s.target.pos
		var to := s.target_pos - s.pos
		var step := s.speed * dt
		if to.length() <= step:
			s.pos = s.target_pos
			if not s.visual:
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
					damage_enemy(e, dmg, s.owner)
			add_boom(s.pos, r)
			send_all("net_boom", [s.pos, r])
		"frost":
			if alive:
				var slow: float = data["slow"][s.level]
				s.target.slow_factor = minf(s.target.slow_factor, slow)
				s.target.slow_time = 2.0
				damage_enemy(s.target, dmg, s.owner)
		_:
			if alive:
				damage_enemy(s.target, dmg, s.owner)


func add_boom(pos: Vector2, r: float) -> void:
	var m := mat(Color(1.0, 0.55, 0.15), 1.5, 0.5)
	var node := add_mesh(self, boom_mesh, m, to3d(pos, 0.2))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3.ZERO
	effects.append({"kind": "boom", "node": node, "mat": m, "radius": r, "time": 0.3, "max": 0.3})


# The gold for a kill goes to the player who owns the tower that made it.
func damage_enemy(e: Enemy, amount: float, owner_slot: int) -> void:
	if e.dead:
		return
	# Armor removes a flat amount, but at least 25% of the hit always goes through.
	e.hp -= maxf(amount - e.armor, amount * 0.25)
	if e.hp <= 0.0:
		e.dead = true
		if players[owner_slot] != null:
			players[owner_slot].gold += e.bounty


func remove_dead() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].dead:
			enemies[i].node.queue_free()
			enemy_by_id.erase(enemies[i].id)
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
		toggle_menu()
		return
	if menu_open:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			menu_click(get_viewport().get_mouse_position())
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			build_type = ""
			selected = null
		elif event.button_index == MOUSE_BUTTON_LEFT:
			on_click(get_viewport().get_mouse_position())
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and not mouse_over_panel():
			zoom_camera(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not mouse_over_panel():
			zoom_camera(1.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				choose_build(TOWER_TYPES[event.keycode - KEY_1])
			KEY_SPACE:
				act("wave", [])
			KEY_U:
				upgrade_selected()
			KEY_X, KEY_DELETE:
				sell_selected()
			KEY_F:
				act("speed", [])
			KEY_R:
				if state != "playing":
					act("restart", [])


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
			act("wave", [])
		if SPEED_RECT.has_point(p):
			act("speed", [])
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
	if can_build(c):
		act("build", [c, build_type])


func upgrade_selected() -> void:
	if selected != null:
		act("upgrade", [selected.cell])


func sell_selected() -> void:
	if selected != null:
		act("sell", [selected.cell])
		selected = null


func toggle_menu() -> void:
	menu_open = not menu_open
	build_type = ""
	if not menu_open:
		code_input.release_focus()


# ---------------------------------------------------------------- player actions

# Everything a player does to the game goes through here. Playing alone or as
# the host it happens right away; the other players ask the host to do it.
func act(action: String, args: Array) -> void:
	match net_mode:
		"client":
			net_request.rpc_id(1, action, args)
		"connecting":
			pass
		_:
			var error := perform(local_slot, action, args)
			if error != "":
				flash(error)


# Does a player's action. Checks everything, since it may come over the network.
# Returns a message to show the player if it can't be done, or "".
func perform(slot: int, action: String, args: Array) -> String:
	match action:
		"build":
			if args.size() == 2 and args[0] is Vector2i and args[1] is String and TOWERS.has(args[1]):
				return build_tower(slot, args[0], args[1])
		"upgrade":
			if args.size() == 1 and args[0] is Vector2i:
				return upgrade_tower(slot, args[0])
		"sell":
			if args.size() == 1 and args[0] is Vector2i:
				return sell_tower(slot, args[0])
		"wave":
			if state == "playing":
				return call_wave()
		"speed":
			if slot != local_slot:
				return "Only the host can change the speed"
			game_speed = game_speed % 3 + 1
		"restart":
			if state != "playing":
				new_game()
	return ""


func build_tower(slot: int, c: Vector2i, type: String) -> String:
	if state != "playing" or not can_build(c):
		return ""
	var cost: int = TOWERS[type]["cost"][0]
	if players[slot].gold < cost:
		return "Not enough gold"
	var t := Tower.new()
	t.type = type
	t.cell = c
	t.pos = cell_center(c)
	t.spent = cost
	t.owner = slot
	players[slot].gold -= cost
	towers[c] = t
	build_tower_node(t)
	send_tower(t)
	return ""


func upgrade_tower(slot: int, c: Vector2i) -> String:
	var t: Tower = towers.get(c)
	if t == null or state != "playing":
		return ""
	if t.owner != slot:
		return "That's %s's tower" % PLAYER_NAMES[t.owner]
	if t.level >= 3:
		return "Already max level"
	var cost: int = TOWERS[t.type]["cost"][t.level + 1]
	if players[slot].gold < cost:
		return "Not enough gold"
	players[slot].gold -= cost
	t.spent += cost
	t.level += 1
	build_tower_node(t)
	send_tower(t)
	return ""


func sell_tower(slot: int, c: Vector2i) -> String:
	var t: Tower = towers.get(c)
	if t == null or state != "playing":
		return ""
	if t.owner != slot:
		return "That's %s's tower" % PLAYER_NAMES[t.owner]
	players[slot].gold += int(t.spent * 0.7)
	remove_tower(c)
	send_all("net_tower_removed", [c])
	return ""


func remove_tower(c: Vector2i) -> void:
	var t: Tower = towers.get(c)
	if t == null:
		return
	t.node.queue_free()
	towers.erase(c)
	if selected == t:
		selected = null


# ---------------------------------------------------------------- multiplayer
#
# The host's game is the real one: it moves the monsters, does the damage and
# keeps everyone's gold. The other players' games send their actions to the
# host (net_request) and show what the host tells them: towers when they
# change, every monster's position many times a second (net_snapshot), and
# shots and explosions as they happen.

var net_port := NET_PORT


# Host: sends a message to every player who has joined.
func send_all(method: StringName, args: Array) -> void:
	if net_mode != "host":
		return
	for p in players:
		if p != null and p.peer != 1:
			callv("rpc_id", [p.peer, method] + args)


func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(NET_PORT, MAX_PLAYERS - 1) != OK:
		net_status = "Couldn't start hosting. Is the game already hosting in another window?"
		return
	multiplayer.multiplayer_peer = peer
	net_mode = "host"
	players[local_slot].peer = 1
	# The short code: players on the same network find this game by asking for it
	search_peer = PacketPeerUDP.new()
	if search_peer.bind(SEARCH_PORT) == OK:
		short_code = ""
		for i in 5:
			short_code += CODE_LETTERS[randi() % CODE_LETTERS.length()]
	else:
		search_peer = null
		short_code = ""
	invite_code = ""
	net_status = "Asking your router to let players from the internet in..."
	upnp_thread = Thread.new()
	upnp_thread.start(open_router_port)


# Host: answers players on the local network who are looking for our short code.
func answer_searches() -> void:
	while search_peer.get_available_packet_count() > 0:
		var message := search_peer.get_packet().get_string_from_utf8()
		if message == "GTD?" + short_code:
			search_peer.set_dest_address(search_peer.get_packet_ip(), search_peer.get_packet_port())
			search_peer.put_packet(("GTD!%s:%d" % [short_code, NET_PORT]).to_utf8_buffer())


# Runs in the background, since talking to the router takes a few seconds.
func open_router_port() -> void:
	var u := UPNP.new()
	var public_ip := ""
	if u.discover(2000, 2) == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() != null and u.get_gateway().is_valid_gateway():
		if u.add_port_mapping(NET_PORT, NET_PORT, "Gettic's first TD", "UDP") == UPNP.UPNP_RESULT_SUCCESS:
			public_ip = u.query_external_address()
	_on_router_port_done.call_deferred(u, public_ip)


func _on_router_port_done(u: UPNP, public_ip: String) -> void:
	upnp_thread.wait_to_finish()
	upnp_thread = null
	var opened := public_ip.is_valid_ip_address() and not public_ip.contains(":")
	if net_mode != "host":
		if opened:
			u.delete_port_mapping(NET_PORT, "UDP")
		return
	if opened:
		upnp = u
		invite_code = make_invite_code([public_ip])
		net_status = ""
	else:
		net_status = "Your router didn't let players from the internet in. Friends far away can still join if you both use a VPN like Radmin VPN, with the short code."


func close_router_port() -> void:
	if upnp != null:
		upnp.delete_port_mapping(NET_PORT, "UDP")
		upnp = null


func _exit_tree() -> void:
	if upnp_thread != null:
		upnp_thread.wait_to_finish()
	close_router_port()
	close_search()


# Where to send a search for a short code: this computer, and every network
# this computer is on (as broadcasts, which every computer on it receives).
func search_targets() -> Array:
	var targets := ["127.0.0.1", "255.255.255.255"]
	for a: String in IP.get_local_addresses():
		var p := a.split(".")
		if p.size() != 4 or p[0] == "127" or a.begins_with("169.254."):
			continue
		# We don't know each network's size, so try the common ones
		for b in ["%s.%s.%s.255" % [p[0], p[1], p[2]], "%s.%s.255.255" % [p[0], p[1]], "%s.255.255.255" % p[0]]:
			if not targets.has(b):
				targets.append(b)
	return targets


# The long invite code holds the host's internet address and port, written with
# letters and digits that are hard to mix up.
func make_invite_code(ips: Array) -> String:
	var bytes := PackedByteArray([ips.size()])
	for ip: String in ips:
		for part in ip.split("."):
			bytes.append(part.to_int())
	bytes.append(NET_PORT >> 8)
	bytes.append(NET_PORT & 255)
	var code := ""
	var buffer := 0
	var bits := 0
	for b in bytes:
		buffer = (buffer << 8) | b
		bits += 8
		while bits >= 5:
			bits -= 5
			code += CODE_LETTERS[(buffer >> bits) & 31]
		buffer &= (1 << bits) - 1
	if bits > 0:
		code += CODE_LETTERS[(buffer << (5 - bits)) & 31]
	var groups := PackedStringArray()
	for i in range(0, code.length(), 4):
		groups.append(code.substr(i, 4))
	return "-".join(groups)


# Returns [addresses, port], or [] if the code isn't valid.
func read_invite_code(code: String) -> Array:
	code = code.to_upper().replace("O", "0").replace("I", "1").replace("L", "1")
	var bytes := PackedByteArray()
	var buffer := 0
	var bits := 0
	for ch in code:
		var v := CODE_LETTERS.find(ch)
		if v < 0:
			continue  # dashes and spaces
		buffer = (buffer << 5) | v
		bits += 5
		if bits >= 8:
			bits -= 8
			bytes.append((buffer >> bits) & 255)
			buffer &= (1 << bits) - 1
	if bytes.is_empty():
		return []
	var count := bytes[0]
	if count < 1 or count > 2 or bytes.size() < 3 + count * 4:
		return []
	var ips := []
	for i in count:
		var o := 1 + i * 4
		ips.append("%d.%d.%d.%d" % [bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]])
	return [ips, (bytes[1 + count * 4] << 8) | bytes[2 + count * 4]]


func join_game() -> void:
	code_input.release_focus()
	var letters := ""
	for ch in code_input.text.to_upper().replace("O", "0").replace("I", "1").replace("L", "1"):
		if CODE_LETTERS.contains(ch):
			letters += ch
	if letters.length() == 5:
		start_search(letters)
		return
	var parsed := read_invite_code(code_input.text)
	if parsed.is_empty():
		net_status = "That invite code doesn't look right."
		return
	net_addresses = parsed[0]
	net_port = parsed[1]
	net_mode = "connecting"
	try_next_address()


# Short code: ask everyone on the local network which game has it.
func start_search(code: String) -> void:
	search_peer = PacketPeerUDP.new()
	search_peer.set_broadcast_enabled(true)
	if search_peer.bind(0) != OK:
		search_peer = null
		net_status = "Couldn't search the network."
		return
	search_code = code
	search_time = 0.0
	search_send_timer = 0.0
	search_found.clear()
	net_mode = "searching"
	net_status = "Looking for game %s on your network..." % code


func update_search(delta: float) -> void:
	search_time += delta
	search_send_timer -= delta
	if search_send_timer <= 0.0:
		search_send_timer = 0.5
		for target in search_targets():
			search_peer.set_dest_address(target, SEARCH_PORT)
			search_peer.put_packet(("GTD?" + search_code).to_utf8_buffer())
	while search_peer.get_available_packet_count() > 0:
		var reply := search_peer.get_packet().get_string_from_utf8()
		var ip := search_peer.get_packet_ip()
		if reply.begins_with("GTD!%s:" % search_code) and not search_found.has(ip):
			net_port = reply.get_slice(":", 1).to_int()
			# The same computer is the surest way in, so try that first
			if ip == "127.0.0.1":
				search_found.push_front(ip)
			else:
				search_found.append(ip)
	# Once someone answered, wait a moment for answers from other networks, then connect
	if not search_found.is_empty() and search_send_timer < 0.2:
		close_search()
		net_addresses = search_found.duplicate()
		net_mode = "connecting"
		try_next_address()
	elif search_time > 4.0:
		close_search()
		net_mode = ""
		net_status = "Couldn't find game %s on your network. If your friend is far away, use their long code, or both use a VPN like Radmin VPN." % search_code


func close_search() -> void:
	if search_peer != null:
		search_peer.close()
		search_peer = null


# Tries the host's addresses from the invite code one by one.
func try_next_address() -> void:
	close_connection()
	if net_addresses.is_empty():
		net_mode = ""
		net_status = "Couldn't reach the host. Check the code, and that the host is still hosting. On the same Wi-Fi as the host? Use the 5-character code instead. Otherwise the host may need to allow the game through the Windows firewall."
		return
	var address: String = net_addresses.pop_front()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, net_port) != OK:
		try_next_address()
		return
	multiplayer.multiplayer_peer = peer
	net_connect_time = 0.0
	net_status = "Connecting to the host..."


func close_connection() -> void:
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func stop_hosting() -> void:
	close_connection()
	close_router_port()
	close_search()
	net_mode = ""
	invite_code = ""
	short_code = ""
	net_status = ""
	for slot in MAX_PLAYERS:
		if slot != local_slot:
			players[slot] = null
			spawn_queues[slot].clear()


# Back to playing alone, with a fresh game.
func leave_game(text: String) -> void:
	close_connection()
	net_mode = ""
	play_alone()
	net_status = text
	flash(text)


func _on_connected_to_host() -> void:
	net_join.rpc_id(1, version)


func _on_connection_failed() -> void:
	if net_mode == "connecting":
		try_next_address()


func _on_host_left() -> void:
	if net_mode == "client":
		leave_game("The host left the game.")
	elif net_mode == "connecting":
		try_next_address()


func _on_peer_connected(_id: int) -> void:
	pass  # the host waits for net_join, which says which version the player has


func _on_peer_disconnected(id: int) -> void:
	if net_mode != "host":
		return
	for slot in MAX_PLAYERS:
		if players[slot] != null and players[slot].peer == id:
			players[slot] = null
			spawn_queues[slot].clear()
			send_players()
			var text := "%s left the game" % PLAYER_NAMES[slot]
			flash(text)
			send_all("net_message", [text])


func send_players() -> void:
	var list := []
	for p in players:
		if p != null:
			list.append([p.peer, p.slot])
	send_all("net_players", [list])


func send_tower(t: Tower) -> void:
	send_all("net_tower", [t.cell, t.type, t.level, t.owner, t.spent])


func send_snapshot() -> void:
	var ids := PackedInt32Array()
	var kinds := PackedByteArray()
	var data := PackedFloat32Array()
	for e in enemies:
		ids.append(e.id)
		kinds.append(ENEMY_KINDS.find(e.kind))
		data.append_array(PackedFloat32Array([e.pos.x, e.pos.y, e.hp, e.max_hp, e.slow_time]))
	var golds := []
	for p in players:
		golds.append(p.gold if p != null else 0)
	var info := [wave, next_wave_timer, state, game_speed, monsters_left_to_spawn(), golds]
	send_all("net_snapshot", [info, ids, kinds, data])


# ----- messages from a player to the host

@rpc("any_peer", "call_remote", "reliable")
func net_join(their_version: String) -> void:
	if net_mode != "host":
		return
	var peer := multiplayer.get_remote_sender_id()
	if their_version != version:
		net_refused.rpc_id(peer, "The host has version %s and you have %s. You both need the same version." % [version, their_version])
		return
	var slot := players.find(null)
	if slot < 0:
		net_refused.rpc_id(peer, "That game is full (4 players).")
		return
	var p := Player.new()
	p.peer = peer
	p.slot = slot
	# Joining late: some extra gold to catch up
	p.gold = START_GOLD + wave * 20
	players[slot] = p
	net_welcome.rpc_id(peer, slot)
	for t: Tower in towers.values():
		net_tower.rpc_id(peer, t.cell, t.type, t.level, t.owner, t.spent)
	send_players()
	var text := "%s joined the game" % PLAYER_NAMES[slot]
	flash(text)
	send_all("net_message", [text])


@rpc("any_peer", "call_remote", "reliable")
func net_request(action: String, args: Array) -> void:
	if net_mode != "host":
		return
	var peer := multiplayer.get_remote_sender_id()
	for p in players:
		if p != null and p.peer == peer:
			var error := perform(p.slot, action, args)
			if error != "":
				net_message.rpc_id(peer, error)
			return


# ----- messages from the host to the players

@rpc("authority", "call_remote", "reliable")
func net_welcome(slot: int) -> void:
	net_mode = "client"
	clear_world()
	players = [null, null, null, null]
	local_slot = slot
	var me := Player.new()
	me.slot = slot
	players[slot] = me
	menu_open = false
	code_input.release_focus()
	net_status = ""
	flash("You joined as %s!" % PLAYER_NAMES[slot])


@rpc("authority", "call_remote", "reliable")
func net_refused(reason: String) -> void:
	close_connection()
	net_mode = ""
	net_status = reason


@rpc("authority", "call_remote", "reliable")
func net_players(list: Array) -> void:
	if net_mode != "client":
		return
	var golds := []
	for p in players:
		golds.append(p.gold if p != null else 0)
	players = [null, null, null, null]
	for item in list:
		var p := Player.new()
		p.peer = item[0]
		p.slot = item[1]
		p.gold = golds[p.slot]
		players[p.slot] = p


@rpc("authority", "call_remote", "reliable")
func net_message(text: String) -> void:
	flash(text)


@rpc("authority", "call_remote", "reliable")
func net_reset() -> void:
	clear_world()


@rpc("authority", "call_remote", "reliable")
func net_tower(cell: Vector2i, type: String, level: int, owner_slot: int, spent: int) -> void:
	var t: Tower = towers.get(cell)
	if t == null:
		t = Tower.new()
		t.cell = cell
		t.pos = cell_center(cell)
		towers[cell] = t
	t.type = type
	t.level = level
	t.owner = owner_slot
	t.spent = spent
	build_tower_node(t)


@rpc("authority", "call_remote", "reliable")
func net_tower_removed(cell: Vector2i) -> void:
	remove_tower(cell)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_shot(cell: Vector2i, target_id: int) -> void:
	var t: Tower = towers.get(cell)
	var target: Enemy = enemy_by_id.get(target_id)
	if t == null or target == null:
		return
	t.aim = (target.pos - t.pos).normalized()
	launch_shot(t, target, true)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_bolt(points: PackedVector3Array) -> void:
	add_bolt(points)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_boom(pos: Vector2, r: float) -> void:
	add_boom(pos, r)


# Where every monster is, plus the wave, timer and everyone's gold.
@rpc("authority", "call_remote", "unreliable_ordered")
func net_snapshot(info: Array, ids: PackedInt32Array, kinds: PackedByteArray, data: PackedFloat32Array) -> void:
	if net_mode != "client":
		return
	wave = info[0]
	next_wave_timer = info[1]
	state = info[2]
	game_speed = info[3]
	net_spawn_left = info[4]
	var golds: Array = info[5]
	for slot in MAX_PLAYERS:
		if players[slot] != null:
			players[slot].gold = golds[slot]
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		var p := Vector2(data[i * 5], data[i * 5 + 1])
		var e: Enemy = enemy_by_id.get(id)
		if e == null:
			e = make_enemy(ENEMY_KINDS[kinds[i]])
			e.id = id
			e.pos = p
			enemies.append(e)
			enemy_by_id[id] = e
		e.net_pos = p
		e.hp = data[i * 5 + 2]
		e.max_hp = data[i * 5 + 3]
		e.slow_time = data[i * 5 + 4]
	# Monsters the host no longer has were killed
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if not seen.has(e.id):
			e.dead = true
			e.node.queue_free()
			enemy_by_id.erase(e.id)
			enemies.remove_at(i)


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
	if menu_open:
		draw_menu()
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
	var danger := clampf(float(alive) / max_alive(), 0.0, 1.0)
	var danger_col := Color(0.4, 0.9, 0.4).lerp(Color(1, 0.3, 0.3), danger)
	text(Vector2(PANEL_X, 66), "Alive: %d / %d" % [alive, max_alive()], 20, danger_col)
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
	if net_mode == "host" or net_mode == "client":
		# A dot per player in their color; yours has a ring
		var x := PANEL_X
		for slot in MAX_PLAYERS:
			if players[slot] == null:
				continue
			hud.draw_circle(Vector2(x + 6, 120), 6, PLAYER_COLORS[slot])
			if slot == local_slot:
				hud.draw_arc(Vector2(x + 6, 120), 9, 0, TAU, 20, Color.WHITE, 1.5)
			x += 22
		text(Vector2(x + 4, 125), "You: %s" % PLAYER_NAMES[local_slot], 14, PLAYER_COLORS[local_slot])
	else:
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
		if selected.owner != local_slot:
			text(Vector2(PANEL_X, 466), "Built by %s" % PLAYER_NAMES[selected.owner], 14, PLAYER_COLORS[selected.owner])
		elif lv < 3:
			text(Vector2(PANEL_X, 466), "Next: Damage %d   Range %d" % [data["damage"][lv + 1], data["range"][lv + 1]], 14, Color(0.6, 0.9, 0.6))
			var cost: int = data["cost"][lv + 1]
			button(UPGRADE_RECT, "Upgrade %dg (U)" % cost, gold >= cost)
		else:
			button(UPGRADE_RECT, "Max level", false)
		if selected.owner == local_slot:
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
	elif wave < MAX_WAVE and monsters_left_to_spawn() > 0:
		wave_label = "Spawning... (%d left)" % monsters_left_to_spawn()
	elif wave < MAX_WAVE:
		wave_label = "Send now +%dg (SPACE)" % int(maxf(next_wave_timer, 0.0))
	else:
		wave_label = "No more waves"
	button(WAVE_RECT, wave_label, wave < MAX_WAVE and state == "playing" and monsters_left_to_spawn() == 0)
	button(SPEED_RECT, "x%d (F)" % game_speed, net_mode != "client", game_speed > 1)
	text(Vector2(PANEL_X, 676), "WASD: move camera   Scroll: zoom", 13, Color(0.55, 0.55, 0.6))
	text(Vector2(PANEL_X, 696), "Right-click: cancel   Esc: menu & multiplayer", 13, Color(0.55, 0.55, 0.6))


func centered(y: float, s: String, size: int, col := Color.WHITE) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2((PANEL_LEFT - w) / 2.0, y), s, size, col)


# The Esc menu: pause, and host or join a multiplayer game.
func draw_menu() -> void:
	var m := MENU_RECT
	var left := HOST_RECT.position.x
	var width := HOST_RECT.size.x
	hud.draw_rect(Rect2(0, 0, PANEL_LEFT, SCREEN_H), Color(0, 0, 0, 0.5))
	hud.draw_rect(m, Color(0.11, 0.12, 0.16))
	hud.draw_rect(m, Color(0.45, 0.48, 0.55), false, 2.0)
	centered(m.position.y + 50, "PAUSED" if net_mode == "" else "MENU", 40)
	var sub := "The game is paused." if net_mode == "" else "The game keeps running while this menu is open."
	centered(m.position.y + 80, sub, 15, Color(0.7, 0.7, 0.75))
	text(Vector2(left, 180), "MULTIPLAYER", 16, Color(1, 0.85, 0.3))
	var grey := Color(0.75, 0.75, 0.8)
	var gold_col := Color(1, 0.85, 0.3)
	match net_mode:
		"":
			button(HOST_RECT, "Host a game and get an invite code", true, true)
			text(Vector2(left, 280), "Or join a friend's game with their invite code:", 15, grey)
			button(JOIN_BUTTON_RECT, "Join")
			hud.draw_multiline_string(font, Vector2(left, 360), net_status, HORIZONTAL_ALIGNMENT_LEFT, width, 15, 4, Color(1, 0.75, 0.5))
		"searching", "connecting":
			button(HOST_RECT, "Cancel")
			hud.draw_multiline_string(font, Vector2(left, 270), net_status, HORIZONTAL_ALIGNMENT_LEFT, width, 16, 3, grey)
		"host":
			if short_code != "":
				text(Vector2(left, 218), "Invite code:", 15, grey)
				text(Vector2(left, 262), short_code, 40, gold_col)
				button(COPY_RECT, "Copy")
				text(Vector2(left, 290), "For friends on the same Wi-Fi, or on a VPN like Radmin VPN.", 14, grey)
			else:
				text(Vector2(left, 240), "No short code: another game on this PC is already hosting.", 14, Color(1, 0.75, 0.5))
			text(Vector2(left, 326), "Friends on other networks use the long code:", 14, grey)
			if invite_code != "":
				text(Vector2(left, 352), invite_code, 18, gold_col)
				button(COPY_LONG_RECT, "Copy")
				text(Vector2(left, 380), "It usually doesn't work from your own Wi-Fi: use the short code there.", 13, grey)
			elif upnp_thread != null:
				text(Vector2(left, 352), "Asking your router...", 16, grey)
			hud.draw_multiline_string(font, Vector2(left, 380), net_status, HORIZONTAL_ALIGNMENT_LEFT, width, 13, 3, Color(1, 0.75, 0.5))
			draw_player_list(Vector2(left, 450))
			button(STOP_RECT, "Stop hosting")
		"client":
			text(Vector2(left, 218), "You are playing as %s." % PLAYER_NAMES[local_slot], 16, PLAYER_COLORS[local_slot])
			draw_player_list(Vector2(left, 250))
			button(STOP_RECT, "Leave the game")
	button(RESUME_RECT, "Resume (Esc)")


func draw_player_list(pos: Vector2) -> void:
	text(pos, "Players (%d / %d):" % [player_count(), MAX_PLAYERS], 15, Color(0.75, 0.75, 0.8))
	var y := pos.y + 24
	for slot in MAX_PLAYERS:
		if players[slot] == null:
			continue
		hud.draw_circle(Vector2(pos.x + 8, y - 5), 6, PLAYER_COLORS[slot])
		var who: String = PLAYER_NAMES[slot]
		if slot == local_slot:
			who += " (you)"
		elif players[slot].peer == 1:
			who += " (host)"
		text(Vector2(pos.x + 22, y), who, 15)
		y += 20


func menu_click(p: Vector2) -> void:
	if RESUME_RECT.has_point(p):
		toggle_menu()
		return
	match net_mode:
		"":
			if HOST_RECT.has_point(p):
				host_game()
			elif JOIN_BUTTON_RECT.has_point(p):
				join_game()
		"searching", "connecting":
			if HOST_RECT.has_point(p):
				close_search()
				close_connection()
				net_mode = ""
				net_status = ""
		"host":
			if COPY_RECT.has_point(p) and short_code != "":
				DisplayServer.clipboard_set(short_code)
				flash("Invite code copied")
			elif COPY_LONG_RECT.has_point(p) and invite_code != "":
				DisplayServer.clipboard_set(invite_code)
				flash("Long invite code copied")
			elif STOP_RECT.has_point(p):
				stop_hosting()
		"client":
			if STOP_RECT.has_point(p):
				leave_game("You left the game.")


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
