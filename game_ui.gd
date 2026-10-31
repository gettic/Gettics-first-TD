extends "res://game_net.gd"
## The 2D overlay: bottom console, health bars, lightning, menus and popups.

# Dark stone with gold edges
const UI_GOLD := Color(0.86, 0.68, 0.32)
const UI_GOLD_LIGHT := Color(1.0, 0.88, 0.55)
const UI_GOLD_DARK := Color(0.4, 0.28, 0.1)
const UI_TEXT := Color(0.95, 0.91, 0.82)
const UI_GREY := Color(0.72, 0.69, 0.63)
const UI_DIM := Color(0.55, 0.52, 0.47)

var title_font: Font  # big titles; the normal font unless a style says otherwise
var map_hud: Node2D  # 2D layer under the console: health bars, lightning, area labels
var console_layer: Node2D  # the console's stone, drawn once (and again when the map changes)
var portrait_view: SubViewport  # a close-up of the selected tower, shown in the console
var portrait_cam: Camera3D

# ---------------------------------------------------------------- 2D overlay

# Made right after the 3D world (see _ready).
func build_hud() -> void:
	title_font = make_title_font()
	# 2D layer for the console, health bars and lightning
	var layer := CanvasLayer.new()
	add_child(layer)
	# Three layers: health bars and lightning at the bottom, then the console's stone,
	# drawn only once since it never changes, then everything else on top
	map_hud = Node2D.new()
	layer.add_child(map_hud)
	map_hud.draw.connect(draw_on.bind(map_hud, draw_map_overlays))
	console_layer = Node2D.new()
	layer.add_child(console_layer)
	console_layer.draw.connect(draw_on.bind(console_layer, ui_console))
	# The portrait: a second small camera in the same world, only drawn while a tower is selected
	portrait_view = SubViewport.new()
	portrait_view.size = Vector2i(PORTRAIT_RECT.size)
	portrait_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(portrait_view)
	portrait_cam = Camera3D.new()
	portrait_cam.fov = 30.0
	portrait_view.add_child(portrait_cam)
	hud = Node2D.new()
	layer.add_child(hud)
	hud.draw.connect(draw_hud)

	# Text boxes: the invite code and the player's name in the Esc menu, and the chat
	code_input = text_box(layer, JOIN_INPUT_RECT, "Invite code", 40, 18)
	code_input.text_submitted.connect(func(_t: String) -> void: join_game())
	name_input = text_box(layer, NAME_INPUT_RECT, "", NAME_MAX, 17)
	name_input.text_submitted.connect(func(_t: String) -> void: name_input.release_focus())
	name_input.focus_exited.connect(save_name)
	load_name()
	# Chat: Enter opens this box, Enter sends, Esc cancels
	chat_input = text_box(layer, CHAT_INPUT_RECT, "Say something to everyone   (Enter: send, Esc: cancel)", CHAT_MAX, 15)
	var see_through: StyleBoxFlat = chat_input.get_theme_stylebox("focus").duplicate()
	see_through.bg_color = Color(0.03, 0.03, 0.035, 0.75)
	chat_input.add_theme_stylebox_override("normal", see_through)
	chat_input.add_theme_stylebox_override("focus", see_through)
	chat_input.text_submitted.connect(func(t: String) -> void:
		send_chat(t)
		close_chat())
	chat_input.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			close_chat()
			chat_input.accept_event())
	chat_input.focus_exited.connect(close_chat)


# A hidden text box: sunken stone with a thin gold edge, like the buttons.
func text_box(layer: CanvasLayer, r: Rect2, placeholder: String, most: int, size: int) -> LineEdit:
	var input := LineEdit.new()
	input.position = r.position
	input.size = r.size
	input.placeholder_text = placeholder
	input.max_length = most
	input.add_theme_font_size_override("font_size", size)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.06, 0.065)
	box.border_color = UI_GOLD_DARK
	box.set_border_width_all(1)
	box.content_margin_left = 8
	input.add_theme_stylebox_override("normal", box)
	var focus := box.duplicate()
	focus.border_color = UI_GOLD
	input.add_theme_stylebox_override("focus", focus)
	input.add_theme_color_override("font_color", UI_TEXT)
	input.add_theme_color_override("font_placeholder_color", UI_DIM)
	input.visible = false
	layer.add_child(input)
	return input


func open_chat() -> void:
	chat_input.visible = true
	chat_input.grab_focus()


func close_chat() -> void:
	chat_input.text = ""
	chat_input.visible = false
	chat_input.release_focus()


func chatting() -> bool:
	return chat_input.visible


# The small map's ground is on the console's layer, so that's drawn again too.
func build_map() -> void:
	super()
	if console_layer != null:
		console_layer.queue_redraw()


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
	if selected == null:
		portrait_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	portrait_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# From the front and a little above, like the main camera but close
	var p := selected.node.position
	portrait_cam.position = p + Vector3(0, 2.2, 3.4)
	portrait_cam.look_at(p + Vector3(0, 0.75, 0))


func draw_hud() -> void:
	draw_panel()
	if state != "playing":
		draw_end_screen()
	draw_chat()
	if menu_open:
		draw_menu()
	if update_dialog != "":
		draw_update_dialog()


# The last chat lines, just above the minimap like in Warcraft III: "Name: text"
# with the name in the player's color. Each line fades out after CHAT_SHOW
# seconds; while typing, the last lines all show.
func draw_chat() -> void:
	var size := 15
	var width := CHAT_INPUT_RECT.size.x
	var now := Time.get_ticks_msec() / 1000.0
	var typing := chatting()
	var y := CHAT_INPUT_RECT.position.y - 8.0 if typing else CHAT_INPUT_RECT.end.y - 8.0
	var shown := 0
	for i in range(chat_log.size() - 1, -1, -1):
		var line: Array = chat_log[i]
		var alpha := 1.0 if typing else clampf(CHAT_SHOW - (now - line[3]), 0.0, 1.0)
		if alpha <= 0.0:
			break
		var slot: int = line[0]
		var who := "" if slot < 0 else str(line[1]) + ": "
		var who_w := font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var rows := wrap_words(str(line[2]), width - who_w, width, size)
		var col := Color(UI_GOLD_LIGHT, alpha) if slot < 0 else Color(UI_TEXT, alpha)
		for r in range(rows.size() - 1, -1, -1):
			if shown >= CHAT_LINES:
				return
			var x := CHAT_INPUT_RECT.position.x + 4.0
			if r == 0 and who != "":
				chat_text(Vector2(x, y), who, size, Color(PLAYER_COLORS[slot], alpha))
				x += who_w
			chat_text(Vector2(x, y), rows[r], size, col)
			y -= size + 4.0
			shown += 1


func chat_text(pos: Vector2, s: String, size: int, col: Color) -> void:
	hud.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85 * col.a))
	hud.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# Splits text into lines that fit: the first line is first_width wide, the rest width.
func wrap_words(s: String, first_width: float, width: float, size: int) -> PackedStringArray:
	var rows := PackedStringArray()
	var row := ""
	var room := first_width
	for word in s.split(" ", false):
		var next := word if row == "" else row + " " + word
		if row != "" and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
			rows.append(row)
			room = width
			next = word
		# A word too long for a whole line is cut
		while font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room and next.length() > 1:
			var cut := next.length() - 1
			while cut > 1 and font.get_string_size(next.left(cut), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
				cut -= 1
			rows.append(next.left(cut))
			room = width
			next = next.substr(cut)
		row = next
	if row != "":
		rows.append(row)
	return rows


# Health bars, lightning and area labels: under the console.
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
		if slot >= area_centers.size() or area_centers[slot] == null:
			continue
		var p := camera.unproject_position(area_centers[slot])
		if slot == local_slot:
			outlined(p, "Your area", 24, UI_TEXT)
		else:
			outlined(p, "%s's area" % name_of(slot), 24, UI_TEXT)
			outlined(p + Vector2(0, 24), "%s must say yes" % name_of(slot), 15, UI_GREY)


# Centered text with a dark outline, readable on top of the map.
func outlined(center: Vector2, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := center - Vector2(w / 2.0, 0)
	hud.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.8 * col.a))
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
	var line := "%s wants to build a %s tower in your area" % [name_of(from), str(ask[2]).capitalize()]
	if asks.size() > 1:
		line += "  (+%d more)" % (asks.size() - 1)
	text(r.position + Vector2(20, 32), line, 17, PLAYER_COLORS[from])
	text(r.position + Vector2(20, 68), "The spot is marked with a ring on the map.", 14, UI_GREY)
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
	# The console's stone is on its own layer (see build_hud)
	draw_top_bar()
	draw_minimap()
	draw_wave_info()
	# Another player's build request takes the middle until it's answered
	if not asks.is_empty() and state == "playing":
		draw_ask()
	elif selected != null:
		draw_selected()
	else:
		draw_build_list()
	draw_command_card()
	var tip := hovered_card()
	if tip >= 0:
		draw_card_tip(tip)
	if message_time > 0.0:
		outlined(Vector2(SCREEN_W / 2.0, MESSAGE_Y), message, 18, Color(1, 1, 0.6, minf(message_time, 1.0)))


# How close you are to losing: 0 with no monsters alive, 1 at the limit.
func danger() -> float:
	return clampf(float(alive_count()) / max_alive(), 0.0, 1.0)


# Green when few monsters are alive, red near the limit.
func danger_color() -> Color:
	return Color(0.4, 0.9, 0.4).lerp(Color(1, 0.3, 0.3), danger())


func next_wave_text() -> String:
	if wave == 0:
		return "First wave: %s" % kind_for_wave(1).capitalize()
	if wave < MAX_WAVE:
		return "Next wave: %s in %ds" % [kind_for_wave(wave + 1).capitalize(), ceili(next_wave_timer)]
	return "Last wave! Kill them all"


# Hints on the left, the update button in the middle, resources on the right.
func draw_top_bar() -> void:
	text(Vector2(14, 20), "WASD: move camera    Scroll: zoom    Right-click: cancel    Enter: chat    Esc: menu & multiplayer", 13, UI_DIM)
	if update_version != "":
		button(UPDATE_RECT, "New version %s - Update" % update_version, true, true)
	var x := SCREEN_W - 14.0
	x = resource(x, "v" + version, 13, ui_title_dim(), "")
	if is_debug_game():
		x = resource(x, "DEBUG", 13, Color(1.0, 0.45, 0.4), "")
	x = resource(x, "%d / %d" % [wave, MAX_WAVE], 18, UI_TEXT, "wave")
	x = resource(x, "%d / %d" % [alive_count(), max_alive()], 18, danger_color(), "alive")
	resource(x, str(gold), 18, Color(1, 0.85, 0.3), "gold")


# A number with its icon in front, ending at x. Returns where the next one ends.
func resource(x: float, s: String, size: int, col: Color, icon: String) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var y := TOP_BAR_H / 2.0
	hud.draw_string(font, Vector2(x - w, y + size * 0.35 + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7))
	text(Vector2(x - w, y + size * 0.35), s, size, col)
	x -= w
	if icon == "":
		return x - 22
	var c := Vector2(x - 14, y)
	match icon:
		"gold":
			icon_coin(c, 8.0)
		"alive":
			icon_monster(c, 8.0)
		"wave":
			icon_flag(c, 9.0)
	return x - 46


# Towers, monsters, gates in use and the camera's view on the small map
# (the ground and the path are on the stone layer).
func draw_minimap() -> void:
	var m := minimap_map()
	var k := m.size.x / map_cols  # pixels per tile
	for g in gate_cells.size():
		if gate_cells[g] != null and players[g] != null:
			hud.draw_rect(Rect2(m.position + Vector2(gate_cells[g]) * k, Vector2(k, k)).grow(1), PLAYER_COLORS[g])
	for t: Tower in towers.values():
		var r := Rect2(m.position + Vector2(t.cell) * k, Vector2(k, k)).grow(-1)
		hud.draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
		hud.draw_rect(r, TOWERS[t.type]["color"])
	var monster := Color(1, 0.22, 0.15)
	for e in enemies:
		var p := m.position + e.pos / CELL * k
		var h := maxf(1.5, e.radius / CELL * k * 0.8)
		hud.draw_rect(Rect2(p - Vector2(h, h), Vector2(h, h) * 2), monster)
	if selected != null:
		hud.draw_rect(Rect2(m.position + Vector2(selected.cell) * k, Vector2(k, k)).grow(2), UI_GOLD_LIGHT, false, 1.5)
	# What the camera sees, cut to the small map
	var view := PackedVector2Array()
	for s: Vector2 in [Vector2(0, TOP_BAR_H), Vector2(SCREEN_W, TOP_BAR_H), Vector2(SCREEN_W, BAR_TOP), Vector2(0, BAR_TOP)]:
		view.append(m.position + screen_to_ground(s) * k)
	var edge := PackedVector2Array([m.position, Vector2(m.end.x, m.position.y), m.end, Vector2(m.position.x, m.end.y)])
	for poly: PackedVector2Array in Geometry2D.intersect_polygons(view, edge):
		poly.append(poly[0])
		hud.draw_polyline(poly, Color(1, 1, 1, 0.8), 1.0)


# The spot on the ground under a screen point, in tiles.
func screen_to_ground(p: Vector2) -> Vector2:
	var from := camera.project_ray_origin(p)
	var dir := camera.project_ray_normal(p)
	dir.y = minf(dir.y, -0.02)  # above the horizon: just far away
	var hit := from + dir * (-from.y / dir.y)
	return Vector2(hit.x, hit.z)


# Wave number, how close you are to losing, when the next wave comes, and the players.
func draw_wave_info() -> void:
	var x := float(INFO_X)
	ui_title(Rect2(x - 14, BAR_TOP + 10, 236, 36), Vector2(x, BAR_TOP + 40), "WAVE %d / %d" % [wave, MAX_WAVE], 24)
	text(Vector2(x, BAR_TOP + 70), next_wave_text(), 15, UI_GREY)
	text(Vector2(x, BAR_TOP + 98), "Alive: %d / %d" % [alive_count(), max_alive()], 17, danger_color())
	ui_bar(Rect2(x, BAR_TOP + 108, 204, 6), danger(), danger_color())
	if net_mode == "host" or net_mode == "client":
		# A dot per player in their color; yours has a ring
		var px := x
		for slot in MAX_PLAYERS:
			if players[slot] == null:
				continue
			hud.draw_circle(Vector2(px + 6, BAR_TOP + 140), 6, PLAYER_COLORS[slot])
			if slot == local_slot:
				hud.draw_arc(Vector2(px + 6, BAR_TOP + 140), 9, 0, TAU, 20, UI_GOLD_LIGHT, 1.5)
			px += 22
		text(Vector2(px + 4, BAR_TOP + 145), "You: %s" % name_of(local_slot), 14, PLAYER_COLORS[local_slot])
	else:
		text(Vector2(x, BAR_TOP + 145), "Build: keys 1-4   Upgrade: U   Sell: X", 13, UI_DIM)


# The selected tower: its picture, level and stats.
func draw_selected() -> void:
	var data: Dictionary = TOWERS[selected.type]
	var lv := selected.level
	hud.draw_texture_rect(portrait_view.get_texture(), PORTRAIT_RECT, false)
	inner_shadow(PORTRAIT_RECT, 6, 0.4)
	var x := float(STATS_X)
	text(Vector2(x, BAR_TOP + 42), "%s Tower" % data["name"], 22, data["color"])
	# A gold diamond per level, filled up to this one
	for i in 4:
		var c := Vector2(x + 7 + i * 17, BAR_TOP + 59)
		diamond(c, 6.0, UI_GOLD_DARK)
		diamond(c, 4.5, data["color"] if i <= lv else Color(0.08, 0.08, 0.08))
	text(Vector2(x + 78, BAR_TOP + 64), "Level %d" % (lv + 1), 15, UI_TEXT)
	var mine := selected.owner == local_slot
	var next := lv < 3 and mine
	stat_row(Vector2(x, BAR_TOP + 96), "Damage", str(data["damage"][lv]), str(data["damage"][lv + 1]) if next else "")
	stat_row(Vector2(x, BAR_TOP + 118), "Range", "%d" % data["range"][lv], "%d" % data["range"][lv + 1] if next else "")
	stat_row(Vector2(x, BAR_TOP + 140), "Speed", "%.2fs" % data["cooldown"][lv], "")
	var right := x + 196
	hud.draw_multiline_string(font, Vector2(right, BAR_TOP + 96), data["desc"], HORIZONTAL_ALIGNMENT_LEFT, 130, 14, 2, UI_GREY)
	if not mine:
		text(Vector2(right, BAR_TOP + 140), "Built by %s" % name_of(selected.owner), 14, PLAYER_COLORS[selected.owner])
	elif lv == 3:
		text(Vector2(right, BAR_TOP + 140), "Max level", 14, UI_GOLD_LIGHT)


# "Damage  120  > 250": the value now and, in green, after the next upgrade.
func stat_row(pos: Vector2, label: String, now: String, after: String) -> void:
	text(pos, label, 14, UI_DIM)
	text(pos + Vector2(64, 0), now, 16, UI_TEXT)
	if after != "":
		text(pos + Vector2(110, 0), "> " + after, 15, Color(0.6, 0.9, 0.6))


# Nothing selected: the four towers with their price and what they do.
func draw_build_list() -> void:
	var p := PORTRAIT_RECT.get_center()
	if build_type != "":
		gem(p, 26.0, TOWERS[build_type]["color"])
	else:
		crest(p, UI_GOLD_DARK)
	var x := float(STATS_X)
	ui_heading(Vector2(x, BAR_TOP + 36), "BUILD A TOWER", 324)
	for i in TOWER_TYPES.size():
		var type: String = TOWER_TYPES[i]
		var data: Dictionary = TOWERS[type]
		var y := BAR_TOP + 62 + i * 24
		var affordable: bool = gold >= data["cost"][0]
		if build_type == type:
			hud.draw_rect(Rect2(x - 6, y - 17, 330, 22), Color(1, 0.85, 0.3, 0.15))
		gem(Vector2(x + 6, y - 6), 5.0, data["color"])
		text(Vector2(x + 18, y), data["name"], 16, UI_TEXT if affordable else UI_DIM)
		text(Vector2(x + 82, y), "%dg" % data["cost"][0], 15, Color(1, 0.85, 0.3) if affordable else Color(0.6, 0.4, 0.3))
		text(Vector2(x + 130, y), data["desc"], 14, UI_GREY)
	var hint := "Click the map to build. Right-click: cancel" if build_type != "" else "Click a tower to upgrade or sell it."
	text(Vector2(x, BAR_TOP + 160), hint, 13, UI_DIM)


# ---- Command card: square buttons with hotkeys

func card_rects() -> Array:
	var out := []
	for i in TOWER_TYPES.size():
		out.append(tower_button_rect(i))
	out.append_array([UPGRADE_RECT, SELL_RECT, WAVE_RECT, SPEED_RECT])
	return out


# The command button under the mouse, or -1.
func hovered_card() -> int:
	if menu_open or update_dialog != "":
		return -1
	var p := get_viewport().get_mouse_position()
	var rects := card_rects()
	for i in rects.size():
		if rects[i].has_point(p):
			return i
	return -1


func draw_command_card() -> void:
	for i in TOWER_TYPES.size():
		var data: Dictionary = TOWERS[TOWER_TYPES[i]]
		var r := tower_button_rect(i)
		var affordable: bool = gold >= data["cost"][0]
		card_button(r, str(i + 1), data["name"], "%dg" % data["cost"][0], true, build_type == TOWER_TYPES[i], affordable)
		gem(r.get_center() + Vector2(0, -2), 11.0, data["color"] if affordable else data["color"].darkened(0.4))
	# Upgrade and Sell only work on your own selected tower
	var mine := selected != null and selected.owner == local_slot
	var up_label := "Upgrade"
	var up_cost := ""
	var can_up := false
	if mine and selected.level < 3:
		var cost: int = TOWERS[selected.type]["cost"][selected.level + 1]
		up_cost = "%dg" % cost
		can_up = gold >= cost
	elif mine:
		up_label = "Max"
	card_button(UPGRADE_RECT, "U", up_label, up_cost, can_up, false, can_up)
	icon_upgrade(UPGRADE_RECT.get_center() + Vector2(0, -2), UI_GOLD_LIGHT if can_up else UI_DIM)
	card_button(SELL_RECT, "X", "Sell", "+%dg" % int(selected.spent * 0.7) if mine else "", mine, false, true)
	icon_coin(SELL_RECT.get_center() + Vector2(0, -2), 10.0, mine)
	var w := wave_button()
	var can_wave := wave < MAX_WAVE and state == "playing" and monsters_left_to_spawn() == 0
	card_button(WAVE_RECT, "Space", w[0], w[1], can_wave, local_slot in wave_votes, true)
	icon_flag(WAVE_RECT.get_center() + Vector2(0, -2), 12.0, can_wave)
	card_button(SPEED_RECT, "F", "x%d" % game_speed, "", net_mode != "client", game_speed > 1, true)
	icon_speed(SPEED_RECT.get_center() + Vector2(0, -2), UI_GOLD_LIGHT if net_mode != "client" else UI_DIM)


# Short label and corner text for the wave button: [label, corner].
func wave_button() -> Array:
	if wave == 0:
		return ["Start", ""]
	if wave < MAX_WAVE and monsters_left_to_spawn() > 0:
		return ["%d left" % monsters_left_to_spawn(), ""]
	var bonus := "+%dg" % int(maxf(next_wave_timer, 0.0))
	var votes := "%d/%d" % [wave_votes.size(), votes_needed()]
	if wave < MAX_WAVE and player_count() > 1:
		return ["Voted " + votes, ""] if local_slot in wave_votes else ["Vote " + votes, bonus]
	if wave < MAX_WAVE:
		return ["Send", bonus]
	return ["Done", ""]


# The full wave button text, as the side panel used to show it.
func wave_tip() -> String:
	if wave == 0:
		return "Start the first wave (SPACE)"
	if wave < MAX_WAVE and monsters_left_to_spawn() > 0:
		return "Spawning... (%d left)" % monsters_left_to_spawn()
	var votes := "%d/%d" % [wave_votes.size(), votes_needed()]
	if wave < MAX_WAVE and player_count() > 1:
		if local_slot in wave_votes:
			return "Voted %s (SPACE: undo)" % votes
		return "Vote to send it now: +%dg each, %s (SPACE)" % [int(maxf(next_wave_timer, 0.0)), votes]
	if wave < MAX_WAVE:
		return "Send the next wave now: +%dg (SPACE)" % int(maxf(next_wave_timer, 0.0))
	return "No more waves"


func card_button(r: Rect2, key: String, label: String, corner: String, enabled: bool, active: bool, affordable: bool) -> void:
	ui_button_bg(r, enabled, active)
	# Hotkey in the top-left corner, price or bonus in the top-right
	text(r.position + Vector2(5, 13), key, 11, UI_GOLD_LIGHT if enabled else UI_DIM)
	if corner != "":
		var cw := font.get_string_size(corner, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		text(Vector2(r.end.x - cw - 5, r.position.y + 13), corner, 11, Color(1, 0.85, 0.3) if affordable else Color(0.7, 0.42, 0.3))
	var col := UI_TEXT if enabled and affordable else UI_DIM
	if active and enabled:
		col = UI_GOLD_LIGHT
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var pos := Vector2(r.get_center().x - lw / 2.0, r.end.y - 6)
	hud.draw_string(font, pos + Vector2(0, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.8))
	text(pos, label, 13, col)


# A box above the command card that explains the button under the mouse.
func draw_card_tip(i: int) -> void:
	var title := ""
	var lines: Array = []
	if i < TOWER_TYPES.size():
		var data: Dictionary = TOWERS[TOWER_TYPES[i]]
		title = "Build %s Tower (%d)  -  %dg" % [data["name"], i + 1, data["cost"][0]]
		lines = [data["desc"], "Damage %d   Range %d   Speed %.2fs" % [data["damage"][0], data["range"][0], data["cooldown"][0]]]
	elif i == 4:
		title = "Upgrade (U)"
		if selected == null or selected.owner != local_slot:
			lines = ["Select one of your towers first."]
		elif selected.level < 3:
			var data: Dictionary = TOWERS[selected.type]
			title = "Upgrade to level %d (U)  -  %dg" % [selected.level + 2, data["cost"][selected.level + 1]]
			lines = ["Damage %d   Range %d" % [data["damage"][selected.level + 1], data["range"][selected.level + 1]]]
		else:
			lines = ["This tower is at its highest level."]
	elif i == 5:
		title = "Sell (X)"
		lines = ["Get back %dg for this tower." % int(selected.spent * 0.7)] if selected != null and selected.owner == local_slot else ["Select one of your towers first."]
	elif i == 6:
		title = "Next wave (SPACE)"
		lines = [wave_tip(), next_wave_text()]
	else:
		title = "Game speed x%d (F)" % game_speed
		lines = ["Only the host can change the speed."] if net_mode == "client" else ["Switches between normal, double and triple speed."]
	var r := Rect2(SCREEN_W - 372, BAR_TOP - 24 - 34 - lines.size() * 20, 360, 34 + lines.size() * 20 + 10)
	hud.draw_rect(r.grow(1), Color(0, 0, 0, 0.9), false, 1.0)
	hud.draw_rect(r, Color(0.05, 0.05, 0.055, 0.92))
	hud.draw_rect(r, UI_GOLD_DARK, false, 1.0)
	text(r.position + Vector2(12, 24), title, 16, Color(1, 0.85, 0.3))
	for j in lines.size():
		text(r.position + Vector2(12, 48 + j * 20), lines[j], 14, UI_TEXT)


# ---- Small icons drawn with shapes

func diamond(c: Vector2, s: float, col: Color) -> void:
	quad(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), col)


func icon_coin(c: Vector2, radius: float, lit := true) -> void:
	var a := 1.0 if lit else 0.4
	hud.draw_circle(c, radius + 1.0, Color(0.25, 0.15, 0.03, a))
	hud.draw_circle(c, radius, Color(0.95, 0.72, 0.2, a))
	hud.draw_circle(c, radius * 0.7, Color(0.75, 0.52, 0.1, a))
	hud.draw_circle(c, radius * 0.55, Color(1.0, 0.82, 0.3, a))
	hud.draw_circle(c - Vector2(radius * 0.35, radius * 0.4), radius * 0.22, Color(1, 1, 0.9, 0.7 * a))


func icon_monster(c: Vector2, radius: float) -> void:
	hud.draw_circle(c, radius + 1.0, Color(0, 0, 0, 0.7))
	hud.draw_circle(c, radius, Color(0.62, 0.14, 0.1))
	hud.draw_circle(c + Vector2(0, -1), radius - 2.0, Color(0.85, 0.24, 0.16))
	hud.draw_circle(c + Vector2(-3, -1), 1.8, Color(1, 0.95, 0.6))
	hud.draw_circle(c + Vector2(3, -1), 1.8, Color(1, 0.95, 0.6))


# A banner on a pole.
func icon_flag(c: Vector2, s: float, lit := true) -> void:
	var pole := Color(0.85, 0.7, 0.4) if lit else UI_DIM
	var cloth := Color(0.85, 0.2, 0.15) if lit else Color(0.35, 0.18, 0.16)
	hud.draw_line(c + Vector2(-s * 0.6, s), c + Vector2(-s * 0.6, -s), pole, 2.0)
	quad(PackedVector2Array([c + Vector2(-s * 0.5, -s), c + Vector2(s * 0.8, -s * 0.75), c + Vector2(s * 0.3, -s * 0.3), c + Vector2(-s * 0.5, -s * 0.05)]), cloth)
	quad(PackedVector2Array([c + Vector2(s * 0.8, -s * 0.75), c + Vector2(s * 0.8, -s * 0.75), c + Vector2(s * 0.75, -s * 0.05), c + Vector2(s * 0.3, -s * 0.3)]), cloth.darkened(0.3))


# Two chevrons pointing up.
func icon_upgrade(c: Vector2, col: Color) -> void:
	for k in 2:
		var y := c.y + 4 - k * 8
		hud.draw_polyline(PackedVector2Array([Vector2(c.x - 9, y + 5), Vector2(c.x, y - 4), Vector2(c.x + 9, y + 5)]), col, 3.0)


# Two triangles pointing right.
func icon_speed(c: Vector2, col: Color) -> void:
	for k in 2:
		var x := c.x - 9 + k * 9
		quad(PackedVector2Array([Vector2(x, c.y - 7), Vector2(x + 9, c.y), Vector2(x + 9, c.y), Vector2(x, c.y + 7)]), col)


# An empty shield, shown in the portrait frame when nothing is selected.
func crest(c: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-24, -28), c + Vector2(24, -28), c + Vector2(24, 4), c + Vector2(0, 30), c + Vector2(-24, 4)])
	pts.append(pts[0])
	hud.draw_polyline(pts, col, 3.0)
	diamond(c + Vector2(0, -2), 9.0, col)


func centered(y: float, s: String, size: int, col := Color.WHITE) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2((SCREEN_W - w) / 2.0, y), s, size, col)


# The Esc menu: pause, and host or join a multiplayer game.
func draw_menu() -> void:
	var m := MENU_RECT
	var left := HOST_RECT.position.x
	var width := HOST_RECT.size.x
	hud.draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.5))
	ui_box(m)
	var title := "PAUSED" if net_mode == "" else "MENU"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	ui_title(Rect2(m.position.x, m.position.y, m.size.x, 66), Vector2((SCREEN_W - tw) / 2.0, m.position.y + 50), title, 40)
	var sub := "The game is paused." if net_mode == "" else "The game keeps running while this menu is open."
	centered(m.position.y + 84, sub, 15, UI_GREY)
	button(GRAPHICS_RECT, "Graphics: %s" % ("High" if graphics_high else "Low"), true, graphics_high)
	ui_heading(Vector2(left, 196), "MULTIPLAYER", width)
	var grey := UI_GREY
	var gold_col := Color(1, 0.85, 0.3)
	match net_mode:
		"":
			text(Vector2(left, NAME_INPUT_RECT.position.y + 24), "Your name:", 16, UI_TEXT)
			button(HOST_RECT, "Host a game and get an invite code", true, true)
			text(Vector2(left, JOIN_INPUT_RECT.position.y - 12), "Or join a friend's game with their invite code:", 15, grey)
			button(JOIN_BUTTON_RECT, "Join")
			hud.draw_multiline_string(font, Vector2(left, JOIN_INPUT_RECT.end.y + 26), net_status, HORIZONTAL_ALIGNMENT_LEFT, width, 15, 3, Color(1, 0.75, 0.5))
			if relay_url != "":
				draw_public_games()
		"searching", "connecting":
			button(HOST_RECT, "Cancel")
			hud.draw_multiline_string(font, Vector2(left, HOST_RECT.end.y + 30), net_status, HORIZONTAL_ALIGNMENT_LEFT, width, 16, 3, grey)
		"host":
			text(Vector2(left, 234), "Invite code:", 15, grey)
			if invite_code != "":
				text(Vector2(left, 278), invite_code, 40, gold_col)
				button(COPY_RECT, "Copy")
			else:
				text(Vector2(left, 272), "Getting your invite code...", 18, grey)
			hud.draw_multiline_string(font, Vector2(left, 312), net_status, HORIZONTAL_ALIGNMENT_LEFT, width, 14, 3, grey)
			if relay != null and invite_code != "":
				var label := "Public game: ON  (anyone can find it in the list)" if public_game else "Public game: OFF  (only friends with the code)"
				button(PUBLIC_RECT, label, true, public_game)
			draw_player_list(Vector2(left, 428))
			button(STOP_RECT, "Stop hosting")
		"client":
			text(Vector2(left, 234), "You are playing as %s." % name_of(local_slot), 16, PLAYER_COLORS[local_slot])
			draw_player_list(Vector2(left, 266))
			button(STOP_RECT, "Leave the game")
	button(RESUME_RECT, "Resume (Esc)")


func game_row_rect(i: int) -> Rect2:
	return Rect2(HOST_RECT.position.x, REFRESH_RECT.end.y + 8 + i * 38, HOST_RECT.size.x, 34)


func draw_public_games() -> void:
	var left := HOST_RECT.position.x
	ui_heading(Vector2(left, REFRESH_RECT.position.y + 20), "PUBLIC GAMES", REFRESH_RECT.position.x - left - 10)
	button(REFRESH_RECT, "Refresh", games_http == null)
	if public_games.is_empty():
		text(Vector2(left, REFRESH_RECT.end.y + 34), games_status, 15, UI_GREY)
	for i in mini(public_games.size(), GAME_ROWS):
		var g: Dictionary = public_games[i]
		button(game_row_rect(i), "Join  %s      %d / %d players      wave %d" % [g.code, int(g.players), MAX_PLAYERS, int(g.wave)])


func draw_player_list(pos: Vector2) -> void:
	text(pos, "Players (%d / %d):" % [player_count(), map_slots()], 15, UI_GREY)
	var y := pos.y + 24
	for slot in MAX_PLAYERS:
		if players[slot] == null:
			continue
		hud.draw_circle(Vector2(pos.x + 8, y - 5), 6, PLAYER_COLORS[slot])
		var who: String = name_of(slot)
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


# Everything about the console that never changes: drawn once, on its own layer.
func ui_console() -> void:
	# Resource bar along the top, with a gold strip under it
	var top := Rect2(0, 0, SCREEN_W, TOP_BAR_H)
	stone_blocks(top, UI_STONE, 30, 96)
	vgrad(top, Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.3))
	hud.draw_rect(Rect2(0, TOP_BAR_H + 4, SCREEN_W, 2), Color(0, 0, 0, 0.5))
	bevel(Rect2(-6, TOP_BAR_H, SCREEN_W + 12, 5), 2, UI_GOLD_LIGHT, UI_GOLD_DARK)
	# A raised arch over the portrait, poking up into the map
	var arch := Vector2(PORTRAIT_RECT.get_center().x, BAR_TOP + ARCH_DROP)
	hud.draw_circle(arch, ARCH_R + 4, Color(0, 0, 0, 0.5))
	hud.draw_circle(arch, ARCH_R + 2, UI_GOLD_DARK)
	hud.draw_circle(arch, ARCH_R, UI_GOLD)
	hud.draw_circle(arch, ARCH_R - 3, UI_GOLD_DARK)
	hud.draw_circle(arch, ARCH_R - 5, UI_STONE)
	# The console
	var r := Rect2(0, BAR_TOP, SCREEN_W, SCREEN_H - BAR_TOP)
	stone_blocks(r, UI_STONE, 36, 96)
	vgrad(r, Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.35))
	# Gold strip along the top edge, stopping at the arch
	var hw := sqrt(ARCH_R * ARCH_R - (ARCH_DROP + 6.0) * (ARCH_DROP + 6.0))
	hud.draw_rect(Rect2(0, BAR_TOP - 8, arch.x - hw, 2), Color(0, 0, 0, 0.5))
	hud.draw_rect(Rect2(arch.x + hw, BAR_TOP - 8, SCREEN_W, 2), Color(0, 0, 0, 0.5))
	bevel(Rect2(-6, BAR_TOP - 6, arch.x - hw + 8, 6), 3, UI_GOLD_LIGHT, UI_GOLD_DARK)
	bevel(Rect2(arch.x + hw - 2, BAR_TOP - 6, SCREEN_W, 6), 3, UI_GOLD_LIGHT, UI_GOLD_DARK)
	stud(Vector2(arch.x - hw - 2, BAR_TOP - 3), 5.0)
	stud(Vector2(arch.x + hw + 2, BAR_TOP - 3), 5.0)
	# Sections, split by gold lines with studs
	recess(MINIMAP_RECT.grow(4))
	draw_minimap_ground()
	vdivider(INFO_X - 12, BAR_TOP + 12, SCREEN_H - 10)
	vdivider(PORTRAIT_RECT.position.x - 18, BAR_TOP + 12, SCREEN_H - 10)
	vdivider(CARD_X - 24, BAR_TOP + 12, SCREEN_H - 10)
	recess(Rect2(CARD_X - 8, CARD_Y - 8, CARD_SIZE * 4 + CARD_GAP * 3 + 16, CARD_SIZE * 2 + CARD_GAP + 16))
	# The portrait's gold frame with a stud on each corner
	recess(PORTRAIT_RECT)
	hud.draw_rect(PORTRAIT_RECT.grow(7), Color(0, 0, 0, 0.8), false, 1.0)
	bevel(PORTRAIT_RECT.grow(6), 6, UI_GOLD_LIGHT, UI_GOLD_DARK)
	for c in [PORTRAIT_RECT.position, Vector2(PORTRAIT_RECT.end.x, PORTRAIT_RECT.position.y), PORTRAIT_RECT.end, Vector2(PORTRAIT_RECT.position.x, PORTRAIT_RECT.end.y)]:
		stud(c, 6.0)


# The small map's grass and path.
func draw_minimap_ground() -> void:
	var m := minimap_map()
	var k := m.size.x / map_cols
	hud.draw_rect(m, Color(0.13, 0.27, 0.1))
	for c: Vector2i in path_cells:
		hud.draw_rect(Rect2(m.position + Vector2(c) * k, Vector2(k, k)), Color(0.4, 0.28, 0.16))


# Where the map sits on the small map: as big as fits, in the middle.
func minimap_map() -> Rect2:
	var m := MINIMAP_RECT
	var k := minf(m.size.x / map_cols, m.size.y / map_rows)
	var size := Vector2(map_cols, map_rows) * k
	return Rect2(m.position + (m.size - size) / 2.0, size)


# A dark sunken area, with light on its lower edges.
func recess(r: Rect2) -> void:
	hud.draw_rect(r, Color(0.05, 0.05, 0.055))
	inner_shadow(r, 6, 0.5)
	bevel(r.grow(2), 2, Color(0.08, 0.06, 0.03), UI_GOLD)


# A thin upright gold line that fades out at both ends, with a stud on top.
func vdivider(x: float, y0: float, y1: float) -> void:
	var mid := (y0 + y1) / 2.0
	var clear := Color(UI_GOLD, 0.0)
	hud.draw_polyline_colors(PackedVector2Array([Vector2(x, y0), Vector2(x, mid), Vector2(x, y1)]), PackedColorArray([UI_GOLD, UI_GOLD, clear]), 1.0)
	hud.draw_polyline_colors(PackedVector2Array([Vector2(x + 1, y0), Vector2(x + 1, mid), Vector2(x + 1, y1)]), PackedColorArray([Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)]), 1.0)
	stud(Vector2(x, y0), 4.0)


# A round gold rivet.
func stud(c: Vector2, radius: float) -> void:
	hud.draw_circle(c, radius + 1.0, Color(0, 0, 0, 0.7))
	hud.draw_circle(c, radius, UI_GOLD_DARK)
	hud.draw_circle(c - Vector2(0.5, 0.5), radius - 1.2, UI_GOLD)
	hud.draw_circle(c - Vector2(radius * 0.3, radius * 0.3), radius * 0.35, UI_GOLD_LIGHT)


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
		name_input.release_focus()
	close_chat()


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
	hud.draw_rect(Rect2(0, TOP_BAR_H, SCREEN_W, BAR_TOP - TOP_BAR_H), Color(0, 0, 0, 0.6))
	var title := "VICTORY!" if state == "won" else "GAME OVER"
	var sub := "You survived all %d waves." % MAX_WAVE if state == "won" else "Too many monsters! You reached wave %d." % wave
	var size := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64)
	var pos := Vector2((SCREEN_W - size.x) / 2.0, END_Y)
	hud.draw_string_outline(title_font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, 6, Color(0, 0, 0, 0.8))
	hud.draw_string(title_font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1, 0.85, 0.3) if state == "won" else Color(1, 0.35, 0.35))
	size = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	text(Vector2((SCREEN_W - size.x) / 2.0, END_Y + 50), sub, 22, UI_TEXT)
	size = font.get_string_size("Press R to play again", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	text(Vector2((SCREEN_W - size.x) / 2.0, END_Y + 90), "Press R to play again", 18, UI_GREY)
