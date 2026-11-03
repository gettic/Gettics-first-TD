# Art credits

Every art file in this folder that wasn't made for this game, where it comes from and its license.

| Files | Pack | Author | Link | License |
|---|---|---|---|---|
| `monsters/Skeleton_Mage.glb`, `monsters/Skeleton_Staff.*`, `monsters/skeleton_texture.png` | KayKit - Character Pack: Skeletons 1.1 | Kay Lousberg (www.kaylousberg.com) | https://kaylousberg.itch.io/kaykit-skeletons | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `monsters/monster_walks.res` (the Walking_A, Walking_B and Walking_C animations of Rig_Medium_MovementBasic, saved on their own; the game uses Walking_C) | KayKit - Character Animations 1.1 | Kay Lousberg (www.kaylousberg.com) | https://kaylousberg.itch.io/kaykit-character-animations | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `nature/Rock_1_E_Color1.*`, `nature/Rock_2_C_Color1.*`, `nature/Rock_3_C_Color1.*`, `nature/Rock_3_F_Color1.*`, `nature/Grass_1_B_Color1.*`, `nature/Grass_2_B_Color1.*`, `nature/forest_texture.png` | KayKit - Forest Nature Pack 1.0 | Kay Lousberg (www.kaylousberg.com) | https://kaylousberg.itch.io/kaykit-forest | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `terrain/grass.png`, `terrain/grass_normal.png` (Grass_03 and Grass_03_Nrm) | Tileable Grass Textures - Set 1 | Cethiel | https://opengameart.org/content/tileable-grass-textures-set-1 | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `terrain/dirt.png`, `terrain/dirt_normal.png` (Dirt_01 and Dirt_01_Nrm) | Tileable Dirt Textures | Cethiel | https://opengameart.org/content/tileable-dirt-textures | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |

The game turns the Arrow tower's roof, cape and flags into each player's color in code (see `arrow_mat()` in `game_world.gd`).

The terrain textures are re-saved (losslessly, smaller PNGs) and renamed; the game tints them with `shaders/ground.gdshader`.

The monsters' walks are posed once when the game starts (see `build_monsters()` in `game_world.gd`). The unicorns and bone spiders are built from simple shapes in code.

Made for this game: `shaders/pack_model.gdshader`, `shaders/ground.gdshader`, `shaders/water.gdshader`, `shaders/painted.gdshader`, `shaders/lake.gdshader`, `shaders/brew.gdshader`, `shaders/cloud.gdshader`, `shaders/shield.gdshader`, `shaders/heal_ring.gdshader`.

Made for this game: `shaders/painted_leaves.gdshader` (for the trees and bushes, which are built in code).

Made for this game (built with a script, no outside sources): the gate `gates/gate.glb` (it uses the cannon tower's atlas and team strip, no textures of its own) and its portal `shaders/gate_portal.gdshader`.

Made for this game (by Claude, with a Python model kit of code-built shapes and painted textures): the Cannon tower, `towers/cannon/cannon_<path>_<look>.glb` (path 0: levels 1-4; path 1 Big Bomb and 2 Cluster: looks 5-10 for levels 5, 10, 15, 20, 30 and 40) and its shared textures `towers/cannon/cannon_atlas.jpg`, `cannon_team.jpg` and `cannon_glow.jpg` (the models are saved without their own copy); the Poison tower, `towers/poison/poison_<path>_<look>.glb` (path 0: levels 1-4; path 1 Venom and 2 Miasma: looks 5-10, the same levels as the cannon's) with `towers/poison/poison_team.jpg` and `poison_glow.jpg` (it shares the cannon's `cannon_atlas.jpg`); and the skeleton warrior `monsters/bone_warrior.glb` with its walk and death (its texture `monsters/bone_warrior_Skeleton.jpg` is taken out of it on import).

Made for this game (by Claude, with the same Python model kit): the Barracks, `towers/barracks/barracks_<path>_<look>.glb` (path 0: levels 1-4; path 1 Knights and 2 Militia: looks 5-10, the same levels as the cannon's) with `towers/barracks/barracks_team.jpg` and `barracks_roof.jpg` (it shares the cannon's `cannon_atlas.jpg` and `cannon_glow.jpg`); its soldiers `units/soldier_footman.glb`, `soldier_knight.glb` and `soldier_militia.glb` with their idle, fight, walk and fall animations and their texture `units/soldier.jpg`; and `shaders/soldier.gdshader`.

Made for this game (by Claude, with the same Python model kit): the Frost tower, `towers/frost/frost_<path>_<look>.glb` (path 0: levels 1-4; path 1 and 2: looks 5-10, the same levels as the cannon's) with `towers/frost/frost_team.jpg` and `frost_glow.jpg`; and the Spark tower, `towers/spark/spark_<path>_<look>.glb` (the same looks) with `towers/spark/spark_team.jpg` and `spark_glow.jpg` (both share the cannon's `cannon_atlas.jpg`).

Made for this game (by Claude, repainted with a script): the Bone Choir's skeleton colours, `monsters/bone_choir_warrior.jpg` (from the skeleton warrior's own texture) and `monsters/bone_choir_mage.png` (from KayKit's CC0 `skeleton_texture.png`, credited above), with their glow masks `bone_choir_warrior_glow.jpg` and `bone_choir_mage_glow.png`.

Made by Gettic: `logo/logo.png` and the game icon `logo/icon.png`, `logo/icon.ico` (cut from his logo).

Made by Gettic with an AI tool: the Arrow tower 0.02, `towers/arrow/archer_tower_L1.glb` to `archer_tower_L10.glb` (one per look), and their textures `towers/arrow/archer_tower_L1_*.jpg` (taken out of `archer_tower_L1.glb` at full size; the other models use the same textures, so they're imported without their own copy).

Made for this game (synthesized with a script, no outside sources): all the sound effects in `sounds/`.

Made for this game (original music, rendered with a script): the 4 music layers in `music/`, played with instrument samples from VSCO 2 Community Edition, Versilian Studios, CC0 (https://versilian-studios.com/vsco-community/, https://github.com/sgossner/VSCO-2-CE); the choir is synthesized. The samples themselves are not in the game.

Made for this game (synthesized with the same script): the story event sounds `sounds/grim_entrance.wav`, `crescendo.wav`, `grim_fall.wav`, `story_page.wav` and `festival_frostfall.wav`, `festival_lantern.wav`, `festival_paint.wav`.

Crediting isn't required by CC0, but thank you, Kay Lousberg and Cethiel.
