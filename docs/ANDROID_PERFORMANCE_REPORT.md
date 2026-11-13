# Android Performance Report — Graphics Overhaul

## Engineering budgets (what the game costs on paper)

| Budget | LOW | MEDIUM (default) | HIGH |
|---|---|---|---|
| 3D render scale | 0.70 | 0.85 | 1.00 |
| Anti-aliasing | off (FXAA) | MSAA 2x + deband | TAA + deband |
| Shadow-casting lights | 0 | 1 (key spot, 4096 atlas) | 1 (soft, high filter) |
| Real lights total | 2 (fill+key) | 12 | 12 |
| SSAO / volumetric fog | off | SSAO + fog shafts | + denser fog |
| SDFGI / SSR / far-DOF | off | off | SDFGI + SSR + DOF |
| Post FX (vignette/CA/grain) | off | subtle | full |
| Audience crowd animation | static | static | subtle sway |

Renderer: **Forward+ (Vulkan)** on Android 9.0+ devices; devices without
Vulkan automatically fall back to the Compatibility (GLES3) renderer
(`fallback_to_opengl3`), which ignores the Forward+-only features above
(gameplay identical, visuals simplified).

Draw-call profile (per gameplay frame, worst-case 12x12 grid):
- Tile floor: **3 draw calls total** (glass tops, steel lips, LED edges — all
  MultiMesh; previously up to 144 unique-material tile draws).
- Arena set: ~20 draws (walls, truss MultiMeshes x4, crowd, LED wall, stage
  pieces, cameras) + shadow pass for the single caster.
- Player: 6 primitives + HUD.

Texture memory (v3.0 photoscan library): ~28 MB ASTC/ETC2 VRAM
(15 maps at 2048px + 1024px velvet, role-aware VRAM compression with full
mip chains — verified by `scripts-dev/probe_textures.gd`); + crowd 1024x256,
LED 1024x512, glass/steel synthetics 512px, character GLB 1.28 MB.
APK grows by the compressed texture payload (~+25-30 MB).

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

v3.0: the engine's **Forward+ (Vulkan)** renderer is used on device; CI
evidence screenshots render the same Forward+ pipeline via lavapipe at
pinned HIGH quality (SDFGI/SSAO/SSR/DOF/TAA). On devices without Vulkan the
Compatibility fallback runs (39/39 touch E2E verified under it).
