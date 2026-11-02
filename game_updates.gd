extends "res://game_base.gd"
## The debug log window, checking for and installing updates, and unpacking.

# The update check reads the last releases, to show what's new since this version
const RELEASES_PAGE := 30
const RELEASES_LIST_API := "https://api.github.com/repos/gettic/Gettics-first-TD/releases?per_page=%d" % RELEASES_PAGE
const NOTES_MOST := 20  # versions shown in the update popup, newest first

var update_changes: Array = []  # [tag, "What's new"] of each newer version, newest first
var update_more := false  # there are older updates than the ones in update_changes
const UPDATE_CHECK_EVERY := 1800.0  # seconds between update checks while the game runs
var update_checking := false  # a check is on its way
var update_etag := ""  # GitHub's tag for the last answer, so an unchanged list costs almost nothing


# Catches every error, warning and print in the debug build, for the log window.
# Godot may call it from other threads, so lines wait in a list until the game takes them.
class DebugLog extends Logger:
	var lines: Array = []  # [text, color, is_error]
	var lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		# Errors raised from the game's own code: point at that line, not inside the engine
		for bt in script_backtraces:
			if bt.get_frame_count() > 0:
				function = bt.get_frame_function(0)
				file = bt.get_frame_file(0)
				line = bt.get_frame_line(0)
				break
		var kind := "ERROR"
		var col := Color(1.0, 0.45, 0.4)
		if error_type == ERROR_TYPE_WARNING:
			kind = "WARNING"
			col = Color(1.0, 0.8, 0.35)
		elif error_type == ERROR_TYPE_SCRIPT:
			kind = "SCRIPT ERROR"
		elif error_type == ERROR_TYPE_SHADER:
			kind = "SHADER ERROR"
		var what := rationale if rationale != "" else code
		add("%s: %s\n    at %s (%s:%d)" % [kind, what, function, file, line], col, error_type != ERROR_TYPE_WARNING)

	func _log_message(message: String, error: bool) -> void:
		add(message.strip_edges(false, true), Color(1.0, 0.6, 0.5) if error else Color(0.75, 0.75, 0.8), error)

	func add(text: String, col: Color, is_error := false) -> void:
		lock.lock()
		lines.append([Time.get_time_string_from_system() + "  " + text, col, is_error])
		lock.unlock()

	func take() -> Array:
		lock.lock()
		var out := lines
		lines = []
		lock.unlock()
		return out


var debug_log: DebugLog  # only in the debug build
var log_window: Window
var log_text: RichTextLabel
var log_errors := 0


# ---------------------------------------------------------------- debug log

# True in the debug build, or when started with "-- --debug-log" (for example from source).
func is_debug_game() -> bool:
	return OS.has_feature(DEBUG_FEATURE) or "--debug-log" in OS.get_cmdline_user_args()


# A second window next to the game that lists every error, warning and print.
# F12 shows and hides it.
func open_log_window() -> void:
	debug_log = DebugLog.new()
	OS.add_logger(debug_log)
	get_viewport().gui_embed_subwindows = false  # a real window of its own
	log_window = Window.new()
	log_window.title = "Gettic's first TD - debug log (F12 hides it)"
	log_window.size = Vector2i(720, 460)
	var main_window := get_window()
	log_window.position = main_window.position + Vector2i(main_window.size.x + 8, 0)
	log_window.close_requested.connect(func(): log_window.hide())
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_window.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_top = 8
	box.offset_right = -8
	box.offset_bottom = -8
	log_window.add_child(box)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var copy := Button.new()
	copy.text = "Copy all"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(log_text.get_parsed_text()))
	buttons.add_child(copy)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func():
		log_text.clear()
		log_errors = 0)
	buttons.add_child(clear)
	var folder := Button.new()
	folder.text = "Open log files"
	folder.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path("user://logs")))
	buttons.add_child(folder)
	log_text = RichTextLabel.new()
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.scroll_following = true
	log_text.selection_enabled = true
	log_text.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(log_text)
	add_child(log_window)
	print("Debug log started: Gettic's first TD v%s, Godot %s, %s" % [
		ProjectSettings.get_setting("application/config/version", "0"),
		Engine.get_version_info().string, OS.get_name()])


func update_log_window() -> void:
	var new_lines := debug_log.take()
	for l in new_lines:
		log_text.push_color(l[1])
		log_text.add_text(l[0] + "\n")
		log_text.pop()
		if l[2]:
			log_errors += 1
	if new_lines.size() > 0:
		log_window.title = "Gettic's first TD - debug log, %d errors (F12 hides it)" % log_errors


# ---------------------------------------------------------------- updates

func check_for_update() -> void:
	version = str(ProjectSettings.get_setting("application/config/version", "0"))
	# The debug build stays a separate single file and leaves the normal game alone.
	if is_debug_game():
		return
	# Clean up the old game files left behind by the last update.
	if OS.has_feature("template"):
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--remove-old="):
				remove_old_exe(arg.trim_prefix("--remove-old="))
		# A fresh download: warn that it will unpack itself
		if is_packed():
			update_dialog = "unpack"
		else:
			# Unpacked: the files should be named with this version
			var wanted := game_file_name(version) + ".exe"
			var mine := game_exe_path().get_file()
			if mine != wanted and mine.to_lower().begins_with(GAME_NAME.to_lower()) \
					and rename_game(wanted.get_basename()) == "":
				restart_game(game_exe_path().get_base_dir().path_join(wanted), game_exe_path())
				return
			remove_other_versions()
	# Only the exported game with a window asks GitHub (at start and from time to
	# time), so test runs, headless runs and runs from the project folder don't
	# use up GitHub's request limit. --update-check turns it on anyway (for tests
	# of the update feature), and so does --update-check-every=SECONDS.
	var every := UPDATE_CHECK_EVERY
	var asked := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--update-check":
			asked = true
		elif arg.begins_with("--update-check-every="):
			asked = true
			every = maxf(arg.trim_prefix("--update-check-every=").to_float(), 1.0)
	if not asked and not (OS.has_feature("template") and DisplayServer.get_name() != "headless"):
		return
	request_releases()
	# Look again from time to time while the game runs
	var timer := Timer.new()
	timer.wait_time = every
	timer.timeout.connect(recheck_for_update)
	add_child(timer)
	timer.start()


# Asks GitHub for the last releases. The answer comes later, in _on_update_checked.
func request_releases() -> void:
	if update_checking:
		return
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(_on_update_checked.bind(http))
	var headers := ["User-Agent: GetticsFirstTD", "Accept: application/vnd.github+json"]
	# Unchanged since last time: GitHub just says so, which is small and doesn't count toward its limit
	if update_etag != "":
		headers.append("If-None-Match: " + update_etag)
	if http.request(RELEASES_LIST_API, headers) != OK:
		http.queue_free()
		return
	update_checking = true


# The timer's check, skipped while the update popup is open or downloading.
func recheck_for_update() -> void:
	if update_dialog == "":
		request_releases()


func _on_update_checked(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	update_checking = false
	# No internet, GitHub not answering, or nothing new since last time: just play on.
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	for h in headers:
		if h.to_lower().begins_with("etag:"):
			update_etag = h.substr(5).strip_edges()
	var list = JSON.parse_string(body.get_string_from_utf8())
	if not list is Array:
		return
	read_releases(list)


# Finds the releases newer than this version: the newest one is the update,
# and all of their "What's new" go in the popup, newest first.
func read_releases(list: Array) -> void:
	var newer: Array = []
	for data in list:
		if not data is Dictionary or data.get("draft", false) or data.get("prerelease", false):
			continue
		if is_newer(str(data.get("tag_name", "")), version):
			newer.append(data)
	if newer.is_empty():
		return
	newer.sort_custom(func(a, b): return is_newer(str(a["tag_name"]), str(b["tag_name"])))
	# Too many to show: the newest ones, and a note about the rest. A full
	# page means there may be even older ones GitHub didn't send.
	update_changes = []
	for data in newer.slice(0, NOTES_MOST):
		var notes = data.get("body")
		update_changes.append([str(data["tag_name"]), clean_notes(notes if notes is String else "")])
	update_more = newer.size() > NOTES_MOST or (newer.size() == list.size() and list.size() >= RELEASES_PAGE)
	# The download is the newest release's files, as before
	var newest: Dictionary = newer[0]
	# A check during the game may find a newer one: forget the last one's files
	update_zip_url = ""
	update_exe_url = ""
	update_pck_url = ""
	update_version = str(newest["tag_name"])
	update_url = str(newest.get("html_url", ""))
	update_notes = update_changes[0][1]
	var assets = newest.get("assets")
	if assets is Array:
		for asset in assets:
			if not asset is Dictionary:
				continue
			var name := str(asset.get("name", ""))
			var url := str(asset.get("browser_download_url", ""))
			if name.ends_with("-windows.zip"):
				update_zip_url = url
			elif name.ends_with(".exe"):
				update_exe_url = url
			elif name.ends_with("-godot-%s.pck" % engine_tag()):
				update_pck_url = url  # just the game, for this same engine


# Keeps only the "What's new" part of the release notes and removes Markdown symbols.
func clean_notes(body: String) -> String:
	var cut := body.find("**How to play")
	if cut >= 0:
		body = body.substr(0, cut)
	var lines := PackedStringArray()
	for line in body.replace("\r", "").split("\n"):
		line = line.replace("**", "").replace("`", "").strip_edges()
		if line == "" or line.to_lower().begins_with("what's new"):
			continue
		if line.begins_with("- "):
			line = "•  " + line.substr(2)
		lines.append(line)
	return "\n".join(lines)


func game_exe_path() -> String:
	return OS.get_executable_path()


func game_pck_path() -> String:
	return game_exe_path().get_basename() + ".pck"


# ---------------------------------------------------------------- unpacking
#
# The download is one .exe: the Godot engine with the game packed inside it.
# The first time it runs it unpacks itself into GAME_FOLDER next to the download:
# the engine ("Gettic's first TD v1.16.exe") and the game ("... v1.16.pck",
# which Godot finds by having the same name). Updates then only need the small
# game file, unless the engine itself changed, and rename both to the new version.

# "Gettic's first TD v1.16" for version "1.16" or "v1.16".
func game_file_name(ver: String) -> String:
	return "%s v%s" % [GAME_NAME, ver.trim_prefix("v")]

# True when the game is still packed inside the .exe (a fresh download).
func is_packed() -> bool:
	return is_packed_file(game_exe_path())


func is_packed_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 4:
		return false
	f.seek(f.get_length() - 4)
	return f.get_buffer(4).get_string_from_ascii() == "GDPC"


# The engine version, which must match for a game file to work with an engine.
func engine_tag() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d.%s" % [v.major, v.minor, v.patch, v.status]


func unpack_folder() -> String:
	return game_exe_path().get_base_dir().path_join(GAME_FOLDER)


# Where the first run unpacks to: next to the download, or where the player chose.
func unpack_destination() -> String:
	return unpack_chosen if unpack_chosen != "" else unpack_folder()


# Lets the player pick another place to unpack to (Windows' own folder picker).
func choose_unpack_folder() -> void:
	if folder_picker == null:
		folder_picker = FileDialog.new()
		folder_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		folder_picker.access = FileDialog.ACCESS_FILESYSTEM
		folder_picker.use_native_dialog = true
		folder_picker.title = "Choose where to unpack the game"
		folder_picker.dir_selected.connect(_on_unpack_folder_chosen)
		add_child(folder_picker)
	folder_picker.current_dir = unpack_destination().get_base_dir()
	folder_picker.popup_centered(Vector2i(800, 500))


# The game goes straight into the folder the player chose.
func _on_unpack_folder_chosen(dir: String) -> void:
	unpack_chosen = dir.replace("\\", "/")


# Splits a packed .exe into [engine, game]. Godot keeps the game in a section
# called "pck" at the end of the .exe, so the engine is everything before it,
# with that section taken out of the .exe's header. Returns [] if it isn't one.
func split_packed(data: PackedByteArray) -> Array:
	var n := data.size()
	if n < 4096 or data.slice(n - 4).get_string_from_ascii() != "GDPC":
		return []
	var pck_size := data.decode_s64(n - 12)
	var pe := data.decode_u32(0x3C)
	var count := data.decode_u16(pe + 6)
	var optional := pe + 24
	var table := optional + data.decode_u16(pe + 20)
	var last := table + (count - 1) * 40
	if count < 2 or data.slice(last, last + 8).get_string_from_ascii() != "pck":
		return []
	var start := data.decode_u32(last + 20)
	if start + pck_size + 12 != n:
		return []
	var engine := data.slice(0, start)
	engine.encode_u16(pe + 6, count - 1)
	for i in 40:
		engine[last + i] = 0
	# The program's size in memory now ends with the section before it
	var before := last - 40
	var align := data.decode_u32(optional + 32)
	var end := data.decode_u32(before + 12) + data.decode_u32(before + 8)
	engine.encode_u32(optional + 56, ceili(float(end) / align) * align)
	engine.encode_u32(optional + 64, 0)  # checksum, not needed for programs
	return [engine, data.slice(start, start + pck_size)]


# Writes a packed .exe's engine and game into a folder, named for its version.
# Returns the engine's path, or an error message.
func unpack_to(data: PackedByteArray, folder: String, ver: String) -> String:
	var parts := split_packed(data)
	if parts.is_empty():
		return "The game file is damaged."
	DirAccess.make_dir_recursive_absolute(folder)
	var exe := folder.path_join(game_file_name(ver) + ".exe")
	var error := replace_file(exe, parts[0])
	if error == "":
		error = replace_file(exe.get_basename() + ".pck", parts[1])
	return error if error != "" else exe


# Renames this game's .exe and .pck (Windows lets a running program be renamed).
# Returns an error message, or "".
func rename_game(new_name: String) -> String:
	var dir := game_exe_path().get_base_dir()
	if DirAccess.rename_absolute(game_pck_path(), dir.path_join(new_name + ".pck")) != OK:
		return "Could not rename the game file."
	if DirAccess.rename_absolute(game_exe_path(), dir.path_join(new_name + ".exe")) != OK:
		DirAccess.rename_absolute(dir.path_join(new_name + ".pck"), game_pck_path())
		return "Could not rename the game file."
	return ""


# Deletes other versions' files (and .old files) from the game folder, for
# example when a newer download was unpacked next to an older one.
func remove_other_versions(tries := 10) -> void:
	var dir := game_exe_path().get_base_dir()
	var mine := [game_exe_path().get_file().to_lower(), game_pck_path().get_file().to_lower()]
	var left := false
	for file in DirAccess.get_files_at(dir):
		var lower := file.to_lower()
		var ours := lower.begins_with(GAME_NAME.to_lower()) and (lower.ends_with(".exe") or lower.ends_with(".pck") or lower.ends_with(".old"))
		if ours and not mine.has(lower) and DirAccess.remove_absolute(dir.path_join(file)) != OK:
			left = true
	# The old version may still be closing, so try again a few times.
	if left and tries > 1:
		await get_tree().create_timer(0.5).timeout
		remove_other_versions(tries - 1)


# Writes a file. Windows won't let a running game's files be overwritten, but
# they can be renamed, so an existing file is moved to .old first (deleted on
# the next start). Returns an error message, or "".
func replace_file(path: String, data: PackedByteArray) -> String:
	var old := path + ".old"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(old)
		if DirAccess.rename_absolute(path, old) != OK:
			return "Could not replace %s." % path.get_file()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		if FileAccess.file_exists(old):
			DirAccess.rename_absolute(old, path)
		return "Could not write %s." % path.get_file()
	f.store_buffer(data)
	f.close()
	return ""


# The player said yes to the first-run warning.
func unpack_self() -> void:
	var data := FileAccess.get_file_as_bytes(game_exe_path())
	var result := unpack_to(data, unpack_destination(), version)
	if not result.ends_with(".exe"):
		update_error = result
		update_dialog = "unpack_failed"
		return
	restart_game(result, game_exe_path())


func start_update() -> void:
	# Running from the Godot editor (or no .exe in the release): open the download page instead.
	if not OS.has_feature("template") or update_exe_url == "":
		OS.shell_open(update_url)
		update_dialog = ""
		return
	# Unpacked with the same engine: only the small game file is needed
	if update_pck_url != "" and not is_packed():
		download_update(update_pck_url, "update.pck")
	else:
		download_update(update_exe_url, "update.exe")


func download_update(url: String, file_name: String) -> void:
	update_dialog = "downloading"
	var path := OS.get_user_data_dir().path_join(file_name)
	update_http = HTTPRequest.new()
	update_http.download_file = path
	add_child(update_http)
	update_http.request_completed.connect(_on_update_downloaded.bind(path))
	if update_http.request(url, ["User-Agent: GetticsFirstTD"]) != OK:
		update_failed("Could not start the download.")


func _on_update_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, path: String) -> void:
	update_http.queue_free()
	update_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		update_failed("The download failed. Check your internet connection.")
		return
	var data := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	var exe := game_exe_path()
	if path.ends_with(".pck"):
		# Just the game: write it under the new version's name, rename the
		# engine to match, and start again (the new version deletes the old game file)
		var new_exe := exe.get_base_dir().path_join(game_file_name(update_version) + ".exe")
		var error := replace_file(new_exe.get_basename() + ".pck", data)
		if error == "" and new_exe != exe and DirAccess.rename_absolute(exe, new_exe) != OK:
			error = "Could not rename the game file."
		if error != "":
			update_failed(error)
			return
		restart_game(new_exe, exe)
		return
	# The whole game: unpack it here (or into the game folder, if this is a download)
	var folder := exe.get_base_dir() if not is_packed() else unpack_folder()
	var new_exe := unpack_to(data, folder, update_version)
	if not new_exe.ends_with(".exe"):
		update_failed(new_exe)
		return
	restart_game(new_exe, exe)


# Starts the new version and closes this one. The new version deletes this
# version's file once it has closed (see remove_old_exe).
func restart_game(new_exe: String, old_exe: String) -> void:
	var args := PackedStringArray()
	if new_exe.to_lower() != old_exe.to_lower():
		args = ["--", "--remove-old=" + old_exe]
	# The profile's last stats and play time (this quit skips the close request),
	# written before the new version starts and reads it
	if has_method("save_profile"):
		call("save_profile")
	OS.create_process(new_exe, args)
	get_tree().quit()


# Deletes the previous version's game file after an update, or the downloaded
# file after unpacking. Only files whose name starts like the game's own are
# deleted, and only next to this game, in the folder above it, or anywhere if
# it is a packed download of the game (the player chose where to unpack).
func remove_old_exe(path: String, tries := 10) -> void:
	path = path.replace("\\", "/")
	var exe := game_exe_path()
	var name := path.get_file().to_lower()
	var dir := path.get_base_dir()
	var near := dir == exe.get_base_dir() or dir == exe.get_base_dir().get_base_dir() or is_packed_file(path)
	if not near or path.to_lower() == exe.to_lower() \
			or not name.ends_with(".exe") or not (name.begins_with("gettic's first td") or name.begins_with("getticsfirsttd")):
		return
	if not FileAccess.file_exists(path):
		return
	# The old version may still be closing, so try again a few times.
	if DirAccess.remove_absolute(path) != OK and tries > 1:
		await get_tree().create_timer(0.5).timeout
		remove_old_exe(path, tries - 1)


func update_failed(message: String) -> void:
	update_dialog = "failed"
	update_error = message


# Compares versions like "v1.10" and "1.2" number by number.
func is_newer(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return x > y
	return false
