# Level Design — Electric Tile Challenge 3D

## 1. Overview — a data-driven level system

All 50 levels ship as plain JSON. The game engine contains **zero hard-coded
level data**: at runtime it loads `res://data/levels/level_%03d.json`
(`level_001.json` … `level_050.json`), reads the frozen schema below, builds
the tile grid, spawns the safe path and any flippers, and configures the run
timer. Rebalancing a level is a pure data edit — no scene changes, no
recompiling GDScript. (On Android the files ride along inside the exported
PCK like any other `res://` resource.)

Frozen per-file schema (keys in this exact order — the engine depends on it):

```json
{
  "id": 1,                    // 1..50, matches the filename
  "name": "First Contact",    // unique themed display name
  "mode": "memory",           // "memory" | "timed" | "pattern"
  "tier": 1,                  // 1..5 difficulty tier
  "cols": 6,                  // grid width  (x axis count)
  "rows": 5,                  // grid depth  (z axis; player advances row 0 -> rows-1)
  "mem_time": 4.5,            // seconds the safe path is revealed for memorization
  "time_limit": 0.0,          // countdown seconds for "timed" mode; 0.0 otherwise
  "path": [[0,0],[0,1],[1,1]],// ORDERED safe cells [row, col]
  "flippers": [],             // [row, col, period, phase, on_path] hazard tiles
  "par_time": 6.2,            // seconds for 2 stars
  "gold_time": 4.3            // seconds for 3 stars
}
```

Path guarantees (enforced by the generator's built-in validator on every
run): the path starts on row 0 and ends on row `rows-1`; consecutive cells are
4-adjacent; the row index never decreases; **every** row `0..rows-1` is
crossed; no cell repeats; the length hits its exact target.

## 2. Challenge modes

- **memory** — the full safe path lights up for `mem_time` seconds at the
  start of the run, then the board goes dark. Cross from the start pad (row 0
  side) to the finish pad (row `rows-1`) purely from memory. No countdown —
  the pressure is recall, not the clock.
- **timed** — a quick hint reveal (the same `mem_time` flash), then a hard
  countdown starts at `time_limit` seconds. Reach the finish pad before zero
  or the run fails. `time_limit` is always `>= par_time + 3` and scales down
  tier by tier (factor 2.2 → 1.3 of par).
- **pattern** — the safe sequence is demonstrated step-by-step: tiles
  illuminate one at a time, in order, then the board resets and the player
  must **replay the steps in the correct order**. The board validates each
  step as it is taken; one wrong step is a shock. This mode is about
  sequencing, not just shape memory.

## 3. Tile rules, flippers, and stars

- **Lethal default:** every grid tile is live (electrified) except the safe
  path. Stepping off the path = shock = run restarts.
- **Flippers:** hazard tiles that alternate between safe and dangerous during
  play on their own clock: each entry is `[row, col, period, phase, on_path]`.
  A tile flips to the dangerous state every `period` seconds, offset by its
  `phase`, and emits a **warning pulse** shortly before each flip so an
  attentive player can time it. Two kinds:
  - *off-path flippers* (`on_path = 0`) sit beside the route — tempting
    shortcuts that are only briefly survivable, and moving hazards near the
    path;
  - *on-path flippers* (`on_path = 1`) occupy a path cell (never `path[0]`,
    never `path[1]` — the first steps are always safe), so the player must
    cross a required tile **at the right moment**, not just in the right
    order. Each on-path flipper adds +2.0s to the level's par.
- **Stars:**
  - 1 star — finish the level;
  - 2 stars — finish under `par_time`;
  - 3 stars — finish under `gold_time`.
  - Formulas (identical in generator and engine): `par_time = 2.5 + 0.62 ×
    path length + 2.0 × on-path flippers`, `gold_time = 0.7 × par_time`.

## 4. Difficulty philosophy by tier

Five tiers of ten levels each. Two knobs tighten continuously — grids grow,
`mem_time` shrinks — while each tier introduces exactly one escalation so
players are never asked to learn two things at once.

- **Tier 1 — Beginner (ids 1-10).** Friendly warm-ups on 6x5 → 7x6 grids,
  short paths (6-12 tiles), generous 4.5s → 3.6s reveals, no flippers. Pure
  memory except two gentle timed intros (4, 9: clock = 2.2 × par) and one
  pattern intro (8). Teaches the core loop: watch, memorize, walk.
- **Tier 2 — Intermediate (ids 11-20).** Confident runs on 7x7 → 8x7 grids,
  paths 13-20, reveals 3.4s → 2.5s, timed clock tightens to 1.8 × par (ids
  13, 16, 19), pattern appears twice (12, 17). Bigger boards mean more
  lateral zigzag to memorize in less time.
- **Tier 3 — Advanced (ids 21-30).** Sharp, fast decisions on 8x8 → 9x8
  grids, paths 21-28, reveals 2.4s → 1.95s, timed clock at 1.6 × par (ids 23,
  26, 29), pattern three times (22, 25, 28). Recollection gives way to
  reaction; the alternating pattern/timed cadence keeps mode-switching
  skills hot.
- **Tier 4 — Expert (ids 31-40).** Ominous boards on 9x9 → 10x9 grids, paths
  29-34, reveals down to 1.45s, timed clock at 1.45 × par (ids 33, 36, 39).
  **Introduces flippers:** one off-path flipper (ids 31-35), then two (36-40),
  all with slow 3.0-3.5s periods. Players learn to read flipper rhythm as a
  third layer on top of the route.
- **Tier 5 — Master (ids 41-50).** Legendary 10x10 → 11x10 arenas, paths
  35-40, reveals 1.4s → 1.1s, timed clock at 1.3 × par (ids 43, 46, 48).
  Flippers everywhere and faster (2.6-3.2s): two off-path (41-43), then
  2 off + 1 on-path (44-47), then 2 off + 2 on-path (48-50) — the final boss
  "Eye of the Storm" requires timing your own safe tiles. Tier 5 leans on
  pattern mode (42, 44, 47, 49, 50) because sequencing 40 steps is the
  ultimate test.

## 5. The 50 levels

| id | name | mode | grid (cols x rows) | path len | mem_time | time_limit | flippers | par | gold |
|----|------|------|--------------------|----------|----------|------------|----------|-----|------|
| 1 | First Contact | memory | 6x5 | 6 | 4.5 | 0.0 | - | 6.2 | 4.3 |
| 2 | Warm-Up Circuit | memory | 6x5 | 7 | 4.4 | 0.0 | - | 6.8 | 4.8 |
| 3 | Neon Steps | memory | 6x5 | 8 | 4.3 | 0.0 | - | 7.5 | 5.2 |
| 4 | Gentle Current | timed | 6x6 | 9 | 4.2 | 18.0 | - | 8.1 | 5.7 |
| 5 | Spark Walk | memory | 6x6 | 10 | 4.1 | 0.0 | - | 8.7 | 6.1 |
| 6 | Soft Glow Alley | memory | 7x6 | 10 | 4.0 | 0.0 | - | 8.7 | 6.1 |
| 7 | Hello Voltage | memory | 7x6 | 11 | 3.9 | 0.0 | - | 9.3 | 6.5 |
| 8 | Test Charge | pattern | 7x6 | 11 | 3.8 | 0.0 | - | 9.3 | 6.5 |
| 9 | Bright Beginnings | timed | 7x6 | 12 | 3.7 | 22.0 | - | 9.9 | 6.9 |
| 10 | Circuit Break-In | memory | 7x6 | 12 | 3.6 | 0.0 | - | 9.9 | 6.9 |
| 11 | Static Alley | memory | 7x7 | 13 | 3.4 | 0.0 | - | 10.6 | 7.4 |
| 12 | Buzzing Bridge | pattern | 7x7 | 14 | 3.3 | 0.0 | - | 11.2 | 7.8 |
| 13 | Current Affairs | timed | 7x7 | 15 | 3.2 | 22.0 | - | 11.8 | 8.3 |
| 14 | Live Wire Lane | memory | 7x7 | 16 | 3.1 | 0.0 | - | 12.4 | 8.7 |
| 15 | Amp It Up | memory | 7x7 | 17 | 3.0 | 0.0 | - | 13.0 | 9.1 |
| 16 | Charge Runner | timed | 8x7 | 17 | 2.9 | 24.0 | - | 13.0 | 9.1 |
| 17 | Voltage Vista | pattern | 8x7 | 18 | 2.8 | 0.0 | - | 13.7 | 9.6 |
| 18 | Zap Zone | memory | 8x7 | 18 | 2.7 | 0.0 | - | 13.7 | 9.6 |
| 19 | Flow State | timed | 8x7 | 19 | 2.6 | 26.0 | - | 14.3 | 10.0 |
| 20 | Pulse Point | memory | 8x7 | 20 | 2.5 | 0.0 | - | 14.9 | 10.4 |
| 21 | Arc Reactor | memory | 8x8 | 21 | 2.4 | 0.0 | - | 15.5 | 10.8 |
| 22 | Tesla Coil | pattern | 8x8 | 22 | 2.35 | 0.0 | - | 16.1 | 11.3 |
| 23 | High Frequency | timed | 8x8 | 23 | 2.3 | 27.0 | - | 16.8 | 11.8 |
| 24 | Storm Circuit | memory | 8x8 | 24 | 2.25 | 0.0 | - | 17.4 | 12.2 |
| 25 | Rapid Discharge | pattern | 8x8 | 25 | 2.2 | 0.0 | - | 18.0 | 12.6 |
| 26 | Ion Corridor | timed | 9x8 | 25 | 2.15 | 29.0 | - | 18.0 | 12.6 |
| 27 | Plasma Path | memory | 9x8 | 26 | 2.1 | 0.0 | - | 18.6 | 13.0 |
| 28 | Surge Sector | pattern | 9x8 | 26 | 2.05 | 0.0 | - | 18.6 | 13.0 |
| 29 | Bolt Barrage | timed | 9x8 | 27 | 2.0 | 31.0 | - | 19.2 | 13.4 |
| 30 | Critical Current | memory | 9x8 | 28 | 1.95 | 0.0 | - | 19.9 | 13.9 |
| 31 | Overload | memory | 9x9 | 29 | 1.9 | 0.0 | 1 off | 20.5 | 14.3 |
| 32 | Meltdown Mile | pattern | 9x9 | 29 | 1.85 | 0.0 | 1 off | 20.5 | 14.3 |
| 33 | Blackout Vault | timed | 9x9 | 30 | 1.8 | 31.0 | 1 off | 21.1 | 14.8 |
| 34 | Fault Line | memory | 9x9 | 30 | 1.75 | 0.0 | 1 off | 21.1 | 14.8 |
| 35 | Grid Reaper | pattern | 9x9 | 31 | 1.7 | 0.0 | 1 off | 21.7 | 15.2 |
| 36 | Redline Capacity | timed | 10x9 | 31 | 1.65 | 32.0 | 2 off | 21.7 | 15.2 |
| 37 | Short Fuse | memory | 10x9 | 32 | 1.6 | 0.0 | 2 off | 22.3 | 15.6 |
| 38 | Killer Watt | pattern | 10x9 | 32 | 1.55 | 0.0 | 2 off | 22.3 | 15.6 |
| 39 | Voltage Vortex | timed | 10x9 | 33 | 1.5 | 34.0 | 2 off | 23.0 | 16.1 |
| 40 | Death Circuit | memory | 10x9 | 34 | 1.45 | 0.0 | 2 off | 23.6 | 16.5 |
| 41 | The Gauntlet | memory | 10x10 | 35 | 1.4 | 0.0 | 2 off | 24.2 | 16.9 |
| 42 | Thunder Dome | pattern | 10x10 | 35 | 1.35 | 0.0 | 2 off | 24.2 | 16.9 |
| 43 | Final Frequency | timed | 10x10 | 36 | 1.3 | 33.0 | 2 off | 24.8 | 17.4 |
| 44 | Omega Circuit | pattern | 10x10 | 36 | 1.25 | 0.0 | 2 off + 1 on | 26.8 | 18.8 |
| 45 | Mythic Megavolt | memory | 10x10 | 37 | 1.2 | 0.0 | 2 off + 1 on | 27.4 | 19.2 |
| 46 | Zenith Surge | timed | 11x10 | 37 | 1.2 | 36.0 | 2 off + 1 on | 27.4 | 19.2 |
| 47 | Apocalypse Amp | pattern | 11x10 | 38 | 1.15 | 0.0 | 2 off + 1 on | 28.1 | 19.7 |
| 48 | Singularity Steps | timed | 11x10 | 38 | 1.15 | 40.0 | 2 off + 2 on | 30.1 | 21.1 |
| 49 | Master Circuit | pattern | 11x10 | 39 | 1.15 | 0.0 | 2 off + 2 on | 30.7 | 21.5 |
| 50 | Eye of the Storm | pattern | 11x10 | 40 | 1.1 | 0.0 | 2 off + 2 on | 31.3 | 21.9 |

Totals: 22 memory, 14 timed, 14 pattern; 35 off-path and 10 on-path flippers
across 20 levels.

## 6. Determinism and regeneration

Every level is generated from a fixed recipe with `random.Random(1000 + id)`
as the only randomness source, so the 50 JSON files are **byte-identical on
every machine and every run** (verified by re-running and hashing). To
regenerate and re-validate all levels from scratch:

```bash
python3 scripts-dev/gen_levels.py            # writes + validates all 50 files
python3 scripts-dev/gen_levels.py --table    # ... also prints the §5 table
```

The script is pure Python 3 stdlib (no numpy, no network), lives in
`scripts-dev/gen_levels.py`, writes to `data/levels/`, and **re-reads every
file from disk** to validate: schema keys/types/order, id ↔ filename, grid
bounds (5-12), all path rules, flipper bounds/period/phase/on-path rules,
timing formulas, `mem_time >= 1.0`, `time_limit >= par + 3` for timed levels
and `0.0` otherwise. It prints one `LEVEL NNN OK` line per level and exits
with code 1 on any failure, so it can gate CI.
