# Gettic's first TD

A small 3D tower defense game made with [Godot 4](https://godotengine.org/), inspired by the classic Warcraft III custom tower defense maps.

![Made with AI](https://img.shields.io/badge/made%20with-AI%20%28Claude%29-8A63D2)

The code for this game was written by Claude. Gettic came up with the ideas, made the choices and play-tested it.

![Screenshot of the game](screenshot.png)

Monsters come out of a green portal in a stone gate at a corner of the map, walk onto a square path and walk around it clockwise, forever, until your towers kill them. Build towers on the grass, upgrade them, and don't let too many monsters pile up: if 50 are alive at the same time, you lose. Survive all 30 waves to win.

Play alone or with up to 4 players: each player gets their own gate at a corner of the square (see [Multiplayer](#multiplayer)).

The 3D world is built from simple shapes in code, so the game has no image, model or sound files.

## Download

**Windows:** download the latest `.exe` from the [Releases page](https://github.com/gettic/Gettics-first-TD/releases/latest) (for example `GetticsFirstTD-v1.15.exe`) and run it. No install needed.

The first time it runs, the game warns you and then unpacks itself into a new **Gettic's first TD** folder next to the download (or click **Choose another folder...** to put it somewhere else), with two files named with the version, for example `Gettic's first TD v1.16.exe` (the Godot engine) and `Gettic's first TD v1.16.pck` (the game itself). The downloaded file is deleted afterwards. From then on, start the game from that folder. When the game updates, both files are renamed to the new version.

When the game starts, it checks GitHub for a newer version. If one is out, a **New version – Update** button appears in the side panel. Click it to see what's new and update with one click: the game downloads the new version and restarts by itself. Usually only the small game file needs to be downloaded; the engine is only downloaded again when it changed.

## Run from source

1. Install [Godot 4.7](https://godotengine.org/download) (the standard version, not .NET).
2. Download this repository (**Code → Download ZIP**) or clone it.
3. Open Godot, click **Import**, select the `project.godot` file, and press **F5** to play.

Or from a terminal:

```
godot --path path/to/this/folder
```

## Controls

| Key / mouse | Action |
|---|---|
| **1–4** or click a tower button | Choose a tower to build |
| **Left-click** on grass | Build the chosen tower |
| **Left-click** on a tower | Select it |
| **U** | Upgrade the selected tower |
| **X** / **Delete** | Sell the selected tower (70% refund) |
| **W A S D** | Move the camera |
| **Scroll wheel** | Zoom in and out |
| **Space** | Start the game / send the next wave early (bonus gold, once the current wave has fully spawned) |
| **F** | Change game speed (1×, 2×, 3×; in multiplayer only the host can) |
| **Y** / **N** | Say yes or no when another player asks to build in your area |
| **Right-click** | Cancel |
| **Esc** | Menu: pause / continue, and host or join a multiplayer game |
| **R** | Restart after winning or losing |

## Towers

Each tower has 4 levels.

| Tower | Cost | What it does |
|---|---|---|
| **Arrow** | 50g | Cheap and fast, hits one enemy |
| **Cannon** | 80g | Slow, but damages every enemy near the impact |
| **Frost** | 70g | Low damage, slows enemies down |
| **Spark** | 120g | Lightning that jumps between several enemies |

## Waves

- **30 waves.** Monsters get tougher every wave.
- Press **Space** to start. After that, a new wave comes every **25 seconds**, whether you're ready or not.
- Press **Space** to send the next wave early and get **1 bonus gold for every second** you skip. You can only do this once every monster of the current wave has spawned.
- Every **3rd** wave is **armored**: armor reduces the damage of each hit.
- Every **5th** wave is **fast**.
- Every **10th** wave is a **boss**. A boss counts as 5 monsters toward the limit.

You start with 150 gold. You earn gold for each kill and a bonus at the start of each wave. The side panel shows how many monsters are alive: you lose if it reaches **50** (per player, see below). You win when all 30 waves are out and every monster is dead.

## Multiplayer

Up to 4 players can defend the square together.

- Each player has a **gate at their own corner** of the square: Blue bottom-left, Red top-left, Yellow top-right, Pink bottom-right. Every player's gate sends a full wave, so **more players means more monsters**, and the loss limit grows with it: **50 alive monsters per player** (100 with 2 players, 200 with 4).
- **Each player has their own area**: the quarter of the map around their gate. When you pick a tower to build, your area lights up and the other players' areas go dark. To build in someone else's area, they have to say yes: a box pops up for them (**Y** for yes, **N** for no). Areas of gates nobody plays are free for everyone.
- **Everyone has their own gold.** Every player gets the wave bonus, and the gold for a kill goes to the player whose tower made it. Tower bases are tinted in the owner's color, and you can only upgrade or sell your own towers.
- You can start hosting in the middle of a game and keep your towers. A player who joins late gets some extra gold to catch up. If a player leaves, their gate closes and their towers stay.
- In multiplayer, **Esc doesn't pause** the game.

**How to play together**

1. The host presses **Esc** and clicks **Host a game and get an invite code**.
2. The other players press **Esc**, type the code in the box and click **Join**.

The invite code is 5 letters and digits (like `JR61X`). It works for anyone, anywhere: the game connects through a small game server, so nobody has to change anything in their router.

**Public and private games**

A new game is **private**: only friends with the code can join. The host can click **Public game** in the menu to turn it on, and then the game shows up under **Public games** in everyone's menu (if it isn't full), where anyone can click it to join. Click it again to make the game private again. The list only shows games with your version of the game.

**If the game server can't be reached**

For example with no internet: the game then hosts on your own network instead, still with a 5-letter code, and only friends on the same **Wi-Fi** can join. When you join, the game always looks for the code on your own network first, then asks the game server. The first time you host this way, Windows may ask whether to let the game through the firewall: click **Allow**.

Everyone needs the same game version.

## Changing the game

All the game code is in `main.gd`. Good places to start:

- `TOWERS` at the top sets each tower's cost, damage, range and fire rate.
- `START_GOLD`, `MAX_ALIVE`, `WAVE_INTERVAL` and `MAX_WAVE` set the starting gold, the monster limit (per player), the time between waves and the number of waves.
- `LOOP` sets the square's corners, and `GATES` where each player's gate stands, just outside one corner.
- `PLAYER_NAMES` and `PLAYER_COLORS` set each player's name and color.
- `start_wave()` controls how much health enemies get each wave, and how many come out of each gate.
- `ZOOM_MIN`, `ZOOM_MAX` and `ZOOM_STEP` set how far you can zoom in and out, and how much each scroll notch zooms.
- `build_world()` sets up the 3D scene: camera angle, lighting and map colors. `build_gate()` builds the gates.
- `build_tower_node()` builds each tower's 3D model.
- The **multiplayer** section of `main.gd` has the networking: `RELAY_URL` is the game server's address, and `NET_PORT` and `SEARCH_PORT` are the network ports used for games on your own network.
- The **unpacking** section of `main.gd` splits the downloaded `.exe` into the engine and the game the first time it runs; `GAME_FOLDER` and `GAME_NAME` set the folder's and files' names.
- The game server is a small Cloudflare Worker, kept outside this repository.
