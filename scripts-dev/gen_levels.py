#!/usr/bin/env python3
"""
gen_levels.py — deterministic level generator + validator for
"Electric Tile Challenge 3D" (Godot 4.3 / Android).

Produces data/levels/level_001.json .. level_050.json from the frozen
parameter tables below, then re-reads every file from disk and validates it
against the frozen level schema, the path rules, the flipper rules and the
timing formulas. Any failure exits with code 1.

Determinism: every level is built with random.Random(1000 + id), so the
output is byte-identical on every run and on every machine.

Stdlib only (json / math / random / sys / pathlib). Usage:

    python3 scripts-dev/gen_levels.py            # generate + validate
    python3 scripts-dev/gen_levels.py --table     # ... also print a markdown
                                                 # table of all 50 levels
"""

from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS_DIR = ROOT / "data" / "levels"

LEVEL_COUNT = 50
SEED_BASE = 1000  # per-level seed = SEED_BASE + id

# ---------------------------------------------------------------------------
# Frozen parameter tables (verbatim from the level design spec — engine
# depends on these values; do not edit casually)
# ---------------------------------------------------------------------------

NAMES = [
    # tier 1 — friendly warm-ups
    "First Contact", "Warm-Up Circuit", "Neon Steps", "Gentle Current",
    "Spark Walk", "Soft Glow Alley", "Hello Voltage", "Test Charge",
    "Bright Beginnings", "Circuit Break-In",
    # tier 2 — confident
    "Static Alley", "Buzzing Bridge", "Current Affairs", "Live Wire Lane",
    "Amp It Up", "Charge Runner", "Voltage Vista", "Zap Zone",
    "Flow State", "Pulse Point",
    # tier 3 — sharp
    "Arc Reactor", "Tesla Coil", "High Frequency", "Storm Circuit",
    "Rapid Discharge", "Ion Corridor", "Plasma Path", "Surge Sector",
    "Bolt Barrage", "Critical Current",
    # tier 4 — ominous
    "Overload", "Meltdown Mile", "Blackout Vault", "Fault Line",
    "Grid Reaper", "Redline Capacity", "Short Fuse", "Killer Watt",
    "Voltage Vortex", "Death Circuit",
    # tier 5 — legendary
    "The Gauntlet", "Thunder Dome", "Final Frequency", "Omega Circuit",
    "Mythic Megavolt", "Zenith Surge", "Apocalypse Amp", "Singularity Steps",
    "Master Circuit", "Eye of the Storm",
]

# target path lengths — ten entries per tier, indexed by (id - 1) % 10
PATH_LEN = {
    1: [6, 7, 8, 9, 10, 10, 11, 11, 12, 12],
    2: [13, 14, 15, 16, 17, 17, 18, 18, 19, 20],
    3: [21, 22, 23, 24, 25, 25, 26, 26, 27, 28],
    4: [29, 29, 30, 30, 31, 31, 32, 32, 33, 34],
    5: [35, 35, 36, 36, 37, 37, 38, 38, 39, 40],
}

# memorization reveal times (seconds) — ten entries per tier
MEM_TIME = {
    1: [4.5, 4.4, 4.3, 4.2, 4.1, 4.0, 3.9, 3.8, 3.7, 3.6],
    2: [3.4, 3.3, 3.2, 3.1, 3.0, 2.9, 2.8, 2.7, 2.6, 2.5],
    3: [2.4, 2.35, 2.3, 2.25, 2.2, 2.15, 2.1, 2.05, 2.0, 1.95],
    4: [1.9, 1.85, 1.8, 1.75, 1.7, 1.65, 1.6, 1.55, 1.5, 1.45],
    5: [1.4, 1.35, 1.3, 1.25, 1.2, 1.2, 1.15, 1.15, 1.15, 1.1],
}

# timed-mode countdown factor per tier: time_limit = ceil(par * factor)
TIME_FACTOR = {1: 2.2, 2: 1.8, 3: 1.6, 4: 1.45, 5: 1.3}

MODE_TIMED = {4, 9, 13, 16, 19, 23, 26, 29, 33, 36, 39, 43, 46, 48}
MODE_PATTERN = {8, 12, 17, 22, 25, 28, 32, 35, 38, 42, 44, 47, 49, 50}


def tier_for(lid: int) -> int:
    """Difficulty tier 1..5 for a level id 1..50."""
    return (lid - 1) // 10 + 1


def grid_for(lid: int) -> tuple[int, int]:
    """(cols, rows) by level id — 'grids' table from the spec."""
    if lid <= 3:
        return 6, 5
    if lid <= 5:
        return 6, 6
    if lid <= 10:
        return 7, 6
    if lid <= 15:
        return 7, 7
    if lid <= 20:
        return 8, 7
    if lid <= 25:
        return 8, 8
    if lid <= 30:
        return 9, 8
    if lid <= 35:
        return 9, 9
    if lid <= 40:
        return 10, 9
    if lid <= 45:
        return 10, 10
    return 11, 10


def mode_for(lid: int) -> str:
    if lid in MODE_TIMED:
        return "timed"
    if lid in MODE_PATTERN:
        return "pattern"
    return "memory"


def flippers_for(lid: int) -> tuple[int, int, float, float]:
    """(n_off_path, n_on_path, period_min, period_max) by level id."""
    if lid <= 30:
        return 0, 0, 0.0, 0.0     # tiers 1-3: no flippers
    if lid <= 35:
        return 1, 0, 3.0, 3.5     # tier 4, ids 31-35: one off-path flipper
    if lid <= 40:
        return 2, 0, 3.0, 3.5     # tier 4, ids 36-40: two off-path flippers
    if lid <= 43:
        return 2, 0, 2.6, 3.2     # tier 5, ids 41-43
    if lid <= 47:
        return 2, 1, 2.6, 3.2     # tier 5, ids 44-46 and the id-47 exception
    return 2, 2, 2.6, 3.2         # tier 5, ids 48-50


# ---------------------------------------------------------------------------
# Path generation
# ---------------------------------------------------------------------------

def gen_path(rng: random.Random, rows: int, cols: int,
             length: int) -> list[list[int]]:
    """
    Generate the ordered safe path as a list of [row, col] cells.

    Spec algorithm: start at (0, random col). While the remaining length
    budget exceeds the number of rows still to be crossed, insert a lateral
    move (c +/- 1; must stay in bounds and not revisit a cell); if that is
    impossible, advance the row instead (zigzag escape). Otherwise advance
    the row by +1. The walk finishes on row rows-1 having used the budget
    exactly, with the row index never decreasing and every row visited.

    Direction heuristic (guarantees the exact budget is always satisfiable):
    among the legal lateral moves, prefer one whose remaining runway can
    absorb the whole surplus (pick randomly among those); if none can, take
    the direction with the longest runway. A segment that hits a wall exits
    at the wall, so the next row is entered with full sweep capacity, which
    keeps the leftover surplus absorbable all the way to the final row.
    """
    max_len = (rows - 1) + rows * (cols - 1)
    if not (rows <= length <= max_len):
        raise ValueError(
            f"target length {length} outside [{rows}, {max_len}] "
            f"for a {cols}x{rows} grid")

    c = rng.randrange(cols)
    path = [[0, c]]
    visited = {(0, c)}

    while len(path) < length:
        r, c = path[-1]
        budget = length - len(path)          # moves still needed
        rows_left = (rows - 1) - r           # row advances still needed
        surplus = budget - rows_left         # moves that must be lateral

        if surplus > 0:
            options = []
            for nc in (c - 1, c + 1):
                if 0 <= nc < cols and (r, nc) not in visited:
                    runway = (cols - 1 - c) if nc > c else c
                    options.append((nc, runway))
            if options:
                safe = [nc for nc, runway in options if runway >= surplus]
                if safe:
                    nc = rng.choice(safe)
                else:
                    longest = max(runway for _, runway in options)
                    nc = rng.choice(
                        [nc for nc, runway in options if runway == longest])
                path.append([r, nc])
                visited.add((r, nc))
                continue
            if r < rows - 1:
                # Lateral move impossible — advance the row early instead
                # (zigzag escape r,c -> r+1,c -> ... keeps surplus for later).
                path.append([r + 1, c])
                visited.add((r + 1, c))
                continue
            raise RuntimeError(
                f"path generation stuck on final row "
                f"({cols}x{rows}, target length {length})")

        # surplus exhausted: every remaining move must be a row advance
        path.append([r + 1, c])
        visited.add((r + 1, c))

    assert len(path) == length, "exact length budget violated"
    assert path[-1][0] == rows - 1, "path must finish on the last row"
    return path


# ---------------------------------------------------------------------------
# Flipper generation
# ---------------------------------------------------------------------------

def gen_flippers(rng: random.Random, lid: int, rows: int, cols: int,
                 path: list[list[int]]) -> list[list[int]]:
    """
    Flippers are hazard tiles that alternate safe/danger during play:
    [row, col, period, phase, on_path].

    - off-path flippers (on_path == 0) sit outside the safe path;
    - on-path flippers (on_path == 1) occupy a safe-path cell with
      path index >= 2 (never path[0], never path[1]).
    """
    n_off, n_on, pmin, pmax = flippers_for(lid)
    if n_off == 0 and n_on == 0:
        return []

    path_cells = [(r, c) for r, c in path]
    path_set = set(path_cells)

    def make(cell: tuple[int, int], on_path: int) -> list:
        period = round(rng.uniform(pmin, pmax), 2)
        phase = round(rng.uniform(0.0, period), 2)
        if phase >= period:                  # keep phase strictly below period
            phase = round(period - 0.01, 2)
        return [cell[0], cell[1], period, phase, on_path]

    flippers: list[list[int]] = []

    # off-path: any in-bounds cell NOT on the path (distinct by sample())
    off_candidates = [(r, c) for r in range(rows) for c in range(cols)
                      if (r, c) not in path_set]
    for cell in rng.sample(off_candidates, n_off):
        flippers.append(make(cell, 0))

    # on-path: distinct path cells with index >= 2 (path cells are unique,
    # so sampled indices give distinct flipper cells)
    for idx in sorted(rng.sample(range(2, len(path)), n_on)):
        flippers.append(make(path_cells[idx], 1))

    return flippers


# ---------------------------------------------------------------------------
# Level assembly
# ---------------------------------------------------------------------------

def build_level(lid: int) -> dict:
    """Assemble one level dict (keys in frozen schema order)."""
    tier = tier_for(lid)
    cols, rows = grid_for(lid)
    idx = (lid - 1) % 10
    plen = PATH_LEN[tier][idx]

    rng = random.Random(SEED_BASE + lid)
    path = gen_path(rng, rows, cols, plen)
    flippers = gen_flippers(rng, lid, rows, cols, path)

    n_on = sum(1 for f in flippers if f[4] == 1)
    par = round(2.5 + 0.62 * plen + 2.0 * n_on, 1)
    gold = round(par * 0.7, 1)

    mode = mode_for(lid)
    if mode == "timed":
        time_limit = float(max(math.ceil(par * TIME_FACTOR[tier]),
                               math.ceil(par + 3.0)))
    else:
        time_limit = 0.0

    return {
        "id": lid,
        "name": NAMES[lid - 1],
        "mode": mode,
        "tier": tier,
        "cols": cols,
        "rows": rows,
        "mem_time": float(MEM_TIME[tier][idx]),
        "time_limit": time_limit,
        "path": path,
        "flippers": flippers,
        "par_time": par,
        "gold_time": gold,
    }


# ---------------------------------------------------------------------------
# Validation (re-reads each JSON from disk and re-checks everything)
# ---------------------------------------------------------------------------

SCHEMA_KEYS = ["id", "name", "mode", "tier", "cols", "rows", "mem_time",
               "time_limit", "path", "flippers", "par_time", "gold_time"]


def validate_level(data: dict, fp: Path) -> list[str]:
    """Return a list of error messages (empty list == level is valid)."""
    errs: list[str] = []
    e = errs.append

    # --- schema keys (present, exact set, exact order) ----------------------
    if list(data.keys()) != SCHEMA_KEYS:
        e(f"key set/order mismatch: {list(data.keys())}")

    # --- types ---------------------------------------------------------------
    if type(data.get("id")) is not int:
        e("id must be int")
    if not isinstance(data.get("name"), str):
        e("name must be str")
    if data.get("mode") not in ("memory", "timed", "pattern"):
        e("mode must be memory|timed|pattern")
    if type(data.get("tier")) is not int:
        e("tier must be int")
    if type(data.get("cols")) is not int:
        e("cols must be int")
    if type(data.get("rows")) is not int:
        e("rows must be int")
    for k in ("mem_time", "time_limit", "par_time", "gold_time"):
        if type(data.get(k)) is not float:
            e(f"{k} must be float")
    if not isinstance(data.get("path"), list):
        e("path must be a list")
    if not isinstance(data.get("flippers"), list):
        e("flippers must be a list")

    lid = data.get("id")
    if type(lid) is int:
        try:
            fid = int(fp.name.split("_")[1].split(".")[0])
        except (IndexError, ValueError):
            fid = -1
        if fid != lid:
            e(f"id {lid} does not match filename {fp.name}")
        if not (1 <= lid <= LEVEL_COUNT):
            e("id outside 1..50")

    if errs:
        return errs  # basics broken — cannot continue checks safely

    tier, cols, rows = data["tier"], data["cols"], data["rows"]
    if not (5 <= rows <= 12):
        e("rows outside 5..12")
    if not (5 <= cols <= 12):
        e("cols outside 5..12")

    # --- conformance to the frozen tables ------------------------------------
    if tier != tier_for(lid):
        e("tier does not match id")
    if (cols, rows) != grid_for(lid):
        e("grid does not match id")
    if data["mode"] != mode_for(lid):
        e("mode does not match id")
    idx = (lid - 1) % 10
    if data["mem_time"] != MEM_TIME[tier][idx]:
        e("mem_time does not match table")
    if data["mem_time"] < 1.0:
        e("mem_time must be >= 1.0")

    name = data["name"]
    if len(name) > 24:
        e("name longer than 24 chars")
    if any(ch in name for ch in (",", "'", '"')):
        e("name contains forbidden characters (quotes/commas)")

    # --- path rules ------------------------------------------------------------
    path = data["path"]
    plen_target = PATH_LEN[tier][idx]
    if len(path) != plen_target:
        e(f"path length {len(path)} != target {plen_target}")
    bad_cell = False
    for cell in path:
        if (not isinstance(cell, list)) or len(cell) != 2 \
                or any(type(v) is not int for v in cell):
            e(f"bad path cell {cell!r}")
            bad_cell = True
            break
    if not bad_cell:
        if path[0][0] != 0:
            e("path must start on row 0")
        if path[-1][0] != rows - 1:
            e("path must end on row rows-1")
        seen = set()
        for i, (r, c) in enumerate(path):
            if not (0 <= r < rows and 0 <= c < cols):
                e(f"path cell {i} {(r, c)} out of bounds")
                break
            if (r, c) in seen:
                e(f"path cell {i} repeats {(r, c)}")
                break
            seen.add((r, c))
            if i > 0:
                pr, pc = path[i - 1]
                if abs(r - pr) + abs(c - pc) != 1:
                    e(f"path cells {i - 1}->{i} not 4-adjacent")
                    break
                if r < pr:
                    e(f"path row decreases at step {i}")
                    break
        if not errs:
            if {r for r, _ in path} != set(range(rows)):
                e("path does not visit every row 0..rows-1")

    # --- flippers --------------------------------------------------------------
    path_index = {(r, c): i for i, (r, c) in enumerate(path)}
    flip_cells = set()
    n_off_cfg, n_on_cfg, pmin, pmax = flippers_for(lid)
    n_off = n_on = 0
    for f in data["flippers"]:
        if (not isinstance(f, list)) or len(f) != 5:
            e(f"bad flipper entry {f!r}")
            continue
        r, c, period, phase, on_path = f
        if type(r) is not int or type(c) is not int or type(on_path) is not int:
            e(f"flipper {f!r}: r/c/on_path must be int")
            continue
        if type(period) is not float or type(phase) is not float:
            e(f"flipper {f!r}: period/phase must be float")
            continue
        if not (0 <= r < rows and 0 <= c < cols):
            e(f"flipper {(r, c)} out of bounds")
        if period < 2.5:
            e(f"flipper {(r, c)} period {period} < 2.5s")
        if not (0.0 <= phase < period):
            e(f"flipper {(r, c)} phase {phase} not in [0, period)")
        if on_path not in (0, 1):
            e(f"flipper {(r, c)} on_path must be 0/1")
        if (r, c) in flip_cells:
            e(f"duplicate flipper cell {(r, c)}")
        flip_cells.add((r, c))
        if on_path == 0:
            n_off += 1
            if (r, c) in path_index:
                e(f"off-path flipper {(r, c)} lies on the path")
        else:
            n_on += 1
            i = path_index.get((r, c))
            if i is None:
                e(f"on-path flipper {(r, c)} is not on the path")
            elif i < 2:
                e(f"on-path flipper {(r, c)} uses path index {i} (< 2)")
    if n_off != n_off_cfg:
        e(f"expected {n_off_cfg} off-path flippers, found {n_off}")
    if n_on != n_on_cfg:
        e(f"expected {n_on_cfg} on-path flippers, found {n_on}")
    if n_off_cfg or n_on_cfg:
        for r, c, period, phase, on_path in data["flippers"]:
            if not (pmin <= period <= pmax):
                e(f"flipper {(r, c)} period {period} outside [{pmin}, {pmax}]")

    # --- timing ----------------------------------------------------------------
    plen = len(path)
    par_expected = round(2.5 + 0.62 * plen + 2.0 * n_on, 1)
    if data["par_time"] != par_expected:
        e(f"par_time {data['par_time']} != formula {par_expected}")
    gold_expected = round(data["par_time"] * 0.7, 1)
    if data["gold_time"] != gold_expected:
        e(f"gold_time {data['gold_time']} != formula {gold_expected}")
    if not data["gold_time"] < data["par_time"]:
        e("gold_time must be below par_time")
    if data["par_time"] < 1.0:
        e("par_time must be >= 1.0")
    if data["mode"] == "timed":
        tl = data["time_limit"]
        if tl != float(int(tl)):
            e("timed time_limit must be whole seconds stored as float")
        if tl < data["par_time"] + 3.0:
            e("timed time_limit must be >= par_time + 3")
        if tl != float(max(math.ceil(par_expected * TIME_FACTOR[tier]),
                           math.ceil(par_expected + 3.0))):
            e("timed time_limit does not match tier formula")
    elif data["time_limit"] != 0.0:
        e("memory/pattern levels must have time_limit == 0.0")

    return errs


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    print_table = "--table" in argv
    LEVELS_DIR.mkdir(parents=True, exist_ok=True)

    # --- generate all 50 levels and write them --------------------------------
    for lid in range(1, LEVEL_COUNT + 1):
        level = build_level(lid)
        fp = LEVELS_DIR / f"level_{lid:03d}.json"
        with open(fp, "w", encoding="utf-8") as fh:
            json.dump(level, fh, indent=2)
            fh.write("\n")

    # --- exactly the 50 expected files must exist -----------------------------
    produced = sorted(LEVELS_DIR.glob("level_*.json"))
    expected = [LEVELS_DIR / f"level_{i:03d}.json"
                for i in range(1, LEVEL_COUNT + 1)]
    if produced != expected:
        print(f"FATAL: expected exactly {LEVEL_COUNT} level files in "
              f"{LEVELS_DIR}, found {len(produced)}")
        return 1

    # --- re-read every file from disk and validate ------------------------------
    failures = 0
    names: set[str] = set()
    mode_counts = {"memory": 0, "timed": 0, "pattern": 0}
    off_total = on_total = 0
    table_rows: list[str] = []

    for fp in expected:
        with open(fp, encoding="utf-8") as fh:
            data = json.load(fh)

        errs = validate_level(data, fp)
        if data.get("name") in names:
            errs.append(f"duplicate level name {data.get('name')!r}")
        names.add(data.get("name"))

        if errs:
            failures += 1
            print(f"LEVEL {data.get('id', 0):03d} FAIL")
            for msg in errs:
                print(f"    - {msg}")
            continue

        print(f"LEVEL {data['id']:03d} OK")
        mode_counts[data["mode"]] += 1
        off_total += sum(1 for f in data["flippers"] if f[4] == 0)
        on_total += sum(1 for f in data["flippers"] if f[4] == 1)

        if print_table:
            fl = data["flippers"]
            n_off = sum(1 for f in fl if f[4] == 0)
            n_on = sum(1 for f in fl if f[4] == 1)
            if n_off and n_on:
                fl_txt = f"{n_off} off + {n_on} on"
            elif n_off:
                fl_txt = f"{n_off} off"
            elif n_on:
                fl_txt = f"{n_on} on"
            else:
                fl_txt = "-"
            table_rows.append(
                f"| {data['id']} | {data['name']} | {data['mode']} "
                f"| {data['cols']}x{data['rows']} | {len(data['path'])} "
                f"| {data['mem_time']} | {data['time_limit']} | {fl_txt} "
                f"| {data['par_time']} | {data['gold_time']} |")

    print("-" * 62)
    print(f"VALIDATION SUMMARY: {LEVEL_COUNT - failures}/{LEVEL_COUNT} levels OK")
    print(f"  modes: memory={mode_counts['memory']}, "
          f"timed={mode_counts['timed']}, pattern={mode_counts['pattern']}")
    print(f"  flippers: {off_total} off-path, {on_total} on-path")
    if failures:
        print(f"RESULT: FAILED ({failures} level file(s) invalid)")
        return 1
    print("RESULT: PASSED — ALL 50 LEVELS VALID")

    if print_table:
        print()
        print("MARKDOWN TABLE")
        print("| id | name | mode | grid (cols x rows) | path len | "
              "mem_time | time_limit | flippers | par | gold |")
        print("|----|------|------|--------------------|----------|"
              "----------|------------|----------|-----|------|")
        for row in table_rows:
            print(row)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
