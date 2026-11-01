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

# The leaderboard: its button next to Resume in the Esc menu, and its box
const LEADERBOARD_RECT := Rect2(710, 640, 140, 44)
const BOARD_RECT := Rect2(320, 50, 640, 620)
const BOARD_REFRESH_RECT := Rect2(360, 606, 170, 40)
const BOARD_BACK_RECT := Rect2(750, 606, 170, 40)
const BOARD_ROW_H := 34

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
	map_hud.queue_redraw()
	update_end_layer()
	update_notes_box()
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
	# Popups in the middle of the screen
	hud.draw_set_transform(Vector2(0, ui_extra / 2.0))
	if menu_open:
		draw_menu()
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
	# The end screen covers the map: no bars, badges or labels on top of it
	if state != "playing":
		return
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
	hud.draw_rect(Rect2(r.position.x + 10, r.position.y + 40, r.size.x - 20, 2), PLAYER_COLORS[from] * Color(1, 1, 1, 0.7))
	var line := "%s wants to build a %s tower in your area" % [name_of(from), str(ask[2]).capitalize()]
	if asks.size() > 1:
		line += "  (+%d more)" % (asks.size() - 1)
	text(r.position + Vector2(20, 32), line, 17, PLAYER_COLORS[from])
	text(r.position + Vector2(20, 68), "The spot is marked with a ring on the map.", 14, UI_GREY)
	button(ASK_YES_RECT, "Yes (Y)", true, true)
	button(ASK_NO_RECT, "No (N)")
	# Point at the spot with a pulsing ring (on the map: not shifted with the console)
	var spot := camera.unproject_position(Vector3(cell.x + 0.5, 0.1, cell.y + 0.5))
	hud.draw_set_transform(Vector2.ZERO)
	hud.draw_arc(spot, 16.0 + sin(time * 6.0) * 4.0, 0, TAU, 32, PLAYER_COLORS[from], 3.0)
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


func draw_health_bars() -> void:
	for e in enemies:
		# Only hurt monsters show a bar, like in Warcraft III, so big waves stay readable
		if e.hp >= e.max_hp:
			continue
		# Just above the monster's model (its height is the 4th part of its look)
		var top: float = e.node.get_meta("mob")[3]
		var p := camera.unproject_position(e.node.position + Vector3(0, top + 0.08, 0))
		var w := e.radius * 2.4
		var bar := Vector2(p.x - w / 2.0, p.y)
		# Black edge so the bar reads on grass and path alike
		hud.draw_rect(Rect2(bar - Vector2(1, 1), Vector2(w + 2, 6)), Color(0, 0, 0, 0.85))
		hud.draw_rect(Rect2(bar, Vector2(w, 4)), Color(0.3, 0.04, 0.02))
		hud.draw_rect(Rect2(bar, Vector2(w * e.hp / e.max_hp, 4)), Color(0.2, 0.85, 0.2))


func text(pos: Vector2, s: String, size := 16, col := Color.WHITE) -> void:
	hud.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# Big numbers made short: 9500, 24k, 240k, 1.2M, 3.4B, 5T.
func short(n: float) -> String:
	if absf(n) < 10000.0:
		return str(int(n))
	for u: Array in [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "k"]]:
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
	x = resource(x, level_name(), 15, level_color(), "") + 8
	x = resource(x, "%d / %d" % [wave, MAX_WAVE], 18, UI_TEXT, "wave")
	x = resource(x, "%d / %d" % [alive_count(), max_alive()], 18, danger_color(), "alive")
	resource(x, short(gold), 18, Color(1, 0.85, 0.3), "gold")


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
	ui_title(Rect2(x - 14, BAR_TOP + 10, 236, 36), Vector2(x, BAR_TOP + 40), "WAVE %d / %d" % [wave, MAX_WAVE], 24)
	draw_wave_preview(x)
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


# ----- wave preview: the next 3 waves under the wave title

# Each monster kind's color in the preview (like its old look).
const KIND_COLORS := {"normal": Color(0.95, 0.5, 0.6), "fast": Color(1.0, 0.9, 0.3),
		"armored": Color(0.6, 0.65, 0.75), "boss": Color(0.95, 0.2, 0.15)}


# The countdown at the title's right end, then a chip per wave: the monster
# kind and how many come (all gates together). Every player sees the same: it's
# all worked out from the wave number, which comes with the host's updates.
func draw_wave_preview(x: float) -> void:
	if state != "playing":
		return
	var right := x + 208.0
	# Before wave 1 there's no countdown: the first wave comes with Space
	if wave > 0 and wave < MAX_WAVE:
		var timer := "%ds" % ceili(next_wave_timer)
		var tw := font.get_string_size(timer, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		text(Vector2(right - tw, BAR_TOP + 38), timer, 14, UI_GREY)
	if wave >= MAX_WAVE:
		text(Vector2(x, BAR_TOP + 70), "Last wave! Kill them all", 15, UI_GREY)
		return
	var cx := x
	for i in 3:
		var n := wave + 1 + i
		if n > MAX_WAVE:
			break
		var label := wave_chip_label(n)
		var w := 32.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if cx + w > right + 4.0:
			break  # no room for a third wide chip
		wave_chip(Rect2(cx, BAR_TOP + 54, w, 22), n, label)
		# The next wave's countdown as a thin gold bar under its chip
		if i == 0 and wave > 0:
			hud.draw_rect(Rect2(cx, BAR_TOP + 79, w * clampf(next_wave_timer / WAVE_INTERVAL, 0.0, 1.0), 2), UI_GOLD)
		cx += w + 5.0


func wave_chip_label(n: int) -> String:
	var count := wave_count(n) * maxi(player_count(), 1)
	return ("BOSS x%d" if kind_for_wave(n) == "boss" else "x%d") % count


func wave_chip(r: Rect2, n: int, label: String) -> void:
	var kind := kind_for_wave(n)
	var boss := kind == "boss"
	var col: Color = KIND_COLORS[kind]
	ui_button_bg(r, true, boss)
	hud.draw_rect(r.grow(-2), Color(col, 0.16))
	if boss:
		# A boss wave blinks red
		var a := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 160.0)
		hud.draw_rect(r.grow(2), Color(1, 0.3, 0.2, a), false, 2.0)
	kind_icon(r.position + Vector2(13, r.size.y / 2.0 + 1), kind, 7.0)
	text(r.position + Vector2(25, r.size.y / 2.0 + 5), label, 13, Color(1, 0.55, 0.45) if boss else UI_TEXT)


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
	stat_row(Vector2(x, BAR_TOP + 96), "Damage", short(data["damage"][lv]), short(after["damage"][lv + 1]) if next else "")
	stat_row(Vector2(x, BAR_TOP + 118), "Range", "%d" % data["range"][lv], "%d" % after["range"][lv + 1] if next else "")
	stat_row(Vector2(x, BAR_TOP + 140), "Speed", "%.2fs" % data["cooldown"][lv], "")
	var right := x + 196
	hud.draw_multiline_string(font, Vector2(right, BAR_TOP + 96), data["desc"], HORIZONTAL_ALIGNMENT_LEFT, 130, 14, 2, UI_GREY)
	if not mine:
		text(Vector2(right, BAR_TOP + 140), "Built by %s" % name_of(selected.owner), 14, PLAYER_COLORS[selected.owner])
	elif lv >= MAX_LEVEL - 1:
		text(Vector2(right, BAR_TOP + 140), "Max level", 14, UI_GOLD_LIGHT)
	elif needs_path(selected):
		text(Vector2(right, BAR_TOP + 140), "Next: pick a path (Q / E)", 14, UI_GOLD_LIGHT)
	# Targeting mode: a plain text button (placeholder until it gets an icon)
	ui_button_bg(MODE_RECT, mine, false)
	text(MODE_RECT.position + Vector2(5, 16), "T", 11, UI_GOLD_LIGHT if mine else UI_DIM)
	text(MODE_RECT.position + Vector2(20, 17), "Target: " + TARGET_MODES[selected.mode], 14, UI_TEXT if mine else UI_DIM)


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
		text(Vector2(x + 82, y), gold_text(data["cost"][0]), 15, Color(1, 0.85, 0.3) if affordable else Color(0.6, 0.4, 0.3))
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
	var p := ui_mouse()
	# 9 and 10: the 2 path buttons over the build row (a level 4 tower of yours selected)
	if picking_path():
		for i in 2:
			if PATH_RECTS[i].has_point(p):
				return 9 + i
	var rects := card_rects()
	for i in rects.size():
		if rects[i].has_point(p):
			return i
	# 8: the targeting mode button in the selected tower's panel
	if selected != null and asks.is_empty() and MODE_RECT.has_point(p):
		return 8
	return -1


func draw_command_card() -> void:
	if picking_path():
		draw_path_buttons()
	else:
		for i in TOWER_TYPES.size():
			var data: Dictionary = TOWERS[TOWER_TYPES[i]]
			var r := tower_button_rect(i)
			var affordable: bool = gold >= data["cost"][0]
			card_button(r, str(i + 1), data["name"], gold_text(data["cost"][0]), true, build_type == TOWER_TYPES[i], affordable)
			gem(r.get_center() + Vector2(0, -2), 11.0, data["color"] if affordable else data["color"].darkened(0.4))
	# Upgrade and Sell only work on your own selected tower
	var mine := selected != null and selected.owner == local_slot
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
	card_button(SELL_RECT, "X", "Sell", "+" + gold_text(selected.spent * 0.7) if mine else "", mine, false, true)
	icon_coin(SELL_RECT.get_center() + Vector2(0, -2), 10.0, mine)
	var w := wave_button()
	var can_wave := wave < MAX_WAVE and state == "playing" and monsters_left_to_spawn() == 0
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
	return ""


# Short label and corner text for the wave button: [label, corner].
func wave_button() -> Array:
	if wave == 0:
		return ["Start", ""]
	if wave < MAX_WAVE and monsters_left_to_spawn() > 0:
		return ["%d left" % monsters_left_to_spawn(), ""]
	var bonus := "+" + gold_text(early_gold())
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
		return "Vote to send it now: +%s gold each, %s (SPACE)" % [short(early_gold()), votes]
	if wave < MAX_WAVE:
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


# A box above the command card that explains the button under the mouse.
func draw_card_tip(i: int) -> void:
	var title := ""
	var lines: Array = []
	if i < TOWER_TYPES.size():
		var data: Dictionary = TOWERS[TOWER_TYPES[i]]
		title = "Build %s Tower (%d)  -  %s" % [data["name"], i + 1, gold_text(data["cost"][0])]
		lines = [data["desc"], "Damage %s   Range %d   Speed %.2fs" % [short(data["damage"][0]), data["range"][0], data["cooldown"][0]]]
	elif i == 4:
		title = "Upgrade (U)"
		if selected == null or selected.owner != local_slot:
			lines = ["Select one of your towers first."]
		elif needs_path(selected):
			title = "Upgrade to level 5: pick a path"
			lines = ["Q: %s   E: %s" % [PATHS[selected.type][0]["name"], PATHS[selected.type][1]["name"]],
					"The path is for good (selling is the only way back)."]
		elif selected.level < MAX_LEVEL - 1:
			var data := tower_data(selected.type, selected.path, selected.level + 1)
			title = "Upgrade to level %d (U)  -  %s gold" % [selected.level + 2, short(data["cost"][selected.level + 1])]
			lines = ["Damage %s   Range %d" % [short(data["damage"][selected.level + 1]), data["range"][selected.level + 1]]]
		else:
			lines = ["This tower is at its highest level."]
	elif i == 5:
		title = "Sell (X)"
		lines = ["Get back %s gold for this tower." % short(selected.spent * 0.7)] if selected != null and selected.owner == local_slot else ["Select one of your towers first."]
	elif i == 6:
		title = "Next wave (SPACE)"
		lines = [wave_tip(), next_wave_text()]
	elif i == 9 or i == 10:
		var p: Dictionary = PATHS[selected.type][i - 9]
		var d := tower_data(selected.type, i - 8, PATH_LEVEL)
		title = "%s (%s)  -  %s gold" % [p["name"], "Q" if i == 9 else "E", short(d["cost"][PATH_LEVEL])]
		lines = [p["desc"] + ".", "Level 5: Damage %s   Range %d   Speed %.2fs" % [short(d["damage"][PATH_LEVEL]), d["range"][PATH_LEVEL], d["cooldown"][PATH_LEVEL]]]
		lines.append_array(path_extra(selected.type, i - 8).split("\n"))
		lines.append("For good: selling is the only way back.")
	elif i == 8:
		title = "Target: %s (T)" % TARGET_MODES[selected.mode]
		lines = ["Shoots: " + TARGET_TIPS[selected.mode]]
		if selected.owner == local_slot:
			lines.append_array(["Click or T: next mode. Shift: all your %s towers." % TOWERS[selected.type]["name"],
					"First, Last, Strongest, Fastest, Closest"])
		else:
			lines.append("Only %s can change it." % name_of(selected.owner))
	else:
		title = "Game speed x%d (F)" % game_speed
		lines = ["Only the host can change the speed."] if net_mode == "client" else ["Switches between x1, x2, x3 and x5 speed."]
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
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.5))
	ui_box(m)
	var title := "PAUSED" if net_mode == "" else "MENU"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	ui_title(Rect2(m.position.x, m.position.y, m.size.x, 66), Vector2((SCREEN_W - tw) / 2.0, m.position.y + 50), title, 40)
	var sub := "The game is paused." if net_mode == "" else "The game keeps running while this menu is open."
	centered(m.position.y + 78, sub, 15, UI_GREY)
	button(GRAPHICS_RECT, "Settings")
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
			text(Vector2(left, 234), "You are playing as %s." % name_of(local_slot), 16, PLAYER_COLORS[local_slot])
			draw_player_list(Vector2(left, 266))
			button(STOP_RECT, "Leave the game")
	button(RESUME_RECT, "Resume (Esc)")
	button(LEADERBOARD_RECT, "Leaderboard")


# The top 10 from the game server (see open_board()), over the Esc menu.
func draw_board() -> void:
	var b := BOARD_RECT
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.5))
	ui_box(b)
	var title := "LEADERBOARD"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
	ui_title(Rect2(b.position.x, b.position.y, b.size.x, 62), Vector2((SCREEN_W - tw) / 2.0, b.position.y + 46), title, 36)
	centered(b.position.y + 82, "%s level, Default map, %d waves. Highest wave first, then the fastest time." % [DIFFICULTIES[board_level], MAX_WAVE], 15, UI_GREY)
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
	var gold_col := Color(1, 0.85, 0.3)
	var x_rank := b.position.x + 40
	var x_names := b.position.x + 90
	var x_wave := b.position.x + 470  # right edge of the wave column
	var x_time := b.end.x - 40  # right edge of the time column
	var y := b.position.y + 144
	text(Vector2(x_rank, y), "#", 15, gold_col)
	text(Vector2(x_names, y), "Players", 15, gold_col)
	right_text(Vector2(x_wave, y), "Wave", 15, gold_col)
	right_text(Vector2(x_time, y), "Time", 15, gold_col)
	ui_divider(b.position.x + 24, b.end.x - 24, y + 10)
	var top := b.position.y + 160
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
		centered(below, "Finish a game on the Default map at %s to get on this list." % DIFFICULTIES[board_level], 15, UI_GREY)
	else:
		var where := "#%d" % board_me.rank if board_me.rank > 0 else "not in the top 1000"
		centered(below, "Your best: %s, wave %d%s, %s" % [where, board_me.wave, " (won)" if board_me.won else "", board_time_text(board_me.ms)], 15, gold_col)
	button(BOARD_REFRESH_RECT, "Refresh", can_refresh_board())
	button(BOARD_BACK_RECT, "Back (Esc)", true, true)


var settings_open := false  # the Settings box over the Esc menu


# Each row of the Settings box: its name and the current choice.
func settings_rows() -> Array:
	return [
		["Graphics", "High" if graphics_high else "Low"],
		["Window", "Fullscreen" if fullscreen else "Windowed"],
		["3D resolution", "%d%%" % roundi(render_scale * 100.0)],
		["Anti-aliasing", AA_NAMES[AA_MODES.find(aa_mode)]],
	]


func settings_row_rect(i: int) -> Rect2:
	return Rect2(SETTINGS_BUTTON_X, SETTINGS_ROW_Y + i * 48, 180, 34)


# Graphics, fullscreen, 3D resolution and anti-aliasing: a click on a row's button picks the next choice.
func draw_settings() -> void:
	var b := SETTINGS_BOX
	hud.draw_rect(screen_rect(), Color(0, 0, 0, 0.5))
	ui_box(b)
	var title := "SETTINGS"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	ui_title(Rect2(b.position.x, b.position.y, b.size.x, 60), Vector2((SCREEN_W - tw) / 2.0, b.position.y + 44), title, 34)
	var rows := settings_rows()
	for i in rows.size():
		var r := settings_row_rect(i)
		text(Vector2(b.position.x + 40, r.position.y + 23), rows[i][0], 17, UI_TEXT)
		button(r, rows[i][1])
	centered(SETTINGS_BACK_RECT.position.y - 14, "F11 or Alt+Enter: fullscreen.  Lower 3D resolution: faster.", 13, UI_DIM)
	button(SETTINGS_BACK_RECT, "Back (Esc)", true, true)


func settings_click(p: Vector2) -> void:
	if SETTINGS_BACK_RECT.has_point(p):
		settings_open = false
		return
	for i in settings_rows().size():
		if settings_row_rect(i).has_point(p):
			match i:
				0:
					graphics_high = not graphics_high
					apply_graphics()
				1:
					set_fullscreen(not fullscreen)
				2:
					var scales := render_scales()
					render_scale = scales[(scales.find(render_scale) + 1) % scales.size()]
					apply_display()
				3:
					aa_mode = AA_MODES[(AA_MODES.find(aa_mode) + 1) % AA_MODES.size()]
					apply_display()
			save_settings()


# The leaderboard's level tabs, centered under its subtitle.
func board_tab_rect(i: int) -> Rect2:
	var w := 110.0
	var gap := 8.0
	var left := (SCREEN_W - DIFFICULTIES.size() * (w + gap) + gap) / 2.0
	return Rect2(left + i * (w + gap), BOARD_RECT.position.y + 96, w, 28)


func board_click(p: Vector2) -> void:
	for i in DIFFICULTIES.size():
		if board_tab_rect(i).has_point(p):
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
	# Esc in the leaderboard or the settings goes back to the menu
	if (board_open or settings_open) and menu_open:
		board_open = false
		settings_open = false
		return
	board_open = false
	settings_open = false
	menu_open = not menu_open
	build_type = ""
	games_timer = 0.0  # fresh list of public games when the menu opens
	if not menu_open:
		code_input.release_focus()
		name_input.release_focus()
	close_chat()


func menu_click(p: Vector2) -> void:
	if board_open:
		board_click(p)
		return
	if settings_open:
		settings_click(p)
		return
	if RESUME_RECT.has_point(p):
		toggle_menu()
		return
	if LEADERBOARD_RECT.has_point(p):
		open_board()
		return
	if GRAPHICS_RECT.has_point(p):
		settings_open = true
		code_input.release_focus()
		name_input.release_focus()
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
	end_layer.visible = state != "playing"
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
	text(Vector2(sx, STATS_TOP - 20), sub, 18, Color(UI_TEXT, k))
	hud.draw_string_outline(font, Vector2(sx + sw + 24.0, STATS_TOP - 20), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8 * k))
	text(Vector2(sx + sw + 24.0, STATS_TOP - 20), lv, 16, Color(level_color(), k))


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
	size = font.get_string_size(again, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	text(Vector2((SCREEN_W - size.x) / 2.0, panel.end.y + 22), again, 16, UI_GREY)
	if end_stats.is_empty():
		outlined(panel.get_center(), "Getting the stats from the host...", 16, UI_GREY)
		return
	var rows: Array = end_stats["players"]
	var team := rows.size() > 1  # alone: no MVP and no owner column
	var left := panel.position.x + 24
	var cols := [left, left + 246, left + 336, left + 436, left + 556]
	# ---- players
	var y := panel.position.y + 30
	ui_title(Rect2(panel.position.x + 10, y - 26, 760, 34), Vector2(left, y), "PLAYERS" if team else "YOU", 18)
	var heads := ["", "Kills", "Damage", "Gold earned", "Spent on towers"]
	for i in range(1, 5):
		text(Vector2(cols[i], y), heads[i], 13, UI_DIM)
	y += 28
	var kills := 0
	var damage := 0.0
	for row: Array in rows:
		var slot: int = row[0]
		kills += row[2]
		damage += row[3]
		hud.draw_circle(Vector2(left + 6, y - 5), 6, PLAYER_COLORS[slot])
		text(Vector2(left + 20, y), row[1], 16, PLAYER_COLORS[slot].lightened(0.3))
		if slot == end_stats["mvp"]:
			var nw := font.get_string_size(row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var mr := Rect2(left + 28 + nw, y - 15, 42, 19)
			ui_button_bg(mr, true, true)
			text(mr.position + Vector2(7, 14), "MVP", 13, UI_GOLD_LIGHT)
		text(Vector2(cols[1], y), short(row[2]), 16, UI_TEXT)
		text(Vector2(cols[2], y), short(row[3]), 16, UI_TEXT)
		text(Vector2(cols[3], y), gold_text(row[4]), 16, Color(1, 0.85, 0.3))
		text(Vector2(cols[4], y), gold_text(row[5]), 16, Color(1, 0.85, 0.3))
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
			text(Vector2(left + 176, y), t[4], 14, PLAYER_COLORS[t[3]].lightened(0.3))
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
			cols.append(PLAYER_COLORS[slot].lerp(Color.WHITE, 0.2))
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
