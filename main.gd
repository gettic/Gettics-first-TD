extends "res://game_ui.gd"
## Gettic's first TD: the root script (see game_base.gd for how the files fit together).
## Waves, the update loop, input and player actions.

func _ready() -> void:
	if is_debug_game():
		open_log_window()
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
	build_hud()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_host)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_host_left)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--relay="):
			relay_url = arg.trim_prefix("--relay=")
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


# A fresh single-player game (at startup, or after leaving a multiplayer game).
func play_alone() -> void:
	players = [null, null, null, null]
	var me := Player.new()
	players[0] = me
	local_slot = 0
	new_game()


# ---------------------------------------------------------------- waves

# Starts the next wave. Called by the wave timer, or early by the player (Space),
# which gives 1 bonus gold for every second skipped.
func start_wave() -> void:
	if state != "playing" or wave >= MAX_WAVE:
		return
	var early_bonus := int(maxf(next_wave_timer, 0.0)) if wave > 0 else 0
	wave += 1
	wave_votes.clear()
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
# every monster of the current wave has spawned. With more players it's a vote:
# pressing again takes the vote back. Returns an error message, or "".
func call_wave(slot: int) -> String:
	if monsters_left_to_spawn() > 0:
		return "Wait until the whole wave has spawned!"
	if wave == 0 or player_count() < 2:
		start_wave()
		return ""
	var text: String
	if slot in wave_votes:
		wave_votes.erase(slot)
		text = "%s doesn't want the next wave early anymore (%d/%d)" % [PLAYER_NAMES[slot], wave_votes.size(), votes_needed()]
	else:
		wave_votes.append(slot)
		text = "%s wants the next wave early (%d/%d)" % [PLAYER_NAMES[slot], wave_votes.size(), votes_needed()]
	if not check_wave_votes():
		flash(text)
		send_all("net_message", [text])
	return ""


# Host: sends the next wave if enough players have voted for it. Also called when a
# player leaves, since fewer votes may then be enough.
func check_wave_votes() -> bool:
	if wave_votes.is_empty() or wave_votes.size() < votes_needed() or monsters_left_to_spawn() > 0:
		return false
	start_wave()
	return true


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


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	if debug_log:
		update_log_window()
	code_input.visible = menu_open and net_mode == ""
	if net_mode == "searching":
		update_search(delta)
	elif net_mode == "connecting":
		net_connect_time += delta
		if relay == null and net_connect_time > 4.0:
			try_next_address()
		elif relay != null and net_connect_time > 6.0:
			relay_join_failed()
	elif net_mode == "host":
		if search_peer != null:
			answer_searches()
		if relay != null:
			update_relay_host(delta)
		update_requests(delta)
	if menu_open and net_mode == "" and relay_url != "":
		games_timer -= delta
		if games_timer <= 0.0:
			games_timer = 5.0
			refresh_games()
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
	if log_window and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		log_window.visible = not log_window.visible
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
			KEY_Y:
				answer_ask(true)
			KEY_N:
				answer_ask(false)
			KEY_R:
				if state != "playing":
					act("restart", [])


func on_click(p: Vector2) -> void:
	if state != "playing":
		return
	if not asks.is_empty():
		if ASK_YES_RECT.has_point(p):
			answer_ask(true)
			return
		if ASK_NO_RECT.has_point(p):
			answer_ask(false)
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
		if update_dialog == "unpack_failed":
			if DIALOG_NO_RECT.has_point(p):
				update_dialog = ""
		elif update_dialog == "unpack" and CHOOSE_FOLDER_RECT.has_point(p):
			choose_unpack_folder()
		elif DIALOG_YES_RECT.has_point(p):
			if update_dialog == "unpack":
				unpack_self()
			elif update_dialog == "ask":
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
				return call_wave(slot)
		"speed":
			if slot != local_slot:
				return "Only the host can change the speed"
			game_speed = game_speed % 3 + 1
		"restart":
			if state != "playing":
				new_game()
		"answer":
			if args.size() == 2 and args[0] is int and args[1] is bool:
				answer_request(slot, args[0], args[1])
	return ""


# Host: building in another player's area needs their yes first.
func ask_to_build(slot: int, owner: int, c: Vector2i, type: String) -> String:
	for r in requests.values():
		if r.cell == c:
			return "Someone is already asking to build there"
	var id := next_request_id
	next_request_id += 1
	requests[id] = {"from": slot, "to": owner, "cell": c, "type": type, "time": 0.0}
	if owner == local_slot:
		asks.append([id, slot, type, c])
	else:
		net_ask.rpc_id(players[owner].peer, id, slot, type, c)
	return "That's %s's area. Waiting for %s to say yes..." % [PLAYER_NAMES[owner], PLAYER_NAMES[owner]]


func answer_request(slot: int, id: int, yes: bool) -> void:
	var r: Dictionary = requests.get(id, {})
	if r.is_empty() or r.to != slot:
		return
	end_request(id)
	var who: String = PLAYER_NAMES[slot]
	if not yes:
		tell(r.from, "%s said no" % who)
		return
	var error := build_tower(r.from, r.cell, r.type, true)
	if error == "" and (not towers.has(r.cell) or towers[r.cell].owner != r.from):
		error = "%s said yes, but you can't build there anymore" % who
	tell(r.from, error if error != "" else "%s said yes" % who)


# Host: forgets a request, and takes the question away from the player it was for.
func end_request(id: int) -> void:
	var r: Dictionary = requests[id]
	requests.erase(id)
	if r.to == local_slot:
		close_ask(id)
	elif players[r.to] != null:
		net_ask_closed.rpc_id(players[r.to].peer, id)


# Host: requests nobody answered in time, or from players who left.
func update_requests(delta: float) -> void:
	for id in requests.keys():
		var r: Dictionary = requests[id]
		r.time += delta
		if players[r.from] == null or players[r.to] == null:
			end_request(id)
		elif r.time > 30.0:
			end_request(id)
			tell(r.from, "%s didn't answer" % PLAYER_NAMES[r.to])


# This player answers the oldest question from another player.
func answer_ask(yes: bool) -> void:
	if asks.is_empty():
		return
	var id: int = asks[0][0]
	close_ask(id)
	act("answer", [id, yes])


# Host: shows a message to one player.
func tell(slot: int, text: String) -> void:
	if players[slot] == null:
		return
	if slot == local_slot:
		flash(text)
	else:
		net_message.rpc_id(players[slot].peer, text)


# allowed: the player whose area it is already said yes.
func build_tower(slot: int, c: Vector2i, type: String, allowed := false) -> String:
	if state != "playing" or not can_build(c):
		return ""
	var cost: int = TOWERS[type]["cost"][0]
	if players[slot].gold < cost:
		return "Not enough gold"
	var owner := area_owner(c)
	if owner >= 0 and owner != slot and not allowed:
		return ask_to_build(slot, owner, c, type)
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
