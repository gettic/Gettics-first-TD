# Art credits

Every art file in this folder that wasn't made for this game, where it comes from and its license.

| Files | Pack | Author | Link | License |
|---|---|---|---|---|
| `monsters/Skeleton_Minion.glb`, `monsters/Skeleton_Warrior.glb`, `monsters/Skeleton_Mage.glb`, `monsters/Skeleton_Shield_Large_A.*`, `monsters/Skeleton_Axe.*`, `monsters/Skeleton_Staff.*`, `monsters/skeleton_texture.png` | KayKit - Character Pack: Skeletons 1.1 | Kay Lousberg (www.kaylousberg.com) | https://kaylousberg.itch.io/kaykit-skeletons | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `monsters/monster_walks.res` (the Walking_A, Walking_B and Walking_C animations of Rig_Medium_MovementBasic, saved on their own) | KayKit - Character Animations 1.1 | Kay Lousberg (www.kaylousberg.com) | https://kaylousberg.itch.io/kaykit-character-animations | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `nature/Rock_1_E_Color1.*`, `nature/Rock_2_C_Color1.*`, `nature/Rock_3_C_Color1.*`, `nature/Rock_3_F_Color1.*`, `nature/Tree_1_A_Color1.*`, `nature/Tree_2_A_Color1.*`, `nature/Tree_3_A_Color1.*`, `nature/Tree_4_A_Color1.*`, `nature/forest_texture.png` | KayKit - Forest Nature Pack 1.0 | Kay Lousberg (www.kaylousberg.com) | https://kaylousberg.itch.io/kaykit-forest | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `terrain/grass.png`, `terrain/grass_normal.png` (Grass_03 and Grass_03_Nrm) | Tileable Grass Textures - Set 1 | Cethiel | https://opengameart.org/content/tileable-grass-textures-set-1 | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `terrain/dirt.png`, `terrain/dirt_normal.png` (Dirt_01 and Dirt_01_Nrm) | Tileable Dirt Textures | Cethiel | https://opengameart.org/content/tileable-dirt-textures | CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/) |

The game turns the Arrow tower's roof, cape and flags into each player's color in code (see `arrow_mat()` in `game_world.gd`).

The terrain textures are re-saved (losslessly, smaller PNGs) and renamed; the game tints them with `shaders/ground.gdshader`.

The monsters' walks are posed once when the game starts (see `build_monsters()` in `game_world.gd`). The unicorns and bone spiders are built from simple shapes in code.

Made for this game: `shaders/pack_model.gdshader`, `shaders/ground.gdshader`, `shaders/water.gdshader`.

Made by Gettic: `logo/logo.png` and the game icon `logo/icon.png`, `logo/icon.ico` (cut from his logo).

Made by Gettic with an AI tool: the Arrow tower 0.02, `towers/arrow/archer_tower_L1.glb` to `archer_tower_L10.glb` (one per look), and their textures `towers/arrow/archer_tower_L1_*.jpg` (taken out of `archer_tower_L1.glb` at full size; the other models use the same textures, so they're imported without their own copy).

Crediting isn't required by CC0, but thank you, Kay Lousberg and Cethiel.
