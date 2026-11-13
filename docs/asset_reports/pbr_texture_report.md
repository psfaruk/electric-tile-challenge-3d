# PBR Texture Report — TV-Studio Environment

**Task ID:** 4-b (Materials & Texture Specialist)
**Generator:** `scripts-dev/gen_textures_pbr.py` — pure numpy + zlib PNG writer, no PIL, deterministic (all RNG is `np.random.default_rng(fixed_seed)`), same pipeline/conventions as `scripts-dev/gen_textures.py` (SR=2 supersampling, `write_png`, `grid`, `seg_dist` copied verbatim).
**Output:** `assets/textures/pbr/` — 21 PNGs, 3,103,345 bytes total (~2.96 MiB). 8-bit RGB, no alpha.
**Status:** `python3 scripts-dev/gen_textures_pbr.py` exits 0, prints `PBR TEXTURES: ALL GENERATED OK`; two consecutive runs produce byte-identical SHA-256 hashes (determinism verified).

Style: dark indoor TV-studio — neutral steel, graphite, concrete, rubber, deep burgundy drape, tungsten-warm LED accents. No neon palettes, no vignettes/gradients (all luminance variation is periodic so every texture tiles).

## 1. Generated files

| File | Size (px) | Bytes | Set / intended material use |
|---|---|---|---|
| `steel_brushed_albedo.png` | 512x512 | 227,490 | A) Brushed stainless — stage trim, podium fascia, light rigging |
| `steel_brushed_normal.png` | 512x512 | 113,256 | low-strength horizontal-groove normals |
| `steel_brushed_rough.png` | 512x512 | 108,142 | 0.30 base ±0.08 streak modulation |
| `steel_painted_dark_albedo.png` | 512x512 | 168,588 | B) Graphite powder-coat — floor frames, rigging, dark studio furniture |
| `steel_painted_dark_normal.png` | 512x512 | 223,557 | chip recess + orange-peel + lip burr normals |
| `steel_painted_dark_rough.png` | 512x512 | 137,396 | ~0.45 paint / ~0.25 chips |
| `concrete_wall_albedo.png` | 512x512 | 228,800 | C) Poured studio concrete — back walls, utility corridors |
| `concrete_wall_normal.png` | 512x512 | 226,716 | seams/pits/blotch heightfield normals |
| `concrete_wall_rough.png` | 512x512 | 164,127 | 0.85 ±0.1 blotch modulation |
| `rubber_mat_albedo.png` | 512x512 | 124,628 | D) Anti-slip rubber — stage walkways, cable ramps, safety mats |
| `rubber_mat_normal.png` | 512x512 | 458,055 | raised diamond tread (low-relief domes) |
| `rubber_mat_rough.png` | 512x512 | 151,786 | ~0.95 matte |
| `audience_crowd_albedo.png` | 1024x256 | 118,498 | E) Seated-audience billboard — arena surround band |
| `audience_crowd_rough.png` | 1024x256 | 55,332 | ~0.8 crowd / 0.55 railing / 0.22 phone screens |
| `led_walls_show_albedo.png` | 1024x512 | 54,798 | F) **LED video-wall show content — map to EMISSION in-engine** (see §4) |
| `curtain_stage_albedo.png` | 512x512 | 114,625 | G) Theatrical drape — backdrop behind the stage |
| `curtain_stage_normal.png` | 512x512 | 116,545 | large vertical folds, medium strength |
| `curtain_stage_rough.png` | 512x512 | 45,864 | 0.65 fold ridges / 0.85 valleys |
| `tile_top_glass_albedo.png` | 512x512 | 69,546 | H) Smoked-glass tile caps — sits on the tile LED frames |
| `tile_top_glass_normal.png` | 512x512 | 83,851 | very-low-strength frosted streak + hairline normals |
| `tile_top_glass_rough.png` | 512x512 | 111,745 | 0.08–0.18 varying |

Measured stats from the generator log (sanity-checked, asserted at generation time):

| Set | Albedo luminance | Roughness | Normal max tilt / channels |
|---|---|---|---|
| steel_brushed | mean 0.617 (p01 0.560, p99 0.673) — spec 0.55–0.70 | mean 0.301, p01 0.255, p99 0.346 — spec 0.30±0.08 | 0.169; green 106..149 (horizontal grooves live in green, red stays 125..130 — correct anisotropy) |
| steel_painted_dark | mean 0.101, paint band ~0.083–0.12, chips peak 0.45 | mean 0.448 (paint 0.45 / chips 0.25) | 0.422 at chip lips; red 74..180, green 76..179 |
| concrete_wall | mean 0.444 (p01 0.390, p99 0.507) — spec 0.35–0.5 | mean 0.844, p01 0.797, p99 0.907 — spec 0.85±0.1 | 0.239; seams rows measurably darker (0.357/0.320 vs 0.442 global) |
| rubber_mat | mean 0.049 — spec 0.03–0.06 | mean 0.945 — spec ~0.95 | 0.466 (diamonds read clearly) |
| audience_crowd | mean 0.060, p99 0.133, phone cores 19 px > 0.5 (max 0.72) | mean 0.818 — spec ~0.8 flat-ish | n/a (billboard, no normal by design) |
| led_walls_show | mean 0.294, p01 0.023 (near-black base #05070a), p99 0.967; band cores measured: amber (0.986, 0.766, 0.288), cool white (0.908, 0.963, 0.989), teal (0.179, 0.913, 0.809) — matches spec colors | n/a (emission texture) | n/a (flat screen content by design) |
| curtain_stage | mean lum 0.066; R≈2.6×G (warm burgundy), ridge base ≈ (0.17, 0.05, 0.05) | mean 0.766, p01 0.671 (ridges), p99 0.861 (valleys) | 0.461; red 69..185 carries the folds (correct — folds vary in X), green 119..135 subtle wrinkles |
| tile_top_glass | mean 0.034 (p01 0.029, p99 0.039) — spec 0.02–0.05 | mean 0.119, p01 0.085, p99 0.155 — spec 0.08–0.18 | 0.040 (very low, as specified) |

## 2. Suggested in-engine material settings (Godot 4.3 StandardMaterial3D)

| Set | Metallic | Roughness | Roughness texture | Normal map | Notes |
|---|---|---|---|---|---|
| steel_brushed | **1.0** | 0.5 (unused) | enable, scale 1.0 | enable, scale **0.4** | texture stays grayscale-neutral; metalness comes from the material |
| steel_painted_dark | **0.15** | 0.5 | enable, scale 1.0 | enable, scale **0.6** | single-material compromise: paint is dielectric, chips want metallic 1.0. If a metallic texture is wanted later, the chip mask is recoverable from `albedo > 0.25` |
| concrete_wall | **0.0** | 0.85 (unused) | enable, scale 1.0 | enable, scale **0.7** | matte wall; disable specular beyond default |
| rubber_mat | **0.0** | 0.95 (unused) | enable, scale 1.0 | enable, scale **0.9–1.0** | near-black; keep albedo as-is, no emission |
| audience_crowd | **0.0** | 0.8 (unused) | enable, scale 1.0 | none | render on a curved/plane billboard; suggest `Unshaded` or low ambient so rows fall into darkness; tile horizontally only |
| led_walls_show | **0.0** | 0.35 flat | none | none | **use as EMISSION** (§4); keep albedo at ~ (0.02, 0.02, 0.02) dark gray |
| curtain_stage | **0.0** | 0.75 (unused) | enable, scale 1.0 | enable, scale **1.2** | large folds benefit from stronger normal scale; back-light slightly warm if desired |
| tile_top_glass | **0.0** | 0.5 (unused) | enable, scale 1.0 | enable, scale **0.25** | transparency alpha 0.35–0.6 over the tile LED frame; optional refraction for close-ups |

UV tiling hints: all sets tile in both axes; the LED wall content is designed to repeat per screen module (1 UV = one 1024x512 module).

## 3. Normal-map convention (verified)

Tangent-space, OpenGL/Godot. From heightfield `h(x, y)` with `y` = image row increasing **downward**:

```
dhdx = np.gradient-equivalent along axis 1   dhdy = along axis 0
nx = -dhdx * strength;  ny = +dhdy * strength;  nz = 1.0   -> normalize
rgb  = (n * 0.5 + 0.5) * 255
```

- Gradients are computed with `np.roll` central differences (`(roll(-1) - roll(+1)) * 0.5`), so the normal tiles seamlessly with the heightfield — no one-sided edge differences.
- **Flat-field ground truth:** a zero heightfield encodes to exactly **(128, 128, 255)** — asserted by `selftest_normal_flat()` at every run start (first thing printed).
- Anisotropy sanity: brushed steel varies in green (horizontal grooves), curtain folds vary in red (vertical folds) — the channels follow the geometry directions correctly.

## 4. Tileability — construction guarantees + automated audit

**Guarantees (by construction, not eyeballing):**
1. `periodic_noise(w, h, cellx, celly, seed)` — new helper replacing `gen_textures.noise_field` (whose `+2` lattice and crop **break** periodicity). It is a wrapped-lattice value noise: smoothstep interpolation between lattice corners with modular indexing, and it **asserts** `w % cellx == 0` and `h % celly == 0`. The output is therefore exactly one period of the pattern in both axes. `periodic_fbm` sums such octaves (all cells divide the image), so fBm is also exactly periodic.
2. `periodic_white` — per-pixel stationary white noise: no structure exists to break at a seam, so the wrap edge is statistically identical to any interior cut.
3. Blobs (paint chips, concrete pits, phone dots, and every audience silhouette) are placed at random positions but rendered through **torus distance** (`wrap_dist`/`wrap_dx`), so shapes that cross an edge continue on the opposite side instead of being cut.
4. Geometric patterns use explicit mod-period coordinates: curtain folds (64 px), rubber diamond tread (64 px), LED sweep `u = (px+py) % 512`, LED scanlines `% 8`, LED circuit lattice `mod 128` (2:1 iso slopes — see §5).

**Automated audit (gate 3):** every emitted file passes `tile_check()`, which rolls the final float image by `(h//2, w//2)` and measures discontinuity at four lines: both rolled borders (interior continuity) **and** the rolled mid-lines — the roll relocates the image's own wrap seams into the interior, so the four checks cover the true left/right and top/bottom seams. A seam passes if it is no worse than the image's own adjacent-pixel difference statistics (`seam <= max(1.5 × p99.9, 6 × mean, 0.02)`). Results: **21/21 files pass**; worst-case ratios are ≤0.2 for most files. The single highest ratio (0.96, `audience_crowd_rough` vertical wrap) is the designed content edge where the bottom barrier band (rough 0.55) meets the dark hall background above the back row (0.90) — identical in magnitude to the barrier's own interior top-rail edge, i.e. pattern content, not a tiling defect. The crowd is intended to tile horizontally along the arena wall band.

**PNG validity (gate 2):** after generation, every file is re-parsed by `verify_png()`: PNG signature, IHDR width/height/bit depth/color type, **all chunk CRCs**, full IDAT inflate with scanline-length check, and IEND presence. 21/21 verified (see `verified ...` lines in the run log).

## 5. Deviations & judgment calls

1. **LED "hex-circuit" overlay is a 2:1 iso line lattice, not true 60° hexagons.** Exact tiling requires the pattern's projection shifts (`w·cosθ`, `h·sinθ`) to be integer multiples of the period; 60° hexagons have irrational `√3/2` components and mathematically cannot wrap on a power-of-two texture. The 2:1 iso grid (horizontal + two diagonal families, plus node dots at crossings) is the established pixel-art hex convention, reads as faint tech-circuitry at billboard distance, and tiles perfectly. Documented in the generator docstring.
2. **`led_walls_show` file is named `_albedo` but is intended for the EMISSION slot.** Kept the `_albedo` suffix for set-naming consistency; the in-engine setup is: albedo ≈ (0.02, 0.02, 0.02), emission = this texture, emission_energy ≈ 2.5–4.0 (bright band cores hit 1.0 and stay saturated for HDR bloom). Asserted at generation: max lum > 0.6, median < 0.1.
3. **Glass micro-scratches are kept ≥20 px away from the tile borders** (length-clipped segments). Interior-only features are trivially tileable; wrapping thin line segments would add complexity for no visible gain. Everything else in the set is periodic-noise based.
4. **Audience crowd has no normal map** (billboard at distance — flat by design) and **LED content has no normal/rough** (flat emissive screen — roughness fixed at 0.35 in-engine). Both reductions are per the set specs.
5. **Curtain fold normals were re-tuned** after the first run: a 64 px-period cosine fold has a small per-pixel slope (amp × π/period), so the normal strength was raised 4.5 → 10.0 with wrinkle height reduced to keep wrinkles subtle. Measured result: fold normals reach tilt 0.461 (≈27°) in red — large folds read clearly, wrinkles stay ≤ ~6°.
6. **`steel_painted_dark` chips** are biased 72% toward tile borders (5–30 px from an edge) so that, when tiled as floor panels, wear gathers along panel seams/corners; ~2% of area is chipped, exposing ~0.45 metal in albedo and dropping roughness to ~0.25.
7. **No vertical gradients / vignettes anywhere** — gradients across a tile break the wrap seam check. Depth in the crowd comes from discrete per-row dimming (period 1 row), which tiles by construction.

## 6. Quality-gate transcript (condensed)

```
PBR TEXTURES: TV-studio material library
normal self-test: flat field -> (128,128,255) OK
... (8 sets; per-set stats lines; per-file:)
  tileable OK [...] (21 files)    wrote assets/textures/pbr/...  WxH  N bytes   (21 files)
re-parse gate:
  verified assets/textures/pbr/...  (21 files)
PBR TEXTURES: ALL GENERATED OK          # exit code 0
```

Determinism: two consecutive full runs → identical stdout and identical SHA-256 per file.
No existing files were modified; new files only: `scripts-dev/gen_textures_pbr.py`, `assets/textures/pbr/*.png` (21), `docs/asset_reports/pbr_texture_report.md`. Nothing committed (Integration Lead commits).
