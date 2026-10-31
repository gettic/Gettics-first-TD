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
			elif packet.size() >= 6:
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
					peers.erase(id)
					peer_disconnected.emit(id)
			"error":
				error = m.text
				socket.close()

	func lost() -> void:
		status = CONNECTION_DISCONNECTED
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
			peers.erase(id)
			peer_disconnected.emit(id)

	func _close() -> void:
		socket.close()
		status = CONNECTION_DISCONNECTED
		peers.clear()
		incoming.clear()


var relay: RelayPeer  # the connection when it goes through the game server


# The game rules are in main.gd, which replaces these. They are here so this
# file can call them.
func perform(_slot: int, _action: String, _args: Array) -> String:
	return ""


func play_alone() -> void:
	pass


func check_wave_votes() -> bool:
	return false


# Host: sends a message to every player who has joined.
func send_all(method: StringName, args: Array) -> void:
	if net_mode != "host":
		return
	for p in players:
		if p != null and p.peer != 1:
			callv("rpc_id", [p.peer, method] + args)


func host_game() -> void:
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


func host_direct() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(NET_PORT, MAX_PLAYERS - 1) != OK:
		net_status = "Couldn't start hosting. Is the game already hosting in another window?"
		return
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
	if net_mode == "connecting":
		net_join.rpc_id(1, version)


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
			wave_votes.erase(slot)
			send_players()
			var text := "%s left the game" % PLAYER_NAMES[slot]
			flash(text)
			send_all("net_message", [text])
			check_wave_votes()


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
	var info := [wave, next_wave_timer, state, game_speed, monsters_left_to_spawn(), golds, wave_votes]
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
	wave_votes = info[6]
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
