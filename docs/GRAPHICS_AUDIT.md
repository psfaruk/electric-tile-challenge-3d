# Graphics Overhaul — Phase 0 Full Code Audit

**Repo:** psfaruk/electric-tile-challenge-3d @ `220f895` (v1.0.2)
**Auditor:** Integration Lead (graphics overhaul master prompt, Phase 0)
**Date:** 2026-11-13
**Method:** every script, config, workflow, level file and asset read line-by-line;
the full CI pipeline (import, syntax, 50-level validation, headless smoke,
touch E2E at 1280x720 + 2400x1080, APK export) was **reproduced locally**
(Godot 4.3-stable Linux, Xvfb + Mesa software GL) before any modification.

---

## 1. Baseline build & test status (evidence)

| Gate | Where | Status at v1.0.2 |
|---|---|---|
| Import + per-script syntax | CI + local | PASS |
| 50-level config validation | CI + local | PASS (50/50) |
| Headless gameplay smoke (win/fail/retry/screens) | CI + local | PASS |
| Touch-input E2E, 16:9 and 20:9 phone geometry | CI (green) | PASS |
| Signed release APK export + artifact | CI (green) | PASS |
| Software-GL screenshots (menu + gameplay) | CI artifact | PASS |

Latest CI runs on `main` and tag `v1.0.2`: `completed / success`.
Baseline screenshots (locally re-rendered, identical pipeline): photorealism
score by independent VLM art-director critique: **2/10**; TV game-show feel:
**3/10**. Confirms the master prompt's assessment: the game reads as a
"low-poly robot inside a neon grid arena".

### The "dead buttons on my phone" report (root cause, already fixed)

The user's complaint refers to the **v1.0.0** APK. Root cause found in
history: the screen-transition veil (`ColorRect` in `main.gd`) started with
`MOUSE_FILTER_STOP` and invisible alpha — it swallowed every tap on real
devices (desktop preview worked, so it shipped unnoticed). Fixed in v1.0.1
(veil set `MOUSE_FILTER_IGNORE` + hidden when idle) and hardened in v1.0.2
(every control answers raw touch, emulated mouse, and both coordinate spaces;
CI touch E2E at phone aspect 2400x1080 added as a permanent gate).
**Action for the user: download the v1.0.2+ APK** (Actions artifact or the
`v1.0.2` GitHub Release), not v1.0.0.

---

## 2. Current visual limitations (what this overhaul must replace)

1. **Player character** (`robot_model.gd`): box+capsule primitives with
   emissive visor — reads as a placeholder droid, no human proportions,
   no clothing, no skeleton, code-driven procedural animation only.
2. **Arena** (`arena.gd`): an empty black box — 4 flat walls, flat ceiling,
   no depth cues, no set dressing, no audience, no LED screens, no stage
   structure. Ceiling light bars are the only "set" element.
3. **Neon identity**: cyan emissive trims on every edge + one pulsing trim
   material = "programmer-art neon prototype", the exact style to remove.
4. **Materials**: single untextured albedo colors for walls/floor (only
   `floor_metal`/`wall_panel` textures, no normal/roughness maps anywhere),
   uniform metallic 0.25-0.45, no PBR variation, no reflections.
5. **Lighting** (`graphics.gd`): 1 directional sun + 1 spot accent (HIGH),
   ambient 1 flat color, fog, glow — flat exposure, no key/fill/rim
   structure, emission used as the primary light source (the master
   prompt explicitly forbids this going forward).
6. **Tiles** (`tile.gd`): 1.15m flat cubes, emissive texture swap only —
   no frames, no bevels, no glass layer, no LED edge hardware.
7. **UI** (`ui.gd` + screens): functional but stock — default font,
   rounded rects, black outlines; menu title "CHALLENGE 3D" clips behind
   PLAY on 1280x720 (bug to fix in Phase 9); banners use tutorial-grade
   outline styling.
8. **Effects** (`sparks.gd`): pooled CPU particles only, no electric arcs,
   no tile activation discharge.
9. **Menu attract mode**: floating slabs + neon strips against void black.

## 3. Existing reusable systems (MUST keep working)

| System | File(s) | API to preserve |
|---|---|---|
| Screen router + transitions | `scripts/main.gd` | `goto(screen, params)`, fade veil (input-safe) |
| Save/settings/progression | `autoload/GameState.gd` | settings dict, `load_level()`, `record_result()`, `is_unlocked()`, env flags (`ETC_SMOKE/TOUCHTEST/SHOT`) |
| Audio | `autoload/AudioManager.gd` | `play_sfx/play_music/click/haptic`, buses |
| Challenge referee | `scripts/game/challenge.gd` | Phase enum, `setup()`, `on_player_cell()`, `on_finish_entered()`, `restart()`, signals `game_won/game_failed` |
| Player controller | `scripts/game/player.gd` | CharacterBody3D, `move_input`, `request_jump`, `play_zap/play_victory`, `locked`, capsule r=0.30 h=1.5 @ y=0.75 |
| Character visuals | `scripts/game/robot_model.gd` | consumed via `model.set_moving/set_air/play_zap/play_victory/bounce` — **replaced by human model with the same call contract** |
| Grid math | `scripts/game/grid.gd` | `PITCH=1.25`, `tile_center()`, `cell_from_pos()`, `spawn_pos()` |
| Tile visuals | `scripts/game/tile.gd` | `setup(cell)`, `set_shared/set_own`, `flash_correct/flash_neutral`, `set_flip`, `mark_failed`, `reveal_safe/reveal_danger` |
| Camera | `scripts/game/camera_rig.gd` | `setup(player, vp)`, `rotate_input/zoom_input/shake`, smart/manual modes |
| Environment/quality | `scripts/game/graphics.gd` | `build_environment(parent, quality)`, `apply_viewport(vp, quality)` (LOW/MED/HIGH) |
| Arena | `scripts/game/arena.gd` | `setup(level, quality)`, `get_spawn()`, `get_finish_z()` |
| Sparks pool | `scripts/game/sparks.gd` | `burst(pos,color,strong)`, `confetti(pos)` |
| HUD | `scripts/ui/screens/hud.gd` | `setup(gp)`, all setters, raw-touch fast path, `is_ui_at()` |
| Gameplay screen | `scripts/ui/screens/gameplay.gd` | pause/results flow, smoke + shot modes, camera touch plumbing |
| Menus | `main_menu.gd`, `level_select.gd`, `settings.gd` | navigation contract, back-button wiring |
| Widgets | `joystick.gd`, `icon_widgets.gd`, `ui.gd` factory | polling `output`, star/lock icons, style factory |
| Content | `data/levels/*.json` (50), `gen_levels.py` | schema frozen (see `validate_levels.gd`) |
| Asset pipelines | `gen_textures.py`, `gen_audio.py`, `gen_icons.py` | deterministic, numpy+zlib, no external assets |
| CI | `.github/workflows/android-build.yml` | 6 gates + screenshots job (keep green at all times) |

**Dependency graph:** gameplay.gd → {arena, tiles, player, challenge, hud,
camera_rig, sparks}; challenge.gd → tiles dict + hud + sparks + cam_rig;
main_menu.gd → robot_model (attract mode) + graphics.gd; robot_model.gd is
referenced by player.gd and main_menu.gd (attract) only.

## 4. Placeholder assets inventory (all current "art")

| Asset | Current form | Verdict |
|---|---|---|
| Player character | code-built primitives (`robot_model.gd`, 276 lines) | REPLACE (human GLB, same API) |
| Arena set | code-built boxes + trims (`arena.gd`) | REBUILD as TV-studio (Phase 3) |
| Floor tiles | flat box + emissive texture (`tile.gd`) | UPGRADE hardware look (Phase 4) |
| Textures | 6 procedural PNGs, albedo only | EXTEND with PBR channel sets |
| Icons | procedural + `icon_widgets.gd` stars/locks | KEEP (small, clean) |
| Audio | synthesized WAV set | KEEP |
| Signage | `Label3D` text | REPLACE with texture-based LED screens |

## 5. Required replacement assets + acquisition (Phase A results)

### 5.1 Human character — ACQUIRED (CC0)

- **Source:** Quaternius "Universal Animated Men (2019)" via quaternius.com
  (public Google Drive pack) — **CC0** license, verifiable on the pack page.
- **Chosen:** `Male_Casual` (casually dressed man: t-shirt, shorts, socks,
  shoes, hair, eyes — 7 separate body-part materials, ideal for PBR cloth).
- **Rig:** `HumanArmature`, 31 joints, skinned mesh ~4k vertices, 6 primitives.
- **Animations exported (11):** Idle, Walk, Run, Jump, RunningJump, Clapping
  (→ victory), Death (→ electrocution/fail), Standing, Sitting, Punch,
  SwordSlash — covers every state the current game needs (idle/move/air/
  victory/zap) plus extras for menus.
- **Scale normalization:** authored at 4.83 m; normalized to **1.80 m**,
  Y-up, feet at y≈0 (validated via glTF bbox: 0.0012 → 1.8066).
- **Missing "fall/land" clips:** covered by `Man_Jump`/`Man_RunningJump`
  (they contain landings) + procedural air pose; documented as a deviation.
- **Textures:** the pack ships color-materialized (no texture images).
  We generate original PBR micro-detail sets (skin pores, knit fabric weave,
  leather) and attach them per material so base colors still tint cloth.
  Export via Blender 3.6 headless (`gltf` exporter, ACTIONS mode), textures
  embedded in the GLB.

**Honest limitation (per master prompt):** a fully *photorealistic* scanned
human (true photographic skin/face detail) cannot be legally redistributed in
this public repo — Mixamo/Renderpeople/Fab licenses forbid it. The CC0 rigged
human above is the highest-quality legally shippable option and is integrated
with a full **AnimationTree** state machine, so a licensed photoreal model can
be dropped in later by replacing one GLB + one retarget profile
(documented in `docs/ASSET_INVENTORY.md`). No fake "photoreal" claims are made
about the CC0 model; it is a clean, well-rigged, clothed, realistic-proportioned
human with PBR materials — a large, honest upgrade from the box robot.

### 5.2 Environment — procedural PBR studio build (no external GLB)

No suitable CC0 TV-studio set is downloadable from this environment (poly.pizza
and kenney.nl are blocked; no CC0 "TV game show studio" pack exists on
reachable sources). Per the master prompt's fallback rule, environment objects
are **produced in-house**: a detailed procedural TV-studio builder
(truss grid, LED walls, audience bleachers with crowd billboards, stage
aprons, spot rig) using the generated PBR texture library. This keeps the
project 100% original-licensed and APK-size friendly, and GLB props can be
added later without touching gameplay code.

### 5.3 PBR texture library — GENERATED (21 PNGs, ~3.0 MB)

New `scripts-dev/gen_textures_pbr.py` (same numpy+zlib pipeline, deterministic,
tileability-proven): brushed steel, painted steel (wear chips), concrete,
rubber, crowd silhouettes (1024x256), LED screen content (1024x512), theatrical
curtain, smoked-glass tile top — each with albedo + tangent-space normal
(OpenGL convention, verified flat=(128,128,255)) + roughness. Details:
`docs/asset_reports/pbr_texture_report.md`.

## 6. Performance risks (mobile Vulkan renderer, low/mid-range targets)

| Risk | Mitigation plan |
|---|---|
| Per-tile unique materials break batching (up to 12x12=144 tiles) | keep the shared-material reveal phases; own materials only during PLAY; static MultiMesh for tile hardware frames |
| New trusses/audience/LED geometry raises draw calls | MultiMesh for audience + trusses + LED panel grid; ≤ ~40 total draws target on LOW |
| Embedded character textures + PBR sets raise VRAM | ≤512px textures, ETC2/ASTC compression (already on), total new textures ~3 MB |
| More lights (spot rig) vs. Mobile renderer | shadows only on 1 key light; spot accents unshadowed on MED/LOW; light count per quality profile |
| Particles on zap | keep pooled one-shot CPUParticles (existing) + short-lived arcs; never continuous per-tile systems |
| Glow cost | LOW: glow off; MED/HIGH: modest glow (already) |
| SSAO/GI unavailable on Mobile renderer | not used; rely on baked-feel ambient + AO textures |
| Software-GL screenshots differ from device output | screenshots are evidence of real engine output; on-device profiling stays a documented user step |

## 7. File-by-file upgrade plan

| File | Action | Phase |
|---|---|---|
| `scripts/game/robot_model.gd` | superseded → `human_character.gd` (same public API: set_moving/set_air/play_victory/play_zap/bounce); robot kept as documented fallback until human passes all gates | 2 |
| `scripts/game/player.gd` | capsule re-fit to 1.8 m human; movement API unchanged | 2 |
| `scripts/main_menu.gd` | attract mode uses human + studio backdrop; fix title clipping | 2/9 |
| `scripts/game/arena.gd` | rebuilt: TV-studio shell (trusses, walls, LED walls, audience, stage aprons, pads) + collision; API (`setup/get_spawn/get_finish_z`) unchanged | 3 |
| `scripts/game/tile.gd` | framed tile: metal frame + LED edge + glass top layer; state API unchanged | 4 |
| `scripts-dev/gen_textures_pbr.py` + `assets/textures/pbr/` | NEW (done) — PBR library | 5 |
| `scripts-dev/gen_textures_human.py` + character GLB | NEW — character micro-detail textures + `assets/characters/human/` | 2 |
| `scripts/game/graphics.gd` | cinematic lighting: key/fill/rim + exposure + glow tuning; 3 profiles preserved & expanded | 6 |
| `scripts/game/sparks.gd` | add electric-arc bursts (procedural polyline + pooled particles); `burst/confetti` API kept | 7 |
| `scripts/game/camera_rig.gd` | framing height/FOV for human scale, smoothing tuning, gentle shake hook kept | 8 |
| `scripts/ui/ui.gd` + screens | typography/spacing/color polish, HUD re-layout; all callables/signals preserved | 9 |
| `.github/workflows/android-build.yml` | extend screenshots to 8 required shots (menu, arena, character close-up, tile close-up, safe, danger, gameplay, victory) | 13 |
| `docs/GRAPHICS_OVERHAUL_REPORT.md`, `ASSET_INVENTORY.md`, `ANDROID_PERFORMANCE_REPORT.md`, `TEST_REPORT.md`, `PHASE_PROGRESS.md` | written/updated per phase | all |

## 8. Execution rules honored

- No working system will be deleted before its replacement passes the same
  CI gates (robot stays until the human passes smoke + touch tests).
- Every phase lands as its own commit and must leave CI green (6 gates).
- Gameplay rules, 50-level schema, difficulty and progression are untouched.
- All new assets are CC0/original with generators checked in — the APK
  remains fully licensed for distribution.
