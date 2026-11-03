extends "res://map_editor.gd"
## Gettic's first TD: the root script (see game_base.gd for how the files fit together).
## Waves, the update loop, input and player actions.

func _ready() -> void:
	if is_debug_game():
		open_log_window()
	font = ThemeDB.fallback_font
	# The path, gates, routes and areas come from the map (see read_map())
	use_map(read_map(DEFAULT_MAP))
	# Before build_world(), which writes settings.cfg on the first start
	var had_settings := FileAccess.file_exists(SETTINGS_FILE)
	build_world()
	load_tutorial(had_settings)
	load_profile()
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
		# A debug/test option, ignored in the released game: --level=easy / normal / hard / insane
		if arg.begins_with("--level=") and OS.is_debug_build():
			var d := DIFFICULTIES.find(arg.trim_prefix("--level=").capitalize())
			if d >= 0:
				difficulty = d
	play_alone()
	check_for_update()


func new_game() -> void:
	clear_world()
	reset_stats()
	for p in players:
		if p != null:
			p.gold = start_gold()
			p.cooldowns = {}
			stat_start[p.slot] = p.gold
			stat_names[p.slot] = name_of(p.slot)
	wave = 0
	prog = [{}, {}, {}, {}]
	endless = false
	from_save = false
	held = false
	held_note = ""
	saved_slots.clear()
	aiming = ""
	next_wave_timer = 0.0
	game_speed = 1
	state = "playing"
	menu_open = false
	story_queue.clear()  # a story card waiting from the last game isn't for this one
	story_end = ""
	send_all("net_reset", [])
	if net_mode != "client":
		apply_mood(pick_mood())
		send_mood(mood)
	flash("Build towers, then press SPACE to start")


# ---------------------------------------------------------------- weather and time of day
# The host (or a player alone) picks the mood (see MOODS and apply_mood() in
# game_world.gd) for every new game: always day with the Settings row
# "Weather: Day" (the host's setting counts) and in the map editor; in the daily
# and weekly challenges from the day / week, so everyone gets the same; otherwise
# random. The other players get it with send_mood() -> set_mood_from_host().

func pick_mood() -> String:
	if weather_setting == "day" or editing:
		return "day"
	if daily_date != "":
		daily_seed("gtd-daily-mood-%d-%s" % [DAILY_VERSION, daily_date])
		return MOODS[daily_roll(0, MOODS.size() - 1)]
	if weekly_id != "":
		daily_seed("gtd-weekly-mood-%d-%s" % [WEEKLY_VERSION, weekly_id])
		return MOODS[daily_roll(0, MOODS.size() - 1)]
	return MOODS[randi() % MOODS.size()]


# Another player: the host's mood (from the network: anything but one of MOODS is ignored).
func set_mood_from_host(m: Variant) -> void:
	if net_mode == "client" and m is String and m in MOODS and m != mood:
		apply_mood(m)


# A fresh single-player game (at startup, or after leaving a multiplayer game).
func play_alone() -> void:
	players = [null, null, null, null]
	var me := Player.new()
	me.name = my_name()
	players[0] = me
	local_slot = 0
	settle_colors()
	new_game()


# ---------------------------------------------------------------- waves

# Starts the next wave. Called by the wave timer, or early by the player (Space),
# which gives bonus gold for every second skipped: the wave's income spread over
# WAVE_INTERVAL (at least 1 gold a second).
func start_wave() -> void:
	if state != "playing" or wave >= last_wave():
		return
	var skipped := int(maxf(next_wave_timer, 0.0)) if wave > 0 else 0
	# Notes who is in the game before this wave (see prog_for())
	for p in players:
		if p != null:
			prog_for(p.slot)
	wave += 1
	wave_votes.clear()
	var income := wave_income(wave)
	var early_bonus := skipped * maxi(1, int(income / WAVE_INTERVAL))
	# Every player gets the wave income, and every player's gate sends a full wave
	for p in players:
		if p != null:
			give_gold(p.slot, income + early_bonus)
	var text := "Wave %d! +%s gold" % [wave, short(income)]
	if early_bonus > 0:
		text = "Wave %d! +%s gold (+%s for calling early)" % [wave, short(income), short(early_bonus)]
	if grimwhistle_wave(wave):
		text = "Wave %d! Grimwhistle the Bone Conductor comes up himself!" % wave
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
	profile_wave_start()
	autosave()


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
	e.max_hp = spawn_hp * DIFFICULTY_HP[difficulty] * challenge_rules().get("hp", 1.0) * weekly_tide(wave)
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
			e.max_hp *= 18.0
			e.speed *= 0.7
			e.bounty = 40 + e.bounty * 12
			e.weight = 5
			# Grimwhistle: the first boss out of each gate in his wave (he leads his singers)
			if grimwhistle_wave(wave) and spawn_queues[g].size() == wave_count(wave) - 1:
				e.special = "conductor"
				e.max_hp *= GRIM_HP
				e.speed *= GRIM_SPEED / 0.7
				e.bounty *= GRIM_GOLD
				e.radius = GRIM_RADIUS
				e.heal_timer = CRESCENDO_FIRST  # his Crescendo timer (he's never a healer)
	# The wave's trait (see wave_special()). The gold stays the same: a splitter
	# gives half, each of its splitlings a quarter.
	match wave_special(wave):
		"split":
			e.special = "split"
			e.max_hp *= SPLIT_HP
			e.bounty = maxi(e.bounty / 2, 1)
		"heal":
			# Every HEALER_EVERY-th monster out of this gate (counted by what's left to come)
			if spawn_queues[g].size() % HEALER_EVERY == HEALER_EVERY - 1:
				e.special = "heal"
				e.max_hp *= HEALER_HP
				e.heal_timer = HEAL_EVERY * randf()
		"shield":
			e.max_shield = e.max_hp * (SHIELD_BOSS if kind == "boss" else SHIELD_SHARE)
			e.shield = e.max_shield
	e.hp = e.max_hp
	enemies.append(e)
	enemy_by_id[e.id] = e


# Host: a splitter died: 2 splitlings come out where it was, as far along,
# faster, with its armor. They join the game in remove_dead() (not while the
# towers are going through the monsters).
func split_enemy(p: Enemy) -> void:
	for i in 2:
		var e := make_enemy(p.kind)
		e.id = next_enemy_id
		next_enemy_id += 1
		e.special = "splitling"
		e.route = p.route
		e.loop_wp = p.loop_wp
		e.wp = p.wp
		e.pos = p.pos + Vector2(0, 6.0 if i == 0 else -6.0).rotated(randf() * TAU)
		e.traveled = p.traveled
		e.speed = p.speed * SPLITLING_SPEED
		e.armor = p.armor
		e.max_hp = p.max_hp / SPLIT_HP * SPLITLING_HP
		e.hp = e.max_hp
		e.bounty = maxi(p.bounty / 2, 1)
		e.radius = p.radius * 0.75
		e.slow_factor = p.slow_factor
		e.slow_time = p.slow_time
		new_enemies.append(e)


# ---------------------------------------------------------------- daily and weekly challenges
# The day's twist or the week's two (see daily_rules() and weekly_rules() in
# game_base.gd, both through challenge_rules()) change these rules from
# game_base.gd; everything else (the top bar, wave preview, late joiners' gold)
# uses them too. Monster health (also the weekly's Rising tide) is changed in
# spawn_enemy(), so the gold, which follows wave_hp(), stays as it is.

func start_gold() -> int:
	return int(super() * challenge_rules().get("start_gold", 1.0))


# Swarm: more monsters a wave (not more bosses).
func wave_count(w: int) -> int:
	var n := super(w)
	return n if kind_for_wave(w) == "boss" else roundi(n * challenge_rules().get("count", 1.0))


func wave_income(w: int) -> int:
	return int(super(w) * challenge_rules().get("income", 1.0))


func wave_bounty(w: int) -> int:
	return maxi(1, int(super(w) * challenge_rules().get("bounty", 1.0)))


# Armored day: normal waves are armored.
func kind_for_wave(w: int) -> String:
	var kind := super(w)
	return "armored" if kind == "normal" and challenge_rules().get("armored", false) else kind


# Two towers: only the challenge's tower types can be built.
func daily_allows(type: String) -> bool:
	var rules := challenge_rules()
	return rules.is_empty() or type in rules.towers


# The Esc menu's daily challenge (J for now; the graphics agent adds a button):
# alone, or as the host while nobody has joined, before wave 1.
func menu_daily() -> void:
	if can_pick_map():
		flash(start_daily())
		play_sound("daily_start")
	elif net_mode == "host" and player_count() > 1:
		flash("The daily challenge can only start while nobody has joined")
	elif net_mode == "client":
		flash("Only the host can start the daily challenge")
	else:
		flash("The daily challenge can only start before wave 1")


# Starts the weekly challenge (id "": this week) alone, or as the host before
# anyone joined, before wave 1 (menu_weekly() checks that, like picking a map).
# Hard, the week's map and twists. Returns a message for the player.
func start_weekly(id := "") -> String:
	if id == "":
		id = weekly_now()
	if not weekly_valid(id):
		return "There's no week %s" % id
	if net_mode not in ["", "host"] or (net_mode == "host" and player_count() > 1):
		return "The weekly challenge can only start while nobody has joined"
	use_map(weekly_map(id), weekly_title(id))
	build_map()
	weekly_id = id
	var rules := weekly_rules(id)
	difficulty = rules.level
	new_game()
	send_difficulty()
	send_weekly(id)
	return "Weekly challenge %s (%s, %d waves): %s. %s" % [id, DIFFICULTIES[difficulty], WEEKLY_WAVES, rules.name, rules.desc]


# The Esc menu's weekly challenge button (the ui calls this).
func menu_weekly() -> void:
	if can_pick_map():
		flash(start_weekly())
		play_sound("daily_start")
	elif net_mode == "host" and player_count() > 1:
		flash("The weekly challenge can only start while nobody has joined")
	elif net_mode == "client":
		flash("Only the host can start the weekly challenge")
	else:
		flash("The weekly challenge can only start before wave 1")


# ---------------------------------------------------------------- tutorial tips
# See TIPS in game_base.gd. Every TIP_POLL seconds of play, update_tips() looks at
# what this computer sees (the same for a player alone, the host and the other
# players, so nothing is sent): a tip that's done (the player did it, or already
# knows how) counts as seen without showing; a tip whose moment has come joins
# the queue; a waiting tip whose moment has passed leaves it again. The tip on
# screen stays until Got it, Skip all, or the player does what it says.

const TIP_POLL := 0.5
const TIP_START := 1.0  # seconds of play before the first tip
var tip_timer := 0.0
var tip_played := 0.0


func update_tips(delta: float) -> void:
	if not tips_on or replay_on or editing or held or state != "playing" or net_mode in ["searching", "connecting", "map_offer"]:
		return
	tip_played += delta
	tip_timer -= delta
	if tip_timer > 0.0 or tip_played < TIP_START or tips_seen.size() >= TIPS.size():
		return
	tip_timer = TIP_POLL
	var mine := my_tower_summary()
	var changed := false
	for id: String in TIPS:
		if id in tips_seen:
			continue
		if tip_done(id, mine):
			tips_seen.append(id)
			tip_queue.erase(id)
			changed = true
		elif tip_ready(id, mine):
			if not id in tip_queue:
				tip_queue.append(id)
		elif id in tip_queue and tip_queue[0] != id:
			tip_queue.erase(id)
	if changed:
		save_tutorial()


# This player's towers, for the tips: how many, whether one is upgraded or has a
# path, and one they can afford to upgrade and one waiting for its path (or null).
func my_tower_summary() -> Dictionary:
	var s := {"count": 0, "upgraded": false, "path_picked": false, "can_upgrade": null, "needs_path": null}
	for t: Tower in towers.values():
		if t.owner != local_slot:
			continue
		s.count += 1
		if t.level > 0:
			s.upgraded = true
		elif s.can_upgrade == null and gold >= TOWERS[t.type]["cost"][1]:
			s.can_upgrade = t
		if t.path != 0:
			s.path_picked = true
		if needs_path(t):
			s.needs_path = t
	return s


# Has the player already done what tip id teaches?
func tip_done(id: String, mine: Dictionary) -> bool:
	match id:
		"build":
			return mine.count > 0 or build_type != ""
		"place":
			return mine.count > 0
		"wave":
			return wave > 0
		"upgrade":
			return mine.upgraded
		"abilities":
			return ability_left(local_slot, "meteor") > 0.0 or ability_left(local_slot, "freeze") > 0.0
		"path":
			return mine.path_picked
	return false  # the others: Got it (menu and target also when used, see tip_learned())


# Is now the moment for tip id?
func tip_ready(id: String, mine: Dictionary) -> bool:
	match id:
		"build":
			return mine.count == 0
		"place":
			return build_type != ""
		"wave":
			return mine.count > 0 and wave == 0
		"menu":
			return wave >= 2
		"upgrade":
			if wave >= 1 and mine.can_upgrade != null:
				tip_spots[id] = mine.can_upgrade.pos
				return true
		"target":
			return selected != null and selected.owner == local_slot and selected.type != "barracks" and "upgrade" in tips_seen
		"abilities":
			return wave >= 3
		"limit":
			return alive_count() * 5 >= max_alive() * 2
		"path":
			if mine.needs_path != null:
				tip_spots[id] = mine.needs_path.pos
				return true
		"boss":
			return wave >= 1 and (kind_for_wave(wave) == "boss" or (wave < last_wave() and kind_for_wave(wave + 1) == "boss"))
		"special":
			return wave >= 1 and (wave_special(wave) != "" or (wave < last_wave() and wave_special(wave + 1) != ""))
	return false


# The player just used what tip id teaches (Esc menu, T): it won't be needed.
func tip_learned(id: String) -> void:
	if tips_on and not id in tips_seen:
		tips_seen.append(id)
		tip_queue.erase(id)
		save_tutorial()


# ----- story cards (see STORY_CARDS in game_base.gd)
# Every computer watches its own game (the wave number and the end are the same
# for everyone, so nothing is sent). A wave card comes only when the wave goes up
# by one while playing: loading a save or joining a game doesn't bring one.

var story_wave := -1  # the wave update_story() saw last (-1: none yet)
var story_state := ""  # and the game's state
var story_played := 0.0  # seconds of play (for gates_waking)


func update_story(delta: float) -> void:
	var last_wave := story_wave
	var last_state := story_state
	story_wave = wave
	story_state = state
	var daily := daily_date != ""
	if replay_on or editing or weekly_id != "" or net_mode in ["searching", "connecting", "map_offer"]:
		return
	# The end of a game: the first win and the first loss (shown on the end screen)
	if last_state == "playing" and state in ["won", "lost"] and wave > 0 and not daily:
		story_unlock("first_win" if state == "won" else "first_loss")
		return
	if state != "playing" or held:
		return
	story_played += delta
	if daily:
		story_unlock("daily_omen")
		return
	if story_played >= STORY_START:
		story_unlock("gates_waking")
	if last_wave < 0 or wave != last_wave + 1:
		return
	for id: String in STORY_WAVES:
		if STORY_WAVES[id] == wave:
			story_unlock(id)
	if kind_for_wave(wave) == "boss":
		story_unlock("first_boss")
	if grimwhistle_wave(wave):
		story_unlock("grimwhistle")


# The Settings row: also saved (settings.cfg [story] cards, see save_settings()).
func set_story_cards(on: bool) -> void:
	super(on)
	save_settings()


# No tips in the map editor or the replay (game_base.gd: only while playing).
func current_tip() -> Dictionary:
	if editing or replay_on:
		return {}
	return super()


# At startup. had_settings: settings.cfg was there before this start. Without a
# [tutorial] section, a new player (no settings.cfg) gets the tips On, a player
# from before the tips Off. The section is written right away, so the next start
# knows.
func load_tutorial(had_settings: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	read_tutorial(cfg, had_settings)
	if not cfg.has_section("tutorial"):
		save_tutorial()


func read_tutorial(cfg: ConfigFile, had_settings: bool) -> void:
	tips_seen = []
	tip_queue.clear()
	if not cfg.has_section("tutorial"):
		tips_on = not had_settings
		return
	var on: Variant = cfg.get_value("tutorial", "on", true)
	tips_on = on if on is bool else true
	var seen: Variant = cfg.get_value("tutorial", "seen", [])
	if seen is Array or seen is PackedStringArray:
		for id: Variant in seen:
			if (id is String or id is StringName) and TIPS.has(str(id)) and not str(id) in tips_seen:
				tips_seen.append(str(id))


func write_tutorial(cfg: ConfigFile) -> void:
	cfg.set_value("tutorial", "on", tips_on)
	cfg.set_value("tutorial", "seen", tips_seen)


# Headless runs (error checks, tests) never write the player's settings.
func save_tutorial() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)  # keeps the other settings
	write_tutorial(cfg)
	cfg.save(SETTINGS_FILE)


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
	update_tips(delta)
	update_story(delta)
	# Watching the replay: the game is over, the replay drives the monsters and shots
	if replay_on:
		replay_update(delta)
		if net_mode == "host":
			snapshot_timer -= delta
			if snapshot_timer <= 0.0:
				snapshot_timer = 1.0 / SNAPSHOT_RATE
				# The other players still get the real monsters, not the replay's
				var ghosts := enemies
				enemies = live_enemies
				send_snapshot()
				enemies = ghosts
		update_camera(delta)
		update_visuals(delta)
		hud.queue_redraw()
		return
	update_effects(delta)
	# The profile's play time (every computer: real seconds of a game going on)
	if state == "playing" and wave > 0 and not held and not editing:
		profile_seconds += delta
	var dt := delta * game_speed
	if net_mode == "client":
		# The host runs the game. Here monsters just glide to where the host says
		# they are, and shots fly for show.
		if state == "playing" and wave > 0 and not held:
			next_wave_timer = maxf(next_wave_timer - dt, 0.0)
		if state == "playing" and not held:
			tick_cooldowns(dt)
		for e in enemies:
			e.pos = e.pos.lerp(e.net_pos, minf(delta * 12.0, 1.0))
			e.freeze_time = maxf(e.freeze_time - dt, 0.0)  # for the frozen look after Freeze all
		update_shots(dt)
	elif state == "playing" and not held:
		tick_cooldowns(dt)
		if wave > 0 and wave < last_wave():
			next_wave_timer -= dt
			if next_wave_timer <= 0.0:
				start_wave()
		update_spawning(dt)
		update_enemies(dt)
		update_towers(dt)
		update_shots(dt)
		update_clouds(dt)
		remove_dead()
		check_grimwhistle()
		if alive_count() >= max_alive():
			state = "lost"
		elif wave >= last_wave() and monsters_left_to_spawn() == 0 and enemies.is_empty():
			state = "won"
		if state != "playing":
			# The stats screen: made once, and sent once to the other players
			end_stats = make_end_stats()
			send_all("net_stats", [end_stats])
			profile_game_end()
	# A loaded game on hold (see load_game()): nothing moves, nothing is recorded or timed
	if not held:
		record_frame(dt)
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
	# Zooming glides toward target_zoom (the tilt follows, see camera_offset()). After a
	# scroll (zoom_camera()), the ground under the mouse stays under the mouse.
	var anchored := zoom_anchored and absf(zoom - target_zoom) > 0.0005
	var before := Vector3.ZERO
	if anchored:
		place_camera()
		before = ground_at(zoom_anchor)
	zoom = lerpf(zoom, target_zoom, 1.0 - exp(-12.0 * delta))
	place_camera()
	if anchored:
		var moved := before - ground_at(zoom_anchor)
		camera_pan = (camera_pan + Vector2(moved.x, moved.z)).clamp(-camera_limit(), camera_limit())
		place_camera()
	else:
		zoom_anchored = false
		camera_pan = camera_pan.clamp(-camera_limit(), camera_limit())  # zooming out shrinks the limit


# Middle-mouse drag: the ground grabbed stays under the mouse. Minimap drag: the
# camera looks where the mouse is on the small map.
var view_drag := Vector3.ZERO  # the ground spot grabbed with the middle button
var view_dragging := false
var minimap_dragging := false


# Mouse buttons and motion that move the camera (the game and the replay).
# Returns true when the event was used.
func camera_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		view_dragging = event.pressed
		if event.pressed:
			view_drag = ground_at(event.position)
			zoom_anchored = false
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		minimap_dragging = false
		return false
	if event is InputEventMouseMotion:
		if view_dragging:
			var moved := view_drag - ground_at(event.position)
			camera_pan = (camera_pan + Vector2(moved.x, moved.z)).clamp(-camera_limit(), camera_limit())
			place_camera()
			return true
		if minimap_dragging:
			minimap_look(ui_mouse())
			return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H \
			and not chatting() and not (get_viewport().gui_get_focus_owner() is LineEdit):
		reset_camera(1.0)  # H: the whole map
		return true
	return false


# A point on the minimap: the camera looks at that spot of the board.
func minimap_look(p: Vector2) -> void:
	var m := minimap_map()
	var at := ((p - m.position) / m.size).clamp(Vector2.ZERO, Vector2.ONE) * Vector2(map_cols, map_rows)
	look_at_ground(at)


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
		e.poisoned = maxf(e.poisoned - dt, 0.0)
		# A shield regrows slowly once the monster hasn't been hit for a while
		if e.max_shield > 0.0:
			e.shield_wait += dt
			if e.shield_wait >= SHIELD_REGROW and e.shield < e.max_shield:
				e.shield = minf(e.shield + e.max_shield * SHIELD_REGROW_RATE * dt, e.max_shield)
		# A healer heals the other monsters near it (not above full health)
		if e.special == "heal" and not e.dead:
			e.heal_timer -= dt
			if e.heal_timer <= 0.0:
				e.heal_timer += HEAL_EVERY
				for o in enemies:
					if o != e and not o.dead and o.pos.distance_squared_to(e.pos) <= HEAL_RANGE * HEAL_RANGE:
						o.hp = minf(o.hp + o.max_hp * (HEAL_BOSS if o.kind == "boss" else HEAL_SHARE), o.max_hp)
		# Grimwhistle's Crescendo (see CRESCENDO_EVERY)
		if e.special == "conductor" and not e.dead:
			e.heal_timer -= dt
			if e.heal_timer <= 0.0:
				e.heal_timer += CRESCENDO_EVERY
				crescendo(e)
		e.haste_time = maxf(e.haste_time - dt, 0.0)
		if e.slow_time > 0.0:
			e.slow_time -= dt
			if e.slow_time <= 0.0:
				e.slow_factor = 1.0
		e.freeze_immune = maxf(e.freeze_immune - dt, 0.0)
		e.hold_immune = maxf(e.hold_immune - dt, 0.0)
		# Frozen by Deep Freeze: stands still, and can't be frozen again for a while after
		if e.freeze_time > 0.0:
			e.freeze_time -= dt
			if e.freeze_time <= 0.0:
				e.freeze_immune = FREEZE_IMMUNE
			continue
		# Held by a Barracks soldier: stands still
		if e.held:
			continue
		var move := e.speed * e.slow_factor * (CRESCENDO_HASTE if e.haste_time > 0.0 else 1.0) * dt
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


# Host: Grimwhistle g's Crescendo: the monsters near him (himself too) shake off
# slows, freezes and soldiers, and walk faster for a moment.
func crescendo(g: Enemy) -> void:
	var freed := {}
	for o in enemies:
		if o.dead or o.pos.distance_squared_to(g.pos) > CRESCENDO_RANGE * CRESCENDO_RANGE:
			continue
		o.slow_factor = 1.0
		o.slow_time = 0.0
		o.freeze_time = 0.0
		o.haste_time = CRESCENDO_TIME
		if o.held:
			freed[o] = true
	if not freed.is_empty():
		for t: Tower in towers.values():
			for i in t.soldier_hold.size():
				if t.soldier_hold[i] != null and freed.has(t.soldier_hold[i]):
					release(t, i)
	crescendo_fx(g)


# Host: once every Grimwhistle has fallen (his wave fully out), the monsters
# left crumble: no gold, no kills, and the game is won.
func check_grimwhistle() -> void:
	if not grimwhistle_wave(wave) or monsters_left_to_spawn() > 0 or enemies.is_empty():
		return
	for e in enemies:
		if e.special == "conductor" and not e.dead:
			return
	for e in enemies:
		e.dead = true
	for t: Tower in towers.values():
		for i in t.soldier_hold.size():
			release(t, i)
	remove_dead()


func update_towers(dt: float) -> void:
	hold_tiles_ready = false
	for t: Tower in towers.values():
		if t.type == "barracks":
			update_barracks(t, dt)
			continue
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
				send_shot(t, e)
		else:
			launch_shot(t, target, false)
			send_shot(t, target)


# ----- Barracks (see TOWER_BASE["barracks"] and ENGAGE_R in game_base.gd)
# Host: each soldier at the rally point holds one monster still for its hold
# time, hitting it, and wears down while it does. Only free soldiers look for a
# monster, and only on the tiles around the rally point (the monsters are sorted
# into tiles at most once a frame, and only when a free soldier needs them).

var hold_tiles := {}  # host: Vector2i -> [monsters on that tile], this frame
var hold_tiles_ready := false


# Sizes a Barracks' soldier lists to its level. New soldiers come at full
# health; a loaded Barracks keeps its soldiers' health (clamped).
func fit_soldiers(t: Tower) -> void:
	var data := tower_data(t.type, t.path, t.level)
	var n: int = data["soldiers"][t.level]
	var most: float = data["soldier_hp"][t.level]
	while t.soldier_hold.size() > n:
		release(t, t.soldier_hold.size() - 1)
		t.soldier_hold.pop_back()
	var had := t.soldier_hp.size()
	t.soldier_hp.resize(n)
	t.soldier_wait.resize(n)
	t.soldier_cd.resize(n)
	t.soldier_left.resize(n)
	for i in n:
		if i >= had or not is_finite(t.soldier_hp[i]):
			t.soldier_hp[i] = most
			t.soldier_wait[i] = 0.0
		t.soldier_hp[i] = clampf(t.soldier_hp[i], 0.0, most)
		t.soldier_wait[i] = clampf(t.soldier_wait[i], 0.0, data["respawn"][t.level]) if is_finite(t.soldier_wait[i]) else 0.0
	t.soldier_hold.resize(n)
	if t.rally.x < 0.0:
		t.rally = rally_point(t.cell, TOWERS["barracks"]["range"][0])


# A soldier lets its monster go (no soldier holds it again for HOLD_IMMUNE).
func release(t: Tower, i: int) -> void:
	var e: Enemy = t.soldier_hold[i]
	if e != null:
		e.held = false
		e.hold_immune = HOLD_IMMUNE
	t.soldier_hold[i] = null


func update_barracks(t: Tower, dt: float) -> void:
	var data := tower_data(t.type, t.path, t.level)
	if t.soldier_hold.size() != data["soldiers"][t.level] or t.soldier_hp.size() != t.soldier_hold.size():
		fit_soldiers(t)
	if t.rally.x < 0.0:
		return
	var max_hp: float = data["soldier_hp"][t.level]
	var p: Dictionary = PATHS["barracks"][t.path - 1] if t.path > 0 and t.level >= PATH_LEVEL else {}
	var boss_hold: float = p.get("boss_hold", 0.0)
	var reach: float = ENGAGE_R * p.get("reach", 1.0)
	for i in t.soldier_hold.size():
		if t.soldier_hp[i] <= 0.0:
			t.soldier_wait[i] -= dt
			if t.soldier_wait[i] <= 0.0:
				t.soldier_hp[i] = max_hp
			continue
		var e: Enemy = t.soldier_hold[i]
		if e != null and e.dead:
			t.soldier_hold[i] = null
			e = null
		if e == null:
			e = free_monster(t.rally, reach, boss_hold > 0.0)
			if e == null:
				continue
			e.held = true
			t.soldier_hold[i] = e
			t.soldier_left[i] = data["hold"][t.level] * (boss_hold if e.kind == "boss" else 1.0) * (GRIM_HOLD if e.special == "conductor" else 1.0)
		t.soldier_left[i] -= dt
		var hurt: float = SOLDIER_HURT.get(e.kind, 1.0) * (0.5 if e.special == "splitling" else (GRIM_HURT if e.special == "conductor" else 1.0))
		t.soldier_hp[i] -= hurt * dt
		t.soldier_cd[i] -= dt
		if t.soldier_cd[i] <= 0.0:
			t.soldier_cd[i] += data["cooldown"][t.level]
			damage_enemy(e, data["damage"][t.level] * (boss_bonus(t.type, t.path, t.level) if e.kind == "boss" else 1.0), t.owner, t)
		if t.soldier_hp[i] <= 0.0:
			t.soldier_hp[i] = 0.0
			t.soldier_wait[i] = data["respawn"][t.level]
			release(t, i)
		elif t.soldier_left[i] <= 0.0 or e.dead:
			release(t, i)


# The monster nearest to the rally point at, within reach, that nobody holds
# (bosses only if bosses is true), or null.
func free_monster(at: Vector2, reach: float, bosses: bool) -> Enemy:
	if not hold_tiles_ready:
		hold_tiles_ready = true
		hold_tiles.clear()
		for e in enemies:
			if not e.dead:
				var k := Vector2i(floori(e.pos.x / CELL), floori(e.pos.y / CELL))
				if hold_tiles.has(k):
					hold_tiles[k].append(e)
				else:
					hold_tiles[k] = [e]
	var best: Enemy = null
	var best_d := reach * reach
	for x in range(floori((at.x - reach) / CELL), floori((at.x + reach) / CELL) + 1):
		for y in range(floori((at.y - reach) / CELL), floori((at.y + reach) / CELL) + 1):
			for o: Enemy in hold_tiles.get(Vector2i(x, y), []):
				if o.dead or o.held or o.hold_immune > 0.0 or (o.kind == "boss" and not bosses):
					continue
				var d := o.pos.distance_squared_to(at)
				if d <= best_d:
					best_d = d
					best = o
	return best


# A tower going away (sold, or removed by the host) lets its monsters go.
func remove_tower(c: Vector2i) -> void:
	var t: Tower = towers.get(c)
	if t != null:
		for i in t.soldier_hold.size():
			release(t, i)
	super(c)


# Every computer, every frame: the soldiers' looks (see show_soldiers()). The
# host and a player alone know the soldiers; the other players get them in the
# snapshots (apply_barracks_info()) and show full soldiers until then. The
# replay sets them from its frames.
func update_visuals(delta: float) -> void:
	super(delta)
	for t: Tower in towers.values():
		if t.type != "barracks":
			continue
		if t.rally.x < 0.0:
			t.rally = rally_point(t.cell, TOWERS["barracks"]["range"][0])
		if not replay_on and net_mode != "client":
			t.soldier_look = soldier_bytes(t)
		if t.soldier_look.is_empty():
			var full := PackedByteArray()
			full.resize(tower_data(t.type, t.path, t.level)["soldiers"][t.level])
			full.fill(127)
			t.soldier_look = full
		show_soldiers(t)


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
	var boss := boss_bonus(t.type, t.path, t.level)
	var hit: Array[Enemy] = [first]
	var points := PackedVector3Array([t.node.position + t.head.position + Vector3(0, 0.1, 0), first.node.position])
	damage_enemy(first, dmg * (boss if first.kind == "boss" else 1.0), t.owner, t)
	var current := first
	# The monsters by square of jump size (their index in enemies), so each jump
	# only looks at the monsters near it. Ties go to the first in enemies, as before.
	var grid := {}
	if data["chain"][t.level] > 1:
		for k in enemies.size():
			var e := enemies[k]
			if not e.dead:
				var g := Vector2i(floori(e.pos.x / jump), floori(e.pos.y / jump))
				if grid.has(g):
					grid[g].append(k)
				else:
					grid[g] = [k]
	for i in range(data["chain"][t.level] - 1):
		dmg *= falloff
		var next: Enemy = null
		var best_dist := jump
		var best_k := 0
		# A pixel more each way, so rounding never leaves a monster out
		var c := current.pos
		for gx in range(floori((c.x - jump - 1.0) / jump), floori((c.x + jump + 1.0) / jump) + 1):
			for gy in range(floori((c.y - jump - 1.0) / jump), floori((c.y + jump + 1.0) / jump) + 1):
				var list: Array = grid.get(Vector2i(gx, gy), [])
				for k: int in list:
					var e := enemies[k]
					if e.dead or hit.has(e):
						continue
					var d := e.pos.distance_to(current.pos)
					if d < best_dist or (d == best_dist and next != null and k < best_k):
						best_dist = d
						best_k = k
						next = e
		if next == null:
			break
		hit.append(next)
		points.append(next.node.position)
		damage_enemy(next, dmg * (boss if next.kind == "boss" else 1.0), t.owner, t)
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
			shot_spark(s)
			# Every computer shows the poison cloud where the glob lands (no message
			# needed: the other players' and the replay's shots land there too)
			if s.type == "poison":
				var cd := tower_data(s.type, s.path, s.level)
				show_cloud(s.pos, cd["cloud"][s.level], cloud_seconds(s.path, s.level), s.path if s.level >= PATH_LEVEL else 0)
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
			var hit := {}  # Cluster: monsters already hit by this shell (each is hit once)
			for e in enemies:
				if e.dead:
					continue
				var d := e.pos.distance_to(s.pos)
				if d <= r:
					hit[e] = true
					damage_enemy(e, dmg * (boss_bonus(s.type, s.path, s.level) if e.kind == "boss" else 1.0), s.owner, s.tower)
				elif path == 2 and d <= BOMBLET_REACH:
					near.append([e.traveled, e])
			blast(s.pos, r)
			if path == 2:
				# Bomblets land on the monsters furthest along near the blast that
				# no blast has hit yet
				near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
				var left: int = path_step(s.level, PATHS["cannon"][1]["bomblets"])
				for n: Array in near:
					if left <= 0:
						break
					if hit.has(n[1]):
						continue
					left -= 1
					var at: Vector2 = n[1].pos
					for e in enemies:
						if not e.dead and not hit.has(e) and e.pos.distance_to(at) <= BOMBLET_RADIUS:
							hit[e] = true
							damage_enemy(e, dmg, s.owner, s.tower)
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
					# Deep Freeze: a chance to stop it for a moment (bosses half as long),
					# unless it was just frozen
					if path == 1 and e.freeze_time <= 0.0 and e.freeze_immune <= 0.0 and randf() < path_step(s.level, PATHS["frost"][0]["freeze"]):
						e.freeze_time = FREEZE_TIME * (0.5 if e.kind == "boss" else 1.0)
					damage_enemy(e, dmg, s.owner, s.tower)
		"poison":
			# A cloud where the glob landed (see update_clouds())
			var p := path
			clouds.append({"pos": s.pos, "r": float(data["cloud"][s.level]), "time": cloud_seconds(s.path, s.level),
					"dps": dmg, "owner": s.owner, "cell": s.tower.cell if s.tower != null else Vector2i(-1, -1),
					"boss": boss_bonus(s.type, s.path, s.level),
					"weak": path_step(s.level, PATHS["poison"][1]["weaken"]) if p == 2 else 0.0})
		_:
			if alive:
				damage_enemy(s.target, dmg * (boss_bonus(s.type, s.path, s.level) if s.target.kind == "boss" else 1.0), s.owner, s.tower)


func blast(at: Vector2, r: float) -> void:
	add_boom(at, r)
	send_all("net_boom", [at, r])


# The gold for a kill goes to the player who owns the tower that made it.
# t: that tower (counted for the stats at the end).
# pierce: armor doesn't stop it (poison, Meteor).
func damage_enemy(e: Enemy, amount: float, owner_slot: int, t: Tower = null, pierce := false) -> void:
	if e.dead:
		return
	# Miasma: monsters in its clouds take more from everything
	amount *= 1.0 + e.weak
	# A shield takes the hit first, before armor
	if e.max_shield > 0.0:
		e.shield_wait = 0.0
		if e.shield > 0.0:
			var took := minf(amount, e.shield)
			e.shield -= took
			amount -= took
			stat_damage[owner_slot] += took
			if t != null:
				t.dealt += took
			if e.shield <= 0.0:
				prog_add(owner_slot, "shields")
			if amount <= 0.0:
				return
	# Armor removes a flat amount, but at least 25% of the hit always goes through.
	var hit := amount if pierce else maxf(amount - e.armor, amount * 0.25)
	# The stats count only the health it really took off (no overkill)
	var done := minf(hit, e.hp)
	stat_damage[owner_slot] += done
	if t != null:
		t.dealt += done
	e.hp -= hit
	if e.hp <= 0.0:
		e.dead = true
		if e.special == "split":
			split_enemy(e)
		stat_kills[owner_slot] += 1
		if t != null:
			t.kills += 1
		give_gold(owner_slot, e.bounty)
		profile_kill(e, owner_slot, t)


# Wave and kill gold for a player (kept below GOLD_MAX, for endless mode).
func give_gold(slot: int, amount: int) -> void:
	var p: Player = players[slot]
	if p == null:
		return
	p.gold = mini(p.gold + amount, GOLD_MAX)
	stat_earned[slot] = mini(stat_earned[slot] + amount, GOLD_MAX)


func remove_dead() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].dead:
			drop_corpse(enemies[i])
			enemy_by_id.erase(enemies[i].id)
			enemies.remove_at(i)
	# Splitlings born this frame (see split_enemy())
	for e in new_enemies:
		enemies.append(e)
		enemy_by_id[e.id] = e
	new_enemies.clear()


# Seconds a poison tower's clouds last (Miasma longer).
func cloud_seconds(path: int, level: int) -> float:
	if path <= 0 or level < PATH_LEVEL:
		return CLOUD_TIME
	return CLOUD_TIME * PATHS["poison"][path - 1].get("cloud_time", 1.0)


# Host: poison clouds hurt every monster inside, each tower's every CLOUD_TICK
# seconds (see CLOUD_TIME). To spread the work, the towers take turns: every
# quarter tick a quarter of them (by their tile) hurt. The monsters are sorted
# into tiles each time, so a cloud only looks at the tiles it covers.
func update_clouds(dt: float) -> void:
	for i in range(clouds.size() - 1, -1, -1):
		clouds[i].time -= dt
		if clouds[i].time <= 0.0:
			clouds.remove_at(i)
	cloud_tick -= dt
	if cloud_tick > 0.0:
		return
	cloud_tick = maxf(cloud_tick + CLOUD_TICK / 4.0, 0.0)
	cloud_turn = (cloud_turn + 1) % 4
	if clouds.is_empty():
		if cloud_turn == 0:
			for e in enemies:
				e.weak = 0.0
		return
	var tiles := {}  # Vector2i -> [monsters on that tile]
	for e in enemies:
		if not e.dead:
			var k := Vector2i(floori(e.pos.x / CELL), floori(e.pos.y / CELL))
			if tiles.has(k):
				tiles[k].append(e)
			else:
				tiles[k] = [e]
	# Miasma's extra damage, worked out once a whole tick (before the poison of
	# that quarter, so it gets it too)
	if cloud_turn == 0:
		for e in enemies:
			e.weak = 0.0
		for c: Dictionary in clouds:
			if c.weak > 0.0:
				for e: Enemy in cloud_monsters(c, tiles):
					e.weak = maxf(e.weak, c.weak)
	var hurt := {}  # tower cell -> {monster: true} already hurt this tick
	for c: Dictionary in clouds:
		var cell: Vector2i = c.cell
		if posmod(cell.x + cell.y * 3, 4) != cloud_turn:
			continue
		if not hurt.has(cell):
			hurt[cell] = {}
		var done: Dictionary = hurt[cell]
		var t: Tower = towers.get(cell)
		if t != null and t.owner != c.owner:
			t = null  # sold, and someone else built there
		for e: Enemy in cloud_monsters(c, tiles):
			if e.dead or done.has(e):
				continue
			done[e] = true
			e.poisoned = 0.5
			damage_enemy(e, c.dps * CLOUD_TICK * (c.boss if e.kind == "boss" else 1.0), c.owner, t, true)


var cloud_turn := 0  # host: which quarter of the poison towers hurts next (see update_clouds())


# The monsters inside a cloud (tiles: the monsters by tile).
func cloud_monsters(c: Dictionary, tiles: Dictionary) -> Array:
	var list := []
	var r: float = c.r
	var at: Vector2 = c.pos
	var r2 := r * r
	var lo := Vector2i(floori((at.x - r) / CELL), floori((at.y - r) / CELL))
	var hi := Vector2i(floori((at.x + r) / CELL), floori((at.y + r) / CELL))
	if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) > tiles.size():
		# Fewer tiles with monsters than tiles under the cloud: go through those
		for k: Vector2i in tiles:
			if k.x >= lo.x and k.x <= hi.x and k.y >= lo.y and k.y <= hi.y:
				for e: Enemy in tiles[k]:
					if e.pos.distance_squared_to(at) <= r2:
						list.append(e)
		return list
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var k := Vector2i(x, y)
			if tiles.has(k):
				for e: Enemy in tiles[k]:
					if e.pos.distance_squared_to(at) <= r2:
						list.append(e)
	return list


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
		elif fx["kind"] == "cloud" and fx.has("node") and fx["node"] is GeometryInstance3D:
			# The placeholder cloud (see show_cloud()) fades out over its last second
			fx["node"].transparency = 1.0 - clampf(fx["time"], 0.0, 1.0)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	# F11 or Alt+Enter: fullscreen on and off, anywhere in the game
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F11 or (event.alt_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER))):
		toggle_fullscreen()
		return
	if update_dialog != "":
		dialog_input(event)
		return
	# Watching the replay: its own keys (Esc goes back to the stats)
	if replay_on and not menu_open:
		replay_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# Aiming Meteor: Esc only stops aiming
		if aiming != "" and not menu_open:
			aiming = ""
			return
		toggle_menu()
		if menu_open:
			tip_learned("menu")
		return
	if log_window and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		log_window.visible = not log_window.visible
		return
	if menu_open:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			menu_click(ui_mouse(true))
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J \
				and not (get_viewport().gui_get_focus_owner() is LineEdit):
			menu_daily()
		elif pick_open and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Scrolls the list of maps in the Esc menu
			var step := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			ed_list_top = clampi(ed_list_top + step, 0, maxi(ed_list.size() - ED_LIST_ROWS, 0))
		return
	if editing:
		editor_input(event)
		return
	# F5 quick-save, F9 quick-load (the host or a player alone)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F5, KEY_F9]:
		if event.keycode == KEY_F5:
			menu_save(QUICKSAVE_NAME)
		else:
			menu_load(QUICKSAVE_NAME)
		return
	# Enter: chat (while typing, the chat box gets the keys, not the game)
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		open_chat()
		return
	if camera_input(event):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			build_type = ""
			selected = null
			aiming = ""
		elif event.button_index == MOUSE_BUTTON_LEFT and event.alt_pressed:
			ping_at(ui_mouse())
		elif event.button_index == MOUSE_BUTTON_LEFT:
			on_click(ui_mouse())
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and not mouse_over_panel():
			zoom_camera(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not mouse_over_panel():
			zoom_camera(1.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
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
			KEY_Z:
				use_ability("meteor")
			KEY_C:
				use_ability("freeze")
			KEY_K:
				if state == "won" and not endless:
					act("endless", [])
			KEY_V:
				if state == "lost":
					start_replay()


# Z / C or an ability button: Meteor starts aiming (the next click on the map
# drops it; Z again, right-click or Esc stops aiming), Freeze all happens now.
func use_ability(ability: String) -> void:
	if state != "playing":
		return
	if aiming == ability:
		aiming = ""
		return
	var left := ability_left(local_slot, ability)
	if left > 0.0:
		flash("%s is ready in %ds" % [ABILITIES[ability]["name"], ceili(left)])
		return
	if wave == 0:
		flash("Abilities work once the first wave has started")
		return
	if ability == "meteor":
		aiming = ability
		build_type = ""
	else:
		act("ability", [ability, Vector2.ZERO])


func on_click(p: Vector2) -> void:
	if tip_click(p):
		return
	if state == "won" and not endless and keep_going_rect().has_point(p):
		act("endless", [])
		return
	if state != "playing":
		return
	# Aiming Meteor: a click on the map drops it there
	if aiming != "" and not over_panel(p):
		act("ability", [aiming, mouse_point()])
		aiming = ""
		return
	for i in ABILITY_ORDER.size():
		if ability_button_rect(i).has_point(p):
			use_ability(ABILITY_ORDER[i])
			return
	if not asks.is_empty():
		if ASK_YES_RECT.has_point(p):
			answer_ask(true)
			return
		if ASK_NO_RECT.has_point(p):
			answer_ask(false)
			return
	# The minimap: the camera looks there (drag to keep moving it; Alt + click pings)
	if minimap_map().has_point(p):
		minimap_dragging = true
		minimap_look(p)
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
		if selected != null and selected.type != "barracks" and asks.is_empty() and MODE_RECT.has_point(p):
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


# Alt + click: pings that spot for everyone (on the map, or on the small map).
# Never builds or selects.
func ping_at(p: Vector2) -> void:
	if chatting():
		return
	var m := minimap_map()
	if m.has_point(p):
		send_ping((p - m.position) / m.size * Vector2(map_cols, map_rows) * CELL)
	elif not over_panel(p):
		send_ping(mouse_point())


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
	if not daily_allows(type):
		flash("Today's challenge doesn't allow %s towers" % TOWERS[type]["name"])
		return
	build_type = type
	selected = null
	aiming = ""


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
	# Barracks soldiers have no targeting mode: they grab the monster nearest their rally point
	if selected != null and selected.type == "barracks":
		flash("Barracks soldiers fight the nearest monster")
		return
	if selected != null:
		act("target", [selected.cell, (selected.mode + 1) % TARGET_MODES.size(), all_of_type])
		if selected.owner == local_slot:
			tip_learned("target")


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
			# A loaded game on hold: the host's Space starts it again (no wave yet)
			if held:
				return unhold(slot)
			if state == "playing":
				return call_wave(slot)
		"speed":
			if slot != local_slot:
				return "Only the host can change the speed"
			game_speed = GAME_SPEEDS[(GAME_SPEEDS.find(game_speed) + 1) % GAME_SPEEDS.size()]
		"restart":
			if state != "playing":
				new_game()
		"difficulty":
			if args.size() == 1 and args[0] is int:
				return set_difficulty(slot, args[0])
		"answer":
			if args.size() == 2 and args[0] is int and args[1] is bool:
				answer_request(slot, args[0], args[1])
		"ability":
			# [ability, where] (where: Meteor's spot in map pixels, unused by Freeze all)
			if args.size() == 2 and args[0] is String and args[1] is Vector2:
				return do_ability(slot, args[0], args[1])
		"endless":
			return keep_going(slot)
		"gift":
			# [to slot, amount] (see gift_gold() in game_net.gd)
			if args.size() == 2 and args[0] is int and args[1] is int:
				var given_before: int = stat_gifted[slot]
				var error := gift_gold(slot, args[0], args[1])
				if error == "" and stat_gifted[slot] < given_before:
					prog_add(slot, "gifts_given")
					prog_add(args[0], "gifts_received")
					earn(slot, "first_gift")
				return error
	return ""


# Host: a player uses an ability (see ABILITIES), if its cooldown is over.
func do_ability(slot: int, ability: String, at: Vector2) -> String:
	if not ABILITIES.has(ability) or state != "playing":
		return ""
	if wave == 0:
		return "Abilities work once the first wave has started"
	if held:
		return "Abilities work once the game goes on"
	var left := ability_left(slot, ability)
	if left > 0.0:
		return "%s is ready in %ds" % [ABILITIES[ability]["name"], ceili(left)]
	match ability:
		"meteor":
			if not (at.is_finite() and Rect2(0, 0, map_cols * CELL, map_rows * CELL).has_point(at)):
				return "Drop the meteor on the map"
			var r: float = ABILITIES["meteor"]["radius"]
			# Armor doesn't stop it (shields do)
			var dmg := meteor_damage()
			var kills_before: int = stat_kills[slot]
			for e in enemies:
				if not e.dead and e.pos.distance_to(at) <= r:
					damage_enemy(e, dmg, slot, null, true)
			prog_add(slot, "meteors")
			if stat_kills[slot] - kills_before >= 20:
				earn(slot, "meteor_20")
		"freeze":
			var on_map := 0
			for e in enemies:
				if not e.dead:
					on_map += 1
			freeze_all()
			prog_add(slot, "freezes")
			if on_map >= 40:
				earn(slot, "freeze_40")
	prog_for(slot).used = true
	start_cooldown(slot, ability)
	show_ability(slot, ability, at)
	send_ability(slot, ability, at)
	return ""


# Host: after beating the last wave, keeps the game going in endless mode. The
# win is already on the normal leaderboard; the endless run's score is sent
# when it ends.
func keep_going(slot: int) -> String:
	if slot != local_slot:
		return "Only the host can choose to keep going"
	if state != "won" or endless:
		return ""
	if daily_date != "":
		return "The daily challenge ends at wave %d" % DAILY_WAVES
	if weekly_id != "":
		return "The weekly challenge ends at wave %d" % WEEKLY_WAVES
	endless = true
	state = "playing"
	end_stats = {}
	score_sent = false  # (game_net.gd) so the game time keeps counting from wave 1
	next_wave_timer = WAVE_INTERVAL
	var text := "Endless mode! How far can you get?"
	flash(text)
	send_all("net_message", [text])
	send_endless()
	play_sound("endless_start")
	return ""


# The difficulty level (index in DIFFICULTIES): only the host (or a player
# alone), and only before wave 1. Start gold changes with it (Easy gives more).
func set_difficulty(slot: int, d: int) -> String:
	if slot != local_slot:
		return "Only the host can change the level"
	if wave > 0 or state != "playing":
		return "The level can only change before wave 1"
	if daily_date != "":
		return "The daily challenge has its own level"
	if weekly_id != "":
		return "The weekly challenge is always %s" % DIFFICULTIES[WEEKLY_LEVEL]
	if d < 0 or d >= DIFFICULTIES.size() or d == difficulty:
		return ""
	var old_gold := start_gold()
	difficulty = d
	for p in players:
		if p != null:
			var before: int = p.gold
			p.gold = maxi(p.gold + start_gold() - old_gold, 0)
			# The stats' start gold changes by what the player really got (or lost)
			stat_start[p.slot] += p.gold - before
	send_difficulty()
	var text := "Level: %s" % DIFFICULTIES[d]
	var hp: float = DIFFICULTY_HP[d]
	if hp != 1.0:
		text += " (monsters have %d%% %s health)" % [roundi(absf(hp - 1.0) * 100.0), "more" if hp > 1.0 else "less"]
	flash(text)
	send_all("net_message", [text])
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
	if not daily_allows(type):
		return "Today's challenge doesn't allow %s towers" % TOWERS[type]["name"]
	var cost: int = TOWERS[type]["cost"][0]
	if type == "barracks" and not barracks_fits(c):
		return "A Barracks must stand next to the path"
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
	stat_spent[slot] += cost
	towers[c] = t
	build_tower_node(t)
	send_tower(t)
	prog_add(slot, "built_" + type)
	if type == "frost":
		prog_for(slot).frost = true
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
	stat_spent[slot] += cost
	t.spent += cost
	t.level += 1
	if path != 0:
		t.path = path
		# Sniper and Overload start on Strongest (the player can change it)
		if PATHS[t.type][path - 1].has("mode"):
			t.mode = PATHS[t.type][path - 1]["mode"]
	build_tower_node(t)
	send_tower(t)
	profile_upgrade(t)
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
	if challenge_rules().get("no_sell", false):
		return "Towers can't be sold in this challenge"
	players[slot].gold += int(t.spent * 0.7)
	stat_spent[slot] -= int(t.spent * 0.7)
	sold_towers.append(t)  # its damage and kills still count at the end
	remove_tower(c)
	send_all("net_tower_removed", [c])
	return ""


# ---------------------------------------------------------------- saving and loading
# A save is SAVES_DIR/<name>.sav, compressed: a header (what the Load list
# shows), then the game. Both are plain values in Godot's binary format, read
# without objects, so a save can't run code, and gold up to GOLD_MAX stays exact.
# Saved: the map (custom maps too), level, wave and timer, spawning, endless,
# daily, each player's gold and ability cooldowns (also saved players not back
# yet), towers, monsters, poison clouds and the end screen's stats. Not saved:
# shots in flight, effects, the replay. Only the host or a player alone saves
# and loads, and only while nobody has joined. A loaded game is held until the
# host presses Space, and never goes on a leaderboard (from_save).
#
# For the Esc menu (graphics): can_save(), can_load(), default_save_name(),
# save_exists(), list_saves(), menu_save(), menu_load(), delete_save(), held_text().
# For game_net.gd: saved_slot_for(), restore_saved_player(), from_save, held, held_note.

# A new tower or monster field only needs adding here: older saves keep its default.
# Barracks: the soldiers' health and respawn wait are saved; holds are let go
# (every monster is free after loading) and the rally point is worked out again.
const SAVE_TOWER_FIELDS := ["type", "cell", "owner", "level", "path", "mode", "spent", "cooldown", "aim", "dealt", "kills",
		"soldier_hp", "soldier_wait"]
const SAVE_ENEMY_FIELDS := ["id", "kind", "pos", "wp", "loop_wp", "hp", "max_hp", "speed", "armor", "bounty", "weight",
		"radius", "slow_factor", "slow_time", "freeze_time", "freeze_immune", "traveled", "special", "shield",
		"max_shield", "shield_wait", "heal_timer", "weak", "poisoned", "hold_immune", "haste_time"]
const SAVE_CLOUD_FIELDS := {"pos": TYPE_VECTOR2, "r": TYPE_FLOAT, "time": TYPE_FLOAT, "dps": TYPE_FLOAT,
		"owner": TYPE_INT, "cell": TYPE_VECTOR2I, "boss": TYPE_FLOAT, "weak": TYPE_FLOAT}


# Why this computer can't save now, or "".
func can_save() -> String:
	if net_mode == "client":
		return "Only the host can save"
	if net_mode in ["searching", "connecting", "map_offer"]:
		return "Can't save while joining a game"
	if editing:
		return "Can't save in the map editor"
	if replay_on or state != "playing":
		return "Only a game that's still going can be saved"
	return ""


# Why this computer can't load a game now, or "".
func can_load() -> String:
	if net_mode == "client":
		return "Only the host can load a game"
	if net_mode in ["searching", "connecting", "map_offer"]:
		return "Can't load while joining a game"
	if net_mode == "host" and player_count() > 1:
		return "A game can only be loaded while nobody has joined"
	if editing:
		return "Close the map editor first"
	return ""


func save_path(save_name: String) -> String:
	return "%s/%s.sav" % [SAVES_DIR, save_name.validate_filename()]


# The name the Save box suggests: "Wave 37 - Normal - Default".
func default_save_name() -> String:
	var title := map_name if daily_date == "" else "Daily %s" % daily_date
	if weekly_id != "":
		title = weekly_title(weekly_id)
	return clean_text("Wave %d - %s - %s" % [wave, DIFFICULTIES[difficulty], title], SAVE_NAME_MAX)


# For the "Overwrite?" question.
func save_exists(save_name: String) -> bool:
	return FileAccess.file_exists(save_path(clean_text(save_name, SAVE_NAME_MAX)))


# Every save's header, for the Load list: Continue first, then newest first.
# Each: {name, time (unix seconds), version, wave, level (index in DIFFICULTIES),
# map, daily, weekly (week id or "", missing in older saves), endless, players
# (names), from_save, auto}. Load or delete one by
# its name.
func list_saves() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		return out
	for file in DirAccess.get_files_at(SAVES_DIR):
		if file.get_extension() != "sav":
			continue
		var f := FileAccess.open_compressed(SAVES_DIR + "/" + file, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if f == null:
			continue
		var head: Variant = f.get_var(false)
		f.close()
		if head is Dictionary and head.get("format") is int and head.get("name") is String:
			out.append(head)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a.name == AUTOSAVE_NAME) != (b.name == AUTOSAVE_NAME):
			return a.name == AUTOSAVE_NAME
		return a.get("time", 0) > b.get("time", 0))
	return out


func named_save_count() -> int:
	return list_saves().filter(func(h: Dictionary) -> bool: return not h.get("auto", false)).size()


# The Esc menu's Save (and F5): saves, and says how it went.
func menu_save(save_name: String) -> void:
	var problem := save_game(save_name)
	play_sound("save" if problem == "" else "denied")
	flash(problem if problem != "" else "Saved \"%s\"" % clean_text(save_name, SAVE_NAME_MAX))


# The Esc menu's Load (and F9).
func menu_load(save_name: String) -> void:
	var problem := load_game(save_name)
	play_sound("load" if problem == "" else "denied")
	if problem != "":
		flash(problem)


func delete_save(save_name: String) -> String:
	var path := save_path(save_name)
	if not FileAccess.file_exists(path):
		return ""
	return "" if DirAccess.remove_absolute(path) == OK else "Couldn't delete that save"


# Saves the game as save_name ("": default_save_name()), over a save with that
# name. Returns why it couldn't, or "".
func save_game(save_name: String) -> String:
	var problem := can_save()
	if problem != "":
		return problem
	save_name = clean_text(save_name, SAVE_NAME_MAX)
	if save_name == "":
		save_name = default_save_name()
	var path := save_path(save_name)
	var auto := save_name == AUTOSAVE_NAME or save_name == QUICKSAVE_NAME
	if not auto and not FileAccess.file_exists(path) and named_save_count() >= SAVES_MAX:
		return "There are %d saves already: delete one first" % SAVES_MAX
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	var names := []
	for p in players:
		if p != null:
			names.append(name_of(p.slot))
	var head := {"format": SAVE_FORMAT, "version": version, "name": save_name, "time": int(Time.get_unix_time_from_system()),
			"wave": wave, "level": difficulty, "map": map_name, "daily": daily_date, "weekly": weekly_id, "endless": endless,
			"players": names, "from_save": from_save, "auto": auto}
	# Written next to it first, so a crash halfway never breaks the old save
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return "Couldn't save (%s)" % error_string(FileAccess.get_open_error())
	f.store_var(head, false)
	f.store_var(make_save(), false)
	var failed := f.get_error() != OK
	f.close()
	if failed:
		DirAccess.remove_absolute(tmp)
		return "Couldn't save"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		return "Couldn't save"
	return ""


# The Continue save: at every wave start and when the game is closed. Not in
# headless test runs, so tests don't touch the player's Continue save.
func autosave() -> void:
	if wave > 0 and can_save() == "" and DisplayServer.get_name() != "headless":
		save_game(AUTOSAVE_NAME)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()
		save_profile()


func pack_fields(o: Object, fields: Array) -> Dictionary:
	var d := {}
	for f: String in fields:
		d[f] = o.get(f)
	return d


# Only values of the right type are taken (a missing one keeps the default).
func unpack_fields(o: Object, d: Dictionary, fields: Array) -> void:
	for f: String in fields:
		if d.has(f) and typeof(d[f]) == typeof(o.get(f)):
			o.set(f, d[f])


# The game, for save_game().
func make_save() -> Dictionary:
	var list := []
	for slot in MAX_PLAYERS:
		var p: Player = players[slot]
		if p != null:
			list.append({"slot": slot, "name": name_of(slot), "gold": p.gold, "cooldowns": p.cooldowns.duplicate()})
		elif saved_slots.has(slot):
			list.append(saved_slots[slot].duplicate(true).merged({"slot": slot}))
	var tower_list := []
	for t: Tower in towers.values():
		tower_list.append(pack_fields(t, SAVE_TOWER_FIELDS))
	var sold := []
	for t: Tower in sold_towers:
		sold.append(pack_fields(t, SAVE_TOWER_FIELDS))
	var monsters := []
	for e in enemies + new_enemies:
		if not e.dead:
			var d := pack_fields(e, SAVE_ENEMY_FIELDS)
			d["gate"] = routes.find(e.route)  # the route itself comes from the map
			monsters.append(d)
	return {"map_name": map_name, "map": map_rows_text.duplicate(), "daily": daily_date, "weekly": weekly_id, "mood": mood, "difficulty": difficulty,
			"endless": endless, "wave": wave, "timer": next_wave_timer, "run_time": run_time, "spawn_hp": spawn_hp,
			"spawn_queues": spawn_queues.duplicate(true), "spawn_timers": spawn_timers.duplicate(),
			"next_enemy_id": next_enemy_id, "host_slot": local_slot, "players": list, "colors": slot_colors.duplicate(), "towers": tower_list,
			"enemies": monsters, "clouds": clouds.duplicate(true), "cloud_tick": cloud_tick, "cloud_turn": cloud_turn,
			"from_save": from_save, "progress": save_progress(),
			"stats": {"kills": stat_kills, "damage": stat_damage, "start": stat_start, "earned": stat_earned,
					"spent": stat_spent, "gifted": stat_gifted, "names": stat_names, "sold": sold}}


# Whether d has these keys with these types (TYPE_FLOAT also takes whole numbers).
func has_types(d: Variant, types: Dictionary) -> bool:
	if not d is Dictionary:
		return false
	for k in types:
		var t := typeof(d.get(k))
		if t != types[k] and not (types[k] == TYPE_FLOAT and t == TYPE_INT):
			return false
	return true


# A per-player-slot list of 4 numbers from a save (0 for anything broken).
func four(v: Variant, as_float: bool) -> Array:
	var out := [0.0, 0.0, 0.0, 0.0] if as_float else [0, 0, 0, 0]
	if v is Array and v.size() == MAX_PLAYERS:
		for i in MAX_PLAYERS:
			if v[i] is int or v[i] is float:
				out[i] = float(v[i]) if as_float else int(v[i])
	return out


# Loads a save (by its name) over the game being played. Returns why it
# couldn't, or "" (then the game is held: see held_text()).
func load_game(save_name: String) -> String:
	var problem := can_load()
	if problem != "":
		return problem
	var path := save_path(save_name)
	if not FileAccess.file_exists(path):
		return "There's no save called \"%s\"" % save_name
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return "Couldn't open that save"
	var head: Variant = f.get_var(false)
	var d: Variant = f.get_var(false)
	f.close()
	if not (head is Dictionary and head.get("format") is int):
		return "That save is broken"
	if head.format > SAVE_FORMAT:
		return "That save is from a newer version of the game (%s)" % str(head.get("version", "?"))
	# (Saves with an older format would be converted here; format 1 is the first.)
	if not has_types(d, {"map": TYPE_ARRAY, "map_name": TYPE_STRING, "daily": TYPE_STRING, "difficulty": TYPE_INT,
			"wave": TYPE_INT, "timer": TYPE_FLOAT, "spawn_queues": TYPE_ARRAY, "spawn_timers": TYPE_ARRAY,
			"next_enemy_id": TYPE_INT, "host_slot": TYPE_INT, "players": TYPE_ARRAY, "towers": TYPE_ARRAY,
			"enemies": TYPE_ARRAY, "stats": TYPE_DICTIONARY}) \
			or d.difficulty < 0 or d.difficulty >= DIFFICULTIES.size() or d.host_slot < 0 or d.host_slot >= MAX_PLAYERS \
			or d.wave < 0 or d.spawn_queues.size() != MAX_PLAYERS or d.spawn_timers.size() != MAX_PLAYERS:
		return "That save is broken"
	var m := read_map(d.map)
	if m.has("error"):
		return "That save's map is broken"
	apply_save(d, m)
	var text := held_text() if held else "Loaded \"%s\"" % save_name
	flash(text)
	return ""


func apply_save(d: Dictionary, m: Dictionary) -> void:
	clear_world()
	reset_stats()
	lap_lengths.clear()
	var title := clean_text(d.map_name, MAP_NAME_MAX)
	use_map(m, title if title != "" else "Saved map")
	# The saved weather and time of day (older saves: day), built with the map
	mood = d.mood if d.get("mood") is String and d.mood in MOODS else "day"
	build_map()
	send_mood(mood)
	var date: String = d.daily
	if date.length() == 10 and date.replace("-", "").is_valid_int() and map_rows_text == daily_map(date).text:
		daily_date = date
	# The weekly challenge: only on that week's map (older saves have no "weekly")
	var week: Variant = d.get("weekly", "")
	if daily_date == "" and weekly_valid(week) and map_rows_text == weekly_map(week).text:
		weekly_id = week
	difficulty = d.difficulty
	endless = d.get("endless") == true
	wave = d.wave
	next_wave_timer = d.timer
	run_time = d.run_time if d.get("run_time") is float else 0.0
	score_sent = false
	spawn_hp = d.spawn_hp if d.get("spawn_hp") is float else wave_hp(maxi(wave, 1))
	for g in MAX_PLAYERS:
		spawn_queues[g] = []
		if d.spawn_queues[g] is Array and g < routes.size() and not routes[g].is_empty():
			for kind in d.spawn_queues[g]:
				if kind in ENEMY_KINDS:
					spawn_queues[g].append(kind)
		spawn_timers[g] = float(d.spawn_timers[g]) if (d.spawn_timers[g] is float or d.spawn_timers[g] is int) else 0.0
	next_enemy_id = maxi(d.next_enemy_id, 1)
	game_speed = 1
	state = "playing"
	aiming = ""
	end_stats = {}
	# Players: this computer gets the saver's slot; the others wait in saved_slots
	var me: Player = players[local_slot]
	if me == null:
		me = Player.new()
		me.name = my_name()
	players = [null, null, null, null]
	saved_slots.clear()
	local_slot = d.host_slot
	me.slot = local_slot
	players[local_slot] = me
	for item in d.players:
		if not has_types(item, {"slot": TYPE_INT, "name": TYPE_STRING, "gold": TYPE_INT, "cooldowns": TYPE_DICTIONARY}) \
				or item.slot < 0 or item.slot >= mini(MAX_PLAYERS, routes.size()) or routes[item.slot].is_empty():
			continue
		var gold_left := clampi(item.gold, 0, GOLD_MAX)
		var cools := {}
		for a in item.cooldowns:
			if ABILITIES.has(a) and (item.cooldowns[a] is float or item.cooldowns[a] is int):
				cools[a] = float(item.cooldowns[a])
		if item.slot == local_slot:
			me.gold = gold_left
			me.cooldowns = cools
		else:
			saved_slots[item.slot] = {"name": clean_text(item.name, NAME_MAX), "gold": gold_left, "cooldowns": cools}
	colors_from_save(d.get("colors"))
	# Towers
	for td in d.towers:
		var t := Tower.new()
		if td is Dictionary:
			unpack_fields(t, td, SAVE_TOWER_FIELDS)
		if not (TOWERS.has(t.type) and in_map(t.cell) and not path_cells.has(t.cell) and not blocked.has(t.cell)
				and not towers.has(t.cell) and t.owner >= 0 and t.owner < MAX_PLAYERS and t.mode >= 0 and t.mode < TARGET_MODES.size()):
			continue
		t.level = clampi(t.level, 0, MAX_LEVEL - 1)
		t.path = clampi(t.path, 0, 2) if t.level >= PATH_LEVEL else 0
		t.pos = cell_center(t.cell)
		towers[t.cell] = t
		build_tower_node(t)
	# Stats
	var s: Dictionary = d.stats
	stat_kills = four(s.get("kills"), false)
	stat_damage = four(s.get("damage"), true)
	stat_start = four(s.get("start"), false)
	stat_earned = four(s.get("earned"), false)
	stat_spent = four(s.get("spent"), false)
	stat_gifted = four(s.get("gifted"), false)
	var names: Variant = s.get("names")
	for i in MAX_PLAYERS:
		stat_names[i] = clean_text(names[i], NAME_MAX) if names is Array and names.size() == MAX_PLAYERS and names[i] is String else ""
	if s.get("sold") is Array:
		for td in s.sold:
			var t := Tower.new()
			if td is Dictionary:
				unpack_fields(t, td, SAVE_TOWER_FIELDS)
			if TOWERS.has(t.type) and t.owner >= 0 and t.owner < MAX_PLAYERS:
				t.level = clampi(t.level, 0, MAX_LEVEL - 1)
				sold_towers.append(t)
	# Monsters, in id order (send_snapshot() needs that)
	var list: Array = d.enemies.filter(func(ed: Variant) -> bool: return ed is Dictionary and ed.get("id") is int)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for ed: Dictionary in list:
		var gate: int = ed.get("gate", -1) if ed.get("gate") is int else -1
		if not (ed.get("kind") in ENEMY_KINDS and gate >= 0 and gate < routes.size() and not routes[gate].is_empty()) \
				or enemy_by_id.has(ed.id):
			continue
		var e := make_enemy(ed.kind)
		unpack_fields(e, ed, SAVE_ENEMY_FIELDS)
		e.route = routes[gate]
		if e.wp < 0 or e.wp >= e.route.size() or e.loop_wp < 0 or e.loop_wp >= e.route.size() or not (e.hp > 0.0):
			e.node.queue_free()
			continue
		enemies.append(e)
		enemy_by_id[e.id] = e
		next_enemy_id = maxi(next_enemy_id, e.id + 1)
	# Poison clouds
	if d.get("clouds") is Array:
		for c: Variant in d.clouds:
			if has_types(c, SAVE_CLOUD_FIELDS):
				var cloud := {}
				for k in SAVE_CLOUD_FIELDS:
					cloud[k] = float(c[k]) if SAVE_CLOUD_FIELDS[k] == TYPE_FLOAT else c[k]
				clouds.append(cloud)
				show_cloud(cloud.pos, cloud.r, cloud.time, 2 if cloud.weak > 0.0 else 0)
	cloud_tick = float(d.get("cloud_tick")) if d.get("cloud_tick") is float else 0.0
	cloud_turn = posmod(d.get("cloud_turn"), 4) if d.get("cloud_turn") is int else 0
	load_progress(d.get("progress"))
	from_save = true
	held = wave > 0
	held_note = ""
	menu_open = false
	send_difficulty()


# The line shown while a loaded game is held ("" when not): who it waits for.
func held_text() -> String:
	if not held:
		return ""
	if net_mode == "client":
		return held_note
	var waiting := []
	for slot in saved_slots:
		waiting.append("%s (%s)" % [color_name(slot), saved_slots[slot].name])
	var text := "Loaded wave %d, on hold." % wave
	if not waiting.is_empty():
		text += " Waiting for %s." % ", ".join(waiting)
	return text + " Press SPACE to go on"


# The host's Space while held: the game goes on.
func unhold(slot: int) -> String:
	if slot != local_slot:
		return "The host goes on when everyone is back"
	held = false
	var text := "The game goes on!"
	flash(text)
	send_all("net_message", [text])
	return ""


# Host, a player joining a loaded game: the saved slot they get back (the one
# saved with their name, else the first one nobody has taken), -1 if none.
func saved_slot_for(their_name: String) -> int:
	var wanted := clean_text(their_name, NAME_MAX).to_lower()
	for slot: int in saved_slots:
		if players[slot] == null and wanted != "" and String(saved_slots[slot].name).to_lower() == wanted:
			return slot
	for slot in MAX_PLAYERS:
		if saved_slots.has(slot) and players[slot] == null:
			return slot
	return -1


# Host: gives a player who just joined (already in players[p.slot]) the gold and
# cooldowns saved for their slot. True if it did: then their stats stay as saved
# (no late-join gold, no fresh stats).
func restore_saved_player(p: Player) -> bool:
	if not saved_slots.has(p.slot):
		return false
	var s: Dictionary = saved_slots[p.slot]
	saved_slots.erase(p.slot)
	p.gold = s.gold
	p.cooldowns = s.cooldowns.duplicate()
	stat_names[p.slot] = p.name
	# Their join wave and flags as saved (see load_progress())
	if prog[p.slot].has("join") and prog[p.slot].get("who") == null:
		prog[p.slot].who = p
	return true


# ---------------------------------------------------------------- achievements and profile (host)
# See ACHIEVEMENTS and apply_profile_update() in game_base.gd. The host (or a
# player alone) keeps a record per player slot in prog (see prog_for()): when they
# joined, whether they used an ability or built a Frost tower, and the counters
# since their last profile update. The hooks are cheap and never run per hit:
# kills and broken shields (damage_enemy()), Meteor and Freeze all (do_ability()),
# builds, upgrades and gifts. At every wave start and at the end of a game each
# player gets their update (profile_update()). A loaded game keeps the records
# (save_progress() / load_progress()), so it counts on, but not as a new game.

const KILL_KEYS := {"arrow": "kills_arrow", "cannon": "kills_cannon", "frost": "kills_frost", "spark": "kills_spark", "poison": "kills_poison",
		"barracks": "kills_barracks"}
const WIN_ACHIEVEMENTS := ["easy_win", "normal_win", "hard_win", "insane_win"]  # per level

# Host: per slot {who (the Player it's about), join (the wave they joined in),
# counted (their games played has this game), used (Meteor or Freeze all), frost
# (built a Frost tower), add (counters not sent yet), earned (ids not sent yet),
# sent (ids already judged this game), dmg (tower damage per type already counted)}.
var prog: Array = [{}, {}, {}, {}]


# A slot's record. Someone new in the slot (a player who joined, or came back)
# starts a new one, joined in this wave.
func prog_for(slot: int) -> Dictionary:
	var p: Player = players[slot]
	var rec: Dictionary = prog[slot]
	if rec.is_empty() or rec.get("who") != p:
		rec = {"who": p, "join": wave, "counted": false, "used": false, "frost": false, "add": {}, "earned": [], "sent": {}, "dmg": {}}
		prog[slot] = rec
	return rec


func prog_add(slot: int, key: String, n := 1) -> void:
	if slot < 0 or slot >= MAX_PLAYERS:
		return
	var add: Dictionary = prog_for(slot).add
	add[key] = add.get(key, 0) + n


# Achievements, best waves and level wins count on the Default map and the daily
# and weekly challenges' maps (daily_date / weekly_id are only set on that day's /
# week's map), not on custom maps.
func map_counts() -> bool:
	return daily_date != "" or weekly_id != "" or map_rows_text == DEFAULT_MAP


# In the game early enough for a win or an endless wave to count.
func were_there(rec: Dictionary) -> bool:
	if daily_date != "":
		return rec.join <= JOIN_BY_DAILY
	return rec.join <= (JOIN_BY_WEEKLY if weekly_id != "" else JOIN_BY)


# Host: a player earned an achievement (on a map that counts). The host's own
# shows right away; the others' go with their next update.
func earn(slot: int, id: String) -> void:
	if not map_counts() or players[slot] == null:
		return
	var rec := prog_for(slot)
	if rec.sent.has(id):
		return
	rec.sent[id] = true
	if slot == local_slot:
		apply_profile_update({"earned": [id]})
	else:
		rec.earned.append(id)


# A monster died (damage_enemy()): slot's counters.
func profile_kill(e: Enemy, slot: int, t: Tower) -> void:
	var add: Dictionary = prog_for(slot).add
	add["kills"] = add.get("kills", 0) + 1
	if e.kind == "boss":
		add["bosses"] = add.get("bosses", 0) + 1
	if e.special == "splitling":
		add["splitlings"] = add.get("splitlings", 0) + 1
	elif e.special == "heal":
		add["healers"] = add.get("healers", 0) + 1
	if t != null:
		var key: String = KILL_KEYS[t.type]
		add[key] = add.get(key, 0) + 1
		if t.type == "poison":
			add["poison_kills"] = add.get("poison_kills", 0) + 1


# A tower was upgraded (upgrade_tower()): Maxed Out and One of Each.
func profile_upgrade(t: Tower) -> void:
	if not map_counts():
		return
	if t.level + 1 >= 30:
		earn(t.owner, "maxed_out")
	if t.level >= PATH_LEVEL and not prog_for(t.owner).sent.has("one_of_each"):
		var types := {}
		for o: Tower in towers.values():
			if o.owner == t.owner and o.level >= PATH_LEVEL:
				types[o.type] = true
		if types.size() >= TOWER_TYPES.size():
			earn(t.owner, "one_of_each")


# Host, at every wave start: the wave achievements, then everyone's update.
func profile_wave_start() -> void:
	if net_mode == "client":
		return
	for p in players:
		if p == null:
			continue
		var rec := prog_for(p.slot)
		var challenge := daily_date != "" or weekly_id != ""
		if not challenge and wave >= 30:
			earn(p.slot, "warming_up")
		if not challenge and difficulty == DIFFICULTIES.size() - 1 and wave >= 150:
			earn(p.slot, "insane_150")
		if endless and were_there(rec):
			for goal: int in [400, 500, 600]:
				if wave >= goal:
					earn(p.slot, "endless_%d" % goal)
		if wave >= 100 and player_count() >= 2:
			earn(p.slot, "together_100")
		if wave >= 50 and player_count() >= MAX_PLAYERS:
			earn(p.slot, "full_house")
		profile_update(p.slot, "")


# Host, when a game ends (won, lost, or an endless run ended; after end_stats):
# the end-of-game achievements, then everyone's update.
func profile_game_end() -> void:
	var result := "won" if state == "won" else ("endless_end" if endless else "lost")
	# Tower damage per slot and type, from the towers' own counts (nothing per hit)
	var dmg := {}
	for t: Tower in sold_towers + towers.values():
		if t.dealt > 0.0:
			if not dmg.has(t.owner):
				dmg[t.owner] = {}
			dmg[t.owner][t.type] = dmg[t.owner].get(t.type, 0.0) + t.dealt
	var rows: Array = end_stats.get("players", [])
	for p in players:
		if p == null:
			continue
		var slot: int = p.slot
		var rec := prog_for(slot)
		var mine: Dictionary = dmg.get(slot, {})
		var top := ""
		for type: String in mine:
			var more: float = mine[type] - rec.dmg.get(type, 0.0)
			if more > 0.0:
				rec.add["damage_" + type] = more
				rec.dmg[type] = mine[type]
			if top == "" or mine[type] > mine[top]:
				top = type
		if result == "won" and were_there(rec):
			if daily_date != "":
				earn(slot, "daily_win")
			elif weekly_id != "":
				earn(slot, "weekly_win")
			else:
				earn(slot, WIN_ACHIEVEMENTS[difficulty])
				if not rec.used:
					earn(slot, "hands_off")
				if difficulty >= 1 and not rec.frost:
					earn(slot, "cold_feet")
				if difficulty >= 2 and top == "poison":
					earn(slot, "green_thumb")
		if end_stats.get("mvp", -1) == slot and rows.size() >= 2 and wave >= 50:
			earn(slot, "mvp")
		profile_update(slot, result)


# Host: hands a player what the game has for their profile (see
# apply_profile_update() in game_base.gd). result: "" at a wave start.
func profile_update(slot: int, result: String) -> void:
	if players[slot] == null:
		return
	var rec := prog_for(slot)
	var data := {"add": rec.add, "earned": rec.earned, "counts": map_counts(), "level": difficulty, "daily": daily_date, "weekly": weekly_id,
			"twist": daily_rules().get("twist", ""), "wave": wave, "endless": endless, "there": were_there(rec), "result": result}
	if not rec.counted and wave > 0:
		rec.counted = true
		data.start = true
	if result != "":
		data.mp = end_stats.get("players", []).size() >= 2
	rec.add = {}
	rec.earned = []
	if slot == local_slot:
		apply_profile_update(data)
	else:
		send_profile_update(slot, data)


# For the save: each player's record (also players not back yet).
func save_progress() -> Array:
	var out := []
	for slot in MAX_PLAYERS:
		if players[slot] == null and not saved_slots.has(slot):
			continue
		var rec: Dictionary = prog_for(slot) if players[slot] != null else prog[slot]
		if rec.is_empty():
			continue
		out.append({"slot": slot, "join": rec.join, "counted": rec.counted, "used": rec.used, "frost": rec.frost, "dmg": rec.dmg.duplicate()})
	return out


# After loading (apply_save()): the records as saved. A player the save has no
# record for (a save from before achievements) counts as joining now, already
# counted, having used an ability and built Frost (nobody knows they didn't).
func load_progress(v: Variant) -> void:
	prog = [{}, {}, {}, {}]
	var found := {}
	if v is Array:
		for item: Variant in v:
			if not has_types(item, {"slot": TYPE_INT, "join": TYPE_INT, "counted": TYPE_BOOL, "used": TYPE_BOOL, "frost": TYPE_BOOL}) \
					or item.slot < 0 or item.slot >= MAX_PLAYERS:
				continue
			var dmg := {}
			if item.get("dmg") is Dictionary:
				for k: Variant in item.dmg:
					var n: Variant = item.dmg[k]
					if k is String and k in TOWER_TYPES and (n is float or n is int) and is_finite(float(n)):
						dmg[k] = float(n)
			found[item.slot] = {"join": maxi(item.join, 0), "counted": item.counted, "used": item.used, "frost": item.frost, "dmg": dmg}
	for slot in MAX_PLAYERS:
		if players[slot] == null and not saved_slots.has(slot):
			continue
		var rec: Dictionary = found.get(slot, {"join": wave, "counted": true, "used": true, "frost": true, "dmg": {}})
		rec.merge({"who": players[slot], "add": {}, "earned": [], "sent": {}}, true)
		prog[slot] = rec


# ---------------------------------------------------------------- stats at the end

# Host / alone, once when the game ends: everything the stats screen shows.
# players: [slot, name, kills, damage, gold earned, gold spent, gold gifted (got
# minus given, see gift_gold())] for everyone who played; towers: the 5 that did the most damage, [type, path, level, owner,
# owner's name, damage, kills]; mvp: the slot with the most damage (kills break a
# tie), -1 alone.
func make_end_stats() -> Dictionary:
	var rows := []
	var mvp := -1
	for slot in MAX_PLAYERS:
		if players[slot] != null:
			stat_names[slot] = name_of(slot)
		elif stat_names[slot] == "":
			continue
		rows.append([slot, stat_names[slot], stat_kills[slot], stat_damage[slot], stat_earned[slot], stat_spent[slot], stat_gifted[slot]])
		if mvp < 0 or stat_damage[slot] > stat_damage[mvp] or \
				(stat_damage[slot] == stat_damage[mvp] and stat_kills[slot] > stat_kills[mvp]):
			mvp = slot
	var list: Array = sold_towers + towers.values()
	list = list.filter(func(t: Tower) -> bool: return t.dealt > 0.0)
	list.sort_custom(func(a: Tower, b: Tower) -> bool: return a.dealt > b.dealt)
	var best := []
	for t: Tower in list.slice(0, 5):
		best.append([t.type, t.path, t.level, t.owner, stat_names[t.owner], t.dealt, t.kills])
	return {"wave": wave, "won": state == "won", "ms": int(run_time * 1000.0), "players": rows,
			"towers": best, "mvp": mvp if rows.size() > 1 else -1}


# ---------------------------------------------------------------- replay of the last minute

# Every computer records what it sees (no network traffic): every REPLAY_STEP
# game seconds a frame with each monster's id, place, health and look, plus the
# shots and effects since the frame before. After losing, V plays the last
# REPLAY_SECONDS back with the normal visuals. While it plays, the real monsters
# and shots are put aside and hidden (live_enemies, live_shots), and enemies /
# shots hold the replay's copies, so the top bar, small map and health bars
# show the replay. The towers are shown as they are at the end.
const REPLAY_SECONDS := 60.0  # game seconds kept
const REPLAY_STEP := 0.1  # game seconds between recorded frames
const REPLAY_SPEEDS := [0.5, 1.0, 2.0, 4.0]
const REPLAY_BAR := Rect2(240, BAR_TOP - 64, 800, 22)  # the timeline's clickable track (REPLAY_TRACK in game_ui.gd draws it)
const REPLAY_BYTES := 12  # per monster in a frame (see record_frame())

# Frames: [game time, wave, alive (see alive_count()), max_alive(), monsters, events,
# soldiers (barracks_info(): every Barracks' soldiers, empty without one)].
# monsters: per monster id (u32), x and y in 1/32 pixels (u16 each), health share
# of 65535 (u16), its kind + 128 slowed + 64 frozen + 32 got past (has walked a
# whole lap; known by the host and alone), and its special_bits() + 32 poisoned.
# events: ["shot", tower cell, monster id], ["bolt", points], ["boom", pos, r],
# ["frost", pos, r], ["ability", slot, ability, pos] or ["crescendo", monster id].
var rec_frames: Array = []
var rec_time := 0.0  # game seconds recorded
var rec_since := 0.0  # since the last frame
var rec_events: Array = []  # since the last frame
var rec_closed := false  # the game ended and its last frame is in
var lap_lengths := {}  # a route's first point -> how far a whole lap is

var replay_on := false
var replay_t := 0.0  # the game time being shown (rec_frames' clock)
var replay_speed := 1.0
var replay_paused := false
var replay_frame := -1  # the frame shown last (its events have been played)
var replay_ghosts := {}  # recorded monster id -> its replay copy (id -1 - recorded id)
var replay_past := {}  # replay copies that got past (Enemy -> true)
var live_enemies: Array[Enemy] = []
var live_shots: Array[Shot] = []
var replay_layer: Node2D  # the replay panel, drawn by draw_replay_bar() in game_ui.gd
var replay_drag := false


# Every computer, every frame: keeps the last minute (see REPLAY_SECONDS).
func record_frame(dt: float) -> void:
	if replay_on or wave == 0:
		return
	if state != "playing":
		# One last frame when the game ends (an endless run starts recording again)
		if rec_closed:
			return
		rec_closed = true
	else:
		rec_closed = false
		rec_time += dt
		rec_since += dt
		if rec_since < REPLAY_STEP:
			return
	rec_since = 0.0
	var data := PackedByteArray()
	data.resize(enemies.size() * REPLAY_BYTES)
	var at := 0
	for e in enemies:
		data.encode_u32(at, e.id)
		data.encode_u16(at + 4, clampi(roundi(e.pos.x * 32.0), 0, 65535))
		data.encode_u16(at + 6, clampi(roundi(e.pos.y * 32.0), 0, 65535))
		data.encode_u16(at + 8, clampi(roundi(e.hp / e.max_hp * 65535.0), 0, 65535))
		var flags := ENEMY_KINDS.find(e.kind) | (128 if e.slow_time > 0.0 else 0) | (64 if e.freeze_time > 0.0 else 0)
		if got_past(e):
			flags |= 32
		data[at + 10] = flags
		# The trait and shield (see special_bits()), + 32 poisoned (host and alone)
		data[at + 11] = special_bits(e) | (32 if e.poisoned > 0.0 else 0)
		at += REPLAY_BYTES
	rec_frames.append([rec_time, wave, alive_count(), max_alive(), data, rec_events, barracks_info()])
	rec_events = []
	while rec_frames.size() > 1 and rec_frames[0][0] < rec_time - REPLAY_SECONDS:
		rec_frames.pop_front()


# How far a monster walks from its gate once around the loop (only the host and
# a player alone know the monsters' routes).
func lap_length(e: Enemy) -> float:
	var key: Vector2 = e.route[0]
	if not lap_lengths.has(key):
		var n := 0.0
		for i in range(1, e.route.size()):
			n += e.route[i - 1].distance_to(e.route[i])
		lap_lengths[key] = n + e.route[e.route.size() - 1].distance_to(e.route[e.loop_wp])
	return lap_lengths[key]


# The host and a player alone know the routes; the other players go by the
# host's snapshots (Enemy.past).
func got_past(e: Enemy) -> bool:
	return e.past if e.route.is_empty() else e.traveled > lap_length(e)


func rec_event(ev: Array) -> void:
	if not replay_on and wave > 0 and state == "playing":
		rec_events.append(ev)


# The effects are recorded where every computer makes them (the other players'
# come from the host's messages), then made as usual.
func launch_shot(t: Tower, target: Enemy, visual: bool) -> void:
	rec_event(["shot", t.cell, target.id])
	super(t, target, visual)
	# The poison glob's speed (gameplay; game_world.gd makes the shot)
	if t.type == "poison" and not shots.is_empty() and shots[-1].tower == t:
		shots[-1].speed = POISON_SHOT_SPEED


func add_bolt(points: PackedVector3Array) -> void:
	rec_event(["bolt", points])
	super(points)


func add_boom(pos: Vector2, r: float) -> void:
	rec_event(["boom", pos, r])
	super(pos, r)


func add_frost_ring(pos: Vector2, r: float) -> void:
	rec_event(["frost", pos, r])
	super(pos, r)
	play_sound("frost_ring", pos)


func show_ability(slot: int, ability: String, at: Vector2) -> void:
	rec_event(["ability", slot, ability, at])
	super(slot, ability, at)


func crescendo_fx(e: Enemy) -> void:
	rec_event(["crescendo", e.id])
	super(e)


# A new game (or the host's restart) also ends the replay and forgets the recording.
func clear_world() -> void:
	stop_replay()
	rec_frames.clear()
	rec_events.clear()
	rec_time = 0.0
	rec_since = 0.0
	rec_closed = false
	super()


func start_replay() -> void:
	if replay_on or rec_frames.size() < 2:
		return
	replay_on = true
	live_enemies = enemies
	live_shots = shots
	for e in live_enemies:
		e.node.visible = false
	for s in live_shots:
		s.node.visible = false
	enemies = []
	shots = []
	replay_ghosts.clear()
	replay_past.clear()
	replay_speed = 1.0
	replay_paused = false
	replay_frame = -1
	replay_t = trouble_start()
	selected = null
	build_type = ""
	aiming = ""
	if replay_layer == null:
		replay_layer = Node2D.new()
		hud.get_parent().add_child(replay_layer)
		replay_layer.draw.connect(draw_on.bind(replay_layer, draw_replay_bar))
	replay_layer.visible = true
	show_replay_time(replay_t, true)
	play_sound("replay_start")


# Where the replay starts: 5 seconds before the monster count last climbed from
# under half the limit, where it started to go wrong (or the recording's start).
func trouble_start() -> float:
	var start: float = rec_frames[0][0]
	for i in range(rec_frames.size() - 1, -1, -1):
		var f: Array = rec_frames[i]
		if f[2] < f[3] * 0.5:
			start = f[0]
			break
	return maxf(start - 5.0, rec_frames[0][0])


# Back to the game's real monsters and shots (the stats screen).
func stop_replay() -> void:
	if not replay_on:
		return
	replay_on = false
	replay_drag = false
	var mine := enemies
	enemies = live_enemies
	for e in mine:
		if e.id < 0:
			e.node.queue_free()
		else:
			enemies.append(e)  # a real monster that came in from the host meanwhile
	for s in shots:
		s.node.queue_free()
	shots = live_shots
	for e in enemies:
		e.node.visible = true
	for s in shots:
		s.node.visible = true
	live_enemies = []
	live_shots = []
	replay_ghosts.clear()
	replay_past.clear()
	if replay_layer != null:
		replay_layer.visible = false


func replay_update(delta: float) -> void:
	# The game went on (a new game from the host): back to it
	if state == "playing":
		stop_replay()
		return
	var last: float = rec_frames[-1][0]
	var dt := 0.0 if replay_paused else delta * replay_speed
	replay_t = clampf(replay_t + dt, rec_frames[0][0], last)
	if replay_t >= last:
		replay_paused = true
	show_replay_time(replay_t, false)
	update_effects(dt)
	update_shots(dt)
	replay_layer.queue_redraw()


# The last frame at or before game time t.
func frame_at(t: float) -> int:
	var lo := 0
	var hi := rec_frames.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if rec_frames[mid][0] <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


# Puts the replay's monsters where they were at game time t (gliding between
# two frames). jump: skipped there (no shots or effects on the way, monsters
# that are gone just vanish instead of falling over).
func show_replay_time(t: float, jump: bool) -> void:
	var i := frame_at(t)
	var j := mini(i + 1, rec_frames.size() - 1)
	var f: Array = rec_frames[i]
	var g: Array = rec_frames[j]
	var a := 0.0 if i == j else clampf((t - f[0]) / (g[0] - f[0]), 0.0, 1.0)
	var natural := not jump and i >= replay_frame and i - replay_frame <= 20
	if natural:
		for k in range(replay_frame + 1, i + 1):
			play_events(rec_frames[k][5])
	else:
		for s in shots:
			s.node.queue_free()
		shots.clear()
	replay_frame = i
	apply_barracks_info(f[6])
	var next := {}
	var gd: PackedByteArray = g[4]
	for at in range(0, gd.size(), REPLAY_BYTES):
		next[gd.decode_u32(at)] = Vector2(gd.decode_u16(at + 4), gd.decode_u16(at + 6)) / 32.0
	var fd: PackedByteArray = f[4]
	var seen := {}
	for at in range(0, fd.size(), REPLAY_BYTES):
		var id := fd.decode_u32(at)
		seen[id] = true
		var p := Vector2(fd.decode_u16(at + 4), fd.decode_u16(at + 6)) / 32.0
		if next.has(id):
			p = p.lerp(next[id], a)
		var flags: int = fd[at + 10]
		var e: Enemy = replay_ghosts.get(id)
		if e == null:
			e = make_enemy(ENEMY_KINDS[flags & 3])
			e.id = -1 - id  # never mixed up with the host's monsters
			e.max_hp = 1.0
			apply_special_bits(e, fd[at + 11])
			if e.special == "splitling":
				e.radius *= 0.75
			e.node.position = to3d(p)
			replay_ghosts[id] = e
			enemies.append(e)
		e.pos = p
		e.net_pos = p
		e.hp = fd.decode_u16(at + 8) / 65535.0
		e.slow_time = 1.0 if flags & 128 else 0.0
		e.freeze_time = 1.0 if flags & 64 else 0.0
		e.shield = 1.0 if fd[at + 11] & 16 else 0.0
		e.poisoned = 1.0 if fd[at + 11] & 32 else 0.0
		if flags & 32:
			replay_past[e] = true
		else:
			replay_past.erase(e)
	for k in range(enemies.size() - 1, -1, -1):
		var e := enemies[k]
		var id := -1 - e.id
		if e.id < 0 and not seen.has(id):
			replay_ghosts.erase(id)
			replay_past.erase(e)
			enemies.remove_at(k)
			if natural and e.hp < 0.5:
				drop_corpse(e)
			else:
				e.node.queue_free()


func play_events(list: Array) -> void:
	for ev: Array in list:
		match ev[0]:
			"shot":
				var t: Tower = towers.get(ev[1])
				var target: Enemy = replay_ghosts.get(ev[2])
				if t != null and target != null:
					t.aim = (target.pos - t.pos).normalized()
					launch_shot(t, target, true)
			"bolt":
				add_bolt(ev[1])
			"boom":
				add_boom(ev[1], ev[2])
			"frost":
				add_frost_ring(ev[1], ev[2])
			"ability":
				show_ability(ev[1], ev[2], ev[3])
			"crescendo":
				# Only the look and sound (see crescendo_fx())
				var g: Enemy = replay_ghosts.get(ev[1])
				if g != null:
					crescendo_fx(g)


# The replay's keys: Space pause, Left / Right 5 seconds, F speed, click or
# drag the timeline, V or Esc back to the stats, R play again, Enter chat.
# WASD, the scroll wheel, middle drag, the minimap and H still move the camera.
func replay_input(event: InputEvent) -> void:
	if camera_input(event):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and minimap_map().has_point(ui_mouse()):
		minimap_dragging = true
		minimap_look(ui_mouse())
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_V:
				stop_replay()
			KEY_SPACE:
				if replay_t >= rec_frames[-1][0]:
					replay_t = trouble_start()
					show_replay_time(replay_t, true)
				replay_paused = not replay_paused
			KEY_LEFT:
				replay_jump(-5.0)
			KEY_RIGHT:
				replay_jump(5.0)
			KEY_F:
				replay_speed = REPLAY_SPEEDS[(REPLAY_SPEEDS.find(replay_speed) + 1) % REPLAY_SPEEDS.size()]
			KEY_R:
				stop_replay()
				act("restart", [])
			KEY_ENTER, KEY_KP_ENTER:
				open_chat()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var p := ui_mouse()
			replay_drag = event.pressed and REPLAY_BAR.grow(8).has_point(p)
			if replay_drag:
				replay_scrub(p.x)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(-1.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(1.0)
	elif event is InputEventMouseMotion and replay_drag:
		replay_scrub(ui_mouse().x)


func replay_jump(seconds: float) -> void:
	replay_t = clampf(replay_t + seconds, rec_frames[0][0], rec_frames[-1][0])
	show_replay_time(replay_t, true)


func replay_scrub(x: float) -> void:
	var k := clampf((x - REPLAY_BAR.position.x) / REPLAY_BAR.size.x, 0.0, 1.0)
	replay_t = lerpf(rec_frames[0][0], rec_frames[-1][0], k)
	show_replay_time(replay_t, true)


# What the timeline shows, for drawing it: [wave, alive, max alive, monsters
# that got past, seconds before the end].
func replay_info() -> Array:
	var f: Array = rec_frames[maxi(replay_frame, 0)]
	return [f[1], f[2], f[3], replay_past.size(), rec_frames[-1][0] - replay_t]

