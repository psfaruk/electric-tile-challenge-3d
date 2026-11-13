# Android Performance Report — Graphics Overhaul

## Engineering budgets (what the game costs on paper)

| Budget | LOW | MEDIUM (default) | HIGH |
|---|---|---|---|
| 3D render scale | 0.70 | 0.85 | 1.00 |
| MSAA | off (FXAA) | 2x | 4x |
| Shadow-casting lights | 0 | 1 (key spot) | 1 |
| Real lights total | 2 (fill+key) | 8 | 11 |
| Glow / haze / adjustments | off | glow+haze | +contrast/vignette |
| Audience crowd animation | static | static | subtle sway |

Draw-call profile (per gameplay frame, worst-case 12x12 grid):
- Tile floor: **3 draw calls total** (glass tops, steel lips, LED edges — all
  MultiMesh; previously up to 144 unique-material tile draws).
- Arena set: ~20 draws (walls, truss MultiMeshes x4, crowd, LED wall, stage
  pieces, cameras) + shadow pass for the single caster.
- Player: 6 primitives + HUD.

Texture memory: ~4.5 MB compressed (PBR sets 512 px, crowd 1024x256, LED
1024x512, character GLB 1.28 MB with embedded 256 px textures, ETC2/ASTC).

Runtime CPU: tile state controllers are 144 tiny Nodes updating a number and
writing one instance color only on change; arcs are 8-pool one-shots.

## Targets (goals, not claimed results)

- Stable 30 FPS on low-end (2 GB RAM, PowerVR/Mali-4xx class) at LOW profile.
- 60 FPS on capable devices at MEDIUM/HIGH.

## How to measure on your phone (user step)

1. Install the APK, Settings → GRAPHICS QUALITY: test LOW / MEDIUM / HIGH.
2. Play 2–3 levels of each tier and note smoothness on the busiest levels
   (Master tier, 12x12 grids with flippers).
3. Optional: enable Developer Options → "Profile GPU rendering" bars overlay;
   the game should stay under the 16 ms / 33 ms lines at MEDIUM / LOW.
4. Report device model + observed quality for the benchmark table below.

## Measured on device

| Device | SoC | Quality | Avg FPS | Notes |
|---|---|---|---|---|
| *(to be filled by device testing)* | | | | |

The engine's Mobile (Vulkan) renderer is used, matching the CI screenshot
renderer when Vulkan is available in CI.
