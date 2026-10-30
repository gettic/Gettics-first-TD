extends Node2D
## Spiral TD - a small tower defense game.
## Enemies walk a spiral path toward the portal in the middle.
## Everything is drawn with simple shapes in _draw(), so there are no assets.

const CELL := 40
const COLS := 24
const ROWS := 18
const MAP_W := COLS * CELL
const MAP_H := ROWS * CELL
const MAX_WAVE := 30
const START_GOLD := 150
const START_LIVES := 20

# Corners of the path in grid coordinates. The first point is off-screen (spawn),
# the last point is the portal.
const WAYPOINTS := [
	Vector2i(-1, 1), Vector2i(22, 1), Vector2i(22, 16), Vector2i(1, 16),
	Vector2i(1, 4), Vector2i(19, 4), Vector2i(19, 13), Vector2i(4, 13),
	Vector2i(4, 7), Vector2i(16, 7), Vector2i(16, 10), Vector2i(8, 10),
]

# Tower stats per level (index 0 = level 1). "cost"[0] is the build price,
# the rest are upgrade prices.
const TOWER_TYPES := ["arrow", "cannon", "frost", "spark"]
const TOWERS := {
	"arrow": {
		"name": "Arrow", "color": Color(0.35, 0.85, 0.35),
		"desc": "Fast single-target shots",
		"cost": [50, 60, 130, 260],
		"damage": [10, 22, 48, 110],
		"range": [120.0, 130.0, 145.0, 165.0],
		"cooldown": [0.5, 0.45, 0.4, 0.32],
	},
	"cannon": {
		"name": "Cannon", "color": Color(1.0, 0.6, 0.2),
		"desc": "Slow shots, splash damage",
		"cost": [80, 90, 180, 360],
		"damage": [20, 45, 95, 210],
		"range": [110.0, 115.0, 125.0, 135.0],
		"cooldown": [1.4, 1.3, 1.2, 1.1],
		"splash": [55.0, 60.0, 70.0, 80.0],
	},
	"frost": {
		"name": "Frost", "color": Color(0.4, 0.85, 1.0),
		"desc": "Slows enemies down",
		"cost": [70, 70, 140, 280],
		"damage": [4, 8, 16, 32],
		"range": [110.0, 120.0, 130.0, 140.0],
		"cooldown": [0.9, 0.8, 0.7, 0.6],
		"slow": [0.6, 0.5, 0.4, 0.3],
	},
	"spark": {
		"name": "Spark", "color": Color(0.75, 0.5, 1.0),
		"desc": "Lightning that chains",
		"cost": [120, 120, 240, 480],
		"damage": [30, 60, 120, 250],
		"range": [140.0, 150.0, 165.0, 185.0],
		"cooldown": [1.2, 1.1, 1.0, 0.9],
		"chain": [3, 4, 5, 6],
	},
}

# Panel layout
const PANEL_X := MAP_W + 16
const UPGRADE_RECT := Rect2(PANEL_X, 480, 140, 40)
const SELL_RECT := Rect2(PANEL_X + 148, 480, 140, 40)
const WAVE_RECT := Rect2(PANEL_X, 610, 200, 44)
const SPEED_RECT := Rect2(PANEL_X + 208, 610, 80, 44)


class Enemy:
	var pos: Vector2
	var wp := 1
	var hp := 1.0
	var max_hp := 1.0
	var speed := 55.0
	var armor := 0.0
	var bounty := 1
	var leak := 1
	var radius := 10.0
	var color := Color.WHITE
	var slow_factor := 1.0
	var slow_time := 0.0
	var traveled := 0.0
	var dead := false


class Tower:
	var type: String
	var cell: Vector2i
	var pos: Vector2
	var level := 0
	var cooldown := 0.0
	var spent := 0
	var aim := Vector2.RIGHT


class Shot:
	var pos: Vector2
	var target: Enemy
	var target_pos: Vector2
	var type: String
	var level := 0
	var speed := 420.0
	var done := false


var path_cells := {}
var path_points: Array[Vector2] = []
var enemies: Array[Enemy] = []
var towers := {}  # Vector2i -> Tower
var shots: Array[Shot] = []
var effects := []  # Dictionaries: bolts and explosions

var gold := 0
var lives := 0
var wave := 0
var wave_running := false
var spawn_queue: Array[String] = []
var spawn_timer := 0.0
var spawn_hp := 0.0
var build_type := ""
var selected: Tower = null
var game_speed := 1
var state := "playing"  # "playing", "won" or "lost"
var message := ""
var message_time := 0.0
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	for i in range(WAYPOINTS.size() - 1):
		var a: Vector2i = WAYPOINTS[i]
		var b: Vector2i = WAYPOINTS[i + 1]
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var c := a
		while true:
			if c.x >= 0:
				path_cells[c] = true
			if c == b:
				break
			c += step
	for w in WAYPOINTS:
		path_points.append(cell_center(w))
	new_game()


func new_game() -> void:
	enemies.clear()
	towers.clear()
	shots.clear()
	effects.clear()
	spawn_queue.clear()
	gold = START_GOLD
	lives = START_LIVES
	wave = 0
	wave_running = false
	build_type = ""
	selected = null
	game_speed = 1
	state = "playing"
	flash("Build towers, then press SPACE")


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)


func mouse_cell() -> Vector2i:
	var p := get_global_mouse_position()
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func can_build(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS \
		and not path_cells.has(c) and not towers.has(c)


func flash(text: String) -> void:
	message = text
	message_time = 3.0


func tower_button_rect(i: int) -> Rect2:
	return Rect2(PANEL_X, 150 + i * 64, 288, 56)


# ---------------------------------------------------------------- waves

func kind_for_wave(w: int) -> String:
	if w % 10 == 0:
		return "boss"
	if w % 5 == 0:
		return "fast"
	if w % 3 == 0:
		return "armored"
	return "normal"


func start_wave() -> void:
	if wave_running or state != "playing":
		return
	wave += 1
	wave_running = true
	spawn_hp = 25.0 * pow(1.17, wave - 1)
	var kind := kind_for_wave(wave)
	var count := 8 + wave
	if kind == "boss":
		count = 1 + int(wave / 10.0)
	for i in count:
		spawn_queue.append(kind)
	spawn_timer = 0.0


func spawn_enemy(kind: String) -> void:
	var e := Enemy.new()
	e.pos = path_points[0]
	e.max_hp = spawn_hp
	e.bounty = 2 + int(wave / 4.0)
	e.color = Color(0.95, 0.5, 0.6)
	match kind:
		"fast":
			e.max_hp *= 0.6
			e.speed *= 1.7
			e.radius = 8.0
			e.color = Color(1.0, 0.9, 0.3)
		"armored":
			e.max_hp *= 1.3
			e.armor = 2.0 + wave * 0.6
			e.radius = 11.0
			e.color = Color(0.6, 0.65, 0.75)
		"boss":
			e.max_hp *= 15.0
			e.speed *= 0.7
			e.radius = 18.0
			e.bounty = 40 + wave * 4
			e.leak = 5
			e.color = Color(0.9, 0.15, 0.15)
	e.hp = e.max_hp
	enemies.append(e)


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	message_time = maxf(message_time - delta, 0.0)
	update_effects(delta)
	if state == "playing":
		var dt := delta * game_speed
		update_spawning(dt)
		update_enemies(dt)
		update_towers(dt)
		update_shots(dt)
		remove_dead()
		if lives <= 0:
			lives = 0
			state = "lost"
		elif wave_running and spawn_queue.is_empty() and enemies.is_empty():
			wave_running = false
			var bonus := 10 + wave * 2
			gold += bonus
			if wave >= MAX_WAVE:
				state = "won"
			else:
				flash("Wave %d cleared! +%d gold" % [wave, bonus])
	queue_redraw()


func update_spawning(dt: float) -> void:
	if spawn_queue.is_empty():
		return
	spawn_timer -= dt
	if spawn_timer <= 0.0:
		var kind: String = spawn_queue.pop_front()
		spawn_enemy(kind)
		match kind:
			"boss": spawn_timer = 2.0
			"fast": spawn_timer = 0.45
			_: spawn_timer = 0.7


func update_enemies(dt: float) -> void:
	for e in enemies:
		if e.slow_time > 0.0:
			e.slow_time -= dt
			if e.slow_time <= 0.0:
				e.slow_factor = 1.0
		var move := e.speed * e.slow_factor * dt
		while move > 0.0 and e.wp < path_points.size():
			var target := path_points[e.wp]
			var d := e.pos.distance_to(target)
			if d <= move:
				e.pos = target
				e.traveled += d
				move -= d
				e.wp += 1
			else:
				e.pos += (target - e.pos) / d * move
				e.traveled += move
				move = 0.0
		if e.wp >= path_points.size() and not e.dead:
			e.dead = true
			lives -= e.leak


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
			var s := Shot.new()
			s.pos = t.pos + t.aim * 14.0
			s.target = target
			s.target_pos = target.pos
			s.type = t.type
			s.level = t.level
			if t.type == "cannon":
				s.speed = 300.0
			shots.append(s)


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
	var points := PackedVector2Array([t.pos, first.pos])
	damage_enemy(first, dmg)
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
		points.append(next.pos)
		damage_enemy(next, dmg)
		current = next
	effects.append({"kind": "bolt", "points": points, "time": 0.15, "max": 0.15})


func update_shots(dt: float) -> void:
	for s in shots:
		if s.target != null and not s.target.dead:
			s.target_pos = s.target.pos
		var to := s.target_pos - s.pos
		var step := s.speed * dt
		if to.length() <= step:
			s.pos = s.target_pos
			shot_hit(s)
			s.done = true
		else:
			s.pos += to.normalized() * step
	for i in range(shots.size() - 1, -1, -1):
		if shots[i].done:
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
					damage_enemy(e, dmg)
			effects.append({"kind": "boom", "pos": s.pos, "radius": r, "time": 0.25, "max": 0.25})
		"frost":
			if alive:
				var slow: float = data["slow"][s.level]
				s.target.slow_factor = minf(s.target.slow_factor, slow)
				s.target.slow_time = 2.0
				damage_enemy(s.target, dmg)
		_:
			if alive:
				damage_enemy(s.target, dmg)


func damage_enemy(e: Enemy, amount: float) -> void:
	if e.dead:
		return
	# Armor removes a flat amount, but at least 25% of the hit always goes through.
	e.hp -= maxf(amount - e.armor, amount * 0.25)
	if e.hp <= 0.0:
		e.dead = true
		gold += e.bounty


func remove_dead() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].dead:
			enemies.remove_at(i)


func update_effects(delta: float) -> void:
	for fx in effects:
		fx["time"] -= delta
	effects = effects.filter(func(fx): return fx["time"] > 0.0)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			build_type = ""
			selected = null
		elif event.button_index == MOUSE_BUTTON_LEFT:
			on_click(get_global_mouse_position())
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				choose_build(TOWER_TYPES[event.keycode - KEY_1])
			KEY_SPACE:
				start_wave()
			KEY_U:
				upgrade_selected()
			KEY_S:
				sell_selected()
			KEY_F:
				toggle_speed()
			KEY_ESCAPE:
				build_type = ""
				selected = null
			KEY_R:
				if state != "playing":
					new_game()


func on_click(p: Vector2) -> void:
	if state != "playing":
		return
	if p.x >= MAP_W:
		for i in TOWER_TYPES.size():
			if tower_button_rect(i).has_point(p):
				choose_build(TOWER_TYPES[i])
		if selected != null and UPGRADE_RECT.has_point(p):
			upgrade_selected()
		if selected != null and SELL_RECT.has_point(p):
			sell_selected()
		if WAVE_RECT.has_point(p):
			start_wave()
		if SPEED_RECT.has_point(p):
			toggle_speed()
		return
	var c := mouse_cell()
	if towers.has(c):
		selected = towers[c]
		build_type = ""
	elif build_type != "":
		try_build(c)
	else:
		selected = null


func choose_build(type: String) -> void:
	build_type = type
	selected = null


func try_build(c: Vector2i) -> void:
	if not can_build(c):
		return
	var cost: int = TOWERS[build_type]["cost"][0]
	if gold < cost:
		flash("Not enough gold")
		return
	var t := Tower.new()
	t.type = build_type
	t.cell = c
	t.pos = cell_center(c)
	t.spent = cost
	gold -= cost
	towers[c] = t


func upgrade_selected() -> void:
	if selected == null:
		return
	if selected.level >= 3:
		flash("Already max level")
		return
	var cost: int = TOWERS[selected.type]["cost"][selected.level + 1]
	if gold < cost:
		flash("Not enough gold")
		return
	gold -= cost
	selected.spent += cost
	selected.level += 1


func sell_selected() -> void:
	if selected == null:
		return
	gold += int(selected.spent * 0.7)
	towers.erase(selected.cell)
	selected = null


func toggle_speed() -> void:
	game_speed = game_speed % 3 + 1


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_map()
	draw_towers()
	draw_enemies()
	for s in shots:
		draw_circle(s.pos, 5.0 if s.type == "cannon" else 3.5, TOWERS[s.type]["color"])
	draw_effects()
	draw_build_preview()
	draw_panel()
	if state != "playing":
		draw_end_screen()


func draw_map() -> void:
	for x in COLS:
		for y in ROWS:
			var c := Vector2i(x, y)
			var col: Color
			if path_cells.has(c):
				col = Color(0.42, 0.33, 0.22)
			elif (x + y) % 2 == 0:
				col = Color(0.13, 0.22, 0.13)
			else:
				col = Color(0.15, 0.25, 0.15)
			draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), col)
	# Portal at the end of the path
	var portal := path_points[path_points.size() - 1]
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
	draw_circle(portal, 17.0, Color(0.25, 0.05, 0.35))
	draw_arc(portal, 15.0 + pulse * 3.0, 0, TAU, 32, Color(0.8, 0.4, 1.0), 3.0)


func draw_towers() -> void:
	if selected != null:
		var rng: float = TOWERS[selected.type]["range"][selected.level]
		draw_circle(selected.pos, rng, Color(1, 1, 1, 0.08))
		draw_arc(selected.pos, rng, 0, TAU, 64, Color(1, 1, 1, 0.5), 1.5)
	for t: Tower in towers.values():
		var col: Color = TOWERS[t.type]["color"]
		var base := Rect2(t.pos - Vector2(16, 16), Vector2(32, 32))
		draw_rect(base, Color(0.2, 0.2, 0.24))
		if t == selected:
			draw_rect(base, Color.WHITE, false, 2.0)
		draw_line(t.pos, t.pos + t.aim * 15.0, col.darkened(0.3), 5.0)
		draw_circle(t.pos, 9.0 + t.level * 1.5, col)
		for i in t.level + 1:
			draw_circle(t.pos + Vector2(-9 + i * 6, 13), 2.0, Color(1, 0.9, 0.3))


func draw_enemies() -> void:
	for e in enemies:
		draw_circle(e.pos, e.radius, e.color)
		if e.armor > 0.0:
			draw_arc(e.pos, e.radius, 0, TAU, 24, Color(0.3, 0.3, 0.35), 2.0)
		if e.slow_time > 0.0:
			draw_arc(e.pos, e.radius + 2.0, 0, TAU, 24, Color(0.4, 0.85, 1.0), 2.0)
		var w := e.radius * 2.0 + 4.0
		var bar := Vector2(e.pos.x - w / 2.0, e.pos.y - e.radius - 8.0)
		draw_rect(Rect2(bar, Vector2(w, 4)), Color(0.3, 0, 0))
		draw_rect(Rect2(bar, Vector2(w * e.hp / e.max_hp, 4)), Color(0.2, 0.9, 0.2))


func draw_effects() -> void:
	for fx in effects:
		var a: float = fx["time"] / fx["max"]
		if fx["kind"] == "bolt":
			draw_polyline(fx["points"], Color(0.85, 0.7, 1.0, a), 3.0)
		else:
			draw_circle(fx["pos"], fx["radius"] * (1.2 - a * 0.4), Color(1.0, 0.55, 0.15, a * 0.45))


func draw_build_preview() -> void:
	if build_type == "" or get_global_mouse_position().x >= MAP_W:
		return
	var c := mouse_cell()
	var ok := can_build(c)
	var col := Color(0.3, 1, 0.3, 0.35) if ok else Color(1, 0.2, 0.2, 0.35)
	draw_rect(Rect2(c * CELL, Vector2(CELL, CELL)), col)
	var rng: float = TOWERS[build_type]["range"][0]
	draw_arc(cell_center(c), rng, 0, TAU, 64, Color(1, 1, 1, 0.4), 1.5)


func text(pos: Vector2, s: String, size := 16, col := Color.WHITE) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func button(r: Rect2, label: String, enabled := true, active := false) -> void:
	var bg := Color(0.22, 0.24, 0.3)
	if active:
		bg = Color(0.3, 0.4, 0.55)
	elif not enabled:
		bg = Color(0.15, 0.15, 0.18)
	draw_rect(r, bg)
	draw_rect(r, Color(0.45, 0.48, 0.55), false, 1.0)
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var col := Color.WHITE if enabled else Color(0.5, 0.5, 0.5)
	text(r.position + Vector2((r.size.x - size.x) / 2.0, r.size.y / 2.0 + 6.0), label, 16, col)


func draw_panel() -> void:
	draw_rect(Rect2(MAP_W, 0, 1280 - MAP_W, MAP_H), Color(0.09, 0.09, 0.12))
	text(Vector2(PANEL_X, 36), "WAVE %d / %d" % [wave, MAX_WAVE], 26)
	text(Vector2(PANEL_X, 70), "Lives: %d" % lives, 20, Color(1, 0.45, 0.45))
	text(Vector2(PANEL_X + 150, 70), "Gold: %d" % gold, 20, Color(1, 0.85, 0.3))
	if wave < MAX_WAVE:
		text(Vector2(PANEL_X, 104), "Next wave: %s" % kind_for_wave(wave + 1).capitalize(), 16, Color(0.75, 0.75, 0.8))
	text(Vector2(PANEL_X, 136), "Build (keys 1-4)", 14, Color(0.6, 0.6, 0.65))

	for i in TOWER_TYPES.size():
		var type: String = TOWER_TYPES[i]
		var data: Dictionary = TOWERS[type]
		var r := tower_button_rect(i)
		var affordable: bool = gold >= data["cost"][0]
		draw_rect(r, Color(0.3, 0.4, 0.55) if build_type == type else Color(0.17, 0.18, 0.23))
		draw_rect(r, Color(0.45, 0.48, 0.55), false, 1.0)
		draw_circle(r.position + Vector2(28, 28), 13.0, data["color"])
		var name_col := Color.WHITE if affordable else Color(0.55, 0.55, 0.55)
		text(r.position + Vector2(52, 24), "%d. %s" % [i + 1, data["name"]], 18, name_col)
		text(r.position + Vector2(220, 24), "%dg" % data["cost"][0], 18, Color(1, 0.85, 0.3) if affordable else Color(0.6, 0.4, 0.3))
		text(r.position + Vector2(52, 46), data["desc"], 14, Color(0.7, 0.7, 0.75))

	if selected != null:
		var data: Dictionary = TOWERS[selected.type]
		var lv := selected.level
		text(Vector2(PANEL_X, 418), "%s  -  Level %d" % [data["name"], lv + 1], 20, data["color"])
		text(Vector2(PANEL_X, 444), "Damage %d   Range %d   Speed %.2fs" % [data["damage"][lv], data["range"][lv], data["cooldown"][lv]], 14)
		if lv < 3:
			text(Vector2(PANEL_X, 466), "Next: Damage %d   Range %d" % [data["damage"][lv + 1], data["range"][lv + 1]], 14, Color(0.6, 0.9, 0.6))
			var cost: int = data["cost"][lv + 1]
			button(UPGRADE_RECT, "Upgrade %dg (U)" % cost, gold >= cost)
		else:
			button(UPGRADE_RECT, "Max level", false)
		button(SELL_RECT, "Sell %dg (S)" % int(selected.spent * 0.7))
	else:
		text(Vector2(PANEL_X, 430), "Click a tower to upgrade or sell it.", 14, Color(0.6, 0.6, 0.65))

	if message_time > 0.0:
		text(Vector2(PANEL_X, 590), message, 16, Color(1, 1, 0.6, minf(message_time, 1.0)))

	var wave_label := "Wave running..." if wave_running else "Next wave (SPACE)"
	button(WAVE_RECT, wave_label, not wave_running and state == "playing")
	button(SPEED_RECT, "x%d (F)" % game_speed, true, game_speed > 1)
	text(Vector2(PANEL_X, 690), "Right-click / Esc: cancel", 13, Color(0.55, 0.55, 0.6))


func draw_end_screen() -> void:
	draw_rect(Rect2(0, 0, MAP_W, MAP_H), Color(0, 0, 0, 0.6))
	var title := "VICTORY!" if state == "won" else "GAME OVER"
	var sub := "You survived all %d waves." % MAX_WAVE if state == "won" else "You reached wave %d." % wave
	var size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64)
	text(Vector2((MAP_W - size.x) / 2.0, 320), title, 64, Color(1, 0.85, 0.3) if state == "won" else Color(1, 0.35, 0.35))
	size = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	text(Vector2((MAP_W - size.x) / 2.0, 370), sub, 22)
	size = font.get_string_size("Press R to play again", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	text(Vector2((MAP_W - size.x) / 2.0, 410), "Press R to play again", 18, Color(0.8, 0.8, 0.8))
