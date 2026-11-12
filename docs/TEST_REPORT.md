# Test Report — Electric Tile Challenge 3D

Report generated at release `v1.0.0`. Testing philosophy: **every claim in this
document comes from an automated gate that runs in CI on every push**, or is
explicitly marked as untested. Nothing is assumed.

## Automated gates (all run on GitHub Actions, ubuntu-latest)

| # | Gate | What it proves | Status |
|---|---|---|---|
| 1 | `godot --headless --import` | Every script in the project compiles; every resource imports (textures, WAVs, icons, scene) | **PASS** (exit 0, zero `SCRIPT ERROR`) |
| 2 | `--check-only` per `.gd` file | Per-file syntax + static checks (with documented filter for autoload identifiers that are not registered in `--script` mode) | **PASS** |
| 3 | `scripts-dev/validate_levels.gd` | All 50 level JSONs: schema, bounds, 4-adjacency, non-decreasing rows, start/end rows, no repeats, flipper rules, timing sanity (`time_limit ≥ par+3`, `mem_time ≥ 1.0`) | **PASS — 50/50** |
| 4 | Headless smoke test (`ETC_SMOKE=1`) | Boots the real game: player + tile grid built; READY→REVEAL→PLAY reached; **walks the entire safe path tile-by-tile**; victory fires; **retry flow resets state**; deliberately stepping on a lethal tile triggers the fail flow; menu/level-select/settings screens all construct | **PASS — 8/8 checks, zero script errors** |
| 5 | Release APK export | Preset + icons + keystore validated by Godot; APK signed with `apksigner` (verified by Godot at export step) | **PASS** (also reproduced locally) |
| 6 | Screenshot render (software GL, non-blocking) | Real rendering of menu + gameplay produces non-empty frames | Evidence artifact on each run |

Smoke-test transcript summary (from the log):

```
SMOKE OK: player exists
SMOKE OK: tile grid built (30)
SMOKE OK: safe path built (6 cells)
SMOKE OK: reached PLAY phase
SMOKE OK: all path tiles stepped (6/6)
SMOKE OK: victory flow fired
SMOKE OK: restart reached PLAY phase
SMOKE OK: zap failure triggered
SMOKE: ALL CHECKS PASSED
```

## Local verification performed before CI (Integration Lead)

- Export dry-run on the CI-runner-equivalent environment produced
  `ElectricTileChallenge3D.apk` (~47.6 MB) signed + verified via
  `apksigner` — identical steps to CI.
- 50/50 level validation, smoke test 8/8, clean menu boot
  (`--quit-after 600`, zero errors).

## Known limitations (honest reporting)

- **On-device testing is pending user verification.** No physical Android
  device is available in the build environment. The 30 FPS (low-end) / 60 FPS
  (capable) targets are *engineering targets* (budgeted via the quality
  presets, pooled particles, MultiMesh, shared materials, capped lights) —
  **they are not claimed as measured results** until you test on your device:

  ```bash
  adb install -r ElectricTileChallenge3D.apk
  adb shell dumpsys gfxinfo com.electrictile.challenge   # frame stats
  ```

  Suggested test matrix: one low-end (2 GB RAM) and one mid/high device;
  compare Low vs High presets in-game; watch memory in Android Studio
  profiler.
- Headless rendering prints benign `dummy mesh storage` warnings during CI
  runs — a headless-renderer artifact, not present on device.
- The smoke test teleports the player across tiles (deterministic) instead of
  using the joystick; touch input itself is validated by interaction, not
  automation (no touchscreen in CI).
- Multi-touch pinch zoom and back-button behavior are best verified on a
  physical device.

## Bug handling log (Phase 11 QA)

| Issue | Root cause | Fix | Re-test |
|---|---|---|---|
| Import failed on `AudioManager.gd` | `AudioServer.bus_set_send()` does not exist in 4.3 | removed (new buses send to Master by default) | PASS |
| Screens failed compile | `:=` type inference on untyped dict/array values in `challenge.gd` | explicit untyped vars | PASS |
| Smoke test hung at screen switch | coroutine bound to gameplay node that got freed on navigation | moved screen-exercise round to persistent `Main` | PASS |
| `Unknown SFX: win` | missing SFX map entry | mapped `win` → victory riser | PASS |
| Export refused to run | Godot needs JDK + Android SDK paths in editor settings | SDK install + settings written in CI (and locally) | PASS |

## Regression policy

All six gates re-run on **every** push. A red gate blocks the APK artifact,
so a regression cannot ship silently. Re-running failed tests after a fix is
automatic (push triggers everything).
