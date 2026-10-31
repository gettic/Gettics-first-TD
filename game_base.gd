extends Node3D
## Gettic's first TD - a small 3D tower defense game.
## Monsters come out of a gate at each player's corner and walk around a square.
## Up to 4 players can play together over the network (see "multiplayer").
## The game logic runs on a flat map measured in pixels (CELL pixels per tile).
## to3d() turns those positions into the 3D world, where one tile is one unit.
## The bottom console, health bars and lightning are drawn in 2D on top (draw_hud).
##
## The code is split over files that extend each other, so the game is still one
## node with every function and variable on it (main.tscn uses main.gd):
## game_base.gd (constants, data, shared state and helpers) <- game_updates.gd
## (debug log, updates, unpacking) <- game_world.gd (3D world, models, effects)
## <- game_net.gd (multiplayer) <- game_ui.gd (2D overlay and menus) <- main.gd
## (waves, update loop, input, player actions). A file can only use what is in
## its own file or the ones before it.

const CELL := 40
const COLS := 24
const ROWS := 18
const SCREEN_W := 1280
const SCREEN_H := 720
const CAMERA_SPEED := 12.0  # tiles per second
const CAMERA_LIMIT := Vector2(9.0, 7.0)  # how far the camera can move from its start
const CAMERA_H_OFFSET := 0.0  # the map uses the full width now
const CAMERA_V_OFFSET := -3.5  # shifts the view so the map sits above the bottom console
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
const PLAYER_NAMES := ["Blue", "Red", "Yellow", "Green"]
const PLAYER_COLORS := [Color(0.3, 0.55, 1.0), Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.25, 0.8, 0.45)]
const ENEMY_KINDS := ["normal", "fast", "armored", "boss"]
const EARLY_VOTE := 0.75  # with more players, this share of them must agree to send a wave early

# Multiplayer: the host's game runs everything, the others send it their actions
const NET_PORT := 24750
const SEARCH_PORT := 24751  # the host listens here for players on its network looking for its code
const SNAPSHOT_RATE := 15.0  # monster updates per second sent to the other players
const CODE_LETTERS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # for invite codes (no I, L, O or U)
# The game server (a Cloudflare Worker) that lists public games and passes messages
# along, so no router ports are needed. Empty: only games on the local network.
# Start the game with "-- --relay=http://127.0.0.1:8787" to use a test server.
const RELAY_URL := "https://gtd-relay.gtd-relay.workers.dev"

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

# Interface layout (screen pixels): a resource bar along the top and a console along the bottom
const TOP_BAR_H := 30
const BAR_TOP := 548  # top of the bottom console
const MINIMAP_RECT := Rect2(24, 566, 192, 144)  # 8 pixels per tile
const INFO_X := 236  # wave info, right of the minimap
const PORTRAIT_RECT := Rect2(474, 568, 120, 120)  # the selected tower's picture
const STATS_X := 612
const CARD_X := 972  # command card: 4 x 2 square buttons
const CARD_Y := 568
const CARD_SIZE := 64
const CARD_GAP := 8
const UPGRADE_RECT := Rect2(CARD_X, CARD_Y + CARD_SIZE + CARD_GAP, CARD_SIZE, CARD_SIZE)
const SELL_RECT := Rect2(CARD_X + (CARD_SIZE + CARD_GAP), CARD_Y + CARD_SIZE + CARD_GAP, CARD_SIZE, CARD_SIZE)
const WAVE_RECT := Rect2(CARD_X + (CARD_SIZE + CARD_GAP) * 2, CARD_Y + CARD_SIZE + CARD_GAP, CARD_SIZE, CARD_SIZE)
const SPEED_RECT := Rect2(CARD_X + (CARD_SIZE + CARD_GAP) * 3, CARD_Y + CARD_SIZE + CARD_GAP, CARD_SIZE, CARD_SIZE)
const UPDATE_RECT := Rect2(560, 3, 240, 24)  # in the top bar
const ARCH_R := 92.0  # the round arch over the portrait
const ARCH_DROP := 62.0  # how far below the console's top its center is
const MESSAGE_Y := BAR_TOP - 46  # flash messages, centered over the console
const END_Y := 290  # the win / lose title, centered over the map
# Where the map can't be clicked
const PANEL_RECTS := [Rect2(0, 0, SCREEN_W, TOP_BAR_H), Rect2(0, BAR_TOP, SCREEN_W, SCREEN_H - BAR_TOP),
		Rect2(474, BAR_TOP - 32, 120, 32)]

# Esc menu layout (screen pixels)
const MENU_RECT := Rect2(390, 60, 500, 620)
const HOST_RECT := Rect2(430, 198, 420, 44)
const JOIN_INPUT_RECT := Rect2(430, 292, 290, 40)
const JOIN_BUTTON_RECT := Rect2(730, 292, 120, 40)
const COPY_RECT := Rect2(730, 226, 120, 40)
const STOP_RECT := Rect2(430, 560, 420, 40)
const RESUME_RECT := Rect2(430, 616, 420, 44)
const PUBLIC_RECT := Rect2(430, 350, 420, 36)
const REFRESH_RECT := Rect2(750, 408, 100, 28)
const GRAPHICS_RECT := Rect2(756, 70, 124, 28)
const GAME_ROWS := 4  # public games shown in the menu

# Update popup layout (screen pixels)
const DIALOG_RECT := Rect2(340, 140, 600, 440)
const DIALOG_YES_RECT := Rect2(380, 506, 250, 44)
const DIALOG_NO_RECT := Rect2(650, 506, 250, 44)
const CHOOSE_FOLDER_RECT := Rect2(370, 368, 250, 36)  # in the unpack warning

# Box asking whether another player may build in your area: in the console's middle,
# over the portrait and stats (screen pixels)
const ASK_RECT := Rect2(456, 556, 484, 156)
const ASK_YES_RECT := Rect2(480, 646, 212, 44)
const ASK_NO_RECT := Rect2(704, 646, 212, 44)

# Checked at startup to see if a newer release is on GitHub
const RELEASES_API := "https://api.github.com/repos/gettic/Gettics-first-TD/releases/latest"

# Where the downloaded .exe unpacks itself (see "unpacking")
const GAME_FOLDER := "Gettic's first TD"
const GAME_NAME := "Gettic's first TD"  # the files are named like "Gettic's first TD v1.16.exe"

# The debug build (made with /debuggame) is exported with this feature tag.
# It opens a log window, and never unpacks, renames or updates itself.
const DEBUG_FEATURE := "debug_game"


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
var wave_votes: Array = []  # player slots that want the next wave early (see EARLY_VOTE)
var wave := 0
var spawn_queues: Array = [[], [], [], []]  # monster kinds still to come out of each gate
var spawn_timers := [0.0, 0.0, 0.0, 0.0]
var spawn_hp := 0.0
var requests := {}  # host: id -> {from, to, cell, type, time}, a player asking to build in another's area
var next_request_id := 1
var asks: Array = []  # [id, from slot, tower type, cell]: other players asking to build in our area
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
var invite_code := ""  # host: 5 letters and digits, from the game server or make_code()
var search_peer: PacketPeerUDP  # host: answers searches; player: sends them
var search_time := 0.0
var search_send_timer := 0.0
var search_code := ""
var search_found: Array = []  # addresses of hosts that answered
var snapshot_timer := 0.0
var relay_url := RELAY_URL
var public_game := false  # host: shown in everyone's list of public games
var game_info_timer := 0.0
var public_games: Array = []  # [{code, players, wave}] from the game server
var games_status := "Looking for public games..."
var games_http: HTTPRequest
var games_timer := 0.0
var code_input: LineEdit
var message := ""
var message_time := 0.0
var font: Font
var time := 0.0
var version := ""
var update_version := ""  # set when GitHub has a newer release
var update_url := ""  # release page
var update_zip_url := ""  # the Windows .zip in the release (how versions before 1.15 update)
var update_exe_url := ""  # the packed .exe in the release
var update_pck_url := ""  # just the game, if the release has one for our engine version
var update_notes := ""  # "What's new" from the release notes
var update_dialog := ""  # "", "ask", "downloading" or "failed"
var update_error := ""
var update_http: HTTPRequest
var unpack_chosen := ""  # a folder the player picked to unpack to, instead of next to the download
var folder_picker: FileDialog

# 3D scene pieces
var camera: Camera3D
var camera_home: Vector3
var camera_focus: Vector3       # the ground point the camera looks at when not moved
var camera_pan := Vector2.ZERO  # how far WASD has moved the camera
var zoom := 1.0
var target_zoom := 1.0
var hud: Node2D
var gate_parts: Array = []  # per gate: the portal pieces that only show while a player uses that gate
var area_planes: Array = []  # per player slot: covers that player's area while building
var range_disc: MeshInstance3D
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var stone_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D
var gold_mat: StandardMaterial3D
var pip_mesh: SphereMesh
var boom_mesh: SphereMesh
var shot_mats := {}


# ---------------------------------------------------------------- shared helpers

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
	wave_votes.clear()
	requests.clear()
	asks.clear()
	towers.clear()
	shots.clear()
	effects.clear()
	for q in spawn_queues:
		q.clear()
	build_type = ""
	selected = null


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
	return over_panel(get_viewport().get_mouse_position())


func over_panel(p: Vector2) -> bool:
	for r: Rect2 in PANEL_RECTS:
		if r.has_point(p):
			return true
	return false


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
	return Rect2(CARD_X + i * (CARD_SIZE + CARD_GAP), CARD_Y, CARD_SIZE, CARD_SIZE)


func kind_for_wave(w: int) -> String:
	if w % 10 == 0:
		return "boss"
	if w % 5 == 0:
		return "fast"
	if w % 3 == 0:
		return "armored"
	return "normal"


# How many players must agree to send the next wave early.
func votes_needed() -> int:
	return ceili(player_count() * EARLY_VOTE)


func alive_count() -> int:
	var n := 0
	for e in enemies:
		n += e.weight
	return n


# Each player has the quarter of the map around their gate. Returns the player
# whose area a tile is in, or -1 if nobody plays that gate (then anyone can build).
func area_owner(c: Vector2i) -> int:
	var slot := 0
	if c.x < COLS / 2.0:
		slot = 1 if c.y < ROWS / 2.0 else 0
	else:
		slot = 2 if c.y < ROWS / 2.0 else 3
	return slot if players[slot] != null else -1


func close_ask(id: int) -> void:
	for i in range(asks.size() - 1, -1, -1):
		if asks[i][0] == id:
			asks.remove_at(i)


func remove_tower(c: Vector2i) -> void:
	var t: Tower = towers.get(c)
	if t == null:
		return
	t.node.queue_free()
	towers.erase(c)
	if selected == t:
		selected = null
