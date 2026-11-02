extends "res://game_world.gd"
## Multiplayer: hosting, joining, invite codes and keeping the players in sync.

# ---------------------------------------------------------------- multiplayer
#
# The host's game is the real one: it moves the monsters, does the damage and
# keeps everyone's gold. The other players' games send their actions to the
# host (net_request) and show what the host tells them: towers when they
# change, every monster's position many times a second (net_snapshot), and
# shots and explosions as they happen.

# A network connection that goes through the game server (see RELAY_URL)
# instead of straight to the host, so nobody has to open router ports.
# Godot's multiplayer uses it just like a direct connection.
class RelayPeer extends MultiplayerPeerExtension:
	var socket := WebSocketPeer.new()
	var hosting := false
	var my_id := 0
	var status := CONNECTION_CONNECTING
	var code := ""  # host: this game's code from the server
	var error := ""  # why the server refused us, if it did
	var peers: Array[int] = []
	var incoming: Array = []  # [sender, channel, mode, data] per message
	var target := 0
	var channel := 0
	var mode := TRANSFER_MODE_RELIABLE
	var refusing := false

	func _init(url: String) -> void:
		socket.inbound_buffer_size = 1 << 20
		socket.outbound_buffer_size = 1 << 20
		if socket.connect_to_url(url) != OK:
			status = CONNECTION_DISCONNECTED

	func send_text(data: Dictionary) -> void:
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			socket.send_text(JSON.stringify(data))

	func _poll() -> void:
		socket.poll()
		while socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()
			if socket.was_string_packet():
				server_message(JSON.parse_string(packet.get_string_from_utf8()))
			elif packet.size() >= 6 and peers.has(packet.decode_s32(0)):
				# Only from players Godot knows: one who left (or was refused) would be an error
				incoming.append([packet.decode_s32(0), packet[4], packet[5], packet.slice(6)])
		var closed := socket.get_ready_state() == WebSocketPeer.STATE_CLOSED or error != ""
		if closed and status != CONNECTION_DISCONNECTED:
			lost()

	func server_message(m: Variant) -> void:
		if not (m is Dictionary):
			return
		match m.get("t"):
			"hosted":
				code = m.code
				my_id = 1
				status = CONNECTION_CONNECTED
			"joined":
				# Connected first: Godot says hello to the host as soon as it hears about it
				my_id = int(m.id)
				status = CONNECTION_CONNECTED
				peers.append(1)
				peer_connected.emit(1)
			"peer":
				if not refusing:
					peers.append(int(m.id))
					peer_connected.emit(int(m.id))
			"left":
				var id := int(m.id)
				if peers.has(id):
					forget(id)
			"error":
				error = m.text
				socket.close()

	# A player is gone: drop their messages still waiting here, then tell Godot
	func forget(id: int) -> void:
		peers.erase(id)
		incoming = incoming.filter(func(p: Array) -> bool: return p[0] != id)
		peer_disconnected.emit(id)

	func lost() -> void:
		status = CONNECTION_DISCONNECTED
		incoming.clear()
		for id in peers.duplicate():
			peer_disconnected.emit(id)
		peers.clear()

	func _get_available_packet_count() -> int:
		return incoming.size()

	func _get_packet_script() -> PackedByteArray:
		return incoming.pop_front()[3]

	func _put_packet_script(data: PackedByteArray) -> Error:
		var packet := PackedByteArray()
		packet.resize(6)
		packet.encode_s32(0, target)
		packet[4] = channel
		packet[5] = mode
		packet.append_array(data)
		return socket.put_packet(packet)

	# Godot asks who sent the next message before it takes it
	func _get_packet_peer() -> int:
		return incoming[0][0] if not incoming.is_empty() else 0

	func _get_packet_channel() -> int:
		return incoming[0][1] if not incoming.is_empty() else 0

	func _get_packet_mode() -> TransferMode:
		return incoming[0][2] if not incoming.is_empty() else TRANSFER_MODE_RELIABLE

	func _get_max_packet_size() -> int:
		return 1 << 20

	func _set_target_peer(id: int) -> void:
		target = id

	func _set_transfer_channel(c: int) -> void:
		channel = c

	func _get_transfer_channel() -> int:
		return channel

	func _set_transfer_mode(m: TransferMode) -> void:
		mode = m

	func _get_transfer_mode() -> TransferMode:
		return mode

	func _get_unique_id() -> int:
		return my_id

	func _is_server() -> bool:
		return hosting

	func _is_server_relay_supported() -> bool:
		return false

	func _get_connection_status() -> ConnectionStatus:
		return status

	func _set_refuse_new_connections(enable: bool) -> void:
		refusing = enable

	func _is_refusing_new_connections() -> bool:
		return refusing

	func _disconnect_peer(id: int, _force: bool) -> void:
		send_text({"t": "kick", "id": id})
		if peers.has(id):
			forget(id)

	func _close() -> void:
		socket.close()
		status = CONNECTION_DISCONNECTED
		peers.clear()
		incoming.clear()


var relay: RelayPeer  # the connection when it goes through the game server

# Most monsters per snapshot message on the local network: 120 x 9 bytes plus
# the rest stays well under the 1392 bytes ENet sends in one piece.
const SNAPSHOT_MONSTERS := 120


# The game rules are in main.gd, which replaces these. They are here so this
# file can call them.
func perform(_slot: int, _action: String, _args: Array) -> String:
	return ""


func play_alone() -> void:
	pass


func check_wave_votes() -> bool:
	return false


func new_game() -> void:
	pass


# Saved games (main.gd has the real ones): a loaded game's saved player slots.
func saved_slot_for(_their_name: String) -> int:
	return -1


func restore_saved_player(_p: Player) -> bool:
	return false


func held_text() -> String:
	return ""


# game_ui.gd has the real one (gold as "12.3K").
func short(n: float) -> String:
	return str(int(n))


# map_editor.gd has the real one: saves a map from the host in the player's map list.
func keep_map(_title: String, _rows: Array) -> void:
	pass


# ----- the host's map
#
# A player joining a game on another map gets the host's map as plain text
# (its rows of letters, see read_map()), never files or objects. Their game
# checks it like the map editor does, shows a preview, and only uses it once
# the player says yes. Players who already have the map (same text, compared
# by its sha256) or join a game on the Default map skip all that.

const OFFER_MAX := 3  # map offers a joining player can get before the host stops answering

var joining := {}  # host: peer -> map offers sent, for players whose version is fine but who have no slot yet
var map_offer := {}  # player: the host's map while the preview is showing {name, host, rows, hash, check, keep, accepted}
var own_map: Array = []  # player: [rows, name] of their own map while playing on the host's


func map_hash(rows: Array) -> String:
	return "\n".join(rows).sha256_text()


# Players this map has room for: one per gate.
func map_slots() -> int:
	return MAX_PLAYERS - gate_cells.count(null)


var game_info_sent := {}  # host: the last "info" sent to the game server


# Why a map from the host can't be used, or "" if it's fine. Only plain text
# of the right size gets as far as read_map().
func offer_problem(title: Variant, host_name: Variant, rows: Variant) -> String:
	if not (title is String and host_name is String and rows is Array):
		return "The host sent a broken map, so you didn't join."
	if title.length() > 200 or host_name.length() > 200 or rows.size() < MAP_MIN.y or rows.size() > MAP_MAX.y:
		return "The host's map is too big or broken, so you didn't join."
	for r in rows:
		if not (r is String) or r.length() > MAP_MAX.x:
			return "The host's map is too big or broken, so you didn't join."
	var check := read_map(rows)
	if check.has("error"):
		return "The host's map can't be used (%s), so you didn't join." % check.error
	return ""


# Player: stops joining without changing anything here.
func stop_joining(text: String) -> void:
	close_connection()
	net_mode = ""
	map_offer = {}
	net_status = text
	flash(text)


# Player: "Download and join" in the preview.
func accept_offer(keep: bool) -> void:
	if net_mode != "map_offer" or map_offer.is_empty():
		return
	map_offer.keep = keep
	map_offer.accepted = true
	net_try_join.rpc_id(1, my_name(), map_offer.hash, true)


func cancel_offer() -> void:
	stop_joining("You didn't join. Nothing was saved or changed.")


# Player: back to the map they had before joining.
func back_to_own_map() -> void:
	if own_map.is_empty():
		return
	var m := read_map(own_map[0])
	if not m.has("error"):
		use_map(m, own_map[1])
		build_map()
	own_map = []


# Host: the first slot with a gate on this map that nobody uses, or -1.
func free_slot() -> int:
	for s in map_slots():
		if players[s] == null:
			return s
	return -1


# Host: sends a message to every player who has joined.
func send_all(method: StringName, args: Array) -> void:
	if net_mode != "host":
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for p in players:
		if p == null or p.peer == 1:
			continue
		# When several players leave at once, the network already knows about
		# the others while we handle the first one: skip them
		if enet != null and enet.get_peer(p.peer).get_state() != ENetPacketPeer.STATE_CONNECTED:
			continue
		callv("rpc_id", [p.peer, method] + args)


# ----- player names

# This player's name: what they typed in the menu, or their silly name.
func my_name() -> String:
	var typed := clean_text(name_input.text, NAME_MAX) if name_input != null else ""
	return typed if typed != "" else random_name


# At startup: the name typed last time, and a silly name for when there is none.
func load_name() -> void:
	random_name = SILLY_NAMES.pick_random()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK:
		name_input.text = clean_text(str(cfg.get_value("player", "name", "")), NAME_MAX)
	name_input.placeholder_text = random_name


# Keeps the typed name for next time (with the other settings in the file).
func save_name() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	var typed := clean_text(name_input.text, NAME_MAX)
	if str(cfg.get_value("player", "name", "")) != typed:
		cfg.set_value("player", "name", typed)
		cfg.save(SETTINGS_FILE)


# Host: the name a player asked for, cleaned up, with a number added when
# another player already has it.
func unique_name(wanted: String, slot: int) -> String:
	var base := clean_text(wanted, NAME_MAX)
	if base == "":
		base = SILLY_NAMES.pick_random()
	var result := base
	var n := 2
	while name_taken(result, slot):
		result = base.left(NAME_MAX - 1 - str(n).length()).strip_edges() + " " + str(n)
		n += 1
	return result


func name_taken(name: String, slot: int) -> bool:
	for p in players:
		if p != null and p.slot != slot and p.name.to_lower() == name.to_lower():
			return true
	return false


# ----- chat
# Players send their messages to the host, which checks them and sends them
# to everyone (net_say), so every chat looks the same.

func send_chat(typed: String) -> void:
	var s := clean_text(typed, CHAT_MAX)
	if s == "":
		return
	match net_mode:
		"host":
			host_chat(local_slot, s)
		"client":
			net_request.rpc_id(1, "chat", [s])
		_:
			add_chat(local_slot, my_name(), s)  # alone: just shows it


# Host: a player's message. Too many in a short time and the rest are dropped.
func host_chat(slot: int, typed: String) -> void:
	var s := clean_text(typed, CHAT_MAX)
	if s == "" or players[slot] == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var budget: float = minf(chat_budget[slot] + (now - chat_budget_time[slot]) / CHAT_REFILL, CHAT_BURST)
	chat_budget_time[slot] = now
	if budget < 1.0:
		chat_budget[slot] = budget
		var text := "Slow down, you're chatting too fast"
		if slot == local_slot:
			flash(text)
		else:
			net_message.rpc_id(players[slot].peer, text)
		return
	chat_budget[slot] = budget - 1.0
	add_chat(slot, name_of(slot), s)
	send_all("net_say", [slot, name_of(slot), s])


# Host: a line from the game itself, like "Sir Wobbles joined the game".
func chat_note(text: String) -> void:
	add_chat(-1, "", text)
	send_all("net_say", [-1, "", text])


func add_chat(slot: int, who: String, text: String) -> void:
	chat_log.append([slot, who, text, Time.get_ticks_msec() / 1000.0])
	if chat_log.size() > 20:
		chat_log.pop_front()


func host_game() -> void:
	save_name()
	players[local_slot].name = my_name()
	if relay_url == "":
		host_direct()
		return
	relay = RelayPeer.new(relay_address("/host?version=" + version.uri_encode()))
	relay.hosting = true
	relay.my_id = 1
	multiplayer.multiplayer_peer = relay
	net_mode = "host"
	players[local_slot].peer = 1
	invite_code = ""
	net_connect_time = 0.0
	net_status = "Connecting to the game server..."


# The game server's WebSocket address: ws:// for http:// and wss:// for https://.
func relay_address(path: String) -> String:
	return "ws" + relay_url.trim_prefix("http") + path


# Host through the game server: wait for the code, keep the public game list
# up to date, and fall back to hosting straight from this computer if the
# server can't be reached.
func update_relay_host(delta: float) -> void:
	if invite_code == "":
		net_connect_time += delta
		if relay.code != "":
			invite_code = relay.code
			net_status = "Works for anyone, anywhere. No router setup needed."
			game_info_timer = 0.0
		elif relay.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED or net_connect_time > 5.0:
			close_connection()
			net_mode = ""
			host_direct()
		return
	if relay.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		stop_hosting()
		net_status = "Lost the connection to the game server, so the other players were dropped."
		flash("Lost the connection to the game server")
		return
	# Every 3 seconds, and right away when something in it changes (like the map)
	var info := {"t": "info", "public": public_game, "players": player_count(), "wave": wave, "max": map_slots()}
	game_info_timer -= delta
	if game_info_timer <= 0.0 or info != game_info_sent:
		game_info_timer = 3.0
		game_info_sent = info
		relay.send_text(info)


# Asks the game server for the public games with this version of the game.
func refresh_games() -> void:
	if games_http != null:
		return
	games_http = HTTPRequest.new()
	games_http.timeout = 8.0
	add_child(games_http)
	games_http.request_completed.connect(_on_games_listed)
	if games_http.request(relay_url + "/games?version=" + version.uri_encode()) != OK:
		_on_games_listed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _on_games_listed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	games_http.queue_free()
	games_http = null
	var list: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		list = JSON.parse_string(body.get_string_from_utf8())
	if not (list is Array):
		public_games.clear()
		games_status = "Couldn't reach the game server."
		return
	public_games = list
	games_status = "No public games right now. Host one and make it public!"


# ----- leaderboard
#
# Everyone's best games, kept by the game server (/scores in relay/worker.js).
# When a game on the Default map ends, the host (or a player alone) sends the
# wave, whether it was won, the game time and every player's name, once. Game
# time: how long the game ran from wave 1 on. Speeding up doesn't change it
# (the monsters move faster too), calling waves early does, and pausing doesn't
# count. The list goes by highest wave, then won before lost, then shortest time.
#
# The same report also feeds Gettic's wave stats (for balancing, only readable
# with the admin key, see relay/admin.mjs): the server counts, without names,
# the wave each game ended at, the number of players and the game time, plus
# the small "stats" part below. A game that is quit, left or restarted before
# it ends sends nothing, so it isn't counted.

# Each board is named after the last wave, this number and the difficulty level
# ("300w-3-hard"): raise the number after a balance change, so new scores aren't
# mixed with ones from the old rules. Each level has its own board (and stats).
const BOARD_SEASON := 5  # 2: tower specializations, 3: difficulty levels, 4: abilities and endless mode, 5: Barracks
const BOARD_ROWS := 10

var board_open := false  # the leaderboard box in the Esc menu
var board_level := 1  # which level's board the box shows (index in DIFFICULTIES)
var board_top: Array = []  # [{names, wave, won, ms}], best first
var board_me := {}  # this player's best entry and its rank ({} if none)
var board_status := ""
var board_http: HTTPRequest
var board_http_level := 1  # the level board_http asks for
var board_asked := -100.0  # when the list was last asked for, in seconds
var board_saved := {}  # level -> [when asked, top, me]: switching back doesn't ask again
var run_time := 0.0  # host / alone: game seconds since wave 1 started
var score_sent := false
var score_http: HTTPRequest


# The board a game's score goes on: "300w-4-hard", "endless-4-hard" for a run
# kept going in endless mode (see keep_going() in main.gd), or "daily-2026-11-02"
# for the daily challenge. endless_board: -1 follows the game (daily, endless),
# 0 the normal board, 1 the endless board.
func board_id(level := -1, endless_board := -1) -> String:
	var d := difficulty if level < 0 else level
	if endless_board < 0 and daily_date != "":
		return daily_board_id(daily_date)
	if endless_board == 1 or (endless_board < 0 and endless):
		return "endless-%d-%s" % [BOARD_SEASON, DIFFICULTIES[d].to_lower()]
	return "%dw-%d-%s" % [MAX_WAVE, BOARD_SEASON, DIFFICULTIES[d].to_lower()]


# Host / alone, every frame the game runs: counts the game time, and sends the
# score once when the game is over.
func track_score(dt: float) -> void:
	if state == "playing":
		# Playing again after a game that ended, or not started yet: a new game
		if score_sent or wave == 0:
			run_time = 0.0
			score_sent = false
		if wave > 0:
			run_time += dt
	elif not score_sent:
		score_sent = true
		submit_score()


# Only the exported release game sends scores and stats, so tests never land on
# the leaderboard: not headless, not from the editor or a debug build (also the
# /debuggame build), and not with --no-scores. For tests against a local server,
# --scores-test sends anyway, but only to a test server on this computer
# (--relay=http://127.0.0.1:8787 or http://localhost:...), never the real one.
func scores_allowed() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--no-scores" in args:
		return false
	if "--scores-test" in args:
		return not "@" in relay_url and (relay_url.begins_with("http://127.0.0.1:") or relay_url.begins_with("http://localhost:"))
	return DisplayServer.get_name() != "headless" and not OS.is_debug_build()


func submit_score() -> void:
	# A loaded game never goes on a leaderboard (it could be loaded again and again)
	if from_save:
		return
	# Only the Default map or the day's daily map: on a map of your own the waves can be made easy
	var map_ok: bool = map_rows_text == DEFAULT_MAP if daily_date == "" else map_rows_text == daily_map(daily_date).text
	if relay_url == "" or not map_ok or score_http != null or not scores_allowed():
		return
	var names := []
	for p in players:
		if p != null:
			names.append(my_name() if p.slot == local_slot else name_of(p.slot))
	# For the wave stats: the team's gold in towers and unspent, its highest tower level, the speed
	var tower_gold := 0
	var top_level := 0
	for t in towers.values():
		tower_gold += t.spent
		top_level = maxi(top_level, t.level + 1)
	var gold_left := 0
	for p in players:
		if p != null:
			gold_left += p.gold
	var stats := {"tower_gold": tower_gold, "gold_left": gold_left, "top_level": top_level, "speed": game_speed}
	# An endless run can't be won: it goes on its own board, ranked by the wave reached
	var won := state == "won" and not endless
	var body := JSON.stringify({"board": board_id(), "names": names, "wave": wave, "won": won, "ms": int(run_time * 1000.0), "stats": stats})
	score_http = HTTPRequest.new()
	score_http.timeout = 10.0
	add_child(score_http)
	score_http.request_completed.connect(_on_score_sent)
	if score_http.request(relay_url + "/scores", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		score_http.queue_free()
		score_http = null


# Not reaching the server only means this game isn't on the list.
func _on_score_sent(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	score_http.queue_free()
	score_http = null
	var r: Variant = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if not (r is Dictionary and r.get("best") == true and r.get("rank") is float and r.rank >= 1):
		return
	board_asked = -100.0  # show the new list next time
	board_saved.erase(difficulty)
	var list := "daily leaderboard" if daily_date != "" else ("endless leaderboard" if endless else "leaderboard")
	var text := "You're #%d on the %s!" % [int(r.rank), list]
	if player_count() > 1:
		text = "Your team is #%d on the %s!" % [int(r.rank), list]
	flash(text)
	send_all("net_message", [text])


# Opens the box on the board of the level this game is played at.
func open_board() -> void:
	board_open = true
	show_board_level(difficulty)


# Shows another level's board (index in DIFFICULTIES), for the box's level
# switcher: from what was loaded in the last 30 seconds, or asks the server.
func show_board_level(d: int) -> void:
	if d < 0 or d >= DIFFICULTIES.size():
		return
	board_level = d
	var now := Time.get_ticks_msec() / 1000.0
	var saved: Array = board_saved.get(d, [])
	if not saved.is_empty() and now - saved[0] < 30.0:
		board_top = saved[1]
		board_me = saved[2]
		board_status = "Nobody is on the leaderboard yet. Be the first!" if board_top.is_empty() else ""
		return
	board_top = []
	board_me = {}
	# A list still loading for another level isn't needed any more
	if board_http != null and board_http_level != d:
		board_http.cancel_request()
		board_http.queue_free()
		board_http = null
	if board_http == null:
		load_board()


# The next (step 1) or previous (step -1) level's board, going round.
func step_board_level(step: int) -> void:
	show_board_level(posmod(board_level + step, DIFFICULTIES.size()))


# Refresh waits a few seconds between asks.
func can_refresh_board() -> bool:
	return board_http == null and Time.get_ticks_msec() / 1000.0 - board_asked > 5.0


func refresh_board() -> void:
	if can_refresh_board():
		load_board()


func load_board() -> void:
	if relay_url == "":
		board_status = "The leaderboard needs the game server, and this game only uses your network."
		return
	board_asked = Time.get_ticks_msec() / 1000.0
	board_status = "Loading the leaderboard..."
	board_http_level = board_level
	board_http = HTTPRequest.new()
	board_http.timeout = 8.0
	add_child(board_http)
	board_http.request_completed.connect(_on_board_loaded)
	# The box shows the normal boards (it has no endless tab yet)
	var url := relay_url + "/scores?board=%s&me=%s" % [board_id(board_level, 0), my_name().to_lower().uri_encode()]
	if board_http.request(url) != OK:
		_on_board_loaded(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _on_board_loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	board_http.queue_free()
	board_http = null
	if board_http_level != board_level:
		return  # the box shows another level now
	var r: Variant = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
	if code == 429:
		board_status = "The game server is busy. Try again in a minute."
		return
	if code != 200 or not (r is Dictionary and r.get("top") is Array):
		board_status = "Couldn't reach the game server. Check your internet connection and try again."
		return
	board_top = []
	for e: Variant in r.top:
		var entry := board_entry(e)
		if not entry.is_empty() and board_top.size() < BOARD_ROWS:
			board_top.append(entry)
	board_me = board_entry(r.get("me"))
	if not board_me.is_empty():
		board_me.rank = int(r.me.get("rank", 0)) if r.me.get("rank") is float else 0
	board_saved[board_level] = [board_asked, board_top, board_me]
	board_status = "Nobody is on the leaderboard yet. Be the first!" if board_top.is_empty() else ""


# ----- daily challenge (the rules and random numbers are in game_base.gd)

const DAILY_BLOCK := 3  # map tiles per block: the loop's parallel lines are this far apart
const DAILY_MARGIN := 3  # tiles around the loop, for the gates' roads
var daily_maps := {}  # date -> read_map() result, worked out once


func daily_board_id(date: String) -> String:
	return "daily-" + date


func daily_title(date: String) -> String:
	return "Daily " + date


# The day's map, checked by read_map() like any map (the Default map if the
# maker never found a good one, which didn't happen in 60 days of tests).
func daily_map(date: String) -> Dictionary:
	if not daily_maps.has(date):
		var rows := daily_map_rows(date)
		var m := read_map(rows)
		daily_maps[date] = m if not m.has("error") else read_map(DEFAULT_MAP)
	return daily_maps[date]


# The day's map as rows of letters (see DEFAULT_MAP): a rectangle of blocks with
# notches cut from its sides, whose outline is the loop; four gates on short
# straight roads, one per quarter of the loop; a few rocks and trees. Maps where
# one player's area has much less room to build than another's are made again.
func daily_map_rows(date: String) -> Array:
	daily_seed("gtd-daily-map-%d-%s" % [DAILY_VERSION, date])
	for attempt in 40:
		var rows := daily_try_map()
		if rows.is_empty():
			continue
		var m := read_map(rows)
		if m.has("error"):
			continue
		var room := [0, 0, 0, 0]
		for c: Vector2i in m.areas:
			if m.areas[c] >= 0 and not m.path.has(c) and not m.blocked.has(c):
				room[m.areas[c]] += 1
		if room.min() >= room.max() * 0.6:
			return rows
	return DEFAULT_MAP.duplicate()


func daily_try_map() -> Array:
	var s := DAILY_BLOCK
	var bw := daily_roll(6, 9)
	var bh := daily_roll(4, 6)
	var blocks := {}
	for i in bw:
		for j in bh:
			blocks[Vector2i(i, j)] = true
	for n in daily_roll(2, 5):
		var w := daily_roll(1, 3)
		var h := daily_roll(1, 2)
		var r: Rect2i
		match daily_roll(0, 3):
			0: r = Rect2i(daily_roll(1, bw - 1 - w), 0, w, h)  # top
			1: r = Rect2i(daily_roll(1, bw - 1 - w), bh - h, w, h)  # bottom
			2: r = Rect2i(0, daily_roll(1, bh - 1 - h), h, w if w < bh - 1 else 1)  # left
			_: r = Rect2i(bw - h, daily_roll(1, bh - 1 - h), h, w if w < bh - 1 else 1)  # right
		for i in range(r.position.x, r.end.x):
			for j in range(r.position.y, r.end.y):
				blocks.erase(Vector2i(i, j))
	var cols := bw * s + 1 + 2 * DAILY_MARGIN
	var rows_n := bh * s + 1 + 2 * DAILY_MARGIN
	var grid := []
	for y in rows_n:
		var row := []
		row.resize(cols)
		row.fill(".")
		grid.append(row)
	# The outline: every block side with no block beyond it
	for b: Vector2i in blocks:
		var x0 := DAILY_MARGIN + b.x * s
		var y0 := DAILY_MARGIN + b.y * s
		for k in s + 1:
			if not blocks.has(b + Vector2i(0, -1)):
				grid[y0][x0 + k] = "#"
			if not blocks.has(b + Vector2i(0, 1)):
				grid[y0 + s][x0 + k] = "#"
			if not blocks.has(b + Vector2i(-1, 0)):
				grid[y0 + k][x0] = "#"
			if not blocks.has(b + Vector2i(1, 0)):
				grid[y0 + k][x0 + s] = "#"
	var first := Vector2i(-1, -1)
	var count := 0
	for y in rows_n:
		for x in cols:
			if grid[y][x] == "#":
				count += 1
				if first.x < 0:
					first = Vector2i(x, y)
	if count < 20:
		return []
	var ring := daily_walk(grid, first)
	if ring.size() != count:
		return []  # a pinch or a hole: not one simple loop
	var q := ring.size() / 4
	var offset := daily_roll(0, ring.size() - 1)
	for g in MAX_PLAYERS:
		var placed := false
		for k in q:
			var c: Vector2i = ring[(offset + g * q + daily_roll(0, q - 1)) % ring.size()]
			if daily_gate(grid, c, g, daily_roll(2, 3)):
				placed = true
				break
		if not placed:
			return []
	# Rocks and trees on some grass away from the path
	for y in rows_n:
		for x in cols:
			if grid[y][x] == "." and not daily_near_path(grid, Vector2i(x, y)) and daily_roll(0, 99) < 5:
				grid[y][x] = "r" if daily_roll(0, 2) == 0 else "t"
	var out := []
	for row: Array in grid:
		out.append("".join(row))
	return out


func daily_at(grid: Array, c: Vector2i) -> String:
	if c.y < 0 or c.y >= grid.size() or c.x < 0 or c.x >= grid[0].size():
		return "X"
	return grid[c.y][c.x]


# The loop's tiles in order, from start.
func daily_walk(grid: Array, start: Vector2i) -> Array:
	var ring := [start]
	var prev := start
	var cur := start
	while ring.size() < 5000:
		var nxt := cur
		for d: Vector2i in DIRS:
			if cur + d != prev and daily_at(grid, cur + d) == "#":
				nxt = cur + d
				break
		if nxt == start or nxt == cur:
			break
		ring.append(nxt)
		prev = cur
		cur = nxt
	return ring


func daily_near_path(grid: Array, c: Vector2i) -> bool:
	for d: Vector2i in DIRS:
		if daily_at(grid, c + d) in ["#", "1", "2", "3", "4"]:
			return true
	return false


# A straight road of `length` tiles from loop tile c, away from the loop, with
# gate g at its end; nothing else may touch the road.
func daily_gate(grid: Array, c: Vector2i, g: int, length: int) -> bool:
	for d: Vector2i in DIRS:
		var cells := []
		var ok := true
		for k in range(1, length + 1):
			var t: Vector2i = c + d * k
			if daily_at(grid, t) != ".":
				ok = false
				break
			for e: Vector2i in DIRS:
				var n: Vector2i = t + e
				if n != t - d and daily_at(grid, n) not in [".", "X"]:
					ok = false
			cells.append(t)
		if ok:
			for k in cells.size():
				grid[cells[k].y][cells[k].x] = str(g + 1) if k == cells.size() - 1 else "#"
			return true
	return false


# Starts the daily challenge (date "": today) alone, or as the host before anyone
# joined, before wave 1 (the Esc menu checks that, like picking a map). The day's
# level is set, and the map is built. Returns a message for the player.
func start_daily(date := "") -> String:
	if date == "":
		date = daily_today()
	if net_mode not in ["", "host"] or (net_mode == "host" and player_count() > 1):
		return "The daily challenge can only start while nobody has joined"
	use_map(daily_map(date), daily_title(date))
	build_map()
	daily_date = date
	var rules := daily_rules(date)
	difficulty = rules.level
	new_game()
	send_difficulty()
	send_all("net_set_daily", [date])
	return "Daily challenge %s (%s): %s. %s" % [date, DIFFICULTIES[difficulty], rules.name, rules.desc]


# The host's daily challenge (its date), when we join a game playing one. Only
# used when our map (from the host) really is that day's map. Its name sorts
# after net_refused (see net_say).
@rpc("authority", "call_remote", "reliable")
func net_set_daily(date: Variant) -> void:
	if net_mode != "client" or not date is String:
		return
	if date == "":
		daily_date = ""
	elif date.length() == 10 and date.substr(4, 1) == "-" and date.substr(7, 1) == "-" \
			and date.replace("-", "").is_valid_int() and map_rows_text == daily_map(date).text:
		if daily_date != date and wave == 0:
			play_sound("daily_start")
		daily_date = date


# ----- pings (Alt + click on the map, see show_ping())

var ping_budget := [PING_BURST, PING_BURST, PING_BURST, PING_BURST]  # host: pings each player may still send
var ping_budget_time := [0.0, 0.0, 0.0, 0.0]
var ping_warned := [false, false, false, false]  # host: told to slow down since their last ping


# This player pings pos (map pixels, like mouse_point()).
func send_ping(pos: Vector2) -> void:
	match net_mode:
		"client":
			net_request.rpc_id(1, "ping", [pos])
		"host":
			host_ping(local_slot, pos)
		"":
			show_ping(local_slot, pos)  # alone: only here


# Host: a player's ping, shown to everyone unless they ping too fast.
func host_ping(slot: int, pos: Vector2) -> void:
	if players[slot] == null or not pos.is_finite() or not Rect2(0, 0, map_cols * CELL, map_rows * CELL).has_point(pos):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var budget: float = minf(ping_budget[slot] + (now - ping_budget_time[slot]) / PING_REFILL, PING_BURST)
	ping_budget_time[slot] = now
	if budget < 1.0:
		ping_budget[slot] = budget
		if not ping_warned[slot]:
			ping_warned[slot] = true
			note_to(slot, "Slow down, you're pinging too fast")
		return
	ping_budget[slot] = budget - 1.0
	ping_warned[slot] = false
	show_ping(slot, pos)
	send_all("net_show_ping", [slot, pos])


# Its name sorts after net_refused (see net_say).
@rpc("authority", "call_remote", "reliable")
func net_show_ping(slot: Variant, pos: Variant) -> void:
	if net_mode != "client" or not (slot is int and pos is Vector2) or slot < 0 or slot >= MAX_PLAYERS or not pos.is_finite():
		return
	show_ping(slot, pos)


# Host: a message for one player (flash on their screen).
func note_to(slot: int, text: String) -> void:
	if players[slot] == null:
		return
	if slot == local_slot:
		flash(text)
	else:
		net_message.rpc_id(players[slot].peer, text)


# ----- gifts (perform("gift") in main.gd calls gift_gold())

var gift_time := [-100.0, -100.0, -100.0, -100.0]  # host: when each player last gave gold


# Host: player `slot` gives `amount` gold to player `to`. Returns a message for
# the giver if it can't be done, or "". Everyone sees it in the chat, and the
# stats count it apart from gold earned and spent (stat_gifted).
func gift_gold(slot: int, to: int, amount: int) -> String:
	if state != "playing" or slot < 0 or slot >= MAX_PLAYERS or players[slot] == null:
		return ""
	if to < 0 or to >= MAX_PLAYERS or to == slot or players[to] == null:
		return "That player isn't in the game"
	if amount < 1 or amount > players[slot].gold:
		return "Not enough gold"
	var now := Time.get_ticks_msec() / 1000.0
	if now - gift_time[slot] < GIFT_WAIT:
		return "Wait a moment before giving gold again"
	amount = mini(amount, GOLD_MAX - players[to].gold)
	if amount < 1:
		return "%s can't carry more gold" % name_of(to)
	gift_time[slot] = now
	players[slot].gold -= amount
	players[to].gold += amount
	stat_gifted[slot] -= amount
	stat_gifted[to] += amount
	chat_note("%s gave %s gold to %s" % [name_of(slot), short(amount), name_of(to)])
	note_to(to, "%s gave you %s gold!" % [name_of(slot), short(amount)])
	note_to(slot, "You gave %s gold to %s" % [short(amount), name_of(to)])
	return ""


# Host: the difficulty level changed (see set_difficulty() in main.gd).
func send_difficulty() -> void:
	send_all("net_set_difficulty", [difficulty])
	if board_open:
		show_board_level(difficulty)


# An entry from the server, checked and cleaned like anything from the network, or {}.
func board_entry(e: Variant) -> Dictionary:
	if not (e is Dictionary and e.get("names") is Array and e.get("wave") is float and e.get("ms") is float):
		return {}
	var names: Array[String] = []
	for n: Variant in e.names.slice(0, MAX_PLAYERS):
		var s := clean_text(str(n), NAME_MAX)
		if s != "":
			names.append(s)
	if names.is_empty():
		return {}
	return {"names": names, "wave": int(e.wave), "won": e.get("won") == true, "ms": maxi(int(e.ms), 0)}


# Game time as "12:34", or "1:02:03" past an hour.
func board_time_text(ms: int) -> String:
	var s := int(ms / 1000.0)
	if s >= 3600:
		return "%d:%02d:%02d" % [int(s / 3600.0), int(s / 60.0) % 60, s % 60]
	return "%d:%02d" % [int(s / 60.0), s % 60]


func host_direct() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(NET_PORT, MAX_PLAYERS - 1) != OK:
		net_status = "Couldn't start hosting. Is the game already hosting in another window?"
		return
	# Players only talk to the host, so Godot doesn't need to tell them about
	# each other (that also sends to players who are leaving at the same moment)
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	net_mode = "host"
	players[local_slot].peer = 1
	# Players on the same network find this game by asking for its code
	search_peer = PacketPeerUDP.new()
	if search_peer.bind(SEARCH_PORT) != OK:
		search_peer = null
	invite_code = make_code()
	net_status = "Couldn't reach the game server, so only players on your network (Wi-Fi) can join."
	if search_peer == null:
		net_status = "Another game on this PC is already hosting, so players on your network can't find this one."


# Host: answers players on the local network who are looking for our code.
func answer_searches() -> void:
	while search_peer.get_available_packet_count() > 0:
		var message := search_peer.get_packet().get_string_from_utf8()
		if invite_code != "" and message == "GTD?" + invite_code:
			search_peer.set_dest_address(search_peer.get_packet_ip(), search_peer.get_packet_port())
			search_peer.put_packet(("GTD!" + invite_code).to_utf8_buffer())


func _exit_tree() -> void:
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


# A random 5-letter code for a game hosted on the local network. (The game
# server makes the codes for its games.)
func make_code() -> String:
	var code := ""
	for i in 5:
		code += CODE_LETTERS[randi() % CODE_LETTERS.length()]
	return code


# Cleans up what a player typed: capitals, no spaces or dashes, and letters that
# look alike (O and 0, I and L and 1) read as the ones codes use.
func clean_code(typed: String) -> String:
	var code := ""
	for ch in typed.to_upper().replace("O", "0").replace("I", "1").replace("L", "1"):
		if CODE_LETTERS.contains(ch):
			code += ch
	return code


# Looks for the game on the local network first, then on the game server.
func join_game() -> void:
	code_input.release_focus()
	save_name()
	var code := clean_code(code_input.text)
	if code.length() != 5:
		net_status = "That invite code doesn't look right. It has 5 letters and digits."
		return
	start_search(code)


func join_relay(code: String) -> void:
	close_connection()
	relay = RelayPeer.new(relay_address("/join?code=" + code))
	multiplayer.multiplayer_peer = relay
	net_addresses.clear()
	net_mode = "connecting"
	net_connect_time = 0.0
	net_status = "Joining game %s..." % code


func relay_join_failed() -> void:
	var reason := "Couldn't reach the game server. Check your internet connection."
	if relay != null and relay.error != "":
		reason = relay.error
	close_connection()
	net_mode = ""
	net_status = reason


# First ask everyone on the local network which game has the code.
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
	net_status = "Looking for game %s..." % code


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
		if reply == "GTD!" + search_code and not search_found.has(ip):
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
	elif search_time > 0.8:
		# Not on this network: ask the game server
		close_search()
		if relay_url != "":
			join_relay(search_code)
		else:
			net_mode = ""
			net_status = "Couldn't find game %s on your network. Check the code." % search_code


func close_search() -> void:
	if search_peer != null:
		search_peer.close()
		search_peer = null


# Tries the host's addresses from the invite code one by one.
func try_next_address() -> void:
	close_connection()
	if net_addresses.is_empty():
		net_mode = ""
		net_status = "Couldn't reach the host. Check the code, and that the host is still hosting. The host may need to allow the game through the Windows firewall."
		return
	var address: String = net_addresses.pop_front()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, NET_PORT) != OK:
		try_next_address()
		return
	multiplayer.multiplayer_peer = peer
	net_connect_time = 0.0
	net_status = "Connecting to the host..."


func close_connection() -> void:
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	relay = null


func stop_hosting() -> void:
	close_connection()
	close_search()
	net_mode = ""
	invite_code = ""
	net_status = ""
	requests.clear()
	asks.clear()
	joining.clear()
	for slot in MAX_PLAYERS:
		if slot != local_slot:
			players[slot] = null
			spawn_queues[slot].clear()


# Back to playing alone, with a fresh game.
func leave_game(text: String) -> void:
	close_connection()
	net_mode = ""
	back_to_own_map()
	play_alone()
	net_status = text
	flash(text)


func _on_connected_to_host() -> void:
	if net_mode == "connecting":
		net_join.rpc_id(1, version)
		# Separate from net_join, so a host with another version can still
		# tell us the versions differ (it doesn't know this message)
		net_try_join.rpc_id(1, my_name(), map_hash(map_rows_text), false)


func _on_connection_failed() -> void:
	if net_mode != "connecting":
		return
	if relay != null:
		relay_join_failed()
	else:
		try_next_address()


func _on_host_left() -> void:
	if net_mode == "client":
		leave_game("The host left the game.")
	elif net_mode == "map_offer":
		stop_joining("The host left before you joined.")
	elif net_mode == "connecting":
		try_next_address()


func _on_peer_connected(_id: int) -> void:
	pass  # the host waits for net_join, which says which version the player has


func _on_peer_disconnected(id: int) -> void:
	if net_mode != "host":
		return
	joining.erase(id)
	for slot in MAX_PLAYERS:
		if players[slot] != null and players[slot].peer == id:
			var p_name: String = players[slot].name
			stat_names[slot] = name_of(slot)  # still shown in the stats at the end
			players[slot] = null
			spawn_queues[slot].clear()
			wave_votes.erase(slot)
			send_players()
			if p_name != "":
				chat_note("%s left the game" % p_name)
			check_wave_votes()


func send_players() -> void:
	var list := []
	for p in players:
		if p != null:
			list.append([p.peer, p.slot, p.name])
	send_all("net_players", [list])


func send_tower(t: Tower) -> void:
	send_all("net_tower", [t.cell, t.type, t.level, t.owner, t.spent, t.mode, t.path])


# Where every monster is, 9 bytes each (see net_snapshot). On the local network
# the monsters are split over several messages, so each one fits in a single
# network packet (ENet sends at most 1392 bytes at once; bigger messages get
# cut up and are lost when any piece is). Each message says which monster ids
# it covers, so the players can tell which monsters are gone even when one of
# the messages doesn't arrive. The game server has no such limit: one message.
func send_snapshot() -> void:
	send_held()
	var golds := []
	for p in players:
		golds.append(p.gold if p != null else 0)
	var info := [wave, next_wave_timer, state, game_speed, monsters_left_to_spawn(), golds, wave_votes]
	# The Barracks' soldiers (see barracks_info()), only while there is a Barracks.
	# Older games read info[0] to info[6] and never look further.
	var soldiers := barracks_info()
	if not soldiers.is_empty():
		info.append(soldiers)
	var most := SNAPSHOT_MONSTERS if relay == null else 1 << 20
	var start := 0
	while true:
		# enemies is in id order (new monsters get the next id and go last)
		var base: int = enemies[start].id if start < enemies.size() else 0
		var end := start
		# The first message also carries the soldiers: fewer monsters, so it still fits one packet
		var room := most
		if start == 0 and not soldiers.is_empty():
			room = maxi(1, most - ceili((soldiers.size() + 8) / 9.0))
		while end < enemies.size() and end - start < room and enemies[end].id - base < 65536:
			end += 1
		var data := PackedByteArray()
		data.resize(8 + (end - start) * 9)
		data.encode_u32(0, base)
		# Covers the ids up to the next message's first monster (0: all the rest)
		data.encode_u32(4, enemies[end].id if end < enemies.size() else 0)
		var at := 8
		for i in range(start, end):
			var e := enemies[i]
			data.encode_u16(at, e.id - base)
			encode_monster(data, at + 2, e)
			e.sent = true
			at += 9
		# The wave, timer and gold only go with the first message
		send_all("net_snapshot", [info if start == 0 else [], data])
		start = end
		if start >= enemies.size():
			break


# A monster's 7 bytes in snapshots: x and y in 1/32 pixels (u16 each), health
# as a share of full health (u16), and one byte: its kind (bits 0-1), its trait
# and shield (bits 2-4, see special_bits()), 32 when it got past (for the
# replay), 64 when it's frozen, 128 when it's slowed. That byte is full: being
# poisoned isn't sent (it would cost a 10th byte per monster).
func encode_monster(data: PackedByteArray, at: int, e: Enemy) -> void:
	data.encode_u16(at, clampi(roundi(e.pos.x * 32.0), 0, 65535))
	data.encode_u16(at + 2, clampi(roundi(e.pos.y * 32.0), 0, 65535))
	data.encode_u16(at + 4, clampi(roundi(e.hp / e.max_hp * 65535.0), 0, 65535))
	data[at + 6] = ENEMY_KINDS.find(e.kind) | special_bits(e) | (32 if got_past(e) else 0) \
			| (64 if e.freeze_time > 0.0 else 0) | (128 if e.slow_time > 0.0 else 0)


# Players: a monster from its 7 bytes (see encode_monster), made if it's new.
func decode_monster(id: int, data: PackedByteArray, at: int) -> Enemy:
	var p := Vector2(data.decode_u16(at), data.decode_u16(at + 2)) / 32.0
	var e: Enemy = enemy_by_id.get(id)
	if e == null:
		e = make_enemy(ENEMY_KINDS[data[at + 6] & 3])
		e.id = id
		e.pos = p
		# Its trait (splitter, splitling, healer); splitlings are smaller, like on the host
		apply_special_bits(e, data[at + 6])
		if e.special == "splitling":
			e.radius *= 0.75
		enemies.append(e)
		enemy_by_id[id] = e
	e.net_pos = p
	e.max_hp = 1.0
	e.hp = data.decode_u16(at + 4) / 65535.0
	e.slow_time = 1.0 if data[at + 6] & 128 else 0.0
	e.freeze_time = 1.0 if data[at + 6] & 64 else 0.0
	e.past = (data[at + 6] & 32) != 0
	# Whether its shield is up (it breaks and regrows on the host)
	apply_special_bits(e, data[at + 6])
	return e


# Host: tells the other players tower t shot at monster e. A monster that no
# snapshot has had yet (it just came out of its gate) comes with the shot, or
# the players wouldn't know it and would drop the shot (a Sniper by a gate kills
# most of its targets before the next snapshot).
func send_shot(t: Tower, e: Enemy) -> void:
	if e.sent:
		send_all("net_shot", [t.cell, e.id])
		return
	var rec := PackedByteArray()
	rec.resize(7)
	encode_monster(rec, 0, e)
	send_all("net_shot_new", [t.cell, e.id, rec])


# ----- messages from a player to the host

@rpc("any_peer", "call_remote", "reliable")
func net_join(their_version: String) -> void:
	if net_mode != "host":
		return
	var peer := multiplayer.get_remote_sender_id()
	if their_version != version:
		net_refused.rpc_id(peer, "The host has version %s and you have %s. You both need the same version." % [version, their_version])
		return
	# The same version: net_try_join comes next, with the player's name and map
	joining[peer] = 0


# After net_join: the player's name and which map they have (its sha256).
# confirmed: they said yes to the map the host offered them. Its name sorts
# after net_refused, like net_say (see there).
@rpc("any_peer", "call_remote", "reliable")
func net_try_join(their_name: Variant, their_map: Variant, confirmed: Variant) -> void:
	if net_mode != "host":
		return
	var peer := multiplayer.get_remote_sender_id()
	if not joining.has(peer) or not (their_name is String and their_map is String and confirmed is bool):
		return
	# A loaded game: the slot saved with their name (or another saved one) first
	var slot := saved_slot_for(their_name)
	if slot < 0:
		slot = free_slot()
	if slot < 0:
		joining.erase(peer)
		var n := map_slots()
		net_refused.rpc_id(peer, "That game is full (%d player%s)." % [n, "" if n == 1 else "s"])
		return
	var mine := map_hash(map_rows_text)
	# Players on another map get this one first, unless it's a built-in map (everyone of this version has those)
	if their_map != mine and builtin_map_name(map_rows_text) == "":
		if confirmed:
			joining.erase(peer)
			net_refused.rpc_id(peer, "The host changed the map. Try joining again.")
		elif joining[peer] < OFFER_MAX:
			joining[peer] += 1
			net_show_map.rpc_id(peer, map_name, my_name(), map_rows_text)
		return
	joining.erase(peer)
	var p := Player.new()
	p.peer = peer
	p.slot = slot
	p.name = unique_name(their_name, slot)
	players[slot] = p
	# Back in a loaded game: their saved gold, cooldowns and stats
	var restored := restore_saved_player(p)
	if not restored:
		# Joining late: half the gold the others could have earned by now (at least the start gold)
		p.gold = maxi(start_gold(), int(gold_before_wave(wave) / 2.0))
		# The stats start fresh for this slot (an earlier player there is forgotten)
		stat_kills[slot] = 0
		stat_damage[slot] = 0.0
		stat_start[slot] = p.gold
		stat_earned[slot] = 0
		stat_spent[slot] = 0
		stat_gifted[slot] = 0
		stat_names[slot] = p.name
	gift_time[slot] = -100.0
	ping_budget[slot] = PING_BURST
	net_welcome.rpc_id(peer, slot, mine)
	net_set_difficulty.rpc_id(peer, difficulty)
	if endless:
		net_set_endless.rpc_id(peer, true)
	if daily_date != "":
		net_set_daily.rpc_id(peer, daily_date)
	for t: Tower in towers.values():
		net_tower.rpc_id(peer, t.cell, t.type, t.level, t.owner, t.spent, t.mode, t.path)
	# Joining a game that just ended: its stats too
	if not end_stats.is_empty():
		net_stats.rpc_id(peer, end_stats)
	send_players()
	# After the player list (which starts a new player's cooldowns empty)
	if restored and not p.cooldowns.is_empty():
		send_all("net_set_cooldowns", [slot, p.cooldowns])
	# A loaded game on hold: the newcomer gets the hold, everyone the new "waiting for"
	if held:
		net_set_held.rpc_id(peer, true, held_text())
	send_held()
	chat_note("%s is back" % p.name if restored else "%s joined the game" % p.name)


@rpc("any_peer", "call_remote", "reliable")
func net_request(action: String, args: Array) -> void:
	if net_mode != "host":
		return
	var peer := multiplayer.get_remote_sender_id()
	for p in players:
		if p != null and p.peer == peer:
			# Chat is for the network, not the game rules
			if action == "chat" and args.size() == 1 and args[0] is String:
				host_chat(p.slot, args[0])
				return
			if action == "ping" and args.size() == 1 and args[0] is Vector2:
				host_ping(p.slot, args[0])
				return
			var error := perform(p.slot, action, args)
			if error != "":
				net_message.rpc_id(peer, error)
			return


# ----- messages from the host to the players

# The host's map, for a player who doesn't have it. Nothing is used before the
# player says yes in the preview (see accept_offer()).
@rpc("authority", "call_remote", "reliable")
func net_show_map(title: Variant, host_name: Variant, rows: Variant) -> void:
	if net_mode != "connecting" and net_mode != "map_offer":
		return
	var problem := offer_problem(title, host_name, rows)
	if problem != "":
		stop_joining(problem)
		return
	var host_called := clean_text(host_name, NAME_MAX)
	map_offer = {"name": clean_text(title, MAP_NAME_MAX), "host": host_called if host_called != "" else "The host",
			"rows": rows.duplicate(), "hash": map_hash(rows), "check": read_map(rows), "keep": false, "accepted": false}
	if map_offer.name == "":
		map_offer.name = "Unnamed map"
	net_mode = "map_offer"
	menu_open = true
	code_input.release_focus()
	name_input.release_focus()


# slot: our player slot. map: the sha256 of the host's map, which must be ours,
# a built-in map (BUILTIN_MAPS) or the one we said yes to.
@rpc("authority", "call_remote", "reliable")
func net_welcome(slot: Variant, map: Variant) -> void:
	if net_mode != "connecting" and net_mode != "map_offer":
		return
	if not (slot is int and slot >= 0 and slot < MAX_PLAYERS and map is String):
		stop_joining("The host sent something broken, so you didn't join.")
		return
	var rows: Array = []
	var title := ""
	if map != map_hash(map_rows_text):
		# A built-in map (Default, Serpent...): every game of this version has it
		for n: String in BUILTIN_MAPS:
			if map == map_hash(BUILTIN_MAPS[n]):
				rows = builtin_map_rows(n)
				title = n
				break
	if map == map_hash(map_rows_text) or not rows.is_empty():
		pass  # we have the host's map already, or it's built in
	elif map_offer.get("accepted", false) and map == map_offer.hash:
		rows = map_offer.rows
		title = map_offer.name
	else:
		stop_joining("The host's map isn't the one you were shown, so you didn't join.")
		return
	var keep: bool = map_offer.get("keep", false) and rows == map_offer.get("rows")
	map_offer = {}
	net_mode = "client"
	clear_world()
	daily_date = ""  # the host says if it plays the daily challenge (net_set_daily)
	if not rows.is_empty():
		if own_map.is_empty():
			own_map = [map_rows_text, map_name]
		use_map(read_map(rows), title)
		build_map()
		if keep:
			keep_map(title, rows)
	players = [null, null, null, null]
	local_slot = slot
	var me := Player.new()
	me.slot = slot
	me.name = my_name()  # until the host's list says which name we got
	players[slot] = me
	menu_open = false
	code_input.release_focus()
	name_input.release_focus()
	net_status = ""
	flash("You joined as %s!" % PLAYER_NAMES[slot])


@rpc("authority", "call_remote", "reliable")
func net_refused(reason: String) -> void:
	close_connection()
	net_mode = ""
	map_offer = {}
	net_status = clean_text(reason, 300)


@rpc("authority", "call_remote", "reliable")
func net_players(list: Array) -> void:
	if net_mode != "client":
		return
	var old := players
	players = [null, null, null, null]
	for item in list:
		var p := Player.new()
		p.peer = item[0]
		p.slot = item[1]
		p.name = clean_text(str(item[2]), NAME_MAX)
		var was: Player = old[p.slot]
		if was != null:
			p.gold = was.gold
			# The same player keeps their ability cooldowns (a new one starts with none)
			if was.peer == p.peer:
				p.cooldowns = was.cooldowns
		players[p.slot] = p


@rpc("authority", "call_remote", "reliable")
func net_message(text: String) -> void:
	flash(text)


# The host's difficulty level (index in DIFFICULTIES), when it changes and when
# we join. Only shown and used for the leaderboard: monster health comes from
# the host. Its name sorts after net_refused (see net_say).
@rpc("authority", "call_remote", "reliable")
func net_set_difficulty(d: Variant) -> void:
	if net_mode != "client" or not (d is int and d >= 0 and d < DIFFICULTIES.size()):
		return
	difficulty = d
	if board_open:
		show_board_level(d)
	else:
		board_level = d


# Host: a player used an ability (see do_ability() in main.gd).
func send_ability(slot: int, ability: String, at: Vector2) -> void:
	send_all("net_used_ability", [slot, ability, at])


# Host: the game keeps going in endless mode (see keep_going() in main.gd).
func send_endless() -> void:
	send_all("net_set_endless", [true])


# A player used an ability: their cooldown starts here too, and it shows. The
# damage and the freezing are the host's (the monsters come in the snapshots);
# freeze_all() here only makes them stand still right away. Its name sorts
# after net_refused (see net_say).
@rpc("authority", "call_remote", "reliable")
func net_used_ability(slot: Variant, ability: Variant, at: Variant) -> void:
	if net_mode != "client" or not (slot is int and ability is String and at is Vector2 and ABILITIES.has(ability)):
		return
	if slot < 0 or slot >= MAX_PLAYERS or not at.is_finite():
		return
	start_cooldown(slot, ability)
	show_ability(slot, ability, at)
	if ability == "freeze":
		freeze_all()


# Endless mode, when the host keeps going after the last wave and when we join
# a game in endless mode (net_reset turns it off). Its name sorts after net_refused.
@rpc("authority", "call_remote", "reliable")
func net_set_endless(on: Variant) -> void:
	if net_mode != "client" or not on is bool:
		return
	if on and not endless and state == "won":
		play_sound("endless_start")
	endless = on
	if on:
		state = "playing"
		end_stats = {}


# ----- a loaded game on hold (see held_text() in main.gd)

var held_sent := [false, ""]  # host: the hold and its text the players last got


# Host, with every snapshot and when someone joins: tells the players when the
# hold or who it waits for changed (a few messages per loaded game).
func send_held() -> void:
	var now := [held, held_text()]
	if now != held_sent:
		held_sent = now
		send_all("net_set_held", now)


# Whether the host's loaded game is on hold, and its "waiting for" line. Its
# name sorts after net_refused (see net_say).
@rpc("authority", "call_remote", "reliable")
func net_set_held(on: Variant, note: Variant) -> void:
	if net_mode != "client" or not (on is bool and note is String):
		return
	held = on
	held_note = clean_text(note, 200) if on else ""
	if on:
		flash(held_note)


# A player back in a loaded game: their saved ability cooldowns. Its name sorts
# after net_refused (see net_say).
@rpc("authority", "call_remote", "reliable")
func net_set_cooldowns(slot: Variant, cools: Variant) -> void:
	if net_mode != "client" or not (slot is int and cools is Dictionary) or slot < 0 or slot >= MAX_PLAYERS or players[slot] == null:
		return
	var clean := {}
	for a: Variant in cools:
		if a is String and ABILITIES.has(a) and (cools[a] is float or cools[a] is int):
			clean[a] = clampf(float(cools[a]), 0.0, ABILITIES[a]["cooldown"])
	players[slot].cooldowns = clean


# ----- the profile (see apply_profile_update() in game_base.gd)

# Host: a player's profile update (main.gd's profile_update(), at every wave
# start and at the end of a game), only to that player. A few hundred bytes.
func send_profile_update(slot: int, data: Dictionary) -> void:
	if net_mode != "host" or slot < 0 or slot >= MAX_PLAYERS or slot == local_slot:
		return
	var p: Player = players[slot]
	if p == null or p.peer == 1:
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.get_peer(p.peer).get_state() != ENetPacketPeer.STATE_CONNECTED:
		return
	net_set_profile.rpc_id(p.peer, data)


# Our profile update from the host. "authority" already drops it from anyone
# else; the sender and mode checks are a second lock (the replay plays only
# recorded frames, never messages, so it can't count anything twice).
# apply_profile_update() checks every field. Its name sorts after net_refused (see net_say).
@rpc("authority", "call_remote", "reliable")
func net_set_profile(data: Variant) -> void:
	if net_mode != "client" or multiplayer.get_remote_sender_id() != 1 or not data is Dictionary:
		return
	apply_profile_update(data)


# A chat line for everyone (slot -1: from the game itself). Its name sorts after
# net_refused, so the messages older versions use to check the version keep
# their numbers (Godot numbers the @rpc functions alphabetically).
@rpc("authority", "call_remote", "reliable")
func net_say(slot: int, who: String, text: String) -> void:
	add_chat(clampi(slot, -1, MAX_PLAYERS - 1), clean_text(who, NAME_MAX), clean_text(text, CHAT_MAX))


# Another player asks to build in our area.
@rpc("authority", "call_remote", "reliable")
func net_ask(id: int, from_slot: int, type: String, cell: Vector2i) -> void:
	asks.append([id, from_slot, type, cell])


@rpc("authority", "call_remote", "reliable")
func net_ask_closed(id: int) -> void:
	close_ask(id)


@rpc("authority", "call_remote", "reliable")
func net_reset() -> void:
	clear_world()
	reset_stats()
	endless = false
	held = false
	held_note = ""
	for p in players:
		if p != null:
			p.cooldowns = {}


# The stats at the end of the game (see make_end_stats()), sent once by the host
# when the game is won or lost. Its name sorts after net_refused (see net_say).
@rpc("authority", "call_remote", "reliable")
func net_stats(stats: Variant) -> void:
	if net_mode != "client" or not stats is Dictionary:
		return
	# Only what the stats screen can show
	var rows := []
	for r: Variant in stats.get("players", []):
		# [slot, name, kills, damage, earned, spent, gifted] (gifted: received minus given)
		if r is Array and (r.size() == 6 or r.size() == 7) and r[0] is int and r[0] >= 0 and r[0] < MAX_PLAYERS:
			rows.append([r[0], clean_text(str(r[1]), NAME_MAX), int(r[2]), float(r[3]), int(r[4]), int(r[5]),
					int(r[6]) if r.size() == 7 else 0])
	var best := []
	for r: Variant in stats.get("towers", []):
		if r is Array and r.size() == 7 and TOWERS.has(r[0]) and r[1] is int and r[2] is int and r[3] is int \
				and r[3] >= 0 and r[3] < MAX_PLAYERS:
			best.append([r[0], clampi(r[1], 0, 2), clampi(r[2], 0, MAX_LEVEL - 1), r[3], clean_text(str(r[4]), NAME_MAX), float(r[5]), int(r[6])])
	var mvp: Variant = stats.get("mvp", -1)
	end_stats = {"wave": int(stats.get("wave", wave)), "won": stats.get("won") == true, "ms": int(stats.get("ms", 0)),
			"players": rows, "towers": best.slice(0, 5), "mvp": mvp if mvp is int else -1}


@rpc("authority", "call_remote", "reliable")
func net_tower(cell: Vector2i, type: String, level: int, owner_slot: int, spent: int, mode: int, path: int) -> void:
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
	t.mode = mode
	t.path = path
	build_tower_node(t)


# A tower's targeting mode changed (only the panel shows it; the host does the aiming).
@rpc("authority", "call_remote", "reliable")
func net_tower_mode(cell: Vector2i, mode: int) -> void:
	var t: Tower = towers.get(cell)
	if t != null:
		t.mode = mode


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


# A shot at a monster that no snapshot has had yet: the monster comes with it
# (its 7 bytes, see send_shot()). The next snapshot moves it, or takes it away
# if it's already dead. Its name sorts after net_refused (see net_say).
@rpc("authority", "call_remote", "unreliable_ordered")
func net_shot_new(cell: Vector2i, target_id: int, rec: PackedByteArray) -> void:
	if net_mode != "client" or rec.size() != 7 or target_id < 0:
		return
	var t: Tower = towers.get(cell)
	if t == null:
		return
	var target := decode_monster(target_id, rec, 0)
	t.aim = (target.pos - t.pos).normalized()
	launch_shot(t, target, true)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_bolt(points: PackedVector3Array) -> void:
	add_bolt(points)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_boom(pos: Vector2, r: float) -> void:
	add_boom(pos, r)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_frost_ring(pos: Vector2, r: float) -> void:
	add_frost_ring(pos, r)


# Blizzard's hit: a pale blue ring the size of its area. A placeholder (the
# cannon's blast in ice colors) until the graphics get a real one; it fades
# like the blast does (the "boom" effect in update_effects()).
func add_frost_ring(pos: Vector2, r: float) -> void:
	var m := mat(Color(0.55, 0.85, 1.0), 1.5, 0.5)
	var node := add_mesh(self, boom_mesh, m, to3d(pos, 0.15))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3.ZERO
	effects.append({"kind": "boom", "node": node, "mat": m, "radius": r, "time": 0.35, "max": 0.35})


# Where the monsters are (some or all of them, see send_snapshot). The first
# message of each update also has the wave, timer and everyone's gold.
# data: the first monster's id (u32), the id after the last one this message
# covers (u32, 0: no end), then per monster 9 bytes: id minus the first id
# (u16), x and y in 1/32 pixels (u16 each), health share of 65535 (u16), and
# its kind with 128 added when it's slowed and 64 when it's frozen (u8).
@rpc("authority", "call_remote", "unreliable_ordered")
func net_snapshot(info: Array, data: PackedByteArray) -> void:
	if net_mode != "client" or data.size() < 8:
		return
	if not info.is_empty():
		wave = info[0]
		next_wave_timer = info[1]
		state = info[2]
		game_speed = info[3]
		net_spawn_left = info[4]
		wave_votes = info[6]
		var golds: Array = info[5]
		for slot in MAX_PLAYERS:
			if players[slot] != null:
				players[slot].gold = golds[slot]
		# The Barracks' soldiers, when the host has a Barracks (apply_barracks_info() checks it)
		if info.size() > 7:
			apply_barracks_info(info[7])
	var base := data.decode_u32(0)
	var end := data.decode_u32(4)
	# The first message also covers every id before its first monster
	var from := 0 if not info.is_empty() else base
	var seen := {}
	for at in range(8, data.size() - 8, 9):
		var id := base + data.decode_u16(at)
		seen[id] = true
		decode_monster(id, data, at + 2)
	# Monsters in this message's id range that the host no longer has were killed
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if e.id >= from and (end == 0 or e.id < end) and not seen.has(e.id):
			e.dead = true
			drop_corpse(e)
			enemy_by_id.erase(e.id)
			enemies.remove_at(i)
