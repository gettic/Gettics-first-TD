<p align="center"><img src="assets/logo/logo.png" width="560" alt="Gettic's first TD logo"></p>

# Gettic's first TD

A small 3D tower defense game made with [Godot 4](https://godotengine.org/), inspired by the classic Warcraft III custom tower defense maps.

![Made with AI](https://img.shields.io/badge/made%20with-AI%20%28Claude%29-8A63D2)

The code for this game was written by Claude. Gettic came up with the ideas, made the choices and play-tested it.

![Screenshot of the game](screenshot.png)

Monsters come out of a glowing portal in a crypt gate at a corner of the map, walk onto a square path and walk around it clockwise, forever, until your towers kill them. Build towers on the grass, upgrade them, and don't let too many monsters pile up: if 50 are alive at the same time, you lose. Survive all 300 waves and beat Grimwhistle at the end to win.

Play alone or with up to 4 players: each player gets their own gate at a corner of the square (see [Multiplayer](#multiplayer)). Or draw your own maps in the [Map editor](#map-editor) and share them.

**The art.** The 3D world has a hand-painted look (painted shaders, a golden sun with cool violet shade and a warm rim light on every model, a forest and a lake around the board).

- Free CC0 models from the KayKit packs by Kay Lousberg: rocks and the skeleton mage boss with its walk (repainted in the Bone Choir colours). Painted CC0 grass and dirt textures by Cethiel.
- Made for the game with a model kit: the Cannon, Poison, Frost and Spark towers (a new look at levels 1-5, 10, 15, 20, 30 and 40 for each path) and the skeleton warrior (with its walk and death).
- Made for the game: the Barracks (a guard hall, a stone keep and a wooden camp) and its soldiers (footmen, knights and militia).
- By Gettic: the Arrow tower models, the logo and the game icon.
- Made for the game: the Bone Choir's crypt gate (a skull over iron doors that swing open, with a swirling portal).
- The trees and bushes are built in code with a painted leaf look (5 shapes in 2 greens).
- The music and sound effects were made for the game too (see [Sound and music](#sound-and-music)). Some smaller things are still simple shapes built in code.

All sources are in [assets/CREDITS.md](assets/CREDITS.md).

## Download

**Windows:** download the latest `.exe` from the [Releases page](https://github.com/gettic/Gettics-first-TD/releases/latest) and run it. No install needed.

The first time it runs, the game unpacks itself into a new **Gettic's first TD** folder next to the download (or click **Choose another folder...** to pick one). There it makes two files with the version in their names: a `.exe` (the Godot engine) and a `.pck` (the game itself). The downloaded file is deleted afterwards. From then on, start the game from that folder.

When the game starts, and every 30 minutes while it runs, it checks GitHub for a newer version. If one is out, a **New version – Update** button appears at the top of the screen. Click it to see what's new since your version and update with one click: the game downloads the new version and restarts by itself. Usually only the small `.pck` file is downloaded; the engine only when it changed.

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
| **1–6** or click a tower button | Choose a tower to build (a grid shows on the grass while you place it) |
| **Hover** a tower button | Shows the tower's info card (see [Towers](#towers)) |
| **Left-click** on grass | Build the chosen tower |
| **Left-click** on a tower | Select it |
| **U** | Upgrade the selected tower |
| **Q** / **E** or the 2 path buttons | Upgrade a level 4 tower to level 5 and pick its path (see [Towers](#towers)) |
| **X** / **Delete** | Sell the selected tower (70% refund) |
| **T** or the **Target** button | Change which monster the selected tower shoots (see [Towers](#towers)); not for the Barracks |
| **Shift+T** or **Shift+click** Target | The same, for all your towers of that type |
| **W A S D** | Move the camera |
| **Scroll wheel** | Zoom in and out |
| **Space** | Start the game / send the next wave early for bonus gold (see [Waves](#waves)) |
| **F** | Game speed: 1×, 2×, 3×, 5× (in multiplayer only the host) |
| **Z**, then **left-click** on the map | **Meteor** (see Abilities). **Z** again, **right-click** or **Esc** stops aiming |
| **C** | **Freeze all** (see Abilities) |
| **Y** / **N** | Yes or no when another player asks to build in your area |
| **Enter** | Chat: type, then **Enter** sends (**Esc** cancels). Game keys are off while you type |
| **Alt + left-click** on the map or small map | **Ping** that spot for every player |
| **Right-click** | Cancel |
| **Esc** | Menu: pause, **Profile**, **Map editor**, **Map**, **Daily challenge**, **Weekly challenge**, **Level**, **Leaderboard**, multiplayer, **Save** / **Load** and [Settings](#settings) |
| **Daily challenge** button or **J** in the Esc menu | Start today's [Daily challenge](#daily-challenge) |
| **F11** or **Alt+Enter** | Fullscreen or window (the game remembers your choice) |
| **F5** / **F9** | Quick-save / quick-load (see [Saving and loading](#saving-and-loading)) |
| **R** | Restart after winning or losing |
| **K** | After winning: keep going in endless mode (in multiplayer only the host) |
| **V** | After losing: watch a [replay](#replay) of the last minute |

## Settings

**Settings** in the **Esc** menu opens a box with one row per setting; click a button for the next choice, or click a slider bar to set the volume. The game remembers them.

| Setting | Choices |
|---|---|
| **Graphics** | High or Low. Low turns off some effects and is faster on older PCs (PCs with built-in graphics start on Low) |
| **Window** | Fullscreen or Windowed (also **F11** / **Alt+Enter**). The game starts in fullscreen the first time |
| **3D resolution** | 100, 85, 75 or 50%: lower is faster |
| **Anti-aliasing** | MSAA 2x, MSAA 4x, FXAA or Off |
| **Music** | Slider, 0-100% in steps of 5 (starts at 70%) |
| **Sound effects** | Slider, 0-100% in steps of 5 (starts at 80%) |
| **Tutorial tips** | On or Off. Turning it On again starts the [tips](#tutorial-tips) over |
| **Story cards** | On or Off (see [Story cards](#story-cards-and-the-chronicle)) |
| **Weather** | Random or Always day (from the next game; see [Weather](#weather-and-festivals)) |
| **Festivals** | On or Off (from the next game) |

## Sound and music

The game has music and sound effects, made for the game. The music is a dark orchestral theme in D minor (played with real instrument samples, CC0). It has a calm, a wave and a boss mood and fades from one to the next as the waves come and go. Sound effects cover shots, hits, deaths, abilities, waves, winning and losing, building, buttons, gifts and pings, plus Grimwhistle's entrance, Crescendo and fall, story cards and a short jingle for each festival. Sounds off the screen are quieter. Set the volumes in [Settings](#settings).

## Tutorial tips

New players get short tips: a gold-framed card with an arrow to what it is about (a pulsing gold edge marks a console button). There are 11 tips, shown one at a time and each only once, when it is useful: the first build, where to build, **Space**, upgrading, targeting, the Esc menu, abilities, the monster limit, the level 5 paths, boss waves and the special waves from wave 31.

- **Got it** closes a tip. **Skip all tips** turns them off.
- Tips never pause the game. They are only on your own computer, also in multiplayer.
- They hide while a menu, popup or tooltip is open.
- New installs start with tips On. If you already had a settings file, they start Off. Turn them on in [Settings](#settings).

## Towers

Towers can be upgraded up to level 60. From level 5 on, every level adds 28-36% damage (a bit different for each level and tower), and every 5th level (5, 10, 15...) is a big one with 62-70%. Range, fire rate, splash, slow and chain also grow a little, up to a limit. Each upgrade costs 38% more than the last (80% more for the big levels), so very high levels get too expensive to reach.

**Looks.** The Arrow, Cannon, Frost, Spark and Poison towers get a new model at levels 1-5, 10, 15, 20, 30 and 40 (all but Arrow a different one for each path; a Volley Arrow tower has three archers). Frost is a rune spire with a floating crystal: Deep Freeze cages it, Blizzard rings it with shards. Spark is an arcane conductor with copper coils and a glowing orb in a crown of prongs, with Storm and Overload looks. The Barracks has its own look at levels 1-4 (more crates, a tower, a chimney and walls), and a new one at levels 5, 10, 15, 20, 30 and 40 for each path: a stone keep for Knights, a wooden camp for Militia. Every tower above level 4 shows a small "Lv" badge, and big numbers are shortened (240k, 1.2M).

| Tower | Cost | What it does |
|---|---|---|
| **Arrow** | 50g | Cheap and fast, hits one enemy |
| **Cannon** | 80g | Slow, but damages every enemy near the impact |
| **Frost** | 70g | Less damage, but slows enemies down |
| **Spark** | 120g | Lightning that jumps between several enemies |
| **Poison** | 90g | Lobs a glob that leaves a green cloud on the path for 3 seconds (see below) |
| **Barracks** | 90g | Soldiers on the path hold monsters still and hit them (see below) |

**Info cards.** Hover a build button (or its row in the build list) to see the tower's card: cost, damage per second, range and speed (with bars), its special, what it is good and weak against, the total cost and numbers at level 4, and both level 5 paths with their numbers.

**Poison clouds.** Every monster inside takes damage over time (4 times a second), and poison goes through armor. Cloud size grows with the level. A monster is hurt by only one cloud of each tower at a time, but different Poison towers add up.

**Barracks.** It must stand within its range of the path (the build ghost turns red where no path is in reach). Its soldiers stand on the path tile nearest to it, marked by a small flag, and each holds one monster still and hits it. At level 1 there are 2 soldiers and a hold lasts 1.5 seconds. Monsters wear soldiers down, and a fallen soldier comes back after a while (8 seconds at level 1). A monster that was let go can't be held again for 1.5 seconds. Held monsters still count toward the limit, and only Knights hold bosses. The halls stay inside their own tile however they are turned. Soldiers fight the nearest monster, so the Barracks has no Target button. Hurt soldiers show a small health bar in their owner's color. Its info card shows damage per soldier and a Soldiers row. In multiplayer everyone sees the host's soldiers, and saves keep their health.

**Specializations.** The upgrade from level 4 to 5 picks one of the tower's 2 paths: with a level 4 tower of yours selected, the tower buttons turn into its 2 paths (**Q** and **E**, price and a short text; hover for the numbers). **U** only reminds you to pick. The path is for good: selling is the only way back. Both paths cost the same, and the tower panel shows its path's name. Each path multiplies the tower's normal numbers from level 5 on, and some extras grow at levels 20 and 40:

| Tower | Path | Good against | What it does |
|---|---|---|---|
| Arrow | **Sniper** | Bosses, armored | Damage ×1.6 (×2 more against bosses), fires half as often, range ×1.25, faster arrows. Starts on Strongest |
| Arrow | **Volley** | Crowds | Shoots 3 monsters at once (4 at level 20, 5 at 40), each arrow ×0.5 damage |
| Cannon | **Big Bomb** | Bosses, packs | Damage ×2 (×1.5 more against bosses), fires 1.6× slower, blast ×1.3 |
| Cannon | **Cluster** | Crowds, long lines | Plus 3 bomblets (4 at 20, 5 at 40) on monsters near the blast, each a small blast with full damage. Each monster is hit only once per shot |
| Frost | **Deep Freeze** | Holding monsters | Damage ×2, 25% chance to freeze a monster for 1 second (32% at 20, 40% at 40; bosses half as long). After a freeze, a monster can't be frozen again for 2 seconds |
| Frost | **Blizzard** | Area slow | Hits and slows every monster within 60 of the target (80 at 20, 100 at 40), damage ×0.35 |
| Spark | **Storm** | Crowds | Chains to 3 more monsters, each jump keeps 90% of the damage (instead of 80%) and reaches further, damage ×0.9 |
| Spark | **Overload** | Bosses | Damage ×2 (×2 more against bosses), fires 1.2× slower, chains to only 2 monsters. Starts on Strongest |
| Poison | **Venom** | Bosses, armored | Damage ×1.9 (×1.75 more against bosses), clouds ×0.7 the size. Starts on Strongest |
| Poison | **Miasma** | Crowds, support | Clouds ×1.5 the size that last ×1.5 as long. Monsters inside take 15% more damage from every tower (20% at level 20, 25% at 40) |
| Barracks | **Knights** | Bosses, tough monsters | Damage ×1.6 (×3 more against bosses), soldier health ×2.5, holds ×1.5 as long and also holds bosses |
| Barracks | **Militia** | Crowds | 2 more soldiers (3 at level 20, 4 at 40), twice the reach, back twice as fast, damage ×0.6, soldier health ×0.7 |

**Targeting.** Each tower has a targeting mode that says which monster in range it shoots. Change it with **T** or the **Target** button in the tower panel (only on your own towers). **Shift** changes all your towers of that type at once. New towers start on **First**.

| Mode | Shoots |
|---|---|
| **First** | The monster that has walked furthest. The path loops forever, so this is the oldest one, which has counted toward the limit the longest |
| **Last** | The monster that has walked the least (the newest, near the gates) |
| **Strongest** | The monster with the most health left |
| **Fastest** | The fastest monster right now (slowed ones count as slow, so Frost on Fastest goes for the ones that aren't slowed yet) |
| **Closest** | The monster nearest to the tower |

When two monsters are equal, the one that has walked furthest is picked. The Barracks has no targeting mode.

## Waves

- **300 waves.** Monsters get tougher every wave: health grows fast up to wave 25, then by 2.5% a wave. Each gate sends one more monster per wave, up to 32.
- Press **Space** to start. After that, a new wave comes every **25 seconds**, whether you're ready or not.
- Press **Space** to send the next wave early and get **bonus gold for every second** you skip (the wave's gold spread over 25 seconds, at least 1 a second). You can only do this once every monster of the current wave has spawned. In multiplayer it's a vote (see [Multiplayer](#multiplayer)).
- Every **3rd** wave is **armored**: armor reduces the damage of each hit, and it grows with the monsters' health.
- Every **5th** wave is **fast**.
- Every **10th** wave is a **boss** wave (up to 5 bosses, each with 18 times the health). A boss counts as 5 monsters toward the limit. Sniper, Big Bomb and Overload hit bosses harder.
- **Special monsters** from wave 31 on (also in endless mode and the daily challenge, on every level). The gold for a wave stays the same:
  - Waves ending in **1**: **splitters** (55% health, purple with a second skull). When one dies it breaks into **2 small purple ones** (25% health each, 25% faster, same armor), each counting toward the limit. Splash, clouds and chains deal with them best.
  - Normal waves ending in **4** (not armored ones): every monster carries a **shield** worth 20% of its health, shown as a glowing blue bubble that bursts when it breaks. The shield takes hits first, before armor (Meteor too), and slowly grows back after 5 seconds without being hit. Boss waves 200, 220, 240... get shields too (10%).
  - Waves ending in **7**: every 6th monster is a **healer** (80% health, golden with a halo). Every 2.5 seconds it sends out a golden ring and heals the monsters near it by 4% of their health (bosses 1.5%). Kill it first.
- **Wave 300: Grimwhistle, the Bone Conductor** (not in the daily or weekly challenge). Every gate sends him first, then 4 bosses.
  - He is a boss with 1.5× a boss's health and shield, speed 0.6 and 2× boss gold. He always shows a wide health bar with his name.
  - Every 10 seconds (the first after 6) he plays a **Crescendo**: monsters within 160 of him, himself too, lose slows and freezes, soldiers let go of them, and they walk 1.4× faster for 3 seconds.
  - Knights hold him half as long as a boss, and he wears soldiers down twice as fast.
  - When every Grimwhistle has fallen, the monsters left crumble (no gold) and you win.
- **Wave preview:** under the wave number in the console, three small chips show the next 3 waves: the monster kind (by color and mark: speed lines for fast, a steel rim for armored, a crown for a boss), how many come (all gates together), and a blinking red **BOSS** chip before a boss wave. A special wave has a round badge on its chip (two blobs for splitters, a shield, or a cross for healers). Hover a chip for what's coming. The seconds until the next wave are at the right of the wave number, with a thin gold bar under the first chip.
- **The monsters:** wave 1 is **unicorns**. After that, normal monsters are bone warriors with sword and shield, armored ones are bigger, steel-tinted bone warriors, fast ones are bone spiders and bosses are big skeleton mages. The skeletons are the Bone Choir: ivory bone, violet cloth, verdigris bronze and glowing soul-green eyes. Slowed monsters look icy, frozen ones stand in ice, and poisoned ones turn sickly green. Health bars show once a monster is hurt.

You start with 150 gold (225 on Easy). You earn gold for each kill and a bonus at the start of each wave; both grow with the monsters' health (playing alone, kills pay about 15% more later on). The console at the bottom shows how many monsters are alive: you lose if it reaches **50** (per player, see below). You win when Grimwhistle has fallen and the monsters left are gone (there are fireworks).

**Endless mode.** After winning, press **K** to keep going: the waves never stop and the score is how far you get. Past wave 300, monster health grows by **4% a wave** (instead of 2.5%), so even maxed towers fall behind somewhere around wave 550-650. The win still counts as a win; the endless run's own stats show when it's lost.

**Abilities.** Two free abilities, each with its own cooldown (counted in game time, so a faster game speed doesn't make them weaker). They work from wave 1 on.

| Ability | Key | Cooldown | What it does |
|---|---|---|---|
| **Meteor** | **Z**, then click | 60 s | Hits every monster within 90 (about 2 tiles) of the spot for 8 times a normal monster's health in this wave (and level), ignoring armor: it kills normal monsters and takes almost half off a boss |
| **Freeze all** | **C** | 90 s | Every monster on the map stands still for 3 seconds (bosses 1.5). Afterwards they can't be frozen by Deep Freeze for 2 seconds |

**Stats at the end.** When the game is lost (after a moment) or won (after 3 seconds of fireworks), a panel shows each player's kills, damage, gold earned (wave gold, early bonus and kills) and gold spent on towers (minus what selling gave back), and the 5 towers that did the most damage (sold towers count too). Damage counts only the health a hit really took off. In multiplayer the **MVP** is the player who did the most damage (kills break a tie).

**Levels.** Before wave 1, pick how hard the game is in the **Esc** menu (playing alone, or the host in multiplayer). Gold from waves and kills is the same on every level, so tougher monsters also mean less gold for their health.

| Level | Monster health | Start gold |
|---|---|---|
| **Easy** | ×0.6 | 225 |
| **Normal** | ×1 | 150 |
| **Hard** | ×1.4 | 150 |
| **Insane** | ×2 | 150 |

## Replay

After losing, press **V** on the stats screen to watch the **last minute** again and see what went wrong. It starts a few seconds before the monster count began climbing for good. Towers are shown as they are at the end, and monsters that got past your towers (walked a whole lap) glow red.

The timeline shows how many monsters were alive (red near the limit), where each wave started, and how many monsters got past.

| Key | In the replay |
|---|---|
| **Space** | Pause / play |
| **←** / **→** | Jump 5 seconds back / forward |
| **F** | Speed: 0.5×, 1×, 2×, 4× |
| **Click** or **drag** the timeline | Jump anywhere |
| **W A S D**, scroll wheel | Move the camera |
| **V** or **Esc** | Back to the stats |
| **R** | Play again |

In multiplayer each player watches what their own game showed (nothing extra is sent).

## Daily challenge

Every day (by UTC time) everyone gets the same challenge. To start it, click **Daily challenge** in the **Esc** menu (or press **J**), playing alone or as the host before wave 1 while nobody has joined. Each day has:

- **Its own map**, made from the date (the same on every computer, no download needed).
- **40 waves** to win (no endless mode), on **Normal** or (one day in three) **Hard**. The level can't be changed.
- **One twist**:

| Twist | What changes |
|---|---|
| **Rich start** | Twice the start gold |
| **Swarm** | 50% more monsters a wave (not more bosses), with 35% less health |
| **Two towers** | Only two of the six tower types can be built (never only Frost and Barracks) |
| **No selling** | Towers can't be sold |
| **Armored day** | Normal waves are armored |
| **Tight budget** | 30% less kill gold, 30% more wave gold |

Picking another map ends the challenge; **R** after the end plays the same day again.

Your daily wins in a row are your **streak**; the [Profile](#profile-and-achievements) shows it and your best one.

## Weekly challenge

A longer challenge, the same for everyone for one week (Monday to Sunday, by UTC time). Start it with **Weekly challenge** in the **Esc** menu (under **Daily challenge**), playing alone or as the host before wave 1 while nobody has joined. The menu tip shows the week, its twists and the time left. Each week has:

- **Its map**: one of the 5 built-in maps or a map made for that week. Each comes once every 6 weeks, and never the same one two weeks in a row.
- **100 waves** to win (no endless mode), always on **Hard**. The level can't be changed.
- **Two twists** from Armored day, No selling and Tight budget (see [Daily challenge](#daily-challenge)).
- **Rising tide:** from wave 31, monster health grows 1% a wave on top of the normal growth (×1.70 at wave 100). The gold stays the same.

A "WEEKLY" banner shows while you play it. A player who joins late counts for the win up to wave 20. Weekly games never count for the best waves and wins per Level. Winning a week gives the **Week Warrior** medal, and winning 4 different weeks gives **Regular**. Your weekly games show in the [Profile](#profile-and-achievements) and have their own tab on the [Leaderboard](#leaderboard).

## Weather and festivals

**Weather.** Every new game gets a time of day or weather: day, evening, night, rain, fog or snow. It changes the light, the sky and the ground, and adds rain, snow, falling leaves, mist or gate torches. It is picked at random. In the daily and weekly challenges it is the same for everyone that day or week. In multiplayer everyone sees the host's weather. Set **Weather** to *Always day* in [Settings](#settings) to turn it off (the map editor is always day).

**Festivals.** On some dates the world dresses up. It is looks only, and each computer uses its own date:

| Festival | Dates | Looks |
|---|---|---|
| **Frostfall Fair** | Dec 18 - Jan 1 | Snow on trees and rocks, garlands on the gates, string lights on towers, scarves on soldiers |
| **Lantern Night** | Oct 24 - Nov 1 | Glowing pumpkins on towers, gates and the board's edge, fireflies, pumpkin hats on bone warriors |
| **Spring Paint Day** | 3 days before to 3 days after Easter | Pastel bunting and eggs, painted gates, monsters burst into paint |

A ribbon with the festival's name shows for the first 8 seconds of a new game, and each festival has a short jingle. Turn them off with **Festivals** in [Settings](#settings).

## Story cards and the Chronicle

The game tells a small story in 11 short **story cards**: your first game, your first daily challenge, wave 1, your first boss, waves 31, 100, 150, 200 and 300, and your first win and first loss. Each card shows once, ever, as a parchment page at the top of the map with the speaker's name. It fades out after 12 seconds (it waits while the mouse is on it).

- **Got it** closes a card. **Turn off story** turns off story cards only (not the tips). Change it any time with **Story cards** in [Settings](#settings).
- Cards never pause the game and are only on your own computer. There are none in the weekly challenge, the replay or the map editor, and in the daily challenge only the daily one.
- The [Profile](#profile-and-achievements) has a **Chronicle** button with every page you found, and "???" with a hint for the rest.

## Profile and achievements

Press **Esc** and click **Profile** (top left) to see your stats. They are your own, kept on your computer in `profile.cfg` (apart from the settings).

- **Colour:** next to your name is a row of 8 colour swatches (Blue, Red, Yellow, Green, Orange, Cyan, Pink, Black). Click one to pick your player colour (see [Multiplayer](#multiplayer)).
- **Profile:** your name, games played, won / lost, time played, multiplayer games, monsters, bosses and gifts, Meteors and freezes, the best wave per Level (with wins, best endless wave and games), a **Daily** row (played, won, streak and best streak, twists), a **Weekly** row (played, won, weeks won), the **Chronicle** (found story pages) and, for each tower, how many you built and its share of the damage, with your favourite lit up. **Reset profile** asks first and deletes only the profile (not your name, settings or saves).
- **Achievements:** 31 medals in 8 groups (**Levels, Endless, Daily, Weekly, Abilities, Towers, Monsters, Together**). Tabs pick a group (**Left** / **Right** too). Earned medals show their date; the rest are dark "?" cards with a progress bar. Scroll with the wheel or **Page Up / Down**.
- A new medal slides in under the top bar for 4 seconds (it waits while a menu is open).

Rules:

- Achievements, best waves and wins per Level only count on the **Default map** and the daily challenge's map (the other built-in maps count as custom maps). Games, kills, time and towers count on any map.
- A win or an endless wave only counts if you were in the game by wave 60 (wave 8 in a daily, wave 20 in a weekly).
- A loaded game adds to your stats, but doesn't count as a new game.

## Saving and loading

Playing alone, or as the host, you can save a game and go on with it later.

- **Save** in the **Esc** menu keeps the game under a name (it suggests one like *Wave 37 - Normal - Default*; the same name asks before it's overwritten). **Load** shows your saves, newest first, with their wave, level, map and players, and **Delete**. **F5** quick-saves and **F9** loads the quick-save.
- **Continue:** the game also saves itself at the start of every wave and when you close it, in the **Continue** save at the top of the list.
- Everything is saved: the map (your own maps too, so the save works even if you change or delete the map), the level, wave and timer, endless mode, the daily or weekly challenge, the weather, every player's gold and ability cooldowns, every tower, the monsters on the map (with their shields, poison and the rest) and the stats for the end screen. Shots in the air and the replay aren't. A save is a few KB, in the game's user folder (saves\<name>.sav).
- A loaded game starts **on hold**: nothing moves until you press **Space**, so you can look around first.
- **A loaded game never goes on a leaderboard** (normal, endless, daily or weekly), since loading again after a bad wave would make the boards meaningless. **R** after it ends starts a fresh game that counts again.
- Only working saves load: a broken one, or one from a newer version of the game, is refused with a message.

## Leaderboard

The **Leaderboard** button in the Esc menu shows the online top 10. Tabs at the top pick the list:

| Tab | What's on it |
|---|---|
| **Normal game** | Games on the Default map, one board per Level. Highest wave first, then won before lost, then the shortest game time |
| **Endless** | Runs kept going after a win (**K**) on the Default map, one board per Level. Highest wave first |
| **Daily challenge** | The day's challenge, a new board every day |
| **Weekly challenge** | The week's challenge (100 waves, Hard), a new board every week. Highest wave first, then won before lost, then the shortest time |

The box opens on the list and Level of the game you're playing; the Level tabs (or **←** / **→**) show the others. Each team (the same player names) has one entry, its best game, and your own best shows under the list.

When a game ends, the host sends the team's names and how the game went (wave, result, game time) to the game server. Only the released game sends scores: test runs and debug builds never do. Other maps (the other built-in ones too) and loaded games don't count.

## Map editor

Playing alone, press **Esc** and click **Map editor** to make your own maps (if a game is going, it asks first, since the editor ends it). The map shows in 3D as you draw it:

- **Path** paints path tiles, **Erase** (or the right mouse button) turns tiles back into grass. Hold the mouse button and drag to paint several tiles.
- **Gate** places a gate: press **1-4** (or click the button again) to pick which one. A gate stands at the end of its own road to the loop.
- **Rock**, **Tree** and **Water** block building (rocks and trees are 3D models, water is a lake with moving waves). **Areas** shows each player's area, **Clear** (click twice) makes the whole map grass.
- **Width** and **Height**: from 12 x 9 up to 48 x 36 tiles.
- The **Check** panel always shows whether the map works: the path must be one closed loop, one tile wide, that doesn't touch itself, with at least 8 tiles; gate 1 is needed and gates are numbered without gaps (up to 4, one per player). Monsters always walk the loop clockwise. Very uneven player areas only give a yellow warning.
- **Save** keeps the map under its name (in the game's user folder, maps\<name>.txt). **Load...** opens a saved map or a copy of a built-in map (they can't be changed; a built-in name can't be saved over, and an older saved map with such a name shows as `<name> (yours)`). **New** starts over.
- **Play this map** starts a game on it, **Exit the editor** goes back to the map you played before. Only working maps can be saved, shared or played.

**Picking a map:** in the **Esc** menu, click the **Map:** button under the title to choose a built-in map or one of your saved maps. You can do this playing alone or as the host, before wave 1. While hosting, the map can only change while nobody has joined yet. Saved maps are checked again every time they're loaded.

The map also decides how many can play: **one player per gate** (a map with 2 gates is full with 2 players). Multiplayer games use the host's map; see [Multiplayer](#multiplayer) for how joining players get it.

### Built-in maps

The game comes with 5 maps, shown first in the map lists and marked "(built in)": **Default**, **Serpent** (a long winding road), **Twin Lanes** (two long lanes with a lake strip between), **Hourglass** (two rooms joined by a narrow waist) and **Four Roads** (long roads from the corners into a small loop around a lake). All have 4 gates. They can't be changed, and only Default counts for the leaderboard and achievements.

### Sharing maps

- **Share** (in the editor, or the share button next to a map in the map lists) copies the map's **map code** and shows it as a **QR code**. A map code is text starting with `GTD1`, so it can be sent in any chat. A map too big for a QR code can still be sent as text.
- To use a map code, copy it, then click **Paste map code** in a map list or press **Ctrl+V** (in the map lists or the editor).
- A pasted map is checked like any map, then shown in a preview with its name, size, gates and trees, rocks and water. **Save to my maps** keeps it (a name you already use gets " (2)"; a map you already have isn't saved twice), **Play it** plays it right away, **Cancel** leaves everything as it was.
- Only the map's tiles are in a code, never files.

## Multiplayer

Up to 4 players can defend the map together: one player per gate on the map (the built-in maps have 4).

- Each player has **their own gate**: on the Default map one at each corner of the square. Until a player picks a colour, the gates are Blue bottom-left, Red top-left, Yellow top-right, Green bottom-right. Every player's gate sends a full wave, so **more players means more monsters**, and the loss limit grows with it: **50 alive monsters per player** (100 with 2 players, 200 with 4).
- **Each player has their own area**: the part of the map nearest to where their gate's road joins the loop (on the Default map, the quarter around their gate). When you pick a tower to build, your own area goes dark and the other players' areas light up in their color. To build in someone else's area, they have to say yes: a box pops up for them (**Y** for yes, **N** for no). Areas of gates nobody plays are free for everyone.
- **Sending a wave early is a vote**: pressing **Space** votes for it, and the wave comes once at least **75% of the players** agree (2 of 2, 3 of 3, or 3 of 4). The button shows the votes, like `2/3`. Press **Space** again to take your vote back. Starting the first wave doesn't need a vote.
- **Everyone has their own gold.** Every player gets the wave bonus, and the gold for a kill goes to the player whose tower made it. Tower bases are tinted in the owner's color, and you can only upgrade or sell your own towers.
- **Player colours:** everyone picks their own colour in the [Profile](#profile-and-achievements), from 8: Blue, Red, Yellow, Green, Orange, Cyan, Pink and Black. It is kept in `profile.cfg` and sent to the host when you join. No two players can have the same colour: colours another player has are dimmed and crossed out (hover one to see who has it), and a refused pick says why. If you join with a colour that is taken, you get the first free one, and your own pick once it frees up. Your colour shows on your gate, towers, soldiers, banners, names, chat, pings, the small map and the stats, and changes for everyone right away. Black shows as silver in text and with a light edge so it can be seen at night. Saves keep the colours.
- **Gifts:** you can give a teammate 10%, 25% or 50% of your gold (once every 2 seconds). Everyone sees it in the chat, and the stats at the end show each player's gifts (got minus given) apart from gold earned and spent.
- **Pings:** **Alt + click** on the map or the small map marks a spot for everyone for 4 seconds (a few pings at once, then one every 2 seconds).
- You can start hosting in the middle of a game and keep your towers. A player who joins late gets some extra gold to catch up. If a player leaves, their gate closes and their towers stay.
- **Everyone has their own abilities**: each player's Meteor and Freeze all have their own cooldowns (the host checks them). After a win, **only the host** can choose to keep going in endless mode.
- **The host picks the Level** (before wave 1), for everyone: the other players see it, also when they join later, and a won or lost game goes on that level's leaderboard.
- **The stats at the end** are counted by the host and sent to everyone once when the game ends, so all players see the same numbers (a player who left still shows up; a player who joins a slot later starts fresh).
- **Profile:** the host counts achievements and stats for everyone and sends each player their update at every wave start and at the end of the game (see [Profile and achievements](#profile-and-achievements)).
- In multiplayer, **Esc doesn't pause** the game.
- **Challenges and weather:** players who join get the host's daily or weekly challenge (the weekly only on that week's map) and see the host's weather. Grimwhistle's Crescendo shows for everyone.
- **Saving:** only the host saves. To go on with a multiplayer save, the host loads it (alone, or hosting before anyone has joined) and invites everyone again. The game waits on hold, showing who it's waiting for. A player who joins gets their old place back: the one saved under their name, or else the first one nobody has taken, with its gold and towers. The host presses **Space** to go on; places nobody took keep their towers (still shooting) and gold, their gate stays closed, and their player can still join later.
- **Names and chat:** type your name in the **Your name** box in the **Esc** menu (up to 16 letters; the game remembers it). Leave it empty and you get a random silly name, like *Sir Wobbles* or *Captain Noodle*. Two players with the same name get a number added. Press **Enter** to chat: messages show above the small map in the bottom-left, in each player's color, and fade after a few seconds.

**How to play together**

1. The host presses **Esc** and clicks **Host a game and get an invite code**.
2. The other players press **Esc**, type the code in the box and click **Join**.

**Playing on your own map**

The host picks the map in the **Esc** menu before inviting anyone (see [Map editor](#map-editor)); once someone has joined, the map stays until the game is over.

A player who doesn't have the host's map yet gets a **Join game** box first: a preview of the map, its name, size, gates and trees, rocks and water. Nothing is saved until they click **Download and join**; **Cancel** (or **Esc**) leaves everything as it was. Only the map's tiles come over (under 2 KB), never files, and the game checks them like the map editor does, so a broken map is refused with a message. Tick **Keep this map in my map list** to save it among your own maps (a name you already use gets " (2)").

Players who already have the same map, and games on any built-in map, skip the box. After leaving the game, you're back on your own map.

The invite code is 5 letters and digits (like `JR61X`). It works for anyone, anywhere: the game connects through a small game server, so nobody has to change anything in their router.

**Public and private games**

A new game is **private**: only friends with the code can join. The host can click **Public game** in the menu to turn it on, and then the game shows up under **Public games** in everyone's menu (if it isn't full), where anyone can click it to join. Click it again to make the game private again. The list only shows games with your version of the game.

**If the game server can't be reached**

For example with no internet: the game then hosts on your own network instead, still with a 5-letter code, and only friends on the same **Wi-Fi** can join. When you join, the game always looks for the code on your own network first, then asks the game server. The first time you host this way, Windows may ask whether to let the game through the firewall: click **Allow**.

Everyone needs the same game version.

## Changing the game

The game code is split into a few files, each building on the one before:

| File | What's in it |
|---|---|
| `game_base.gd` | All the settings (constants) and the game's shared state, the tutorial tips (`TIPS`) and the achievements (`ACHIEVEMENTS`) |
| `game_updates.gd` | Checking for updates, unpacking the downloaded `.exe`, and the debug log window |
| `game_audio.gd` | Music and sound effects |
| `game_world.gd` | The 3D world: map, gates, trees, tower and monster models, shots and effects |
| `game_net.gd` | Multiplayer: hosting, joining, invite codes, public games, the leaderboard |
| `game_ui.gd` | The bottom console (small map, tower portrait, command buttons, wave preview), the tower info cards, the tutorial tip card, the Esc menu and its boxes (settings, profile, achievements, leaderboard, save / load), the end stats and the replay timeline |
| `map_editor.gd` | The map editor, saved maps, picking a map, and the share and pasted-map boxes |
| `main.gd` | The game itself: waves, monsters walking, towers shooting, keys and clicks, tips, saving and the replay |

`map_share.gd` isn't in that chain: it turns maps into map codes and QR codes (`map_to_code()`, `code_to_map()`, `qr_grid()`), and the game loads it with `preload()`.

Good places to start:

- `TOWER_BASE` in `game_base.gd` sets each tower's cost, damage, range and fire rate for levels 1-4. `LEVEL_GAIN`, `LEVEL_COST` and the other `LEVEL_` values set how the levels after that grow (`make_towers()` works them out). `PATHS` sets the 2 specializations of each tower (their numbers times the normal ones from level 5 on); their rules are in `update_towers()`, `fire_lightning()` and `shot_hit()` in `main.gd`. Poison clouds: `CLOUD_TIME` and `CLOUD_TICK` in `game_base.gd`, their rules in `update_clouds()` in `main.gd`.
- Barracks: `TOWER_BASE["barracks"]` and `PATHS["barracks"]` (Knights, Militia) in `game_base.gd`, with `ENGAGE_R`, `HOLD_IMMUNE`, `SOLDIERS_MAX` and `SOLDIER_HURT` next to them. The rules are in `update_barracks()` in `main.gd`. The helpers `rally_point()`, `barracks_fits()`, `soldier_bytes()`, `barracks_info()` and `apply_barracks_info()` are in `game_base.gd` (the multiplayer snapshots and the replay carry `barracks_info()`). `show_soldiers()` in `game_world.gd` draws the soldiers.
- `wave_special()` in `game_base.gd` says which waves have splitters, shields or healers; their numbers are the `SPLIT_`, `HEAL_`, `HEALER_` and `SHIELD_` values next to it, their rules in `spawn_enemy()`, `split_enemy()`, `update_enemies()` and `damage_enemy()` in `main.gd`.
- `BOARD_SEASON` in `game_net.gd` (now 6) is part of the leaderboard's name: raise it after a balance change, so new scores aren't mixed with old ones.
- `weekly_rules()`, `weekly_tide()` and `weekly_map_pick()` in `game_base.gd` set the weekly challenge, with the `WEEKLY_` values (`WEEKLY_WAVES`, `WEEKLY_LEVEL`, `WEEKLY_TWIST_COUNT`, `WEEKLY_NO_TWISTS`, `WEEKLY_TIDE_FROM`, `WEEKLY_TIDE`, `WEEKLY_MAPS`) next to them; `start_weekly()` in `main.gd` starts it and `net_set_weekly()` in `game_net.gd` sends it to joiners. Raise `WEEKLY_VERSION` when its map pick or rules change.
- Weather: `MOODS` and `apply_mood()` in `game_world.gd` (the light, sky and effects of each mood); `pick_mood()` in `main.gd` picks one for each new game.
- Festivals: `FESTIVALS` and `festival_today()` in `game_base.gd` (the dates), `apply_festival()` in `game_world.gd` (the looks). In a debug build, start with `-- --festival=frostfall` (or `lantern`, `paint`, `none`) to see one.
- Story cards: `STORY_CARDS` and `STORY_WAVES` in `game_base.gd` (the texts and when they show), `story_unlock()` there saves a page in `profile.cfg`, and `update_story()` in `main.gd` decides when a card shows.
- Grimwhistle: the `GRIM_` and `CRESCENDO_` values and `grimwhistle_wave()` in `game_base.gd`; his rules are `crescendo()` and `check_grimwhistle()` in `main.gd`; his model is `add_grim()` in `game_world.gd`. `net_show_crescendo()` in `game_net.gd` shows the Crescendo to the other players.
- The gates: `gate_model()` and `build_gate()` in `game_world.gd` (the model is `assets/gates/gate.glb`, the portal `assets/shaders/gate_portal.gdshader`); `GATE_W` is the gate's width. `BARRACKS_REACH` sets how far a Barracks hall may reach inside its tile.
- `GAME_SPEEDS` in `game_base.gd` are the speeds the **F** button goes through.
- Saves: `save_game()` / `load_game()` in `main.gd`. A new tower or monster field is saved by adding its name to `SAVE_TOWER_FIELDS` / `SAVE_ENEMY_FIELDS` there (older saves keep the default). Raise `SAVE_FORMAT` in `game_base.gd` only when a save's layout changes in a way old saves can't follow.
- `wave_hp()`, `wave_count()`, `wave_income()` and `wave_bounty()` in `game_base.gd` set each wave's monster health, how many come out of each gate, the wave gold and the gold per kill.
- `DIFFICULTIES`, `DIFFICULTY_HP` and `DIFFICULTY_GOLD` in `game_base.gd` are the levels and what each one does to monster health and start gold. For tests there is also the debug/test option `-- --level=hard` (or easy, normal, insane): it only works when running from source or in the debug version (`OS.is_debug_build()`), and the released game ignores it.
- `daily_rules()` and `DAILY_WAVES` in `game_base.gd` set the daily challenge's twists and length; its map is made by `daily_map()` in `game_net.gd`.
- `REPLAY_SECONDS` and `REPLAY_STEP` in `main.gd` set how much the replay keeps (game seconds) and how often it records (the replay code is at the end of `main.gd`).
- `START_GOLD`, `MAX_ALIVE`, `WAVE_INTERVAL` and `MAX_WAVE` set the starting gold, the monster limit (per player), the time between waves and the number of waves.
- `ABILITIES` in `game_base.gd` sets each ability's cooldown and numbers (their rules are in `do_ability()` in `main.gd`). `ENDLESS_HP_GROWTH` is how fast monster health grows per wave in endless mode.
- Only the exported game with a window looks for updates on GitHub; runs from the project folder, headless runs and tests don't. For testing the update feature, start with `-- --update-check` (or `--update-check-every=SECONDS`, which also checks again every that many seconds).
- `EARLY_VOTE` sets the share of players (0.75 = 75%) who must agree to send a wave early in multiplayer.
- `DEFAULT_MAP` in `game_base.gd` is the map, one letter per tile: `.` grass, `#` path, `1`-`4` a player's gate, `r` rock, `t` tree, `w` water (nothing can be built on these). `read_map()` checks it: the path must be one closed loop, one tile wide, and each gate must stand at the end of its own road to the loop. Monsters walk from their gate to the loop and then around it clockwise. Each player's area is the part of the map nearest to where their gate's road joins the loop.
- `BUILTIN_MAPS` in `game_base.gd` lists the built-in maps by name (same letters as `DEFAULT_MAP`); `builtin_map_rows()` and `builtin_map_name()` look them up, and `map_list()`, `list_name()`, `list_rows()`, `is_builtin_name()` and `load_map_rows()` in `map_editor.gd` put them in the map lists.
- Map sharing: `open_share()` and `import_code()` in `map_editor.gd` open the share box and read a pasted code; the code itself is in `map_share.gd`.
- `PLAYER_COLORS` and `PLAYER_NAMES` list the 8 player colours and their names (the name is also used when a player has no name). `color_of()`, `color_name()` and `my_color()` in `game_base.gd` give a player's colour, `settle_colors()` and `pick_color()` in `game_net.gd` make sure no two players share one, and `draw_color_picker()` in `game_ui.gd` is the picker in the Profile box. `SILLY_NAMES` is the list of random names for players who leave the name box empty.
- `ZOOM_MIN`, `ZOOM_MAX` and `ZOOM_STEP` set how far you can zoom in and out, and how much each scroll notch zooms.
- `start_wave()` and `spawn_enemy()` in `main.gd` start each wave and give each monster kind its health, armor and gold.
- `build_world()` in `game_world.gd` sets up the 3D scene: camera angle, lighting, haze and effects; `build_map()` the ground (painted grass and dirt, see `assets/shaders/ground.gdshader`) and the land around the board. Models get the painted look of `assets/shaders/painted.gdshader` (see `painted()`). `build_gate()` builds the gates, and `build_tower_node()` each tower's 3D model. Which model a tower level shows: `arrow_look()` and `ARROW_FROM` (Arrow), `kit_look()` and `KIT_FILES` (Cannon, Poison, Frost and Spark). Model files are in `assets/`, with their sources in `assets/CREDITS.md`.
- Sound: `SOUNDS` (sound effects, files in `assets/sounds`), `MUSIC_LAYERS` and `MUSIC_MOODS` (music, 4 layers in `assets/music`) in `game_audio.gd`. `play_sound()` plays one. The volumes are saved in `settings.cfg` under `[audio]`.
- Tutorial tips: the tips are `TIPS` in `game_base.gd`; when each one shows is in `tip_ready()` and `tip_done()` in `main.gd`; the card is `draw_tip_card()` in `game_ui.gd`. Saved in `settings.cfg` under `[tutorial]`.
- Tower info cards: `tower_card()` and `draw_tower_card()` in `game_ui.gd` (every number comes from `TOWERS` and `PATHS`).
- Achievements: `ACHIEVEMENTS` and `ACHIEVEMENT_GROUPS` in `game_base.gd`; stats are saved in `PROFILE_FILE` (`profile.cfg`). `JOIN_BY` and `JOIN_BY_DAILY` are the last waves you can join for a win to count.
- Trees: `add_trees()` and `make_tree_kinds()` in `game_world.gd`, with the look in `assets/shaders/painted_leaves.gdshader`.
- `RELAY_URL` in `game_base.gd` is the game server's address, and `NET_PORT` and `SEARCH_PORT` are the network ports used for games on your own network.
- `GAME_FOLDER` and `GAME_NAME` in `game_base.gd` set the names of the folder and files the downloaded `.exe` unpacks into.
- The game server is a small Cloudflare Worker, kept outside this repository.
- To see errors while testing, start the game with `godot --path . -- --debug-log`: a second window lists every error, warning and print (**F12** shows and hides it). The **Windows Debug** export preset builds a separate debug .exe that always has this window and never unpacks or updates itself.
