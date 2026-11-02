# Art credits

Every art file in this folder that wasn't made for this game, where it comes from and its license.

| Files | Pack | Author | Link | License |
|---|---|---|---|---|
| `monsters/Skeleton_Mage.glb`, `monsters/Skeleton_Staff.*`, `monsters/skeleton_texture.png` | KayKit - Character Pack: Skeletons 1.1 | Kay Lousberg (www.kaylousberg.com) | https://kaylousberg.itch.io/kaykit-skeletons | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `monsters/monster_walks.res` (the Walking_A, Walking_B and Walking_C animations of Rig_Medium_MovementBasic, saved on their own; the game uses Walking_C) | KayKit - Character Animations 1.1 | Kay Lousberg (www.kaylousberg.com) | https://kaylousberg.itch.io/kaykit-character-animations | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `nature/Rock_1_E_Color1.*`, `nature/Rock_2_C_Color1.*`, `nature/Rock_3_C_Color1.*`, `nature/Rock_3_F_Color1.*`, `nature/Tree_1_A_Color1.*`, `nature/Tree_2_A_Color1.*`, `nature/Tree_3_A_Color1.*`, `nature/Tree_4_A_Color1.*`, `nature/Tree_Bare_1_A_Color1.*`, `nature/Bush_1_B_Color1.*`, `nature/Bush_2_C_Color1.*`, `nature/Bush_3_A_Color1.*`, `nature/Grass_1_B_Color1.*`, `nature/Grass_2_B_Color1.*`, `nature/forest_texture.png` | KayKit - Forest Nature Pack 1.0 | Kay Lousberg (www.kaylousberg.com) | https://kaylousberg.itch.io/kaykit-forest | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `terrain/grass.png`, `terrain/grass_normal.png` (Grass_03 and Grass_03_Nrm) | Tileable Grass Textures - Set 1 | Cethiel | https://opengameart.org/content/tileable-grass-textures-set-1 | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `terrain/dirt.png`, `terrain/dirt_normal.png` (Dirt_01 and Dirt_01_Nrm) | Tileable Dirt Textures | Cethiel | https://opengameart.org/content/tileable-dirt-textures | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |

The game turns the Arrow tower's roof, cape and flags into each player's color in code (see `arrow_mat()` in `game_world.gd`).

The terrain textures are re-saved (losslessly, smaller PNGs) and renamed; the game tints them with `shaders/ground.gdshader`.

The monsters' walks are posed once when the game starts (see `build_monsters()` in `game_world.gd`). The unicorns and bone spiders are built from simple shapes in code.

Made for this game: `shaders/pack_model.gdshader`, `shaders/ground.gdshader`, `shaders/water.gdshader`, `shaders/painted.gdshader`, `shaders/lake.gdshader`, `shaders/brew.gdshader`, `shaders/cloud.gdshader`, `shaders/shield.gdshader`, `shaders/heal_ring.gdshader`.

Made for this game (by Claude, with a Python model kit of code-built shapes and painted textures): the Cannon tower, `towers/cannon/cannon_<path>_<look>.glb` (path 0: levels 1-4; path 1 Big Bomb and 2 Cluster: looks 5-10 for levels 5, 10, 15, 20, 30 and 40) and its shared textures `towers/cannon/cannon_atlas.jpg`, `cannon_team.jpg` and `cannon_glow.jpg` (the models are saved without their own copy); the Poison tower, `towers/poison/poison_<path>_<look>.glb` (path 0: levels 1-4; path 1 Venom and 2 Miasma: looks 5-10, the same levels as the cannon's) with `towers/poison/poison_team.jpg` and `poison_glow.jpg` (it shares the cannon's `cannon_atlas.jpg`); and the skeleton warrior `monsters/bone_warrior.glb` with its walk and death (its texture `monsters/bone_warrior_Skeleton.jpg` is taken out of it on import).

Made by Gettic: `logo/logo.png` and the game icon `logo/icon.png`, `logo/icon.ico` (cut from his logo).

Made by Gettic with an AI tool: the Arrow tower 0.02, `towers/arrow/archer_tower_L1.glb` to `archer_tower_L10.glb` (one per look), and their textures `towers/arrow/archer_tower_L1_*.jpg` (taken out of `archer_tower_L1.glb` at full size; the other models use the same textures, so they're imported without their own copy).

Crediting isn't required by CC0, but thank you, Kay Lousberg and Cethiel.
