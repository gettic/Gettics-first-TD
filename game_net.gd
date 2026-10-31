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
	game_info_timer -= delta
	if game_info_timer <= 0.0:
		game_info_timer = 3.0
		relay.send_text({"t": "info", "public": public_game, "players": player_count(), "wave": wave})


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

# Each board is named after the last wave and this number: raise it after a
# balance change, so new scores aren't mixed with ones from the old rules.
const BOARD_SEASON := 1
const BOARD_ROWS := 10

var board_open := false  # the leaderboard box in the Esc menu
var board_top: Array = []  # [{names, wave, won, ms}], best first
var board_me := {}  # this player's best entry and its rank ({} if none)
var board_status := ""
var board_http: HTTPRequest
var board_asked := -100.0  # when the list was last asked for, in seconds
var run_time := 0.0  # host / alone: game seconds since wave 1 started
var score_sent := false
var score_http: HTTPRequest


func board_id() -> String:
	return "%dw-%d" % [MAX_WAVE, BOARD_SEASON]


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


func submit_score() -> void:
	# Only the Default map: on a map of your own the waves can be made easy
	if relay_url == "" or map_rows_text != DEFAULT_MAP or score_http != null:
		return
	var names := []
	for p in players:
		if p != null:
			names.append(my_name() if p.slot == local_slot else name_of(p.slot))
	var body := JSON.stringify({"board": board_id(), "names": names, "wave": wave, "won": state == "won", "ms": int(run_time * 1000.0)})
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
	var text := "You're #%d on the leaderboard!" % int(r.rank)
	if player_count() > 1:
		text = "Your team is #%d on the leaderboard!" % int(r.rank)
	flash(text)
	send_all("net_message", [text])


func open_board() -> void:
	board_open = true
	if Time.get_ticks_msec() / 1000.0 - board_asked > 30.0:
		refresh_board()


# Refresh waits a few seconds between asks.
func can_refresh_board() -> bool:
	return board_http == null and Time.get_ticks_msec() / 1000.0 - board_asked > 5.0


func refresh_board() -> void:
	if not can_refresh_board():
		return
	if relay_url == "":
		board_status = "The leaderboard needs the game server, and this game only uses your network."
		return
	board_asked = Time.get_ticks_msec() / 1000.0
	board_status = "Loading the leaderboard..."
	board_http = HTTPRequest.new()
	board_http.timeout = 8.0
	add_child(board_http)
	board_http.request_completed.connect(_on_board_loaded)
	var url := relay_url + "/scores?board=%s&me=%s" % [board_id(), my_name().to_lower().uri_encode()]
	if board_http.request(url) != OK:
		_on_board_loaded(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _on_board_loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	board_http.queue_free()
	board_http = null
	var r: Variant = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
	if code == 429:
		board_status = "The game server is busy. Try again in a minute."
		return
	if code != 200 or not (r is Dictionary and r.get("top") is Array):
		board_status = "Couldn't reach the game server. Check your internet connection and try again."
		return
	board_top.clear()
	for e: Variant in r.top:
		var entry := board_entry(e)
		if not entry.is_empty() and board_top.size() < BOARD_ROWS:
			board_top.append(entry)
	board_me = board_entry(r.get("me"))
	if not board_me.is_empty():
		board_me.rank = int(r.me.get("rank", 0)) if r.me.get("rank") is float else 0
	board_status = "Nobody is on the leaderboard yet. Be the first!" if board_top.is_empty() else ""


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
	send_all("net_tower", [t.cell, t.type, t.level, t.owner, t.spent])


# Where every monster is, 9 bytes each (see net_snapshot). On the local network
# the monsters are split over several messages, so each one fits in a single
# network packet (ENet sends at most 1392 bytes at once; bigger messages get
# cut up and are lost when any piece is). Each message says which monster ids
# it covers, so the players can tell which monsters are gone even when one of
# the messages doesn't arrive. The game server has no such limit: one message.
func send_snapshot() -> void:
	var golds := []
	for p in players:
		golds.append(p.gold if p != null else 0)
	var info := [wave, next_wave_timer, state, game_speed, monsters_left_to_spawn(), golds, wave_votes]
	var most := SNAPSHOT_MONSTERS if relay == null else 1 << 20
	var start := 0
	while true:
		# enemies is in id order (new monsters get the next id and go last)
		var base: int = enemies[start].id if start < enemies.size() else 0
		var end := start
		while end < enemies.size() and end - start < most and enemies[end].id - base < 65536:
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
			# Positions in 1/32 pixels, health as a share of full health
			data.encode_u16(at + 2, clampi(roundi(e.pos.x * 32.0), 0, 65535))
			data.encode_u16(at + 4, clampi(roundi(e.pos.y * 32.0), 0, 65535))
			data.encode_u16(at + 6, clampi(roundi(e.hp / e.max_hp * 65535.0), 0, 65535))
			data[at + 8] = ENEMY_KINDS.find(e.kind) | (128 if e.slow_time > 0.0 else 0)
			at += 9
		# The wave, timer and gold only go with the first message
		send_all("net_snapshot", [info if start == 0 else [], data])
		start = end
		if start >= enemies.size():
			break


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
	var slot := free_slot()
	if slot < 0:
		joining.erase(peer)
		var n := map_slots()
		net_refused.rpc_id(peer, "That game is full (%d player%s)." % [n, "" if n == 1 else "s"])
		return
	var mine := map_hash(map_rows_text)
	# Players on another map get this one first, unless it's the Default map (everyone has that)
	if their_map != mine and map_rows_text != DEFAULT_MAP:
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
	# Joining late: half the gold the others could have earned by now (at least the start gold)
	p.gold = maxi(START_GOLD, int(gold_before_wave(wave) / 2.0))
	players[slot] = p
	net_welcome.rpc_id(peer, slot, mine)
	for t: Tower in towers.values():
		net_tower.rpc_id(peer, t.cell, t.type, t.level, t.owner, t.spent)
	send_players()
	chat_note("%s joined the game" % p.name)


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
# the Default map or the one we said yes to.
@rpc("authority", "call_remote", "reliable")
func net_welcome(slot: Variant, map: Variant) -> void:
	if net_mode != "connecting" and net_mode != "map_offer":
		return
	if not (slot is int and slot >= 0 and slot < MAX_PLAYERS and map is String):
		stop_joining("The host sent something broken, so you didn't join.")
		return
	var rows: Array = []
	var title := ""
	if map == map_hash(map_rows_text):
		pass  # we have the host's map already
	elif map == map_hash(DEFAULT_MAP):
		rows = DEFAULT_MAP
		title = "Default"
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
	var golds := []
	for p in players:
		golds.append(p.gold if p != null else 0)
	players = [null, null, null, null]
	for item in list:
		var p := Player.new()
		p.peer = item[0]
		p.slot = item[1]
		p.name = clean_text(str(item[2]), NAME_MAX)
		p.gold = golds[p.slot]
		players[p.slot] = p


@rpc("authority", "call_remote", "reliable")
func net_message(text: String) -> void:
	flash(text)


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


# Where the monsters are (some or all of them, see send_snapshot). The first
# message of each update also has the wave, timer and everyone's gold.
# data: the first monster's id (u32), the id after the last one this message
# covers (u32, 0: no end), then per monster 9 bytes: id minus the first id
# (u16), x and y in 1/32 pixels (u16 each), health share of 65535 (u16), and
# its kind with 128 added when it's slowed (u8).
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
	var base := data.decode_u32(0)
	var end := data.decode_u32(4)
	# The first message also covers every id before its first monster
	var from := 0 if not info.is_empty() else base
	var seen := {}
	for at in range(8, data.size(), 9):
		var id := base + data.decode_u16(at)
		seen[id] = true
		var p := Vector2(data.decode_u16(at + 2), data.decode_u16(at + 4)) / 32.0
		var e: Enemy = enemy_by_id.get(id)
		if e == null:
			e = make_enemy(ENEMY_KINDS[data[at + 8] & 127])
			e.id = id
			e.pos = p
			enemies.append(e)
			enemy_by_id[id] = e
		e.net_pos = p
		e.max_hp = 1.0
		e.hp = data.decode_u16(at + 6) / 65535.0
		e.slow_time = 1.0 if data[at + 8] & 128 else 0.0
	# Monsters in this message's id range that the host no longer has were killed
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if e.id >= from and (end == 0 or e.id < end) and not seen.has(e.id):
			e.dead = true
			e.node.queue_free()
			enemy_by_id.erase(e.id)
			enemies.remove_at(i)
