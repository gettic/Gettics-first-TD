extends "res://map_editor.gd"
## Gettic's first TD: the root script (see game_base.gd for how the files fit together).
## Waves, the update loop, input and player actions.

func _ready() -> void:
	if is_debug_game():
		open_log_window()
	font = ThemeDB.fallback_font
	# The path, gates, routes and areas come from the map (see read_map())
	use_map(read_map(DEFAULT_MAP))
	build_world()
	build_hud()
	# Esc leaves the Esc menu's name and invite-code boxes, like the chat and map-name boxes
	# (the next Esc closes the menu)
	for box: LineEdit in [name_input, code_input]:
		box.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
				box.release_focus()
				box.accept_event())
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
	me.name = my_name()
	players[0] = me
	local_slot = 0
	new_game()


# ---------------------------------------------------------------- waves

# Starts the next wave. Called by the wave timer, or early by the player (Space),
# which gives bonus gold for every second skipped: the wave's income spread over
# WAVE_INTERVAL (at least 1 gold a second).
func start_wave() -> void:
	if state != "playing" or wave >= MAX_WAVE:
		return
	var skipped := int(maxf(next_wave_timer, 0.0)) if wave > 0 else 0
	wave += 1
	wave_votes.clear()
	var income := wave_income(wave)
	var early_bonus := skipped * maxi(1, int(income / WAVE_INTERVAL))
	# Every player gets the wave income, and every player's gate sends a full wave
	for p in players:
		if p != null:
			p.gold += income + early_bonus
	var text := "Wave %d! +%s gold" % [wave, short(income)]
	if early_bonus > 0:
		text = "Wave %d! +%s gold (+%s for calling early)" % [wave, short(income), short(early_bonus)]
	flash(text)
	send_all("net_message", [text])
	next_wave_timer = WAVE_INTERVAL
	spawn_hp = wave_hp(wave)
	var kind := kind_for_wave(wave)
	var count := wave_count(wave)
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
		text = "%s doesn't want the next wave early anymore (%d/%d)" % [name_of(slot), wave_votes.size(), votes_needed()]
	else:
		wave_votes.append(slot)
		text = "%s wants the next wave early (%d/%d)" % [name_of(slot), wave_votes.size(), votes_needed()]
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
	e.loop_wp = loop_starts[g]
	e.pos = e.route[0]
	e.max_hp = spawn_hp
	e.bounty = wave_bounty(wave)
	match kind:
		"fast":
			e.max_hp *= 0.6
			e.speed *= 1.7
		"armored":
			e.max_hp *= 1.3
			# Later on, armor grows with the monsters' health
			e.armor = maxf(2.0 + mini(wave, 30) * 0.6, spawn_hp * 0.0085)
		"boss":
			e.max_hp *= 15.0
			e.speed *= 0.7
			e.bounty = 40 + e.bounty * 12
			e.weight = 5
	e.hp = e.max_hp
	enemies.append(e)
	enemy_by_id[e.id] = e


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	if debug_log:
		update_log_window()
	code_input.visible = menu_open and net_mode == "" and not editing and not ed_ask_open and not pick_open and not board_open and not settings_open and update_dialog == ""
	name_input.visible = code_input.visible
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
	if net_mode != "client":
		track_score(dt)
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
	# Typing W, A, S or D in the chat or any text box (name, invite code, map name) doesn't move the camera
	if dir != Vector2.ZERO and not chatting() and not (get_viewport().gui_get_focus_owner() is LineEdit):
		# Move slower when zoomed in, so it doesn't feel too fast up close
		camera_pan += dir.normalized() * CAMERA_SPEED * zoom * delta
		camera_pan = camera_pan.clamp(-camera_limit(), camera_limit())
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
		# Frozen by Deep Freeze: stands still
		if e.freeze_time > 0.0:
			e.freeze_time -= dt
			continue
		var move := e.speed * e.slow_factor * dt
		while move > 0.0:
			var target := e.route[e.wp]
			var d := e.pos.distance_to(target)
			if d <= move:
				e.pos = target
				e.traveled += d
				move -= d
				e.wp += 1
				# After the last corner, go around the loop again from where the road joined it
				if e.wp >= e.route.size():
					e.wp = e.loop_wp
			else:
				e.pos += (target - e.pos) / d * move
				e.traveled += move
				move = 0.0


func update_towers(dt: float) -> void:
	for t: Tower in towers.values():
		t.cooldown -= dt
		if t.cooldown > 0.0:
			continue
		var data := tower_data(t.type, t.path, t.level)
		var target := find_target(t.pos, data["range"][t.level], t.mode)
		if target == null:
			continue
		t.aim = (target.pos - t.pos).normalized()
		# Keeps the time it was late by (up to one frame), so fast speeds don't slow towers down
		t.cooldown = data["cooldown"][t.level] + maxf(t.cooldown, -dt)
		if t.type == "spark":
			fire_lightning(t, target)
		elif t.type == "arrow" and t.path == 2 and t.level >= PATH_LEVEL:
			# Volley: one arrow each at the best few monsters in range
			for e in find_targets(t.pos, data["range"][t.level], t.mode, path_step(t.level, PATHS["arrow"][1]["arrows"])):
				launch_shot(t, e, false)
				send_all("net_shot", [t.cell, e.id])
		else:
			launch_shot(t, target, false)
			send_all("net_shot", [t.cell, target.id])


# Picks the enemy in range that fits the tower's targeting mode best (see
# TARGET_MODES). Ties go to the one that has walked furthest.
func find_target(from: Vector2, rng: float, mode := 0) -> Enemy:
	var best: Enemy = null
	var best_score := -INF
	var r2 := rng * rng
	for e in enemies:
		if e.dead:
			continue
		var d2 := e.pos.distance_squared_to(from)
		if d2 > r2:
			continue
		var s := target_score(e, d2, mode)
		if best == null or s > best_score or (s == best_score and e.traveled > best.traveled):
			best_score = s
			best = e
	return best


# How much a tower in this targeting mode wants to shoot e (d2: its distance squared).
func target_score(e: Enemy, d2: float, mode: int) -> float:
	match mode:
		1: return -e.traveled
		2: return e.hp
		3: return e.speed * e.slow_factor
		4: return -d2
	return e.traveled


# Volley: the best n different monsters in range, by the targeting mode.
func find_targets(from: Vector2, rng: float, mode: int, n: int) -> Array[Enemy]:
	var list := []  # [score, traveled, enemy]
	var r2 := rng * rng
	for e in enemies:
		if e.dead:
			continue
		var d2 := e.pos.distance_squared_to(from)
		if d2 <= r2:
			list.append([target_score(e, d2, mode), e.traveled, e])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	var out: Array[Enemy] = []
	for i in mini(n, list.size()):
		out.append(list[i][2])
	return out


func fire_lightning(t: Tower, first: Enemy) -> void:
	var data := tower_data("spark", t.path, t.level)
	var dmg: float = data["damage"][t.level]
	# Storm: each jump keeps more of the damage and reaches further
	var falloff := 0.8
	var jump := 110.0
	if t.path > 0 and t.level >= PATH_LEVEL:
		falloff = PATHS["spark"][t.path - 1].get("falloff", falloff)
		jump = PATHS["spark"][t.path - 1].get("jump", jump)
	var hit: Array[Enemy] = [first]
	var points := PackedVector3Array([t.node.position + t.head.position + Vector3(0, 0.1, 0), first.node.position])
	damage_enemy(first, dmg, t.owner)
	var current := first
	for i in range(data["chain"][t.level] - 1):
		dmg *= falloff
		var next: Enemy = null
		var best_dist := jump
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
	var data := tower_data(s.type, s.path, s.level)
	var dmg: float = data["damage"][s.level]
	var alive := s.target != null and not s.target.dead
	var path := s.path if s.level >= PATH_LEVEL else 0
	match s.type:
		"cannon":
			var r: float = data["splash"][s.level]
			var near := []  # Cluster: [traveled, monster] near the blast but outside it
			for e in enemies:
				if e.dead:
					continue
				var d := e.pos.distance_to(s.pos)
				if d <= r:
					damage_enemy(e, dmg, s.owner)
				elif path == 2 and d <= BOMBLET_REACH:
					near.append([e.traveled, e])
			blast(s.pos, r)
			if path == 2:
				# Bomblets land on the monsters furthest along near the blast
				near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
				for i in mini(path_step(s.level, PATHS["cannon"][1]["bomblets"]), near.size()):
					var at: Vector2 = near[i][1].pos
					for e in enemies:
						if not e.dead and e.pos.distance_to(at) <= BOMBLET_RADIUS:
							damage_enemy(e, dmg, s.owner)
					blast(at, BOMBLET_RADIUS)
		"frost":
			if alive:
				var slow: float = data["slow"][s.level]
				var hit: Array[Enemy] = [s.target]
				if path == 2:
					# Blizzard: everything around the target
					var area: float = path_step(s.level, PATHS["frost"][1]["area"])
					hit = []
					for e in enemies:
						if not e.dead and e.pos.distance_to(s.target.pos) <= area:
							hit.append(e)
					add_frost_ring(s.target.pos, area)
					send_all("net_frost_ring", [s.target.pos, area])
				for e in hit:
					e.slow_factor = minf(e.slow_factor, slow)
					e.slow_time = 2.0
					# Deep Freeze: a chance to stop it for a moment (bosses half as long)
					if path == 1 and randf() < path_step(s.level, PATHS["frost"][0]["freeze"]):
						e.freeze_time = FREEZE_TIME * (0.5 if e.kind == "boss" else 1.0)
					damage_enemy(e, dmg, s.owner)
		_:
			if alive:
				damage_enemy(s.target, dmg, s.owner)


func blast(at: Vector2, r: float) -> void:
	add_boom(at, r)
	send_all("net_boom", [at, r])


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
	# F11 or Alt+Enter: fullscreen on and off, anywhere in the game
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F11 or (event.alt_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER))):
		toggle_fullscreen()
		return
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
			menu_click(ui_mouse(true))
		elif pick_open and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Scrolls the list of maps in the Esc menu
			var step := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			ed_list_top = clampi(ed_list_top + step, 0, maxi(ed_list.size() - ED_LIST_ROWS, 0))
		return
	if editing:
		editor_input(event)
		return
	# Enter: chat (while typing, the chat box gets the keys, not the game)
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		open_chat()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			build_type = ""
			selected = null
		elif event.button_index == MOUSE_BUTTON_LEFT:
			on_click(ui_mouse())
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
			KEY_T:
				cycle_target_mode(event.shift_pressed)
			KEY_Q:
				choose_path(1)
			KEY_E:
				choose_path(2)
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
	if over_panel(p):
		# A level 4 tower of yours: the build row shows its 2 paths instead
		if picking_path():
			for i in 2:
				if PATH_RECTS[i].has_point(p):
					choose_path(i + 1)
		else:
			for i in TOWER_TYPES.size():
				if tower_button_rect(i).has_point(p):
					choose_build(TOWER_TYPES[i])
		if selected != null and UPGRADE_RECT.has_point(p):
			upgrade_selected()
		if selected != null and SELL_RECT.has_point(p):
			sell_selected()
		if selected != null and asks.is_empty() and MODE_RECT.has_point(p):
			cycle_target_mode(Input.is_key_pressed(KEY_SHIFT))
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
		var p := ui_mouse(true)
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
	if selected == null:
		return
	if needs_path(selected) and selected.owner == local_slot:
		flash(path_hint(selected))
		return
	act("upgrade", [selected.cell])


# Upgrades the selected level 4 tower to level 5 with path 1 or 2 (Q / E, or the path buttons).
func choose_path(path: int) -> void:
	if selected != null and needs_path(selected):
		act("upgrade", [selected.cell, path])


func path_hint(t: Tower) -> String:
	var p: Array = PATHS[t.type]
	return "Pick a path: Q %s or E %s" % [p[0]["name"], p[1]["name"]]


func sell_selected() -> void:
	if selected != null:
		act("sell", [selected.cell])
		selected = null


# The selected tower shoots at the next kind of monster (see TARGET_MODES).
# With Shift, all of your towers of that type switch to that mode too.
func cycle_target_mode(all_of_type: bool) -> void:
	if selected != null:
		act("target", [selected.cell, (selected.mode + 1) % TARGET_MODES.size(), all_of_type])


# ---------------------------------------------------------------- player actions

# Everything a player does to the game goes through here. Playing alone or as
# the host it happens right away; the other players ask the host to do it.
func act(action: String, args: Array) -> void:
	match net_mode:
		"client":
			net_request.rpc_id(1, action, args)
		"connecting", "map_offer":
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
			# [cell], or [cell, path] for the upgrade to level 5 (path 1 or 2)
			if args.size() == 1 and args[0] is Vector2i:
				return upgrade_tower(slot, args[0], 0)
			if args.size() == 2 and args[0] is Vector2i and args[1] is int:
				return upgrade_tower(slot, args[0], args[1])
		"sell":
			if args.size() == 1 and args[0] is Vector2i:
				return sell_tower(slot, args[0])
		"target":
			if args.size() == 3 and args[0] is Vector2i and args[1] is int and args[2] is bool:
				return set_target_mode(slot, args[0], args[1], args[2])
		"wave":
			if state == "playing":
				return call_wave(slot)
		"speed":
			if slot != local_slot:
				return "Only the host can change the speed"
			game_speed = GAME_SPEEDS[(GAME_SPEEDS.find(game_speed) + 1) % GAME_SPEEDS.size()]
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
	return "That's %s's area. Waiting for %s to say yes..." % [name_of(owner), name_of(owner)]


func answer_request(slot: int, id: int, yes: bool) -> void:
	var r: Dictionary = requests.get(id, {})
	if r.is_empty() or r.to != slot:
		return
	end_request(id)
	var who: String = name_of(slot)
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
			tell(r.from, "%s didn't answer" % name_of(r.to))


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


# path: 1 or 2 for the upgrade to level 5, which picks the tower's path for
# good; 0 for every other upgrade.
func upgrade_tower(slot: int, c: Vector2i, path: int) -> String:
	var t: Tower = towers.get(c)
	if t == null or state != "playing":
		return ""
	if t.owner != slot:
		return "That's %s's tower" % name_of(t.owner)
	if t.level >= MAX_LEVEL - 1:
		return "Already max level"
	if needs_path(t) and path != 1 and path != 2:
		return path_hint(t)
	if not needs_path(t) and path != 0:
		if t.path != 0:
			return "This tower is already a %s" % tower_name(t)
		return "Paths are picked at level 4"
	var cost: int = TOWERS[t.type]["cost"][t.level + 1]
	if players[slot].gold < cost:
		return "Not enough gold"
	players[slot].gold -= cost
	t.spent += cost
	t.level += 1
	if path != 0:
		t.path = path
		# Sniper and Overload start on Strongest (the player can change it)
		if PATHS[t.type][path - 1].has("mode"):
			t.mode = PATHS[t.type][path - 1]["mode"]
	build_tower_node(t)
	send_tower(t)
	return ""


# Sets which monster a tower shoots; all_of_type: also every other tower of
# that type the same player owns.
func set_target_mode(slot: int, c: Vector2i, mode: int, all_of_type: bool) -> String:
	var t: Tower = towers.get(c)
	if t == null or state != "playing" or mode < 0 or mode >= TARGET_MODES.size():
		return ""
	if t.owner != slot:
		return "That's %s's tower" % name_of(t.owner)
	for other: Tower in towers.values():
		if other == t or (all_of_type and other.owner == slot and other.type == t.type):
			other.mode = mode
			send_all("net_tower_mode", [other.cell, mode])
	if all_of_type:
		tell(slot, "All your %s towers: %s" % [TOWERS[t.type]["name"], TARGET_MODES[mode]])
	return ""


func sell_tower(slot: int, c: Vector2i) -> String:
	var t: Tower = towers.get(c)
	if t == null or state != "playing":
		return ""
	if t.owner != slot:
		return "That's %s's tower" % name_of(t.owner)
	players[slot].gold += int(t.spent * 0.7)
	remove_tower(c)
	send_all("net_tower_removed", [c])
	return ""
