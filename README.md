# Gettic's first TD

A small 3D tower defense game made with [Godot 4](https://godotengine.org/), inspired by the classic Warcraft III custom tower defense maps.

![Screenshot of the game](screenshot.png)

Monsters come out of a portal in the middle of the map, walk out to a square path and walk around it clockwise, forever, until your towers kill them. Build towers on the grass, upgrade them, and don't let too many monsters pile up: if 50 are alive at the same time, you lose. Survive all 30 waves to win.

The 3D world is built from simple shapes in code, so the game has no image, model or sound files.

## Download

**Windows:** download the latest `.zip` from the [Releases page](https://github.com/gettic/Gettics-first-TD/releases/latest), unzip it, and run the game (for example `Gettic's first TD v1.8.exe`). No install needed.

When the game starts, it checks GitHub for a newer version. If one is out, a **New version – Update** button appears in the side panel. Click it to see what's new and update with one click: the game downloads the new version and restarts by itself.

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
| **Space** | Start the game / send the next wave early (bonus gold, once the current wave has fully spawned) |
| **F** | Change game speed (1×, 2×, 3×) |
| **Right-click** | Cancel |
| **Esc** | Pause / continue |
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

You start with 150 gold. You earn gold for each kill and a bonus at the start of each wave. The side panel shows how many monsters are alive: you lose if it reaches **50**. You win when all 30 waves are out and every monster is dead.

## Changing the game

All the game code is in `main.gd`. Good places to start:

- `TOWERS` at the top sets each tower's cost, damage, range and fire rate.
- `START_GOLD`, `MAX_ALIVE`, `WAVE_INTERVAL` and `MAX_WAVE` set the starting gold, the monster limit, the time between waves and the number of waves.
- `SPAWN_PATH` and `LOOP` set the shape of the path: from the portal out to the square, and the square itself.
- `start_wave()` controls how much health enemies get each wave.
- `build_world()` sets up the 3D scene: camera angle, lighting and map colors.
- `build_tower_node()` builds each tower's 3D model.
