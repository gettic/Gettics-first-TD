# Gettic's first TD

A small 3D tower defense game made with [Godot 4](https://godotengine.org/), inspired by the classic Warcraft III custom tower defense maps.

![Screenshot of the game](screenshot.png)

Enemies walk a spiral path toward a portal in the middle of the map. Build towers on the grass beside the path, upgrade them, and stop the enemies before they get through. Survive all 30 waves to win.

The 3D world is built from simple shapes in code, so the game has no image, model or sound files.

## Download

**Windows:** download the latest `.zip` from the [Releases page](https://github.com/gettic/Gettics-first-TD/releases/latest), unzip it, and run `GetticsFirstTD.exe`. No install needed.

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
| **Space** | Start the next wave |
| **F** | Change game speed (1×, 2×, 3×) |
| **Right-click** / **Esc** | Cancel |
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

- **30 waves.** Enemies get tougher every wave.
- Every **3rd** wave is **armored**: armor reduces the damage of each hit.
- Every **5th** wave is **fast**.
- Every **10th** wave is a **boss**. A boss that reaches the portal costs 5 lives.

You start with 150 gold and 20 lives. You earn gold for each kill and a bonus for each wave you clear.

## Changing the game

All the game code is in `main.gd`. Good places to start:

- `TOWERS` at the top sets each tower's cost, damage, range and fire rate.
- `START_GOLD`, `START_LIVES` and `MAX_WAVE` set the starting values and the number of waves.
- `WAYPOINTS` sets the shape of the path.
- `start_wave()` controls how much health enemies get each wave.
- `build_world()` sets up the 3D scene: camera angle, lighting and map colors.
- `build_tower_node()` builds each tower's 3D model.
