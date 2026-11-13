# Challenge — the referee/state machine of every level.
# Phases: READY -> REVEAL (memorize/pattern) -> PLAY -> DONE.
# Enforces: lethal non-path tiles, pattern order, flipper hazard timing,
# time limits, win via finish zone, fail via zap. Emits game_won/game_failed.
extends Node

signal game_won(time_sec: float)
signal game_failed(reason: String)

enum Phase { READY, REVEAL, PLAY, DONE }

const Grid := preload("res://scripts/game/grid.gd")
const U := preload("res://scripts/ui/ui.gd")

const COL_SAFE := Color(0.27, 0.97, 0.51)
const COL_DANGER := Color(1.0, 0.30, 0.30)
const COL_TEAL := Color(0.16, 0.9, 0.78)

var level: Dictionary
var tiles: Dictionary
var player
var sparks
var hud
var cam_rig

var phase := Phase.READY
var mode := "memory"
var path_cells: Array = []
var path_set: Dictionary = {}
var stepped: Dictionary = {}
var next_idx := 0
var flippers: Array = []
var play_t := 0.0
var mem_speed := 1.0

var _cols := 6
var _rows := 6
var _ready_t := 0.0
var _reveal_t := 0.0
var _seq_i := 0
var _seq_timer := 0.0
var _beep_count := -1
var _limit_beep := false

func setup(p_level: Dictionary, p_tiles: Dictionary, p_player, p_sparks, p_hud, p_cam) -> void:
        level = p_level
        tiles = p_tiles
        player = p_player
        sparks = p_sparks
        hud = p_hud
        cam_rig = p_cam
        mode = str(level.get("mode", "memory"))
        _cols = int(level.get("cols", 6))
        _rows = int(level.get("rows", 6))
        for c in level.get("path", []):
                var cell := Vector2i(int(c[0]), int(c[1]))
                path_cells.append(cell)
                path_set[cell] = true
        for f in level.get("flippers", []):
                flippers.append({
                        "cell": Vector2i(int(f[0]), int(f[1])),
                        "period": float(f[2]),
                        "phase0": float(f[3]),
                        "on_path": int(f[4]) == 1,
                        "safe_now": true,
                })

func _shared_mat(col: Color, energy: float) -> StandardMaterial3D:
        # retained for API compatibility; unused with the TileField renderer
        var m := StandardMaterial3D.new()
        m.albedo_color = col * 0.2
        m.emission_enabled = true
        m.emission = col
        m.emission_energy_multiplier = energy
        return m

func _process(delta: float) -> void:
        match phase:
                Phase.READY:
                        _ready_t += delta
                        if _ready_t >= 1.2:
                                _begin_reveal()
                Phase.REVEAL:
                        if mode == "pattern":
                                _seq_timer -= delta
                                if _seq_timer <= 0.0 and _seq_i < path_cells.size():
                                        var tc = tiles.get(path_cells[_seq_i])
                                        if tc != null:
                                                tc.flash_correct(_seq_i)
                                        AudioManager.play_sfx("seq_note", 1.0 + _seq_i * 0.04)
                                        _seq_i += 1
                                        _seq_timer = 0.3
                                        if _seq_i >= path_cells.size():
                                                _seq_timer = 0.8
                                elif _seq_i >= path_cells.size() and _seq_timer <= 0.0:
                                        _begin_play()
                        else:
                                _reveal_t += delta
                                var total := _reveal_total()
                                hud.set_reveal_frac(1.0 - clampf(_reveal_t / total, 0.0, 1.0))
                                var remaining := total - _reveal_t
                                var beep := int(ceil(remaining))
                                if remaining <= 3.05 and remaining > 0.0 and beep != _beep_count:
                                        _beep_count = beep
                                        AudioManager.play_sfx("count", 1.0)
                                if _reveal_t >= total:
                                        _begin_play()
                Phase.PLAY:
                        play_t += delta
                        var limit := float(level.get("time_limit", 0.0))
                        if limit > 0.0:
                                var rem := limit - play_t
                                hud.set_time(true, "%.1f" % maxf(0.0, rem), rem <= 5.0)
                                if rem <= 5.05 and not _limit_beep:
                                        _limit_beep = true
                                        AudioManager.play_sfx("warn")
                                if rem <= 0.0:
                                        _fail("TIME UP")
                                        return
                        else:
                                hud.set_time(true, "%.1f" % play_t, false)
                        _update_flippers()

func _reveal_total() -> float:
        var t := maxf(0.3, float(level.get("mem_time", 3.0)) * mem_speed)
        if mode == "timed":
                t = minf(t, 2.0)
        return t

func _begin_reveal() -> void:
        phase = Phase.REVEAL
        _reveal_t = 0.0
        _seq_i = 0
        _seq_timer = 0.35
        _beep_count = -1
        player.locked = true
        if mode == "pattern":
                for cellv in tiles:
                        tiles[cellv].reset_visual()
                hud.show_banner("MEMORIZE THE ORDER", U.C.accent, 1.6)
        else:
                for cellv in tiles:
                        var tc = tiles[cellv]
                        if path_set.has(cellv):
                                tc.set_shared(true)
                        else:
                                tc.set_shared(false)
                if mode == "timed":
                        hud.show_banner("CROSS BEFORE TIME RUNS OUT!", U.C.gold, 1.5)
                else:
                        hud.show_banner("MEMORIZE THE PATH!", U.C.accent, 1.5)
        AudioManager.play_sfx("tile_show", 1.0, -4.0)



func _begin_play() -> void:
        for cellv in tiles:
                tiles[cellv].reset_visual()
        _apply_flipper_visuals()
        player.locked = false
        play_t = 0.0
        _limit_beep = false
        phase = Phase.PLAY
        hud.set_reveal_frac(0.0)
        hud.show_banner("GO!", U.C.safe, 0.9)
        AudioManager.play_sfx("go")
        if mode == "pattern":
                hud.set_seq(true, 0, path_cells.size())

# ---------------- stepping / rules ----------------

func on_player_cell(cell: Vector2i) -> void:
        if phase != Phase.PLAY:
                return
        if path_set.has(cell):
                var f = _flipper_for(cell)
                if f != null and not f.safe_now:
                        _fail("ZAPPED BY HAZARD", cell)
                        return
                if mode == "pattern":
                        if next_idx < path_cells.size() and cell == path_cells[next_idx]:
                                _correct(cell)
                        elif stepped.has(cell):
                                tiles[cell].flash_neutral()
                        else:
                                _fail("OUT OF ORDER", cell)
                else:
                        _correct(cell)
        else:
                var f2 = _flipper_for(cell)
                if f2 != null and f2.safe_now:
                        tiles[cell].flash_neutral()
                        AudioManager.play_sfx("step", 1.0, -8.0)
                else:
                        _fail("ELECTROCUTED", cell)

func _correct(cell: Vector2i) -> void:
        stepped[cell] = true
        var idx := path_cells.find(cell)
        if mode == "pattern":
                idx = next_idx
                next_idx += 1
                hud.set_seq(true, next_idx, path_cells.size())
        if idx < 0:
                idx = stepped.size()
        tiles[cell].flash_correct(idx)
        sparks.arc(Grid.tile_center(cell, _cols) + Vector3(0, 0.18, 0),
                        Grid.tile_center(cell, _cols) + Vector3(0, 0.85, 0), COL_SAFE)
        AudioManager.play_sfx("seq_note" if mode == "pattern" else "tile_good", 1.0 + idx * 0.045)
        hud.set_progress(stepped.size(), path_cells.size())
        AudioManager.haptic(15)

func on_finish_entered() -> void:
        if phase != Phase.PLAY:
                return
        if mode == "pattern" and next_idx < path_cells.size():
                hud.show_banner("FINISH THE SEQUENCE!", U.C.gold, 1.2)
                return
        _win()

func _win() -> void:
        phase = Phase.DONE
        player.play_victory()
        AudioManager.play_sfx("win")
        AudioManager.haptic(60)
        sparks.confetti(player.global_position)
        hud.show_banner("VICTORY!", U.C.gold, 1.6)
        hud.set_time(false, "", false)
        emit_signal("game_won", play_t)

func _fail(reason: String, cell := Vector2i(-99, -99)) -> void:
        if phase == Phase.DONE:
                return
        phase = Phase.DONE
        player.play_zap()
        if tiles.has(cell):
                tiles[cell].mark_failed()
        sparks.burst(player.global_position + Vector3(0, 0.45, 0), Color(1.0, 0.35, 0.2))
        var zc: Vector3 = player.global_position + Vector3(0, 0.2, 0)
        sparks.arc(zc, zc + Vector3(0.35, 1.1, 0.2), Color(1.0, 0.5, 0.22))
        sparks.arc(zc, zc + Vector3(-0.3, 1.0, -0.25), Color(0.85, 0.95, 1.0))
        hud.flash_screen(U.C.danger)
        cam_rig.shake(1.2)
        AudioManager.play_sfx("zap")
        AudioManager.play_sfx("fail", 1.0, -3.0)
        AudioManager.haptic(200)
        hud.set_time(false, "", false)
        var tw := create_tween()
        tw.tween_interval(0.55)
        tw.tween_callback(_reveal_truth)
        emit_signal("game_failed", reason)

func _reveal_truth() -> void:
        for cellv in tiles:
                var tc = tiles[cellv]
                if path_set.has(cellv):
                        tc.reveal_safe()
                elif _flipper_for(cellv) != null:
                        continue
                else:
                        tc.reveal_danger()

# ---------------- flipper hazards ----------------

func _flipper_for(cell: Vector2i):
        for f in flippers:
                if f.cell == cell:
                        return f
        return null

func _apply_flipper_visuals() -> void:
        for f in flippers:
                var frac = fmod(play_t + f.phase0, f.period) / f.period
                f.safe_now = frac < 0.5
                var tc = tiles.get(f.cell)
                if tc != null:
                        tc.set_flip(f.safe_now, false)

func _update_flippers() -> void:
        for f in flippers:
                var frac = fmod(play_t + f.phase0, f.period) / f.period
                var safe_now = frac < 0.5
                if safe_now != f.safe_now:
                        f.safe_now = safe_now
                        AudioManager.play_sfx("tile_show" if safe_now else "warn", 1.35 if safe_now else 0.9, -8.0)
                var warn = safe_now and frac > 0.38
                var tc = tiles.get(f.cell)
                if tc != null:
                        tc.set_flip(safe_now, warn)
                if f.on_path and not safe_now:
                        var pcell: Vector2i = Grid.cell_from_pos(player.global_position, _cols, _rows)
                        if pcell == f.cell and player.is_on_floor():
                                _fail("ZAPPED BY HAZARD", f.cell)
                                return

# ---------------- restart (retry flow) ----------------

func restart() -> void:
        stepped.clear()
        next_idx = 0
        play_t = 0.0
        player.locked = true
        player.velocity = Vector3.ZERO
        player.rotation.y = 0.0
        player.global_position = Grid.spawn_pos()
        for cellv in tiles:
                tiles[cellv].reset_visual()
        start()

func start() -> void:
        phase = Phase.READY
        _ready_t = 0.0
        _reveal_t = 0.0
        _seq_i = 0
        _limit_beep = false
        player.locked = true
        var id := int(level.get("id", 1))
        hud.set_level_info("LEVEL %d" % id, str(level.get("name", "")) + " — " + GameState.mode_label(mode))
        hud.set_time(false, "", false)
        hud.set_seq(false, 0, 0)
        hud.set_progress(0, path_cells.size())
        var col: Color = U.C.accent
        if mode == "timed":
                col = U.C.gold
        elif mode == "pattern":
                col = U.C.orange
        hud.show_banner("LEVEL %d" % id, col, 1.1)
        AudioManager.play_sfx("tile_show", 1.0, -4.0)
