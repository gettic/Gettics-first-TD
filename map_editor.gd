extends "res://game_ui.gd"
## The map editor and saved maps. It opens from the Esc menu when playing alone.
## The map being edited is plain text (rows of letters, see DEFAULT_MAP). After
## every change it's checked with read_map() and shown on the 3D map right away.

# Esc menu: the editor button, left of Graphics, and the box asking before a game ends
const EDITOR_RECT := Rect2(400, 50, 124, 28)
# Esc menu: the map being played, under the title
const MAP_PICK_RECT := Rect2(530, 136, 320, 30)
# Joining a game on a map you don't have: the preview and Download / Cancel
const JOIN_BOX := Rect2(312, 100, 656, 470)
const JOIN_PREVIEW := Rect2(336, 206, 296, 222)
const JOIN_KEEP := Rect2(340, 486, 20, 20)
const JOIN_YES := Rect2(340, 518, 290, 40)
const JOIN_NO := Rect2(650, 518, 290, 40)
const ED_ASK_RECT := Rect2(430, 250, 420, 180)
const ED_ASK_YES_RECT := Rect2(450, 364, 180, 44)
const ED_ASK_NO_RECT := Rect2(650, 364, 180, 44)
# Esc while editing
const ED_MENU_RECT := Rect2(440, 200, 400, 250)
const ED_BACK_RECT := Rect2(480, 296, 320, 44)
const ED_LEAVE_RECT := Rect2(480, 356, 320, 44)
# The editor's console: Tools, Map, Check and File
const ED_TOOLS := ["Path", "Erase", "Gate", "Rock", "Tree", "Water", "Areas", "Clear"]
const ED_LETTERS := {"Path": "#", "Erase": ".", "Rock": "r", "Tree": "t", "Water": "w"}
const ED_NAME_RECT := Rect2(400, 588, 230, 28)
const ED_W_MINUS := Rect2(420, 626, 30, 28)
const ED_W_PLUS := Rect2(492, 626, 30, 28)
const ED_H_MINUS := Rect2(420, 664, 30, 28)
const ED_H_PLUS := Rect2(492, 664, 30, 28)
const ED_NEW_RECT := Rect2(980, 586, 134, 36)
const ED_LOAD_RECT := Rect2(1124, 586, 134, 36)
const ED_SAVE_RECT := Rect2(980, 630, 134, 36)
const ED_PLAY_RECT := Rect2(1124, 630, 134, 36)
const ED_EXIT_RECT := Rect2(980, 674, 278, 36)
# The list of maps to load
const ED_LIST_RECT := Rect2(440, 60, 400, 470)
const ED_LIST_ROWS := 9
const ED_LIST_CANCEL := Rect2(480, 470, 320, 40)
const ED_UNEVEN := 1.5  # areas: a warning when the biggest is this much bigger than the smallest
const ED_RESERVED := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "LPT1", "LPT2", "LPT3"]

var editing := false
var ed_rows: Array = []  # the map being edited: rows of letters
var ed_name := ""  # the saved map it came from ("": new or Default)
var ed_check: Dictionary = {}  # read_map() of ed_rows
var ed_tool := "Path"
var ed_gate := 0  # the gate the Gate tool places (0-3)
var ed_areas := true  # show the players' areas
var ed_dirty := false  # the 3D map needs building again
var ed_changed := false  # changes since the last save or load
var ed_painting := 0  # mouse button held on the map: 1 paints, 2 erases
var ed_last_cell := Vector2i(-1, -1)
var ed_list_open := false
var ed_list: Array = []  # names of the maps to load, Default first
var ed_list_top := 0
var ed_confirm := ""  # a click that needs a second click to happen
var ed_confirm_was := ""
var ed_ask_open := false  # Esc menu: "end this game for the editor?"
var ed_before: Array = []  # the map played before the editor, to go back to
var ed_before_name := ""
var map_name_input: LineEdit
var pick_open := false  # Esc menu: the list of maps to play


# main.gd has the real one
func new_game() -> void:
	pass


func build_hud() -> void:
	super()
	map_name_input = text_box(code_input.get_parent(), ED_NAME_RECT, "Name the map", MAP_NAME_MAX, 16)
	map_name_input.text_changed.connect(func(t: String) -> void:
		var clean := clean_map_name(t, false)
		if clean != t:
			var at := map_name_input.caret_column
			map_name_input.text = clean
			map_name_input.caret_column = mini(at, clean.length()))
	map_name_input.text_submitted.connect(func(_t: String) -> void: map_name_input.release_focus())
	# Esc leaves the box, like it cancels the chat box (the next Esc opens the menu)
	map_name_input.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			map_name_input.release_focus()
			map_name_input.accept_event())


# ---------------------------------------------------------------- saved maps

# Keeps letters, digits, spaces and - _ ' ( ), so the name is also a safe file name.
func clean_map_name(s: String, trim := true) -> String:
	var out := ""
	for ch in s:
		if ch.is_valid_identifier() or ch.is_valid_int() or ch in [" ", "-", "'", "(", ")"]:
			out += ch
	out = out.left(MAP_NAME_MAX)
	return out.strip_edges() if trim else out


func map_file(n: String) -> String:
	return "%s/%s.txt" % [MAPS_DIR, n]


# Names of the saved maps, sorted.
func saved_maps() -> Array:
	var names := []
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		return names
	for f in DirAccess.get_files_at(MAPS_DIR):
		if f.get_extension() == "txt":
			var n := f.get_basename()
			if clean_map_name(n) == n and n != "":
				names.append(n)
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return names


# A map's rows of letters, or [] if the file can't be read. Not checked yet:
# the caller runs read_map() on it.
func load_map_rows(n: String) -> Array:
	if n == "Default":
		return DEFAULT_MAP.duplicate()
	var f := FileAccess.open(map_file(n), FileAccess.READ)
	if f == null or f.get_length() > MAP_FILE_MAX:
		return []
	var rows := []
	for line in f.get_as_text().split("\n", false):
		if line.strip_edges() != "":
			rows.append(line.strip_edges())
	return rows


func save_map_rows(n: String, rows: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	var f := FileAccess.open(map_file(n), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("\n".join(rows) + "\n")
	return true


# Why a name can't be used to save, or "".
func bad_map_name(n: String) -> String:
	if n == "":
		return "Type a name for the map first"
	if n.to_lower() == "default":
		return "The Default map can't be changed: give your map another name"
	if n.to_upper() in ED_RESERVED or n.validate_filename() != n:
		return "Windows doesn't allow that name: try another"
	return ""


# A map from the host the player chose to keep: saved like their own maps (and
# checked with read_map() again whenever it's loaded). Nothing happens when the
# same map is saved already; a name in use gets " (2)".
func keep_map(title: String, rows: Array) -> void:
	for n in saved_maps():
		if load_map_rows(n) == rows:
			return
	var base := clean_map_name(title)
	if bad_map_name(base) != "":
		base = "Downloaded map"
	var n := base
	var k := 2
	while FileAccess.file_exists(map_file(n)):
		n = "%s (%d)" % [base.left(MAP_NAME_MAX - 5).strip_edges(), k]
		k += 1
	if save_map_rows(n, rows):
		map_name = n
		add_chat(-1, "", "The map is in your map list now, as %s" % n)


# ---------------------------------------------------------------- choosing the map
# Alone or as the host, before wave 1 and while nobody has joined: Esc menu,
# "Map:". Players who join get it from the host (see game_net.gd).

func can_pick_map() -> bool:
	if wave > 0 and state == "playing":
		return false
	return net_mode == "" or (net_mode == "host" and player_count() == 1)


func open_picker() -> void:
	if not can_pick_map():
		if net_mode == "host" and player_count() > 1:
			flash("The map can only change while nobody has joined")
		elif net_mode == "" or net_mode == "host":
			flash("The map can only change before wave 1")
		return
	ed_list = ["Default"] + saved_maps()
	ed_list_top = 0
	pick_open = true


func pick_click(p: Vector2) -> void:
	if ED_LIST_CANCEL.has_point(p) or not ED_LIST_RECT.has_point(p):
		pick_open = false
		return
	for i in mini(ED_LIST_ROWS, ed_list.size() - ed_list_top):
		if not ed_list_row(i).has_point(p):
			continue
		var n: String = ed_list[ed_list_top + i]
		var check := read_map(load_map_rows(n))
		if check.has("error"):
			flash("Can't use %s: %s" % [n, check.error])
			return
		pick_open = false
		if not can_pick_map():
			return
		use_map(check, n)
		build_map()
		var open := menu_open
		new_game()
		menu_open = open
		flash("Map: %s" % n)
		return


# ---------------------------------------------------------------- joining a game on another map

# The host's map, drawn from its letters like the small map.
func draw_map_preview(rows: Array, r: Rect2) -> void:
	var cols: int = String(rows[0]).length()
	var k := minf(r.size.x / cols, r.size.y / rows.size())
	var size := Vector2(cols, rows.size()) * k
	var o := r.position + (r.size - size) / 2.0
	hud.draw_rect(Rect2(o, size), Color(0.13, 0.27, 0.1))
	for y in rows.size():
		for x in cols:
			var ch: String = rows[y][x]
			var cell := Rect2(o + Vector2(x, y) * k, Vector2(k, k))
			match ch:
				"#":
					hud.draw_rect(cell, Color(0.4, 0.28, 0.16))
				"1", "2", "3", "4":
					hud.draw_rect(cell, PLAYER_COLORS[int(ch) - 1])
				"w":
					hud.draw_rect(cell, Color(0.25, 0.45, 0.85))
				"r":
					hud.draw_rect(cell.grow(-k * 0.22), Color(0.62, 0.62, 0.64))
				"t":
					hud.draw_circle(cell.get_center(), k * 0.36, Color(0.1, 0.42, 0.15))


func draw_join_box() -> void:
	var b := JOIN_BOX
	var rows: Array = map_offer.rows
	var check: Dictionary = map_offer.check
	hud.draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.45))
	ui_box(b)
	var title := "JOIN GAME"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	ui_title(Rect2(b.position.x, b.position.y, b.size.x, 60), Vector2((SCREEN_W - tw) / 2.0, b.position.y + 44), title, 34)
	centered(b.position.y + 86, "%s's game is on a map you don't have yet:" % map_offer.host, 16, UI_GREY)
	recess(JOIN_PREVIEW.grow(4))
	draw_map_preview(rows, JOIN_PREVIEW)
	var counts := {"t": 0, "r": 0, "w": 0}
	var size := 0
	for row: String in rows:
		size += row.length() + 1
		for ch in counts:
			counts[ch] += row.count(ch)
	var gates: int = MAX_PLAYERS - check.gates.count(null)
	var info := [
		["Map", map_offer.name, Color(1, 0.85, 0.3)],
		["From", "%s (the host)" % map_offer.host, UI_TEXT],
		["Size", "%d x %d tiles" % [check.cols, check.rows], UI_TEXT],
		["Gates", "%d  (up to %d player%s)" % [gates, gates, "" if gates == 1 else "s"], UI_TEXT],
		["Path", "%d tiles + %d road%s" % [check.loop, gates, "" if gates == 1 else "s"], UI_TEXT],
		["Nature", "%d trees, %d rocks, %d water" % [counts.t, counts.r, counts.w], UI_TEXT],
		["Download", "%.1f KB of map tiles" % (size / 1024.0), UI_TEXT],
	]
	for i in info.size():
		var y := JOIN_PREVIEW.position.y + 18 + i * 28
		text(Vector2(652, y), info[i][0], 15, UI_GREY)
		text(Vector2(738, y), fit_text(info[i][1], 222, 16), 16, info[i][2])
	hud.draw_multiline_string(font, Vector2(340, JOIN_PREVIEW.end.y + 24), "Only the map's tiles are downloaded. Your game checks them and builds the map itself, like the map editor does.", HORIZONTAL_ALIGNMENT_LEFT, 600, 14, 2, UI_GREY)
	var keep: bool = map_offer.keep
	hud.draw_rect(JOIN_KEEP, Color(0.06, 0.06, 0.065))
	hud.draw_rect(JOIN_KEEP, UI_GOLD, false, 1.5)
	if keep:
		hud.draw_polyline(PackedVector2Array([JOIN_KEEP.position + Vector2(4, 10), JOIN_KEEP.position + Vector2(8, 15), JOIN_KEEP.position + Vector2(16, 4)]), UI_GOLD_LIGHT, 2.5)
	text(JOIN_KEEP.position + Vector2(30, 16), "Keep this map in my map list after the game", 15, UI_TEXT)
	if map_offer.accepted:
		button(JOIN_YES, "Joining...", false)
	else:
		button(JOIN_YES, "Download and join", true, true)
	button(JOIN_NO, "Cancel")


func join_box_click(p: Vector2) -> void:
	if map_offer.accepted:
		if JOIN_NO.has_point(p):
			cancel_offer()
		return
	if Rect2(JOIN_KEEP.position, Vector2(380, JOIN_KEEP.size.y)).has_point(p):
		map_offer.keep = not map_offer.keep
	elif JOIN_YES.has_point(p):
		accept_offer(map_offer.keep)
	elif JOIN_NO.has_point(p):
		cancel_offer()


# ---------------------------------------------------------------- opening and leaving

func open_editor() -> void:
	ed_before = map_rows_text.duplicate()
	ed_before_name = map_name
	menu_open = false
	ed_ask_open = false
	code_input.release_focus()
	name_input.release_focus()
	editing = true
	new_game()
	message = ""
	ed_rows = map_rows_text.duplicate()
	ed_name = map_name if map_name != "Default" else ""
	map_name_input.text = ed_name
	map_name_input.visible = true
	console_layer.visible = false
	ed_changed = false
	ed_tool = "Path"
	ed_list_open = false
	ed_confirm = ""
	ed_update()


# Leaves the editor and starts a game alone on rows (already checked).
func close_editor(rows: Array, title: String) -> void:
	editing = false
	ed_list_open = false
	ed_painting = 0
	map_name_input.release_focus()
	map_name_input.visible = false
	console_layer.visible = true
	use_map(read_map(rows), title)
	build_map()
	new_game()


func ed_update() -> void:
	ed_check = read_map(ed_rows)
	ed_dirty = true


# Shows the map being edited. When it isn't a working map yet, its tiles and
# gates still show, with each gate facing its road.
func ed_show() -> void:
	ed_dirty = false
	var pan := camera_pan
	var same_size := ed_rows.size() == map_rows and String(ed_rows[0]).length() == map_cols
	if not ed_check.has("error"):
		use_map(ed_check, ed_name)
	else:
		map_cols = String(ed_rows[0]).length()
		map_rows = ed_rows.size()
		path_cells = {}
		blocked = {}
		gate_cells = [null, null, null, null]
		for y in map_rows:
			for x in map_cols:
				var ch: String = ed_rows[y][x]
				var c := Vector2i(x, y)
				if ch == "#" or ch in ["1", "2", "3", "4"]:
					path_cells[c] = true
				elif ch != ".":
					blocked[c] = ch
				if ch in ["1", "2", "3", "4"]:
					gate_cells[int(ch) - 1] = c
		routes = []
		for g in MAX_PLAYERS:
			if gate_cells[g] == null:
				routes.append([])
				continue
			var gc: Vector2i = gate_cells[g]
			var to := gc + Vector2i(0, -1)
			for d: Vector2i in DIRS:
				if path_cells.has(gc + d):
					to = gc + d
			routes.append([cell_center(gc), cell_center(to)])
		loop_starts = [0, 0, 0, 0]
		area_of = {}
	build_map()
	if same_size:
		camera_pan = pan


func update_visuals(delta: float) -> void:
	if editing and ed_dirty:
		ed_show()
	super(delta)
	# The map-name box hides while the Esc menu or the map list is open (they're drawn under it)
	var show_name := editing and not menu_open and not ed_list_open
	if map_name_input != null and map_name_input.visible != show_name:
		if not show_name:
			map_name_input.release_focus()
		map_name_input.visible = show_name
	if editing:
		# Grid lines always on, and every player's area in their color
		grid_fade = 0.0
		if not ground_mats.is_empty():
			ground_mats[0].set_shader_parameter("grid", 1.0)
		for slot in area_planes.size():
			area_planes[slot].visible = ed_areas
			area_planes[slot].material_override.albedo_color = Color(PLAYER_COLORS[slot], 0.035)


# ---------------------------------------------------------------- editing

func ed_get(c: Vector2i) -> String:
	return ed_rows[c.y][c.x]


func ed_set(c: Vector2i, ch: String) -> void:
	var row: String = ed_rows[c.y]
	ed_rows[c.y] = row.left(c.x) + ch + row.substr(c.x + 1)


func blank_rows(w: int, h: int) -> Array:
	var rows := []
	for y in h:
		rows.append(".".repeat(w))
	return rows


# Paints the tile under the mouse with the tool (erase with the right button).
func ed_paint(c: Vector2i, dragging: bool) -> void:
	if c.x < 0 or c.y < 0 or c.y >= ed_rows.size() or c.x >= String(ed_rows[0]).length() or c == ed_last_cell:
		return
	ed_last_cell = c
	var ch := "."
	if ed_painting == 1:
		if ed_tool == "Gate":
			if dragging:
				return
			ch = str(ed_gate + 1)
			# The gate moves here; where it stood stays path
			for y in ed_rows.size():
				var x: int = String(ed_rows[y]).find(ch)
				if x >= 0:
					ed_set(Vector2i(x, y), "#")
		elif ED_LETTERS.has(ed_tool):
			ch = ED_LETTERS[ed_tool]
		else:
			return
	if ed_get(c) == ch:
		return
	ed_set(c, ch)
	ed_changed = true
	ed_update()


# Adds or removes columns on the right and rows at the bottom.
func ed_resize(dw: int, dh: int) -> void:
	var w := clampi(String(ed_rows[0]).length() + dw, MAP_MIN.x, MAP_MAX.x)
	var h := clampi(ed_rows.size() + dh, MAP_MIN.y, MAP_MAX.y)
	var rows := []
	for y in h:
		var row: String = ed_rows[y] if y < ed_rows.size() else ""
		rows.append(row.left(w).rpad(w, "."))
	if rows == ed_rows:
		return
	ed_rows = rows
	ed_changed = true
	ed_update()


# For clicks that need a second click (like Clear): true on the second one.
func ed_sure(key: String, warning: String) -> bool:
	if ed_confirm_was == key:
		return true
	ed_confirm = key
	flash(warning)
	return false


func ed_over_console(p: Vector2) -> bool:
	return p.y < TOP_BAR_H + 5 or p.y >= BAR_TOP - 6


func ed_tool_rect(i: int) -> Rect2:
	return Rect2(20 + (i % 4) * 76, 586 + (i / 4) * 44, 70, 38)


func editor_input(event: InputEvent) -> void:
	var p := get_viewport().get_mouse_position()
	if event is InputEventMouseButton:
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				ed_painting = 0
			return
		map_name_input.release_focus()
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				ed_confirm_was = ed_confirm
				ed_confirm = ""
				if ed_list_open:
					if event.button_index == MOUSE_BUTTON_LEFT:
						ed_list_click(p)
				elif ed_over_console(p):
					if event.button_index == MOUSE_BUTTON_LEFT:
						ed_console_click(p)
				else:
					ed_painting = 1 if event.button_index == MOUSE_BUTTON_LEFT else 2
					ed_last_cell = Vector2i(-1, -1)
					ed_paint(mouse_cell(), false)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var step := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				if ed_list_open:
					ed_list_top = clampi(ed_list_top + step, 0, maxi(ed_list.size() - ED_LIST_ROWS, 0))
				elif not ed_over_console(p):
					target_zoom = clampf(target_zoom + step * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	elif event is InputEventMouseMotion and ed_painting != 0 and not ed_over_console(p):
		ed_paint(mouse_cell(), true)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			ed_gate = event.keycode - KEY_1
			ed_tool = "Gate"


func ed_console_click(p: Vector2) -> void:
	for i in ED_TOOLS.size():
		if not ed_tool_rect(i).has_point(p):
			continue
		var t: String = ED_TOOLS[i]
		match t:
			"Areas":
				ed_areas = not ed_areas
			"Clear":
				if ed_sure("Clear", "Click Clear again to make the whole map grass"):
					ed_rows = blank_rows(String(ed_rows[0]).length(), ed_rows.size())
					ed_changed = true
					ed_update()
			"Gate":
				if ed_tool == "Gate":
					ed_gate = (ed_gate + 1) % MAX_PLAYERS
				ed_tool = "Gate"
			_:
				ed_tool = t
		return
	if ED_W_MINUS.has_point(p):
		ed_resize(-1, 0)
	elif ED_W_PLUS.has_point(p):
		ed_resize(1, 0)
	elif ED_H_MINUS.has_point(p):
		ed_resize(0, -1)
	elif ED_H_PLUS.has_point(p):
		ed_resize(0, 1)
	elif ED_NEW_RECT.has_point(p):
		if not ed_changed or ed_sure("New", "Not saved yet: click New again to start over anyway"):
			ed_rows = blank_rows(DEFAULT_SIZE.x, DEFAULT_SIZE.y)
			ed_name = ""
			map_name_input.text = ""
			ed_changed = false
			ed_update()
	elif ED_LOAD_RECT.has_point(p):
		ed_list = ["Default"] + saved_maps()
		ed_list_top = 0
		ed_list_open = true
	elif ED_SAVE_RECT.has_point(p):
		ed_save()
	elif ED_PLAY_RECT.has_point(p):
		if ed_check.has("error"):
			flash("Fix the map first: " + ed_check.error)
		else:
			var title := clean_map_name(map_name_input.text)
			close_editor(ed_rows, title if title != "" else "New map")
	elif ED_EXIT_RECT.has_point(p):
		ed_leave()


func ed_leave() -> void:
	if ed_changed and not ed_sure("Exit", "Not saved yet: click again to leave without saving"):
		return
	close_editor(ed_before, ed_before_name)


func ed_save() -> void:
	var n := clean_map_name(map_name_input.text)
	map_name_input.text = n
	var bad := bad_map_name(n)
	if bad != "":
		flash(bad)
		return
	if ed_check.has("error"):
		flash("Can't save yet: " + ed_check.error)
		return
	if n != ed_name and FileAccess.file_exists(map_file(n)) and not ed_sure("Save", "There's already a map called %s: click Save again to replace it" % n):
		return
	if not save_map_rows(n, ed_rows):
		flash("Couldn't save the map")
		return
	ed_name = n
	ed_changed = false
	flash("Saved as %s" % n)


func ed_list_row(i: int) -> Rect2:
	return Rect2(480, 130 + i * 36, 320, 32)


func ed_list_click(p: Vector2) -> void:
	if ED_LIST_CANCEL.has_point(p) or not ED_LIST_RECT.has_point(p):
		ed_list_open = false
		return
	for i in mini(ED_LIST_ROWS, ed_list.size() - ed_list_top):
		if not ed_list_row(i).has_point(p):
			continue
		var n: String = ed_list[ed_list_top + i]
		if ed_changed and not ed_sure("Load " + n, "Not saved yet: click %s again to load it anyway" % n):
			return
		var rows := load_map_rows(n)
		var check := read_map(rows)
		if check.has("error"):
			flash("Can't load %s: %s" % [n, check.error])
			return
		ed_rows = rows
		ed_name = n if n != "Default" else ""
		map_name_input.text = ed_name
		ed_changed = false
		ed_list_open = false
		ed_update()
		return


# ---------------------------------------------------------------- Esc menu

func draw_menu() -> void:
	if editing:
		ed_draw_menu()
		return
	super()
	if net_mode == "":
		button(EDITOR_RECT, "Map editor")
	# The map being played; alone or as the host it can be changed before wave 1
	text(Vector2(HOST_RECT.position.x, MAP_PICK_RECT.position.y + 21), "Map:", 16, UI_TEXT)
	if net_mode == "client":
		text(Vector2(MAP_PICK_RECT.position.x, MAP_PICK_RECT.position.y + 21), fit_text(map_name, MAP_PICK_RECT.size.x, 16), 16, Color(1, 0.85, 0.3))
	else:
		var label := map_name + ("   (change)" if can_pick_map() else "")
		button(MAP_PICK_RECT, label, can_pick_map(), false)
	if pick_open:
		ed_draw_list("CHOOSE A MAP", map_name)
	if net_mode == "map_offer" and not map_offer.is_empty():
		draw_join_box()
	if ed_ask_open:
		hud.draw_rect(MENU_RECT, Color(0, 0, 0, 0.5))
		ui_box(ED_ASK_RECT)
		centered(ED_ASK_RECT.position.y + 50, "Open the map editor?", 22, Color(1, 0.85, 0.3))
		centered(ED_ASK_RECT.position.y + 84, "This ends the game you're playing.", 16, UI_TEXT)
		button(ED_ASK_YES_RECT, "Open the editor", true, true)
		button(ED_ASK_NO_RECT, "Keep playing")
	if board_open:
		draw_board()


func menu_click(p: Vector2) -> void:
	if editing:
		ed_confirm_was = ed_confirm
		ed_confirm = ""
		if ED_BACK_RECT.has_point(p):
			toggle_menu()
		elif ED_LEAVE_RECT.has_point(p):
			if not ed_changed:
				menu_open = false
			ed_leave()
		return
	if board_open:
		super(p)  # the leaderboard box gets the click
		return
	if ed_ask_open:
		if ED_ASK_YES_RECT.has_point(p):
			open_editor()
		elif ED_ASK_NO_RECT.has_point(p):
			ed_ask_open = false
		return
	if net_mode == "map_offer":
		if not map_offer.is_empty():
			join_box_click(p)
		return
	if pick_open:
		pick_click(p)
		return
	if MAP_PICK_RECT.has_point(p) and net_mode != "client":
		open_picker()
		return
	if net_mode == "" and EDITOR_RECT.has_point(p):
		if state == "playing" and (wave > 0 or not towers.is_empty()):
			ed_ask_open = true
		else:
			open_editor()
		return
	super(p)


func toggle_menu() -> void:
	# Esc in the join preview is Cancel; in the map list it closes the list
	if net_mode == "map_offer" and menu_open:
		cancel_offer()
		return
	if pick_open:
		pick_open = false
		return
	super()
	ed_ask_open = false
	if map_name_input != null:
		map_name_input.release_focus()


func ed_draw_menu() -> void:
	hud.draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.5))
	ui_box(ED_MENU_RECT)
	var title := "MAP EDITOR"
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	ui_title(Rect2(ED_MENU_RECT.position.x, ED_MENU_RECT.position.y, ED_MENU_RECT.size.x, 60), Vector2((SCREEN_W - tw) / 2.0, ED_MENU_RECT.position.y + 44), title, 34)
	centered(ED_MENU_RECT.position.y + 80, "Not saved yet." if ed_changed else "Everything is saved.", 15, UI_GREY)
	button(ED_BACK_RECT, "Back to the editor (Esc)", true, true)
	button(ED_LEAVE_RECT, "Exit the editor")
	if message_time > 0.0:
		outlined(Vector2(SCREEN_W / 2.0, ED_MENU_RECT.end.y + 30), message, 18, Color(1, 1, 0.6, minf(message_time, 1.0)))


# ---------------------------------------------------------------- drawing

func draw_hud() -> void:
	if not editing:
		super()
		return
	ed_draw_marks()
	ed_draw_console()
	if ed_list_open:
		ed_draw_list()
	if message_time > 0.0 and not menu_open:
		outlined(Vector2(SCREEN_W / 2.0, MESSAGE_Y), message, 18, Color(1, 1, 0.6, minf(message_time, 1.0)))
	if menu_open:
		draw_menu()


func ground_point(x: float, y: float, h := 0.06) -> Vector2:
	return camera.unproject_position(Vector3(x, h, y))


func cell_shape(c: Vector2i, col: Color, filled := true) -> void:
	var pts := PackedVector2Array([ground_point(c.x, c.y), ground_point(c.x + 1, c.y), ground_point(c.x + 1, c.y + 1), ground_point(c.x, c.y + 1)])
	if filled:
		hud.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		hud.draw_polyline(pts, col, 2.5)


# On the map: the walking direction, gate numbers, the error's tile and the brush.
func ed_draw_marks() -> void:
	if not ed_check.has("error"):
		var r: Array = ed_check.routes[0]
		var pts := r.slice(ed_check.loop_starts[0])
		for i in pts.size():
			var a: Vector2 = pts[i] / CELL
			var b: Vector2 = pts[(i + 1) % pts.size()] / CELL
			var n := int(a.distance_to(b) / 2.5)
			for k in range(1, n + 1):
				chevron(a.lerp(b, float(k) / (n + 1)), (b - a).normalized())
	else:
		# Errors that name a tile, like "(at 5, 3)", mark it in red
		var m := RegEx.create_from_string("(\\d+), (\\d+)").search(ed_check.error)
		if m != null:
			var c := Vector2i(int(m.get_string(1)), int(m.get_string(2)))
			cell_shape(c, Color(1, 0.15, 0.1, 0.55))
			cell_shape(c, Color(1, 0.4, 0.3), false)
	for g in MAX_PLAYERS:
		if g >= gate_cells.size() or gate_cells[g] == null:
			continue
		var gc: Vector2i = gate_cells[g]
		var sp := camera.unproject_position(Vector3(gc.x + 0.5, 1.9, gc.y + 0.5))
		hud.draw_circle(sp, 11, Color(0, 0, 0, 0.7))
		hud.draw_circle(sp, 9, PLAYER_COLORS[g])
		text(sp + Vector2(-4.5, 6), str(g + 1), 16, Color.BLACK)
	var mp := get_viewport().get_mouse_position()
	if ed_list_open or menu_open or ed_over_console(mp):
		return
	var c := mouse_cell()
	if in_map(c):
		var col := ed_tool_color(ed_tool)
		cell_shape(c, Color(col, 0.35))
		cell_shape(c, col.lightened(0.3), false)


func ed_tool_color(t: String) -> Color:
	match t:
		"Path": return Color(0.75, 0.5, 0.25)
		"Erase": return Color(1, 0.35, 0.3)
		"Gate": return PLAYER_COLORS[ed_gate]
		"Rock": return Color(0.65, 0.65, 0.68)
		"Tree": return Color(0.25, 0.75, 0.3)
		"Water": return Color(0.3, 0.6, 1.0)
	return Color.WHITE


func chevron(p: Vector2, d: Vector2) -> void:
	var side := Vector2(-d.y, d.x)
	var tip := ground_point(p.x + d.x * 0.22, p.y + d.y * 0.22, 0.05)
	var l := ground_point(p.x - d.x * 0.15 + side.x * 0.25, p.y - d.y * 0.15 + side.y * 0.25, 0.05)
	var r := ground_point(p.x - d.x * 0.15 - side.x * 0.25, p.y - d.y * 0.15 - side.y * 0.25, 0.05)
	hud.draw_polyline(PackedVector2Array([l, tip, r]), Color(0, 0, 0, 0.5), 5.0)
	hud.draw_polyline(PackedVector2Array([l, tip, r]), Color(1, 0.95, 0.8, 0.95), 2.5)


func ed_draw_console() -> void:
	# Top bar
	var top := Rect2(0, 0, SCREEN_W, TOP_BAR_H)
	stone_blocks(top, UI_STONE, 30, 96)
	vgrad(top, Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.3))
	bevel(Rect2(-6, TOP_BAR_H, SCREEN_W + 12, 5), 2, UI_GOLD_LIGHT, UI_GOLD_DARK)
	text(Vector2(16, 21), "MAP EDITOR", 18, Color(1, 0.85, 0.3))
	var title := ed_name if ed_name != "" else "New map"
	if ed_changed:
		title += "   (not saved)"
	text(Vector2(140, 21), title, 16, UI_TEXT)
	text(Vector2(1010, 21), "Esc: menu   WASD / wheel: camera", 14, UI_GREY)
	# Console
	var r := Rect2(0, BAR_TOP, SCREEN_W, SCREEN_H - BAR_TOP)
	stone_blocks(r, UI_STONE, 36, 96)
	vgrad(r, Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.35))
	bevel(Rect2(-6, BAR_TOP - 6, SCREEN_W + 12, 6), 3, UI_GOLD_LIGHT, UI_GOLD_DARK)
	# Tools
	ui_heading(Vector2(20, 574), "TOOLS", 300)
	for i in ED_TOOLS.size():
		var t: String = ED_TOOLS[i]
		var b := ed_tool_rect(i)
		var label := t
		if t == "Gate":
			label = "Gate %d" % (ed_gate + 1)
		button(b, label, true, t == ed_tool or (t == "Areas" and ed_areas))
		var ic := b.position + Vector2(9, 9)
		match t:
			"Areas":
				for k in 4:
					hud.draw_rect(Rect2(ic + Vector2((k % 2) * 4 - 4, (k / 2) * 4 - 4), Vector2(4, 4)), PLAYER_COLORS[k])
			"Clear":
				pass
			_:
				hud.draw_rect(Rect2(ic - Vector2(4, 4), Vector2(8, 8)), ed_tool_color(t))
	text(Vector2(20, 690), "Gate: 1-4 picks the gate, click places it.", 13, UI_GREY)
	text(Vector2(20, 707), "Left-drag paints, right-drag erases.", 13, UI_GREY)
	vdivider(334, BAR_TOP + 12, SCREEN_H - 10)
	# Map: name and size
	ui_heading(Vector2(350, 574), "MAP", 280)
	text(Vector2(350, 608), "Name", 15, UI_GREY)
	text(Vector2(350, 646), "Width", 15, UI_GREY)
	button(ED_W_MINUS, "-", String(ed_rows[0]).length() > MAP_MIN.x)
	text(Vector2(461, 647), str(String(ed_rows[0]).length()), 18, UI_TEXT)
	button(ED_W_PLUS, "+", String(ed_rows[0]).length() < MAP_MAX.x)
	text(Vector2(350, 684), "Height", 15, UI_GREY)
	button(ED_H_MINUS, "-", ed_rows.size() > MAP_MIN.y)
	text(Vector2(461, 685), str(ed_rows.size()), 18, UI_TEXT)
	button(ED_H_PLUS, "+", ed_rows.size() < MAP_MAX.y)
	text(Vector2(536, 646), "%d to %d" % [MAP_MIN.x, MAP_MAX.x], 13, UI_DIM)
	text(Vector2(536, 684), "%d to %d" % [MAP_MIN.y, MAP_MAX.y], 13, UI_DIM)
	vdivider(646, BAR_TOP + 12, SCREEN_H - 10)
	# Check
	ui_heading(Vector2(662, 574), "CHECK", 290)
	var ok := Color(0.5, 0.95, 0.45)
	if ed_check.has("error"):
		hud.draw_circle(Vector2(668, 595), 5, Color(1, 0.35, 0.3))
		hud.draw_multiline_string(font, Vector2(680, 600), ed_check.error, HORIZONTAL_ALIGNMENT_LEFT, 275, 14, 3, Color(1, 0.6, 0.5))
		text(Vector2(680, 668), "Fix this to save or play the map.", 13, UI_DIM)
	else:
		var gates: int = MAX_PLAYERS - ed_check.gates.count(null)
		var counts := ed_area_counts()
		var even: bool = counts.max() <= counts.min() * ED_UNEVEN
		var parts := []
		for n in counts:
			parts.append(str(n))
		var lines := [
			[ok, "Loop: %d tiles, closed" % ed_check.loop],
			[ok, "Gates: %d (up to %d player%s)" % [gates, gates, "" if gates == 1 else "s"]],
			[ok, "Monsters walk clockwise"],
			[ok if even else Color(1, 0.8, 0.35), "Areas: %s tiles%s" % [" / ".join(parts), "" if even else " (uneven)"]],
			[ok, "Ready to save and play"],
		]
		for i in lines.size():
			var y := 600 + i * 22
			hud.draw_circle(Vector2(668, y - 5), 5, lines[i][0])
			text(Vector2(680, y), lines[i][1], 14, UI_TEXT)
	vdivider(964, BAR_TOP + 12, SCREEN_H - 10)
	# File
	ui_heading(Vector2(980, 574), "FILE", 278)
	button(ED_NEW_RECT, "New")
	button(ED_LOAD_RECT, "Load...")
	button(ED_SAVE_RECT, "Save", true, ed_changed)
	button(ED_PLAY_RECT, "Play this map", not ed_check.has("error"))
	button(ED_EXIT_RECT, "Exit the editor")


# Buildable tiles in each gate's area.
func ed_area_counts() -> Array:
	var counts := []
	for g in MAX_PLAYERS:
		if ed_check.gates[g] != null:
			counts.append(0)
	for c: Vector2i in ed_check.areas:
		var s: int = ed_check.areas[c]
		if s >= 0 and s < counts.size() and not ed_check.path.has(c) and not ed_check.blocked.has(c):
			counts[s] += 1
	return counts


func ed_draw_list(title := "LOAD A MAP", current := ed_name) -> void:
	hud.draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, 0.4))
	ui_box(ED_LIST_RECT)
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	ui_title(Rect2(ED_LIST_RECT.position.x, ED_LIST_RECT.position.y, ED_LIST_RECT.size.x, 54), Vector2((SCREEN_W - tw) / 2.0, ED_LIST_RECT.position.y + 40), title, 28)
	for i in mini(ED_LIST_ROWS, ed_list.size() - ed_list_top):
		var n: String = ed_list[ed_list_top + i]
		button(ed_list_row(i), n + ("  (built in)" if n == "Default" else ""), true, n == current)
	if ed_list.size() > ED_LIST_ROWS:
		centered(ED_LIST_CANCEL.position.y - 6, "Scroll for more (%d maps)" % ed_list.size(), 13, UI_DIM)
	button(ED_LIST_CANCEL, "Cancel")
