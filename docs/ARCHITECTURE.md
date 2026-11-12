# Architecture — Electric Tile Challenge 3D

Engine: **Godot 4.3-stable** (pinned), GDScript, Mobile renderer (Vulkan),
ETC2/ASTC texture compression, landscape orientation, 1280x720 design resolution
with `canvas_items` stretch mode + `expand` aspect.

## Design decisions

1. **One scene, code-built everything.** The project ships exactly one `.tscn`
   (`scenes/main.tscn` = a root Node with `scripts/main.gd`). All screens, HUD,
   arena, tiles and the character are constructed programmatically. This keeps
   the repo text-only (reviewable diffs), avoids scene-merge conflicts between
   agents, and exercises the full game in headless CI.
2. **Data-driven levels.** Levels are JSON documents (`data/levels/*.json`),
   loaded via `FileAccess` + `JSON.parse_string` at runtime. Nothing about a
   level is hardcoded in scripts.
3. **Procedural original assets.** No binary blobs are committed except the
   generated textures/audio/icons (all reproducible via `scripts-dev/*.py`).
   The character is a stylized droid assembled from shaped primitives with a
   hand-tuned animation system — see `scripts/game/robot_model.gd`.
4. **Autoloads** (`project.godot`): `GameState` (save data, settings, level
   loading, InputMap) and `AudioManager` (buses, SFX pool, music crossfade).

## Module map

```
Main (scripts/main.gd)  — screen router, fade overlay, smoke/screenshot modes
├─ GameState (autoload) ─── settings, stars/best times, load_level(id), InputMap
├─ AudioManager (autoload) ─ Music/SFX buses, play_sfx(name), crossfade music
└─ <active screen>  (one at a time; screens are plain Node/CanvasLayer roots)
   ├─ MainMenuScreen   — 3D attract arena + orbit camera + menu UI
   ├─ LevelSelect      — 50 cards, lock/star states, tier sections
   ├─ SettingsScreen   — volumes, quality, camera, haptics, reset
   └─ GameplayScreen   — composes the in-match world:
      ├─ Graphics.build_environment() — WorldEnvironment + sun + accents
      ├─ Arena (arena.gd)   — room shell + collision, neon trims, hazard
      │                       frame, start/finish pads, signage, rib MultiMesh
      ├─ Tiles (tile.gd)    — one MeshInstance per grid cell, per-tile
      │                       material, shared reveal materials (batched look)
      ├─ Robot (robot_model.gd) + Player (player.gd, CharacterBody3D)
      ├─ CameraRig (camera_rig.gd) — smart follow / manual orbit, ray clip guard
      ├─ Sparks (sparks.gd)  — pooled CPUParticles3D emitters
      ├─ Challenge (challenge.gd) — referee state machine (see below)
      └─ HUD (hud.gd)         — banners, bars, timer, joystick, jump button,
                                pause + results overlays
```

## Challenge state machine

```
READY ──1.2s──▶ REVEAL ────────────────▶ PLAY ────────▶ DONE
                │ memory: safe/danger  │ timed:       win  → game_won(t)
                │ shared mats pulse    │ countdown    fail → game_failed(reason)
                │ pattern: sequence    │ flippers
                │ flash each step      │ stepping rules
```

- **Stepping rules**: every grid cell outside the safe path is lethal (zap),
  except off-path flippers during their safe window. Pattern mode additionally
  enforces exact step order. On-path flippers zap if they flip while stood on.
- **Win**: enter the finish zone (pattern mode requires the full sequence).
- **Stars**: 1 = finish, 2 = beat `par_time`, 3 = beat `gold_time`.

## Tile state visual language

| State | Look |
|---|---|
| OFF / dark | teal glow at 0.16 energy (idle arena) |
| SHOWING_SAFE / SHOWING_DANGER | shared green/red pulsing materials (reveal) |
| ACTIVATED (stepped) | white-green flash settling to 0.9 |
| Flipper safe / warning / danger | green 0.65 / orange pulse / red 0.45 |
| FAILED (zapped) | red spike 5.0 → 1.6 |
| Truth reveal (post-fail) | green 0.9 path vs red 0.4 danger |

## Performance architecture

- One `StaticBody3D` for the entire room (5 collision shapes).
- Wall ribs drawn via a single `MultiMeshInstance3D`.
- Reveal phases swap tiles onto 2 shared animated materials instead of
  animating 100+ materials.
- Sparks are a pre-allocated pool (no runtime allocation during play).
- Quality presets: Low (no shadows/glow, 70% 3D scale, FXAA), Medium
  (2048px directional shadows, MSAA 2x, 85%), High (MSAA 4x, accent spots, 100%).
- Audio buses created once; pooled `AudioStreamPlayer`s for SFX.

## Extensibility (iOS / Windows later)

The renderer preset uses the standard mobile pipeline; porting means adding
export presets per platform — gameplay/UI code is platform-agnostic
(`OS.get_name()` is only used for platform-specific behavior, currently none).
To upgrade visuals with Blender/GLB assets later: drop `.glb` models under
`assets/models/`, replace the procedural construction in `robot_model.gd` /
`arena.gd` with `AnimatedMesh3D` instancing — the rest of the game logic
(cell grid, challenge rules, HUD) is decoupled from the visual source.
