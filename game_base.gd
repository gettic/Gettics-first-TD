extends Node3D
## Gettic's first TD - a small 3D tower defense game.
## Monsters come out of each player's gate and walk around a loop (see DEFAULT_MAP).
## Up to 4 players can play together over the network (see "multiplayer").
## The game logic runs on a flat map measured in pixels (CELL pixels per tile).
## to3d() turns those positions into the 3D world, where one tile is one unit.
## The bottom console, health bars and lightning are drawn in 2D on top (draw_hud).
##
## The code is split over files that extend each other, so the game is still one
## node with every function and variable on it (main.tscn uses main.gd):
## game_base.gd (constants, data, shared state and helpers) <- game_updates.gd
## (debug log, updates, unpacking) <- game_world.gd (3D world, models, effects)
## <- game_net.gd (multiplayer) <- game_ui.gd (2D overlay and menus) <-
## map_editor.gd (the map editor, saved maps) <- main.gd (waves, update loop,
## input, player actions). A file can only use what is in its own file or the
## ones before it.

const CELL := 40
const SCREEN_W := 1280
const SCREEN_H := 720  # the layout's size: screens taller than 16:9 add ui_extra
const CAMERA_SPEED := 12.0  # tiles per second
const CAMERA_LIMIT := Vector2(9.0, 7.0)  # how far the camera can move from its start
const CAMERA_H_OFFSET := 0.0  # the map uses the full width now
const CAMERA_V_OFFSET := -3.5  # shifts the view so the map sits above the bottom console
const ZOOM_MIN := 0.35  # closest zoom (fraction of the starting distance)
const ZOOM_MAX := 1.3   # furthest zoom
const ZOOM_STEP := 0.1  # how much one scroll-wheel notch zooms
const MAX_WAVE := 300
const MAX_LEVEL := 60  # endless in practice: level 30 already costs millions, level 60 about a trillion
const WIN_TEXT := "GZ you have no life, go touch grass"  # shown when all waves are beaten
const START_GOLD := 150
# Difficulty levels (picked in the Esc menu before wave 1; the host picks in multiplayer)
const DIFFICULTIES := ["Easy", "Normal", "Hard", "Insane"]
const DIFFICULTY_HP := [0.6, 1.0, 1.4, 2.0]  # monster health
const DIFFICULTY_GOLD := [1.5, 1.0, 1.0, 1.0]  # start gold
const MAX_ALIVE := 50  # per player: you lose when this many monsters are alive at once (a boss counts as 5)
const WAVE_INTERVAL := 25.0  # seconds between waves once the game has started
const GAME_SPEEDS := [1, 2, 3, 5]  # the speed button (F) goes through these
# Abilities: free, each player has their own cooldowns, counted in game time (so the
# speed button doesn't make them weaker). Ready from wave 1.
# Meteor (Z, then click): hits everything within "radius" for "damage" times a
# monster's health in this wave (and level), ignoring armor.
# Freeze all (C): every monster stands still for "time" seconds (bosses half).
const ABILITIES := {
	"meteor": {"name": "Meteor", "key": "Z", "cooldown": 60.0, "radius": 90.0, "damage": 8.0},
	"freeze": {"name": "Freeze all", "key": "C", "cooldown": 90.0, "time": 3.0},
}
const ABILITY_ORDER := ["meteor", "freeze"]  # the order of their buttons
# Endless mode: after beating wave MAX_WAVE the host can keep going (K). Monster
# health then grows ENDLESS_HP_GROWTH a wave, so a run ends somewhere around wave
# 550-650; ENDLESS_LAST_WAVE is only a safe upper end nobody reaches.
const ENDLESS_HP_GROWTH := 1.04
const ENDLESS_LAST_WAVE := 9999
const GOLD_CAP := 1000000000000000  # 1e15: the most gold one wave or one kill gives (keeps whole numbers safe)
const GOLD_MAX := 1000000000000000000  # 1e18: the most gold a player can have

# The map is data (see read_map()): one letter per tile, . grass, # path,
# 1-4 a player's gate (standing on a path tile), r rock, t tree, w water.
# The same text is a saved map and what the host sends to joining players.
# Monsters come out of their gate, walk its road to the loop and then around
# the loop clockwise, forever. This is the normal map ("Default"): a square
# loop with a gate just outside each corner (player 1 uses gate 1).
const DEFAULT_MAP := [
	".....................3..",
	".....................#..",
	"2#####################..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#..................#..",
	"..#####################4",
	"..#.....................",
	"..1.....................",
]
# The maps that come with the game (Default first), read-only and the same on
# every computer of the same version. Name -> rows of letters.
const BUILTIN_MAPS := {
	"Default": DEFAULT_MAP,
	# The long winding one: 8 switchbacks, 3 tiles of grass between the lanes
	"Serpent": [
		"....1.......2......3.......4...",
		".#############################.",
		".#...........................#.",
		".#...#####...#####...#####...#.",
		".#...#...#...#...#...#...#...#t",
		".#...#...#...#...#...#...#...#.",
		".#...#...#.r.#...#...#...#...#.",
		".#...#...#...#...#...#...#...#.",
		".#...#...#...#...#...#.t.#...#.",
		"t#...#...#...#...#...#...#...#.",
		".#...#.t.#...#...#...#...#...#t",
		".#...#...#...#...#...#...#...#.",
		".#...#...#...#.r.#...#...#...#.",
		".#...#...#...#...#...#...#...#.",
		".#...#...#...#...#...#...#...#.",
		"t#...#...#...#...#.r.#...#...#.",
		".#...#...#...#...#...#...#...#.",
		".#####...#####...#####...#####.",
		"...............................",
	],
	# Two long parallel lanes (out and back) with a lake-dotted strip between
	"Twin Lanes": [
		"...............3................",
		".t.............#................",
		"..t.......r....#.........t......",
		"...............#................",
		"...............#................",
		"...##########################...",
		"...#........................#...",
		"1###...wwwww........wwwww...#...",
		"...#...wwwww........wwwww...###2",
		"...#........................#...",
		"...##########################...",
		"................#...............",
		"................#...............",
		"......t.........#....r........t.",
		"................#............t..",
		"................4...............",
	],
	# Two rooms joined by a narrow waist where both lanes pass side by side
	"Hourglass": [
		".........r..............",
		"2######################3",
		"..#..................#..",
		"..#..r...........t...#..",
		"t.#..................#..",
		"..#..................#..",
		"..##########..########..",
		"...........#..#.........",
		"wwwwwwww...#..#.wwwwwwww",
		"wwwwwwww...#..#.wwwwwwww",
		"...........#..#.........",
		"..##########..########..",
		"..#..................#..",
		"..#..................#.t",
		"..#...t...........r..#..",
		"..#..................#..",
		"1######################4",
		"..............r.........",
	],
	# Long winding roads from the corners into a tiny loop around a lake
	"Four Roads": [
		".2......................3.",
		".#......t...............#.",
		".#..........t...........#.",
		".#......................#.",
		".#####.......r......#####.",
		".....#..............#.....",
		".....#..............#.....",
		".....#...########...#.r...",
		".....#####wwwwww#####.....",
		"...t.....#wwwwww#.........",
		".....#####wwwwww#####.t...",
		".....#...#wwwwww#...#.....",
		"...r.#...########...#.....",
		".....#..............#.....",
		".....#..............#.....",
		".#####......r.......#####.",
		".#......................#.",
		".#...........t..........#.",
		".#...............t......#.",
		".1......................4.",
	],
}
const MAP_MIN := Vector2i(12, 9)  # smallest map in tiles
const MAP_MAX := Vector2i(48, 36)  # biggest: monster positions are sent in 16 bits (up to 51 tiles)
const MAP_LETTERS := ".#1234rtw"
const MIN_LOOP := 8  # tiles
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const DEFAULT_SIZE := Vector2i(24, 18)  # the Default map's size in tiles
const MAPS_DIR := "user://maps"  # saved maps: <name>.txt, the map's rows of letters
const MAP_NAME_MAX := 24
const MAP_FILE_MAX := 4096  # bytes: a 48 x 36 map is under 1800
const MAX_PLAYERS := 4
# The colours a player can pick (index = colour number 0-7; the first 4 are each
# slot's colour when nobody picked one). Use color_of(slot) / color_name(slot)
# for a player's colour: see "player colours" below.
const PLAYER_NAMES := ["Blue", "Red", "Yellow", "Green", "Orange", "Cyan", "Pink", "Black"]
const PLAYER_COLORS := [Color(0.3, 0.55, 1.0), Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.25, 0.8, 0.45),
		Color(1.0, 0.55, 0.15), Color(0.2, 0.85, 0.9), Color(1.0, 0.42, 0.6), Color(0.14, 0.14, 0.16)]
const DARK_COLOR := 7  # Black: needs a light rim or ring to show
# A player who hasn't typed a name gets one of these (a new one each time the game starts)
const SILLY_NAMES := [
	"Sir Wobbles", "Captain Noodle", "Lady Pickles", "Baron Fluff", "Duke Waffle",
	"Mister Muffin", "Professor Puddle", "Count Crumpet", "Admiral Sprout", "Princess Pudding",
	"Tiny Thunder", "Sneaky Biscuit", "Grumpy Turnip", "Jolly Bean", "Dizzy Pancake",
	"Bumble Boots", "Wiggle Worm", "Snorty Pig", "Fuzzy Pebble", "Giggle Goose",
	"Noodle Knight", "Toast Wizard", "Pickle Pirate", "Muffin Mage", "Bubble Bard",
	"Captain Socks", "Sir Snorez", "Lord Doodle", "Queen Jellybean", "King Crouton",
	"Wobbly Walrus", "Sleepy Llama", "Dancing Duck", "Happy Hamster", "Cheeky Cheese",
	"Soggy Cereal", "Major Mallow", "Doctor Dumpling", "Banana Bandit", "Turbo Turtle",
	"Spaghetti Yeti", "Mighty Mitten", "Rusty Spoon", "Gnome Nibbles", "Puddle Jumper",
	"Sir Squeaks", "Fluffy Dragon", "Cosmic Cupcake", "Waddle Penguin", "Lumpy Potato",
]
const NAME_MAX := 16  # longest player name
const CHAT_MAX := 120  # longest chat message
const CHAT_LINES := 6  # chat lines shown at once
const CHAT_SHOW := 10.0  # seconds a chat line stays (the last one fading out)
const CHAT_BURST := 4.0  # chat messages a player may send at once...
const CHAT_REFILL := 1.5  # ...and then one per this many seconds
const ENEMY_KINDS := ["normal", "fast", "armored", "boss"]
const EARLY_VOTE := 0.75  # with more players, this share of them must agree to send a wave early

# Multiplayer: the host's game runs everything, the others send it their actions
const NET_PORT := 24750
const SEARCH_PORT := 24751  # the host listens here for players on its network looking for its code
const SNAPSHOT_RATE := 15.0  # monster updates per second sent to the other players
const CODE_LETTERS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # for invite codes (no I, L, O or U)
# The game server (a Cloudflare Worker) that lists public games and passes messages
# along, so no router ports are needed. Empty: only games on the local network.
# Start the game with "-- --relay=http://127.0.0.1:8787" to use a test server.
const RELAY_URL := "https://gtd-relay.gtd-relay.workers.dev"

# Tower stats for levels 1-4 (index 0 = level 1). "cost"[0] is the build price,
# the rest are upgrade prices. Levels go on after 4 (see make_towers()): the
# game uses TOWERS, which has every level up to MAX_LEVEL.
const TOWER_TYPES := ["arrow", "cannon", "frost", "spark", "poison", "barracks"]
# Which monster in range a tower shoots (T or the button in the tower panel picks it).
# The path loops forever, so "First" is the monster that has walked furthest: the
# oldest one, which has counted toward the limit the longest. New towers use First.
const TARGET_MODES := ["First", "Last", "Strongest", "Fastest", "Closest"]
const TARGET_TIPS := ["The monster that has walked furthest.", "The monster that has walked the least.",
		"The monster with the most health left.", "The fastest monster (slowed ones count as slow).",
		"The monster nearest to the tower."]
const TOWER_BASE := {
	"arrow": {
		"name": "Arrow", "color": Color(0.35, 0.85, 0.35),
		"desc": "Fast single-target shots",
		"cost": [50, 60, 130, 260],
		"damage": [11, 24, 52, 120],
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
		"damage": [12, 24, 48, 96],
		"range": [110.0, 120.0, 130.0, 140.0],
		"cooldown": [0.9, 0.8, 0.7, 0.6],
		"slow": [0.6, 0.5, 0.4, 0.3],
	},
	"spark": {
		"name": "Spark", "color": Color(0.75, 0.5, 1.0),
		"desc": "Lightning that chains",
		"cost": [120, 120, 240, 480],
		"damage": [24, 48, 96, 200],
		"range": [140.0, 150.0, 165.0, 185.0],
		"cooldown": [1.2, 1.1, 1.0, 0.9],
		"chain": [3, 4, 5, 6],
	},
	# Poison: a slow glob that lands where the monster is and leaves a cloud there.
	# "damage" is per second, to every monster in the cloud, and goes through armor.
	"poison": {
		"name": "Poison", "color": Color(0.45, 0.9, 0.25),
		"desc": "Clouds that hurt every monster inside",
		"cost": [90, 90, 180, 360],
		"damage": [13, 29, 60, 130],
		"range": [110.0, 120.0, 130.0, 140.0],
		"cooldown": [1.5, 1.4, 1.3, 1.2],
		"cloud": [40.0, 44.0, 50.0, 56.0],  # the cloud's radius
	},
	# Barracks: soldiers stand on the path tile nearest the tower (its rally point,
	# see rally_point()) and each holds one monster still for "hold" seconds,
	# hitting it ("damage" every "cooldown"). "range" only finds the rally point.
	# Monsters wear soldiers down (SOLDIER_HURT a second, so "soldier_hp" is in
	# seconds of a normal monster); a fallen soldier is back after "respawn" seconds.
	"barracks": {
		"name": "Barracks", "color": Color(0.75, 0.6, 0.4),
		"desc": "Soldiers hold monsters on the path",
		"cost": [90, 90, 180, 360],
		"damage": [8, 18, 38, 85],
		"range": [90.0, 95.0, 100.0, 105.0],
		"cooldown": [1.0, 0.95, 0.9, 0.85],
		"soldiers": [2, 2, 3, 3],
		"soldier_hp": [6.0, 7.0, 8.5, 10.0],
		"hold": [1.5, 1.75, 2.0, 2.25],
		"respawn": [8.0, 7.5, 7.0, 6.0],
	},
}
# Barracks soldiers: a free soldier grabs the monster nearest its rally point
# within ENGAGE_R (Militia: times its "reach") that nobody holds. A monster that
# was let go can't be held again for HOLD_IMMUNE seconds (it walks out of reach).
# Bosses are only held by Knights. Held monsters still count toward the limit.
const ENGAGE_R := 26.0
const HOLD_IMMUNE := 1.5
const SOLDIERS_MAX := 6  # without Militia's extra ones
# How fast each monster kind wears a soldier down (soldier health a second; splitlings half)
const SOLDIER_HURT := {"normal": 1.0, "fast": 0.6, "armored": 1.5, "boss": 4.0}
# Poison clouds last CLOUD_TIME seconds (Miasma longer) and hurt 4 times a second.
# A monster is hurt by only one cloud of each tower at a time (a tower's own
# clouds overlapping don't add up); different towers' clouds do add up.
const CLOUD_TIME := 3.0
const CLOUD_TICK := 0.25
const POISON_SHOT_SPEED := 300.0  # the glob flies like a cannon ball (set in main.gd's launch_shot())
# Levels after 4. Each one adds LEVEL_GAIN damage plus a bit more (0 to
# LEVEL_GAIN_SPREAD), different for every level and tower but the same in every
# game. Every 5th level (5, 10, 15...) is a big one. Upgrades cost LEVEL_COST
# times the last one (LEVEL_COST_BIG for the big levels), so damage per gold
# slowly drops and very high levels price themselves out.
const LEVEL_GAIN := 0.28  # +28% damage a level...
const LEVEL_GAIN_SPREAD := 0.08  # ...plus 0-8%
const LEVEL_GAIN_BIG := 0.62  # every 5th level: +62% (plus the spread)
const LEVEL_COST := 1.38
const LEVEL_COST_BIG := 1.8
const LEVEL_RANGE := 3.0  # range added a level, up to LEVEL_RANGE_MAX in all
const LEVEL_RANGE_MAX := 60.0
# Specializations: the upgrade to level 5 (index PATH_LEVEL) picks one of a
# tower's 2 paths, for good (selling is the only way back). From then on its
# numbers are the normal ones times the path's: "damage", "cooldown", "range",
# "splash", "cloud" (size) and "cloud_time" multiply, "chain_add" / "chain_set" change the chain. Lists of 3
# are the path's extra at levels 5, 20 and 40 (see path_step()).
const PATH_LEVEL := 4  # the first level index with a path (level 5)
const PATHS := {
	"arrow": [
		{"name": "Sniper", "desc": "Long range, huge hits", "damage": 1.6, "cooldown": 2.0, "range": 1.25, "shot_speed": 2.5, "mode": 2, "boss": 2.0},
		{"name": "Volley", "desc": "Shoots 3 monsters at once", "damage": 0.5, "arrows": [3, 4, 5]},
	],
	"cannon": [
		{"name": "Big Bomb", "desc": "Huge slow blasts", "damage": 2.0, "cooldown": 1.6, "splash": 1.3, "boss": 1.5},
		{"name": "Cluster", "desc": "Bomblets hit monsters nearby", "damage": 1.0, "bomblets": [3, 4, 5]},
	],
	"frost": [
		{"name": "Deep Freeze", "desc": "Chance to freeze monsters", "damage": 2.0, "freeze": [0.25, 0.32, 0.4]},
		{"name": "Blizzard", "desc": "Slows everything around the target", "damage": 0.35, "area": [60.0, 80.0, 100.0]},
	],
	"spark": [
		{"name": "Storm", "desc": "Longer chains that fade less", "damage": 0.9, "chain_add": 3, "falloff": 0.9, "jump": 150.0},
		{"name": "Overload", "desc": "One huge bolt, chains once", "damage": 2.0, "cooldown": 1.2, "chain_set": 2, "mode": 2, "boss": 2.0},
	],
	"poison": [
		{"name": "Venom", "desc": "Small deadly clouds, worse for bosses", "damage": 1.9, "cloud": 0.7, "mode": 2, "boss": 1.75},
		{"name": "Miasma", "desc": "Big lasting clouds: monsters inside take more damage", "damage": 1.0, "cloud": 1.5,
				"cloud_time": 1.5, "weaken": [0.15, 0.2, 0.25]},
	],
	# Barracks: "soldier_hp", "hold" and "respawn" multiply, "soldiers_add" adds
	# soldiers, "reach" multiplies ENGAGE_R, "boss_hold" lets it hold bosses (times the hold).
	"barracks": [
		{"name": "Knights", "desc": "Tough soldiers that also hold bosses", "damage": 1.6, "soldier_hp": 2.5, "hold": 1.5,
				"boss_hold": 1.0, "boss": 3.0},
		{"name": "Militia", "desc": "More soldiers, back faster", "damage": 0.6, "soldier_hp": 0.7, "respawn": 0.5,
				"soldiers_add": [2, 3, 4], "reach": 2.0},
	],
}
const BOMBLET_REACH := 130.0  # Cluster: bomblets land on monsters this close to the blast...
const BOMBLET_RADIUS := 45.0  # ...each a small blast this big
const FREEZE_TIME := 1.0  # Deep Freeze: seconds a frozen monster stands still (bosses half)
const FREEZE_IMMUNE := 2.0  # ...and then it can't be frozen again for this long
# Every tower level up to MAX_LEVEL, built from TOWER_BASE (same keys and shape).
# TOWERS[type]["paths"] has the same for each of its 2 paths.
var TOWERS := make_towers()

# Interface layout (screen pixels): a resource bar along the top and a console along the bottom
const TOP_BAR_H := 30
const BAR_TOP := 548  # top of the bottom console
const MINIMAP_RECT := Rect2(24, 566, 192, 144)  # 8 pixels per tile
const INFO_X := 236  # wave info, right of the minimap
const PORTRAIT_RECT := Rect2(474, 568, 120, 120)  # the selected tower's picture
const STATS_X := 612
const CARD_X := 972  # command card: 4 x 2 square buttons
const CARD_Y := 568
const CARD_SIZE := 64
const CARD_GAP := 8
const UPGRADE_RECT := Rect2(CARD_X, CARD_Y + CARD_SIZE + CARD_GAP, CARD_SIZE, CARD_SIZE)
const SELL_RECT := Rect2(CARD_X + (CARD_SIZE + CARD_GAP), CARD_Y + CARD_SIZE + CARD_GAP, CARD_SIZE, CARD_SIZE)
const WAVE_RECT := Rect2(CARD_X + (CARD_SIZE + CARD_GAP) * 2, CARD_Y + CARD_SIZE + CARD_GAP, CARD_SIZE, CARD_SIZE)
const SPEED_RECT := Rect2(CARD_X + (CARD_SIZE + CARD_GAP) * 3, CARD_Y + CARD_SIZE + CARD_GAP, CARD_SIZE, CARD_SIZE)
const MODE_RECT := Rect2(STATS_X + 196, BAR_TOP + 50, 140, 24)  # the selected tower's targeting mode
# Picking a path (a level 4 tower of yours selected): two wide buttons over the build row
const PATH_RECTS := [Rect2(CARD_X, CARD_Y, CARD_SIZE * 2 + CARD_GAP, CARD_SIZE),
		Rect2(CARD_X + (CARD_SIZE + CARD_GAP) * 2, CARD_Y, CARD_SIZE * 2 + CARD_GAP, CARD_SIZE)]
const UPDATE_RECT := Rect2(560, 3, 240, 24)  # in the top bar
const ARCH_R := 92.0  # the round arch over the portrait
const ARCH_DROP := 62.0  # how far below the console's top its center is
const MESSAGE_Y := BAR_TOP - 46  # flash messages, centered over the console
const END_Y := 290  # the win / lose title, centered over the map
# Where the map can't be clicked
const PANEL_RECTS := [Rect2(0, 0, SCREEN_W, TOP_BAR_H), Rect2(0, BAR_TOP, SCREEN_W, SCREEN_H - BAR_TOP),
		Rect2(474, BAR_TOP - 32, 120, 32)]

# Esc menu layout (screen pixels)
const MENU_RECT := Rect2(390, 40, 500, 660)  # taller since step 4: room for "Map:" under the title
const HOST_RECT := Rect2(430, 256, 420, 44)
const JOIN_INPUT_RECT := Rect2(430, 350, 290, 40)
const JOIN_BUTTON_RECT := Rect2(730, 350, 120, 40)
const COPY_RECT := Rect2(730, 242, 120, 40)
const NAME_INPUT_RECT := Rect2(530, 210, 320, 36)  # above the host button
const STOP_RECT := Rect2(430, 580, 420, 40)
const RESUME_RECT := Rect2(430, 640, 270, 44)  # the Leaderboard button is next to it
const PUBLIC_RECT := Rect2(430, 366, 420, 36)
const REFRESH_RECT := Rect2(750, 472, 100, 28)
const GRAPHICS_RECT := Rect2(756, 50, 124, 28)  # opens the Settings box
# The Settings box over the Esc menu: a row per setting, its button cycles the choices
const SETTINGS_BOX := Rect2(430, 110, 420, 494)
const SETTINGS_ROW_Y := 186  # the first row's button; the rest follow every 48
const SETTINGS_BUTTON_X := 640
const SETTINGS_BACK_RECT := Rect2(560, 542, 160, 40)
const GAME_ROWS := 3  # public games shown in the menu

# Update popup layout (screen pixels)
const DIALOG_RECT := Rect2(340, 140, 600, 440)
const DIALOG_YES_RECT := Rect2(380, 506, 250, 44)
const DIALOG_NO_RECT := Rect2(650, 506, 250, 44)
const CHOOSE_FOLDER_RECT := Rect2(370, 368, 250, 36)  # in the unpack warning

# Box asking whether another player may build in your area: in the console's middle,
# over the portrait and stats (screen pixels)
const ASK_RECT := Rect2(456, 556, 484, 156)
const ASK_YES_RECT := Rect2(480, 646, 212, 44)
const ASK_NO_RECT := Rect2(704, 646, 212, 44)

# Chat: the typing box sits just above the minimap, the lines above it
const CHAT_INPUT_RECT := Rect2(16, BAR_TOP - 44, 420, 28)

# Checked at startup to see if a newer release is on GitHub
const RELEASES_API := "https://api.github.com/repos/gettic/Gettics-first-TD/releases/latest"

# Where the downloaded .exe unpacks itself (see "unpacking")
const GAME_FOLDER := "Gettic's first TD"
const GAME_NAME := "Gettic's first TD"  # the files are named like "Gettic's first TD v1.16.exe"

# The debug build (made with /debuggame) is exported with this feature tag.
# It opens a log window, and never unpacks, renames or updates itself.
const DEBUG_FEATURE := "debug_game"


class Enemy:
	var id := 0  # the same on every player's computer
	var kind := "normal"
	var pos: Vector2
	var net_pos: Vector2  # other players: latest position from the host, pos glides toward it
	var route: Array[Vector2]  # this monster's gate, its road's corners, then the loop's corners from where it joins
	var wp := 1
	var loop_wp := 1  # where in route the loop starts again after its last point
	var hp := 1.0
	var max_hp := 1.0
	var speed := 55.0
	var armor := 0.0
	var bounty := 1
	var weight := 1  # how much this monster counts toward MAX_ALIVE
	var radius := 10.0
	var color := Color.WHITE
	var slow_factor := 1.0
	var slow_time := 0.0
	var freeze_time := 0.0  # Deep Freeze: stands still while above 0
	var freeze_immune := 0.0  # host: can't be frozen again while above 0
	var traveled := 0.0
	var dead := false
	var sent := false  # host: a snapshot has had it, so the players know it (see send_shot())
	var past := false  # other players: the host says it got past (once round the loop, see got_past())
	# Monster SPECIALS (see wave_special()): "" none, "split" (breaks in 2 when it
	# dies), "splitling" (one of those 2), "heal" (heals monsters near it),
	# "conductor" (Grimwhistle, a boss: see grimwhistle_wave())
	var special := ""
	var shield := 0.0  # host: takes hits before health and armor (0: none or broken)
	var max_shield := 0.0  # 0: this monster has no shield
	var shield_wait := 0.0  # host: seconds since it was last hit (the shield regrows after SHIELD_REGROW)
	var heal_timer := 0.0  # host: healers, seconds to the next heal
	var weak := 0.0  # host: Miasma, extra damage taken (0.2: +20%), set each poison tick
	var poisoned := 0.0  # host: seconds it still looks poisoned (for the looks)
	var held := false  # host: a Barracks soldier holds it (it stands still)
	var hold_immune := 0.0  # host: no soldier holds it while above 0
	var haste_time := 0.0  # host: Grimwhistle's Crescendo, walks CRESCENDO_HASTE times faster while above 0
	var node: MeshInstance3D
	var mat: Material
	var bob := 0.0


class Tower:
	var type: String
	var cell: Vector2i
	var pos: Vector2
	var owner := 0  # player slot (0-3) that built it and gets the gold for its kills
	var level := 0
	var cooldown := 0.0
	var spent := 0
	var aim := Vector2.UP
	var mode := 0  # which monster it shoots, an index in TARGET_MODES
	var path := 0  # its specialization from level 5: 0 none yet, 1 or 2 (see PATHS)
	var dealt := 0.0  # host: damage done, for the stats at the end
	var kills := 0
	# Barracks. Every computer: the rally point (map pixels, worked out by
	# rally_point(); x < 0: not yet) and soldier_look, a byte per soldier (see
	# soldier_bytes()). Host: per soldier its health (0: fallen), seconds until it's
	# back, seconds to its next hit and of its hold left, and the monster it holds (or null).
	var rally := Vector2(-1, -1)
	var soldier_look := PackedByteArray()
	var soldier_hp := PackedFloat32Array()
	var soldier_wait := PackedFloat32Array()
	var soldier_cd := PackedFloat32Array()
	var soldier_left := PackedFloat32Array()
	var soldier_hold: Array = []
	var node: Node3D
	var head: Node3D


class Shot:
	var pos: Vector2
	var target: Enemy
	var target_pos: Vector2
	var type: String
	var level := 0
	var path := 0
	var owner := 0
	var tower: Tower  # host: the tower that fired it, for the stats at the end
	var visual := false  # other players' copy of a host's shot: just for show, does no damage
	var speed := 420.0
	var done := false
	var node: MeshInstance3D


class Player:
	var peer := 1  # network id; the host is always 1
	var slot := 0  # 0-3: which gate and color
	var gold := 0
	var name := ""  # chosen by the player, checked by the host ("": not known yet)
	var cooldowns := {}  # ability (see ABILITIES) -> game seconds until it's ready again (missing: ready)
	var pick := -1  # host: the colour (0-7) this player asked for, -1: none (see settle_colors())
	var joined := 0  # host: join order (an earlier player keeps their colour in a clash)
	var color_set := false  # host: already had a colour, which they keep while their pick is taken


# The map being played (set by use_map())
var map_name := "Default"
var map_rows_text: Array = DEFAULT_MAP  # the map's letters, as read_map() got them
var map_cols := DEFAULT_SIZE.x  # size in tiles
var map_rows := DEFAULT_SIZE.y
var path_cells := {}  # Vector2i -> true: the loop and the gates' roads (gate tiles too)
var gate_cells: Array = []  # per player slot: the gate's Vector2i, or null if the map has fewer gates
var routes: Array = []  # per gate: Array[Vector2] of points (pixels), gate first; [] if no gate
var loop_starts: Array = []  # per gate: the index in its route where the loop begins
var blocked := {}  # Vector2i -> "r", "t" or "w" (rock, tree, water): nothing can be built there
var area_of := {}  # Vector2i -> the player slot whose area the tile is in
var enemies: Array[Enemy] = []
var enemy_by_id := {}
var next_enemy_id := 1
var towers := {}  # Vector2i -> Tower
var shots: Array[Shot] = []
var effects := []  # Dictionaries: bolts and explosions
# Host: poison clouds, {pos (Vector2), r, time (seconds left), dps, owner (slot),
# cell (the tower's Vector2i), boss (damage factor on bosses), weak (Miasma)}
var clouds: Array = []
var cloud_tick := 0.0  # host: seconds to the next poison tick
var new_enemies: Array[Enemy] = []  # host: splitlings born this frame, added in remove_dead()

var players: Array = [null, null, null, null]  # Player per slot, null = free
var local_slot := 0  # this computer's player
# Each slot's colour number (index in PLAYER_COLORS), also for empty slots; never
# two the same. Set by settle_colors() (host / alone) or the host's messages.
var slot_colors: Array = [0, 1, 2, 3]
# This computer's gold
var gold: int:
	get:
		return players[local_slot].gold if players[local_slot] != null else 0
	set(value):
		if players[local_slot] != null:
			players[local_slot].gold = value
var next_wave_timer := 0.0
var wave_votes: Array = []  # player slots that want the next wave early (see EARLY_VOTE)
var wave := 0
var difficulty := 1  # index in DIFFICULTIES
var spawn_queues: Array = [[], [], [], []]  # monster kinds still to come out of each gate
var spawn_timers := [0.0, 0.0, 0.0, 0.0]
var spawn_hp := 0.0
var requests := {}  # host: id -> {from, to, cell, type, time}, a player asking to build in another's area
var next_request_id := 1
var asks: Array = []  # [id, from slot, tower type, cell]: other players asking to build in our area
var net_spawn_left := 0  # other players: monsters still to spawn, from the host
var build_type := ""
var selected: Tower = null
var game_speed := 1
var state := "playing"  # "playing", "won" or "lost"
var endless := false  # kept going after beating wave MAX_WAVE (see last_wave())
var aiming := ""  # the ability being aimed with the mouse ("meteor"), "" if none
var menu_open := false  # the Esc menu; it only pauses the game when playing alone

# Multiplayer
var net_mode := ""  # "" alone, "host", "searching", "connecting" or "client"
var net_addresses: Array = []  # client: the host's addresses, tried in order
var net_connect_time := 0.0
var net_status := ""  # shown in the menu
var invite_code := ""  # host: 5 letters and digits, from the game server or make_code()
var search_peer: PacketPeerUDP  # host: answers searches; player: sends them
var search_time := 0.0
var search_send_timer := 0.0
var search_code := ""
var search_found: Array = []  # addresses of hosts that answered
var snapshot_timer := 0.0
var relay_url := RELAY_URL
var public_game := false  # host: shown in everyone's list of public games
var game_info_timer := 0.0
var public_games: Array = []  # [{code, players, wave}] from the game server
var games_status := "Looking for public games..."
var games_http: HTTPRequest
var games_timer := 0.0
var code_input: LineEdit
var name_input: LineEdit  # in the Esc menu: this player's name ("": a silly one)
var random_name := ""  # picked from SILLY_NAMES at startup, for when name_input is empty
var chat_input: LineEdit  # shown while typing a chat message
var chat_log: Array = []  # [slot (-1: the game), name, text, time it came]
var chat_budget := [CHAT_BURST, CHAT_BURST, CHAT_BURST, CHAT_BURST]  # host: messages each player may still send
var chat_budget_time := [0.0, 0.0, 0.0, 0.0]
var bbcode_tag := RegEx.create_from_string("\\[/?[A-Za-z_]+[^\\]]*\\]")
var message := ""
var message_time := 0.0
var font: Font
var time := 0.0
var version := ""
var update_version := ""  # set when GitHub has a newer release
var update_url := ""  # release page
var update_zip_url := ""  # the Windows .zip in the release (how versions before 1.15 update)
var update_exe_url := ""  # the packed .exe in the release
var update_pck_url := ""  # just the game, if the release has one for our engine version
var update_notes := ""  # "What's new" from the release notes
var update_dialog := ""  # "", "ask", "downloading" or "failed"
var update_error := ""
var update_http: HTTPRequest
var unpack_chosen := ""  # a folder the player picked to unpack to, instead of next to the download
var folder_picker: FileDialog

# 3D scene pieces
var camera: Camera3D
var camera_home: Vector3
var camera_focus: Vector3       # the ground point the camera looks at when not moved
var camera_pan := Vector2.ZERO  # how far WASD has moved the camera
var zoom := 1.0
var target_zoom := 1.0
var hud: Node2D
var gate_parts: Array = []  # per gate: the portal pieces that only show while a player uses that gate
var area_planes: Array = []  # per player slot: covers that player's area while building
var range_disc: MeshInstance3D
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var stone_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D
var gold_mat: StandardMaterial3D
var pip_mesh: SphereMesh
var boom_mesh: SphereMesh
var shot_mats := {}


# ---------------------------------------------------------------- shared helpers

# Removes all towers, monsters and effects.
func clear_world() -> void:
	for e in enemies:
		e.node.queue_free()
	for t: Tower in towers.values():
		t.node.queue_free()
	for s in shots:
		s.node.queue_free()
	for fx in effects:
		if fx.has("node"):
			fx["node"].queue_free()
	enemies.clear()
	enemy_by_id.clear()
	wave_votes.clear()
	requests.clear()
	asks.clear()
	towers.clear()
	shots.clear()
	effects.clear()
	clouds.clear()
	cloud_tick = 0.0
	for e in new_enemies:
		e.node.queue_free()
	new_enemies.clear()
	for q in spawn_queues:
		q.clear()
	build_type = ""
	selected = null


# A player's name, or their color while the name isn't known.
func name_of(slot: int) -> String:
	if slot >= 0 and slot < MAX_PLAYERS and players[slot] != null and players[slot].name != "":
		return players[slot].name
	return color_name(slot)


# ----- player colours
# Every player picks one of PLAYER_COLORS in their profile (profile.color, -1:
# none = their slot's colour). The host (or a player alone) decides who gets
# which (settle_colors() in game_net.gd) and sends slot_colors to the others.
# For graphics and ui: color_of(), color_name(), color_is_dark(), and the hook
# colors_changed().

# The colour number (0-7) of player slot 0-3.
func color_index(slot: int) -> int:
	return slot_colors[clampi(slot, 0, MAX_PLAYERS - 1)]


# The colour of player slot 0-3.
func color_of(slot: int) -> Color:
	return PLAYER_COLORS[color_index(slot)]


# Its name: "Blue" ... "Black".
func color_name(slot: int) -> String:
	return PLAYER_NAMES[color_index(slot)]


# Black: needs a light rim or ring to show on dark things.
func color_is_dark(slot: int) -> bool:
	return color_index(slot) == DARK_COLOR


# This computer's pick from the profile: 0-7, or -1 (none: the slot's colour).
func my_color() -> int:
	var c: Variant = profile.get("color", -1)
	return c if c is int and c >= -1 and c < PLAYER_COLORS.size() else -1


# The slot of another player (or a saved player still to come back to a loaded
# game) who has colour i, -1 if nobody does. me: the slot asking.
func color_holder(i: int, me := -1) -> int:
	if me < 0:
		me = local_slot
	for s in MAX_PLAYERS:
		if s != me and slot_colors[s] == i and (players[s] != null or saved_slots.has(s)):
			return s
	return -1


func color_locked(i: int) -> bool:
	return color_holder(i) >= 0


# Called on every computer after slot_colors changed. game_world.gd / game_ui.gd
# override it (calling super()) to recolour what was built with the old colours.
func colors_changed() -> void:
	pass


# Makes text from another player safe to show: no control or invisible
# characters, no [tags], no runs of spaces, and at most `most` characters.
func clean_text(s: String, most: int) -> String:
	var out := ""
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 32 or (c >= 127 and c < 160):
			out += " "
		elif not ((c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F) or c == 0xFEFF):
			out += ch
	out = bbcode_tag.sub(out, "", true)
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges().left(most).strip_edges()


func player_count() -> int:
	return MAX_PLAYERS - players.count(null)


# The loss limit grows with the number of players, like the waves do.
func max_alive() -> int:
	return MAX_ALIVE * player_count()


func monsters_left_to_spawn() -> int:
	if net_mode == "client":
		return net_spawn_left
	var n := 0
	for q in spawn_queues:
		n += q.size()
	return n


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)


func to3d(p: Vector2, height := 0.0) -> Vector3:
	return Vector3(p.x / CELL, height, p.y / CELL)


func mouse_over_panel() -> bool:
	return over_panel(ui_mouse())


# Screens taller than 16:9 (like 16:10) show more map: the layout is 1280 x (720 +
# ui_extra), with the console ui_extra lower and popups ui_extra / 2 lower.
var ui_extra := 0.0


# A screen point in the 1280x720 layout's pixels (the UI's rects). popup: for the
# centered popups and menus; otherwise for the top bar and the console.
func ui_point(p: Vector2, popup := false) -> Vector2:
	if popup:
		return p - Vector2(0, ui_extra / 2.0)
	var split := BAR_TOP - 60.0
	if p.y < split:
		return p
	# The extra map between: just above the console
	return Vector2(p.x, maxf(p.y - ui_extra, split - 1.0))


func ui_mouse(popup := false) -> Vector2:
	return ui_point(get_viewport().get_mouse_position(), popup)


func over_panel(p: Vector2) -> bool:
	for r: Rect2 in PANEL_RECTS:
		if r.has_point(p):
			return true
	return false


# Finds the map tile under the mouse by shooting a ray from the camera to the ground.
func mouse_cell() -> Vector2i:
	return screen_to_cell(get_viewport().get_mouse_position())


func screen_to_cell(mp: Vector2) -> Vector2i:
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return Vector2i(-100, -100)
	var hit := from + dir * (-from.y / dir.y)
	return Vector2i(floori(hit.x), floori(hit.z))


func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map_cols and c.y < map_rows


func can_build(c: Vector2i) -> bool:
	return in_map(c) and not path_cells.has(c) and not blocked.has(c) and not towers.has(c)


# How far WASD can move the camera from its start: more on bigger maps.
func camera_limit() -> Vector2:
	return CAMERA_LIMIT * Vector2(maxf(map_cols / float(DEFAULT_SIZE.x), 1.0), maxf(map_rows / float(DEFAULT_SIZE.y), 1.0))


# ---------------------------------------------------------------- maps

# How many of the 4 neighbor tiles are in cells.
func count_near(c: Vector2i, cells: Dictionary) -> int:
	var n := 0
	for d: Vector2i in DIRS:
		if cells.has(c + d):
			n += 1
	return n


# Reads and checks a map: its rows of letters (see DEFAULT_MAP). Used for the
# Default map, saved maps and maps from the host, so only plain text goes in and
# anything unexpected is refused. Returns {"error": text} or the finished map
# for use_map().
func read_map(lines: Variant) -> Dictionary:
	if not (lines is Array) or lines.size() < MAP_MIN.y or lines.size() > MAP_MAX.y:
		return {"error": "The map must be %d to %d tiles high" % [MAP_MIN.y, MAP_MAX.y]}
	if not (lines[0] is String):
		return {"error": "Broken map"}
	var cols: int = lines[0].length()
	if cols < MAP_MIN.x or cols > MAP_MAX.x:
		return {"error": "The map must be %d to %d tiles wide" % [MAP_MIN.x, MAP_MAX.x]}
	var path := {}
	var gates: Array = [null, null, null, null]
	var block := {}
	for y in lines.size():
		if not (lines[y] is String) or lines[y].length() != cols:
			return {"error": "Broken map: its rows aren't all as long"}
		for x in cols:
			var ch: String = lines[y][x]
			var c := Vector2i(x, y)
			if not MAP_LETTERS.contains(ch):
				return {"error": "Broken map: unknown tile '%s'" % ch}
			if ch == "#":
				path[c] = true
			elif ch in ["1", "2", "3", "4"]:
				var g := int(ch) - 1
				if gates[g] != null:
					return {"error": "Gate %s is on the map twice" % ch}
				gates[g] = c
				path[c] = true
			elif ch != ".":
				block[c] = ch
	# Gate 1 is needed (playing alone uses it), and the gates are numbered without gaps
	for g in range(1, 4):
		if gates[g] != null and gates[g - 1] == null:
			return {"error": "Gate %d is missing (gates go 1, 2, 3, 4)" % g}
	if gates[0] == null:
		return {"error": "Place gate 1"}
	# The loop is what's left after taking away dead ends again and again
	var core := path.duplicate()
	var changed := true
	while changed:
		changed = false
		for c: Vector2i in core.keys():
			if count_near(c, core) <= 1:
				core.erase(c)
				changed = true
	if core.size() < MIN_LOOP:
		return {"error": "The path needs a closed loop of at least %d tiles" % MIN_LOOP}
	for c: Vector2i in core:
		if count_near(c, core) != 2:
			return {"error": "The loop must be one tile wide and can't touch itself (at %d, %d)" % [c.x, c.y]}
	# Walk the loop from its first tile in reading order
	var start: Vector2i = core.keys()[0]
	for c: Vector2i in core:
		if c.y < start.y or (c.y == start.y and c.x < start.x):
			start = c
	var ring: Array[Vector2i] = [start]
	var prev := start
	var cur := start
	while true:
		var nxt := cur
		for d: Vector2i in DIRS:
			if core.has(cur + d) and cur + d != prev:
				nxt = cur + d
				break
		if nxt == start or nxt == cur:
			break
		ring.append(nxt)
		prev = cur
		cur = nxt
	if ring.size() != core.size():
		return {"error": "The path must be one single loop"}
	# Monsters walk clockwise on screen: with y pointing down, that's a positive area
	var area := 0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0:
		ring.reverse()
	# Each gate's road to the loop, then once around the loop from where it joins
	var used := {}
	var new_routes: Array = []
	var starts: Array = []
	for g in MAX_PLAYERS:
		if gates[g] == null:
			new_routes.append([])
			starts.append(0)
			continue
		var gc: Vector2i = gates[g]
		if core.has(gc) or count_near(gc, path) != 1:
			return {"error": "Gate %d must be at the end of a road that leads to the loop" % (g + 1)}
		var road: Array[Vector2i] = [gc]
		prev = gc
		cur = gc
		while not core.has(cur):
			used[cur] = true
			var next_cells := []
			for d: Vector2i in DIRS:
				if path.has(cur + d) and cur + d != prev:
					next_cells.append(cur + d)
			if next_cells.size() != 1:
				return {"error": "Gate %d's road must lead to the loop without splitting" % (g + 1)}
			prev = cur
			cur = next_cells[0]
			road.append(cur)
		var j := ring.find(cur)
		var cells: Array[Vector2i] = road.duplicate()
		for i in range(1, ring.size()):
			cells.append(ring[(j + i) % ring.size()])
		# Only the corners (and the gate and the joining tile) become route points
		var pts: Array[Vector2] = []
		var loop_at := 0
		for i in cells.size():
			var is_join := i == road.size() - 1
			var keep := i == 0 or is_join
			if not keep:
				var after: Vector2i = cells[i + 1] if i + 1 < cells.size() else cur
				keep = cells[i] - cells[i - 1] != after - cells[i]
			if keep:
				if is_join:
					loop_at = pts.size()
				pts.append(cell_center(cells[i]))
		new_routes.append(pts)
		starts.append(loop_at)
	for c: Vector2i in path:
		if not core.has(c) and not used.has(c):
			return {"error": "The road at %d, %d doesn't lead from a gate to the loop" % [c.x, c.y]}
	# Areas: each tile belongs to the gate whose road joins the loop nearest to it
	# (on the Default map that's the quarter around each gate)
	var areas := {}
	for x in cols:
		for y in lines.size():
			var best := -1
			var best_d := 0.0
			for g in MAX_PLAYERS:
				if gates[g] == null:
					continue
				var join: Vector2 = new_routes[g][starts[g]] / CELL - Vector2(0.5, 0.5)
				var d := Vector2(x, y).distance_squared_to(join)
				if best < 0 or d < best_d:
					best = g
					best_d = d
			areas[Vector2i(x, y)] = best
	return {"text": lines.duplicate(), "loop": ring.size(), "cols": cols, "rows": lines.size(), "path": path, "gates": gates,
			"routes": new_routes, "loop_starts": starts, "blocked": block, "areas": areas}


# Makes a map checked by read_map() the one being played. The 3D world has to be
# built (again) after this.
func use_map(m: Dictionary, title := "Default") -> void:
	map_name = title
	map_rows_text = m.text
	map_cols = m.cols
	map_rows = m.rows
	path_cells = m.path
	gate_cells = m.gates
	routes = m.routes
	loop_starts = m.loop_starts
	blocked = m.blocked
	area_of = m.areas
	daily_date = ""  # another map ends the daily challenge (start_daily() sets it after this)
	weekly_id = ""  # ...and the weekly one (start_weekly() in main.gd sets it after this)


# The built-in map with exactly these rows ("Default", "Serpent"...), or "".
func builtin_map_name(rows: Array) -> String:
	for n: String in BUILTIN_MAPS:
		if BUILTIN_MAPS[n] == rows:
			return n
	return ""


# A built-in map's rows (a copy), or [] if there's no built-in map called n.
func builtin_map_rows(n: String) -> Array:
	return BUILTIN_MAPS[n].duplicate() if BUILTIN_MAPS.has(n) else []


func flash(text: String) -> void:
	message = text
	message_time = 3.0


func tower_button_rect(i: int) -> Rect2:
	return Rect2(CARD_X + i * (CARD_SIZE + CARD_GAP), CARD_Y, CARD_SIZE, CARD_SIZE)


func kind_for_wave(w: int) -> String:
	if w % 10 == 0:
		return "boss"
	if w % 5 == 0:
		return "fast"
	if w % 3 == 0:
		return "armored"
	return "normal"


# ----- monster SPECIALS
# From wave 31, waves ending in 1 are splitters, normal waves ending in 4 carry
# shields (not armored ones), and waves ending in 7 bring healers (every 6th
# monster). Boss waves 200, 220, 240... get shields too. Same on every level,
# in endless mode and in the daily challenge.
const SPECIALS := ["", "split", "splitling", "heal"]  # index: sent in 2 bits (see special_bits())
const SPLIT_HP := 0.55  # a splitter's health (times normal)...
const SPLITLING_HP := 0.25  # ...and each of its 2 splitlings'
const SPLITLING_SPEED := 1.25
const HEALER_EVERY := 6  # every 6th monster of a healer wave is a healer
const HEALER_HP := 0.8
const HEAL_EVERY := 2.5  # seconds between heals
const HEAL_RANGE := 80.0  # pixels
const HEAL_SHARE := 0.04  # of the healed monster's full health (bosses HEAL_BOSS)
const HEAL_BOSS := 0.015
const SHIELD_SHARE := 0.2  # a shield is worth this much of the monster's health (bosses SHIELD_BOSS)
const SHIELD_BOSS := 0.1
const SHIELD_REGROW := 5.0  # seconds without being hit before the shield regrows...
const SHIELD_REGROW_RATE := 0.1  # ...by this share of it a second


# The wave's trait: "", "split", "shield" or "heal".
func wave_special(w: int) -> String:
	var kind := kind_for_wave(w)
	if kind == "boss":
		return "shield" if w >= 200 and w % 20 == 0 else ""
	if w < 31:
		return ""
	match w % 10:
		1: return "split"
		4: return "shield" if kind == "normal" else ""
		7: return "heal"
	return ""


# A monster's trait and shield in 3 bits, for snapshots and the replay:
# SPECIALS index * 4 (bits 4 and 8), + 16 while its shield is up. Bosses never
# have a trait, so a boss with index 3 is Grimwhistle ("conductor").
func special_bits(e: Enemy) -> int:
	var i := 3 if e.special == "conductor" else maxi(SPECIALS.find(e.special), 0)
	return i * 4 | (16 if e.shield > 0.0 else 0)


# The other players' (and the replay's) copy of a monster: its trait and whether
# its shield is up (max_shield 1, shield 1 or 0) from special_bits(). e.kind
# must be set first (make_enemy()).
func apply_special_bits(e: Enemy, bits: int) -> void:
	var i := (bits >> 2) & 3
	if e.kind == "boss":
		e.special = "conductor" if i == 3 else ""
		if i == 3:
			e.radius = GRIM_RADIUS
	else:
		e.special = SPECIALS[i]
	e.max_shield = 1.0 if bits & 16 else e.max_shield
	e.shield = 1.0 if bits & 16 else 0.0


# ----- Grimwhistle, the Bone Conductor
# The last wave (MAX_WAVE, not in the daily or weekly challenge) sends from every
# gate Grimwhistle first, then 4 bosses. He is a boss (kind "boss") with special
# "conductor". His Crescendo (every CRESCENDO_EVERY seconds): monsters within
# CRESCENDO_RANGE of him (himself too) lose slows and freezes, soldiers let go
# of them, and they walk CRESCENDO_HASTE times faster for CRESCENDO_TIME. Knights
# hold him for GRIM_HOLD of their boss hold, and he wears soldiers down GRIM_HURT
# times faster than a boss. When every Grimwhistle has fallen, the monsters
# left crumble (no gold) and the game is won (main.gd).
const GRIM_NAME := "Grimwhistle, the Bone Conductor"  # over his health bar (the ui)
const GRIM_HP := 1.5  # times a boss's health (and shield)
const GRIM_SPEED := 0.6  # times a normal monster's speed (bosses 0.7)
const GRIM_RADIUS := 22.0  # bosses 18
const GRIM_GOLD := 2  # times a boss's gold
const GRIM_HOLD := 0.5
const GRIM_HURT := 2.0
const CRESCENDO_FIRST := 6.0  # seconds after he comes out
const CRESCENDO_EVERY := 10.0
const CRESCENDO_RANGE := 160.0  # pixels
const CRESCENDO_HASTE := 1.4
const CRESCENDO_TIME := 3.0


# Is wave w Grimwhistle's wave?
func grimwhistle_wave(w: int) -> bool:
	return w == MAX_WAVE and daily_date == "" and weekly_id == ""


# Every computer: Grimwhistle e just did his Crescendo (the host's crescendo()
# in main.gd, the other players from net_show_crescendo, the replay from its
# recording). Empty here: game_audio.gd (the sound), game_world.gd (the look),
# game_net.gd (the host tells the other players) and main.gd (the replay
# records it) override it and call super(). Overrides only show and play: the
# game itself (slows, holds, haste) is changed by crescendo() on the host.
func crescendo_fx(_e: Enemy) -> void:
	pass


# Every computer: a poison cloud's look at pos (map pixels), radius r, for
# seconds. A placeholder flat green disc; game_world.gd can make the real one.
# path: the tower's path (0 none, 1 Venom, 2 Miasma).
func show_cloud(pos: Vector2, r: float, seconds: float, _path: int) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = r / CELL
	disc.bottom_radius = r / CELL
	disc.height = 0.04
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.9, 0.2, 0.3)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var node := MeshInstance3D.new()
	node.mesh = disc
	node.material_override = m
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = to3d(pos, 0.05)
	add_child(node)
	effects.append({"kind": "cloud", "node": node, "time": seconds, "max": seconds})


# ----- Barracks (see TOWER_BASE["barracks"]; the soldiers' rules are in main.gd)

# The path tile nearest to a Barracks on tile c, within rng pixels (gate tiles
# left out), as its center in map pixels, or (-1, -1) if there's none. The same
# on every computer (ties go to the first in reading order), so it's never sent.
func rally_point(c: Vector2i, rng: float) -> Vector2:
	var best := Vector2(-1, -1)
	var best_d := INF
	var from := cell_center(c)
	var k := ceili(rng / CELL)
	for y in range(c.y - k, c.y + k + 1):
		for x in range(c.x - k, c.x + k + 1):
			var p := Vector2i(x, y)
			if not path_cells.has(p) or p in gate_cells:
				continue
			var d := cell_center(p).distance_to(from)
			if d <= rng and d < best_d:
				best_d = d
				best = cell_center(p)
	return best


# Can a Barracks stand on tile c (besides can_build())? It needs a path tile in
# its level 1 range. For the build ghost too.
func barracks_fits(c: Vector2i) -> bool:
	return rally_point(c, TOWERS["barracks"]["range"][0]).x >= 0.0


# Host: a Barracks' soldiers as one byte each: its health share 1-127 (0: fallen),
# + 128 while it holds a monster.
func soldier_bytes(t: Tower) -> PackedByteArray:
	var out := PackedByteArray()
	var n := t.soldier_hp.size()
	out.resize(n)
	if n == 0:
		return out
	var most: float = tower_data(t.type, t.path, t.level)["soldier_hp"][t.level]
	for i in n:
		var hp: float = t.soldier_hp[i]
		var b := 0 if hp <= 0.0 else clampi(roundi(hp / most * 127.0), 1, 127)
		if b > 0 and i < t.soldier_hold.size() and t.soldier_hold[i] != null:
			b |= 128
		out[i] = b
	return out


# Every Barracks' soldier_look in one message, for the snapshots and the replay:
# per Barracks its tile x, y and soldier count (1 byte each), then a byte per
# soldier (see soldier_bytes()). Empty when there's no Barracks.
func barracks_info() -> PackedByteArray:
	var out := PackedByteArray()
	for t: Tower in towers.values():
		if t.type == "barracks":
			out.append(t.cell.x)
			out.append(t.cell.y)
			out.append(t.soldier_look.size())
			out.append_array(t.soldier_look)
	return out


# Other players (from the snapshot) and the replay: sets each Barracks'
# soldier_look from barracks_info(). Checked like anything from the network.
func apply_barracks_info(data: Variant) -> void:
	if not data is PackedByteArray:
		return
	var at := 0
	while at + 3 <= data.size():
		var c := Vector2i(data[at], data[at + 1])
		var n: int = data[at + 2]
		at += 3
		if at + n > data.size():
			return
		var t: Tower = towers.get(c)
		if t != null and t.type == "barracks" and n <= 16:
			t.soldier_look = data.slice(at, at + n)
		at += n


# Every computer, every frame, for each Barracks: shows its soldiers at its rally
# point from t.soldier_look. A placeholder (small capsules in the owner's color,
# leaning forward while holding a monster, hidden when fallen) under the tower's
# node; game_world.gd can make the real soldiers.
var soldier_mesh: CapsuleMesh
var soldier_mats := {}  # owner slot -> material


func show_soldiers(t: Tower) -> void:
	if t.node == null or t.rally.x < 0.0:
		return
	var group: Node3D = t.node.get_node_or_null("Soldiers")
	if group == null:
		group = Node3D.new()
		group.name = "Soldiers"
		t.node.add_child(group)
	group.position = to3d(t.rally) - t.node.position
	if soldier_mesh == null:
		soldier_mesh = CapsuleMesh.new()
		soldier_mesh.radius = 0.06
		soldier_mesh.height = 0.25
	if not soldier_mats.has(t.owner):
		var m := StandardMaterial3D.new()
		m.albedo_color = color_of(t.owner).lerp(Color(0.75, 0.6, 0.4), 0.3)
		soldier_mats[t.owner] = m
	var n := t.soldier_look.size()
	while group.get_child_count() < n:
		var s := MeshInstance3D.new()
		s.mesh = soldier_mesh
		s.material_override = soldier_mats[t.owner]
		group.add_child(s)
	for i in group.get_child_count():
		var s: Node3D = group.get_child(i)
		var b: int = t.soldier_look[i] if i < n else 0
		s.visible = b & 127 > 0
		if s.visible:
			var a := TAU * i / n
			s.position = Vector3(cos(a), 0.0, sin(a)) * (0.12 if n > 1 else 0.0) + Vector3(0, 0.125, 0)
			s.rotation.x = 0.35 if b & 128 else 0.0


# The last wave: MAX_WAVE, DAILY_WAVES in the daily challenge, WEEKLY_WAVES in the
# weekly one (no endless mode there), or (practically) never in endless mode.
func last_wave() -> int:
	if daily_date != "":
		return DAILY_WAVES
	if weekly_id != "":
		return WEEKLY_WAVES
	return ENDLESS_LAST_WAVE if endless else MAX_WAVE


# A monster's health in wave w: +17% a wave up to wave 25, then +2.5% a wave,
# and in endless mode +4% a wave after MAX_WAVE (ENDLESS_HP_GROWTH).
func wave_hp(w: int) -> float:
	var hp := 25.0 * pow(1.17, mini(w, 25) - 1) * pow(1.025, clampi(w, 25, MAX_WAVE) - 25)
	return hp * pow(ENDLESS_HP_GROWTH, maxi(w - MAX_WAVE, 0))


# Monsters out of each gate in wave w: one more each wave up to 32, bosses up to 5.
func wave_count(w: int) -> int:
	if kind_for_wave(w) == "boss":
		return mini(1 + int(w / 10.0), 5)
	return mini(8 + w, 32)


# Gold every player gets when wave w starts.
func wave_income(w: int) -> int:
	return maxi(10 + w * 2, int(minf(wave_hp(w) / 35.0, GOLD_CAP)))


# Gold for killing a monster in wave w (a boss gives 40 + 12 times this).
# Playing alone pays about 15% more later on, since nobody helps.
func wave_bounty(w: int) -> int:
	var hp_per_gold := 175.0 if player_count() < 2 else 200.0
	return maxi(2 + int(mini(w, 30) / 4.0), int(minf(wave_hp(w) / hp_per_gold, GOLD_CAP)))


# All the gold a player who killed everything would have earned before wave w
# (for players joining late).
func gold_before_wave(w: int) -> int:
	var total := start_gold()
	for i in range(1, mini(w, last_wave() + 1)):
		var bounty := wave_bounty(i)
		if kind_for_wave(i) == "boss":
			bounty = 40 + bounty * 12
		total = mini(total + wave_income(i) + bounty * wave_count(i), GOLD_MAX)
	return total


# ----- abilities (see ABILITIES)

# Game seconds until a player's ability is ready again (0: ready).
func ability_left(slot: int, ability: String) -> float:
	var p: Player = players[slot] if slot >= 0 and slot < MAX_PLAYERS else null
	return p.cooldowns.get(ability, 0.0) if p != null else 0.0


# Starts a player's cooldown for an ability (the host when it's used; the other
# players when the host tells them).
func start_cooldown(slot: int, ability: String) -> void:
	var p: Player = players[slot] if slot >= 0 and slot < MAX_PLAYERS else null
	if p != null and ABILITIES.has(ability):
		p.cooldowns[ability] = ABILITIES[ability]["cooldown"]


# Counts every player's cooldowns down (game seconds).
func tick_cooldowns(dt: float) -> void:
	for p in players:
		if p != null:
			for a: String in p.cooldowns.keys():
				p.cooldowns[a] = maxf(p.cooldowns[a] - dt, 0.0)


# Meteor's damage in this wave (and level).
func meteor_damage() -> float:
	return ABILITIES["meteor"]["damage"] * wave_hp(maxi(wave, 1)) * DIFFICULTY_HP[difficulty]


# Freeze all: every monster stands still (bosses half as long), even one Deep
# Freeze made immune; after it thaws, it's immune like after Deep Freeze.
func freeze_all() -> void:
	var seconds: float = ABILITIES["freeze"]["time"]
	for e in enemies:
		e.freeze_time = maxf(e.freeze_time, seconds * (0.5 if e.kind == "boss" else 1.0))
		e.freeze_immune = 0.0


# Where the mouse points on the ground, in map pixels (for aiming Meteor).
func mouse_point() -> Vector2:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return Vector2(-1000, -1000)
	var hit := from + dir * (-from.y / dir.y)
	return Vector2(hit.x, hit.z) * CELL


# The ability buttons on the console (i: index in ABILITY_ORDER) and the "Keep
# going" button on the win screen. Empty here (nothing to click) until the
# graphics agent places them; the keys work without them.
func ability_button_rect(_i: int) -> Rect2:
	return Rect2()


func keep_going_rect() -> Rect2:
	return Rect2()


# Hooks, empty here. game_net.gd fills in the sending (like send_difficulty()),
# game_world.gd the effects.
# Host: tells the other players a player used an ability (they start its cooldown
# with start_cooldown() and show it with show_ability(); for "freeze" also freeze_all()).
func send_ability(_slot: int, _ability: String, _at: Vector2) -> void:
	pass


# Host: tells the other players the game keeps going in endless mode (they set
# endless = true, state = "playing" and end_stats = {}).
func send_endless() -> void:
	pass


# Every computer: the look of an ability being used (Meteor at "at", or Freeze all).
func show_ability(_slot: int, _ability: String, _at: Vector2) -> void:
	pass


# Whether a monster got past (walked once round the loop), for the replay. The
# host and a player alone work it out (main.gd); the other players only know
# what the host's snapshots say (Enemy.past).
func got_past(e: Enemy) -> bool:
	return e.past


# Every computer: a player's ping at pos (map pixels), for PING_TIME seconds
# (see send_ping() in game_net.gd). The look is the graphics agent's.
func show_ping(_slot: int, _pos: Vector2) -> void:
	pass


# ---------------------------------------------------------------- pings and gifts

const PING_TIME := 4.0  # seconds a ping shows
const PING_BURST := 3.0  # pings a player may send at once...
const PING_REFILL := 2.0  # ...and then one per this many seconds
const GIFT_SHARES := [0.1, 0.25, 0.5]  # the gift box's buttons: this share of your gold
const GIFT_WAIT := 2.0  # seconds between one player's gifts


# ---------------------------------------------------------------- daily challenge
# The same map and rules for everyone each UTC day, worked out from the date by
# every game (no server needed): the map in game_net.gd (daily_map_rows()), the
# rules here. Everything comes from our own small random numbers, so a Godot
# update can never change a day's map or rules.

const DAILY_VERSION := 1  # raise when the map maker or the twists change (that day's map changes too)
const DAILY_WAVES := 40  # the daily challenge is won after this wave (the server knows it too)
const DAILY_LEVELS := [1, 1, 2]  # index in DIFFICULTIES, picked from these: Normal twice as often as Hard
# One twist per day. Numbers multiply (1.0: no change); main.gd applies them.
#   start_gold: start gold    count: monsters per wave    hp: monster health
#   bounty: kill gold    income: wave gold    towers: how many tower types can be built (0: all)
#   no_sell: towers can't be sold    armored: every wave that would be "normal" is "armored"
const DAILY_TWISTS := {
	"rich": {"name": "Rich start", "desc": "Twice the start gold.", "start_gold": 2.0},
	"swarm": {"name": "Swarm", "desc": "50% more monsters, with 35% less health.", "count": 1.5, "hp": 0.65},
	"two_towers": {"name": "Two towers", "desc": "Only two tower types can be built.", "towers": 2},
	"no_selling": {"name": "No selling", "desc": "Towers can't be sold.", "no_sell": true},
	"armored": {"name": "Armored day", "desc": "Normal waves are armored.", "armored": true},
	"tight": {"name": "Tight budget", "desc": "30% less kill gold, 30% more wave gold.", "bounty": 0.7, "income": 1.3},
}
const DAILY_HELPERS := ["frost", "barracks"]  # "Two towers" never picks only these
var daily_date := ""  # "2026-11-02" while playing that day's challenge, "" otherwise
var daily_state := 1  # the daily random numbers (see daily_seed())
var daily_cache := {}  # the last daily_rules() worked out


# Today in UTC, "2026-11-02": everyone's daily challenge changes at the same moment.
func daily_today() -> String:
	return Time.get_date_string_from_system(true)


# Starts the daily random numbers for a text (FNV-1a hash into xorshift32).
func daily_seed(text: String) -> void:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	daily_state = h if h != 0 else 1


func daily_next() -> int:
	daily_state ^= (daily_state << 13) & 0xFFFFFFFF
	daily_state ^= daily_state >> 17
	daily_state ^= (daily_state << 5) & 0xFFFFFFFF
	return daily_state


# A whole number from lo to hi (both included).
func daily_roll(lo: int, hi: int) -> int:
	return lo + daily_next() % (hi - lo + 1)


# The day's rules, or {} when this game isn't a daily challenge (date "": the one
# being played). Every key is always there, so main.gd can just use them:
# {date, name, desc, level, waves, start_gold, count, hp, bounty, income,
#  towers (the tower types that can be built), no_sell, armored}
func daily_rules(date := "") -> Dictionary:
	if date == "":
		date = daily_date
	if date == "":
		return {}
	if daily_cache.get("date", "") == date:
		return daily_cache  # cheap enough to ask every frame
	daily_seed("gtd-daily-rules-%d-%s" % [DAILY_VERSION, date])
	var level: int = DAILY_LEVELS[daily_roll(0, DAILY_LEVELS.size() - 1)]
	var keys := DAILY_TWISTS.keys()
	keys.sort()  # the same order everywhere
	var key: String = keys[daily_roll(0, keys.size() - 1)]
	var tw: Dictionary = DAILY_TWISTS[key]
	var types: Array = TOWER_TYPES.duplicate()
	var keep: int = tw.get("towers", 0)
	while keep > 0:
		types = TOWER_TYPES.duplicate()
		while types.size() > keep:
			types.remove_at(daily_roll(0, types.size() - 1))
		# Two helpers and nothing that really kills: roll again
		if types.any(func(t: String) -> bool: return not t in DAILY_HELPERS):
			break
	daily_cache = {"date": date, "twist": key, "name": tw.name, "desc": tw.desc, "level": level, "waves": DAILY_WAVES,
			"start_gold": tw.get("start_gold", 1.0), "count": tw.get("count", 1.0), "hp": tw.get("hp", 1.0),
			"bounty": tw.get("bounty", 1.0), "income": tw.get("income", 1.0), "towers": types,
			"no_sell": tw.get("no_sell", false), "armored": tw.get("armored", false)}
	return daily_cache


# ---------------------------------------------------------------- weekly challenge
# Like the daily, but harder and longer: the same map and rules for everyone each
# ISO week (Monday 00:00 UTC to Sunday), worked out from the week id ("2026-W45")
# with the daily's random numbers. Always Hard, two daily twists (never "Rich
# start"), 100 waves, and the Rising tide: from wave WEEKLY_TIDE_FROM monster
# health grows by WEEKLY_TIDE a wave on top (gold doesn't follow it).
# main.gd starts it (start_weekly(), menu_weekly()) and applies the rules
# through challenge_rules(), like the daily's.

const WEEKLY_VERSION := 1  # raise when the weekly map pick or rules change (the board gets "-r2")
const WEEKLY_WAVES := 100  # the weekly challenge is won after this wave (the server knows it too)
const WEEKLY_LEVEL := 2  # index in DIFFICULTIES: always Hard
const WEEKLY_TWIST_COUNT := 2
# Daily twists the weekly never picks: Rich start and Swarm make it easier, Two
# towers without Frost makes 100 waves out of reach. 3 twists left: 3 pairs.
const WEEKLY_NO_TWISTS := ["rich", "two_towers", "swarm"]
const WEEKLY_TIDE_FROM := 31  # Rising tide: from this wave...
const WEEKLY_TIDE := 0.01  # ...+1% monster health a wave (x1.20 at wave 50, x1.70 at wave 100)
# The maps a week can have: the built-in ones, and "" for a map of its own
# (made like the daily's). Every block of 6 weeks has each one once, in a
# seeded order, and never the same one two weeks in a row.
const WEEKLY_MAPS := ["Default", "Serpent", "Twin Lanes", "Hourglass", "Four Roads", ""]
var weekly_id := ""  # "2026-W45" while playing that week's challenge, "" otherwise
var weekly_cache := {}  # the last weekly_rules() worked out
var weekly_maps := {}  # id -> read_map() result, worked out once


# The ISO week (UTC) a moment is in, as "2026-W45": weeks start on Monday, and
# week 1 is the one with the year's first Thursday.
func weekly_id_at(unix: float) -> String:
	var day := floori(unix / 86400.0)
	var thursday := day - posmod(day + 3, 7) + 3  # day 0 (1970-01-01) was a Thursday
	var year: int = Time.get_date_dict_from_unix_time(thursday * 86400).year
	var jan1 := floori(Time.get_unix_time_from_datetime_string("%04d-01-01T00:00:00" % year) / 86400.0)
	return "%04d-W%02d" % [year, floori((thursday - jan1) / 7.0) + 1]


# This week's id, the same for everyone at the same moment.
func weekly_now() -> String:
	return weekly_id_at(Time.get_unix_time_from_system())


# Seconds until this week's challenge ends (next Monday 00:00 UTC).
func weekly_ends_in() -> int:
	var now := Time.get_unix_time_from_system()
	var day := floori(now / 86400.0)
	return int((day - posmod(day + 3, 7) + 7) * 86400 - now)


# A week's Monday (days since 1970-01-01), or -1 if id isn't a real week
# ("2025-W53" isn't: 2025 has 52 weeks). Years 2000-9999.
func weekly_monday(id: String) -> int:
	if id.length() != 8 or id.substr(4, 2) != "-W" or not id.left(4).is_valid_int() or not id.right(2).is_valid_int():
		return -1
	var year := id.left(4).to_int()
	var w := id.right(2).to_int()
	if year < 2000 or w < 1 or w > 53:
		return -1
	var jan4 := floori(Time.get_unix_time_from_datetime_string("%04d-01-04T00:00:00" % year) / 86400.0)
	var monday := jan4 - posmod(jan4 + 3, 7) + 7 * (w - 1)  # jan 4 is always in week 1
	return monday if weekly_id_at(monday * 86400.0) == id else -1


func weekly_valid(id: Variant) -> bool:
	return id is String and weekly_monday(id) >= 0


# The week before (for "never the same map two weeks in a row").
func weekly_before(id: String) -> String:
	var monday := weekly_monday(id)
	return weekly_id_at((monday - 7) * 86400.0) if monday >= 0 else ""


# The week's map: a built-in map's name, or "" for a map of its own.
func weekly_map_pick(id: String) -> String:
	var monday := weekly_monday(id)
	if monday < 0:
		return "Default"
	var n := floori((monday + 3) / 7.0)  # weeks since Monday 1969-12-29
	var block := floori(n / 6.0)
	var order := weekly_map_order(block)
	var i := n - block * 6
	# A block never starts with the map the block before ended with
	if i <= 1 and weekly_map_order(block - 1)[5] == order[0]:
		var first: String = order[0]
		order[0] = order[1]
		order[1] = first
	return order[i]


# Block b's 6 weeks of maps: WEEKLY_MAPS in a seeded order.
func weekly_map_order(block: int) -> Array:
	daily_seed("gtd-weekly-map-%d-%d" % [WEEKLY_VERSION, block])
	var order: Array = WEEKLY_MAPS.duplicate()
	for k in range(order.size() - 1, 0, -1):
		var j := daily_roll(0, k)
		var t: String = order[k]
		order[k] = order[j]
		order[j] = t
	return order


# The week's map, checked by read_map() like any map.
func weekly_map(id: String) -> Dictionary:
	if not weekly_maps.has(id):
		var pick := weekly_map_pick(id)
		var m := read_map(BUILTIN_MAPS[pick] if pick != "" else weekly_map_rows(id))
		weekly_maps[id] = m if not m.has("error") else read_map(DEFAULT_MAP)
	return weekly_maps[id]


# A week's own map (when weekly_map_pick() is ""): made by the daily's map maker
# (daily_map_rows() in game_net.gd, after this file) from the week's id.
func weekly_map_rows(id: String) -> Array:
	return call("daily_map_rows", "weekly-%d-%s" % [WEEKLY_VERSION, id])


# For the menu tip and the banner: the week's map name, or "its own map".
func weekly_map_label(id: String) -> String:
	var pick := weekly_map_pick(id)
	return pick if pick != "" else "its own map"


func weekly_title(id: String) -> String:
	return "Weekly " + id


# The week's rules (id "": the one being played), or {} when this game isn't a
# weekly challenge. The same keys as daily_rules() (twist is ""), plus
# twists: [the 2 twist keys], tide, tide_from.
func weekly_rules(id := "") -> Dictionary:
	if id == "":
		id = weekly_id
	if id == "":
		return {}
	if weekly_cache.get("id", "") == id:
		return weekly_cache
	daily_seed("gtd-weekly-rules-%d-%s" % [WEEKLY_VERSION, id])
	var keys: Array = DAILY_TWISTS.keys().filter(func(k: String) -> bool: return not k in WEEKLY_NO_TWISTS)
	keys.sort()  # the same order everywhere
	var picked := []
	while picked.size() < WEEKLY_TWIST_COUNT and not keys.is_empty():
		picked.append(keys.pop_at(daily_roll(0, keys.size() - 1)))
	var r := {"id": id, "date": "", "twist": "", "twists": picked, "level": WEEKLY_LEVEL, "waves": WEEKLY_WAVES,
			"start_gold": 1.0, "count": 1.0, "hp": 1.0, "bounty": 1.0, "income": 1.0, "towers": TOWER_TYPES.duplicate(),
			"no_sell": false, "armored": false, "tide": WEEKLY_TIDE, "tide_from": WEEKLY_TIDE_FROM}
	var names := []
	var descs := []
	for k: String in picked:
		var tw: Dictionary = DAILY_TWISTS[k]
		names.append(tw.name)
		descs.append(tw.desc)
		for n: String in ["start_gold", "count", "hp", "bounty", "income"]:
			r[n] *= tw.get(n, 1.0)
		r.no_sell = r.no_sell or tw.get("no_sell", false)
		r.armored = r.armored or tw.get("armored", false)
		var keep: int = tw.get("towers", 0)
		while keep > 0:
			var types: Array = TOWER_TYPES.duplicate()
			while types.size() > keep:
				types.remove_at(daily_roll(0, types.size() - 1))
			r.towers = types
			if types.any(func(t: String) -> bool: return not t in DAILY_HELPERS):
				break
	r["name"] = " + ".join(names)
	r["desc"] = " ".join(descs)
	weekly_cache = r
	return weekly_cache


# The challenge being played: the daily's rules, the weekly's, or {} (main.gd's
# rule overrides and the ui use this).
func challenge_rules() -> Dictionary:
	return daily_rules() if daily_date != "" else weekly_rules()


# Rising tide: the weekly's extra monster health in wave w (1.0 otherwise).
func weekly_tide(w: int) -> float:
	if weekly_id == "":
		return 1.0
	return 1.0 + WEEKLY_TIDE * maxi(w - WEEKLY_TIDE_FROM + 1, 0)


# Host: tells the other players the weekly challenge (id, or "" for none) after
# it starts. Empty here; game_net.gd sends it (net_set_weekly).
func send_weekly(_id: String) -> void:
	pass


# Host: tells the other players the mood (weather and time of day, one of MOODS
# in game_world.gd) after main.gd picked it. Empty here; game_net.gd sends it,
# and the other players call set_mood_from_host() (main.gd) with it.
func send_mood(_m: String) -> void:
	pass


# Every tower level up to MAX_LEVEL: levels 1-4 from TOWER_BASE, then each level
# from the one before (see LEVEL_GAIN). Called once, to fill TOWERS.
func make_towers() -> Dictionary:
	var out := {}
	for type: String in TOWER_BASE:
		var d: Dictionary = TOWER_BASE[type].duplicate(true)
		var top: int = d["cost"].size() - 1  # the last hand-made level
		var damage: float = d["damage"][top]
		var cost: float = d["cost"][top]
		for lv in range(top + 1, MAX_LEVEL):
			var n: int = lv - top  # levels past the hand-made ones
			var big := (lv + 1) % 5 == 0
			# A fixed "random" 0-8 for this level and tower
			var bump := (lv * 37 + TOWER_TYPES.find(type) * 11) % 9 / 8.0
			damage *= 1.0 + (LEVEL_GAIN_BIG if big else LEVEL_GAIN) + bump * LEVEL_GAIN_SPREAD
			cost *= LEVEL_COST_BIG if big else LEVEL_COST
			d["damage"].append(int(round_nicely(damage)))
			d["cost"].append(int(round_nicely(cost)))
			d["range"].append(d["range"][top] + minf(n * LEVEL_RANGE, LEVEL_RANGE_MAX))
			d["cooldown"].append(snappedf(d["cooldown"][top] * maxf(pow(0.98, n), 0.75), 0.01))
			if d.has("splash"):
				d["splash"].append(d["splash"][top] + minf(n * 2.0, 40.0))
			if d.has("cloud"):
				d["cloud"].append(d["cloud"][top] + minf(n * 2.0, 40.0))
			if d.has("slow"):
				d["slow"].append(snappedf(0.15 + (d["slow"][top] - 0.15) * pow(0.95, n), 0.01))
			if d.has("chain"):
				d["chain"].append(mini(d["chain"][top] + n / 4, 12))
			if d.has("soldiers"):
				# +1 soldier at levels 19, 34 and 49; tougher, longer holds, back sooner
				d["soldiers"].append(mini(d["soldiers"][top] + n / 15, SOLDIERS_MAX))
				d["soldier_hp"].append(snappedf(d["soldier_hp"][top] + minf(n * 0.3, 12.0), 0.1))
				d["hold"].append(snappedf(d["hold"][top] + minf(n * 0.03, 1.0), 0.01))
				d["respawn"].append(snappedf(maxf(d["respawn"][top] * pow(0.98, n), 4.0), 0.1))
		# Each path: the same levels, times the path's numbers from level 5 on
		var paths := []
		for p: Dictionary in PATHS[type]:
			var pd: Dictionary = d.duplicate(true)
			pd["name"] = p["name"]
			pd["desc"] = p["desc"]
			for lv in range(PATH_LEVEL, MAX_LEVEL):
				pd["damage"][lv] = int(round_nicely(d["damage"][lv] * p.get("damage", 1.0)))
				pd["cooldown"][lv] = snappedf(d["cooldown"][lv] * p.get("cooldown", 1.0), 0.01)
				pd["range"][lv] = roundf(d["range"][lv] * p.get("range", 1.0))
				if pd.has("splash"):
					pd["splash"][lv] = roundf(d["splash"][lv] * p.get("splash", 1.0))
				if pd.has("cloud"):
					pd["cloud"][lv] = roundf(d["cloud"][lv] * p.get("cloud", 1.0))
				if pd.has("chain"):
					pd["chain"][lv] = p["chain_set"] if p.has("chain_set") else mini(d["chain"][lv] + p.get("chain_add", 0), 15)
				if pd.has("soldiers"):
					pd["soldiers"][lv] = d["soldiers"][lv] + (path_step(lv, p["soldiers_add"]) if p.has("soldiers_add") else 0)
					for k: String in ["soldier_hp", "hold", "respawn"]:
						pd[k][lv] = snappedf(d[k][lv] * p.get(k, 1.0), 0.01)
			paths.append(pd)
		d["paths"] = paths
		out[type] = d
	return out


# A tower's numbers: its path's from level 5 on, the plain ones before.
func tower_data(type: String, path: int, level: int) -> Dictionary:
	if path <= 0 or level < PATH_LEVEL:
		return TOWERS[type]
	return TOWERS[type]["paths"][path - 1]


# A path's extra that grows: the first of 3 values at levels 5-19, the second at 20-39, then the third.
func path_step(level: int, values: Array) -> Variant:
	return values[0 if level < 19 else (1 if level < 39 else 2)]


# Damage factor against bosses for a tower (its path's "boss", from level 5 on).
func boss_bonus(type: String, path: int, level: int) -> float:
	if path <= 0 or level < PATH_LEVEL:
		return 1.0
	return PATHS[type][path - 1].get("boss", 1.0)


# Does this tower's next upgrade pick its path?
func needs_path(t: Tower) -> bool:
	return t.level == PATH_LEVEL - 1 and t.path == 0


# Is a level 4 tower of ours selected, so the command card shows its 2 paths?
func picking_path() -> bool:
	return selected != null and selected.owner == local_slot and needs_path(selected)


# "Sniper" once an arrow tower has that path, "Arrow" before.
func tower_name(t: Tower) -> String:
	return tower_data(t.type, t.path, t.level)["name"]


# Rounds to 2 significant digits above 100 (1234 -> 1200), so prices stay readable.
func round_nicely(x: float) -> float:
	if x < 100.0:
		return roundf(x)
	var step := pow(10.0, floorf(log(x) / log(10.0)) - 1.0)
	return roundf(x / step) * step


func start_gold() -> int:
	return int(START_GOLD * DIFFICULTY_GOLD[difficulty])


# Host: tells the other players the difficulty level after it changes. Empty
# here; game_net.gd fills it in (the other players only show the level and
# open its leaderboard: monster health always comes from the host).
func send_difficulty() -> void:
	pass


# How many players must agree to send the next wave early.
func votes_needed() -> int:
	return ceili(player_count() * EARLY_VOTE)


func alive_count() -> int:
	var n := 0
	for e in enemies:
		n += e.weight
	return n


# Each player has the part of the map nearest to where their gate's road joins
# the loop (see read_map()). Returns the player whose area a tile is in, or -1 if
# nobody plays that gate (then anyone can build).
func area_owner(c: Vector2i) -> int:
	var slot: int = area_of.get(c, -1)
	return slot if slot >= 0 and players[slot] != null else -1


func close_ask(id: int) -> void:
	for i in range(asks.size() - 1, -1, -1):
		if asks[i][0] == id:
			asks.remove_at(i)


func remove_tower(c: Vector2i) -> void:
	var t: Tower = towers.get(c)
	if t == null:
		return
	t.node.queue_free()
	towers.erase(c)
	if selected == t:
		selected = null


# ---------------------------------------------------------------- stats at the end

# The host (or a player alone) counts per player slot, so a player who leaves
# still shows up at the end. Cheap: a few additions per hit and per kill.
# Their gold always adds up: gold = stat_start + stat_earned - stat_spent + stat_gifted.
var stat_kills := [0, 0, 0, 0]
var stat_gifted := [0, 0, 0, 0]  # gold other players gave them, minus what they gave (see gift_gold())
var stat_damage := [0.0, 0.0, 0.0, 0.0]  # health really taken off (no overkill)
var stat_start := [0, 0, 0, 0]  # start gold (joining late: the gold they got then)
var stat_earned := [0, 0, 0, 0]  # wave gold, early bonus and kill gold
var stat_spent := [0, 0, 0, 0]  # gold put into towers, minus what selling gave back
var stat_names := ["", "", "", ""]  # names, kept for players who left
var sold_towers := []  # sold towers' stats: [type, path, level, owner, damage, kills]
# Everything the stats screen shows, made once by the host when the game ends
# (see make_end_stats()); the other players get it in net_stats. {}: not yet.
var end_stats := {}


func reset_stats() -> void:
	stat_kills = [0, 0, 0, 0]
	stat_damage = [0.0, 0.0, 0.0, 0.0]
	stat_start = [0, 0, 0, 0]
	stat_earned = [0, 0, 0, 0]
	stat_spent = [0, 0, 0, 0]
	stat_gifted = [0, 0, 0, 0]
	stat_names = ["", "", "", ""]
	sold_towers = []
	end_stats = {}


# ---------------------------------------------------------------- saving and loading
# See save_game() / load_game() in main.gd. Only the host (or a player alone)
# saves and loads; a loaded game never goes on the leaderboards.

const SAVE_FORMAT := 1  # raise when a save's layout changes (older saves: converted in load_game(), newer: refused)
const SAVES_DIR := "user://saves"  # <name>.sav: a header (for the list), then the game
const SAVE_NAME_MAX := 32
const SAVES_MAX := 50  # named saves (the Continue and Quicksave slots don't count)
const AUTOSAVE_NAME := "Continue"  # written at every wave start and when the game is closed
const QUICKSAVE_NAME := "Quicksave"  # F5 / F9
var from_save := false  # this game was loaded from a save: no scores (see submit_score())
var held := false  # a loaded game waits, nothing moving, until the host presses Space
var held_note := ""  # other players: the host's "waiting for" text while held (see held_text())
# Host, after loading a game with more players: slot -> {name, gold, cooldowns}
# of saved players not back yet. Their towers stay; a player joining gets one of
# these slots back (see saved_slot_for() and restore_saved_player() in main.gd).
var saved_slots := {}


# ---------------------------------------------------------------- tutorial tips
# Short tips for new players, shown one at a time when they're useful, each once
# ever. Only on this computer: never sent to the other players, and they never
# pause the game. When each one comes up and when it counts as done: update_tips()
# in main.gd. Saved in settings.cfg under [tutorial] (on, seen): load_tutorial()
# and save_tutorial() in main.gd. New players get them On; a settings.cfg from
# before tips existed means an old player, so they start Off.
#
# For the ui (game_ui.gd): current_tip() (draw it when not empty), tip_got_it()
# and tip_skip_all() (its 2 buttons), tutorial_on() / set_tutorial() (the Settings
# row), and tip_click() (override it: the clicks on the card).
#
# id -> its text and anchor, what its arrow points at: "tower_buttons" (the build
# row), "cursor" (the mouse, over the grid), "wave_button" (WAVE_RECT),
# "target_button" (MODE_RECT), "ability_buttons", "alive_counter" (the top bar's
# monster count), "wave_preview", "none" (no arrow: the card on its own), or
# "tower": the tower it's about, which current_tip() turns into its spot on the
# map (a Vector2 in map pixels, like Tower.pos).
const TIPS := {
	"build": {"text": "Pick a tower at the bottom (or press 1-6), then click on the grass to build it.", "anchor": "tower_buttons"},
	"place": {"text": "Towers go on the grass squares of the grid, not on the path. Right-click to stop building.", "anchor": "cursor"},
	"wave": {"text": "Ready? Press SPACE to start the first wave. Later, SPACE sends the next wave early for bonus gold.", "anchor": "wave_button"},
	"menu": {"text": "Esc opens the menu: Settings, saving, multiplayer and the leaderboard.", "anchor": "none"},
	"upgrade": {"text": "You have gold to spare: click this tower, then press U to upgrade it.", "anchor": "tower"},
	"target": {"text": "T changes which monster this tower shoots first. Shift+T does it for all your towers of this type.", "anchor": "target_button"},
	"abilities": {"text": "Z drops a Meteor where you click, C freezes all monsters. Both recharge after a while.", "anchor": "ability_buttons"},
	"limit": {"text": "If %d monsters are alive at once, you lose. Keep an eye on this counter.", "anchor": "alive_counter"},
	"path": {"text": "This tower is level 4. Its next upgrade picks one of 2 paths for good: select it and press Q or E.", "anchor": "tower"},
	"boss": {"text": "A boss wave is coming! Bosses have huge health and count as 5 monsters.", "anchor": "wave_preview"},
	"special": {"text": "From wave 31, waves get a trait: splitters, healers or shields. The wave preview shows which.", "anchor": "wave_preview"},
}
var tips_on := true  # the Settings row "Tutorial tips"
var tips_seen: Array = []  # ids of the tips already shown (or already learned)
var tip_queue: Array = []  # ids waiting to be shown; the first one is on screen
var tip_spots := {}  # id -> the map spot of the tower an anchor "tower" points at


# The tip on screen: {id, text, anchor}, or {} for none. A story card (see
# STORY_CARDS) comes before the tips: {id, text, anchor "none", story true, who}.
func current_tip() -> Dictionary:
	if state != "playing":
		return {}
	if story_on and not story_queue.is_empty():
		var sid: String = story_queue[0]
		return {"id": sid, "text": STORY_CARDS[sid]["text"], "anchor": "none", "story": true, "who": STORY_CARDS[sid]["who"]}
	if not tips_on or tip_queue.is_empty():
		return {}
	var id: String = tip_queue[0]
	var text: String = TIPS[id]["text"]
	if id == "limit":
		text = text % max_alive()
	var anchor: Variant = TIPS[id]["anchor"]
	if anchor == "tower":
		anchor = tip_spots.get(id, Vector2.ZERO)
	return {"id": id, "text": text, "anchor": anchor}


# "Got it" (or a story card fading out): the card on screen won't come back.
func tip_got_it() -> void:
	if story_on and not story_queue.is_empty():
		story_queue.pop_front()
		return
	if tip_queue.is_empty():
		return
	var id: String = tip_queue.pop_front()
	if not id in tips_seen:
		tips_seen.append(id)
	save_tutorial()


# "Skip all": turns the tips off, or on a story card the story cards (Settings
# can turn them on again).
func tip_skip_all() -> void:
	if story_on and not story_queue.is_empty():
		set_story_cards(false)
	else:
		set_tutorial(false)


func tutorial_on() -> bool:
	return tips_on


# Turning the tips on again starts over: every tip can come back.
func set_tutorial(on: bool) -> void:
	if on and not tips_on:
		tips_seen.clear()
	tips_on = on
	tip_queue.clear()
	tip_spots.clear()
	save_tutorial()


# main.gd writes [tutorial] to settings.cfg (not in headless runs).
func save_tutorial() -> void:
	pass


# The ui (game_ui.gd) overrides this: true if the click p (screen pixels) was on
# the tip's card, after calling tip_got_it() or tip_skip_all() for its buttons.
# on_click() (main.gd) asks it first, so a click on the card never builds.
func tip_click(_p: Vector2) -> bool:
	return false


# ---------------------------------------------------------------- story cards and the Chronicle
# Short story pages at story moments, each once per player ever, shown in the
# tip card (current_tip() returns them first, with "story" and "who"). Only on
# this computer: nothing is sent, so in multiplayer every player gets their own.
# Not in the daily (but daily_omen) or weekly challenge, the replay or the map
# editor, and a wave's card only when that wave starts while playing (not after
# loading or joining). When each one comes: update_story() in main.gd.
#
# A card unlocks when its moment comes, even with the story cards Off (then it
# just isn't shown). Unlocked cards are kept in profile.cfg under [chronicle]
# (id = the date), and the Profile's Chronicle page lists them (chronicle_list()).
# first_win and first_loss come at the end of a game, when the tip card is gone:
# the ui shows end_story_card() on the end screen.
#
# The texts are the story agent's (graphics plan\story\card texts.md).
# "hint" is what the Chronicle shows for a card that's still locked.
const STORY_CARDS := {
	"gates_waking": {"who": "Wren", "text": "Welcome, Warden! The gates are waking. Build towers along the Ring and keep it clear. Fifty monsters, and it breaks!", "hint": "Play your first game."},
	"daily_omen": {"who": "Wren", "text": "A new Omen is nailed to the well! One ring, one strange rule, one day. Let's see what you make of it.", "hint": "Start a daily challenge."},
	"mirages": {"who": "Wren", "text": "Unicorns? No, those are painted fakes. The Choir wants to see if we're awake. Pop them!", "hint": "Start wave 1."},
	"first_boss": {"who": "Sergeant Thump", "text": "A Bone Mage, one of the Choir's singers! Big and slow, and it crowds the Ring like five. Hit it hard!", "hint": "Meet your first boss."},
	"new_songs": {"who": "Wren", "text": "Hear that? The Choir is teaching new songs. Splitters, Bubblebones, Hummers... watch for new tricks!", "hint": "Reach wave 31."},
	"wave_100": {"who": "Sergeant Thump", "text": "One hundred waves! My soldiers asked for cake. I said after the next hundred.", "hint": "Reach wave 100."},
	"halfway": {"who": "The Ringkeeper", "text": "Halfway, little Warden. The song below is growing tired. Keep the Ring clear, and I will keep watch.", "hint": "Reach wave 150."},
	"wave_200": {"who": "Wren", "text": "Two hundred waves! The guild ran out of paint for the tally board. Only a hundred to go!", "hint": "Reach wave 200."},
	"grimwhistle": {"who": "Grimwhistle", "text": "ENOUGH! If my Choir can't do it, I'll conduct this song myself! Cover your ears, Wardens!", "hint": "Reach wave 300."},
	"first_win": {"who": "Wren", "text": "The gates are quiet. Grimwhistle has no one left to send. You did it, Warden! Fireworks, everyone!", "hint": "Win a game."},
	"first_loss": {"who": "Sergeant Thump", "text": "The Ring broke. Happens to the best of us. Grab a brush, Warden. We'll paint it again!", "hint": "Lose a game."},
}
# The Profile's Chronicle page (the ui draws it)
const CHRONICLE_TITLE := "The Warden's Chronicle"
const CHRONICLE_INTRO := "Every story moment you've lived, written down by the Lamplight Guild."
# The wave whose start brings each wave card (first_boss: the first boss wave)
const STORY_WAVES := {"mirages": 1, "new_songs": 31, "wave_100": 100, "halfway": 150, "wave_200": 200}
const STORY_START := 1.0  # seconds of the first game before gates_waking
var story_on := true  # the Settings row "Story cards: On / Off", settings.cfg [story] cards
var story_queue: Array = []  # ids waiting to be shown; the first one is on screen
var story_end := ""  # first_win / first_loss to show on this game's end screen ("" none)


# Unlocks story card id (once ever): into the Chronicle, and shown if show and
# the story cards are on. Returns true if it was new.
func story_unlock(id: String, show := true) -> bool:
	if profile.is_empty():
		profile = new_profile()
	if not STORY_CARDS.has(id) or profile.chronicle.has(id):
		return false
	profile.chronicle[id] = Time.get_date_string_from_system()
	save_profile()
	if show and story_on:
		if id in ["first_win", "first_loss"]:
			story_end = id
		elif not id in story_queue:
			story_queue.append(id)
	return true


# For the ui: the card for this game's end screen, {id, text, who}, or {}.
func end_story_card() -> Dictionary:
	if story_end == "" or not story_on:
		return {}
	return {"id": story_end, "text": STORY_CARDS[story_end]["text"], "who": STORY_CARDS[story_end]["who"]}


# For the ui: the end screen's card was closed (or faded).
func end_story_done() -> void:
	story_end = ""


# For the ui's Chronicle page: every card in story order, {id, who, text, hint,
# date ("" while locked, then text and who are for the ui to hide)}.
func chronicle_list() -> Array:
	var out := []
	var got: Dictionary = profile.get("chronicle", {})
	for id: String in STORY_CARDS:
		var c: Dictionary = STORY_CARDS[id]
		out.append({"id": id, "who": c.who, "text": c.text, "hint": c.hint, "date": got.get(id, "")})
	return out


func story_cards_on() -> bool:
	return story_on


# The Settings row. main.gd also saves it (settings.cfg [story] cards, written
# by save_settings() in game_world.gd).
func set_story_cards(on: bool) -> void:
	story_on = on
	story_queue.clear()
	story_end = ""


# ---------------------------------------------------------------- holiday festivals
# Looks only (game_world.gd's apply_festival() dresses the valley up): nothing
# about play changes, so every computer uses its own local date and nothing is
# sent. Picked when a game starts. The Settings row "Festivals" (festivals_on,
# settings.cfg [graphics] festivals) turns them off. Test option (debug builds):
# --festival=frostfall / lantern / paint / none.
const FESTIVALS := ["frostfall", "lantern", "paint"]
const FESTIVAL_NAMES := {"frostfall": "Frostfall Fair", "lantern": "Lantern Night", "paint": "Spring Paint Day"}
# The ui's festival banner line
const FESTIVAL_BANNERS := {
	"frostfall": "Frostfall Fair! Snow on the trees, ribbons on the gates, and warm scarves for the guard.",
	"lantern": "Lantern Night! Pumpkin lanterns on every tower. Even the bones are wearing hats.",
	"paint": "Spring Paint Day! Every fallen monster leaves a splash of color.",
}
var festivals_on := true


# Today's festival on this computer: "", "frostfall", "lantern" or "paint".
func festival_today() -> String:
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--festival="):
				var f := a.trim_prefix("--festival=")
				return f if f in FESTIVALS else ""
	if not festivals_on:
		return ""
	var d := Time.get_date_dict_from_system()
	return festival_on(d.year, d.month, d.day)


# The festival on a date: Frostfall Fair Dec 18 - Jan 1, Lantern Night Oct 24 -
# Nov 1, Spring Paint Day from 3 days before to 3 days after Easter Sunday.
func festival_on(y: int, m: int, d: int) -> String:
	if (m == 12 and d >= 18) or (m == 1 and d == 1):
		return "frostfall"
	if (m == 10 and d >= 24) or (m == 11 and d == 1):
		return "lantern"
	var e := easter(y)
	var day := func(mm: int, dd: int) -> int:
		return int(Time.get_unix_time_from_datetime_dict({"year": y, "month": mm, "day": dd}) / 86400)
	if absi(day.call(m, d) - day.call(e.x, e.y)) <= 3:
		return "paint"
	return ""


# Easter Sunday in year y (Gregorian, the anonymous algorithm): Vector2i(month, day).
func easter(y: int) -> Vector2i:
	var a := y % 19
	var b := y / 100
	var c := y % 100
	var dd := b / 4
	var e := b % 4
	var f := (b + 8) / 25
	var g := (b - f + 1) / 3
	var h := (19 * a + b - dd - g + 15) % 30
	var i := c / 4
	var k := c % 4
	var l := (32 + 2 * e + 2 * i - h - k) % 7
	var mm := (a + 11 * h + 22 * l) / 451
	var month := (h + l - 7 * mm + 114) / 31
	var day := (h + l - 7 * mm + 114) % 31 + 1
	return Vector2i(month, day)


# ---------------------------------------------------------------- achievements and profile
# Each player's own stats and achievements, kept on their own computer in
# PROFILE_FILE (apart from settings.cfg). The host (or a player alone) watches the
# game for every player (main.gd: prog_for() and the hooks), judges what they
# earn, and hands each player their part with profile_update(): the host's own
# part straight to apply_profile_update(), the others' through
# send_profile_update() (game_net.gd sends it; the player's computer calls
# apply_profile_update() with it). That happens at every wave start, at the end
# of a game, and right away for the host's own achievements.
# Achievements, best waves and wins per level only count on the Default map and
# the daily and weekly challenges' maps (map_counts() in main.gd); games, kills, play time and
# towers count on any map. Headless runs never write the profile.
#
# For the ui (game_ui.gd): profile_stats(), achievement_list(), pop_achievement()
# (the popup queue) and reset_profile().

const PROFILE_FILE := "user://profile.cfg"
const JOIN_BY := 60  # a win or an endless wave counts only for players in the game by this wave (20% of MAX_WAVE)...
const JOIN_BY_DAILY := 8  # ...and by this wave in the daily challenge
const JOIN_BY_WEEKLY := 20  # ...and in the weekly challenge
const ACHIEVEMENT_GROUPS := ["Levels", "Endless", "Daily", "Weekly", "Abilities", "Towers", "Monsters", "Together"]
# goal: the number the progress bar fills to (0: no bar). counter: what it counts
# (a key in the profile's progress, or one of the keys achievement_progress() works out).
const ACHIEVEMENTS := [
	{"id": "warming_up", "name": "Warming Up", "desc": "Reach wave 30 (any level, not a challenge).", "group": "Levels", "goal": 30, "counter": "best_wave"},
	{"id": "easy_win", "name": "Easy Does It", "desc": "Win on Easy.", "group": "Levels", "goal": 0, "counter": ""},
	{"id": "normal_win", "name": "Holding the Line", "desc": "Win on Normal.", "group": "Levels", "goal": 0, "counter": ""},
	{"id": "hard_win", "name": "Hard Earned", "desc": "Win on Hard.", "group": "Levels", "goal": 0, "counter": ""},
	{"id": "insane_win", "name": "Insane in the Brain", "desc": "Win on Insane.", "group": "Levels", "goal": 0, "counter": ""},
	{"id": "insane_150", "name": "Halfway to Madness", "desc": "Reach wave 150 on Insane.", "group": "Levels", "goal": 150, "counter": "best_insane"},
	{"id": "endless_400", "name": "Endless Night", "desc": "Reach wave 400 in endless mode.", "group": "Endless", "goal": 400, "counter": "endless_best"},
	{"id": "endless_500", "name": "Touch Grass Later", "desc": "Reach wave 500 in endless mode.", "group": "Endless", "goal": 500, "counter": "endless_best"},
	{"id": "endless_600", "name": "No Life", "desc": "Reach wave 600 in endless mode.", "group": "Endless", "goal": 600, "counter": "endless_best"},
	{"id": "daily_win", "name": "Daily Bread", "desc": "Win a daily challenge (beat wave 40).", "group": "Daily", "goal": 0, "counter": ""},
	{"id": "daily_7", "name": "Habit", "desc": "Win daily challenges on 7 different days.", "group": "Daily", "goal": 7, "counter": "daily_days"},
	{"id": "daily_twists", "name": "Twist Master", "desc": "Win a daily with each of the 6 twists.", "group": "Daily", "goal": 6, "counter": "daily_twists"},
	{"id": "weekly_win", "name": "Week Warrior", "desc": "Win a weekly challenge (beat wave 100).", "group": "Weekly", "goal": 0, "counter": ""},
	{"id": "weekly_4", "name": "Regular", "desc": "Win weekly challenges in 4 different weeks.", "group": "Weekly", "goal": 4, "counter": "weekly_weeks"},
	{"id": "meteor_20", "name": "Meteor Shower", "desc": "Kill 20 or more monsters with one Meteor.", "group": "Abilities", "goal": 0, "counter": ""},
	{"id": "freeze_40", "name": "Ice Age", "desc": "Use Freeze all while 40 or more monsters are on the map.", "group": "Abilities", "goal": 0, "counter": ""},
	{"id": "hands_off", "name": "Hands Off", "desc": "Win without using Meteor or Freeze all yourself.", "group": "Abilities", "goal": 0, "counter": ""},
	{"id": "cold_feet", "name": "Cold Feet", "desc": "Win on Normal or harder without building a Frost tower yourself.", "group": "Towers", "goal": 0, "counter": ""},
	{"id": "one_of_each", "name": "One of Each", "desc": "Own all 6 tower types at level 5 or higher at the same time.", "group": "Towers", "goal": 0, "counter": ""},
	{"id": "maxed_out", "name": "Maxed Out", "desc": "Upgrade a tower to level 30.", "group": "Towers", "goal": 0, "counter": ""},
	{"id": "poison_kills", "name": "Plague Doctor", "desc": "Your Poison towers kill 10,000 monsters (all games together).", "group": "Towers", "goal": 10000, "counter": "poison_kills"},
	{"id": "green_thumb", "name": "Green Thumb", "desc": "Win on Hard or Insane with Poison doing the most of your damage.", "group": "Towers", "goal": 0, "counter": ""},
	{"id": "bosses", "name": "Boss Hunter", "desc": "Kill 1,000 bosses (all games together).", "group": "Monsters", "goal": 1000, "counter": "bosses"},
	{"id": "splitlings", "name": "Split Decision", "desc": "Kill 5,000 splitlings (all games together).", "group": "Monsters", "goal": 5000, "counter": "splitlings"},
	{"id": "shields", "name": "Shield Breaker", "desc": "Break 1,000 shields (all games together).", "group": "Monsters", "goal": 1000, "counter": "shields"},
	{"id": "healers", "name": "Medic!", "desc": "Kill 500 healers (all games together).", "group": "Monsters", "goal": 500, "counter": "healers"},
	{"id": "together_100", "name": "Better Together", "desc": "Reach wave 100 with 2 or more players in the game.", "group": "Together", "goal": 0, "counter": ""},
	{"id": "full_house", "name": "Full House", "desc": "Reach wave 50 with 4 players in the game.", "group": "Together", "goal": 0, "counter": ""},
	{"id": "mvp", "name": "MVP", "desc": "Be the MVP of a game with 2 or more players that reached wave 50.", "group": "Together", "goal": 0, "counter": ""},
	{"id": "first_gift", "name": "Sharing is Caring", "desc": "Give gold to another player.", "group": "Together", "goal": 0, "counter": ""},
	{"id": "gifts_50", "name": "Patron", "desc": "Give 50 gifts (all games together).", "group": "Together", "goal": 50, "counter": "gifts_given"},
]
# [stats]: on any map
const PROFILE_STATS := ["games", "wins", "losses", "seconds", "mp_games", "kills", "bosses", "splitlings", "healers",
		"shields", "poison_kills", "gifts_given", "gifts_received", "meteors", "freezes"]
# Counted by the host during a game and sent in profile updates' "add" (also
# built_<type>, kills_<type> and damage_<type>)
const PROFILE_ADDS := ["kills", "bosses", "splitlings", "healers", "shields", "poison_kills", "gifts_given",
		"gifts_received", "meteors", "freezes"]
# [progress]: the counters behind achievements (only on maps that count)
const PROGRESS_KEYS := ["bosses", "splitlings", "healers", "shields", "poison_kills", "gifts_given"]
const PROFILE_INT_MAX := 1000000000000000  # counters stop here (1e15)

var profile := {}  # see new_profile()
var achievement_queue: Array = []  # ids earned and not shown yet (pop_achievement())
var profile_seconds := 0.0  # play time not written into the profile yet (main.gd counts it)


# An empty profile: {stats: {key: n}, levels: [per level {games, best, wins,
# endless}], daily: {played, won, dates, twists}, weekly: {played, won, weeks
# (ids won)}, towers: {type: {built, damage,
# kills}}, progress: {key: n}, achievements: {id: date earned}, chronicle: {story
# card id: date unlocked}}.
func new_profile() -> Dictionary:
	var stats := {}
	for k: String in PROFILE_STATS:
		stats[k] = 0
	var levels := []
	for i in DIFFICULTIES.size():
		levels.append({"games": 0, "best": 0, "wins": 0, "endless": 0})
	var tower_stats := {}
	for type: String in TOWER_TYPES:
		tower_stats[type] = {"built": 0, "damage": 0.0, "kills": 0}
	var progress := {}
	for k: String in PROGRESS_KEYS:
		progress[k] = 0
	return {"stats": stats, "levels": levels, "daily": {"played": 0, "won": 0, "dates": [], "twists": [], "best_streak": 0},
			"weekly": {"played": 0, "won": 0, "weeks": []}, "towers": tower_stats, "progress": progress, "achievements": {},
			"chronicle": {}, "color": -1}


# A whole number from a file or the network (0 for anything else).
func count_of(v: Variant) -> int:
	if v is int:
		return clampi(v, 0, PROFILE_INT_MAX)
	if v is float and is_finite(v):
		return clampi(int(v), 0, PROFILE_INT_MAX)
	return 0


func achievement_ids() -> Array:
	return ACHIEVEMENTS.map(func(a: Dictionary) -> String: return a.id)


# Reads a profile file (missing or broken parts stay empty).
func read_profile(path: String) -> Dictionary:
	var out := new_profile()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	for k: String in PROFILE_STATS:
		out.stats[k] = count_of(cfg.get_value("stats", k, 0))
	for i in DIFFICULTIES.size():
		var d: Variant = cfg.get_value("levels", DIFFICULTIES[i].to_lower(), {})
		if d is Dictionary:
			for k: String in out.levels[i]:
				out.levels[i][k] = count_of(d.get(k, 0))
	out.daily.played = count_of(cfg.get_value("daily", "played", 0))
	out.daily.won = count_of(cfg.get_value("daily", "won", 0))
	for k: String in ["dates", "twists"]:
		var list: Variant = cfg.get_value("daily", k, [])
		if list is Array or list is PackedStringArray:
			for s: Variant in list:
				if s is String and s.length() <= 16 and not s in out.daily[k] and (k == "dates" or DAILY_TWISTS.has(s)):
					out.daily[k].append(s)
	# A profile from before best_streak gets it from its won dates (at least its current streak)
	out.daily.best_streak = maxi(count_of(cfg.get_value("daily", "best_streak", 0)), longest_streak(out.daily.dates))
	out.weekly.played = count_of(cfg.get_value("weekly", "played", 0))
	out.weekly.won = count_of(cfg.get_value("weekly", "won", 0))
	var weeks: Variant = cfg.get_value("weekly", "weeks", [])
	if weeks is Array or weeks is PackedStringArray:
		for s: Variant in weeks:
			if weekly_valid(s) and not s in out.weekly.weeks:
				out.weekly.weeks.append(s)
	for type: String in TOWER_TYPES:
		var d: Variant = cfg.get_value("towers", type, {})
		if d is Dictionary:
			out.towers[type].built = count_of(d.get("built", 0))
			out.towers[type].kills = count_of(d.get("kills", 0))
			var dmg: Variant = d.get("damage", 0.0)
			out.towers[type].damage = maxf(float(dmg), 0.0) if (dmg is float or dmg is int) and is_finite(float(dmg)) else 0.0
	for k: String in PROGRESS_KEYS:
		out.progress[k] = count_of(cfg.get_value("progress", k, 0))
	var ids := achievement_ids()
	if cfg.has_section("achievements"):
		for id: String in cfg.get_section_keys("achievements"):
			var date: Variant = cfg.get_value("achievements", id, "")
			if id in ids and date is String:
				out.achievements[id] = date.left(10)
	# The story cards unlocked (see STORY_CARDS): id = the date
	if cfg.has_section("chronicle"):
		for id: String in cfg.get_section_keys("chronicle"):
			var date: Variant = cfg.get_value("chronicle", id, "")
			if STORY_CARDS.has(id) and date is String:
				out.chronicle[id] = date.left(10)
	# The player's colour (see my_color()); older profiles have none
	var c: Variant = cfg.get_value("player", "color", -1)
	out.color = c if c is int and c >= -1 and c < PLAYER_COLORS.size() else -1
	return out


func write_profile(path: String) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "version", 1)
	for k: String in PROFILE_STATS:
		cfg.set_value("stats", k, profile.stats[k])
	for i in DIFFICULTIES.size():
		cfg.set_value("levels", DIFFICULTIES[i].to_lower(), profile.levels[i])
	for k: String in profile.daily:
		cfg.set_value("daily", k, profile.daily[k])
	for k: String in profile.weekly:
		cfg.set_value("weekly", k, profile.weekly[k])
	for type: String in TOWER_TYPES:
		cfg.set_value("towers", type, profile.towers[type])
	for k: String in PROGRESS_KEYS:
		cfg.set_value("progress", k, profile.progress[k])
	for id: String in profile.achievements:
		cfg.set_value("achievements", id, profile.achievements[id])
	for id: String in profile.chronicle:
		cfg.set_value("chronicle", id, profile.chronicle[id])
	cfg.set_value("player", "color", profile.get("color", -1))
	return cfg.save(path)


# At startup (main.gd).
func load_profile() -> void:
	profile = read_profile(PROFILE_FILE)
	achievement_queue.clear()
	profile_seconds = 0.0


# Writes the profile: at the end of a game, when something is earned, every 10th
# wave and on quit. Never in headless runs (tests can't touch the player's profile).
func save_profile() -> void:
	if profile.is_empty():
		profile = new_profile()
	var whole := int(profile_seconds)
	profile.stats.seconds = mini(profile.stats.seconds + whole, PROFILE_INT_MAX)
	profile_seconds -= whole
	if DisplayServer.get_name() == "headless":
		return
	write_profile(PROFILE_FILE)


# The Profile box's "Reset profile" (after its confirm box): forgets every stat
# and achievement and deletes the file. The name, colour, settings and saves stay.
func reset_profile() -> void:
	var color := my_color()
	profile = new_profile()
	profile.color = color
	achievement_queue.clear()
	story_queue.clear()  # the Chronicle starts over too
	story_end = ""
	profile_seconds = 0.0
	if DisplayServer.get_name() != "headless" and FileAccess.file_exists(PROFILE_FILE):
		DirAccess.remove_absolute(PROFILE_FILE)
		if color >= 0:
			write_profile(PROFILE_FILE)  # a fresh profile that only keeps the colour


# This computer earns an achievement (once): dated today, queued for the popup.
func earn_achievement(id: String) -> bool:
	if profile.is_empty():
		profile = new_profile()
	if profile.achievements.has(id) or not id in achievement_ids():
		return false
	profile.achievements[id] = Time.get_date_string_from_system()
	achievement_queue.append(id)
	return true


# Host: hands a player (not the host) their profile update. Empty here;
# game_net.gd sends it, and that player's computer calls apply_profile_update().
func send_profile_update(_slot: int, _data: Dictionary) -> void:
	pass


# This player's profile update from the host (or from main.gd for the host's
# own part). Checked like anything from the network. All keys are optional:
#   add: {key: n} counters to add (PROFILE_ADDS, built_/kills_/damage_<type>)
#   earned: [ids] achievements the host judged earned
#   counts: this map counts for achievements, best waves and level wins
#   start: a new game for this player (counted once: not again for a loaded game)
#   level (index in DIFFICULTIES), daily (date or ""), weekly (week id or ""),
#   twist, wave, endless
#   there: the player was in the game by JOIN_BY (JOIN_BY_DAILY, JOIN_BY_WEEKLY) wave
#   result: "" while playing, "won", "lost", or "endless_end" (an endless run ended)
#   mp: the game had 2 or more players (with a result)
func apply_profile_update(data: Variant) -> void:
	if not data is Dictionary:
		return
	if profile.is_empty():
		profile = new_profile()
	var counts: bool = data.get("counts") == true
	var level: int = data.get("level") if data.get("level") is int and data.level >= 0 and data.level < DIFFICULTIES.size() else -1
	var daily: String = data.get("daily") if data.get("daily") is String and data.daily.length() <= 16 else ""
	var weekly: String = data.get("weekly") if daily == "" and weekly_valid(data.get("weekly")) else ""
	var w: int = count_of(data.get("wave", 0))
	var there: bool = data.get("there") == true
	var result: String = data.get("result") if data.get("result") in ["won", "lost", "endless_end"] else ""
	var stats: Dictionary = profile.stats
	# Counters
	var add: Variant = data.get("add", {})
	if add is Dictionary:
		for k: Variant in add:
			if not k is String:
				continue
			var n: Variant = add[k]
			if k in PROFILE_ADDS:
				stats[k] = mini(stats[k] + count_of(n), PROFILE_INT_MAX)
				if counts and k in PROGRESS_KEYS:
					profile.progress[k] = mini(profile.progress[k] + count_of(n), PROFILE_INT_MAX)
				continue
			var parts: PackedStringArray = k.split("_", true, 1)
			if parts.size() == 2 and parts[1] in TOWER_TYPES and parts[0] in ["built", "kills", "damage"]:
				var ts: Dictionary = profile.towers[parts[1]]
				if parts[0] == "damage":
					if (n is float or n is int) and is_finite(float(n)) and n > 0:
						ts.damage += float(n)
				else:
					ts[parts[0]] = mini(ts[parts[0]] + count_of(n), PROFILE_INT_MAX)
	# A new game
	if data.get("start") == true:
		stats.games += 1
		if counts and daily != "":
			profile.daily.played += 1
		elif counts and weekly != "":
			profile.weekly.played += 1
		elif counts and level >= 0:
			profile.levels[level].games += 1
	# How far the game got (not in the challenges: they have their own rules)
	if counts and daily == "" and weekly == "" and level >= 0:
		var lv: Dictionary = profile.levels[level]
		lv.best = maxi(lv.best, mini(w, MAX_WAVE))
		if data.get("endless") == true and there:
			lv.endless = maxi(lv.endless, w)
	# The end of a game
	# A win only counts for players in the game early enough (see JOIN_BY)
	if result == "won" and there:
		stats.wins += 1
	elif result == "lost":
		stats.losses += 1
	if result in ["won", "lost"] and data.get("mp") == true:
		stats.mp_games += 1
	if result == "won" and counts and there:
		if daily != "":
			profile.daily.won += 1
			if not daily in profile.daily.dates:
				profile.daily.dates.append(daily)
			profile.daily.best_streak = maxi(profile.daily.best_streak, longest_streak(profile.daily.dates))
			var twist: Variant = data.get("twist")
			if twist is String and DAILY_TWISTS.has(twist) and not twist in profile.daily.twists:
				profile.daily.twists.append(twist)
		elif weekly != "":
			profile.weekly.won += 1
			if not weekly in profile.weekly.weeks:
				profile.weekly.weeks.append(weekly)
		elif level >= 0:
			profile.levels[level].wins += 1
	# Achievements: the host's verdicts, then the counters this computer keeps
	var any := false
	var earned: Variant = data.get("earned", [])
	if earned is Array:
		for id: Variant in earned.slice(0, ACHIEVEMENTS.size()):
			if id is String and earn_achievement(id):
				any = true
	for a: Dictionary in ACHIEVEMENTS:
		if a.goal > 0 and not profile.achievements.has(a.id) and achievement_progress(a) >= a.goal:
			any = earn_achievement(a.id) or any
	if any or result != "" or (w > 0 and w % 10 == 0):
		save_profile()


# How far along an achievement's counter is (0 without one).
func achievement_progress(a: Dictionary) -> int:
	if profile.is_empty():
		profile = new_profile()
	match a.counter:
		"":
			return 0
		"best_wave":
			var best := 0
			for lv: Dictionary in profile.levels:
				best = maxi(best, lv.best)
			return best
		"best_insane":
			return profile.levels[DIFFICULTIES.size() - 1].best
		"endless_best":
			var best := 0
			for lv: Dictionary in profile.levels:
				best = maxi(best, lv.endless)
			return best
		"daily_days":
			return profile.daily.dates.size()
		"daily_twists":
			return profile.daily.twists.size()
		"weekly_weeks":
			return profile.weekly.weeks.size()
	return profile.progress.get(a.counter, 0)


# For the Achievements box: every achievement in order, as {id, name, desc,
# group, earned (date "2026-11-02", or "" when locked), progress, goal (0: no bar)}.
func achievement_list() -> Array:
	if profile.is_empty():
		profile = new_profile()
	var out := []
	for a: Dictionary in ACHIEVEMENTS:
		out.append({"id": a.id, "name": a.name, "desc": a.desc, "group": a.group,
				"earned": profile.achievements.get(a.id, ""), "goal": a.goal,
				"progress": mini(achievement_progress(a), a.goal) if a.goal > 0 else 0})
	return out


# The popup queue: the next achievement to show ({id, name, desc, group, date}),
# taken off the queue, or {} if none is waiting.
func pop_achievement() -> Dictionary:
	while not achievement_queue.is_empty():
		var id: String = achievement_queue.pop_front()
		for a: Dictionary in ACHIEVEMENTS:
			if a.id == id:
				return {"id": id, "name": a.name, "desc": a.desc, "group": a.group, "date": profile.achievements.get(id, "")}
	return {}


# For the Profile box:
#   stats: {games, wins, losses, seconds, mp_games, kills, bosses, splitlings,
#     healers, shields, poison_kills, gifts_given, gifts_received, meteors, freezes}
#   levels: per level [{name, games, best, wins, endless}] (Default map only)
#   daily: {played, won, days (different days won), twists (won with), streak
#     (days in a row won, up to today or yesterday), best_streak (the longest
#     streak so far, kept in profile.cfg)}
#   weekly: {played, won, weeks (different weeks won)}
#   towers: [{type, name, built, damage, share (of all tower damage, 0-1), kills}]
#   favourite: the most built type (ties: more damage), "" before any tower
#   earned, total: achievements earned and how many there are
func profile_stats() -> Dictionary:
	if profile.is_empty():
		profile = new_profile()
	var stats: Dictionary = profile.stats.duplicate()
	stats.seconds += int(profile_seconds)
	var levels := []
	for i in DIFFICULTIES.size():
		levels.append(profile.levels[i].merged({"name": DIFFICULTIES[i]}))
	var total_damage := 0.0
	for type: String in TOWER_TYPES:
		total_damage += profile.towers[type].damage
	var tower_list := []
	var favourite := ""
	for type: String in TOWER_TYPES:
		var ts: Dictionary = profile.towers[type]
		tower_list.append({"type": type, "name": TOWERS[type]["name"], "built": ts.built, "damage": ts.damage,
				"share": ts.damage / total_damage if total_damage > 0.0 else 0.0, "kills": ts.kills})
		if ts.built > 0 and (favourite == "" or ts.built > profile.towers[favourite].built
				or (ts.built == profile.towers[favourite].built and ts.damage > profile.towers[favourite].damage)):
			favourite = type
	var d: Dictionary = profile.daily
	return {"stats": stats, "levels": levels, "towers": tower_list, "favourite": favourite,
			"daily": {"played": d.played, "won": d.won, "days": d.dates.size(), "twists": d.twists.size(), "streak": daily_streak(),
				"best_streak": maxi(d.best_streak, daily_streak())},
			"weekly": {"played": profile.weekly.played, "won": profile.weekly.won, "weeks": profile.weekly.weeks.size()},
			"earned": profile.achievements.size(), "total": ACHIEVEMENTS.size()}


# Daily challenges won on days in a row, ending today or yesterday (UTC).
# The longest run of days in a row in the won dates.
func longest_streak(dates: Array) -> int:
	var days := {}
	for date: String in dates:
		var t := Time.get_unix_time_from_datetime_string(date + "T00:00:00")
		if t > 0:
			days[floori(t / 86400.0)] = true
	var best := 0
	for day: int in days:
		if days.has(day - 1):
			continue  # not the first day of its run
		var n := 1
		while days.has(day + n):
			n += 1
		best = maxi(best, n)
	return best


# dates: the won dates (left out: the profile's).
func daily_streak(dates: Variant = null) -> int:
	var days := {}
	for date: String in (profile.daily.dates if dates == null else dates):
		var t := Time.get_unix_time_from_datetime_string(date + "T00:00:00")
		if t > 0:
			days[floori(t / 86400.0)] = true
	var today := floori(Time.get_unix_time_from_datetime_string(daily_today() + "T00:00:00") / 86400.0)
	var day := today if days.has(today) else today - 1
	var n := 0
	while days.has(day):
		n += 1
		day -= 1
	return n
