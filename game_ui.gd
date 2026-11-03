extends "res://game_net.gd"
## The 2D overlay: bottom console, health bars, lightning, menus and popups.

# Dark stone with gold edges
const UI_GOLD := Color(0.86, 0.68, 0.32)
const UI_GOLD_LIGHT := Color(1.0, 0.88, 0.55)
const UI_GOLD_DARK := Color(0.4, 0.28, 0.1)
const UI_TEXT := Color(0.95, 0.91, 0.82)
const UI_GREY := Color(0.72, 0.69, 0.63)
const UI_DIM := Color(0.55, 0.52, 0.47)
# Each difficulty level's color (see DIFFICULTIES): Easy, Normal, Hard, Insane
const LEVEL_COLORS := [Color(0.5, 0.92, 0.42), Color(0.95, 0.91, 0.82), Color(1.0, 0.62, 0.25), Color(1.0, 0.32, 0.28)]

# The Esc menu's bottom row: Save, Load, Resume and Leaderboard
const MENU_SAVE_RECT := Rect2(430, 640, 80, 44)
const MENU_LOAD_RECT := Rect2(518, 640, 80, 44)
const MENU_RESUME_RECT := Rect2(606, 640, 128, 44)
# The leaderboard: its button right of Resume in the Esc menu, and its box
const LEADERBOARD_RECT := Rect2(742, 640, 108, 44)
const BOARD_RECT := Rect2(320, 50, 640, 620)
const BOARD_REFRESH_RECT := Rect2(360, 606, 170, 40)
const BOARD_BACK_RECT := Rect2(750, 606, 170, 40)
const BOARD_ROW_H := 32

# The update popup's "What's new" box, which scrolls when the notes don't fit
const NOTES_RECT := Rect2(364, 244, 552, 208)
const NOTES_PAD := 14.0  # space between the box's edge and the text
const NOTES_BAR_W := 8.0
const NOTES_STEP := 50.0  # pixels per mouse wheel notch or arrow key

var title_font: Font  # big titles; the normal font unless a style says otherwise
var map_hud: Node2D  # 2D layer under the console: health bars, lightning, area labels
var console_layer: Node2D  # the console's stone, drawn once (and again when the map changes)
var end_layer: Node2D  # the end screen's dark cover, under the overlay
var stats_layer: Node2D  # the end screen's stats panel, fading in (a child of end_layer)
var portrait_view: SubViewport  # a close-up of the selected tower, shown in the console
var portrait_cam: Camera3D
var notes_clip: Control  # cuts the update notes off at their box's edges
var notes_layer: Node2D  # the update notes, drawn inside notes_clip
var notes_lines: Array = []  # the notes laid out once: [y, x, width, text, size, color]
var notes_for := ""  # which notes notes_lines was laid out for
var notes_height := 0.0
var notes_scroll := 0.0
var notes_target := 0.0  # where the notes glide to
var notes_drag := -1.0  # where the mouse holds the scrollbar's handle, or -1

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
	portrait_view.size = Vector2i(PORTRAIT_RECT.size)  # bigger on big screens (see place_ui)
	portrait_view.msaa_3d = Viewport.MSAA_4X  # it's small, so smooth edges are cheap
	portrait_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(portrait_view)
	portrait_cam = Camera3D.new()
	portrait_cam.fov = 30.0
	portrait_view.add_child(portrait_cam)
	# The end screen's dark cover and stats panel: under the rest, so chat and
	# popups stay on top. The panel is its own node so it can fade in.
	end_layer = Node2D.new()
	end_layer.visible = false
	layer.add_child(end_layer)
	end_layer.draw.connect(draw_on.bind(end_layer, draw_end_cover))
	stats_layer = Node2D.new()
	end_layer.add_child(stats_layer)
	stats_layer.draw.connect(draw_on.bind(stats_layer, draw_stats_panel))
	hud = Node2D.new()
	layer.add_child(hud)
	hud.draw.connect(draw_hud)
	build_story_layer()
	# The update notes go on top of the popup, cut off at their box
	notes_clip = Control.new()
	notes_clip.position = NOTES_RECT.position + Vector2(2, 2)
	notes_clip.size = NOTES_RECT.size - Vector2(4, 4)
	notes_clip.clip_contents = true
	notes_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notes_clip.visible = false
	layer.add_child(notes_clip)
	notes_layer = Node2D.new()
	notes_clip.add_child(notes_layer)
	notes_layer.draw.connect(draw_on.bind(notes_layer, draw_notes))

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
	# The Save box's name (Enter saves, Esc closes the box)
	save_input = text_box(layer, SAVE_INPUT_RECT, "Name the save", SAVE_NAME_MAX, 17)
	save_input.text_submitted.connect(func(_t: String) -> void: save_click(SAVE_OK_RECT.get_center()))
	save_input.text_changed.connect(func(_t: String) -> void: save_confirm = "")
	save_input.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			close_save_boxes()
			save_input.accept_event())
	get_viewport().size_changed.connect(place_ui)


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


# New player colours: the overlay reads color_of() as it draws, so drawing the
# layers once more is all it needs.
func colors_changed() -> void:
	super()
	for layer: CanvasItem in [map_hud, console_layer, stats_layer]:
		if layer != null:
			layer.queue_redraw()


# Runs draw_func with the drawing helpers drawing on node instead of hud.
func draw_on(node: Node2D, draw_func: Callable) -> void:
	var top := hud
	hud = node
	draw_func.call()
	hud = top


# The map layer redraws every frame along with the 3D world.
func update_visuals(delta: float) -> void:
	super(delta)
	update_fireworks(delta)
	for i in range(pings.size() - 1, -1, -1):
		pings[i][2] -= delta
		if pings[i][2] <= 0.0:
			pings.remove_at(i)
	gift_glow = maxf(gift_glow - delta, 0.0)
	if gift_to >= 0 and not can_gift(gift_to):
		gift_to = -1
	map_hud.queue_redraw()
	update_end_layer()
	update_notes_box()
	update_save_boxes()
	update_profile_boxes()
	update_story_card(delta)
	update_festival(delta)
	if selected == null:
		portrait_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	portrait_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# From the front and a little above, like the main camera but close
	var p := selected.node.position
	if selected.type == "barracks":
		# A low, wide hall: closer and lower
		portrait_cam.position = p + Vector3(0, 1.9, 3.0)
		portrait_cam.look_at(p + Vector3(0, 0.5, 0))
		return
	portrait_cam.position = p + Vector3(0, 2.2, 3.4)
	portrait_cam.look_at(p + Vector3(0, 0.75, 0))


func draw_hud() -> void:
	draw_panel()
	if state == "playing":
		end_at_ms = -1
	elif end_at_ms < 0:
		end_at_ms = Time.get_ticks_msec()
	if state != "playing":
		hud.draw_set_transform(Vector2(0, ui_extra / 2.0))
		draw_end_screen()
		draw_fireworks()
	hud.draw_set_transform(Vector2(0, ui_extra))
	draw_chat()
	hud.draw_set_transform(Vector2.ZERO)
	draw_tip_card()
	draw_achievement_popup()
	# Popups in the middle of the screen
	hud.draw_set_transform(Vector2(0, ui_extra / 2.0))
	if menu_open:
		draw_menu()
	if gift_to >= 0:
		draw_gift_box()
	if update_dialog != "":
		draw_update_dialog()
	hud.draw_set_transform(Vector2.ZERO)


# The whole screen whichever way the drawing is shifted, for darkening it under popups.
func screen_rect() -> Rect2:
	return Rect2(0, -ui_extra, SCREEN_W, SCREEN_H + ui_extra * 2.0)


# Taller screens (16:10): the console and text boxes move down, popups half as
# much (see ui_extra). Called at the start and whenever the window's size changes.
func place_ui() -> void:
	var vp := get_viewport()
	var seen := vp.get_visible_rect().size
	ui_extra = maxf(seen.y - SCREEN_H, 0.0)
	var down := Vector2(0, ui_extra)
	var half := down / 2.0
	chat_input.position = CHAT_INPUT_RECT.position + down
	code_input.position = JOIN_INPUT_RECT.position + half
	name_input.position = NAME_INPUT_RECT.position + half
	save_input.position = SAVE_INPUT_RECT.position + half
	notes_clip.position = NOTES_RECT.position + Vector2(2, 2) + half
	if fw_glow != null:
		fw_glow.position = half
		fw_paper.position = half
	# The portrait at the screen's real pixels, so it's sharp on big screens
	var k := clampf(vp.get_final_transform().get_scale().x, 1.0, 4.0)
	portrait_view.size = Vector2i(PORTRAIT_RECT.size * k)
	console_layer.queue_redraw()


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
				chat_text(Vector2(x, y), who, size, Color(ink_of(slot), alpha))
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
	# The end screen covers the map: no bars, badges or labels on top of it (the replay hides it)
	if state != "playing" and not replaying():
		return
	draw_pings()
	draw_health_bars()
	draw_level_badges()
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
	if aiming == "meteor" and not mouse_over_panel():
		draw_meteor_aim()
	if freeze_flash > 0.0:
		draw_frost_edge(freeze_flash / FREEZE_EDGE)


# Aiming Meteor: the circle it will hit, lying on the ground under the mouse
# (seen at the camera's angle), and a small cross in the middle.
func draw_meteor_aim() -> void:
	var at := mouse_point()
	var radius: float = ABILITIES["meteor"]["radius"]
	var pts := PackedVector2Array()
	for k in 49:
		var ang := k * TAU / 48.0
		pts.append(camera.unproject_position(to3d(at + Vector2(cos(ang), sin(ang)) * radius, 0.02)))
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
	hud.draw_colored_polygon(pts, Color(1.0, 0.4, 0.1, 0.16 + 0.06 * pulse))
	hud.draw_polyline(pts, Color(0, 0, 0, 0.5), 4.5)
	hud.draw_polyline(pts, Color(1.0, 0.62, 0.25, 0.85 + 0.15 * pulse), 2.5)
	var c := camera.unproject_position(to3d(at, 0.02))
	for d: Vector2 in [Vector2(1, 0), Vector2(0, 1)]:
		hud.draw_line(c - d * 7.0, c + d * 7.0, Color(0, 0, 0, 0.6), 3.0)
		hud.draw_line(c - d * 6.0, c + d * 6.0, Color(1.0, 0.8, 0.45), 1.5)
	# The monsters it would hit get a small red mark at their feet
	var r2 := radius * radius
	for e in enemies:
		if e.pos.distance_squared_to(at) <= r2:
			var p := camera.unproject_position(e.node.position)
			hud.draw_arc(p, 5.0, 0, TAU, 12, Color(1.0, 0.3, 0.15, 0.85), 1.5)


# Freeze all: the screen's edge frosts over and thaws again (k: 1 to 0).
func draw_frost_edge(k: float) -> void:
	var s := Rect2(0, TOP_BAR_H, SCREEN_W, BAR_TOP + ui_extra - TOP_BAR_H)  # the map between the bars
	var deep := 150.0 * (0.6 + 0.4 * k)
	var ice := Color(0.72, 0.88, 1.0, 0.55 * k)
	var clear := Color(0.72, 0.88, 1.0, 0.0)
	var o := [s.position, Vector2(s.end.x, s.position.y), s.end, Vector2(s.position.x, s.end.y)]
	var i := [s.position + Vector2(deep, deep), Vector2(s.end.x - deep, s.position.y + deep), s.end - Vector2(deep, deep), Vector2(s.position.x + deep, s.end.y - deep)]
	for side in 4:
		var n := (side + 1) % 4
		hud.draw_polygon(PackedVector2Array([o[side], o[n], i[n], i[side]]), PackedColorArray([ice, ice, clear, clear]))
	# A quick white-blue flash at the start
	var flash := clampf((k - 0.75) / 0.25, 0.0, 1.0)
	if flash > 0.0:
		hud.draw_rect(s, Color(0.75, 0.9, 1.0, 0.22 * flash))


# Towers above level 4 look like level 4, so their level shows on a small
# badge at their foot: "Lv 12".
func draw_level_badges() -> void:
	for t: Tower in towers.values():
		if t.level <= 3:
			continue
		var p := camera.unproject_position(t.node.position + Vector3(0, 0.05, 0.5))
		var s := "Lv %d" % (t.level + 1)
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var r := Rect2(p.x - w / 2.0 - 4, p.y - 7, w + 8, 15)
		hud.draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
		hud.draw_rect(r, Color(0.12, 0.09, 0.05, 0.9))
		hud.draw_rect(r, UI_GOLD_DARK, false, 1.0)
		text(Vector2(r.position.x + 4, p.y + 5), s, 12, UI_GOLD_LIGHT)


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
	hud.draw_rect(Rect2(r.position.x + 10, r.position.y + 40, r.size.x - 20, 2), ink_of(from) * Color(1, 1, 1, 0.7))
	var line := "%s wants to build a %s tower in your area" % [name_of(from), str(ask[2]).capitalize()]
	if asks.size() > 1:
		line += "  (+%d more)" % (asks.size() - 1)
	text(r.position + Vector2(20, 32), line, 17, ink_of(from))
	text(r.position + Vector2(20, 68), "The spot is marked with a ring on the map.", 14, UI_GREY)
	button(ASK_YES_RECT, "Yes (Y)", true, true)
	button(ASK_NO_RECT, "No (N)")
	# Point at the spot with a pulsing ring (on the map: not shifted with the console)
	var spot := camera.unproject_position(Vector3(cell.x + 0.5, 0.1, cell.y + 0.5))
	hud.draw_set_transform(Vector2.ZERO)
	hud.draw_arc(spot, 16.0 + sin(time * 6.0) * 4.0, 0, TAU, 32, ink_of(from), 3.0)
	hud.draw_set_transform(Vector2(0, ui_extra))


func draw_update_dialog() -> void:
	var d := DIALOG_RECT
	var left := d.position.x + 30
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.6))
	ui_box(d)
	if update_dialog.begins_with("unpack"):
		draw_unpack_dialog()
		return
	ui_title(Rect2(d.position.x, d.position.y, d.size.x, 66), Vector2(left, d.position.y + 46), "New version %s is out!" % update_version, 28)
	var mine := "You have v%s" % version
	if update_dialog != "ask":
		text(Vector2(left, d.position.y + 90), mine, 15, UI_DIM)
	match update_dialog:
		"ask":
			text(Vector2(left, d.position.y + 94), "What's new", 18, UI_GOLD_LIGHT)
			hud.draw_string(font, Vector2(d.end.x - 30 - 300, d.position.y + 94), mine, HORIZONTAL_ALIGNMENT_RIGHT, 300, 15, UI_DIM)
			draw_notes_box()
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


# ---- The update popup's "What's new" box

# The sunken box and, when the notes don't fit, a scrollbar. The notes
# themselves are drawn on notes_layer (draw_notes), cut off at the box.
func draw_notes_box() -> void:
	recess(NOTES_RECT)
	if notes_max() <= 0.0:
		return
	var track := notes_track()
	hud.draw_rect(track, Color(0, 0, 0, 0.55))
	hud.draw_rect(track.grow(1), Color(0.3, 0.22, 0.1, 0.8), false, 1.0)
	var thumb := notes_thumb()
	var grabbed := notes_drag >= 0.0 or thumb.has_point(ui_mouse(true))
	vgrad(thumb, UI_GOLD_LIGHT if grabbed else UI_GOLD, UI_GOLD_DARK)
	bevel(thumb, 1, UI_GOLD_LIGHT, Color(0.2, 0.13, 0.05))


# Every newer version's notes, newest first, each under its version number.
func draw_notes() -> void:
	layout_notes()
	var top := -roundf(notes_scroll)
	for l: Array in notes_lines:
		var y: float = l[0] + top
		if y > notes_clip.size.y + 40.0 or y + 200.0 < 0.0:
			continue
		var s: String = l[3]
		if s == "-":
			# The thin gold line next to a version number
			ui_divider(l[1], l[1] + l[2], y)
		elif s == "•":
			var c := Vector2(l[1], y)
			quad(PackedVector2Array([c + Vector2(0, -3.5), c + Vector2(3.5, 0), c + Vector2(0, 3.5), c + Vector2(-3.5, 0)]), UI_GOLD)
		else:
			hud.draw_multiline_string(font, Vector2(l[1], y), s, HORIZONTAL_ALIGNMENT_LEFT, l[2], l[4], -1, l[5])
	# Soft edges where more text is hidden above or below
	var w := notes_clip.size.x
	var h := notes_clip.size.y
	var shade := Color(0.05, 0.05, 0.055)
	if notes_scroll > 1.0:
		vgrad(Rect2(0, 0, w, 18), shade, Color(shade, 0.0))
	if notes_scroll < notes_max() - 1.0:
		vgrad(Rect2(0, h - 18, w, 18), Color(shade, 0.0), shade)


# Works out where every line of the notes goes, once per set of notes.
func layout_notes() -> void:
	var key := update_version + str(update_changes.size()) + str(update_more)
	if key == notes_for:
		return
	notes_for = key
	notes_lines = []
	var x := NOTES_PAD
	var width := notes_clip.size.x - NOTES_PAD * 2.0 - NOTES_BAR_W - 6.0
	var y := 10.0
	var changes := update_changes
	if changes.is_empty():
		changes = [[update_version, update_notes]]
	for c: Array in changes:
		# The version number, with a gold line after it
		var tag := "v" + str(c[0]).trim_prefix("v")
		y += font.get_ascent(18)
		notes_lines.append([y, x, 0.0, tag, 18, UI_GOLD_LIGHT])
		var after := x + font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 10.0
		notes_lines.append([y - 6.0, after, x + width - after, "-", 0, UI_GOLD])
		y += font.get_descent(18) + 6.0
		var notes: String = c[1] if c[1] != "" else "No details for this update."
		for line in notes.split("\n"):
			# Bullets hang: the dot sits out on the left, the text lines up after it
			var indent := 0.0
			if line.begins_with("•"):
				line = line.trim_prefix("•").strip_edges()
				indent = 16.0
				notes_lines.append([y + font.get_ascent(15) * 0.6, x + 5.0, 0.0, "•", 0, UI_GOLD])
			var size := font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, width - indent, 15)
			notes_lines.append([y + font.get_ascent(15), x + indent, width - indent, line, 15, UI_TEXT])
			y += size.y + 4.0
		y += 12.0
	if update_more:
		y += font.get_ascent(15)
		notes_lines.append([y, x, width, "...and older updates (see all on GitHub)", 15, UI_DIM])
		y += font.get_descent(15) + 8.0
	notes_height = y


# How far the notes can scroll (0 when they fit).
func notes_max() -> float:
	return maxf(notes_height - notes_clip.size.y, 0.0)


func notes_track() -> Rect2:
	return Rect2(NOTES_RECT.end.x - NOTES_BAR_W - 8, NOTES_RECT.position.y + 8, NOTES_BAR_W, NOTES_RECT.size.y - 16)


func notes_thumb() -> Rect2:
	var track := notes_track()
	var h := maxf(track.size.y * notes_clip.size.y / maxf(notes_height, 1.0), 24.0)
	var y := track.position.y + (track.size.y - h) * (notes_scroll / maxf(notes_max(), 1.0))
	return Rect2(track.position.x, y, track.size.x, h)


# Every frame: shows the notes with the popup and glides them to where they're scrolled.
func update_notes_box() -> void:
	var open := update_dialog == "ask"
	if open and not notes_clip.visible:
		notes_scroll = 0.0
		notes_target = 0.0
	notes_clip.visible = open
	if not open:
		notes_drag = -1.0
		return
	layout_notes()
	notes_target = clampf(notes_target, 0.0, notes_max())
	notes_scroll = lerpf(notes_scroll, notes_target, minf(get_process_delta_time() * 16.0, 1.0))
	if absf(notes_scroll - notes_target) < 0.5:
		notes_scroll = notes_target
	notes_layer.queue_redraw()


# Scrolling the notes: mouse wheel, arrow keys, Page Up/Down, Home/End, or the scrollbar.
func _input(event: InputEvent) -> void:
	ui_click(event)
	if gift_input(event):
		get_viewport().set_input_as_handled()
		return
	# The Load list scrolls with the mouse wheel
	if load_open and menu_open and event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		load_top = clampi(load_top + step, 0, maxi(load_rows.size() - LOAD_ROWS, 0))
		get_viewport().set_input_as_handled()
		return
	if ach_open and menu_open and ach_input(event):
		get_viewport().set_input_as_handled()
		return
	if chron_open and menu_open and chron_input(event):
		get_viewport().set_input_as_handled()
		return
	# The leaderboard box: Left / Right switch the level's board
	if board_open and menu_open and event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		step_board_level(-1 if event.keycode == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()
		return
	if update_dialog != "ask" or notes_max() <= 0.0:
		return
	var max_y := notes_max()
	var page := notes_clip.size.y - 40.0
	var target := notes_target
	if event is InputEventMouseButton and event.pressed:
		var p := ui_mouse(true)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target -= NOTES_STEP
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target += NOTES_STEP
		elif event.button_index == MOUSE_BUTTON_LEFT and notes_track().grow_individual(4, 0, 4, 0).has_point(p):
			# Grab the handle where it was clicked, or jump it to the click
			var thumb := notes_thumb()
			notes_drag = p.y - thumb.position.y if thumb.has_point(p) else thumb.size.y / 2.0
			drag_notes(p.y)
			get_viewport().set_input_as_handled()
			return
		else:
			return
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		notes_drag = -1.0
		return
	elif event is InputEventMouseMotion and notes_drag >= 0.0:
		drag_notes(ui_mouse(true).y)
		return
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP: target -= NOTES_STEP
			KEY_DOWN: target += NOTES_STEP
			KEY_PAGEUP: target -= page
			KEY_PAGEDOWN: target += page
			KEY_HOME: target = 0.0
			KEY_END: target = max_y
			_: return
	else:
		return
	notes_target = clampf(target, 0.0, max_y)
	get_viewport().set_input_as_handled()


# Moves the notes so the scrollbar's handle sits under the mouse.
func drag_notes(mouse_y: float) -> void:
	var track := notes_track()
	var room := track.size.y - notes_thumb().size.y
	var f := clampf((mouse_y - notes_drag - track.position.y) / maxf(room, 1.0), 0.0, 1.0)
	notes_target = f * notes_max()
	notes_scroll = notes_target


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


const SOLDIER_BAR_W := 14.0  # a soldier's health bar (monsters' are wider)


func draw_health_bars() -> void:
	for e in enemies:
		# Only hurt monsters show a bar, like in Warcraft III, so big waves stay readable
		# (Grimwhistle always shows his, with his name over it)
		var grim := e.kind == "boss" and e.special == "conductor"
		if e.hp >= e.max_hp and not grim:
			continue
		# Just above the monster's model (its height is the 4th part of its look)
		var top: float = e.node.get_meta("mob")[3]
		var p := camera.unproject_position(e.node.position + Vector3(0, top + 0.08, 0))
		var w := e.radius * (3.4 if grim else 2.4)
		var bar := Vector2(p.x - w / 2.0, p.y)
		# Black edge so the bar reads on grass and path alike
		hud.draw_rect(Rect2(bar - Vector2(1, 1), Vector2(w + 2, 6)), Color(0, 0, 0, 0.85))
		hud.draw_rect(Rect2(bar, Vector2(w, 4)), Color(0.3, 0.04, 0.02))
		hud.draw_rect(Rect2(bar, Vector2(w * e.hp / e.max_hp, 4)), Color(0.2, 0.85, 0.2))
		if grim:
			hud.draw_rect(Rect2(bar - Vector2(2, 2), Vector2(w + 4, 8)), GRIM_COLOR, false, 1.0)
			outlined(Vector2(p.x, bar.y - 6.0), GRIM_NAME, 14, GRIM_COLOR.lightened(0.45))
	# Hurt Barracks soldiers (game_world.gd fills soldier_bars each frame): a
	# smaller bar in the owner's color
	for s: Array in soldier_bars:
		if camera.is_position_behind(s[0]):
			continue
		var p := camera.unproject_position(s[0])
		var bar := Vector2(p.x - SOLDIER_BAR_W / 2.0, p.y)
		hud.draw_rect(Rect2(bar - Vector2(1, 1), Vector2(SOLDIER_BAR_W + 2, 5)), Color(0, 0, 0, 0.85))
		hud.draw_rect(Rect2(bar, Vector2(SOLDIER_BAR_W, 3)), Color(0.18, 0.15, 0.12))
		hud.draw_rect(Rect2(bar, Vector2(SOLDIER_BAR_W * clampf(s[1], 0.0, 1.0), 3)), ink_of(s[2]))


func text(pos: Vector2, s: String, size := 16, col := Color.WHITE) -> void:
	hud.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


const DARK_INK := Color(0.7, 0.7, 0.76)  # Black players' names and bars: readable on dark stone


# A player's colour for text, lines and bars on the dark UI (Black shows as silver).
func ink_of(slot: int) -> Color:
	return DARK_INK if color_is_dark(slot) else color_of(slot)


# A dot in a player's colour; Black gets a light ring so it shows on dark stone.
func player_dot(c: Vector2, radius: float, slot: int) -> void:
	if color_is_dark(slot):
		hud.draw_circle(c, radius + 1.5, DARK_INK)
	hud.draw_circle(c, radius, color_of(slot))


# Big numbers made short: 9500, 24k, 240k, 1.2M, 3.4B, 5T, 7Qa (quadrillion), 2Qi (quintillion).
func short(n: float) -> String:
	if absf(n) < 10000.0:
		return str(int(n))
	for u: Array in [[1e18, "Qi"], [1e15, "Qa"], [1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "k"]]:
		if absf(n) >= u[0]:
			var v: float = n / u[0]
			if absf(v) < 10.0:
				return ("%.1f" % (floorf(v * 10.0) / 10.0)).trim_suffix(".0") + u[1]
			return str(int(v)) + u[1]
	return str(int(n))


# A gold amount: "950g", or short without the g when big ("240k", not "240kg").
func gold_text(n: float) -> String:
	return short(n) + ("g" if absf(n) < 10000.0 else "")


# Bonus gold for sending the next wave now (the same sum start_wave() pays).
func early_gold() -> int:
	return int(maxf(next_wave_timer, 0.0)) * maxi(1, int(wave_income(wave + 1) / WAVE_INTERVAL))


func button(r: Rect2, label: String, enabled := true, active := false) -> void:
	note_button(r, enabled)
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
	# The rest sits at the screen's bottom (see ui_extra)
	hud.draw_set_transform(Vector2(0, ui_extra))
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
	if tip >= 0 and tip < TOWER_TYPES.size():
		draw_tower_card(tip)
	elif tip >= 0:
		draw_card_tip(tip)
	else:
		var chip := hovered_chip()
		if chip >= 0:
			draw_chip_tip(chip)
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
	if wave < last_wave():
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
	x = resource(x, level_name(), 15, level_color(), "") + 8
	x = resource(x, wave_label(), 18, UI_TEXT, "wave")
	var alive_end := x
	x = resource(x, "%d / %d" % [alive_count(), max_alive()], 18, danger_color(), "alive")
	alive_spot = Vector2((x + 24 + alive_end) / 2.0, TOP_BAR_H)  # for the tip's arrow
	var gold_end := x
	resource(x, short(gold), 18, Color(1, 0.85, 0.3), "gold")
	if gift_glow > 0.0:
		draw_gift_glow(gold_end)
	if challenge_on() and state == "playing" and not menu_open:
		draw_daily_banner()
	if fest_name != "" and fest_t < FEST_SHOW and state == "playing" and not menu_open:
		draw_festival_banner(TOP_BAR_H + (48 if challenge_on() else 9))
	if held and state == "playing" and not menu_open:
		draw_held_line(TOP_BAR_H + (48 if challenge_on() else 9))


# "12 / 300", or "312 (endless)" after the last wave (no "/ 9999").
func wave_label() -> String:
	return "%d (endless)" % shown_wave() if endless else "%d / %d" % [shown_wave(), last_wave()]


func level_name() -> String:
	return DIFFICULTIES[difficulty]


func level_color() -> Color:
	return LEVEL_COLORS[difficulty]


# What the level changes, for the Esc menu's Level tooltip: one or two lines.
func level_tip() -> Array:
	var hp: float = DIFFICULTY_HP[difficulty]
	var lines := ["Monsters have normal health."]
	if hp != 1.0:
		lines = ["Monsters have %d%% %s health." % [roundi(absf(hp - 1.0) * 100.0), "more" if hp > 1.0 else "less"]]
	var g: float = DIFFICULTY_GOLD[difficulty]
	if g != 1.0:
		lines.append("You start with %d%% %s gold." % [roundi(absf(g - 1.0) * 100.0), "more" if g > 1.0 else "less"])
	return lines


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
			var gr := Rect2(m.position + Vector2(gate_cells[g]) * k, Vector2(k, k)).grow(1)
			if color_is_dark(g):
				hud.draw_rect(gr.grow(1), DARK_INK)
			hud.draw_rect(gr, color_of(g))
	for t: Tower in towers.values():
		var r := Rect2(m.position + Vector2(t.cell) * k, Vector2(k, k)).grow(-1)
		hud.draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
		hud.draw_rect(r, TOWERS[t.type]["color"])
	var monster := Color(1, 0.22, 0.15)
	for e in enemies:
		var p := m.position + e.pos / CELL * k
		var h := maxf(1.5, e.radius / CELL * k * 0.8)
		hud.draw_rect(Rect2(p - Vector2(h, h), Vector2(h, h) * 2), monster)
	# Pings: a pulsing ring in the player's color
	for g: Array in pings:
		var c: Vector2 = (m.position + g[1] / CELL * k).clamp(m.position, m.end)
		var age: float = PING_TIME - g[2]
		var col: Color = ink_of(g[0])
		var a := clampf(g[2] / 0.5, 0.0, 1.0)
		hud.draw_circle(c, 3.0, Color(col, a))
		hud.draw_arc(c, 4.0 + fmod(age, 1.0) * 8.0, 0, TAU, 16, Color(col, a * (1.0 - fmod(age, 1.0))), 1.5)
	if selected != null:
		hud.draw_rect(Rect2(m.position + Vector2(selected.cell) * k, Vector2(k, k)).grow(2), UI_GOLD_LIGHT, false, 1.5)
	# What the camera sees, cut to the small map
	var view := PackedVector2Array()
	var low := BAR_TOP + ui_extra
	for s: Vector2 in [Vector2(0, TOP_BAR_H), Vector2(SCREEN_W, TOP_BAR_H), Vector2(SCREEN_W, low), Vector2(0, low)]:
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
	if endless or replaying():
		# "WAVE 312" with a small red "ENDLESS" (or "REPLAY") after it
		var title := "WAVE %d" % shown_wave()
		var tag := "REPLAY" if replaying() else "ENDLESS"
		ui_title(Rect2(x - 14, BAR_TOP + 10, 236, 36), Vector2(x, BAR_TOP + 40), title, 24)
		var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		hud.draw_string(font, Vector2(x + tw + 7, BAR_TOP + 39), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.8))
		text(Vector2(x + tw + 6, BAR_TOP + 38), tag, 12, Color(1.0, 0.45, 0.3))
	else:
		ui_title(Rect2(x - 14, BAR_TOP + 10, 236, 36), Vector2(x, BAR_TOP + 40), "WAVE %d / %d" % [wave, last_wave()], 24)
	draw_wave_preview(x)
	text(Vector2(x, BAR_TOP + 98), "Alive: %d / %d" % [alive_count(), max_alive()], 17, danger_color())
	ui_bar(Rect2(x, BAR_TOP + 108, 112, 6), danger(), danger_color())
	draw_ability_buttons()
	if net_mode == "host" or net_mode == "client":
		# A dot per player in their color; yours has a ring. Another player's dot
		# under the mouse lights up: a click opens the gift box.
		var dots := player_dots()
		var hover := hovered_dot()
		for d: Array in dots:
			var slot: int = d[0]
			var c: Vector2 = d[1]
			if slot == hover:
				hud.draw_circle(c, 10, Color(UI_GOLD_LIGHT, 0.35))
			player_dot(c, 6, slot)
			if slot == local_slot:
				hud.draw_arc(c, 9, 0, TAU, 20, UI_GOLD_LIGHT, 1.5)
		var px: float = x + dots.size() * 22
		if hover >= 0:
			text(Vector2(px + 4, BAR_TOP + 145), "Give gold to %s" % name_of(hover), 14, UI_GOLD_LIGHT)
		else:
			text(Vector2(px + 4, BAR_TOP + 145), "You: %s" % name_of(local_slot), 14, ink_of(local_slot))
	else:
		text(Vector2(x, BAR_TOP + 145), build_keys_hint, 13, UI_DIM)


var build_keys_hint := "Build: keys 1-%d   Upgrade: U   Sell: X" % TOWER_TYPES.size()


# ----- abilities: two square buttons right of the Alive bar

func ability_button_rect(i: int) -> Rect2:
	return Rect2(INFO_X + 126 + i * 46, BAR_TOP + 84, 40, 40)


# Each button: its icon, its key, and while it cools down a dark sweep that
# shrinks clockwise (like Warcraft III) with the seconds left.
func draw_ability_buttons() -> void:
	for i in ABILITY_ORDER.size():
		var a: String = ABILITY_ORDER[i]
		var r := ability_button_rect(i)
		var left := ability_left(local_slot, a)
		var usable := state == "playing" and wave > 0
		ui_button_bg(r, usable, aiming == a)
		var c := r.get_center() + Vector2(0, 1)
		if a == "meteor":
			icon_meteor(c, usable)
		else:
			icon_freeze(c, usable)
		if left > 0.0:
			cooldown_sweep(r.grow(-2), clampf(left / ABILITIES[a]["cooldown"], 0.0, 1.0))
			outlined(c + Vector2(0, 6), str(ceili(left)), 15, UI_TEXT)
		elif usable:
			# Ready: a soft gold glow around the edge
			var glow := 0.35 + 0.25 * sin(Time.get_ticks_msec() / 300.0 + i)
			hud.draw_rect(r.grow(1), Color(UI_GOLD_LIGHT, glow), false, 1.5)
		hud.draw_string(font, r.position + Vector2(4, 13), ABILITIES[a]["key"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.9))
		text(r.position + Vector2(3, 12), ABILITIES[a]["key"], 11, UI_GOLD_LIGHT if usable else UI_DIM)


# A dark pie over r for the part of the cooldown still to wait (left: 1 to 0).
func cooldown_sweep(r: Rect2, left: float) -> void:
	var c := r.get_center()
	var reach := r.size.length()
	var pie := PackedVector2Array([c])
	var steps := maxi(ceili(left * 32.0), 1)
	for k in steps + 1:
		var ang := -PI / 2.0 - TAU * left * k / steps
		pie.append(c + Vector2(cos(ang), sin(ang)) * reach)
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for poly: PackedVector2Array in Geometry2D.intersect_polygons(pie, box):
		hud.draw_colored_polygon(poly, Color(0, 0, 0, 0.62))


# A burning rock with its flame tail, falling down to the left.
func icon_meteor(c: Vector2, lit: bool) -> void:
	var a := 1.0 if lit else 0.4
	var head := c + Vector2(-4, 4)
	var back := Vector2(0.72, -0.69)
	var side := Vector2(-back.y, back.x)
	hud.draw_circle(head, 10.0, Color(1.0, 0.45, 0.1, 0.22 * a))
	quad(PackedVector2Array([head + side * 7.0, head + back * 22.0, head + back * 22.0, head - side * 7.0]), Color(0.95, 0.35, 0.08, 0.8 * a))
	quad(PackedVector2Array([head + side * 4.5, head + back * 15.0 + side * 1.5, head + back * 15.0 - side * 1.5, head - side * 4.5]), Color(1.0, 0.75, 0.25, 0.9 * a))
	hud.draw_circle(head, 6.5, Color(0.12, 0.06, 0.03, a))
	hud.draw_circle(head, 5.3, Color(0.5, 0.22, 0.09, a))
	hud.draw_circle(head + Vector2(1.2, -1.2), 3.0, Color(1.0, 0.6, 0.2, a))
	hud.draw_circle(head + Vector2(1.8, -1.8), 1.4, Color(1.0, 0.95, 0.7, a))


# A snowflake: three bars with little Vs near their ends.
func icon_freeze(c: Vector2, lit: bool) -> void:
	var col := Color(0.72, 0.9, 1.0) if lit else Color(0.42, 0.48, 0.52)
	hud.draw_circle(c, 13.0, Color(0.35, 0.65, 1.0, 0.18 if lit else 0.0))
	for pass_i in 2:
		var w := 4.0 if pass_i == 0 else 2.0
		var pc := Color(0, 0, 0, 0.6) if pass_i == 0 else col
		for k in 6:
			var ang := k * TAU / 6.0 - PI / 2.0
			var d := Vector2(cos(ang), sin(ang))
			var n := Vector2(-d.y, d.x)
			hud.draw_line(c, c + d * 12.0, pc, w)
			var m := c + d * 7.5
			hud.draw_line(m, m + (d - n) * 3.5, pc, w)
			hud.draw_line(m, m + (d + n) * 3.5, pc, w)
	hud.draw_circle(c, 2.5, Color(1, 1, 1, 0.9) if lit else col)


# ----- wave preview: the next 3 waves under the wave title

# Each monster kind's color in the preview (like its old look).
const KIND_COLORS := {"normal": Color(0.95, 0.5, 0.6), "fast": Color(1.0, 0.9, 0.3),
		"armored": Color(0.6, 0.65, 0.75), "boss": Color(0.95, 0.2, 0.15)}


# The countdown at the title's right end, then a chip per wave: the monster
# kind and how many come (all gates together). Every player sees the same: it's
# all worked out from the wave number, which comes with the host's updates.
func draw_wave_preview(x: float) -> void:
	chip_spots.clear()
	if state != "playing":
		return
	var right := x + 208.0
	# Before wave 1 there's no countdown: the first wave comes with Space
	if wave > 0 and wave < last_wave():
		var timer := "%ds" % ceili(next_wave_timer)
		var tw := font.get_string_size(timer, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		text(Vector2(right - tw, BAR_TOP + 38), timer, 14, UI_GREY)
	if wave >= last_wave():
		text(Vector2(x, BAR_TOP + 70), "Last wave! Kill them all", 15, UI_GREY)
		return
	var cx := x
	for i in 3:
		var n := wave + 1 + i
		if n > last_wave():
			break
		var label := wave_chip_label(n)
		var w := 32.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if cx + w > right + 4.0:
			break  # no room for a third wide chip
		wave_chip(Rect2(cx, BAR_TOP + 54, w, 22), n, label)
		chip_spots.append([Rect2(cx, BAR_TOP + 54, w, 22), n])
		# The next wave's countdown as a thin gold bar under its chip
		if i == 0 and wave > 0:
			hud.draw_rect(Rect2(cx, BAR_TOP + 79, w * clampf(next_wave_timer / WAVE_INTERVAL, 0.0, 1.0), 2), UI_GOLD)
		cx += w + 5.0


func wave_chip_label(n: int) -> String:
	if grimwhistle_wave(n):
		return "GRIMWHISTLE"
	var count := wave_count(n) * maxi(player_count(), 1)
	return ("BOSS x%d" if kind_for_wave(n) == "boss" else "x%d") % count


const GRIM_COLOR := Color(0.62, 0.38, 0.9)  # Grimwhistle's purple: his chip and name bar


func wave_chip(r: Rect2, n: int, label: String) -> void:
	var kind := kind_for_wave(n)
	var boss := kind == "boss"
	var grim := grimwhistle_wave(n)
	var col: Color = GRIM_COLOR if grim else KIND_COLORS[kind]
	ui_button_bg(r, true, boss)
	hud.draw_rect(r.grow(-2), Color(col, 0.22 if grim else 0.16))
	if boss:
		# A boss wave blinks red (Grimwhistle's purple)
		var a := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 160.0)
		hud.draw_rect(r.grow(2), Color(GRIM_COLOR.lightened(0.2), a) if grim else Color(1, 0.3, 0.2, a), false, 2.0)
	kind_icon(r.position + Vector2(13, r.size.y / 2.0 + 1), kind, 7.0)
	var label_col := Color(1, 0.55, 0.45) if boss else UI_TEXT
	if grim:
		label_col = GRIM_COLOR.lightened(0.5)
	text(r.position + Vector2(25, r.size.y / 2.0 + 5), label, 13, label_col)
	var special := wave_special(n)
	if special != "":
		special_badge(Vector2(r.end.x - 1, r.position.y), special)


# ----- special waves: a round badge on the wave's chip, and a tip on hover

var chip_spots := []  # the wave chips drawn this frame: [rect (console pixels), wave]
const SPECIAL_COLORS := {"split": Color(1.0, 0.6, 0.25), "shield": Color(0.5, 0.78, 1.0), "heal": Color(0.45, 0.95, 0.45)}


# A small gold-rimmed coin with the special's mark: two blobs (split), a shield, or a cross (heal).
func special_badge(c: Vector2, special: String) -> void:
	var col: Color = SPECIAL_COLORS[special]
	hud.draw_circle(c, 9.0, Color(0, 0, 0, 0.8))
	hud.draw_circle(c, 8.0, UI_GOLD)
	hud.draw_circle(c, 6.5, col.darkened(0.55))
	match special:
		"split":
			hud.draw_circle(c + Vector2(-2.2, 1.0), 2.6, col)
			hud.draw_circle(c + Vector2(2.4, -1.2), 2.6, col)
		"shield":
			var pts := PackedVector2Array([c + Vector2(-4, -4), c + Vector2(4, -4), c + Vector2(4, 0.5), c + Vector2(0, 4.5), c + Vector2(-4, 0.5)])
			hud.draw_colored_polygon(pts, col)
		"heal":
			hud.draw_rect(Rect2(c - Vector2(1.5, 4.5), Vector2(3, 9)), col)
			hud.draw_rect(Rect2(c - Vector2(4.5, 1.5), Vector2(9, 3)), col)


# The name and what it does, for the tip: [name, lines].
func special_info(special: String) -> Array:
	match special:
		"split":
			return ["Splitters", ["Each monster breaks into 2 smaller, faster ones when killed."]]
		"shield":
			return ["Shields", ["A shield takes the hits first: %d%% of its health (bosses %d%%)." % [roundi(SHIELD_SHARE * 100), roundi(SHIELD_BOSS * 100)],
					"It grows back after %ss without being hit." % str(SHIELD_REGROW).trim_suffix(".0")]]
		"heal":
			return ["Healers", ["Every %dth monster is a healer: every %ss it heals" % [HEALER_EVERY, str(HEAL_EVERY).trim_suffix(".0")],
					"the monsters near it by %d%% of their health (bosses less)." % roundi(HEAL_SHARE * 100)]]
	return ["", []]


# The wave chip under the mouse (its wave), or -1.
func hovered_chip() -> int:
	if menu_open or update_dialog != "" or gift_to >= 0:
		return -1
	var p := ui_mouse()
	for s: Array in chip_spots:
		if s[0].grow(2).has_point(p):
			return s[1]
	return -1


# Over the wave preview: the wave's monsters, and its special if it has one.
func draw_chip_tip(n: int) -> void:
	var kind := kind_for_wave(n)
	var count := wave_count(n) * maxi(player_count(), 1)
	var lines := ["%d %s monster%s." % [count, kind, "" if count == 1 else "s"]]
	if player_count() > 1:
		lines[0] = "%d %s monster%s (%d from each gate)." % [count, kind, "" if count == 1 else "s", wave_count(n)]
	var title := "Wave %d" % n
	var col := Color(1, 0.85, 0.3)
	if grimwhistle_wave(n):
		var mages := maxi(wave_count(n) - 1, 0)
		lines = ["%s and %d bone mage%s, from each gate." % [GRIM_NAME, mages, "" if mages == 1 else "s"],
				"His Crescendo frees the monsters near him from slows and holds.",
				"When he falls, the rest crumble and the Ring is won."]
		title += ":  Grimwhistle"
		col = GRIM_COLOR.lightened(0.3)
	var special := wave_special(n)
	if special != "":
		var info := special_info(special)
		title += ":  " + info[0]
		col = SPECIAL_COLORS[special]
		lines.append_array(info[1])
	tip_box(INFO_X - 12, 440, title, col, lines)


# A monster blob in its kind's color with the kind's mark: speed lines (fast),
# a steel rim (armored) or a crown (boss).
func kind_icon(c: Vector2, kind: String, r: float) -> void:
	var col: Color = KIND_COLORS[kind]
	if kind == "fast":
		for k in 3:
			hud.draw_line(c + Vector2(-r - 7, -3 + k * 3), c + Vector2(-r - 2, -3 + k * 3), col, 1.5)
	hud.draw_circle(c, r + 1.0, Color(0, 0, 0, 0.75))
	hud.draw_circle(c, r, col.darkened(0.4))
	hud.draw_circle(c + Vector2(0, -1), r - 2.0, col)
	if kind == "armored":
		hud.draw_arc(c, r - 1.0, PI * 1.05, PI * 1.95, 10, Color(0.85, 0.9, 1.0), 2.5)
	if kind == "boss":
		quad(PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.55), c + Vector2(-r * 0.8, -r * 1.35), c + Vector2(0, -r * 0.8), c + Vector2(0, -r * 0.55)]), UI_GOLD_LIGHT)
		quad(PackedVector2Array([c + Vector2(0, -r * 0.55), c + Vector2(0, -r * 0.8), c + Vector2(r * 0.8, -r * 1.35), c + Vector2(r * 0.8, -r * 0.55)]), UI_GOLD_LIGHT)
	hud.draw_circle(c + Vector2(-r * 0.35, 0), 1.6, Color(0.1, 0.05, 0.05))
	hud.draw_circle(c + Vector2(r * 0.35, 0), 1.6, Color(0.1, 0.05, 0.05))


# The selected tower: its picture, level and stats.
func draw_selected() -> void:
	var lv := selected.level
	var data := tower_data(selected.type, selected.path, lv)
	# The next level's numbers (the same path; before level 5 the plain ones)
	var after := tower_data(selected.type, selected.path, lv + 1)
	hud.draw_texture_rect(portrait_view.get_texture(), PORTRAIT_RECT, false)
	inner_shadow(PORTRAIT_RECT, 6, 0.4)
	var x := float(STATS_X)
	text(Vector2(x, BAR_TOP + 42), "%s Tower" % data["name"], 22, data["color"])
	# A gold diamond per level up to 4, filled up to this one. After 4: one diamond and the number.
	if lv <= 3:
		for i in 4:
			var c := Vector2(x + 7 + i * 17, BAR_TOP + 59)
			diamond(c, 6.0, UI_GOLD_DARK)
			diamond(c, 4.5, data["color"] if i <= lv else Color(0.08, 0.08, 0.08))
		text(Vector2(x + 78, BAR_TOP + 64), "Level %d" % (lv + 1), 15, UI_TEXT)
	else:
		var c := Vector2(x + 7, BAR_TOP + 59)
		diamond(c, 7.0, UI_GOLD_DARK)
		diamond(c, 5.5, data["color"])
		text(Vector2(x + 20, BAR_TOP + 65), "Level %d" % (lv + 1), 17, UI_GOLD_LIGHT)
	var mine := selected.owner == local_slot
	# Before level 5 the next level depends on the path, so no "> next" then
	var next := lv < MAX_LEVEL - 1 and mine and not needs_path(selected)
	var right := x + 196
	if data.has("cloud"):
		# Poison: damage a second to all in the cloud, the cloud's size and how long it lasts
		stat_row(Vector2(x, BAR_TOP + 92), "Damage", short(data["damage"][lv]) + "/s", short(after["damage"][lv + 1]) + "/s" if next else "")
		stat_row(Vector2(x, BAR_TOP + 110), "Range", "%d" % data["range"][lv], "%d" % after["range"][lv + 1] if next else "")
		stat_row(Vector2(x, BAR_TOP + 128), "Cloud", "%d" % data["cloud"][lv], "%d" % after["cloud"][lv + 1] if next else "")
		stat_row(Vector2(x, BAR_TOP + 146), "Speed", "%.2fs" % data["cooldown"][lv], "")
		text(Vector2(right, BAR_TOP + 96), "Clouds last %ss" % str(cloud_time(selected.path, lv)).trim_suffix(".0"), 14, UI_GREY)
		var weak := cloud_weaken(selected.path, lv)
		var boss := boss_bonus(selected.type, selected.path, lv)
		if weak > 0.0:
			text(Vector2(right, BAR_TOP + 114), "Inside: +%d%% damage" % roundi(weak * 100.0), 14, Color(0.6, 0.95, 0.4))
		elif boss > 1.0:
			text(Vector2(right, BAR_TOP + 114), "x%s damage to bosses" % str(boss).trim_suffix(".0"), 14, Color(0.6, 0.95, 0.4))
		else:
			text(Vector2(right, BAR_TOP + 114), "Goes through armor", 14, UI_GREY)
	elif data.has("soldiers"):
		# Barracks: damage of each soldier's hit, soldiers standing now (from
		# soldier_look, which every computer has), their health and hold time
		var total: int = data["soldiers"][lv]
		var up := 0
		for b in selected.soldier_look:
			if b & 127 > 0:
				up += 1
		up = mini(up, total)
		stat_row(Vector2(x, BAR_TOP + 92), "Damage", short(data["damage"][lv]), short(after["damage"][lv + 1]) if next else "")
		stat_row(Vector2(x, BAR_TOP + 110), "Soldiers", "%d / %d" % [up, total], "%d" % after["soldiers"][lv + 1] if next and after["soldiers"][lv + 1] != total else "")
		stat_row(Vector2(x, BAR_TOP + 128), "Health", num(data["soldier_hp"][lv], true), num(after["soldier_hp"][lv + 1], true) if next else "")
		stat_row(Vector2(x, BAR_TOP + 146), "Hold", num(data["hold"][lv]) + "s", num(after["hold"][lv + 1]) + "s" if next else "")
		text(Vector2(right, BAR_TOP + 96), "Respawn %ss" % num(data["respawn"][lv], true), 14, UI_GREY)
		var boss := boss_bonus(selected.type, selected.path, lv)
		if selected.path == 1 and lv >= PATH_LEVEL:
			text(Vector2(right, BAR_TOP + 114), "Holds bosses (x%s)" % num(boss), 14, Color(0.6, 0.95, 0.4))
		elif selected.path == 2 and lv >= PATH_LEVEL:
			text(Vector2(right, BAR_TOP + 114), "Wide reach, no bosses", 14, UI_GREY)
		else:
			text(Vector2(right, BAR_TOP + 114), "Can't hold bosses", 14, UI_GREY)
	else:
		stat_row(Vector2(x, BAR_TOP + 96), "Damage", short(data["damage"][lv]), short(after["damage"][lv + 1]) if next else "")
		stat_row(Vector2(x, BAR_TOP + 118), "Range", "%d" % data["range"][lv], "%d" % after["range"][lv + 1] if next else "")
		stat_row(Vector2(x, BAR_TOP + 140), "Speed", "%.2fs" % data["cooldown"][lv], "")
		hud.draw_multiline_string(font, Vector2(right, BAR_TOP + 96), data["desc"], HORIZONTAL_ALIGNMENT_LEFT, 130, 14, 2, UI_GREY)
	if not mine:
		text(Vector2(right, BAR_TOP + 140), "Built by %s" % name_of(selected.owner), 14, ink_of(selected.owner))
	elif lv >= MAX_LEVEL - 1:
		text(Vector2(right, BAR_TOP + 140), "Max level", 14, UI_GOLD_LIGHT)
	elif needs_path(selected):
		text(Vector2(right, BAR_TOP + 140), "Next: pick a path (Q / E)", 14, UI_GOLD_LIGHT)
	# Targeting mode: a plain text button (placeholder until it gets an icon).
	# Not for a Barracks: its soldiers fight the nearest monster.
	if not has_target_button(selected):
		return
	ui_button_bg(MODE_RECT, mine, false)
	text(MODE_RECT.position + Vector2(5, 16), "T", 11, UI_GOLD_LIGHT if mine else UI_DIM)
	text(MODE_RECT.position + Vector2(20, 17), "Target: " + TARGET_MODES[selected.mode], 14, UI_TEXT if mine else UI_DIM)


# Can this tower type be built in the challenge being played? ("Two towers"; always outside one.)
func twist_allows(type: String) -> bool:
	var rules := challenge_rules()
	return rules.is_empty() or type in rules.get("towers", TOWER_TYPES)


# Does this tower's panel have the Target button? (A Barracks doesn't.)
func has_target_button(t: Tower) -> bool:
	return t != null and t.type != "barracks"


# A small number with up to 2 decimals (1 with one_place) and no trailing zeros: 1.5, 2.25, 8.
func num(v: float, one_place := false) -> String:
	var s := ("%.1f" if one_place else "%.2f") % v
	return s.rstrip("0").trim_suffix(".")


# "Damage  120  > 250": the value now and, in green, after the next upgrade.
func stat_row(pos: Vector2, label: String, now: String, after: String) -> void:
	text(pos, label, 14, UI_DIM)
	text(pos + Vector2(64, 0), now, 16, UI_TEXT)
	if after != "":
		text(pos + Vector2(110, 0), "> " + after, 15, Color(0.6, 0.9, 0.6))


# The build list's line for towers whose own text is too long for it.
const BUILD_BLURBS := {"poison": "Clouds hurt all inside", "barracks": "Soldiers hold monsters"}
# The build list's rows: 17 apart, so 6 towers and the hint fit under the heading
const BUILD_ROW_H := 17


# Nothing selected: the towers with their price and what they do.
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
		var y := BAR_TOP + 57 + i * BUILD_ROW_H
		var affordable: bool = gold >= data["cost"][0] and twist_allows(type)
		if build_type == type:
			hud.draw_rect(build_row_rect(i), Color(1, 0.85, 0.3, 0.15))
		gem(Vector2(x + 6, y - 5), 4.5, data["color"])
		text(Vector2(x + 18, y), data["name"], 15, UI_TEXT if affordable else UI_DIM)
		text(Vector2(x + 88, y), gold_text(data["cost"][0]), 14, Color(1, 0.85, 0.3) if affordable else Color(0.6, 0.4, 0.3))
		text(Vector2(x + 132, y), BUILD_BLURBS.get(type, data["desc"]), 14, UI_GREY)
	var hint := "Click the map to build. Right-click: cancel" if build_type != "" else "Click a tower to upgrade or sell it."
	text(Vector2(x, BAR_TOP + 160), hint, 13, UI_DIM)


# A tower's row in the build list (console pixels).
func build_row_rect(i: int) -> Rect2:
	return Rect2(STATS_X - 6, BAR_TOP + 57 - 14 + i * BUILD_ROW_H, 330, BUILD_ROW_H)


# ---- Command card: square buttons with hotkeys

# The build buttons share the top row of the card: up to 5 side by side, more
# in 2 short rows (6 towers: 2 rows of 3, see draw_build_chip()).
const TOWER_BUTTON_GAP := 5.0
const TOWER_ROW_GAP := 4.0


func tower_button_rect(i: int) -> Rect2:
	var n := TOWER_TYPES.size()
	var row := CARD_SIZE * 4 + CARD_GAP * 3
	if n <= 5:
		var w := floorf((row - TOWER_BUTTON_GAP * (n - 1)) / n)
		return Rect2(CARD_X + i * (w + TOWER_BUTTON_GAP), CARD_Y, w, CARD_SIZE)
	var per := ceili(n / 2.0)
	var cw := floorf((row - TOWER_BUTTON_GAP * (per - 1)) / per)
	var h := floorf((CARD_SIZE - TOWER_ROW_GAP) / 2.0)
	return Rect2(CARD_X + (i % per) * (cw + TOWER_BUTTON_GAP), CARD_Y + (i / per) * (h + TOWER_ROW_GAP), cw, h)


# What hovered_card() returns besides a tower's index (0 and up)
const CARD_UPGRADE := 100
const CARD_SELL := 101
const CARD_WAVE := 102
const CARD_SPEED := 103
const CARD_MODE := 104  # the targeting mode button in the tower panel
const CARD_PATH := 110  # + 0 or 1: the 2 path buttons
const CARD_ABILITY := 120  # + the index in ABILITY_ORDER


# The command button under the mouse (a tower index or a CARD_ value), or -1.
func hovered_card() -> int:
	if menu_open or update_dialog != "":
		return -1
	var p := ui_mouse()
	# The 2 path buttons over the build row (a level 4 tower of yours selected)
	if picking_path():
		for i in 2:
			if PATH_RECTS[i].has_point(p):
				return CARD_PATH + i
	else:
		for i in TOWER_TYPES.size():
			if tower_button_rect(i).has_point(p):
				return i
	# The build list's rows show the same card as the buttons
	if selected == null and asks.is_empty():
		for i in TOWER_TYPES.size():
			if build_row_rect(i).has_point(p):
				return i
	var others := [UPGRADE_RECT, SELL_RECT, WAVE_RECT, SPEED_RECT]
	for i in others.size():
		if others[i].has_point(p):
			return CARD_UPGRADE + i
	if has_target_button(selected) and asks.is_empty() and MODE_RECT.has_point(p):
		return CARD_MODE
	for i in ABILITY_ORDER.size():
		if ability_button_rect(i).has_point(p):
			return CARD_ABILITY + i
	return -1


func draw_command_card() -> void:
	if picking_path():
		draw_path_buttons()
	else:
		for i in TOWER_TYPES.size():
			var data: Dictionary = TOWERS[TOWER_TYPES[i]]
			var r := tower_button_rect(i)
			var allowed := twist_allows(TOWER_TYPES[i])
			var affordable: bool = gold >= data["cost"][0] and allowed
			if r.size.y < CARD_SIZE:
				draw_build_chip(r, i, data, affordable)
				continue
			card_button(r, str(i + 1), data["name"], gold_text(data["cost"][0]), allowed, build_type == TOWER_TYPES[i], affordable)
			gem(r.get_center() + Vector2(0, -2), 11.0, data["color"] if affordable else data["color"].darkened(0.4))
	# Upgrade and Sell only work on your own selected tower (Sell not in a no-selling challenge)
	var mine := selected != null and selected.owner == local_slot
	var can_sell: bool = mine and not challenge_rules().get("no_sell", false)
	var up_label := "Upgrade"
	var up_cost := ""
	var can_up := false
	if mine and selected.level < MAX_LEVEL - 1:
		var cost: int = TOWERS[selected.type]["cost"][selected.level + 1]
		up_cost = gold_text(cost)
		can_up = gold >= cost
	elif mine:
		up_label = "Max"
	if picking_path():
		up_label = "Q or E"  # level 5 picks a path: the 2 buttons above
	card_button(UPGRADE_RECT, "U", up_label, up_cost, can_up, false, can_up)
	icon_upgrade(UPGRADE_RECT.get_center() + Vector2(0, -2), UI_GOLD_LIGHT if can_up else UI_DIM)
	card_button(SELL_RECT, "X", "Sell", "+" + gold_text(selected.spent * 0.7) if can_sell else "", can_sell, false, true)
	icon_coin(SELL_RECT.get_center() + Vector2(0, -2), 10.0, can_sell)
	var w := wave_button()
	var can_wave := wave < last_wave() and state == "playing" and monsters_left_to_spawn() == 0
	card_button(WAVE_RECT, "Space", w[0], w[1], can_wave, local_slot in wave_votes, true)
	icon_flag(WAVE_RECT.get_center() + Vector2(0, -2), 12.0, can_wave)
	card_button(SPEED_RECT, "F", "x%d" % game_speed, "", net_mode != "client", game_speed > 1, true)
	icon_speed(SPEED_RECT.get_center() + Vector2(0, -2), UI_GOLD_LIGHT if net_mode != "client" else UI_DIM)


# The selected level 4 tower's 2 paths, as wide buttons over the build row: hotkey,
# price, name and a short line. Placeholder look (a gem with the path's number)
# until the graphics get path icons.
func draw_path_buttons() -> void:
	var cost: int = TOWERS[selected.type]["cost"][selected.level + 1]
	var affordable := gold >= cost
	var col: Color = TOWERS[selected.type]["color"]
	for i in 2:
		var r: Rect2 = PATH_RECTS[i]
		var p: Dictionary = PATHS[selected.type][i]
		card_button(r, "Q" if i == 0 else "E", p["name"], gold_text(cost), true, false, affordable)
		gem(r.position + Vector2(17, 32), 9.0, col if affordable else col.darkened(0.4))
		text(r.position + Vector2(14, 36), str(i + 1), 11, Color(0, 0, 0, 0.8))
		hud.draw_multiline_string(font, r.position + Vector2(32, 27), p["desc"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36, 10, 2, UI_GREY)


# What a path does besides its numbers: one or two lines (split by "\n").
func path_extra(type: String, path: int) -> String:
	var p: Dictionary = PATHS[type][path - 1]
	var d := tower_data(type, path, PATH_LEVEL)
	var boss := "\nx%s damage to bosses." % str(p["boss"]).trim_suffix(".0") if p.has("boss") else ""
	match p["name"]:
		"Sniper": return "Faster arrows. Starts on Strongest." + boss
		"Volley": return "%d arrows (%d at level 20, %d at level 40)." % p["arrows"]
		"Big Bomb": return "Blast radius %d (Cannon: %d)." % [d["splash"][PATH_LEVEL], TOWERS[type]["splash"][PATH_LEVEL]] + boss
		"Cluster": return "%d bomblets (%d at level 20, %d at level 40).\nEach monster is hit only once." % p["bomblets"]
		"Deep Freeze": return "Freezes %ss: %d%% chance (%d%% at 20, %d%% at 40).\nThen it can't be frozen for %ss." % [str(FREEZE_TIME).trim_suffix(".0"), roundi(p["freeze"][0] * 100), roundi(p["freeze"][1] * 100), roundi(p["freeze"][2] * 100), str(FREEZE_IMMUNE).trim_suffix(".0")]
		"Blizzard": return "Hits all within %d (%d at level 20, %d at level 40)." % p["area"]
		"Storm": return "Chains to %d monsters, jumps further." % d["chain"][PATH_LEVEL]
		"Overload": return "Chains to %d monsters. Starts on Strongest." % d["chain"][PATH_LEVEL] + boss
		"Venom": return "Cloud size %d (Poison: %d). Starts on Strongest." % [d["cloud"][PATH_LEVEL], TOWERS[type]["cloud"][PATH_LEVEL]] + boss
		"Miasma": return "Cloud size %d (Poison: %d), lasts %ss.\nInside: +%d%% damage taken (%d%% at level 20, %d%% at 40)." % [d["cloud"][PATH_LEVEL],
				TOWERS[type]["cloud"][PATH_LEVEL], str(cloud_time(path, PATH_LEVEL)).trim_suffix(".0"),
				roundi(p["weaken"][0] * 100), roundi(p["weaken"][1] * 100), roundi(p["weaken"][2] * 100)]
		"Knights": return "Soldier health x%s, hold x%s. Holds bosses too." % [num(p["soldier_hp"]), num(p["hold"])] + boss
		"Militia": return "+%d soldiers (+%d at level 20, +%d at 40), back %sx as fast.\nReach x%s. Never holds bosses." % [p["soldiers_add"][0],
				p["soldiers_add"][1], p["soldiers_add"][2], num(1.0 / p["respawn"]), num(p["reach"])]
	return ""


# Seconds a poison tower's clouds last at a level (Miasma's longer): cloud_seconds() is in main.gd.
func cloud_time(path: int, level: int) -> float:
	return float(call("cloud_seconds", path, level))


# Miasma: the extra damage monsters in its clouds take (0.2: +20%), or 0.
func cloud_weaken(path: int, level: int) -> float:
	if path != 2 or level < PATH_LEVEL:
		return 0.0
	return path_step(level, PATHS["poison"][1]["weaken"])


# Short label and corner text for the wave button: [label, corner].
func wave_button() -> Array:
	if wave == 0:
		return ["Start", ""]
	if wave < last_wave() and monsters_left_to_spawn() > 0:
		return ["%d left" % monsters_left_to_spawn(), ""]
	var bonus := "+" + gold_text(early_gold())
	var votes := "%d/%d" % [wave_votes.size(), votes_needed()]
	if wave < last_wave() and player_count() > 1:
		return ["Voted " + votes, ""] if local_slot in wave_votes else ["Vote " + votes, bonus]
	if wave < last_wave():
		return ["Send", bonus]
	return ["Done", ""]


# The full wave button text, as the side panel used to show it.
func wave_tip() -> String:
	if wave == 0:
		return "Start the first wave (SPACE)"
	if wave < last_wave() and monsters_left_to_spawn() > 0:
		return "Spawning... (%d left)" % monsters_left_to_spawn()
	var votes := "%d/%d" % [wave_votes.size(), votes_needed()]
	if wave < last_wave() and player_count() > 1:
		if local_slot in wave_votes:
			return "Voted %s (SPACE: undo)" % votes
		return "Vote to send it now: +%s gold each, %s (SPACE)" % [short(early_gold()), votes]
	if wave < last_wave():
		return "Send the next wave now: +%s gold (SPACE)" % short(early_gold())
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


# A short build button (6 or more towers): the gem on the left, the name and
# under it the price, the hotkey in the bottom right corner.
func draw_build_chip(r: Rect2, i: int, data: Dictionary, affordable: bool) -> void:
	var active: bool = build_type == TOWER_TYPES[i]
	ui_button_bg(r, true, active)
	var col: Color = data["color"]
	gem(Vector2(r.position.x + 14, r.get_center().y), 8.0, col if affordable else col.darkened(0.4))
	var name_col := UI_GOLD_LIGHT if active else (UI_TEXT if affordable else UI_DIM)
	var at := r.position + Vector2(27, 14)
	hud.draw_string(font, at + Vector2(0, 1), data["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.8))
	text(at, data["name"], 13, name_col)
	text(r.position + Vector2(27, 26), gold_text(data["cost"][0]), 11, Color(1, 0.85, 0.3) if affordable else Color(0.7, 0.42, 0.3))
	right_text(Vector2(r.end.x - 5, r.position.y + 26), str(i + 1), 11, UI_GOLD_LIGHT)


# A box above the command card that explains the button under the mouse.
func draw_card_tip(i: int) -> void:
	var title := ""
	var lines: Array = []
	# (the build buttons have their own card: draw_tower_card())
	if i == CARD_UPGRADE:
		title = "Upgrade (U)"
		if selected == null or selected.owner != local_slot:
			lines = ["Select one of your towers first."]
		elif needs_path(selected):
			title = "Upgrade to level 5: pick a path"
			lines = ["Q: %s   E: %s" % [PATHS[selected.type][0]["name"], PATHS[selected.type][1]["name"]],
					"The path is for good (selling is the only way back)."]
		elif selected.level < MAX_LEVEL - 1:
			var data := tower_data(selected.type, selected.path, selected.level + 1)
			var lv: int = selected.level + 1
			title = "Upgrade to level %d (U)  -  %s gold" % [lv + 1, short(data["cost"][lv])]
			lines = ["Damage %s%s   Range %d" % [short(data["damage"][lv]), "/s" if data.has("cloud") else "", data["range"][lv]]]
			if data.has("cloud"):
				lines[0] += "   Cloud %d" % data["cloud"][lv]
			if data.has("soldiers"):
				lines = ["Damage %s   Soldiers %d   Health %s   Hold %ss" % [short(data["damage"][lv]), data["soldiers"][lv], num(data["soldier_hp"][lv], true), num(data["hold"][lv])]]
		else:
			lines = ["This tower is at its highest level."]
	elif i == CARD_SELL:
		title = "Sell (X)"
		lines = ["Get back %s gold for this tower." % short(selected.spent * 0.7)] if selected != null and selected.owner == local_slot else ["Select one of your towers first."]
		if challenge_rules().get("no_sell", false):
			lines = ["Towers can't be sold in this challenge (No selling)."]
	elif i == CARD_WAVE:
		title = "Next wave (SPACE)"
		lines = [wave_tip(), next_wave_text()]
	elif i == CARD_PATH or i == CARD_PATH + 1:
		var k := i - CARD_PATH
		var p: Dictionary = PATHS[selected.type][k]
		var d := tower_data(selected.type, k + 1, PATH_LEVEL)
		title = "%s (%s)  -  %s gold" % [p["name"], "Q" if k == 0 else "E", short(d["cost"][PATH_LEVEL])]
		lines = [p["desc"] + ".", "Level 5: Damage %s%s   Range %d   Speed %.2fs" % [short(d["damage"][PATH_LEVEL]), "/s" if d.has("cloud") else "", d["range"][PATH_LEVEL], d["cooldown"][PATH_LEVEL]]]
		if d.has("soldiers"):
			lines[1] = "Level 5: %d soldiers, damage %s, hold %ss" % [d["soldiers"][PATH_LEVEL], short(d["damage"][PATH_LEVEL]), num(d["hold"][PATH_LEVEL])]
		lines.append_array(path_extra(selected.type, k + 1).split("\n"))
		lines.append("For good: selling is the only way back.")
	elif i == CARD_MODE:
		title = "Target: %s (T)" % TARGET_MODES[selected.mode]
		lines = ["Shoots: " + TARGET_TIPS[selected.mode]]
		if selected.owner == local_slot:
			lines.append_array(["Click or T: next mode. Shift: all your %s towers." % TOWERS[selected.type]["name"],
					"First, Last, Strongest, Fastest, Closest"])
		else:
			lines.append("Only %s can change it." % name_of(selected.owner))
	elif i >= CARD_ABILITY:
		var a: String = ABILITY_ORDER[i - CARD_ABILITY]
		var ab: Dictionary = ABILITIES[a]
		title = "%s (%s)  -  free" % [ab["name"], ab["key"]]
		if a == "meteor":
			lines = ["%s, then click the map: hits all in the circle." % ab["key"],
					"Ignores armor. Grows stronger with the wave."]
		else:
			lines = ["Every monster stands still for %ss (bosses half)." % str(ab["time"]).trim_suffix(".0")]
		var left := ability_left(local_slot, a)
		lines.append("Ready in %ds" % ceili(left) if left > 0.0 else ("Ready" if wave > 0 else "Ready once the first wave starts"))
		lines.append("Cooldown: %ds" % roundi(ab["cooldown"]))
	else:
		title = "Game speed x%d (F)" % game_speed
		lines = ["Only the host can change the speed."] if net_mode == "client" else ["Switches between x1, x2, x3 and x5 speed."]
	# Over the ability buttons, or over the command card
	tip_box(INFO_X - 12 if i >= CARD_ABILITY else SCREEN_W - 372, 360, title, Color(1, 0.85, 0.3), lines)


# A dark box above the console with a gold title and lines under it.
func tip_box(x: float, w: float, title: String, title_col: Color, lines: Array) -> void:
	var r := Rect2(x, BAR_TOP - 24 - 34 - lines.size() * 20, w, 34 + lines.size() * 20 + 10)
	hud.draw_rect(r.grow(1), Color(0, 0, 0, 0.9), false, 1.0)
	hud.draw_rect(r, Color(0.05, 0.05, 0.055, 0.92))
	hud.draw_rect(r, UI_GOLD_DARK, false, 1.0)
	text(r.position + Vector2(12, 24), title, 16, title_col)
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
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.5))
	ui_box(m)
	var title := "PAUSED" if net_mode == "" else "MENU"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	ui_title(Rect2(m.position.x, m.position.y, m.size.x, 66), Vector2((SCREEN_W - tw) / 2.0, m.position.y + 50), title, 40)
	var sub := "The game is paused." if net_mode == "" else "The game keeps running while this menu is open."
	centered(m.position.y + 78, sub, 15, UI_GREY)
	button(GRAPHICS_RECT, "Settings")
	button(PROFILE_RECT, "Profile", true, true)
	ui_heading(Vector2(left, 203), "MULTIPLAYER", width)  # under Map: and Level: (see map_editor.gd)
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
			text(Vector2(left, 234), "You are playing as %s." % name_of(local_slot), 16, ink_of(local_slot))
			draw_player_list(Vector2(left, 266))
			button(STOP_RECT, "Leave the game")
	button(MENU_SAVE_RECT, "Save", call("can_save") == "")
	button(MENU_LOAD_RECT, "Load", call("can_load") == "")
	button(MENU_RESUME_RECT, "Resume (Esc)")
	button(LEADERBOARD_RECT, "Leaderboard")
	# Messages (like "Saved") over the bottom row: the one over the console is under the menu
	var note := menu_message()
	if note != "" and not (save_open or load_open):
		outlined(Vector2(SCREEN_W / 2.0, MENU_RESUME_RECT.position.y - 10), fit_text(note, m.size.x - 30, 15), 15, Color(1, 1, 0.6))


# The top 10 from the game server (see open_board()), over the Esc menu.
func draw_board() -> void:
	var b := BOARD_RECT
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.5))
	ui_box(b)
	var title := "LEADERBOARD"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
	ui_title(Rect2(b.position.x, b.position.y, b.size.x, 62), Vector2((SCREEN_W - tw) / 2.0, b.position.y + 46), title, 36)
	# Which list: the normal game, endless mode or today's daily challenge
	for i in BOARD_TABS.size():
		var r := board_mode_rect(i)
		var on: bool = BOARD_TABS[i][0] == board_tab
		ui_button_bg(r, true, on)
		var label: String = BOARD_TABS[i][1]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var pos := Vector2(r.get_center().x - w / 2.0, r.position.y + 18)
		hud.draw_string(font, pos + Vector2(0, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.7))
		text(pos, label, 15, UI_GOLD_LIGHT if on else UI_GREY)
	var sub := ""
	if board_tab == "daily":
		# The daily challenge has one level, picked with the day's twist
		var rules := daily_rules(board_daily_date())
		var lv: int = rules.get("level", 1)
		centered(board_tab_rect(0).position.y + 19, "Daily %s:  %s, %s level" % [board_daily_date(), rules.get("name", ""), DIFFICULTIES[lv]], 16, LEVEL_COLORS[lv])
		sub = "%s  %d waves on the day's own map, the same for everyone." % [rules.get("desc", ""), DAILY_WAVES]
	elif board_tab == "weekly":
		# The weekly challenge: always Hard, the week's two twists
		var id := board_weekly_week()
		var rules := weekly_rules(id)
		centered(board_tab_rect(0).position.y + 19, fit_text("Weekly %s:  %s, %s level" % [id, rules.get("name", ""), DIFFICULTIES[WEEKLY_LEVEL]], b.size.x - 40, 16), 16, LEVEL_COLORS[WEEKLY_LEVEL])
		var ends := "Ends in %s." % time_left_text(weekly_ends_in()) if id == weekly_now() else "That week is over."
		sub = "%d waves on the week's map (%s), the same for everyone. %s" % [WEEKLY_WAVES, weekly_map_label(id), ends]
	else:
		# A tab per level, in the level's color (Left / Right arrows switch too)
		for i in DIFFICULTIES.size():
			var r := board_tab_rect(i)
			var on := i == board_level
			ui_button_bg(r, true, on)
			var col: Color = LEVEL_COLORS[i] if on else LEVEL_COLORS[i].darkened(0.3)
			var w := font.get_string_size(DIFFICULTIES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var pos := Vector2(r.get_center().x - w / 2.0, r.position.y + 18)
			hud.draw_string(font, pos + Vector2(0, 1), DIFFICULTIES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.7))
			text(pos, DIFFICULTIES[i], 15, col)
			if on:
				hud.draw_rect(Rect2(r.position.x + 10, r.end.y - 4, r.size.x - 20, 2), LEVEL_COLORS[i])
		if board_tab == "endless":
			sub = "%s level, Default map, kept going after wave %d. Highest wave first." % [DIFFICULTIES[board_level], MAX_WAVE]
		else:
			sub = "%s level, Default map, %d waves. Highest wave first, then the fastest time." % [DIFFICULTIES[board_level], MAX_WAVE]
	centered(b.position.y + 150, fit_text(sub, b.size.x - 40, 14), 14, UI_GREY)
	var gold_col := Color(1, 0.85, 0.3)
	var x_rank := b.position.x + 40
	var x_names := b.position.x + 90
	var x_wave := b.position.x + 470  # right edge of the wave column
	var x_time := b.end.x - 40  # right edge of the time column
	var y := b.position.y + 172
	text(Vector2(x_rank, y), "#", 15, gold_col)
	text(Vector2(x_names, y), "Players", 15, gold_col)
	right_text(Vector2(x_wave, y), "Wave", 15, gold_col)
	right_text(Vector2(x_time, y), "Time", 15, gold_col)
	ui_divider(b.position.x + 24, b.end.x - 24, y + 10)
	var top := b.position.y + 182
	for i in BOARD_ROWS:
		var row := Rect2(b.position.x + 24, top + i * BOARD_ROW_H, b.size.x - 48, BOARD_ROW_H - 2)
		var e: Dictionary = board_top[i] if i < board_top.size() else {}
		var mine: bool = not e.is_empty() and not board_me.is_empty() and e.names == board_me.names
		hud.draw_rect(row, Color(0.55, 0.42, 0.15, 0.35) if mine else Color(0, 0, 0, 0.28 if i % 2 == 0 else 0.16))
		var ty := row.position.y + 22
		var rank_col: Color = [Color(1, 0.84, 0.3), Color(0.82, 0.84, 0.88), Color(0.85, 0.55, 0.3)][i] if i < 3 else UI_GREY
		text(Vector2(x_rank, ty), str(i + 1), 17, rank_col)
		if e.is_empty():
			text(Vector2(x_names, ty), "-", 16, UI_DIM)
			continue
		text(Vector2(x_names, ty), fit_text(" + ".join(e.names), x_wave - x_names - 60, 16), 16, UI_GOLD_LIGHT if mine else UI_TEXT)
		right_text(Vector2(x_wave, ty), str(e.wave), 17, UI_TEXT)
		if e.won:
			text(Vector2(x_wave + 8, ty), "won", 13, gold_col)
		right_text(Vector2(x_time, ty), board_time_text(e.ms), 16, UI_TEXT)
	var below := top + BOARD_ROWS * BOARD_ROW_H + 26
	if board_status != "":
		centered(below, board_status, 15, Color(1, 0.75, 0.5))
	elif board_me.is_empty():
		var how := "Finish a game on the Default map at %s to get on this list." % DIFFICULTIES[board_level]
		if board_tab == "daily":
			how = "Play today's daily challenge (Esc menu) to get on this list."
		elif board_tab == "weekly":
			how = "Play this week's challenge (Esc menu) to get on this list."
		elif board_tab == "endless":
			how = "Win at %s and keep going (K) to get on this list." % DIFFICULTIES[board_level]
		centered(below, how, 15, UI_GREY)
	else:
		var where := "#%d" % board_me.rank if board_me.rank > 0 else "not in the top 1000"
		centered(below, "Your best: %s, wave %d%s, %s" % [where, board_me.wave, " (won)" if board_me.won else "", board_time_text(board_me.ms)], 15, gold_col)
	button(BOARD_REFRESH_RECT, "Refresh", can_refresh_board())
	button(BOARD_BACK_RECT, "Back (Esc)", true, true)


var settings_open := false  # the Settings box over the Esc menu


# Each row of the Settings box: its name, the current choice, its key, and
# whether it counts from the next game (a small line under the name).
func settings_rows() -> Array:
	return [
		["Graphics", "High" if graphics_high else "Low", "graphics", false],
		["Window", "Fullscreen" if fullscreen else "Windowed", "window", false],
		["3D resolution", "%d%%" % roundi(render_scale * 100.0), "scale", false],
		["Anti-aliasing", AA_NAMES[AA_MODES.find(aa_mode)], "aa", false],
		["Music", "%d%%" % roundi(music_volume * 100.0), "music", false],
		["Sound effects", "%d%%" % roundi(effects_volume * 100.0), "effects", false],
		["Tutorial tips", "On" if tutorial_on() else "Off", "tips", false],
		["Story cards", "On" if story_cards_on() else "Off", "story", false],
		["Weather", "Always day" if weather_setting == "day" else "Random", "weather", true],
		["Festivals", "On" if festivals_on else "Off", "festivals", true],
	]


# The box is taller than SETTINGS_BOX (game_base.gd) so 10 rows fit
const SETTINGS_TALL := Rect2(430, 58, 420, 600)
const SETTINGS_TOP := 134  # the first row's button
const SETTINGS_ROW_STEP := 42
const SETTINGS_BACK := Rect2(560, 600, 160, 40)


func settings_row_rect(i: int) -> Rect2:
	return Rect2(SETTINGS_BUTTON_X, SETTINGS_TOP + i * SETTINGS_ROW_STEP, 180, 34)


# A click on a row's button picks the next choice; the 2 volume rows are sliders.
func draw_settings() -> void:
	var b := SETTINGS_TALL
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.5))
	ui_box(b)
	var title := "SETTINGS"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	ui_title(Rect2(b.position.x, b.position.y, b.size.x, 60), Vector2((SCREEN_W - tw) / 2.0, b.position.y + 44), title, 34)
	var rows := settings_rows()
	for i in rows.size():
		var r := settings_row_rect(i)
		var later: bool = rows[i][3]
		text(Vector2(b.position.x + 40, r.position.y + (17 if later else 23)), rows[i][0], 17, UI_TEXT)
		if later:
			text(Vector2(b.position.x + 40, r.position.y + 33), "from the next game", 12, UI_DIM)
		if rows[i][2] in ["music", "effects"]:
			volume_bar(r, music_volume if rows[i][2] == "music" else effects_volume, rows[i][1])
		else:
			button(r, rows[i][1])
	centered(SETTINGS_BACK.position.y - 14, "F11 or Alt+Enter: fullscreen.  Lower 3D resolution: faster.", 13, UI_DIM)
	button(SETTINGS_BACK, "Back (Esc)", true, true)


func settings_click(p: Vector2) -> void:
	if SETTINGS_BACK.has_point(p):
		settings_open = false
		return
	var rows := settings_rows()
	for i in rows.size():
		if settings_row_rect(i).has_point(p):
			match rows[i][2]:
				"graphics":
					graphics_high = not graphics_high
					apply_graphics()
				"window":
					set_fullscreen(not fullscreen)
				"scale":
					var scales := render_scales()
					render_scale = scales[(scales.find(render_scale) + 1) % scales.size()]
					apply_display()
				"aa":
					aa_mode = AA_MODES[(AA_MODES.find(aa_mode) + 1) % AA_MODES.size()]
					apply_display()
				"music", "effects":
					# Where the bar was clicked sets the volume (5% steps)
					var r := settings_row_rect(i)
					var v := snappedf(clampf((p.x - r.position.x - 8.0) / (r.size.x - 16.0), 0.0, 1.0), 0.05)
					if rows[i][2] == "music":
						set_music_volume(v)
					else:
						set_effects_volume(v)
				"tips":
					set_tutorial(not tutorial_on())  # saves itself
				"story":
					set_story_cards(not story_cards_on())  # saves itself
				"weather":
					# The next game's weather (pick_mood() in main.gd reads it)
					weather_setting = WEATHER_SETTINGS[(WEATHER_SETTINGS.find(weather_setting) + 1) % WEATHER_SETTINGS.size()]
				"festivals":
					# The next game's decorations (festival_today() reads it)
					festivals_on = not festivals_on
			save_settings()


# A volume slider: the bar fills up to v (0..1), the percentage on it.
func volume_bar(r: Rect2, v: float, label: String) -> void:
	note_button(r, true)
	ui_button_bg(r, true, false)
	var bar := Rect2(r.position.x + 8.0, r.end.y - 9.0, r.size.x - 16.0, 4.0)
	hud.draw_rect(bar, Color(0, 0, 0, 0.5))
	hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * v, bar.size.y)), UI_GOLD)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	text(Vector2(r.position.x + (r.size.x - w) / 2.0, r.position.y + 20.0), label, 16, UI_TEXT)

# The leaderboard's level tabs, centered under the list tabs.
func board_tab_rect(i: int) -> Rect2:
	var w := 110.0
	var gap := 8.0
	var left := (SCREEN_W - DIFFICULTIES.size() * (w + gap) + gap) / 2.0
	return Rect2(left + i * (w + gap), BOARD_RECT.position.y + 104, w, 28)


# ----- the leaderboard's lists: the normal game, endless mode, the daily and the weekly challenge

const BOARD_TABS := [["normal", "Normal game"], ["endless", "Endless"], ["daily", "Daily challenge"], ["weekly", "Weekly challenge"]]
const CHALLENGE_TABS := ["daily", "weekly"]  # one level each: no level tabs
var board_tab := "normal"


func board_mode_rect(i: int) -> Rect2:
	var w := 140.0
	var gap := 8.0
	var left := (SCREEN_W - BOARD_TABS.size() * (w + gap) + gap) / 2.0
	return Rect2(left + i * (w + gap), BOARD_RECT.position.y + 70, w, 28)


# The daily list shows the day being played, or today's.
func board_daily_date() -> String:
	return daily_date if daily_date != "" else daily_today()


# The weekly list shows the week being played, or this week's.
func board_weekly_week() -> String:
	return weekly_id if weekly_id != "" else weekly_now()


# "3 d 5 h", "5 h 12 min" or "12 min" (the weekly challenge's time left).
func time_left_text(seconds: int) -> String:
	var d := seconds / 86400
	var h := (seconds % 86400) / 3600
	if d > 0:
		return "%d d %d h" % [d, h]
	return "%d h %d min" % [h, (seconds % 3600) / 60] if h > 0 else "%d min" % maxi(seconds / 60, 1)


# The box asks the server for board_id(level, 0) (see load_board()): here that's
# the board of the list being shown.
func board_id(level := -1, endless_board := -1) -> String:
	if endless_board == 0 and board_tab == "daily":
		return daily_board_id(board_daily_date())
	if endless_board == 0 and board_tab == "weekly":
		return weekly_board_id(board_weekly_week())
	if endless_board == 0 and board_tab == "endless":
		return super(level, 1)
	return super(level, endless_board)


# Opens on the list of the game being played.
func open_board() -> void:
	if daily_date != "":
		set_board_tab("daily")
	elif weekly_id != "":
		set_board_tab("weekly")
	else:
		set_board_tab("endless" if endless else "normal")
	super()


# Another list: what was loaded is for the old one, so it's forgotten.
func set_board_tab(tab: String) -> void:
	if tab == board_tab:
		return
	board_tab = tab
	board_saved.clear()
	if board_http != null:
		board_http.cancel_request()
		board_http.queue_free()
		board_http = null


func board_click(p: Vector2) -> void:
	for i in BOARD_TABS.size():
		if board_mode_rect(i).has_point(p):
			if BOARD_TABS[i][0] != board_tab:
				set_board_tab(BOARD_TABS[i][0])
				show_board_level(board_level)
			return
	for i in DIFFICULTIES.size():
		if not board_tab in CHALLENGE_TABS and board_tab_rect(i).has_point(p):
			if i != board_level:
				show_board_level(i)
			return
	if BOARD_BACK_RECT.has_point(p):
		board_open = false
	elif BOARD_REFRESH_RECT.has_point(p):
		refresh_board()


# Text whose right edge is at pos.x.
func right_text(pos: Vector2, s: String, size: int, col: Color) -> void:
	text(pos - Vector2(font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, 0), s, size, col)


# s, cut short with "..." if it's wider than width.
func fit_text(s: String, width: float, size: int) -> String:
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return s
	while s.length() > 1 and font.get_string_size(s + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		s = s.left(-1)
	return s + "..."


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
		var most := clampi(int(g.get("max", MAX_PLAYERS)), 1, MAX_PLAYERS)  # older game servers don't say: 4
		button(game_row_rect(i), "Join  %s      %d / %d players      wave %d" % [g.code, int(g.players), most, int(g.wave)])


func draw_player_list(pos: Vector2) -> void:
	text(pos, "Players (%d / %d):" % [player_count(), map_slots()], 15, UI_GREY)
	var y := pos.y + 24
	for slot in MAX_PLAYERS:
		if players[slot] == null:
			continue
		player_dot(Vector2(pos.x + 8, y - 5), 6, slot)
		var who: String = name_of(slot)
		if slot == local_slot:
			who += " (you)"
		elif players[slot].peer == 1:
			who += " (host)"
		text(Vector2(pos.x + 22, y), who, 15, UI_TEXT)
		if slot != local_slot:
			var r := gift_menu_rect(slot)
			var ok := can_gift(slot)
			ui_button_bg(r, ok, false)
			icon_coin(r.position + Vector2(12, r.size.y / 2.0), 6.0, ok)
			text(r.position + Vector2(24, 16), "Give gold", 13, UI_TEXT if ok else UI_DIM)
		y += 24


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
	# The rest sits at the screen's bottom (see ui_extra)
	hud.draw_set_transform(Vector2(0, ui_extra))
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
	hud.draw_set_transform(Vector2.ZERO)


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
	# Esc in the reset question or Achievements goes back to the Profile, and from there to the menu
	if menu_open and (profile_open or ach_open or chron_open or reset_ask):
		if reset_ask:
			reset_ask = false
		elif ach_open:
			ach_open = false
		elif chron_open:
			chron_open = false
		else:
			profile_open = false
		return
	# Esc in the leaderboard, the settings or the Save / Load box goes back to the menu
	if (board_open or settings_open or save_open or load_open) and menu_open:
		board_open = false
		settings_open = false
		close_save_boxes()
		return
	board_open = false
	settings_open = false
	close_save_boxes()
	menu_open = not menu_open
	build_type = ""
	games_timer = 0.0  # fresh list of public games when the menu opens
	if not menu_open:
		code_input.release_focus()
		name_input.release_focus()
	close_chat()


func menu_click(p: Vector2) -> void:
	if profile_open:
		profile_click(p)
		return
	if PROFILE_RECT.has_point(p):
		open_profile()
		return
	if board_open:
		board_click(p)
		return
	if settings_open:
		settings_click(p)
		return
	if save_open:
		save_click(p)
		return
	if load_open:
		load_click(p)
		return
	if MENU_RESUME_RECT.has_point(p):
		toggle_menu()
		return
	if MENU_SAVE_RECT.has_point(p):
		open_save_box()
		return
	if MENU_LOAD_RECT.has_point(p):
		open_load_box()
		return
	if LEADERBOARD_RECT.has_point(p):
		open_board()
		return
	if GRAPHICS_RECT.has_point(p):
		settings_open = true
		code_input.release_focus()
		name_input.release_focus()
		return
	if net_mode == "host" or net_mode == "client":
		for slot in MAX_PLAYERS:
			if slot != local_slot and players[slot] != null and gift_menu_rect(slot).has_point(p):
				open_gift(slot)
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


# ----- the end screen and its stats

const STATS_WIN_DELAY := 3.0  # seconds of title and fireworks alone before the stats on a win
const STATS_LOSE_DELAY := 0.8
const STATS_TOP := 152.0  # the stats panel's top (the title goes above it)
var end_at_ms := -1  # when the end screen showed up (-1: still playing)


func showing_stats() -> bool:
	if state == "playing" or end_at_ms < 0:
		return false
	var wait := STATS_WIN_DELAY if state == "won" else STATS_LOSE_DELAY
	return Time.get_ticks_msec() - end_at_ms >= wait * 1000.0


# The stats panel's place: its height grows with the players.
func stats_rect() -> Rect2:
	var n := maxi((end_stats.get("players", []) as Array).size(), 1)
	var m := maxi((end_stats.get("towers", []) as Array).size(), 1)
	return Rect2(250, STATS_TOP, 780, 30 + 28 + n * 26 + 24 + 26 + m * 24 + 30)


const STATS_FADE := 0.45  # seconds for the stats panel to fade in and the title to move up


# 0 before the stats show, then up to 1 over STATS_FADE seconds (eased).
func stats_fade() -> float:
	if not showing_stats():
		return 0.0
	var wait := STATS_WIN_DELAY if state == "won" else STATS_LOSE_DELAY
	var t := clampf((Time.get_ticks_msec() - end_at_ms - wait * 1000.0) / (STATS_FADE * 1000.0), 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


# The end screen's nodes under the overlay (see build_hud): shown, placed and faded.
func update_end_layer() -> void:
	end_layer.visible = state != "playing" and not replaying()  # the replay hides it
	if not end_layer.visible:
		return
	end_layer.position = Vector2(0, ui_extra / 2.0)
	end_layer.queue_redraw()
	var k := stats_fade()
	stats_layer.visible = showing_stats() and not menu_open and update_dialog == ""
	stats_layer.modulate.a = k
	stats_layer.position = Vector2(0, (1.0 - k) * 18.0)  # rises a little as it fades in
	stats_layer.queue_redraw()


# Darkens the map under the end screen; less when won, so the fireworks show.
func draw_end_cover() -> void:
	var won := state == "won"
	var a := lerpf(0.4 if won else 0.6, 0.55 if won else 0.65, stats_fade())
	hud.draw_rect(Rect2(0, TOP_BAR_H - ui_extra / 2.0, SCREEN_W, BAR_TOP - TOP_BAR_H + ui_extra), Color(0, 0, 0, a))


# The title and the lines under it. When the stats come, the title shrinks and
# moves up over the panel, and the lines under it change to one shorter line.
func draw_end_screen() -> void:
	if replaying():
		return
	var won := state == "won"
	var k := stats_fade()
	var title := WIN_TEXT if won else "GAME OVER"
	# The win text is long, so it's smaller (it fits FW_KEEP, where no fireworks burst)
	var big := roundi(lerpf(48 if won else 64, 40 if won else 52, k))
	var size := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, big)
	var pos := Vector2((SCREEN_W - size.x) / 2.0, lerpf(END_Y, STATS_TOP - 58, k))
	hud.draw_string_outline(title_font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 6, Color(0, 0, 0, 0.8))
	hud.draw_string(title_font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color(1, 0.85, 0.3) if won else Color(1, 0.35, 0.35))
	var shown_wave: int = end_stats.get("wave", wave)
	var sub := "You survived all %d waves." % MAX_WAVE if won else "Too many monsters! You reached wave %d." % shown_wave
	var a := clampf(1.0 - k * 3.0, 0.0, 1.0)  # gone quickly, so they don't mix with the panel
	if a > 0.0:
		size = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		text(Vector2((SCREEN_W - size.x) / 2.0, END_Y + 50), sub, 22, Color(UI_TEXT, a))
		outlined(Vector2(SCREEN_W / 2.0, END_Y + 84), "Level: " + level_name(), 18, Color(level_color(), a))
		size = font.get_string_size("Press R to play again", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		text(Vector2((SCREEN_W - size.x) / 2.0, END_Y + 112), "Press R to play again", 16, Color(UI_GREY, a))
		if can_replay():
			outlined(Vector2(SCREEN_W / 2.0, END_Y + 140), "Press V to watch the replay", 17, Color(UI_GOLD_LIGHT, a))
		if from_save:
			outlined(Vector2(SCREEN_W / 2.0, END_Y - 76), LOADED_NOTE, 16, Color(LOADED_COLOR, a))
	var keep := can_keep_going()
	if keep:
		button(keep_going_spot(), "Keep going (K)", true, true)
		if not showing_stats():
			outlined(Vector2(SCREEN_W / 2.0, END_Y + 190), "Endless mode: the waves go on and keep getting harder.", 15, UI_GREY)
	# The short line comes in once the title has moved past it
	k = clampf(k * 2.0 - 1.0, 0.0, 1.0)
	if k <= 0.0:
		return
	var lv := "Level: " + level_name()
	if end_stats.has("ms"):
		var sec := int(end_stats["ms"] / 1000.0)
		lv += "    Time %d:%02d" % [int(sec / 60.0), sec % 60]
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var lw := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var sx := (SCREEN_W - sw - 24.0 - lw) / 2.0
	if keep:
		# The Keep going button sits at the line's right end, so the line moves left
		sx = (keep_going_spot().position.x + 240.0 - sw - 24.0 - lw) / 2.0
	text(Vector2(sx, STATS_TOP - 20), sub, 18, Color(UI_TEXT, k))
	hud.draw_string_outline(font, Vector2(sx + sw + 24.0, STATS_TOP - 20), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8 * k))
	text(Vector2(sx + sw + 24.0, STATS_TOP - 20), lv, 16, Color(level_color(), k))


# After a win the host (or a player alone) can keep going in endless mode.
func can_keep_going() -> bool:
	return state == "won" and not endless and net_mode != "client"


# The Keep going button, in the end screen's own pixels: under the lines before
# the stats come, then at the right end of the line over the stats panel.
func keep_going_spot() -> Rect2:
	if showing_stats():
		return Rect2(stats_rect().end.x - 164, STATS_TOP - 46, 164, 34)
	return Rect2(SCREEN_W / 2.0 - 100.0, END_Y + 132, 200, 38)


# Where it's clicked: the end screen is drawn ui_extra / 2 lower (see draw_hud)
func keep_going_rect() -> Rect2:
	if not can_keep_going():
		return Rect2()
	var r := keep_going_spot()
	r.position.y += ui_extra / 2.0
	return r


# The stats panel (on its own node, see update_end_layer()): each player's kills,
# damage and gold (the MVP did the most damage) and the 5 towers that did the
# most damage. The host made the stats (see make_end_stats()).
func draw_stats_panel() -> void:
	var size: Vector2
	var panel := stats_rect()
	hud.draw_rect(panel.grow(4), Color(0, 0, 0, 0.35))
	vgrad(panel, Color(0.12, 0.115, 0.11, 0.94), Color(0.07, 0.065, 0.06, 0.94))
	bevel(panel, 3, UI_GOLD_LIGHT, UI_GOLD_DARK)
	var again := "Press R to play again"
	var extra := ""  # a second hint, in gold
	if can_keep_going():
		extra = "K: keep going in endless mode"
	elif can_replay():
		extra = "V: watch the replay of the last minute"
	var gap := "     " if extra != "" else ""
	size = font.get_string_size(again + gap + extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var ax := (SCREEN_W - size.x) / 2.0
	text(Vector2(ax, panel.end.y + 22), again + gap, 16, UI_GREY)
	text(Vector2(ax + font.get_string_size(again + gap, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, panel.end.y + 22), extra, 16, UI_GOLD_LIGHT)
	if from_save:
		centered(panel.end.y + 46, LOADED_NOTE, 15, LOADED_COLOR)
	if end_stats.is_empty():
		outlined(panel.get_center(), "Getting the stats from the host...", 16, UI_GREY)
		return
	var rows: Array = end_stats["players"]
	var team := rows.size() > 1  # alone: no MVP and no owner column
	var left := panel.position.x + 24
	# In a team game a 6th column: gold got from the others minus gold given
	var cols := [left, left + 246, left + 336, left + 436, left + 556]
	if team:
		cols = [left, left + 226, left + 302, left + 392, left + 498, left + 632]
	# ---- players
	var y := panel.position.y + 30
	ui_title(Rect2(panel.position.x + 10, y - 26, 760, 34), Vector2(left, y), "PLAYERS" if team else "YOU", 18)
	var heads := ["", "Kills", "Damage", "Gold earned", "Spent on towers", "Gifts"]
	for i in range(1, cols.size()):
		text(Vector2(cols[i], y), heads[i], 13, UI_DIM)
	y += 28
	var kills := 0
	var damage := 0.0
	for row: Array in rows:
		var slot: int = row[0]
		kills += row[2]
		damage += row[3]
		player_dot(Vector2(left + 6, y - 5), 6, slot)
		text(Vector2(left + 20, y), row[1], 16, ink_of(slot).lightened(0.3))
		if slot == end_stats["mvp"]:
			var nw := font.get_string_size(row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var mr := Rect2(left + 28 + nw, y - 15, 42, 19)
			ui_button_bg(mr, true, true)
			text(mr.position + Vector2(7, 14), "MVP", 13, UI_GOLD_LIGHT)
		text(Vector2(cols[1], y), short(row[2]), 16, UI_TEXT)
		text(Vector2(cols[2], y), short(row[3]), 16, UI_TEXT)
		text(Vector2(cols[3], y), gold_text(row[4]), 16, Color(1, 0.85, 0.3))
		text(Vector2(cols[4], y), gold_text(row[5]), 16, Color(1, 0.85, 0.3))
		if team:
			var g: int = row[6] if row.size() > 6 else 0
			if g == 0:
				text(Vector2(cols[5], y), "-", 16, UI_DIM)
			else:
				text(Vector2(cols[5], y), ("+" if g > 0 else "-") + gold_text(absi(g)), 16, Color(0.55, 0.9, 0.5) if g > 0 else Color(1.0, 0.55, 0.45))
		y += 26
	# ---- best towers
	y += 24
	ui_title(Rect2(panel.position.x + 10, y - 26, 760, 34), Vector2(left, y), "BEST TOWERS", 18)
	text(Vector2(left + 496, y), "Damage", 13, UI_DIM)
	text(Vector2(left + 640, y), "Kills", 13, UI_DIM)
	y += 26
	var best: Array = end_stats["towers"]
	if best.is_empty():
		text(Vector2(left, y), "No tower did any damage.", 15, UI_GREY)
	var most: float = best[0][5] if not best.is_empty() else 1.0
	for i in best.size():
		var t: Array = best[i]
		gem(Vector2(left + 8, y - 5), 7.0, TOWERS[t[0]]["color"])
		var tname: String = tower_data(t[0], t[1], t[2])["name"]
		text(Vector2(left + 26, y), "%s  Lv %d" % [tname, t[2] + 1], 15, UI_GOLD_LIGHT if i == 0 else UI_TEXT)
		if team:
			text(Vector2(left + 176, y), t[4], 14, ink_of(t[3]).lightened(0.3))
		ui_bar(Rect2(left + 306, y - 10, 180, 8), t[5] / maxf(most, 1.0), Color(0.9, 0.45, 0.2))
		text(Vector2(left + 496, y), short(t[5]), 15, UI_TEXT)
		text(Vector2(left + 640, y), short(t[6]), 15, UI_TEXT)
		y += 24
	var foot := "Monsters killed: %s     Damage done: %s" % [short(kills), short(damage)]
	size = font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	text(Vector2((SCREEN_W - size.x) / 2.0, panel.end.y - 12), foot, 14, UI_GREY)


# ---------------------------------------------------------------- fireworks

# Silly fireworks over the win screen, drawn in 2D. Every player's game knows
# it's won (the state comes with the host's updates), so each makes its own.
# Sparks are one MultiMesh of glowing dots (one draw call), confetti another.
const FW_KEEP := Rect2(230, 235, 820, 165)  # the win text: no bursts in here
const FW_MOST := 500  # sparks at most, so it never gets too busy
const FW_PARTY := [Color(1, 0.85, 0.35), Color(1, 0.45, 0.75), Color(0.45, 0.95, 1), Color(0.6, 1, 0.4),
		Color(0.75, 0.5, 1), Color(1, 0.6, 0.25)]
var fw_sparks := []  # [pos, vel, color, life, max life, drag, gravity, size]
var fw_rockets := []  # Dictionaries: rising rockets
var fw_confetti := []  # [pos, vel, color, life, angle, spin]
var fw_words := []  # [pos, text, life]: "pfft"
var fw_timer := 0.0
var fw_glow: MultiMeshInstance2D
var fw_paper: MultiMeshInstance2D


# Made the first time a game is won, on top of the overlay.
func build_fireworks() -> void:
	var dot := GradientTexture2D.new()
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.gradient = Gradient.new()
	dot.gradient.set_color(0, Color(1, 1, 1, 1))
	dot.gradient.set_color(1, Color(1, 1, 1, 0))
	dot.gradient.add_point(0.25, Color(1, 1, 1, 0.55))
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fw_glow = fw_layer(dot, add, FW_MOST + 60)
	fw_paper = fw_layer(null, null, 200)


func fw_layer(tex: Texture2D, m: Material, most: int) -> MultiMeshInstance2D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = most
	mm.visible_instance_count = 0
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture = tex
	node.material = m
	node.position = Vector2(0, ui_extra / 2.0)  # with the win text (see draw_hud)
	hud.get_parent().add_child(node)
	return node


func update_fireworks(delta: float) -> void:
	if state != "won":
		# Cleared even while hidden (Esc menu or popup open), so no old sparks come back next win
		fw_sparks.clear()
		fw_rockets.clear()
		fw_confetti.clear()
		fw_words.clear()
		if fw_glow != null and fw_glow.visible:
			fw_glow.visible = false
			fw_paper.visible = false
		fw_timer = 0.3
		return
	if fw_glow == null:
		build_fireworks()
	# Not over the Esc menu or a popup
	fw_glow.visible = not menu_open and update_dialog == ""
	fw_paper.visible = fw_glow.visible
	fw_timer -= delta
	if fw_timer <= 0.0:
		fw_timer = randf_range(0.35, 0.8)
		if fw_sparks.size() < FW_MOST - 100:
			if randf() < 0.1 and fw_confetti.size() < 100:
				fw_confetti_pop()
			else:
				fw_launch()
	for r: Dictionary in fw_rockets:
		r.time += delta
		r.pos += r.vel * delta
		r.vel.y += 60.0 * delta
		if r.kind == "fizzle":
			r.pos.x += sin(r.time * 14.0) * 90.0 * delta  # wobbly
		# A short trail of embers
		if randf() < 0.6:
			fw_sparks.append([r.pos, Vector2(randf_range(-15, 15), 20), Color(1, 0.6, 0.3), 0.35, 0.35, 2.0, 40.0, 6.0])
		if r.pos.y <= r.top or r.vel.y >= 0.0:
			fw_burst(r)
			r.done = true
	fw_rockets = fw_rockets.filter(func(r: Dictionary) -> bool: return not r.done)
	var keep := []
	for s: Array in fw_sparks:
		s[3] -= delta
		if s[3] <= 0.0:
			continue
		s[1] *= exp(-s[5] * delta)
		s[1].y += s[6] * delta
		s[0] += s[1] * delta
		keep.append(s)
	fw_sparks = keep
	keep = []
	for c: Array in fw_confetti:
		c[3] -= delta
		if c[3] <= 0.0 or c[0].y > BAR_TOP:
			continue
		c[1] *= exp(-1.6 * delta)
		c[1].y += 70.0 * delta
		c[0] += (c[1] + Vector2(sin(c[3] * 3.0 + c[5]) * 25.0, 0)) * delta
		c[4] += c[5] * delta
		keep.append(c)
	fw_confetti = keep
	for w: Array in fw_words:
		w[2] -= delta
		w[0].y -= 12.0 * delta
	fw_words = fw_words.filter(func(w: Array) -> bool: return w[2] > 0.0)
	fw_fill()


# Hands the sparks and confetti to the two MultiMeshes in one go each.
# Per dot: 8 numbers for its place, size and turn, then 4 for its color.
func fw_fill() -> void:
	var buf := PackedFloat32Array()
	var mm := fw_glow.multimesh
	buf.resize(mm.instance_count * 12)
	var n := 0
	var all := fw_sparks.duplicate()
	for r: Dictionary in fw_rockets:
		all.append([r.pos, r.vel, Color(1, 0.9, 0.7), 1.0, 1.0, 0.0, 0.0, 8.0])
	for s: Array in all:
		if n >= mm.instance_count:
			break
		var fade: float = s[3] / s[4]
		var size: float = s[7]
		var v: Vector2 = s[1]
		var speed := v.length()
		# Fast sparks are stretched along their flight, like a short trail
		var x := v / speed if speed > 1.0 else Vector2.RIGHT
		var y := Vector2(-x.y, x.x) * size
		x *= size * (1.0 + speed * 0.03)
		if size > 20.0:
			x *= 1.6 - fade  # the flash grows as it fades
			y *= 1.6 - fade
		var c: Color = s[2]
		var i := n * 12
		buf[i] = x.x
		buf[i + 1] = y.x
		buf[i + 3] = s[0].x
		buf[i + 4] = x.y
		buf[i + 5] = y.y
		buf[i + 7] = s[0].y
		buf[i + 8] = c.r
		buf[i + 9] = c.g
		buf[i + 10] = c.b
		buf[i + 11] = c.a * fade
		n += 1
	mm.buffer = buf
	mm.visible_instance_count = n
	mm = fw_paper.multimesh
	buf = PackedFloat32Array()
	buf.resize(mm.instance_count * 12)
	n = 0
	for c: Array in fw_confetti:
		if n >= mm.instance_count:
			break
		# Flipping paper: thinner when seen edge-on
		var x := Vector2.from_angle(c[4]) * 8.0
		var y := Vector2(-x.y, x.x) * (0.1 + 0.5 * absf(sin(c[4] * 1.7)))
		var col: Color = c[2]
		var i := n * 12
		buf[i] = x.x
		buf[i + 1] = y.x
		buf[i + 3] = c[0].x
		buf[i + 4] = x.y
		buf[i + 5] = y.y
		buf[i + 7] = c[0].y
		buf[i + 8] = col.r
		buf[i + 9] = col.g
		buf[i + 10] = col.b
		buf[i + 11] = clampf(c[3], 0.0, 1.0)
		n += 1
	mm.buffer = buf
	mm.visible_instance_count = n


# Party colors and the colors of the players in the game.
func fw_colors() -> Array:
	var cols := FW_PARTY.duplicate()
	for slot in MAX_PLAYERS:
		if players[slot] != null:
			cols.append(ink_of(slot).lerp(Color.WHITE, 0.2))
	return cols


# A rocket from the bottom of the map to a spot away from the text.
func fw_launch() -> void:
	# Left of the text, right of it, or above it (not above the stats: no room)
	var keep := FW_KEEP
	if showing_stats():
		keep = stats_rect().grow_individual(0, 110, 0, 30)  # with the title above it
	var top := Vector2(randf_range(80, keep.position.x - 50), randf_range(TOP_BAR_H + 90, BAR_TOP - 150))
	match randi() % (2 if keep.position.y - 75 < TOP_BAR_H + 100 else 3):
		1:
			top.x = randf_range(keep.end.x + 50, SCREEN_W - 80)
		2:
			top = Vector2(randf_range(110, SCREEN_W - 110), randf_range(TOP_BAR_H + 80, keep.position.y - 75))
	var kinds := ["ball", "ball", "ball", "ring", "ring", "smiley", "heart", "tower", "unicorn", "fizzle"]
	var kind: String = kinds.pick_random()
	var start := Vector2(top.x + randf_range(-60, 60), BAR_TOP)
	# Fast enough to reach the top just as gravity stops it
	var vel := Vector2((top.x - start.x) / 1.2, -sqrt(2.0 * 60.0 * (start.y - top.y)) - 30.0)
	var cols := fw_colors()
	fw_rockets.append({"pos": start, "vel": vel, "top": top.y, "kind": kind, "time": 0.0,
			"color": cols.pick_random(), "color2": cols.pick_random(), "done": false})


func fw_burst(r: Dictionary) -> void:
	var p: Vector2 = r.pos
	var col: Color = r.color
	match r.kind:
		"fizzle":
			# Pfft: a few sad sparks and a word
			for i in 6:
				fw_sparks.append([p, Vector2(randf_range(-30, 30), randf_range(-30, 10)), Color(0.6, 0.6, 0.6), 0.9, 0.9, 1.0, 120.0, 6.0])
			fw_words.append([p + Vector2(-14, -6), "pfft", 1.4])
			return
		"ball", "ring":
			var n := 70
			for i in n:
				var a := TAU * i / n + randf() * 0.1
				var speed := randf_range(220, 260) if r.kind == "ring" else randf_range(60, 260)
				var c: Color = col if i % 2 == 0 or r.kind == "ring" else r.color2
				fw_sparks.append([p, Vector2(cos(a), sin(a)) * speed, c, randf_range(1.3, 1.8), 1.8, 2.2, 45.0, 9.0])
		_:
			# A shape: every spark flies to its spot in the shape, hangs there, then droops
			var pts := fw_shape(r.kind)
			for i in pts.size():
				var c := col
				if r.kind == "unicorn":
					c = Color.from_hsv(float(i) / pts.size(), 0.6, 1.0)  # rainbow, of course
				elif r.kind == "heart":
					c = Color(1, 0.4, 0.6)
				fw_sparks.append([p, pts[i] * 70.0 * 3.0, c, randf_range(2.0, 2.4), 2.4, 3.0, 16.0, 9.0])
	# A flash where it burst
	fw_sparks.append([p, Vector2.ZERO, Color(col, 0.6), 0.25, 0.25, 0.0, 0.0, 90.0])


# Points along a silly shape, about -1..1 in size (y down).
func fw_shape(kind: String) -> PackedVector2Array:
	var lines := []
	match kind:
		"smiley":
			var face := PackedVector2Array()
			for i in 25:
				face.append(Vector2.from_angle(TAU * i / 24.0))
			var mouth := PackedVector2Array()
			for i in 9:
				mouth.append(Vector2.from_angle(deg_to_rad(25 + 130 * i / 8.0)) * 0.6)
			lines = [face, mouth, PackedVector2Array([Vector2(-0.35, -0.35), Vector2(-0.35, -0.2)]),
					PackedVector2Array([Vector2(0.35, -0.35), Vector2(0.35, -0.2)])]
		"heart":
			var h := PackedVector2Array()
			for i in 33:
				var t := TAU * i / 32.0
				h.append(Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) / 15.0)
			lines = [h]
		"tower":
			# The arrow tower: walls, battlements and a door
			lines = [PackedVector2Array([Vector2(-0.5, 1), Vector2(-0.5, -0.4), Vector2(-0.75, -0.4), Vector2(-0.75, -0.9),
					Vector2(-0.45, -0.9), Vector2(-0.45, -0.7), Vector2(-0.15, -0.7), Vector2(-0.15, -0.9), Vector2(0.15, -0.9),
					Vector2(0.15, -0.7), Vector2(0.45, -0.7), Vector2(0.45, -0.9), Vector2(0.75, -0.9), Vector2(0.75, -0.4),
					Vector2(0.5, -0.4), Vector2(0.5, 1), Vector2(-0.5, 1)]),
					PackedVector2Array([Vector2(-0.18, 1), Vector2(-0.18, 0.55), Vector2(0, 0.38), Vector2(0.18, 0.55), Vector2(0.18, 1)])]
		"unicorn":
			# A unicorn's head looking left, with its horn
			lines = [PackedVector2Array([Vector2(0.65, 1), Vector2(0.6, 0.25), Vector2(0.4, -0.3), Vector2(0.38, -0.75),
					Vector2(0.15, -0.42), Vector2(-0.15, -0.4), Vector2(-0.5, -0.05), Vector2(-0.85, 0.3), Vector2(-0.8, 0.52),
					Vector2(-0.5, 0.55), Vector2(-0.2, 0.45), Vector2(0.0, 1)]),
					PackedVector2Array([Vector2(-0.22, -0.42), Vector2(-0.55, -1.05), Vector2(-0.02, -0.45)]),
					PackedVector2Array([Vector2(-0.18, -0.12), Vector2(-0.12, -0.08)])]
	# Evenly spaced points along the lines
	var out := PackedVector2Array()
	for l: PackedVector2Array in lines:
		for i in l.size() - 1:
			var a := l[i]
			var b := l[i + 1]
			var steps := maxi(int(a.distance_to(b) / 0.13), 1)
			for k in steps:
				out.append(a.lerp(b, float(k) / steps))
		out.append(l[l.size() - 1])
	return out


# Confetti popping up from a bottom corner.
func fw_confetti_pop() -> void:
	var left := randf() < 0.5
	var from := Vector2(40 if left else SCREEN_W - 40, BAR_TOP)
	var cols := fw_colors()
	for i in 50:
		var a := deg_to_rad(randf_range(-80, -40) if left else randf_range(-140, -100))
		fw_confetti.append([from, Vector2.from_angle(a) * randf_range(250, 520), cols.pick_random(),
				randf_range(3.5, 5.0), randf() * TAU, randf_range(-8, 8)])


func draw_fireworks() -> void:
	if state != "won":
		return
	for w: Array in fw_words:
		text(w[0], w[1], 15, Color(0.85, 0.85, 0.85, clampf(w[2], 0.0, 1.0)))


# ---------------------------------------------------------------- replay
# main.gd keeps the replay (it comes after this file), so its values are read by
# name: replay_on, replay_t, replay_paused, replay_speed, rec_frames, replay_info().

const REPLAY_PANEL := Rect2(224, 420, 832, 94)
const REPLAY_TRACK := Rect2(240, 484, 800, 22)  # the same place as REPLAY_BAR in main.gd, which takes its clicks


func replaying() -> bool:
	return get("replay_on") == true


# The wave the console shows: the replay's while it plays.
func shown_wave() -> int:
	return int(call("replay_info")[0]) if replaying() else wave


# After losing, V plays the last minute again (if there's a recording).
func can_replay() -> bool:
	var frames: Variant = get("rec_frames")
	return state == "lost" and frames is Array and frames.size() >= 2


# The replay's panel over the console: what's happening, the keys, and a
# timeline of the monsters alive (red near the limit) with the wave starts.
# Drawn on main.gd's replay_layer, over everything, so it also frames the map.
func draw_replay_bar() -> void:
	var frames: Array = get("rec_frames")
	if menu_open or frames.size() < 2:
		return
	draw_replay_vignette()
	# Sits on the console, which moves down on taller screens (ui_mouse() takes the clicks there)
	hud.draw_set_transform(Vector2(0, ui_extra))
	var p := REPLAY_PANEL
	hud.draw_rect(p.grow(4), Color(0, 0, 0, 0.35))
	vgrad(p, Color(0.12, 0.115, 0.11, 0.94), Color(0.07, 0.065, 0.06, 0.94))
	bevel(p, 3, UI_GOLD_LIGHT, UI_GOLD_DARK)
	var info: Array = call("replay_info")
	var paused: bool = get("replay_paused")
	var speed: float = get("replay_speed")
	# Row 1: a blinking red dot and REPLAY, then the wave, the monsters and who got past
	var x := p.position.x + 24
	var y := p.position.y + 30
	var blink := 1.0 if paused else 0.55 + 0.45 * sin(Time.get_ticks_msec() / 220.0)
	hud.draw_circle(Vector2(x, y - 8), 7.5, Color(0, 0, 0, 0.7))
	hud.draw_circle(Vector2(x, y - 8), 6.0, Color(1.0, 0.18, 0.12, blink))
	x += 16
	hud.draw_string(title_font, Vector2(x, y + 1), "REPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.8))
	hud.draw_string(title_font, Vector2(x, y), "REPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.3))
	x += title_font.get_string_size("REPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 26
	var k := clampf(float(info[1]) / maxf(info[2], 1.0), 0.0, 1.0)
	for part: Array in [["Wave", str(info[0]), UI_TEXT], ["Alive", "%d / %d" % [info[1], info[2]], Color(0.4, 0.9, 0.4).lerp(Color(1, 0.3, 0.3), k)],
			["Got past", str(info[3]), Color(1.0, 0.4, 0.3) if info[3] > 0 else UI_TEXT]]:
		text(Vector2(x, y), part[0], 14, UI_DIM)
		x += font.get_string_size(part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 6
		text(Vector2(x, y), part[1], 17, part[2])
		x += font.get_string_size(part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 22
	# Right end: the time to the end, the speed and PAUSED
	var right := p.end.x - 20
	var left_s := int(ceilf(info[4]))
	var time_s := "-%d:%02d" % [int(left_s / 60.0), left_s % 60]
	right_text(Vector2(right, y), time_s, 17, UI_TEXT)
	right -= font.get_string_size(time_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 14
	var chip := Rect2(right - 42, y - 17, 42, 22)
	ui_button_bg(chip, true, speed != 1.0)
	var sp := "x%s" % str(speed).trim_suffix(".0")
	text(Vector2(chip.get_center().x - font.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x / 2.0, y - 1), sp, 14, UI_GOLD_LIGHT)
	right = chip.position.x - 10
	if paused:
		right_text(Vector2(right, y), "PAUSED", 15, Color(1.0, 0.75, 0.35))
	# Row 2: the keys
	text(Vector2(p.position.x + 24, p.position.y + 52), "Space: pause    Left / Right: 5 seconds    F: speed    Click the bar: jump    V or Esc: back to the stats    R: play again", 13, UI_DIM)
	draw_replay_track(frames, get("replay_t"))
	hud.draw_set_transform(Vector2.ZERO)


func draw_replay_track(frames: Array, now: float) -> void:
	var r := REPLAY_TRACK
	hud.draw_rect(r.grow(2), Color(0.03, 0.03, 0.035))
	bevel(r.grow(3), 1, Color(0.08, 0.06, 0.03), UI_GOLD_DARK)
	var first: float = frames[0][0]
	var span := maxf(frames[-1][0] - first, 0.01)
	var cx := r.position.x + clampf((now - first) / span, 0.0, 1.0) * r.size.x
	var w := maxf(r.size.x / frames.size(), 1.0) + 0.6
	# Monsters alive, as a share of the limit: green to red, dimmer ahead of the playhead
	for f: Array in frames:
		var fx: float = r.position.x + (f[0] - first) / span * r.size.x
		var k := clampf(float(f[2]) / maxf(f[3], 1.0), 0.0, 1.0)
		var col := Color(0.3, 0.95, 0.35).lerp(Color(1.0, 0.85, 0.2), minf(k * 2.0, 1.0)).lerp(Color(1.0, 0.2, 0.15), maxf(k * 2.0 - 1.0, 0.0))
		if fx > cx:
			col = col.darkened(0.65)
		hud.draw_line(Vector2(fx, r.end.y), Vector2(fx, r.end.y - maxf(k * r.size.y, 1.0)), col, w)
	# The limit along the top, and a tick with the number where each wave starts
	hud.draw_line(r.position, Vector2(r.end.x, r.position.y), Color(1.0, 0.3, 0.25, 0.45), 1.0)
	var prev := -1
	for f: Array in frames:
		if f[1] != prev and prev >= 0:
			var fx: float = r.position.x + (f[0] - first) / span * r.size.x
			hud.draw_line(Vector2(fx, r.position.y), Vector2(fx, r.end.y), Color(1, 1, 1, 0.45), 1.0)
			hud.draw_string_outline(font, Vector2(fx + 3, r.position.y + 10), "W%d" % f[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.8))
			text(Vector2(fx + 3, r.position.y + 10), "W%d" % f[1], 10, Color(1, 1, 1, 0.85))
		prev = f[1]
	# The playhead: a gold line with a diamond on top
	hud.draw_line(Vector2(cx, r.position.y - 4), Vector2(cx, r.end.y + 4), Color(0, 0, 0, 0.6), 4.0)
	hud.draw_line(Vector2(cx, r.position.y - 4), Vector2(cx, r.end.y + 4), UI_GOLD_LIGHT, 2.0)
	diamond(Vector2(cx, r.position.y - 6), 6.0, UI_GOLD_DARK)
	diamond(Vector2(cx, r.position.y - 6), 4.5, UI_GOLD_LIGHT)


# While the replay plays, the map's edges darken to a deep red, like an old film.
func draw_replay_vignette() -> void:
	var s := Rect2(0, TOP_BAR_H, SCREEN_W, BAR_TOP + ui_extra - TOP_BAR_H)
	hud.draw_rect(s, Color(0.3, 0.08, 0.03, 0.12))
	var deep := 210.0
	var edge := Color(0.22, 0.02, 0.01, 0.8)
	var clear := Color(0.18, 0.02, 0.01, 0.0)
	var o := [s.position, Vector2(s.end.x, s.position.y), s.end, Vector2(s.position.x, s.end.y)]
	var i := [s.position + Vector2(deep, deep * 0.7), Vector2(s.end.x - deep, s.position.y + deep * 0.7), s.end - Vector2(deep, deep * 0.7), Vector2(s.position.x + deep, s.end.y - deep * 0.7)]
	for side in 4:
		var n := (side + 1) % 4
		hud.draw_polygon(PackedVector2Array([o[side], o[n], i[n], i[side]]), PackedColorArray([edge, edge, clear, clear]))
	hud.draw_rect(s.grow(-2), Color(0.85, 0.15, 0.1, 0.6), false, 3.0)


# ---------------------------------------------------------------- pings (Alt + click)

var pings := []  # [slot, pos (map pixels), seconds left]


func show_ping(slot: int, pos: Vector2) -> void:
	if slot < 0 or slot >= MAX_PLAYERS:
		return
	pings.append([slot, pos, PING_TIME])
	play_sound("ping", pos)
	if pings.size() > 12:
		pings.pop_front()


# On the map: rings spreading on the ground, a bobbing marker and the name, all
# in the player's color. Off screen: an arrow at the screen's edge pointing to it.
func draw_pings() -> void:
	var view := Rect2(0, TOP_BAR_H, SCREEN_W, BAR_TOP + ui_extra - TOP_BAR_H)
	for g: Array in pings:
		var slot: int = g[0]
		var col: Color = ink_of(slot)
		var light := col.lightened(0.35)
		var age: float = PING_TIME - g[2]
		var a := clampf(g[2] / 0.5, 0.0, 1.0) * clampf(age / 0.12, 0.0, 1.0)
		var ground := to3d(g[1], 0.03)
		var behind := camera.is_position_behind(ground)
		var c := camera.unproject_position(ground)
		if not behind and view.grow(-16).has_point(c):
			for k in 2:
				var ph := fmod(age * 1.1 + k * 0.5, 1.0)
				ground_ring(g[1], CELL * (0.3 + ph * 0.9), Color(light, a * (1.0 - ph)), 3.5)
			ground_ring(g[1], CELL * 0.25, Color(0, 0, 0, a * 0.5), 4.5)
			ground_ring(g[1], CELL * 0.25, Color(light, a), 2.5)
			var tip := camera.unproject_position(ground + Vector3(0, 0.7, 0)) + Vector2(0, sin(age * 6.0) * 3.0)
			hud.draw_line(c, tip, Color(col, a * 0.8), 2.0)
			var head := PackedVector2Array([tip, tip + Vector2(-10, -17), tip + Vector2(10, -17)])
			hud.draw_colored_polygon(head, Color(col, a))
			head.append(tip)
			hud.draw_polyline(head, Color(0, 0, 0, 0.7 * a), 1.5)
			outlined(tip + Vector2(0, -24), name_of(slot), 14, Color(light, a))
			continue
		var mid := view.get_center()
		var dir := (c - mid) * (-1.0 if behind else 1.0)
		if dir.length() < 1.0:
			continue
		dir = dir.normalized()
		var inner := view.grow(-30)
		var tx := INF
		var ty := INF
		if absf(dir.x) > 0.001:
			tx = ((inner.end.x if dir.x > 0 else inner.position.x) - mid.x) / dir.x
		if absf(dir.y) > 0.001:
			ty = ((inner.end.y if dir.y > 0 else inner.position.y) - mid.y) / dir.y
		var p := mid + dir * minf(tx, ty)
		var s := 1.0 + 0.18 * sin(age * 8.0)
		var n := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([p + dir * 15.0 * s, p - dir * 8.0 + n * 11.0 * s, p - dir * 8.0 - n * 11.0 * s])
		hud.draw_colored_polygon(tri, Color(col, a))
		tri.append(tri[0])
		hud.draw_polyline(tri, Color(0, 0, 0, 0.75 * a), 1.5)
		outlined(p - dir * 28.0 + Vector2(0, 5), name_of(slot), 13, Color(light, a))


# A circle lying on the ground (map pixels), seen at the camera's angle.
func ground_ring(at: Vector2, radius: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for k in 33:
		var ang := k * TAU / 32.0
		pts.append(camera.unproject_position(to3d(at + Vector2(cos(ang), sin(ang)) * radius, 0.03)))
	hud.draw_polyline(pts, col, width, true)


# ---------------------------------------------------------------- gifts

const GIFT_BOX := Rect2(460, 250, 360, 196)
const GIFT_CANCEL := Rect2(580, 398, 120, 32)
var gift_to := -1  # the gift box is open for this player slot (-1: closed)
var gift_glow := 0.0  # seconds of the gold counter's glow after a gift
var gift_text := ""  # "+250" or "-250", under the gold counter


func can_gift(slot: int) -> bool:
	return state == "playing" and (net_mode == "host" or net_mode == "client") and slot >= 0 and slot < MAX_PLAYERS \
			and slot != local_slot and players[slot] != null and not replaying()


func open_gift(slot: int) -> void:
	if can_gift(slot):
		gift_to = slot
	elif state != "playing":
		flash("Gold can only be given while playing")


func gift_amount(i: int) -> int:
	return int(gold * GIFT_SHARES[i])


func gift_button_rect(i: int) -> Rect2:
	return Rect2(GIFT_BOX.position.x + 20 + i * 110, GIFT_BOX.position.y + 90, 100, 54)


# The Esc menu's "Give gold" button in a player's row (see draw_player_list()).
func gift_menu_rect(slot: int) -> Rect2:
	var pos := Vector2(HOST_RECT.position.x, 428 if net_mode == "host" else 266)
	var y := pos.y + 24
	for s in slot:
		if players[s] != null:
			y += 24
	return Rect2(pos.x + 300, y - 17, 120, 22)


# The console's player dots (see draw_wave_info()): [slot, center].
func player_dots() -> Array:
	var out := []
	var px := float(INFO_X)
	for slot in MAX_PLAYERS:
		if players[slot] != null:
			out.append([slot, Vector2(px + 6, BAR_TOP + 140)])
			px += 22
	return out


# Another player's dot under the mouse (a click gives them gold), or -1.
func hovered_dot() -> int:
	if menu_open or gift_to >= 0 or update_dialog != "" or not (net_mode == "host" or net_mode == "client") or state != "playing":
		return -1
	var p := ui_mouse()
	for d: Array in player_dots():
		if d[0] != local_slot and p.distance_to(d[1]) <= 10.0:
			return d[0]
	return -1


# Clicks and Esc for the gift box, and clicks on the player dots. True: used.
func gift_input(event: InputEvent) -> bool:
	if gift_to >= 0:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			gift_to = -1
			return true
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var p := ui_mouse(true)
			for i in GIFT_SHARES.size():
				if gift_button_rect(i).has_point(p):
					if gift_amount(i) >= 1:
						call("act", "gift", [gift_to, gift_amount(i)])  # act() is in main.gd, after this file
						gift_to = -1
					return true
			if GIFT_CANCEL.has_point(p) or not GIFT_BOX.has_point(p):
				gift_to = -1
			return true
		return false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not event.alt_pressed:
		var slot := hovered_dot()
		if slot >= 0:
			open_gift(slot)
			return true
	return false


func draw_gift_box() -> void:
	var b := GIFT_BOX
	hud.draw_rect(b.grow(8), Color(0, 0, 0, 0.35))
	ui_box(b)
	var who := name_of(gift_to)
	var head := "Give gold to "
	var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var ww := font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var hx := b.get_center().x - (hw + ww) / 2.0
	text(Vector2(hx, b.position.y + 40), head, 20, Color(1, 0.85, 0.3))
	text(Vector2(hx + hw, b.position.y + 40), who, 20, ink_of(gift_to).lightened(0.3))
	centered(b.position.y + 68, "You have %s gold. Pick how much:" % short(gold), 15, UI_GREY)
	for i in GIFT_SHARES.size():
		var r := gift_button_rect(i)
		var amount := gift_amount(i)
		var ok := amount >= 1
		ui_button_bg(r, ok, false)
		var pct := "%d%%" % roundi(GIFT_SHARES[i] * 100.0)
		var pw := font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		text(Vector2(r.get_center().x - pw / 2.0, r.position.y + 24), pct, 19, UI_TEXT if ok else UI_DIM)
		var g := short(amount) + "g"
		var gw := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		text(Vector2(r.get_center().x - gw / 2.0, r.position.y + 44), g, 14, Color(1, 0.85, 0.3) if ok else UI_DIM)
	button(GIFT_CANCEL, "Cancel (Esc)")


# Gifts come with a message for the giver and the one who gets it (gift_gold()
# in game_net.gd): the gold counter lights up and the amount drifts under it.
func flash(t: String) -> void:
	super(t)
	flash_ms = Time.get_ticks_msec()
	flash_menu = menu_open
	var got := RegEx.create_from_string("gave you (\\S+) gold").search(t)
	var gave := RegEx.create_from_string("^You gave (\\S+) gold").search(t)
	if got != null:
		gift_text = "+" + got.get_string(1)
		play_sound("gift")
		gift_glow = 2.2
	elif gave != null:
		gift_text = "-" + gave.get_string(1)
		play_sound("gift", Vector2.INF, -4.0, 0.85)
		gift_glow = 2.2


func draw_gift_glow(gold_end: float) -> void:
	var k := clampf(gift_glow / 2.2, 0.0, 1.0)
	var w := font.get_string_size(short(gold), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var r := Rect2(gold_end - w - 32, 3, w + 38, TOP_BAR_H - 6)
	var pulse := 0.6 + 0.4 * sin(gift_glow * 12.0)
	hud.draw_rect(r, Color(1, 0.8, 0.25, 0.22 * k * pulse))
	hud.draw_rect(r, Color(UI_GOLD_LIGHT, 0.9 * k), false, 1.5)
	# Coins popping out of the counter
	var c := r.get_center()
	var t := 1.0 - k
	for i in 7:
		var dir := Vector2.from_angle(PI * 0.15 + i * PI * 0.7 / 6.0)
		var p := c + dir * (12.0 + t * 46.0) + Vector2(0, t * t * 30.0)
		hud.draw_circle(p, 4.5 * k + 1.0, Color(0.3, 0.18, 0.04, k))
		hud.draw_circle(p, 3.5 * k + 0.6, Color(1.0, 0.82, 0.3, k))
	var got := gift_text.begins_with("+")
	outlined(Vector2(c.x, TOP_BAR_H + 20 + t * 16.0), gift_text + " gold", 17, Color(0.55, 1.0, 0.5, k) if got else Color(1.0, 0.6, 0.45, k))


# ---------------------------------------------------------------- daily challenge

# Is a daily or weekly challenge being played? (Its banner shows under the top bar.)
func challenge_on() -> bool:
	return daily_date != "" or weekly_id != ""


const BANNER_MAX_W := 820.0  # wider than this, the weekly banner leaves out its twists' text
var banner_cache := []  # [key, head, twist, tail, head w, twist w, tail w]: made once per challenge


# The banner's texts and widths, worked out again only when the challenge changes.
func banner_texts() -> Array:
	var key := "d" + daily_date if daily_date != "" else "w" + weekly_id
	if not banner_cache.is_empty() and banner_cache[0] == key:
		return banner_cache
	var rules := challenge_rules()
	if rules.is_empty():
		return []
	var head := "DAILY %s" % daily_date
	var tail := "%s   %d waves" % [DIFFICULTIES[difficulty], DAILY_WAVES]
	if daily_date == "":
		head = weekly_title(weekly_id).to_upper()
		tail = "%s   %d waves   Rising tide from wave %d" % [DIFFICULTIES[WEEKLY_LEVEL], WEEKLY_WAVES, WEEKLY_TIDE_FROM]
	var twist := "%s:  %s" % [rules.get("name", ""), rules.get("desc", "")]
	var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var lw := font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var tw := font.get_string_size(twist, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	if hw + tw + lw + 48.0 > BANNER_MAX_W:
		twist = str(rules.get("name", ""))
		tw = font.get_string_size(twist, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	banner_cache = [key, head, twist, tail, hw, tw, lw]
	return banner_cache


# Under the top bar while playing the daily or weekly challenge: the day or
# week, its twist(s) and level.
func draw_daily_banner() -> void:
	var b := banner_texts()
	if b.is_empty():
		return
	var head: String = b[1]
	var twist: String = b[2]
	var tail: String = b[3]
	var hw: float = b[4]
	var tw: float = b[5]
	var lw: float = b[6]
	var total := hw + tw + lw + 48.0
	var r := Rect2((SCREEN_W - total) / 2.0 - 18.0, TOP_BAR_H + 9, total + 36.0, 26)
	# A ribbon: dark cloth with gold edges and cut ends
	var y0 := r.position.y
	var y1 := r.end.y
	for side in 2:
		var x := r.position.x if side == 0 else r.end.x
		var out := -14.0 if side == 0 else 14.0
		quad(PackedVector2Array([Vector2(x, y0 + 3), Vector2(x + out, y0 + 3), Vector2(x + out * 0.55, (y0 + y1) / 2.0 + 1.5), Vector2(x + out, y1 + 3)]), Color(0.28, 0.07, 0.05, 0.92))
		hud.draw_line(Vector2(x, y1 + 3), Vector2(x + out, y1 + 3), Color(0, 0, 0, 0.5), 1.0)
	vgrad(r, Color(0.45, 0.12, 0.08, 0.95), Color(0.3, 0.07, 0.05, 0.95))
	bevel(r, 2, UI_GOLD_LIGHT, UI_GOLD_DARK)
	var x := r.position.x + 18.0
	var y := r.position.y + 18.0
	text(Vector2(x, y), head, 15, Color(1, 0.85, 0.3))
	x += hw + 24.0
	text(Vector2(x, y), twist, 15, UI_TEXT)
	x += tw + 24.0
	text(Vector2(x, y), tail, 15, level_color())


# ---------------------------------------------------------------- holiday festivals
# For the first seconds of a new game: a ribbon with today's festival
# (festival_today(), FESTIVAL_BANNERS), picked once when the game starts.

const FEST_SHOW := 8.0  # seconds on screen
const FEST_FADE := 0.6
const FEST_COLORS := {"frostfall": [Color(0.16, 0.3, 0.46), Color(0.09, 0.17, 0.28)],
		"lantern": [Color(0.42, 0.18, 0.04), Color(0.24, 0.09, 0.03)],
		"paint": [Color(0.34, 0.24, 0.44), Color(0.2, 0.13, 0.27)]}
var fest_name := ""  # this game's festival ("" none)
var fest_t := 0.0  # seconds since the game started
var fest_fresh := false  # a new game (wave 0) last frame
var fest_texts := []  # [head, rest, head w, rest w]: made once per game


# Every frame: a new game (wave 0, not the editor) picks the festival again.
func update_festival(delta: float) -> void:
	var fresh := state == "playing" and wave == 0 and not bool(get("editing")) and not replaying()
	if fresh and not fest_fresh:
		fest_name = festival_today()
		fest_t = 0.0
		fest_texts = []
		if fest_name != "":
			# The name (up to the "!") in gold, the rest in white
			var s: String = FESTIVAL_BANNERS.get(fest_name, FESTIVAL_NAMES.get(fest_name, ""))
			var cut := s.find("!") + 1
			var head := s.substr(0, cut) if cut > 0 else ""
			var rest := s.substr(cut).strip_edges()
			fest_texts = [head, rest, font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x,
					font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x]
	fest_fresh = fresh
	if fest_name != "":
		fest_t += delta


# A ribbon like the daily's, in the festival's colors, fading in and out.
func draw_festival_banner(y: float) -> void:
	if fest_texts.is_empty():
		return
	var a := clampf(minf(fest_t / FEST_FADE, (FEST_SHOW - fest_t) / FEST_FADE), 0.0, 1.0)
	var hw: float = fest_texts[2]
	var rw: float = fest_texts[3]
	var gap := 10.0 if hw > 0.0 else 0.0
	var total := 26.0 + hw + gap + rw
	var r := Rect2((SCREEN_W - total) / 2.0 - 18.0, y, total + 36.0, 26)
	var cols: Array = FEST_COLORS.get(fest_name, FEST_COLORS["lantern"])
	for side in 2:
		var x := r.position.x if side == 0 else r.end.x
		var out := -14.0 if side == 0 else 14.0
		quad(PackedVector2Array([Vector2(x, r.position.y + 3), Vector2(x + out, r.position.y + 3), Vector2(x + out * 0.55, r.get_center().y + 1.5), Vector2(x + out, r.end.y + 3)]), Color(cols[1], 0.92 * a))
	vgrad(r, Color(cols[0], 0.95 * a), Color(cols[1], 0.95 * a))
	bevel(r, 2, Color(UI_GOLD_LIGHT, a), Color(UI_GOLD_DARK, a))
	festival_icon(Vector2(r.position.x + 26.0, r.get_center().y), a)
	var x := r.position.x + 44.0
	text(Vector2(x, r.position.y + 18), fest_texts[0], 15, Color(1, 0.85, 0.3, a))
	text(Vector2(x + hw + gap, r.position.y + 18), fest_texts[1], 15, Color(UI_TEXT, a))


# A little mark: a snowflake, a pumpkin lantern or paint drops.
func festival_icon(c: Vector2, a: float) -> void:
	match fest_name:
		"frostfall":
			for k in 3:
				var d := Vector2.from_angle(k * PI / 3.0) * 7.0
				hud.draw_line(c - d, c + d, Color(0.85, 0.95, 1.0, a), 2.0)
		"lantern":
			hud.draw_circle(c + Vector2(0, 1), 7.0, Color(0.95, 0.5, 0.1, a))
			hud.draw_rect(Rect2(c + Vector2(-1, -9), Vector2(2.5, 4)), Color(0.3, 0.5, 0.15, a))
			hud.draw_circle(c + Vector2(-2.5, 0), 1.4, Color(1, 0.9, 0.4, a))
			hud.draw_circle(c + Vector2(2.5, 0), 1.4, Color(1, 0.9, 0.4, a))
		"paint":
			hud.draw_circle(c + Vector2(-4, 2), 4.0, Color(1, 0.55, 0.7, a))
			hud.draw_circle(c + Vector2(4, 3), 3.5, Color(0.5, 0.85, 1.0, a))
			hud.draw_circle(c + Vector2(0, -4), 3.5, Color(1, 0.9, 0.4, a))


# ---------------------------------------------------------------- saving and loading
# main.gd does the saving (it comes after this file), so it's called by name:
# can_save(), can_load(), default_save_name(), save_exists(), list_saves(),
# save_game(), menu_load(), delete_save() and held_text().

const LOADED_NOTE := "Loaded game: not on the leaderboard"
const LOADED_COLOR := Color(1.0, 0.68, 0.42)
# The Save box: a name, then Save (or Overwrite) and Cancel
const SAVE_BOX := Rect2(410, 214, 460, 262)
const SAVE_INPUT_RECT := Rect2(496, 296, 344, 36)
const SAVE_OK_RECT := Rect2(450, 416, 180, 40)
const SAVE_CANCEL_RECT := Rect2(650, 416, 180, 40)
# The Load list: a row per save with Load and Delete
const LOAD_BOX := Rect2(330, 60, 620, 600)
const LOAD_ROWS := 8
const LOAD_ROW_H := 50
const LOAD_CLOSE_RECT := Rect2(560, 604, 160, 40)

var save_input: LineEdit
var save_open := false
var save_suggest := ""  # default_save_name() when the box opened
var save_confirm := ""  # the name the Save box asks "Overwrite?" about
var load_open := false
var load_rows := []  # the saves, read once when the list opens (see save_row())
var load_top := 0
var load_confirm := ""  # the save whose Delete asks "Are you sure?"
var flash_ms := -100000  # when the last flash() came
var flash_menu := false  # ...and whether the Esc menu was open then


# The last flash() for a few seconds, for boxes over the message line.
func recent_message() -> String:
	return message if Time.get_ticks_msec() - flash_ms < 3500 else ""


# The same, if it came while the Esc menu was open (not the game's own news).
func menu_message() -> String:
	return recent_message() if flash_menu else ""


func close_save_boxes() -> void:
	save_open = false
	load_open = false
	save_confirm = ""
	load_confirm = ""
	if save_input != null:
		save_input.release_focus()
		save_input.visible = false


# Every frame: the boxes close with the menu, and the menu's own text boxes hide under them.
func update_save_boxes() -> void:
	if not menu_open and (save_open or load_open):
		close_save_boxes()
	if save_input.visible != save_open:
		if not save_open:
			save_input.release_focus()
		save_input.visible = save_open
	if save_open or load_open:
		code_input.visible = false
		name_input.visible = false


func open_save_box() -> void:
	var why: String = call("can_save")
	if why != "":
		flash(why)
		return
	code_input.release_focus()
	name_input.release_focus()
	save_open = true
	save_confirm = ""
	save_suggest = call("default_save_name")
	save_input.text = save_suggest
	save_input.visible = true
	save_input.grab_focus()
	save_input.select_all()


# The "Suggested:" line under the name: a click puts it back in the box.
func save_suggest_rect() -> Rect2:
	return Rect2(SAVE_INPUT_RECT.position.x, SAVE_INPUT_RECT.end.y + 6, SAVE_INPUT_RECT.size.x, 22)


func draw_save_box() -> void:
	var b := SAVE_BOX
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.5))
	ui_box(b)
	var title := "SAVE GAME"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	ui_title(Rect2(b.position.x, b.position.y, b.size.x, 60), Vector2((SCREEN_W - tw) / 2.0, b.position.y + 44), title, 34)
	text(Vector2(b.position.x + 30, SAVE_INPUT_RECT.position.y + 24), "Name:", 16, UI_TEXT)
	var sr := save_suggest_rect()
	var over := sr.has_point(ui_mouse(true))
	text(sr.position + Vector2(2, 16), fit_text("Suggested: " + save_suggest, sr.size.x - 4, 13), 13, UI_GOLD_LIGHT if over else UI_DIM)
	if save_confirm != "":
		centered(SAVE_OK_RECT.position.y - 34, fit_text("There's already a save called \"%s\"." % save_confirm, b.size.x - 40, 15), 15, Color(1, 0.75, 0.5))
		centered(SAVE_OK_RECT.position.y - 12, "Overwrite it?", 16, Color(1, 0.85, 0.3))
		button(SAVE_OK_RECT, "Overwrite", true, true)
	else:
		var note := menu_message()
		if note != "":
			centered(SAVE_OK_RECT.position.y - 18, fit_text(note, b.size.x - 40, 15), 15, Color(1, 0.75, 0.5))
		button(SAVE_OK_RECT, "Save (Enter)", true, true)
	button(SAVE_CANCEL_RECT, "Cancel (Esc)")


func save_click(p: Vector2) -> void:
	if SAVE_CANCEL_RECT.has_point(p) or not SAVE_BOX.has_point(p):
		close_save_boxes()
		return
	if save_suggest_rect().has_point(p):
		save_input.text = save_suggest
		save_input.caret_column = save_suggest.length()
		save_confirm = ""
		save_input.grab_focus()
		return
	if not SAVE_OK_RECT.has_point(p):
		return
	var n := clean_text(save_input.text, SAVE_NAME_MAX)
	if n == "":
		n = save_suggest
	# Same name as a save there is: ask first
	if n != save_confirm and call("save_exists", n):
		save_confirm = n
		save_input.release_focus()
		return
	var problem: String = call("save_game", n)
	flash(problem if problem != "" else "Saved \"%s\"" % n)
	if problem == "":
		close_save_boxes()
	else:
		save_confirm = ""


func open_load_box() -> void:
	code_input.release_focus()
	name_input.release_focus()
	read_load_rows()
	load_top = 0
	load_confirm = ""
	load_open = true


# The saves' headers, made into the list's lines once (not every frame).
func read_load_rows() -> void:
	load_rows.clear()
	for h: Variant in call("list_saves"):
		if h is Dictionary:
			load_rows.append(save_row(h))
	load_top = clampi(load_top, 0, maxi(load_rows.size() - LOAD_ROWS, 0))


# A save's header (from a file, so checked) as {name, title, auto, wave, level, color, rest}.
func save_row(h: Dictionary) -> Dictionary:
	var n := str(h.get("name", ""))
	var title := clean_text(n, SAVE_NAME_MAX)
	var auto := n == AUTOSAVE_NAME or n == QUICKSAVE_NAME
	if n == AUTOSAVE_NAME:
		title = "Continue  (autosave)"
	elif n == QUICKSAVE_NAME:
		title = "Quicksave  (F5 / F9)"
	var lv := clampi(h.get("level") if h.get("level") is int else 1, 0, DIFFICULTIES.size() - 1)
	var w: int = h.get("wave") if h.get("wave") is int else 0
	var daily := clean_text(str(h.get("daily", "")), 12)
	var map_s := "Daily " + daily if daily != "" else clean_text(str(h.get("map", "")), MAP_NAME_MAX)
	var week := clean_text(str(h.get("weekly", "")), 12)
	if daily == "" and week != "":
		map_s = "Weekly " + week
	var names: Array = h.get("players") if h.get("players") is Array else []
	var who := "alone"
	if names.size() > 1:
		var list := []
		for s: Variant in names:
			list.append(clean_text(str(s), NAME_MAX))
		who = "%d players (%s)" % [names.size(), ", ".join(list)]
	var t: int = h.get("time") if h.get("time") is int else 0
	var parts := [map_s, who]
	if t > 0:
		parts.push_front(date_text(t))
	return {"name": n, "title": title, "auto": auto, "level": DIFFICULTIES[lv], "color": LEVEL_COLORS[lv],
			"wave": "Wave %d%s   " % [w, " (endless)" if h.get("endless") == true else ""], "rest": "   " + "   ".join(parts)}


# "2026-11-02 14:05" in this computer's time.
func date_text(unix: int) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]


func load_row_rect(i: int) -> Rect2:
	return Rect2(LOAD_BOX.position.x + 24, LOAD_BOX.position.y + 96 + i * LOAD_ROW_H, LOAD_BOX.size.x - 48, LOAD_ROW_H - 4)


# A row's buttons: 0 Load (or Delete when asking), 1 Delete (or Keep).
func load_button_rect(i: int, k: int) -> Rect2:
	var row := load_row_rect(i)
	return Rect2(row.end.x - 176 + k * 88, row.position.y + 8, 80, 30)


func draw_load_box() -> void:
	var b := LOAD_BOX
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.5))
	ui_box(b)
	var title := "LOAD GAME"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	ui_title(Rect2(b.position.x, b.position.y, b.size.x, 60), Vector2((SCREEN_W - tw) / 2.0, b.position.y + 44), title, 34)
	var why: String = call("can_load")
	if why != "":
		centered(b.position.y + 84, why, 15, Color(1, 0.75, 0.5))
	else:
		centered(b.position.y + 84, "Newest first. Loaded games don't go on the leaderboard.", 14, UI_GREY)
	if load_rows.is_empty():
		centered(b.position.y + 200, "No saved games yet.", 18, UI_TEXT)
		centered(b.position.y + 228, "Save from this menu, or press F5 while playing.", 15, UI_GREY)
	for i in mini(LOAD_ROWS, load_rows.size() - load_top):
		var s: Dictionary = load_rows[load_top + i]
		var row := load_row_rect(i)
		var sure: bool = load_confirm == s.name
		hud.draw_rect(row, Color(0.45, 0.12, 0.08, 0.4) if sure else Color(0, 0, 0, 0.28 if i % 2 == 0 else 0.16))
		var x := row.position.x + 12
		var room := load_button_rect(i, 0).position.x - x - 10
		if sure:
			text(Vector2(x, row.position.y + 20), fit_text("Delete \"%s\"?" % s.title, room, 16), 16, Color(1, 0.6, 0.5))
			text(Vector2(x, row.position.y + 39), "Are you sure? This can't be undone.", 13, UI_GREY)
			button(load_button_rect(i, 0), "Delete", true, true)
			button(load_button_rect(i, 1), "Keep")
			continue
		text(Vector2(x, row.position.y + 20), fit_text(s.title, room, 16), 16, UI_GOLD_LIGHT if s.auto else UI_TEXT)
		# "Wave 37   Normal   2026-11-02 14:05   Default   alone", the level in its color
		var y := row.position.y + 39
		text(Vector2(x, y), s.wave, 13, UI_GREY)
		x += font.get_string_size(s.wave, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		text(Vector2(x, y), s.level, 13, s.color)
		x += font.get_string_size(s.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		text(Vector2(x, y), fit_text(s.rest, row.position.x + 12 + room - x, 13), 13, UI_GREY)
		button(load_button_rect(i, 0), "Load", why == "", s.name == AUTOSAVE_NAME)
		button(load_button_rect(i, 1), "Delete")
	var note := menu_message()
	if note != "":
		centered(LOAD_CLOSE_RECT.position.y - 14, fit_text(note, b.size.x - 40, 15), 15, Color(1, 1, 0.6))
	elif load_rows.size() > LOAD_ROWS:
		centered(LOAD_CLOSE_RECT.position.y - 14, "Scroll for more (%d saves)" % load_rows.size(), 13, UI_DIM)
	button(LOAD_CLOSE_RECT, "Back (Esc)", true, true)


func load_click(p: Vector2) -> void:
	if LOAD_CLOSE_RECT.has_point(p) or not LOAD_BOX.has_point(p):
		close_save_boxes()
		return
	for i in mini(LOAD_ROWS, load_rows.size() - load_top):
		var s: Dictionary = load_rows[load_top + i]
		if load_button_rect(i, 0).has_point(p):
			if load_confirm == s.name:
				# The second click: delete it
				load_confirm = ""
				var problem: String = call("delete_save", s.name)
				flash(problem if problem != "" else "Deleted \"%s\"" % s.title)
				read_load_rows()
				return
			load_confirm = ""
			var why: String = call("can_load")
			if why != "":
				flash(why)
				return
			call("menu_load", s.name)
			if not menu_open:
				close_save_boxes()  # loaded: the menu closed for the game
			return
		if load_button_rect(i, 1).has_point(p):
			load_confirm = "" if load_confirm == s.name else s.name
			return
	load_confirm = ""


# While a loaded game is held: who it waits for, and Space to go on (held_text() in main.gd).
func draw_held_line(y: float) -> void:
	var s: String = call("held_text")
	if s == "":
		return
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var r := Rect2((SCREEN_W - w) / 2.0 - 34.0, y, w + 52.0, 26)
	hud.draw_rect(r.grow(3), Color(0, 0, 0, 0.35))
	vgrad(r, Color(0.2, 0.18, 0.15, 0.95), Color(0.1, 0.09, 0.08, 0.95))
	bevel(r, 2, UI_GOLD_LIGHT, UI_GOLD_DARK)
	# A pause mark that slowly pulses
	var a := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 400.0)
	hud.draw_rect(Rect2(r.position.x + 12, r.position.y + 7, 4, 12), Color(UI_GOLD_LIGHT, a))
	hud.draw_rect(Rect2(r.position.x + 19, r.position.y + 7, 4, 12), Color(UI_GOLD_LIGHT, a))
	text(Vector2(r.position.x + 34, r.position.y + 18), s, 15, UI_TEXT)


# ---------------------------------------------------------------- tutorial tips
# The tip on screen (current_tip() in game_base.gd): a card with the text, an
# arrow to what it's about, and Got it / Skip all tips. Drawn in screen pixels,
# always ending above the console's click split (BAR_TOP - 60), where screen and
# layout pixels are the same, so on_click()'s point hits it on 16:10 too.

const TIP_W := 420.0
const TIP_LOW := BAR_TOP - 64.0  # the card's lowest bottom edge
const TIP_TEXT := 16
var alive_spot := Vector2(1000, TOP_BAR_H)  # under the top bar's monster count (see draw_top_bar)
var tip_lines_for := ""  # the text tip_lines was wrapped for
var tip_lines := PackedStringArray()


# The card: {rect, got, skip, target (screen point or null)}, or {} when none shows.
# Hidden under the Esc menu and popups, and while a button's tooltip is up.
func tip_layout() -> Dictionary:
	var tip := current_tip()
	if tip.is_empty() or tip.get("story", false) or menu_open or gift_to >= 0 or update_dialog != "":
		return {}  # a story card has its own look (see draw_story_card)
	if hovered_card() >= 0 or hovered_chip() >= 0:
		return {}
	if tip["text"] != tip_lines_for:
		tip_lines_for = tip["text"]
		tip_lines = wrap_words(tip_lines_for, TIP_W - 28.0, TIP_W - 28.0, TIP_TEXT)
	var h := 84.0 + tip_lines.size() * 20.0
	var anchor: Variant = tip["anchor"]
	var target: Variant = null
	var glow := Rect2()  # a console spot to light up (screen pixels)
	# Top middle of the map unless the anchor says otherwise
	var x := (SCREEN_W - TIP_W) / 2.0
	var y := 96.0
	if anchor is Vector2:
		# A tower: above it and a bit to the side, below it near the top, beside it as a last resort
		var s := camera.unproject_position(to3d(anchor, 0.8))
		target = s
		x = s.x - TIP_W * 0.3
		y = s.y - 70.0 - h
		if y < TOP_BAR_H + 12.0:
			y = s.y + 60.0
		if y + h > TIP_LOW:
			y = s.y - h / 2.0
			x = s.x + 70.0 if s.x < SCREEN_W / 2.0 else s.x - 70.0 - TIP_W
	else:
		match anchor:
			"tower_buttons":
				glow = Rect2(tower_button_rect(0).position, tower_button_rect(TOWER_TYPES.size() - 1).end - tower_button_rect(0).position)
			"wave_button":
				glow = WAVE_RECT
			"target_button":
				glow = MODE_RECT
			"ability_buttons":
				glow = ability_button_rect(0).merge(ability_button_rect(ABILITY_ORDER.size() - 1))
			"wave_preview":
				glow = chip_spots[0][0] if not chip_spots.is_empty() else Rect2(INFO_X, BAR_TOP + 54, 80, 22)
				for s: Array in chip_spots:
					glow = glow.merge(s[0])
			"alive_counter":
				target = alive_spot + Vector2(0, 4)
				x = alive_spot.x - TIP_W * 0.6
				y = TOP_BAR_H + 60.0
			"cursor":
				target = get_viewport().get_mouse_position()
		if glow.size.x > 0.0:
			# In the console (ui_extra lower on 16:10): the thing glows and the arrow
			# stops at the console's top edge, so it never crosses other buttons
			glow.position.y += ui_extra
			target = Vector2(glow.get_center().x, BAR_TOP + ui_extra - 4.0)
			x = target.x - TIP_W / 2.0
			y = TIP_LOW - h
	x = clampf(x, 16.0, SCREEN_W - TIP_W - 16.0)
	y = clampf(y, TOP_BAR_H + 12.0, TIP_LOW - h)
	var r := Rect2(x, y, TIP_W, h)
	var got := Rect2(r.end.x - 114, r.end.y - 38, 100, 28)
	return {"rect": r, "got": got, "skip": Rect2(got.position.x - 140, got.position.y, 130, 28), "target": target, "glow": glow}


func draw_tip_card() -> void:
	var l := tip_layout()
	if l.is_empty():
		return
	var r: Rect2 = l["rect"]
	var glow: Rect2 = l["glow"]
	if glow.size.x > 0.0:
		var a := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
		hud.draw_rect(glow.grow(7), Color(UI_GOLD_LIGHT, a * 0.25), false, 4.0)
		hud.draw_rect(glow.grow(4), Color(0, 0, 0, 0.6), false, 3.0)
		hud.draw_rect(glow.grow(3), Color(UI_GOLD_LIGHT, a), false, 2.5)
	if l["target"] != null:
		tip_arrow(r, l["target"])
	hud.draw_rect(r.grow(4), Color(0, 0, 0, 0.35))
	hud.draw_rect(r, Color(0.05, 0.05, 0.055, 0.94))
	inner_shadow(r.grow(-3), 6, 0.3)
	bevel(r, 3, UI_GOLD_LIGHT, UI_GOLD_DARK)
	hud.draw_rect(r.grow(-3), Color(0, 0, 0, 0.6), false, 1.0)
	text(r.position + Vector2(14, 25), "TIP", 15, Color(1, 0.85, 0.3))
	text(r.position + Vector2(50, 25), "%d / %d" % [mini(tips_seen.size() + 1, TIPS.size()), TIPS.size()], 12, UI_DIM)
	for j in tip_lines.size():
		text(r.position + Vector2(14, 50 + j * 20), tip_lines[j], TIP_TEXT, UI_TEXT)
	button(l["skip"], "Skip all tips")
	button(l["got"], "Got it", true, true)


# A gold arrow from the card's nearest edge to the target, bobbing a little.
func tip_arrow(r: Rect2, target: Vector2) -> void:
	if r.grow(24).has_point(target):
		return  # the mouse is on the card: nothing to point at
	var from := Vector2(clampf(target.x, r.position.x + 30, r.end.x - 30), clampf(target.y, r.position.y + 20, r.end.y - 20))
	if target.y > r.end.y:
		from.y = r.end.y
	elif target.y < r.position.y:
		from.y = r.position.y
	elif target.x > r.end.x:
		from.x = r.end.x
	else:
		from.x = r.position.x
	var dir := (target - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tip := target - dir * (6.0 + 3.0 * sin(Time.get_ticks_msec() / 220.0))
	var base := tip - dir * 15.0
	hud.draw_line(from, base, Color(0, 0, 0, 0.6), 5.0)
	hud.draw_line(from, base, UI_GOLD_LIGHT, 2.5)
	hud.draw_colored_polygon(PackedVector2Array([tip + dir * 2.0, base + side * 10.0 - dir * 1.5, base - side * 10.0 - dir * 1.5]), Color(0, 0, 0, 0.6))
	hud.draw_colored_polygon(PackedVector2Array([tip, base + side * 8.0, base - side * 8.0]), UI_GOLD_LIGHT)


# on_click() asks this first: Got it, Skip all tips, and no building through the card.
func tip_click(p: Vector2) -> bool:
	if story_click(p):
		return true
	var l := tip_layout()
	if l.is_empty() or not l["rect"].has_point(p):
		return false
	if l["got"].has_point(p):
		tip_got_it()
	elif l["skip"].has_point(p):
		tip_skip_all()
	return true


# ---------------------------------------------------------------- story cards
# A story card (current_tip() with "story", see STORY_CARDS) is a parchment page
# with the speaker's portrait and name, not a tip. It fades out by itself after
# STORY_SHOW seconds (held while the mouse is on it), then tip_got_it(). On the
# end screen, end_story_card() shows as a narrower page left of the stats.
# Drawn on story_layer so the whole card can fade (made in build_hud, see
# build_story_layer), in screen pixels, above the console's click split.

const STORY_W := 470.0
const END_STORY_W := 210.0  # stops left of the win title (FW_KEEP) and the stats panel
const STORY_SHOW := 12.0  # seconds before it fades out by itself
const STORY_IN := 0.3
const STORY_OUT := 0.6
const PARCH_TOP := Color(0.92, 0.85, 0.67)
const PARCH_LOW := Color(0.8, 0.69, 0.5)
const INK := Color(0.24, 0.15, 0.07)
# The speakers' portrait placeholders: [initial, color] (painted portraits later)
const SPEAKERS := {"Wren": ["W", Color(0.36, 0.62, 0.34)], "Sergeant Thump": ["T", Color(0.72, 0.32, 0.22)],
		"The Ringkeeper": ["R", Color(0.32, 0.5, 0.8)], "Grimwhistle": ["G", Color(0.55, 0.32, 0.82)]}
var story_layer: Node2D
var story_id := ""  # the story card up now ("" none)
var story_end_card := false  # ...and whether it's the end screen's
var story_who := ""
var story_lines := PackedStringArray()  # its text, wrapped once
var story_t := 0.0  # seconds it has been up


func build_story_layer() -> void:
	story_layer = Node2D.new()
	story_layer.visible = false
	hud.add_child(story_layer)  # over the hud's drawing
	story_layer.draw.connect(draw_on.bind(story_layer, draw_story_card))


# The story card to show now: {id, text, who}, or {}.
func story_card() -> Dictionary:
	if state == "playing":
		var tip := current_tip()
		return tip if tip.get("story", false) else {}
	if replaying():
		return {}
	return end_story_card()


# Every frame: picks up a new card, counts its time and closes it when it's faded.
func update_story_card(delta: float) -> void:
	var c := story_card()
	var id: String = c.get("id", "")
	var end := state != "playing"
	if id != story_id or end != story_end_card:
		story_id = id
		story_end_card = end
		story_t = 0.0
		if id != "":
			story_who = c.get("who", "")
			var w := (END_STORY_W - 28.0) if end else (STORY_W - 92.0)
			story_lines = wrap_words(c.text, w, w, 14 if end else 15)
	var shown := story_id != "" and not menu_open and gift_to < 0 and update_dialog == ""
	story_layer.visible = shown
	if not shown:
		return
	story_layer.queue_redraw()
	var l := story_layout()
	var a := clampf(minf(story_t / STORY_IN, (STORY_SHOW + STORY_OUT - story_t) / STORY_OUT), 0.0, 1.0)
	story_layer.modulate.a = a
	# Held while the mouse is on it (once it's fully in)
	if story_t < STORY_IN or not l["rect"].has_point(get_viewport().get_mouse_position()):
		story_t += delta
	if story_t >= STORY_SHOW + STORY_OUT:
		close_story_card()


func close_story_card() -> void:
	if story_end_card:
		end_story_done()
	else:
		tip_got_it()
	story_id = ""
	story_layer.visible = false


# The card's place in screen pixels: {rect, got, skip (none on the end screen)}.
func story_layout() -> Dictionary:
	if story_end_card:
		var h := 72.0 + story_lines.size() * 19.0 + 46.0
		var e := Rect2(14, STATS_TOP + ui_extra / 2.0, END_STORY_W, h)
		return {"rect": e, "got": Rect2(e.position.x + 14, e.end.y - 42, e.size.x - 28, 28), "skip": Rect2()}
	var h := maxf(58.0 + story_lines.size() * 20.0 + 50.0, 126.0)
	var r := Rect2((SCREEN_W - STORY_W) / 2.0, 96, STORY_W, h)
	var got := Rect2(r.end.x - 114, r.end.y - 40, 100, 28)
	return {"rect": r, "got": got, "skip": Rect2(got.position.x - 150, got.position.y, 140, 28)}


func draw_story_card() -> void:
	if story_id == "":
		return
	var l := story_layout()
	var r: Rect2 = l["rect"]
	# Parchment: warm paper, darker at the edges, an inked frame in the gold
	hud.draw_rect(Rect2(r.position + Vector2(3, 5), r.size), Color(0, 0, 0, 0.45))
	vgrad(r, PARCH_TOP, PARCH_LOW)
	inner_shadow(r.grow(-3), 10, 0.22)
	bevel(r, 3, UI_GOLD_LIGHT, UI_GOLD_DARK)
	hud.draw_rect(r.grow(-7), Color(INK, 0.4), false, 1.0)
	var col: Color = SPEAKERS.get(story_who, ["?", Color(0.5, 0.45, 0.4)])[1]
	if story_end_card:
		story_portrait(r.position + Vector2(36, 38), 20.0, story_who)
		hud.draw_string(title_font, r.position + Vector2(64, 36), fit_text(story_who, r.size.x - 78, 18), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col.darkened(0.55))
		hud.draw_line(r.position + Vector2(14, 62), Vector2(r.end.x - 14, r.position.y + 62), Color(INK, 0.35), 1.0)
		for j in story_lines.size():
			text(r.position + Vector2(14, 84 + j * 19), story_lines[j], 14, INK)
	else:
		story_portrait(r.position + Vector2(42, 44), 25.0, story_who)
		hud.draw_string(title_font, r.position + Vector2(80, 34), story_who, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col.darkened(0.55))
		for j in story_lines.size():
			text(r.position + Vector2(80, 60 + j * 20), story_lines[j], 15, INK)
		button(l["skip"], "Turn off story")
	button(l["got"], "Got it", true, true)
	# How long it stays: a thin ink line along the bottom
	var left := clampf(1.0 - story_t / STORY_SHOW, 0.0, 1.0)
	hud.draw_rect(Rect2(r.position.x + 8, r.end.y - 9, (r.size.x - 16) * left, 2), Color(INK, 0.45))


# The speaker's portrait slot: a gold-rimmed medallion with the initial (a painted
# portrait goes here later).
func story_portrait(c: Vector2, radius: float, who: String) -> void:
	var s: Array = SPEAKERS.get(who, ["?", Color(0.5, 0.45, 0.4)])
	hud.draw_circle(c + Vector2(1, 2), radius + 3.0, Color(0, 0, 0, 0.35))
	hud.draw_circle(c, radius + 3.0, UI_GOLD_DARK)
	hud.draw_circle(c, radius + 1.5, UI_GOLD)
	hud.draw_circle(c, radius, s[1].darkened(0.35))
	hud.draw_circle(c - Vector2(0, 2), radius - 3.0, s[1])
	var size := roundi(radius * 1.1)
	var w := title_font.get_string_size(s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := c + Vector2(-w / 2.0, size * 0.36)
	hud.draw_string_outline(title_font, p, s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.6))
	hud.draw_string(title_font, p, s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 0.95, 0.85))


# Got it, Turn off story, and no building through the card.
func story_click(p: Vector2) -> bool:
	if story_layer == null or not story_layer.visible or story_id == "":
		return false
	var l := story_layout()
	if not l["rect"].has_point(p):
		return false
	if l["got"].has_point(p):
		close_story_card()
	elif l["skip"].has_point(p):
		tip_skip_all()  # turns the story cards off (saves itself)
		story_id = ""
		story_layer.visible = false
	return true


# ---------------------------------------------------------------- tower info cards
# Hovering a build button (or its row in the build list): what the tower does,
# its level 4 numbers and both level 5 paths. Every number comes from TOWERS and
# PATHS; the texts are made once per tower (see tower_card()).

const INFO_W := 440.0
const INFO_H := 336.0
# Short words for each tower: what it's good and weak against
const INFO_GOOD_WEAK := {
	"arrow": ["Single monsters, fast ones", "Armor (small hits)"],
	"cannon": ["Groups (splash)", "Fast monsters (slow ball)"],
	"frost": ["Fast monsters, helping other towers", "Low damage on its own"],
	"spark": ["Crowds, long range", "Pricey, chain fades"],
	"poison": ["Armor, crowds on the path", "Fast monsters (walk out of clouds)"],
	"barracks": ["Fast monsters, crowds at a bend", "Bosses (unless Knights)"],
}
var tower_cards := {}  # type -> its card's texts and bar sizes


# Damage a second: one monster's, at a level (Poison's damage already is a second's).
func tower_dps(d: Dictionary, lv: int) -> float:
	if d.has("cloud"):
		return float(d["damage"][lv])
	return d["damage"][lv] / d["cooldown"][lv]


func tower_card(type: String) -> Dictionary:
	if tower_cards.has(type):
		return tower_cards[type]
	var d: Dictionary = TOWERS[type]
	# The bars: level 1 numbers against the best of all towers
	var most := [0.0, 0.0, 0.0]
	for t: String in TOWER_TYPES:
		var o: Dictionary = TOWERS[t]
		most = [maxf(most[0], tower_dps(o, 0)), maxf(most[1], o["range"][0]), maxf(most[2], 1.0 / o["cooldown"][0])]
	var dps := tower_dps(d, 0)
	var stats := [["Damage/s", dps / most[0], short(roundf(dps)) + (" to all inside" if d.has("cloud") else "")],
			["Range", d["range"][0] / most[1], "%d" % d["range"][0]],
			["Speed", (1.0 / d["cooldown"][0]) / most[2], "%s shots/s" % str(snappedf(1.0 / d["cooldown"][0], 0.1))]]
	var special := "Single target, quick shots"
	if d.has("soldiers"):
		# Barracks: each soldier's damage, and soldiers instead of shots
		stats[0][2] += " per soldier"
		stats[2] = ["Soldiers", float(d["soldiers"][0]) / SOLDIERS_MAX, "%d, health %s, back in %ss" % [d["soldiers"][0], num(d["soldier_hp"][0], true), num(d["respawn"][0], true)]]
		special = "Holds monsters still %ss each (not bosses)" % num(d["hold"][0])
	elif d.has("splash"):
		special = "Splash: hits all within %d" % d["splash"][0]
	elif d.has("slow"):
		special = "Slows monsters to %d%% speed" % roundi(d["slow"][0] * 100.0)
	elif d.has("chain"):
		special = "Chains to %d monsters" % d["chain"][0]
	elif d.has("cloud"):
		special = "Cloud size %d, lasts %ss, ignores armor" % [d["cloud"][0], str(CLOUD_TIME).trim_suffix(".0")]
	var words: Array = INFO_GOOD_WEAK.get(type, ["", ""])
	var top: int = PATH_LEVEL - 1
	var all := 0
	for lv in PATH_LEVEL:
		all += d["cost"][lv]
	var paths := []
	var best := 0.0
	for k in 2:
		best = maxf(best, tower_dps(d["paths"][k], PATH_LEVEL))
	for k in 2:
		var pd: Dictionary = d["paths"][k]
		var pdps := tower_dps(pd, PATH_LEVEL)
		var reach := "range %d" % pd["range"][PATH_LEVEL] if not d.has("soldiers") else "%d soldiers" % pd["soldiers"][PATH_LEVEL]
		paths.append(["Q" if k == 0 else "E", pd["name"], "%s dmg/s" % short(roundf(pdps)), reach, pdps / best, path_line(type, k)])
	var title := "%s TOWER" % d["name"].to_upper()
	var lv4 := "%s gold in all:  %s damage/s, range %d" % [short(all), short(roundf(tower_dps(d, top))), d["range"][top]]
	if d.has("soldiers"):
		lv4 = "%s gold in all:  %d soldiers, %s damage/s each" % [short(all), d["soldiers"][top], short(roundf(tower_dps(d, top)))]
	var card := {"name": title, "name_w": title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x,
			"cost": "%s gold" % short(d["cost"][0]), "desc": d["desc"] + ".", "stats": stats,
			"info": [["Special", special, UI_TEXT], ["Good vs", words[0], Color(0.55, 0.92, 0.45)], ["Weak vs", words[1], Color(1.0, 0.5, 0.42)]],
			"lv4": lv4,
			"lv5": "LEVEL 5: PICK A PATH  (%s gold)" % short(d["cost"][PATH_LEVEL]), "paths": paths}
	tower_cards[type] = card
	return card


# A path's extras in one short line, as many as fit: "Blast 107 (was 82), x1.5 vs bosses".
func path_line(type: String, k: int) -> String:
	var p: Dictionary = PATHS[type][k]
	var pd: Dictionary = TOWERS[type]["paths"][k]
	var d: Dictionary = TOWERS[type]
	var lv := PATH_LEVEL
	var parts := []
	if p.has("arrows"):
		parts.append("%d arrows at once (%d at lv 20, %d at lv 40)" % p["arrows"])
	if p.has("bomblets"):
		parts.append("+%d bomblets nearby (%d at lv 20, %d at lv 40)" % p["bomblets"])
	if p.has("freeze"):
		parts.append("%d%% freeze chance (%d%% at lv 20, %d%% at lv 40)" % [roundi(p["freeze"][0] * 100), roundi(p["freeze"][1] * 100), roundi(p["freeze"][2] * 100)])
	if p.has("area"):
		parts.append("Slows all within %d (%d at lv 20, %d at lv 40)" % p["area"])
	if p.has("splash"):
		parts.append("Blast %d (was %d)" % [pd["splash"][lv], d["splash"][lv]])
	if p.has("cloud"):
		parts.append("Cloud %d (was %d)" % [pd["cloud"][lv], d["cloud"][lv]])
	if p.has("cloud_time"):
		parts.append("lasts %ss" % str(cloud_time(k + 1, lv)).trim_suffix(".0"))
	if p.has("weaken"):
		parts.append("+%d%% damage taken inside" % roundi(p["weaken"][0] * 100))
	if p.has("chain_add") or p.has("chain_set"):
		parts.append("Chains to %d" % pd["chain"][lv])
	# Barracks
	if p.has("soldiers_add"):
		parts.append("+%d soldiers (+%d at lv 20, +%d at lv 40)" % p["soldiers_add"])
	if p.has("boss_hold"):
		parts.append("Holds bosses (x%s damage)" % num(p.get("boss", 1.0)))
	if p.has("reach"):
		parts.append("reach x%s" % num(p["reach"]))
	if p.has("soldier_hp"):
		parts.append("health %s" % num(pd["soldier_hp"][lv], true))
	if p.has("hold"):
		parts.append("hold %ss" % num(pd["hold"][lv]))
	if p.has("respawn"):
		parts.append("back in %ss" % num(pd["respawn"][lv], true))
	if p.has("boss") and not p.has("boss_hold"):
		parts.append("x%s vs bosses" % str(p["boss"]).trim_suffix(".0"))
	var room := INFO_W - 44.0
	var out := ""
	for s: String in parts:
		var next := s if out == "" else out + ", " + s
		if out != "" and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > room:
			break
		out = next
	# Few extras (Sniper, Storm): the path's own line in front, if it fits
	var grows := p.has("arrows") or p.has("bomblets") or p.has("freeze") or p.has("area")
	if parts.size() < 2 and not grows:
		var longer: String = p["desc"] + (", " + out[0].to_lower() + out.substr(1) if out != "" else "")
		if font.get_string_size(longer, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= room:
			out = longer
	return out


# The card over the command card's right side (console pixels, like the other tooltips).
func draw_tower_card(i: int) -> void:
	var type: String = TOWER_TYPES[i]
	var c := tower_card(type)
	var col: Color = TOWERS[type]["color"]
	var r := Rect2(SCREEN_W - 12.0 - INFO_W, BAR_TOP - 10.0 - INFO_H, INFO_W, INFO_H)
	hud.draw_rect(r.grow(4), Color(0, 0, 0, 0.35))
	hud.draw_rect(r, Color(0.05, 0.05, 0.055, 0.94))
	inner_shadow(r.grow(-3), 6, 0.3)
	bevel(r, 3, UI_GOLD_LIGHT, UI_GOLD_DARK)
	hud.draw_rect(r.grow(-3), Color(0, 0, 0, 0.6), false, 1.0)
	var x := r.position.x
	var y := r.position.y
	var gold_col := Color(1, 0.85, 0.3)
	# Name, hotkey and price
	gem(Vector2(x + 24, y + 22), 8.0, col)
	hud.draw_string(title_font, Vector2(x + 42, y + 29), c["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0, 0, 0, 0.7))
	hud.draw_string(title_font, Vector2(x + 42, y + 28), c["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, gold_col)
	text(Vector2(x + 50 + c["name_w"], y + 28), "(%d)" % (i + 1), 13, UI_DIM)
	var affordable: bool = gold >= TOWERS[type]["cost"][0]
	right_text(Vector2(r.end.x - 16, y + 28), c["cost"], 16, gold_col if affordable else Color(0.8, 0.45, 0.35))
	text(Vector2(x + 14, y + 50), c["desc"], 14, UI_GREY)
	# Damage, range and speed with bars
	for j in 3:
		var s: Array = c["stats"][j]
		var ry := y + 74 + j * 20
		text(Vector2(x + 14, ry), s[0], 14, UI_DIM)
		var bar := Rect2(x + 92, ry - 10, 90, 8)
		hud.draw_rect(bar.grow(1), Color(0, 0, 0, 0.8))
		hud.draw_rect(bar, Color(0.12, 0.11, 0.1))
		hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(s[1], 0.0, 1.0), bar.size.y)), col)
		text(Vector2(x + 194, ry), s[2], 14, UI_TEXT)
	for j in 3:
		var s: Array = c["info"][j]
		var ry := y + 134 + j * 20
		text(Vector2(x + 14, ry), s[0], 14, UI_DIM)
		text(Vector2(x + 92, ry), s[1], 14, s[2])
	# Level 4, then the 2 paths at level 5
	ui_heading(Vector2(x + 14, y + 200), "LEVEL 4", INFO_W - 28)
	text(Vector2(x + 14, y + 220), c["lv4"], 14, UI_TEXT)
	ui_heading(Vector2(x + 14, y + 246), c["lv5"], INFO_W - 28)
	for k in 2:
		var p: Array = c["paths"][k]
		var py := y + 268 + k * 36
		text(Vector2(x + 16, py), p[0], 13, UI_GOLD_LIGHT)
		text(Vector2(x + 34, py), p[1], 15, UI_TEXT)
		text(Vector2(x + 150, py), p[2], 14, UI_TEXT)
		text(Vector2(x + 236, py), p[3], 14, UI_GREY)
		var bar := Rect2(r.end.x - 126, py - 10, 110, 8)
		hud.draw_rect(bar.grow(1), Color(0, 0, 0, 0.8))
		hud.draw_rect(bar, Color(0.12, 0.11, 0.1))
		hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(p[4], 0.0, 1.0), bar.size.y)), col)
		text(Vector2(x + 34, py + 16), p[5], 12, UI_GREY)


# ---------------------------------------------------------------- profile and achievements
# The Esc menu's Profile button opens the Profile box (profile_stats() in
# game_base.gd); its buttons open the Achievements box (achievement_list()) and
# the reset question (reset_profile()). Both lists are read once when a box
# opens. Earned achievements pop up under the top bar (pop_achievement()).

const PROFILE_RECT := Rect2(400, 50, 124, 28)  # the Esc menu's button, top left (Map editor under it)
const PROFILE_BOX := Rect2(330, 40, 620, 640)
const PROFILE_NAME_RECT := Rect2(436, 112, 204, 36)  # the name box moves here while the Profile is open
const SWATCH_X := 730.0  # the colour picker: 8 swatches right of the name
const SWATCH_Y := 130.0
const SWATCH_STEP := 26.0
const SWATCH_R := 9.0
const PROFILE_ACH_RECT := Rect2(354, 620, 196, 40)
const PROFILE_CHRON_RECT := Rect2(558, 620, 150, 40)
const PROFILE_RESET_RECT := Rect2(716, 620, 116, 40)
const PROFILE_BACK_RECT := Rect2(840, 620, 86, 40)
const CHRON_BOX := Rect2(250, 30, 780, 660)
const CHRON_BACK_RECT := Rect2(560, 630, 160, 40)
const CHRON_ROWS := 8  # cards shown at once
const CHRON_ROW_H := 60
const ACH_BOX := Rect2(250, 30, 780, 660)
const ACH_BACK_RECT := Rect2(560, 630, 160, 40)
const ACH_ROWS := 6  # rows of 2 cards shown at once
const ACH_ROW_H := 70
const RESET_BOX := Rect2(440, 270, 400, 180)
const RESET_YES_RECT := Rect2(470, 392, 160, 40)
const RESET_NO_RECT := Rect2(650, 392, 160, 40)
const POPUP_W := 400.0
const POPUP_H := 76.0
const POPUP_IN := 0.35  # seconds to slide in (and out)
const POPUP_STAY := 4.0
const MEDAL_GOLD := Color(0.95, 0.78, 0.35)
var profile_open := false
var ach_open := false  # over the Profile box
var reset_ask := false  # "Reset your profile?" over the Profile box
var prof_cache := {}  # profile_stats() when the box opened
var ach_cache: Array = []  # achievement_list() when the box opened
var ach_tab := 0  # 0: All, then ACHIEVEMENT_GROUPS
var ach_top := 0  # the first row shown
var chron_open := false  # the Chronicle over the Profile box
var chron_cache: Array = []  # chronicle_list() when it opened, each with its text wrapped ("lines")
var chron_top := 0  # the first card shown
var ach_popup := {}  # the achievement popping up, or {}
var ach_popup_at := -1  # when it started showing (ms); -1: waiting for the menus to close


func open_profile() -> void:
	prof_cache = profile_stats()
	profile_open = true
	ach_open = false
	chron_open = false
	reset_ask = false
	code_input.release_focus()


# The texts are wrapped once here, not every frame.
func open_chronicle() -> void:
	chron_cache = chronicle_list()
	for c: Dictionary in chron_cache:
		c["lines"] = wrap_words(c.text, CHRON_BOX.size.x - 150.0, CHRON_BOX.size.x - 150.0, 14) if c.date != "" else PackedStringArray()
	chron_open = true
	chron_top = 0
	name_input.release_focus()


func chron_max_top() -> int:
	return maxi(chron_cache.size() - CHRON_ROWS, 0)


# Mouse wheel, arrow keys and Page Up / Down scroll.
func chron_input(event: InputEvent) -> bool:
	var top := chron_top
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			top -= 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			top += 1
		else:
			return false
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP: top -= 1
			KEY_DOWN: top += 1
			KEY_PAGEUP: top -= CHRON_ROWS
			KEY_PAGEDOWN: top += CHRON_ROWS
			_: return false
	else:
		return false
	chron_top = clampi(top, 0, chron_max_top())
	return true


# The Warden's Chronicle: every story card, unlocked ones with who said it, the
# date and the text, locked ones as "???" with how to unlock them.
func draw_chronicle() -> void:
	var b := CHRON_BOX
	profile_box(b, CHRONICLE_TITLE.to_upper(), 30)
	var got := 0
	for c: Dictionary in chron_cache:
		if c.date != "":
			got += 1
	center_text(b.get_center().x, b.position.y + 82, CHRONICLE_INTRO, 15, UI_GREY)
	center_text(b.get_center().x, b.position.y + 104, "%d of %d pages found" % [got, chron_cache.size()], 13, UI_DIM)
	chron_top = clampi(chron_top, 0, chron_max_top())
	var top := b.position.y + 120
	for k in range(chron_top, mini(chron_cache.size(), chron_top + CHRON_ROWS)):
		var c: Dictionary = chron_cache[k]
		var r := Rect2(b.position.x + 24, top + (k - chron_top) * CHRON_ROW_H, b.size.x - 56, CHRON_ROW_H - 6)
		if c.date == "":
			hud.draw_rect(r, Color(0, 0, 0, 0.32))
			hud.draw_rect(r, Color(0.3, 0.28, 0.25), false, 1.0)
			medal(r.position + Vector2(34, r.size.y / 2.0), 20.0, false)
			text(r.position + Vector2(68, 22), "???", 16, UI_DIM)
			text(r.position + Vector2(68, 42), c.hint, 13, UI_GREY)
			continue
		# A strip of parchment, like the card in the game
		vgrad(r, PARCH_TOP, PARCH_LOW)
		hud.draw_rect(r, UI_GOLD, false, 1.0)
		story_portrait(r.position + Vector2(34, r.size.y / 2.0), 19.0, c.who)
		var col: Color = SPEAKERS.get(c.who, ["?", Color(0.5, 0.45, 0.4)])[1]
		hud.draw_string(title_font, r.position + Vector2(68, 19), c.who, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col.darkened(0.55))
		right_text(Vector2(r.end.x - 10, r.position.y + 17), c.date, 12, Color(INK, 0.7))
		var lines: PackedStringArray = c.lines
		for j in mini(lines.size(), 2):
			var s := lines[j]
			if j == 1 and lines.size() > 2:
				s = fit_text(s + " " + " ".join(lines.slice(2)), r.size.x - 90.0, 14)
			text(r.position + Vector2(68, 35 + j * 15), s, 14, INK)
	# More than fits: a thin scrollbar and the hint
	if chron_cache.size() > CHRON_ROWS:
		var track := Rect2(b.end.x - 22, top, 4, CHRON_ROWS * CHRON_ROW_H - 6)
		hud.draw_rect(track, Color(0, 0, 0, 0.5))
		var h := track.size.y * CHRON_ROWS / chron_cache.size()
		hud.draw_rect(Rect2(track.position.x, track.position.y + (track.size.y - h) * chron_top / maxf(chron_max_top(), 1), 4, h), UI_GOLD)
	button(CHRON_BACK_RECT, "Back (Esc)", true, true)


func open_achievements() -> void:
	ach_cache = achievement_list()
	ach_open = true
	ach_tab = 0
	ach_top = 0
	name_input.release_focus()


# Every frame: the boxes close with the menu, and the name box moves into the Profile.
func update_profile_boxes() -> void:
	if not menu_open and profile_open:
		profile_open = false
		ach_open = false
		chron_open = false
		reset_ask = false
	var spot := (PROFILE_NAME_RECT.position if profile_open else NAME_INPUT_RECT.position) + Vector2(0, ui_extra / 2.0)
	if name_input.position != spot:
		name_input.position = spot
		name_input.size = PROFILE_NAME_RECT.size if profile_open else NAME_INPUT_RECT.size
	if profile_open:
		code_input.visible = false
		name_input.visible = net_mode == "" and not ach_open and not chron_open and not reset_ask
		if not name_input.visible:
			name_input.release_focus()


func draw_profile_boxes() -> void:
	if not profile_open:
		return
	draw_profile()
	if ach_open:
		draw_achievements()
	if chron_open:
		draw_chronicle()
	if reset_ask:
		draw_reset_ask()


func profile_click(p: Vector2) -> void:
	if reset_ask:
		if RESET_YES_RECT.has_point(p):
			reset_profile()
			reset_ask = false
			prof_cache = profile_stats()
		elif RESET_NO_RECT.has_point(p):
			reset_ask = false
		return
	if ach_open:
		ach_click(p)
		return
	if chron_open:
		if CHRON_BACK_RECT.has_point(p):
			chron_open = false
		return
	var sw := swatch_at(p)
	if sw >= 0:
		if sw != shown_color():
			var why := pick_color(sw)
			if why != "":
				flash(why)
		return
	if PROFILE_ACH_RECT.has_point(p):
		open_achievements()
	elif PROFILE_CHRON_RECT.has_point(p):
		open_chronicle()
	elif PROFILE_RESET_RECT.has_point(p):
		reset_ask = true
		name_input.release_focus()
	elif PROFILE_BACK_RECT.has_point(p):
		profile_open = false


# A popup box's dark cover, stone and gold title.
func profile_box(r: Rect2, title: String, size: int) -> void:
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.5))
	ui_box(r)
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ui_title(Rect2(r.position.x, r.position.y, r.size.x, 60), Vector2(r.get_center().x - tw / 2.0, r.position.y + 44), title, size)


func center_text(cx: float, y: float, s: String, size: int, col: Color) -> void:
	text(Vector2(cx - font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0, y), s, size, col)


# "31 h 12 min", or "12 min" under an hour.
func play_time(seconds: int) -> String:
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	return "%d h %d min" % [h, m] if h > 0 else "%d min" % m


func draw_profile() -> void:
	var b := PROFILE_BOX
	var p := prof_cache
	var s: Dictionary = p.stats
	profile_box(b, "PROFILE", 34)
	var x := b.position.x + 36
	var right := b.end.x - 36
	var w := b.size.x - 72
	# The name: its box (alone), or just the name in a multiplayer game
	text(Vector2(x, PROFILE_NAME_RECT.position.y + 24), "Name:", 16, UI_TEXT)
	if net_mode != "":
		text(Vector2(PROFILE_NAME_RECT.position.x + 8, PROFILE_NAME_RECT.position.y + 24), fit_text(name_of(local_slot), PROFILE_NAME_RECT.size.x - 12, 17), 17, UI_GOLD_LIGHT)
	draw_color_picker(right)
	ui_heading(Vector2(x, 172), "GAMES", w)
	var left := [["Games played", short(s.games)], ["Won / lost", "%s / %s" % [short(s.wins), short(s.losses)]],
			["Time played", play_time(s.seconds)], ["Multiplayer games", short(s.mp_games)]]
	var more := [["Monsters killed", short(s.kills)], ["Bosses killed", short(s.bosses)],
			["Gifts given", short(s.gifts_given)], ["Meteors / freezes", "%s / %s" % [short(s.meteors), short(s.freezes)]]]
	for i in 4:
		var y := 202 + i * 24
		text(Vector2(x, y), left[i][0], 15, UI_GREY)
		right_text(Vector2(x + 260, y), left[i][1], 15, UI_TEXT)
		text(Vector2(x + 290, y), more[i][0], 15, UI_GREY)
		right_text(Vector2(right, y), more[i][1], 15, UI_TEXT)
	# Per level (Default map), then the daily and the weekly challenge as the last rows
	ui_heading(Vector2(x, 294), "BEST WAVE PER LEVEL", w)
	for h: Array in [[120, "Best wave"], [250, "Wins"], [340, "Endless best"], [470, "Games"]]:
		text(Vector2(x + h[0], 322), h[1], 14, UI_GOLD)
	for i in p.levels.size():
		var lv: Dictionary = p.levels[i]
		var ry: float = 330 + i * 26
		hud.draw_rect(Rect2(x - 8, ry, b.size.x - 56, 24), Color(0, 0, 0, 0.28 if i % 2 == 0 else 0.16))
		text(Vector2(x, ry + 18), lv.name, 16, LEVEL_COLORS[i])
		var best := "-" if lv.best <= 0 else str(lv.best) + ("  won" if lv.wins > 0 else "")
		text(Vector2(x + 120, ry + 18), best, 16, UI_TEXT)
		text(Vector2(x + 250, ry + 18), short(lv.wins), 16, UI_TEXT)
		text(Vector2(x + 340, ry + 18), "-" if lv.endless <= 0 else str(lv.endless), 16, UI_TEXT)
		text(Vector2(x + 470, ry + 18), short(lv.games), 16, UI_TEXT)
	var d: Dictionary = p.daily
	var dy: float = 330 + p.levels.size() * 26
	hud.draw_rect(Rect2(x - 8, dy, b.size.x - 56, 24), Color(0, 0, 0, 0.28))
	text(Vector2(x, dy + 18), "Daily", 16, Color(1, 0.85, 0.3))
	# The streak now and the best, or only the best when both don't fit
	var best_run: int = d.get("best_streak", d.streak)
	var head := "%s played, %s won   " % [short(d.played), short(d.won)]
	var tail := "   Twists: %d / %d" % [d.twists, DAILY_TWISTS.size()]
	var daily := head + "Streak: %d day%s (best %d)" % [d.streak, "" if d.streak == 1 else "s", best_run] + tail
	if font.get_string_size(daily, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x > w - 120:
		daily = head + "Best streak: %d day%s" % [best_run, "" if best_run == 1 else "s"] + tail
	text(Vector2(x + 120, dy + 18), fit_text(daily, w - 120, 15), 15, UI_TEXT)
	# The weekly challenge: played, won, and in how many different weeks
	var wk: Dictionary = p.get("weekly", {"played": 0, "won": 0, "weeks": 0})
	var wy := dy + 26
	hud.draw_rect(Rect2(x - 8, wy, b.size.x - 56, 24), Color(0, 0, 0, 0.16))
	text(Vector2(x, wy + 18), "Weekly", 16, Color(1, 0.85, 0.3))
	var weeks := "%s played, %s won   Weeks won: %d" % [short(wk.played), short(wk.won), wk.weeks]
	text(Vector2(x + 120, wy + 18), fit_text(weeks, w - 120, 15), 15, UI_TEXT)
	# Towers: built and share of the damage, the favourite lit up
	ui_heading(Vector2(x, 508), "TOWERS", w)
	var fav: String = p.favourite
	right_text(Vector2(right, 513), "Favourite: %s (most built)" % TOWERS[fav]["name"] if fav != "" else "Favourite: none yet", 15, UI_GOLD_LIGHT)
	# Spread over the width, centered, at most 112 apart
	var n: int = p.towers.size()
	var step := minf(112.0, w / maxf(n, 1.0))
	for i in n:
		var t: Dictionary = p.towers[i]
		var cx: float = x + w / 2.0 + (i - (n - 1) / 2.0) * step
		if t.type == fav:
			hud.draw_rect(Rect2(cx - step / 2.0 + 4.0, 520, step - 8.0, 88), Color(0.55, 0.42, 0.15, 0.35))
		gem(Vector2(cx, 542), 14.0, TOWERS[t.type]["color"])
		center_text(cx, 576, "%s built" % short(t.built), 14, UI_TEXT)
		center_text(cx, 594, "%d%% damage" % roundi(t.share * 100.0), 13, UI_GREY)
	button(PROFILE_ACH_RECT, "Achievements  %d / %d" % [p.earned, p.total], true, true)
	button(PROFILE_CHRON_RECT, "Chronicle  %d / %d" % [(profile.get("chronicle", {}) as Dictionary).size(), STORY_CARDS.size()], true, true)
	button(PROFILE_RESET_RECT, "Reset profile")
	button(PROFILE_BACK_RECT, "Back (Esc)", true, true)


# ----- the colour picker (pick_color() in game_net.gd decides and sends it)

func swatch_center(i: int) -> Vector2:
	return Vector2(SWATCH_X + i * SWATCH_STEP, SWATCH_Y)


# The swatch under p, or -1.
func swatch_at(p: Vector2) -> int:
	for i in PLAYER_COLORS.size():
		if p.distance_to(swatch_center(i)) <= SWATCH_STEP / 2.0:
			return i
	return -1


# The colour shown as picked: this player's colour now (while joining: the pick).
func shown_color() -> int:
	if (net_mode == "connecting" or net_mode == "map_offer") and my_color() >= 0:
		return my_color()
	return color_index(local_slot)


# "Colour:" and 8 swatches; colours other players have are dimmed and crossed
# out. Under them: the colour under the mouse (and who has it), else the picked
# one, or a refusal from pick_color() / the host.
func draw_color_picker(right: float) -> void:
	var y := PROFILE_NAME_RECT.position.y + 24
	text(Vector2(SWATCH_X - 78, y), "Colour:", 16, UI_TEXT)
	var mine := shown_color()
	var hover := -1 if ach_open or chron_open or reset_ask else swatch_at(ui_mouse(true))
	for i in PLAYER_COLORS.size():
		var c := swatch_center(i)
		var col: Color = PLAYER_COLORS[i]
		var locked := color_locked(i)
		hud.draw_circle(c, SWATCH_R + 1.5, DARK_INK if i == DARK_COLOR else Color(0, 0, 0, 0.7))
		hud.draw_circle(c, SWATCH_R, col.darkened(0.55) if locked else col)
		if locked:
			var d := Vector2(SWATCH_R, -SWATCH_R) * 0.6
			hud.draw_line(c - d, c + d, Color(0.05, 0.04, 0.03), 3.0)
			hud.draw_line(c - d, c + d, Color(0.75, 0.3, 0.25), 1.5)
		else:
			hud.draw_circle(c - Vector2(3, 3), 2.2, Color(1, 1, 1, 0.45))
		if i == mine:
			hud.draw_arc(c, SWATCH_R + 4.0, 0, TAU, 24, UI_GOLD_LIGHT, 2.0)
		elif i == hover:
			hud.draw_arc(c, SWATCH_R + 4.0, 0, TAU, 24, Color(1, 1, 1, 0.55), 1.5)
	var note := menu_message()
	var col := Color(1, 1, 0.6)
	if hover >= 0:
		note = PLAYER_NAMES[hover]
		col = UI_GREY
		if color_locked(hover):
			note += ": %s has it" % name_of(color_holder(hover))
	elif note == "":
		note = PLAYER_NAMES[mine]
		col = UI_DIM
	right_text(Vector2(right, y + 24), fit_text(note, 300, 12), 12, col)


func draw_reset_ask() -> void:
	var r := RESET_BOX
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.45))
	ui_box(r)
	center_text(r.get_center().x, r.position.y + 44, "Reset your profile?", 22, UI_GOLD_LIGHT)
	center_text(r.get_center().x, r.position.y + 76, "All stats and achievements on this PC are deleted.", 14, UI_GREY)
	center_text(r.get_center().x, r.position.y + 96, "Your name, settings and saves stay.", 14, UI_GREY)
	button(RESET_YES_RECT, "Reset")
	button(RESET_NO_RECT, "Cancel (Esc)", true, true)


# ----- the Achievements box

func ach_tab_rect(i: int) -> Rect2:
	var n := ACHIEVEMENT_GROUPS.size() + 1
	var tw := minf(86.0, floorf((ACH_BOX.size.x - 40.0 - (n - 1) * 6.0) / n))  # narrower with more groups
	var left := ACH_BOX.get_center().x - (n * (tw + 6.0) - 6.0) / 2.0
	return Rect2(left + i * (tw + 6.0), ACH_BOX.position.y + 94, tw, 28)


# The achievements on the open tab.
func ach_shown() -> Array:
	if ach_tab == 0:
		return ach_cache
	var group: String = ACHIEVEMENT_GROUPS[ach_tab - 1]
	return ach_cache.filter(func(a: Dictionary) -> bool: return a.group == group)


func ach_max_top() -> int:
	return maxi(ceili(ach_shown().size() / 2.0) - ACH_ROWS, 0)


func set_ach_tab(i: int) -> void:
	ach_tab = posmod(i, ACHIEVEMENT_GROUPS.size() + 1)
	ach_top = 0


func ach_click(p: Vector2) -> void:
	if ACH_BACK_RECT.has_point(p):
		ach_open = false
		return
	for i in ACHIEVEMENT_GROUPS.size() + 1:
		if ach_tab_rect(i).has_point(p):
			set_ach_tab(i)
			return


# Mouse wheel, arrow keys and Page Up / Down scroll; Left / Right switch tabs.
func ach_input(event: InputEvent) -> bool:
	var top := ach_top
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			top -= 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			top += 1
		else:
			return false
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP: top -= 1
			KEY_DOWN: top += 1
			KEY_PAGEUP: top -= ACH_ROWS
			KEY_PAGEDOWN: top += ACH_ROWS
			KEY_LEFT, KEY_RIGHT:
				set_ach_tab(ach_tab + (-1 if event.keycode == KEY_LEFT else 1))
				return true
			_: return false
	else:
		return false
	ach_top = clampi(top, 0, ach_max_top())
	return true


func draw_achievements() -> void:
	var b := ACH_BOX
	profile_box(b, "ACHIEVEMENTS", 34)
	var earned := 0
	for a: Dictionary in ach_cache:
		if a.earned != "":
			earned += 1
	center_text(b.get_center().x, b.position.y + 80, "%d of %d earned" % [earned, ach_cache.size()], 15, UI_GREY)
	for i in ACHIEVEMENT_GROUPS.size() + 1:
		var r := ach_tab_rect(i)
		ui_button_bg(r, true, i == ach_tab)
		center_text(r.get_center().x, r.position.y + 19, "All" if i == 0 else ACHIEVEMENT_GROUPS[i - 1], 14, UI_GOLD_LIGHT if i == ach_tab else UI_GREY)
	var list := ach_shown()
	ach_top = clampi(ach_top, 0, ach_max_top())
	var top := b.position.y + 136
	for k in range(ach_top * 2, mini(list.size(), (ach_top + ACH_ROWS) * 2)):
		var a: Dictionary = list[k]
		var j := k - ach_top * 2
		var r := Rect2(b.position.x + 24 + (j % 2) * 370, top + (j / 2) * ACH_ROW_H, 362, 64)
		var done: bool = a.earned != ""
		hud.draw_rect(r, Color(0.55, 0.42, 0.15, 0.30) if done else Color(0, 0, 0, 0.32))
		hud.draw_rect(r, UI_GOLD if done else Color(0.3, 0.28, 0.25), false, 1.0)
		medal(r.position + Vector2(34, 32), 23.0, done)
		text(r.position + Vector2(68, 22), a.name, 16, UI_GOLD_LIGHT if done else UI_TEXT)
		text(r.position + Vector2(68, 40), fit_text(a.desc.trim_suffix("."), 284, 13), 13, UI_GREY)
		if done:
			right_text(Vector2(r.end.x - 10, r.position.y + 24), a.earned, 12, UI_DIM)
		elif a.goal > 0:
			var bar := Rect2(r.position.x + 68, r.position.y + 48, 200, 8)
			hud.draw_rect(bar, Color(0.05, 0.05, 0.05))
			hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(a.progress) / a.goal, 0.0, 1.0), 8)), Color(0.85, 0.65, 0.25))
			text(Vector2(bar.end.x + 8, bar.end.y + 1), "%s / %s" % [short(a.progress), short(a.goal)], 12, UI_GREY)
	# More than fits: a thin scrollbar and the hint
	var rows := ceili(list.size() / 2.0)
	if rows > ACH_ROWS:
		var track := Rect2(b.end.x - 16, top, 4, ACH_ROWS * ACH_ROW_H - 6)
		hud.draw_rect(track, Color(0, 0, 0, 0.5))
		var h := track.size.y * ACH_ROWS / rows
		hud.draw_rect(Rect2(track.position.x, track.position.y + (track.size.y - h) * ach_top / maxf(ach_max_top(), 1), 4, h), UI_GOLD)
		center_text(b.get_center().x, b.end.y - 78, "Scroll or Page Up / Down for more", 13, UI_DIM)
	button(ACH_BACK_RECT, "Back (Esc)", true, true)


# A round gold medal with a star (earned), or a dark one with "?".
func medal(c: Vector2, r: float, lit: bool) -> void:
	if not lit:
		hud.draw_circle(c, r, Color(0.2, 0.19, 0.18))
		hud.draw_circle(c, r - 3.0, Color(0.12, 0.115, 0.11))
		center_text(c.x, c.y + 7, "?", 20, UI_DIM)
		return
	hud.draw_circle(c, r, UI_GOLD_DARK)
	hud.draw_circle(c, r - 2.0, UI_GOLD)
	hud.draw_circle(c, r - 6.0, MEDAL_GOLD)
	var pts := PackedVector2Array()
	for k in 10:
		var ang := -PI / 2.0 + k * PI / 5.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * (r * 0.5 if k % 2 == 0 else r * 0.2))
	hud.draw_colored_polygon(pts, UI_GOLD_DARK)


# ----- the popup

# Under the top bar in the middle (lower with the daily banner or the held line),
# out of the tip card's way. Waits while a menu, popup or the replay is up.
func draw_achievement_popup() -> void:
	var free := not menu_open and gift_to < 0 and update_dialog == "" and not replaying() and not bool(get("editing"))
	if ach_popup.is_empty():
		if not free:
			return
		ach_popup = pop_achievement()
		if ach_popup.is_empty():
			return
		ach_popup_at = -1
	if not free:
		ach_popup_at = -1  # shows again from the start once the way is clear
		return
	var now := Time.get_ticks_msec()
	if ach_popup_at < 0:
		ach_popup_at = now
		if SOUNDS.has("achievement"):
			play_sound("achievement")
	var t := (now - ach_popup_at) / 1000.0
	if t > POPUP_STAY + POPUP_IN * 2.0:
		ach_popup = {}
		return
	var fest := fest_name != "" and fest_t < FEST_SHOW and state == "playing"
	var y := TOP_BAR_H + 12.0 + (30.0 if challenge_on() else 0.0) + (32.0 if held or fest else 0.0)
	var r := Rect2((SCREEN_W - POPUP_W) / 2.0, y, POPUP_W, POPUP_H)
	var tip := tip_layout()
	if tip.is_empty() and story_layer.visible and story_id != "" and not story_end_card:
		tip = story_layout()
	if not tip.is_empty() and tip["rect"].grow(8).intersects(r):
		var tr: Rect2 = tip["rect"]
		r.position.y = tr.end.y + 12.0 if tr.end.y + 12.0 + POPUP_H < TIP_LOW else maxf(tr.position.y - POPUP_H - 12.0, TOP_BAR_H + 6.0)
	# Slides down from above the screen, and back up at the end
	var k := clampf(minf(t, POPUP_STAY + POPUP_IN * 2.0 - t) / POPUP_IN, 0.0, 1.0)
	r.position.y = lerpf(-POPUP_H - 10.0, r.position.y, 1.0 - pow(1.0 - k, 3.0))
	hud.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.45))
	ui_box(r)
	medal(r.position + Vector2(40, 38), 26.0, true)
	text(r.position + Vector2(80, 26), "ACHIEVEMENT UNLOCKED", 13, UI_GOLD)
	text(r.position + Vector2(80, 50), fit_text(ach_popup.name, POPUP_W - 96, 20), 20, UI_GOLD_LIGHT)
	text(r.position + Vector2(80, 68), fit_text(ach_popup.desc.trim_suffix("."), POPUP_W - 96, 13), 13, UI_GREY)
