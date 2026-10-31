extends "res://game_net.gd"
## The 2D overlay: side panel, health bars, lightning, menus and popups.

# Dark stone with gold edges
const UI_GOLD := Color(0.86, 0.68, 0.32)
const UI_GOLD_LIGHT := Color(1.0, 0.88, 0.55)
const UI_GOLD_DARK := Color(0.4, 0.28, 0.1)
const UI_TEXT := Color(0.95, 0.91, 0.82)
const UI_GREY := Color(0.72, 0.69, 0.63)
const UI_DIM := Color(0.55, 0.52, 0.47)

var title_font: Font  # big titles; the normal font unless a style says otherwise
var map_hud: Node2D  # 2D layer under the panel: health bars, lightning, area labels

# ---------------------------------------------------------------- 2D overlay

# Made right after the 3D world (see _ready).
func build_hud() -> void:
	title_font = make_title_font()
	# 2D layer for the panel, health bars and lightning
	var layer := CanvasLayer.new()
	add_child(layer)
	# Three layers: health bars and lightning at the bottom, then the panel's stone,
	# drawn only once since it never changes, then everything else on top
	map_hud = Node2D.new()
	layer.add_child(map_hud)
	map_hud.draw.connect(draw_on.bind(map_hud, draw_map_overlays))
	var stone := Node2D.new()
	layer.add_child(stone)
	stone.draw.connect(draw_on.bind(stone, ui_panel.bind(Rect2(PANEL_LEFT, 0, SCREEN_W - PANEL_LEFT, SCREEN_H))))
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
	# Sunken stone with a thin gold edge, like the buttons
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.06, 0.065)
	box.border_color = UI_GOLD_DARK
	box.set_border_width_all(1)
	box.content_margin_left = 8
	code_input.add_theme_stylebox_override("normal", box)
	var focus := box.duplicate()
	focus.border_color = UI_GOLD
	code_input.add_theme_stylebox_override("focus", focus)
	code_input.add_theme_color_override("font_color", UI_TEXT)
	code_input.add_theme_color_override("font_placeholder_color", UI_DIM)
	code_input.visible = false
	code_input.text_submitted.connect(func(_t: String) -> void: join_game())
	layer.add_child(code_input)


# Runs draw_func with the drawing helpers drawing on node instead of hud.
func draw_on(node: Node2D, draw_func: Callable) -> void:
	var top := hud
	hud = node
	draw_func.call()
	hud = top


# The map layer redraws every frame along with the 3D world.
func update_visuals(delta: float) -> void:
	super(delta)
	map_hud.queue_redraw()


func draw_hud() -> void:
	if not asks.is_empty() and state == "playing":
		draw_ask()
	draw_panel()
	if state != "playing":
		draw_end_screen()
	if menu_open:
		draw_menu()
	if update_dialog != "":
		draw_update_dialog()


# Health bars, lightning and area labels: under the side panel.
func draw_map_overlays() -> void:
	draw_health_bars()
	for fx in effects:
		if fx["kind"] == "bolt":
			var pts := PackedVector2Array()
			for p in fx["points"]:
				pts.append(camera.unproject_position(p))
			var a: float = fx["time"] / fx["max"]
			hud.draw_polyline(pts, Color(0.75, 0.5, 1.0, a * 0.5), 7.0)
			hud.draw_polyline(pts, Color(0.95, 0.9, 1.0, a), 2.5)
	if showing_areas():
		draw_area_labels()


func draw_area_labels() -> void:
	for slot in MAX_PLAYERS:
		if players[slot] == null:
			continue
		var p := camera.unproject_position(area_planes[slot].position)
		if slot == local_slot:
			outlined(p, "Your area", 24, UI_TEXT)
		else:
			outlined(p, "%s's area" % PLAYER_NAMES[slot], 24, PLAYER_COLORS[slot])
			outlined(p + Vector2(0, 24), "%s must say yes" % PLAYER_NAMES[slot], 15, UI_GREY)


# Centered text with a dark outline, readable on top of the map.
func outlined(center: Vector2, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := center - Vector2(w / 2.0, 0)
	hud.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.8))
	hud.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# Another player asks to build in our area: Yes or No.
func draw_ask() -> void:
	var ask: Array = asks[0]
	var from: int = ask[1]
	var cell: Vector2i = ask[3]
	var r := ASK_RECT
	ui_box(r)
	# A strip in the asking player's color
	hud.draw_rect(Rect2(r.position.x + 10, r.position.y + 40, r.size.x - 20, 2), PLAYER_COLORS[from] * Color(1, 1, 1, 0.7))
	var line := "%s wants to build a %s tower in your area" % [PLAYER_NAMES[from], str(ask[2]).capitalize()]
	if asks.size() > 1:
		line += "  (+%d more)" % (asks.size() - 1)
	text(r.position + Vector2(20, 32), line, 17, PLAYER_COLORS[from])
	button(ASK_YES_RECT, "Yes (Y)", true, true)
	button(ASK_NO_RECT, "No (N)")
	# Point at the spot with a pulsing ring
	var spot := camera.unproject_position(Vector3(cell.x + 0.5, 0.1, cell.y + 0.5))
	hud.draw_arc(spot, 16.0 + sin(time * 6.0) * 4.0, 0, TAU, 32, PLAYER_COLORS[from], 3.0)


func draw_update_dialog() -> void:
	var d := DIALOG_RECT
	var left := d.position.x + 30
	hud.draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.6))
	ui_box(d)
	if update_dialog.begins_with("unpack"):
		draw_unpack_dialog()
		return
	ui_title(Rect2(d.position.x, d.position.y, d.size.x, 66), Vector2(left, d.position.y + 46), "New version %s is out!" % update_version, 28)
	text(Vector2(left, d.position.y + 90), "You have v%s" % version, 15, UI_DIM)
	match update_dialog:
		"ask":
			text(Vector2(left, d.position.y + 126), "What's new", 18, UI_GOLD_LIGHT)
			var notes := update_notes if update_notes != "" else "No details for this update."
			hud.draw_multiline_string(font, Vector2(left, d.position.y + 154), notes, HORIZONTAL_ALIGNMENT_LEFT, d.size.x - 60, 16, 9, UI_TEXT)
			text(Vector2(left, DIALOG_YES_RECT.position.y - 20), "Do you want to update now?", 18, UI_TEXT)
			button(DIALOG_YES_RECT, "Yes, update", true, true)
			button(DIALOG_NO_RECT, "No, not now")
		"downloading":
			var done := 0.0
			if update_http != null and update_http.get_body_size() > 0:
				done = float(update_http.get_downloaded_bytes()) / update_http.get_body_size()
			text(Vector2(left, d.position.y + 160), "Downloading update... %d%%" % int(done * 100), 20, UI_TEXT)
			ui_bar(Rect2(left, d.position.y + 185, d.size.x - 60, 20), done, Color(0.3, 0.75, 0.4))
			text(Vector2(left, d.position.y + 240), "The game will restart by itself when it's done.", 16, UI_GREY)
		"failed":
			text(Vector2(left, d.position.y + 150), "The update didn't work.", 20, Color(1, 0.45, 0.45))
			hud.draw_multiline_string(font, Vector2(left, d.position.y + 185), update_error, HORIZONTAL_ALIGNMENT_LEFT, d.size.x - 60, 16, 4, UI_TEXT)
			text(Vector2(left, d.position.y + 260), "You can download it from GitHub instead.", 16, UI_GREY)
			button(DIALOG_YES_RECT, "Open download page", true, true)
			button(DIALOG_NO_RECT, "Close")


# First run of a fresh download: the game is about to unpack itself.
func draw_unpack_dialog() -> void:
	var d := DIALOG_RECT
	var left := d.position.x + 30
	var width := d.size.x - 60
	ui_title(Rect2(d.position.x, d.position.y, d.size.x, 66), Vector2(left, d.position.y + 46), "Heads up: the game will unpack itself", 26)
	if update_dialog == "unpack_failed":
		text(Vector2(left, d.position.y + 110), "Unpacking didn't work.", 20, Color(1, 0.45, 0.45))
		hud.draw_multiline_string(font, Vector2(left, d.position.y + 145), update_error + "\n\nYou can still play from this file.", HORIZONTAL_ALIGNMENT_LEFT, width, 16, 5, UI_TEXT)
		button(DIALOG_NO_RECT, "Play anyway")
		return
	var info := "This is the first time the game runs from this download. It will now unpack itself into this folder:"
	hud.draw_multiline_string(font, Vector2(left, d.position.y + 100), info, HORIZONTAL_ALIGNMENT_LEFT, width, 17, 2, UI_TEXT)
	text(Vector2(left, d.position.y + 175), fit_path(unpack_destination(), width, 16), 16, Color(0.6, 0.85, 1.0))
	button(CHOOSE_FOLDER_RECT, "Choose another folder...")
	var files := game_file_name(version)
	var after := "It gets the game engine (%s.exe) and the game itself (%s.pck). Start the game from there afterwards. This downloaded file is deleted when it's done." % [files, files]
	hud.draw_multiline_string(font, Vector2(left, d.position.y + 296), after, HORIZONTAL_ALIGNMENT_LEFT, width, 15, 3, UI_GREY)
	button(DIALOG_YES_RECT, "OK, unpack", true, true)
	button(DIALOG_NO_RECT, "Not now")


# A folder path that fits on one line: "C:\…\Downloads\Gettic's first TD", keeping
# as many of the last folders as fit.
func fit_path(path: String, width: float, size: int) -> String:
	var parts := path.replace("/", "\\").split("\\")
	var fits := func(s: String) -> bool: return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width
	if fits.call("\\".join(parts)) or parts.size() < 3:
		return "\\".join(parts)
	var tail: String = parts[parts.size() - 1]
	for i in range(parts.size() - 2, 0, -1):
		var longer: String = parts[i] + "\\" + tail
		if not fits.call(parts[0] + "\\…\\" + longer):
			break
		tail = longer
	return parts[0] + "\\…\\" + tail


func draw_health_bars() -> void:
	for e in enemies:
		var r := e.radius / CELL
		var p := camera.unproject_position(e.node.position + Vector3(0, r + 0.25, 0))
		var w := e.radius * 2.4
		var bar := Vector2(p.x - w / 2.0, p.y)
		# Black edge so the bar reads on grass and path alike
		hud.draw_rect(Rect2(bar - Vector2(1, 1), Vector2(w + 2, 6)), Color(0, 0, 0, 0.85))
		hud.draw_rect(Rect2(bar, Vector2(w, 4)), Color(0.3, 0.04, 0.02))
		hud.draw_rect(Rect2(bar, Vector2(w * e.hp / e.max_hp, 4)), Color(0.2, 0.85, 0.2))


func text(pos: Vector2, s: String, size := 16, col := Color.WHITE) -> void:
	hud.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func button(r: Rect2, label: String, enabled := true, active := false) -> void:
	ui_button_bg(r, enabled, active)
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var col := UI_TEXT if enabled else UI_DIM
	if active and enabled:
		col = UI_GOLD_LIGHT
	var pos := r.position + Vector2((r.size.x - size.x) / 2.0, r.size.y / 2.0 + 6.0)
	hud.draw_string(font, pos + Vector2(0, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, 0.7))
	text(pos, label, 16, col)


# A round gem in the tower's color, set in gold.
func gem(c: Vector2, radius: float, col: Color) -> void:
	hud.draw_circle(c, radius + 3.0, UI_GOLD_DARK)
	hud.draw_circle(c, radius + 2.0, UI_GOLD)
	hud.draw_circle(c, radius, col.darkened(0.45))
	hud.draw_circle(c + Vector2(0, 1.5), radius - 2.0, col)
	hud.draw_circle(c - Vector2(radius * 0.35, radius * 0.35), radius * 0.28, Color(1, 1, 1, 0.55))


func draw_panel() -> void:
	# The panel's stone background is on its own layer (see build_hud)
	ui_title(Rect2(PANEL_LEFT, 0, SCREEN_W - PANEL_LEFT, 46), Vector2(PANEL_X, 36), "WAVE %d / %d" % [wave, MAX_WAVE], 26)
	text(Vector2(PANEL_X + 250, 34), "v" + version, 13, ui_title_dim())
	if is_debug_game():
		text(Vector2(PANEL_X + 196, 34), "DEBUG", 13, Color(1.0, 0.45, 0.4))
	# How close you are to losing: green when few monsters are alive, red near the limit
	var alive := alive_count()
	var danger := clampf(float(alive) / max_alive(), 0.0, 1.0)
	var danger_col := Color(0.4, 0.9, 0.4).lerp(Color(1, 0.3, 0.3), danger)
	text(Vector2(PANEL_X, 66), "Alive: %d / %d" % [alive, max_alive()], 20, danger_col)
	text(Vector2(PANEL_X + 170, 66), "Gold: %d" % gold, 20, Color(1, 0.85, 0.3))
	ui_bar(Rect2(PANEL_X, 74, 288, 6), danger, danger_col)
	var next_text: String
	if wave == 0:
		next_text = "First wave: %s" % kind_for_wave(1).capitalize()
	elif wave < MAX_WAVE:
		next_text = "Next wave: %s in %ds" % [kind_for_wave(wave + 1).capitalize(), ceili(next_wave_timer)]
	else:
		next_text = "Last wave! Kill them all"
	text(Vector2(PANEL_X, 104), next_text, 16, UI_GREY)
	if net_mode == "host" or net_mode == "client":
		# A dot per player in their color; yours has a ring
		var x := PANEL_X
		for slot in MAX_PLAYERS:
			if players[slot] == null:
				continue
			hud.draw_circle(Vector2(x + 6, 120), 6, PLAYER_COLORS[slot])
			if slot == local_slot:
				hud.draw_arc(Vector2(x + 6, 120), 9, 0, TAU, 20, UI_GOLD_LIGHT, 1.5)
			x += 22
		text(Vector2(x + 4, 125), "You: %s" % PLAYER_NAMES[local_slot], 14, PLAYER_COLORS[local_slot])
	else:
		text(Vector2(PANEL_X, 136), "Build (keys 1-4)", 14, UI_DIM)

	for i in TOWER_TYPES.size():
		var type: String = TOWER_TYPES[i]
		var data: Dictionary = TOWERS[type]
		var r := tower_button_rect(i)
		var affordable: bool = gold >= data["cost"][0]
		ui_button_bg(r, true, build_type == type)
		gem(r.position + Vector2(28, 28), 12.0, data["color"])
		var name_col := UI_TEXT if affordable else UI_DIM
		text(r.position + Vector2(52, 24), "%d. %s" % [i + 1, data["name"]], 18, name_col)
		text(r.position + Vector2(220, 24), "%dg" % data["cost"][0], 18, Color(1, 0.85, 0.3) if affordable else Color(0.6, 0.4, 0.3))
		text(r.position + Vector2(52, 46), data["desc"], 14, UI_GREY)

	if selected != null:
		var data: Dictionary = TOWERS[selected.type]
		var lv := selected.level
		text(Vector2(PANEL_X, 428), "%s  -  Level %d" % [data["name"], lv + 1], 20, data["color"])
		text(Vector2(PANEL_X, 450), "Damage %d   Range %d   Speed %.2fs" % [data["damage"][lv], data["range"][lv], data["cooldown"][lv]], 14, UI_TEXT)
		if selected.owner != local_slot:
			text(Vector2(PANEL_X, 470), "Built by %s" % PLAYER_NAMES[selected.owner], 14, PLAYER_COLORS[selected.owner])
		elif lv < 3:
			text(Vector2(PANEL_X, 470), "Next: Damage %d   Range %d" % [data["damage"][lv + 1], data["range"][lv + 1]], 14, Color(0.6, 0.9, 0.6))
			var cost: int = data["cost"][lv + 1]
			button(UPGRADE_RECT, "Upgrade %dg (U)" % cost, gold >= cost)
		else:
			button(UPGRADE_RECT, "Max level", false)
		if selected.owner == local_slot:
			button(SELL_RECT, "Sell %dg (X)" % int(selected.spent * 0.7))
	else:
		text(Vector2(PANEL_X, 440), "Click a tower to upgrade or sell it.", 14, UI_DIM)

	if update_version != "":
		button(UPDATE_RECT, "New version %s - Update" % update_version, true, true)

	if message_time > 0.0:
		text(Vector2(PANEL_X, 592), message, 16, Color(1, 1, 0.6, minf(message_time, 1.0)))

	var wave_label: String
	if wave == 0:
		wave_label = "Start (SPACE)"
	elif wave < MAX_WAVE and monsters_left_to_spawn() > 0:
		wave_label = "Spawning... (%d left)" % monsters_left_to_spawn()
	elif wave < MAX_WAVE and player_count() > 1:
		# A vote: the button shows how many agree and how many are needed
		var votes := "%d/%d" % [wave_votes.size(), votes_needed()]
		if local_slot in wave_votes:
			wave_label = "Voted %s (SPACE: undo)" % votes
		else:
			wave_label = "Vote +%dg %s (SPACE)" % [int(maxf(next_wave_timer, 0.0)), votes]
	elif wave < MAX_WAVE:
		wave_label = "Send now +%dg (SPACE)" % int(maxf(next_wave_timer, 0.0))
	else:
		wave_label = "No more waves"
	button(WAVE_RECT, wave_label, wave < MAX_WAVE and state == "playing" and monsters_left_to_spawn() == 0)
	button(SPEED_RECT, "x%d (F)" % game_speed, net_mode != "client", game_speed > 1)
	ui_divider(PANEL_X, PANEL_X + 288, 664)
	text(Vector2(PANEL_X, 682), "WASD: move camera   Scroll: zoom", 13, UI_DIM)
	text(Vector2(PANEL_X, 700), "Right-click: cancel   Esc: menu & multiplayer", 13, UI_DIM)


func centered(y: float, s: String, size: int, col := Color.WHITE) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2((PANEL_LEFT - w) / 2.0, y), s, size, col)


# The Esc menu: pause, and host or join a multiplayer game.
func draw_menu() -> void:
	var m := MENU_RECT
	var left := HOST_RECT.position.x
	var width := HOST_RECT.size.x
	hud.draw_rect(Rect2(0, 0, PANEL_LEFT, SCREEN_H), Color(0, 0, 0, 0.5))
	ui_box(m)
	var title := "PAUSED" if net_mode == "" else "MENU"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	ui_title(Rect2(m.position.x, m.position.y, m.size.x, 66), Vector2((PANEL_LEFT - tw) / 2.0, m.position.y + 50), title, 40)
	var sub := "The game is paused." if net_mode == "" else "The game keeps running while this menu is open."
	centered(m.position.y + 88, sub, 15, UI_GREY)
	button(GRAPHICS_RECT, "Graphics: %s" % ("High" if graphics_high else "Low"), true, graphics_high)
	ui_heading(Vector2(left, 180), "MULTIPLAYER", width)
	var grey := UI_GREY
	var gold_col := Color(1, 0.85, 0.3)
	match net_mode:
		"":
			button(HOST_RECT, "Host a game and get an invite code", true, true)
			text(Vector2(left, 280), "Or join a friend's game with their invite code:", 15, grey)
			button(JOIN_BUTTON_RECT, "Join")
			hud.draw_multiline_string(font, Vector2(left, 360), net_status, HORIZONTAL_ALIGNMENT_LEFT, width, 15, 3, Color(1, 0.75, 0.5))
			if relay_url != "":
				draw_public_games()
		"searching", "connecting":
			button(HOST_RECT, "Cancel")
			hud.draw_multiline_string(font, Vector2(left, 270), net_status, HORIZONTAL_ALIGNMENT_LEFT, width, 16, 3, grey)
		"host":
			text(Vector2(left, 218), "Invite code:", 15, grey)
			if invite_code != "":
				text(Vector2(left, 262), invite_code, 40, gold_col)
				button(COPY_RECT, "Copy")
			else:
				text(Vector2(left, 256), "Getting your invite code...", 18, grey)
			hud.draw_multiline_string(font, Vector2(left, 296), net_status, HORIZONTAL_ALIGNMENT_LEFT, width, 14, 3, grey)
			if relay != null and invite_code != "":
				var label := "Public game: ON  (anyone can find it in the list)" if public_game else "Public game: OFF  (only friends with the code)"
				button(PUBLIC_RECT, label, true, public_game)
			draw_player_list(Vector2(left, 412))
			button(STOP_RECT, "Stop hosting")
		"client":
			text(Vector2(left, 218), "You are playing as %s." % PLAYER_NAMES[local_slot], 16, PLAYER_COLORS[local_slot])
			draw_player_list(Vector2(left, 250))
			button(STOP_RECT, "Leave the game")
	button(RESUME_RECT, "Resume (Esc)")


func game_row_rect(i: int) -> Rect2:
	return Rect2(HOST_RECT.position.x, 444 + i * 38, HOST_RECT.size.x, 34)


func draw_public_games() -> void:
	var left := HOST_RECT.position.x
	ui_heading(Vector2(left, 428), "PUBLIC GAMES", REFRESH_RECT.position.x - left - 10)
	button(REFRESH_RECT, "Refresh", games_http == null)
	if public_games.is_empty():
		text(Vector2(left, 470), games_status, 15, UI_GREY)
	for i in mini(public_games.size(), GAME_ROWS):
		var g: Dictionary = public_games[i]
		button(game_row_rect(i), "Join  %s      %d / %d players      wave %d" % [g.code, int(g.players), MAX_PLAYERS, int(g.wave)])


func draw_player_list(pos: Vector2) -> void:
	text(pos, "Players (%d / %d):" % [player_count(), MAX_PLAYERS], 15, UI_GREY)
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
		text(Vector2(pos.x + 22, y), who, 15, UI_TEXT)
		y += 20


# A gold section heading with a fading gold line after it.
func ui_heading(pos: Vector2, s: String, width: float) -> void:
	text(pos, s, 16, Color(1, 0.85, 0.3))
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	ui_divider(pos.x + w + 10, pos.x + width, pos.y - 6)


# A thin gold line that fades out at both ends.
func ui_divider(x0: float, x1: float, y: float) -> void:
	if x1 - x0 < 20:
		return
	var mid := (x0 + x1) / 2.0
	var clear := Color(UI_GOLD, 0.0)
	hud.draw_polyline_colors(PackedVector2Array([Vector2(x0, y), Vector2(mid, y), Vector2(x1, y)]), PackedColorArray([clear, UI_GOLD, clear]), 1.0)
	hud.draw_polyline_colors(PackedVector2Array([Vector2(x0, y + 1), Vector2(mid, y + 1), Vector2(x1, y + 1)]), PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)]), 1.0)


# A rect filled top to bottom with two colors.
func vgrad(r: Rect2, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	hud.draw_primitive(pts, PackedColorArray([top, top, bottom, bottom]), PackedVector2Array())


# Stone blocks: each block a slightly different shade, with carved seams.
func stone_blocks(r: Rect2, base: Color, block_h: float, block_w: float) -> void:
	hud.draw_rect(r, base)
	var rows := ceili(r.size.y / block_h)
	for row in rows:
		var y0 := r.position.y + row * block_h
		var y1 := minf(y0 + block_h, r.end.y)
		var shift := block_w * 0.5 if row % 2 == 1 else 0.0
		var x := r.position.x - shift
		var col := 0
		while x < r.end.x:
			var x0 := maxf(x, r.position.x)
			var x1 := minf(x + block_w, r.end.x)
			# Fixed shade per block, so it doesn't flicker
			var shade := (((row * 7 + col * 13) % 5) - 2) * 0.008
			hud.draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), Color(base.r + shade, base.g + shade, base.b + shade))
			if x > r.position.x:
				hud.draw_line(Vector2(x0, y0 + 1), Vector2(x0, y1 - 1), Color(0, 0, 0, 0.45), 1.0)
				hud.draw_line(Vector2(x0 + 1, y0 + 1), Vector2(x0 + 1, y1 - 1), Color(1, 1, 1, 0.04), 1.0)
			x += block_w
			col += 1
		if row > 0:
			hud.draw_line(Vector2(r.position.x, y0), Vector2(r.end.x, y0), Color(0, 0, 0, 0.5), 1.0)
			hud.draw_line(Vector2(r.position.x, y0 + 1), Vector2(r.end.x, y0 + 1), Color(1, 1, 1, 0.05), 1.0)


# A frame with light top-left and dark bottom-right sides, like raised (or sunken) metal.
func bevel(r: Rect2, w: float, light: Color, dark: Color) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	var i := Vector2(w, w)
	var j := Vector2(-w, w)
	quad(PackedVector2Array([a, b, b + j, a + i]), light)
	quad(PackedVector2Array([a, a + i, d - j, d]), light.lerp(dark, 0.3))
	quad(PackedVector2Array([d, d - j, c - i, c]), dark)
	quad(PackedVector2Array([b, c, c - i, b + j]), dark.lerp(light, 0.3))


# A four-cornered shape in one color (draw_primitive is much faster than draw_colored_polygon).
func quad(pts: PackedVector2Array, col: Color) -> void:
	hud.draw_primitive(pts, PackedColorArray([col, col, col, col]), PackedVector2Array())


# Soft shadow on the inside edges of a rect, so it looks set into the stone.
func inner_shadow(r: Rect2, size: int, strength: float) -> void:
	for k in size:
		var a := strength * (1.0 - float(k) / size)
		var q := r.grow(-k)
		hud.draw_rect(Rect2(q.position, Vector2(q.size.x, 1)), Color(0, 0, 0, a))
		hud.draw_rect(Rect2(q.position, Vector2(1, q.size.y)), Color(0, 0, 0, a))
		hud.draw_rect(Rect2(q.position.x, q.end.y - 1, q.size.x, 1), Color(0, 0, 0, a * 0.5))
		hud.draw_rect(Rect2(q.end.x - 1, q.position.y, 1, q.size.y), Color(0, 0, 0, a * 0.5))


# ---- Style B: carved stone blocks, beveled gold frame, inner shadow

const UI_STONE := Color(0.15, 0.145, 0.14)


func make_title_font() -> Font:
	return font


func ui_title_dim() -> Color:
	return UI_DIM


func ui_panel(r: Rect2) -> void:
	stone_blocks(r, UI_STONE, 36, 96)
	# Darker toward the bottom
	vgrad(r, Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.35))
	inner_shadow(Rect2(r.position.x + 6, r.position.y, r.size.x - 6, r.size.y), 10, 0.35)
	# Beveled gold strip between the map and the panel
	hud.draw_rect(Rect2(r.position.x - 1, r.position.y, 1, r.size.y), Color(0, 0, 0, 0.8))
	bevel(Rect2(r.position.x, r.position.y - 6, 6, r.size.y + 12), 3, UI_GOLD_LIGHT, UI_GOLD_DARK)


func ui_box(r: Rect2) -> void:
	hud.draw_rect(r.grow(4), Color(0, 0, 0, 0.35))
	stone_blocks(r, UI_STONE, 36, 96)
	vgrad(r, Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.3))
	inner_shadow(r.grow(-5), 12, 0.3)
	hud.draw_rect(r.grow(1), Color(0, 0, 0, 0.9), false, 1.0)
	bevel(r, 5, UI_GOLD_LIGHT, UI_GOLD_DARK)
	# Thin dark line inside the gold, like a groove
	hud.draw_rect(r.grow(-5), Color(0, 0, 0, 0.6), false, 1.0)


func ui_title(bar: Rect2, pos: Vector2, s: String, size: int) -> void:
	# Carved into the stone: dark above, light below
	hud.draw_string(title_font, pos + Vector2(0, -1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8))
	hud.draw_string(title_font, pos + Vector2(0, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.3, 0.2, 0.05, 0.9))
	hud.draw_string(title_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 0.85, 0.3))
	ui_divider(bar.position.x + 14, bar.end.x - 14, bar.end.y)


func ui_button_bg(r: Rect2, enabled: bool, active: bool) -> void:
	var top := Color(0.25, 0.24, 0.22)
	var bottom := Color(0.13, 0.125, 0.12)
	var light := Color(0.78, 0.62, 0.32)
	var dark := Color(0.32, 0.22, 0.09)
	if active and enabled:
		top = Color(0.42, 0.31, 0.13)
		bottom = Color(0.2, 0.13, 0.05)
		light = UI_GOLD_LIGHT
		dark = Color(0.5, 0.36, 0.13)
	elif not enabled:
		top = Color(0.11, 0.105, 0.1)
		bottom = Color(0.08, 0.075, 0.07)
		light = Color(0.32, 0.29, 0.24)
		dark = Color(0.16, 0.14, 0.11)
	hud.draw_rect(r.grow(1), Color(0, 0, 0, 0.7), false, 1.0)
	vgrad(r, top, bottom)
	bevel(r, 2, light, dark)


func ui_bar(r: Rect2, frac: float, col: Color) -> void:
	bevel(r.grow(2), 2, UI_GOLD_DARK, UI_GOLD)
	hud.draw_rect(r, Color(0.03, 0.03, 0.035))
	var f := Rect2(r.position, Vector2(r.size.x * frac, r.size.y))
	vgrad(f, col.lightened(0.25), col.darkened(0.35))
	inner_shadow(r, 2, 0.5)


func toggle_menu() -> void:
	menu_open = not menu_open
	build_type = ""
	games_timer = 0.0  # fresh list of public games when the menu opens
	if not menu_open:
		code_input.release_focus()


func menu_click(p: Vector2) -> void:
	if RESUME_RECT.has_point(p):
		toggle_menu()
		return
	if GRAPHICS_RECT.has_point(p):
		graphics_high = not graphics_high
		apply_graphics()
		save_settings()
		return
	match net_mode:
		"":
			if HOST_RECT.has_point(p):
				host_game()
			elif JOIN_BUTTON_RECT.has_point(p):
				join_game()
			elif relay_url != "" and REFRESH_RECT.has_point(p):
				refresh_games()
			elif relay_url != "":
				for i in mini(public_games.size(), GAME_ROWS):
					if game_row_rect(i).has_point(p):
						code_input.text = public_games[i].code
						join_game()
		"searching", "connecting":
			if HOST_RECT.has_point(p):
				close_search()
				close_connection()
				net_mode = ""
				net_status = ""
		"host":
			if COPY_RECT.has_point(p) and invite_code != "":
				DisplayServer.clipboard_set(invite_code)
				flash("Invite code copied")
			elif relay != null and invite_code != "" and PUBLIC_RECT.has_point(p):
				public_game = not public_game
				game_info_timer = 0.0
			elif STOP_RECT.has_point(p):
				stop_hosting()
		"client":
			if STOP_RECT.has_point(p):
				leave_game("You left the game.")


func draw_end_screen() -> void:
	hud.draw_rect(Rect2(0, 0, PANEL_LEFT, SCREEN_H), Color(0, 0, 0, 0.6))
	var title := "VICTORY!" if state == "won" else "GAME OVER"
	var sub := "You survived all %d waves." % MAX_WAVE if state == "won" else "Too many monsters! You reached wave %d." % wave
	var size := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64)
	var pos := Vector2((PANEL_LEFT - size.x) / 2.0, 320)
	hud.draw_string_outline(title_font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, 6, Color(0, 0, 0, 0.8))
	hud.draw_string(title_font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1, 0.85, 0.3) if state == "won" else Color(1, 0.35, 0.35))
	size = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	text(Vector2((PANEL_LEFT - size.x) / 2.0, 370), sub, 22, UI_TEXT)
	size = font.get_string_size("Press R to play again", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	text(Vector2((PANEL_LEFT - size.x) / 2.0, 410), "Press R to play again", 18, UI_GREY)
