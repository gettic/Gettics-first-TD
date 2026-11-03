extends "res://game_updates.gd"
## Sound: the music and the sound effects. Holds the players, the list of sounds
## with each one's limits, the volume settings, and update_audio(). That function
## plays the music for the moment (calm, wave, boss) and the sounds that come from
## watching the game: waves, the end, building, shields, healers.
## Every computer plays its own sounds from what it sees. No network messages.
## Headless runs (tests) use Godot's silent dummy audio device, so the code here
## runs the same way there.

const SOUND_DIR := "res://assets/sounds/"
const MUSIC_DIR := "res://assets/music/"

# name -> files (1: name.wav, more: name_1.wav, name_2.wav, ...), volume (dB),
# at most this many at once, at least this many seconds between two starts,
# random pitch (0.08: +-8%), duck (dB the music goes down while it plays),
# frequent (tower shots, hits and deaths: the first to give way when every player
# is busy) and important (always gets a player, see sound_priority()).
const SOUNDS := {
	# Towers (most frequent: quiet, few at once)
	"arrow_fire": {"files": 3, "db": -18.0, "max": 4, "gap": 0.05, "pitch": 0.08, "frequent": true},
	"arrow_hit": {"files": 2, "db": -20.0, "max": 3, "gap": 0.05, "pitch": 0.1, "frequent": true},
	"cannon_fire": {"files": 2, "db": -13.0, "max": 3, "gap": 0.08, "pitch": 0.06, "frequent": true},
	"cannon_boom": {"files": 2, "db": -11.0, "max": 3, "gap": 0.08, "pitch": 0.08, "frequent": true},
	"frost_fire": {"db": -19.0, "max": 3, "gap": 0.06, "pitch": 0.08, "frequent": true},
	"frost_hit": {"db": -20.0, "max": 3, "gap": 0.06, "pitch": 0.1, "frequent": true},
	"frost_ring": {"db": -14.0, "max": 2, "gap": 0.15, "pitch": 0.06},
	"spark_zap": {"files": 2, "db": -15.0, "max": 3, "gap": 0.06, "pitch": 0.1, "frequent": true},
	"poison_spit": {"db": -19.0, "max": 3, "gap": 0.06, "pitch": 0.08, "frequent": true},
	"poison_cloud": {"files": 2, "db": -15.0, "max": 3, "gap": 0.1, "pitch": 0.1, "frequent": true},
	# Monsters
	"death": {"files": 3, "db": -14.0, "max": 4, "gap": 0.04, "pitch": 0.1, "frequent": true},
	"boss_death": {"db": -3.0, "max": 1, "duck": 4.0, "important": true},
	"shield_break": {"db": -10.0, "max": 3, "gap": 0.08, "pitch": 0.08},
	"heal": {"db": -18.0, "max": 2, "gap": 0.5, "pitch": 0.05},
	"split": {"db": -13.0, "max": 3, "gap": 0.07, "pitch": 0.1},
	# Grimwhistle (wave 300)
	"grim_entrance": {"db": -3.0, "max": 1, "gap": 1.0, "duck": 8.0, "important": true},
	"crescendo": {"db": -8.0, "max": 2, "gap": 0.3, "pitch": 0.04, "duck": 2.0, "important": true},
	"grim_fall": {"db": -3.0, "max": 1, "gap": 0.5, "duck": 6.0, "important": true},
	# Abilities
	"meteor": {"db": -3.0, "max": 2, "pitch": 0.03, "duck": 5.0, "important": true},
	"freeze": {"db": -5.0, "max": 1, "gap": 0.5, "duck": 4.0, "important": true},
	# The game
	"wave_start": {"db": -7.0, "max": 1, "gap": 0.5, "duck": 5.0, "important": true},
	"boss_wave": {"db": -4.0, "max": 1, "gap": 0.5, "duck": 6.0, "important": true},
	"win": {"db": -3.0, "max": 1, "duck": 8.0, "important": true},
	"lose": {"db": -3.0, "max": 1, "duck": 8.0, "important": true},
	"endless_start": {"db": -3.0, "max": 1, "gap": 1.0, "duck": 8.0, "important": true},
	"daily_start": {"db": -4.0, "max": 1, "gap": 1.0, "duck": 6.0, "important": true},
	"replay_start": {"db": -6.0, "max": 1, "gap": 0.5, "important": true},
	"story_page": {"db": -12.0, "max": 1, "gap": 0.5, "pitch": 0.04, "important": true},
	"festival_frostfall": {"db": -7.0, "max": 1, "gap": 2.0, "duck": 5.0, "important": true},
	"festival_lantern": {"db": -7.0, "max": 1, "gap": 2.0, "duck": 5.0, "important": true},
	"festival_paint": {"db": -7.0, "max": 1, "gap": 2.0, "duck": 5.0, "important": true},
	"build": {"db": -9.0, "max": 2, "gap": 0.05, "pitch": 0.05},
	"upgrade": {"db": -9.0, "max": 2, "gap": 0.05, "pitch": 0.03},
	"sell": {"db": -9.0, "max": 2, "gap": 0.05, "pitch": 0.05},
	"ping": {"db": -7.0, "max": 2, "gap": 0.3, "important": true},
	"gift": {"db": -6.0, "max": 1, "gap": 0.3, "important": true},
	"achievement": {"db": -9.0, "max": 1, "gap": 0.6, "duck": 2.0, "important": true},
	"save": {"db": -8.0, "max": 1, "gap": 0.2, "important": true},
	"load": {"db": -8.0, "max": 1, "gap": 0.2, "important": true},
	"click": {"db": -12.0, "max": 2, "gap": 0.03, "pitch": 0.03, "important": true},
	"denied": {"db": -12.0, "max": 1, "gap": 0.1, "important": true},
}

# The music: 4 layers of the same 64 s dark-fantasy piece (16 bars) that play in step.
# Each mood is a volume per layer; the layers fade over MUSIC_FADE seconds.
const MUSIC_LAYERS := ["soft", "pad", "drive", "boss"]
const MUSIC_MOODS := {"calm": [1.4, 1.0, 0.0, 0.0], "wave": [0.7, 1.0, 1.0, 0.0], "boss": [0.0, 0.8, 1.0, 1.0]}
const MUSIC_FADE := {"calm": 5.0, "wave": 3.0, "boss": 2.0}
const CALM_AFTER := 2.0  # seconds after the last monster before the music calms down
const VOICES_HIGH := 24  # effect players (Graphics High)...
const VOICES_LOW := 16  # ...and on Low
const VOICES_KEPT := 6  # of those, kept free for the important sounds
const OFF_SCREEN_DB := -9.0  # sounds off the screen are this much quieter
const SAME_SOUND_DB := -2.0  # and each copy of the same sound already playing makes a new one this much quieter
const OTHERS_DB := -8.0  # building, upgrading and selling by the other players
const REPLAY_MUSIC_DB := -6.0
const PAUSED_MUSIC_DB := -4.0

var music_volume := 0.7  # 0..1, the Settings box's sliders (saved in settings.cfg)
var effects_volume := 0.8

var audio_root: Node
var sound_streams := {}  # name -> Array of AudioStream
var voices: Array[AudioStreamPlayer] = []
var voice_sound: Array[String] = []  # what each player plays now
var voice_start: Array[int] = []  # when it started (msec)
var voice_end: Array[int] = []  # when its sound ends (msec)
var sound_last := {}  # name -> msec it last started
var music_player: AudioStreamPlayer
var music_stream: AudioStreamSynchronized
var music_mix: Array = [1.4, 1.0, 0.0, 0.0]  # the layers' volumes now
var music_duck := 0.0  # dB the music is down for a fanfare (comes back by itself)
var calm_wait := 0.0

# For tests: how often each sound was asked for and really played, and the most
# copies of each that played at once.
var sound_asked := {}
var sound_played := {}
var sound_most := {}

# What update_audio() saw last frame
var heard_wave := -1
var heard_state := ""
var heard_towers := {}  # cell -> [level, owner]
var heard_shields := {}  # Enemy -> true while its shield is up
var heal_clock := {}  # Enemy -> game seconds to its next chime
var heard_story := ""  # the story card on screen
var heard_fresh := false  # a new game (wave 0) last frame (for the festival jingle)
var ui_buttons := {}  # Rect2 -> [enabled, frame drawn] (see note_button())


# ---------------------------------------------------------------- setup

# Made the first time anything plays (or the settings load), so no hook is needed.
func setup_audio() -> void:
	if audio_root != null:
		return
	ensure_buses()
	audio_root = Node.new()
	audio_root.name = "Audio"
	audio_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio_root)
	for sound_name: String in SOUNDS:
		var n: int = SOUNDS[sound_name].get("files", 1)
		var list := []
		for i in n:
			var p := SOUND_DIR + (sound_name if n == 1 else "%s_%d" % [sound_name, i + 1]) + ".wav"
			if ResourceLoader.exists(p):
				list.append(load(p))
		sound_streams[sound_name] = list
	for i in VOICES_HIGH:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		audio_root.add_child(p)
		voices.append(p)
		voice_sound.append("")
		voice_start.append(0)
		voice_end.append(0)
	start_music()


# The Music and Effects buses, under Master (made here, so there's no bus layout file).
func ensure_buses() -> void:
	for bus: String in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	apply_volumes()


func apply_volumes() -> void:
	for pair: Array in [["Music", music_volume], ["Effects", effects_volume]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(pair[1], 0.0001)))
			AudioServer.set_bus_mute(i, pair[1] <= 0.0)


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	apply_volumes()


func set_effects_volume(v: float) -> void:
	effects_volume = clampf(v, 0.0, 1.0)
	apply_volumes()


# Called by load_settings() / save_settings() (game_world.gd) with their ConfigFile.
func load_audio_settings(cfg: ConfigFile) -> void:
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	effects_volume = clampf(float(cfg.get_value("audio", "effects", effects_volume)), 0.0, 1.0)
	ensure_buses()


func save_audio_settings(cfg: ConfigFile) -> void:
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "effects", effects_volume)


# The 4 layers in one AudioStreamSynchronized, so they stay in step; each loops.
# Not without a sound device (headless tests): nothing plays there, and Godot would
# report the never-started layers as leaked at exit.
func start_music() -> void:
	if silent_device():
		return
	music_stream = AudioStreamSynchronized.new()
	music_stream.stream_count = MUSIC_LAYERS.size()
	for i in MUSIC_LAYERS.size():
		var p: String = MUSIC_DIR + "music_" + MUSIC_LAYERS[i] + ".wav"
		if not ResourceLoader.exists(p):
			music_stream = null
			return
		var s: AudioStream = load(p)
		if s is AudioStreamWAV and s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		music_stream.set_sync_stream(i, s)
		music_stream.set_sync_stream_volume(i, linear_to_db(maxf(music_mix[i], 0.0001)))
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.stream = music_stream
	audio_root.add_child(music_player)
	music_player.play()


# ---------------------------------------------------------------- playing

# Plays a sound from SOUNDS. pos: where on the map (pixels; Vector2.INF: not on
# the map, full volume). volume_db and pitch change it on top of its own.
func play_sound(sound_name: String, pos := Vector2.INF, volume_db := 0.0, pitch := 1.0) -> void:
	var s: Dictionary = SOUNDS.get(sound_name, {})
	if s.is_empty():
		return
	setup_audio()
	sound_asked[sound_name] = sound_asked.get(sound_name, 0) + 1
	var now := Time.get_ticks_msec()
	var important: bool = s.get("important", false)
	if now - int(sound_last.get(sound_name, -100000)) < float(s.get("gap", 0.0)) * 1000.0:
		return
	var streams: Array = sound_streams.get(sound_name, [])
	if streams.is_empty():
		return
	# Free player, copies of this sound playing, and the oldest unimportant one (to
	# take if needed). The last VOICES_KEPT players are only for important sounds.
	var count := VOICES_HIGH if get("graphics_high") != false else VOICES_LOW
	var usable := count if important else count - VOICES_KEPT
	var mine := sound_priority(sound_name)
	var free := -1
	var same := 0
	var oldest := -1
	for i in count:
		if voice_busy(i, now):
			if voice_sound[i] == sound_name:
				same += 1
			elif sound_priority(voice_sound[i]) < mine and (oldest < 0 or voice_start[i] < voice_start[oldest]):
				oldest = i
		elif free < 0 and i < usable:
			free = i
	if same >= int(s.get("max", 1)):
		return
	if free < 0:
		if oldest < 0:
			return
		free = oldest
		voices[free].stop()
	var p := voices[free]
	p.stream = streams[randi() % streams.size()]
	p.volume_db = float(s.get("db", 0.0)) + volume_db + same * SAME_SOUND_DB + screen_db(pos)
	var vary: float = s.get("pitch", 0.0)
	p.pitch_scale = pitch * (1.0 + randf_range(-vary, vary))
	# Without a sound device (headless) nothing plays: the player only counts as
	# busy for the sound's length, so the limits work the same, and no sound is
	# left "playing" at exit (Godot would report it as leaked)
	if not silent_device():
		p.play()
	voice_sound[free] = sound_name
	voice_start[free] = now
	voice_end[free] = now + int(p.stream.get_length() / p.pitch_scale * 1000.0)
	sound_last[sound_name] = now
	sound_played[sound_name] = sound_played.get(sound_name, 0) + 1
	sound_most[sound_name] = maxi(sound_most.get(sound_name, 0), same + 1)
	music_duck = maxf(music_duck, float(s.get("duck", 0.0)))


# Quieter off the screen.
func screen_db(pos: Vector2) -> float:
	if not pos.is_finite() or camera == null:
		return 0.0
	return 0.0 if on_screen(pos) else OFF_SCREEN_DB


func on_screen(pos: Vector2) -> bool:
	if camera == null or not camera.is_inside_tree():
		return true
	var p3 := to3d(pos)
	if camera.is_position_behind(p3):
		return false
	return get_viewport().get_visible_rect().grow(60.0).has_point(camera.unproject_position(p3))


# When every player is busy, a sound takes the one that has played a lower one
# the longest: 0 tower shots and hits, 1 the rest, 2 important.
func sound_priority(sound_name: String) -> int:
	var s: Dictionary = SOUNDS[sound_name]
	if s.get("important", false):
		return 2
	return 0 if s.get("frequent", false) else 1


# A player is busy while it plays, and until its sound's length has passed.
func voice_busy(i: int, now: int) -> bool:
	return voices[i].playing or now < voice_end[i]


# How many effect players are busy now (for tests).
func voices_busy() -> int:
	var now := Time.get_ticks_msec()
	var n := 0
	for i in voices.size():
		if voice_busy(i, now):
			n += 1
	return n


# Headless runs have Godot's dummy audio device: it plays nothing.
func silent_device() -> bool:
	return AudioServer.get_driver_name() == "Dummy"


# ---------------------------------------------------------------- helpers for the hooks

# A tower shoots (launch_shot(); the Spark tower's bolt is sound_bolt()).
func sound_shot(type: String, pos: Vector2) -> void:
	match type:
		"arrow": play_sound("arrow_fire", pos)
		"cannon": play_sound("cannon_fire", pos)
		"frost": play_sound("frost_fire", pos)
		"poison": play_sound("poison_spit", pos)


func sound_bolt(points: PackedVector3Array) -> void:
	if not points.is_empty():
		play_sound("spark_zap", Vector2(points[0].x, points[0].z) * CELL)


# A shot lands (shot_spark(); the cannon's blast is add_boom()).
func sound_hit(s: Shot) -> void:
	match s.type:
		"arrow": play_sound("arrow_hit", s.target_pos)
		"frost": play_sound("frost_hit", s.target_pos)
		"poison": play_sound("poison_cloud", s.target_pos)


# A monster dies (drop_corpse(), on every computer and in the replay).
func sound_death(e: Enemy) -> void:
	if e.special == "conductor":
		play_sound("grim_fall", e.pos)
	elif e.kind == "boss":
		play_sound("boss_death", e.pos)
	elif e.special == "split":
		play_sound("split", e.pos)
	else:
		play_sound("death", e.pos)


# Buttons: button() (game_ui.gd) tells where it drew one, ui_click() plays the
# click when the mouse is pressed on one drawn in the last few frames.
func note_button(r: Rect2, enabled: bool) -> void:
	if ui_buttons.size() > 300:
		ui_buttons.clear()
	ui_buttons[r] = [enabled, Engine.get_process_frames()]


# Grimwhistle's Crescendo: on the host, on the players (net_show_crescendo) and
# in the replay.
func crescendo_fx(e: Enemy) -> void:
	play_sound("crescendo", e.pos)
	super(e)


func ui_click(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var a := ui_mouse(true)
	var b := ui_mouse(false)
	var frame := Engine.get_process_frames()
	for r: Rect2 in ui_buttons:
		var d: Array = ui_buttons[r]
		if frame - int(d[1]) <= 3 and (r.has_point(a) or r.has_point(b)):
			play_sound("click" if d[0] else "denied")
			return


# ---------------------------------------------------------------- every frame

# Called by update_visuals() (game_world.gd) every frame, also while paused.
func update_audio(_delta: float) -> void:
	setup_audio()
	var dt := get_process_delta_time()  # real time, also when the game is paused
	update_music(dt)
	if get("replay_on") == true:
		watch_shields()
		return
	watch_game()
	watch_towers()
	watch_shields()
	watch_healers(dt)
	watch_story()
	watch_festival()


func music_mood(dt: float) -> String:
	if state != "playing" or wave == 0:
		calm_wait = 0.0
		return "calm"
	for e in enemies:
		if e.kind == "boss" and not e.dead:
			calm_wait = CALM_AFTER
			return "boss"
	if not enemies.is_empty() or monsters_left_to_spawn() > 0:
		calm_wait = CALM_AFTER
		return "wave"
	calm_wait -= dt
	return "wave" if calm_wait > 0.0 else "calm"


func update_music(dt: float) -> void:
	if music_stream == null:
		return
	var mood := music_mood(dt)
	var want: Array = MUSIC_MOODS[mood]
	var step := dt / float(MUSIC_FADE[mood])
	music_duck = move_toward(music_duck, 0.0, dt * 4.0)
	var extra := -music_duck
	if get("replay_on") == true:
		extra += REPLAY_MUSIC_DB
	elif menu_open and net_mode == "":
		extra += PAUSED_MUSIC_DB
	for i in MUSIC_LAYERS.size():
		music_mix[i] = move_toward(music_mix[i], want[i], step * 1.4)
		music_stream.set_sync_stream_volume(i, linear_to_db(maxf(music_mix[i], 0.0001)) + extra)


# Waves and the end, the same on every computer: the wave number going up by
# one (not jumps, like loading or joining), and the game ending.
func watch_game() -> void:
	if heard_wave >= 0 and wave == heard_wave + 1 and state == "playing" and not held:
		if grimwhistle_wave(wave):
			play_sound("grim_entrance")
		else:
			play_sound("boss_wave" if kind_for_wave(wave) == "boss" else "wave_start")
	heard_wave = wave
	if heard_state == "playing" and wave > 0 and (state == "won" or state == "lost"):
		play_sound("win" if state == "won" else "lose")
	heard_state = state


# Building, upgrading and selling, by anyone (the others' quieter). More than 3
# changes at once is a new game, a loaded save or joining: no sounds then.
func watch_towers() -> void:
	var now := {}
	var changes := []
	for c: Vector2i in towers:
		var t: Tower = towers[c]
		now[c] = [t.level, t.owner]
		var was: Variant = heard_towers.get(c)
		if was == null:
			changes.append(["build", t.pos, t.owner])
		elif int(was[0]) < t.level:
			changes.append(["upgrade", t.pos, t.owner])
	if heard_towers.size() + changes.size() > now.size():
		for c: Vector2i in heard_towers:
			if not towers.has(c):
				changes.append(["sell", cell_center(c), heard_towers[c][1]])
	heard_towers = now
	if changes.size() > 3:
		return
	for ch: Array in changes:
		play_sound(ch[0], ch[1], 0.0 if ch[2] == local_slot else OTHERS_DB)


# A shield going down. The host sees its value, the others and the replay a
# flag (shield 1 or 0): both go from above 0 to 0.
func watch_shields() -> void:
	if heard_shields.is_empty():
		var any := false
		for e in enemies:
			if e.max_shield > 0.0:
				any = true
				break
		if not any:
			return
	var up := {}
	for e in enemies:
		if e.max_shield <= 0.0 or e.dead:
			continue
		if e.shield > 0.0:
			up[e] = true
		elif heard_shields.has(e):
			if e.kind == "boss":
				play_sound("shield_break", e.pos, 5.0, 0.8)
			else:
				play_sound("shield_break", e.pos)
	heard_shields = up


# Healers chime about when they heal (every HEAL_EVERY game seconds; only the
# host knows the exact moment, so every computer keeps its own clock). Only on screen.
func watch_healers(dt: float) -> void:
	if state != "playing" or held or (menu_open and net_mode == ""):
		return
	var next := {}
	for e in enemies:
		if e.special != "heal" or e.dead:
			continue
		var left: float = heal_clock.get(e, randf() * HEAL_EVERY) - dt * game_speed
		if left <= 0.0:
			left += HEAL_EVERY
			if on_screen(e.pos):
				play_sound("heal", e.pos)
		next[e] = left
	heal_clock = next


# A page turn when a new story card shows (not Grimwhistle's: his entrance plays).
func watch_story() -> void:
	var tip := current_tip()
	var id: String = tip.get("id", "") if tip.get("story", false) else ""
	if id != "" and id != heard_story and id != "grimwhistle":
		play_sound("story_page")
	heard_story = id


# The festival's jingle once when a new game starts (wave 0, like the ui's banner).
func watch_festival() -> void:
	var fresh: bool = state == "playing" and wave == 0 and get("editing") != true
	if fresh and not heard_fresh and festivals_on:
		var f := festival_today()
		if f != "":
			play_sound("festival_" + f)
	heard_fresh = fresh
