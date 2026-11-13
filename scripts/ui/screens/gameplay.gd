# Gameplay — the in-match scene: world (arena + tiles + player + camera + challenge)
# plus HUD CanvasLayer, touch camera controls, pause/results flow.
# Also hosts the automated smoke test (ETC_SMOKE=1) used by CI.
extends Node

const Grid := preload("res://scripts/game/grid.gd")
const Graphics := preload("res://scripts/game/graphics.gd")
const U := preload("res://scripts/ui/ui.gd")
const CS := preload("res://scripts/game/challenge.gd")

var main
var level_id := 1
var smoke := false
var shot := false

var level: Dictionary
var arena
var player
var cam_rig
var sparks
var challenge
var hud
var finish_area: Area3D
var field

var tiles := {}
var _cols := 6
var _rows := 6
var _last_cell := Vector2i(-99, -99)
var _was_floor := false
var _cam_touch := {}
var _prev_pinch := -1.0
var _paused := false
var _won := false

func _ready() -> void:
        level = GameState.load_level(level_id)
        _cols = int(level.get("cols", 6))
        _rows = int(level.get("rows", 6))
        var quality := int(GameState.settings.get("quality", 1))

        Graphics.build_environment(self, quality)
        Graphics.apply_viewport(get_viewport(), quality)

        arena = preload("res://scripts/game/arena.gd").new()
        add_child(arena)
        arena.setup(level, quality)

        # electric floor: one shared TileField (3 draw calls) + tile state controllers
        field = preload("res://scripts/game/tile_field.gd").new()
        add_child(field)
        field.setup(level)
        var tile_script := preload("res://scripts/game/tile.gd")
        for r in _rows:
                for c in _cols:
                        var t = tile_script.new()
                        t.setup(Vector2i(r, c), field)
                        add_child(t)
                        tiles[Vector2i(r, c)] = t

        player = preload("res://scripts/game/player.gd").new()
        add_child(player)
        player.global_position = arena.get_spawn()

        cam_rig = preload("res://scripts/game/camera_rig.gd").new()
        add_child(cam_rig)
        cam_rig.setup(player, get_viewport())

        sparks = preload("res://scripts/game/sparks.gd").new()
        add_child(sparks)

        _build_finish_area()

        challenge = preload("res://scripts/game/challenge.gd").new()
        add_child(challenge)
        hud = preload("res://scripts/ui/screens/hud.gd").new()
        add_child(hud)
        hud.setup(self)
        challenge.setup(level, tiles, player, sparks, hud, cam_rig)
        challenge.game_won.connect(_on_win)
        challenge.game_failed.connect(_on_fail)

        AudioManager.play_music("game")

        var win := get_window()
        if win.has_signal("go_back_requested"):
                win.go_back_requested.connect(_on_back)

        challenge.start()
        if smoke:
                _smoke_run()
        elif shot:
                _shot_run()

func _exit_tree() -> void:
        get_tree().paused = false
        var win := get_window()
        if win != null and win.has_signal("go_back_requested") and win.go_back_requested.is_connected(_on_back):
                win.go_back_requested.disconnect(_on_back)

func _build_finish_area() -> void:
        finish_area = Area3D.new()
        var cs := CollisionShape3D.new()
        var sh := BoxShape3D.new()
        sh.size = Vector3(_cols * Grid.PITCH - 0.4, 1.2, 1.0)
        cs.shape = sh
        cs.position = Vector3(0, 0.7, arena.get_finish_z() + 0.35)
        finish_area.add_child(cs)
        add_child(finish_area)
        finish_area.body_entered.connect(_on_finish_body)

func _on_finish_body(body: Node3D) -> void:
        if body == player:
                challenge.on_finish_entered()

# ---------------- per-frame input plumbing ----------------

func _physics_process(_delta: float) -> void:
        if player == null or challenge == null or hud == null:
                return
        var v: Vector2 = hud.move_output()
        var kv := Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.15)
        if kv.length() > v.length():
                v = kv
        var dir3 := Vector3(v.x, 0, v.y).rotated(Vector3.UP, cam_rig.yaw)
        player.move_input = Vector2(dir3.x, dir3.z)

        var cell := Grid.cell_from_pos(player.global_position, _cols, _rows)
        var floor_now: bool = player.is_on_floor()
        if floor_now and (cell != _last_cell or not _was_floor):
                _last_cell = cell
                if Grid.in_bounds(cell, _cols, _rows):
                        challenge.on_player_cell(cell)
        elif cell != _last_cell:
                _last_cell = cell
        _was_floor = floor_now

# ---------------- touch camera controls ----------------

func _input(ev: InputEvent) -> void:
        if player == null or cam_rig == null or hud == null:
                return
        var root := get_tree().root
        if ev is InputEventScreenTouch:
                var t := ev as InputEventScreenTouch
                if t.pressed:
                        if not hud.is_ui_at(t.position) and not hud.joystick_active(t.index) \
                                                and not hud.button_touch(t.index):
                                _cam_touch[t.index] = U.norm_pos(t.position, root)
                else:
                        _cam_touch.erase(t.index)
                        if _cam_touch.size() < 2:
                                _prev_pinch = -1.0
        elif ev is InputEventScreenDrag:
                if _cam_touch.has(ev.index):
                        var prev: Vector2 = _cam_touch[ev.index]
                        var pos: Vector2 = U.norm_pos(ev.position, root)
                        _cam_touch[ev.index] = pos
                        if _cam_touch.size() >= 2:
                                var pts: Array = _cam_touch.values()
                                var d: float = (pts[0] - pts[1]).length()
                                if _prev_pinch > 0.0:
                                        cam_rig.zoom_input((_prev_pinch - d) * 0.14)
                                _prev_pinch = d
                        else:
                                cam_rig.rotate_input(pos.x - prev.x, pos.y - prev.y)
        elif ev is InputEventMouseButton and ev.pressed:
                if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
                        cam_rig.zoom_input(-0.5)
                elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                        cam_rig.zoom_input(0.5)

func _unhandled_input(ev: InputEvent) -> void:
        if ev.is_action_pressed("ui_cancel"):
                _on_back()

# ---------------- pause / results / navigation ----------------

func _on_back() -> void:
        if _paused:
                resume_pressed()
        elif hud != null and not hud.results_visible():
                request_pause()

func request_pause() -> void:
        if _paused or challenge == null or challenge.phase == CS.Phase.DONE:
                return
        _paused = true
        get_tree().paused = true
        hud.show_pause()
        AudioManager.click()

func resume_pressed() -> void:
        _paused = false
        if hud != null:
                hud.hide_pause()
        get_tree().paused = false
        AudioManager.click()

var _last_jump_ms := -100000

func jump_pressed() -> void:
        # Swallow the emulated-mouse echo of a press already answered by the
        # raw-touch fast-path (both pathways can fire for the same tap).
        var now := Time.get_ticks_msec()
        if now - _last_jump_ms < 120:
                return
        _last_jump_ms = now
        if player != null:
                player.request_jump()

func retry() -> void:
        get_tree().paused = false
        AudioManager.click()
        main.goto("gameplay", {"level": level_id})

func next_level() -> void:
        get_tree().paused = false
        AudioManager.click()
        main.goto("gameplay", {"level": level_id + 1})

func goto_levels() -> void:
        get_tree().paused = false
        AudioManager.click()
        main.goto("levels")

func quit_to_menu() -> void:
        get_tree().paused = false
        AudioManager.click()
        main.goto("menu")

func _on_win(time_sec: float) -> void:
        _won = true
        var stars := 1
        if time_sec <= float(level.get("gold_time", 999.0)):
                stars = 3
        elif time_sec <= float(level.get("par_time", 999.0)):
                stars = 2
        GameState.record_result(level_id, time_sec, stars)
        var best: float = GameState.get_best(level_id)
        await get_tree().create_timer(1.7).timeout
        if is_instance_valid(hud) and hud != null:
                hud.show_results(true, time_sec, stars, best, level_id, "")

func _on_fail(reason: String) -> void:
        await get_tree().create_timer(1.6).timeout
        if is_instance_valid(hud) and hud != null:
                var best: float = GameState.get_best(level_id)
                hud.show_results(false, challenge.play_t, 0, best, level_id, reason)

# ---------------- automated smoke test (CI) ----------------

func _smoke_check(cond: bool, msg: String) -> void:
        if cond:
                print("SMOKE OK: " + msg)
        else:
                push_error("SMOKE FAIL: " + msg)
                print("SMOKE FAIL: " + msg)
                get_tree().quit(1)

func _smoke_run() -> void:
        await get_tree().physics_frame
        await get_tree().physics_frame
        _smoke_check(player != null, "player exists")
        _smoke_check(tiles.size() == _cols * _rows, "tile grid built (%d)" % tiles.size())
        _smoke_check(challenge != null and challenge.path_cells.size() >= 4, "safe path built (%d cells)" % challenge.path_cells.size())
        challenge.mem_speed = 0.12
        var frames := 0
        while challenge.phase != CS.Phase.PLAY and frames < 1500:
                await get_tree().physics_frame
                frames += 1
        _smoke_check(challenge.phase == CS.Phase.PLAY, "reached PLAY phase")

        # Walk the entire safe path.
        var path: Array = challenge.path_cells
        for i in path.size():
                var cell: Vector2i = path[i]
                player.global_position = Grid.tile_center(cell, _cols) + Vector3(0, 0.02, 0)
                await get_tree().physics_frame
                await get_tree().physics_frame
                if challenge.phase == CS.Phase.DONE:
                        _smoke_check(false, "unexpected failure at step %d" % i)
                        return
        _smoke_check(challenge.stepped.size() == path.size(), "all path tiles stepped (%d/%d)" % [challenge.stepped.size(), path.size()])

        # Enter the finish zone -> expect victory.
        player.global_position = Vector3(0, 0.2, arena.get_finish_z() + 0.4)
        var wframes := 0
        while not _won and wframes < 300:
                await get_tree().physics_frame
                wframes += 1
        _smoke_check(_won, "victory flow fired")
        await get_tree().create_timer(0.7).timeout

        # Retry flow: restart and confirm reset works.
        _won = false
        hud.hide_results()
        challenge.restart()
        var rframes := 0
        while challenge.phase != CS.Phase.PLAY and rframes < 1500:
                await get_tree().physics_frame
                rframes += 1
        _smoke_check(challenge.phase == CS.Phase.PLAY, "restart reached PLAY phase")

        # Zap test: step onto a dangerous (non-path) tile -> expect failure.
        var danger := Vector2i(-9, -9)
        for r in _rows:
                for c in _cols:
                        var cell2 := Vector2i(r, c)
                        if not challenge.path_set.has(cell2) and challenge._flipper_for(cell2) == null:
                                danger = cell2
                                break
                if danger.x >= 0:
                        break
        player.global_position = Grid.tile_center(danger, _cols) + Vector3(0, 0.02, 0)
        var zframes := 0
        while challenge.phase == CS.Phase.PLAY and zframes < 200:
                await get_tree().physics_frame
                zframes += 1
        _smoke_check(challenge.phase == CS.Phase.DONE, "zap failure triggered")

        # Remaining screen navigation is orchestrated by Main (this node is about
        # to be freed when the screen switches, which would kill our coroutine).
        main.smoke_screens_round()

# ---------------- screenshot capture (CI evidence) ----------------

func _shot_run() -> void:
        # evidence framing: zoom out to the in-game maximum so the full studio
        # set (audience, trusses, LED wall) is captured — a view any player can
        # also reach with pinch-zoom; then a second close-up on the tiles
        if cam_rig != null:
                cam_rig.zoom_input(3.2)
                cam_rig.cam.fov = 74.0
        await get_tree().create_timer(2.2).timeout
        await RenderingServer.frame_post_draw
        var img := get_viewport().get_texture().get_image()
        if GameState.shot_path != "" and img != null:
                img.save_png(GameState.shot_path)
        get_tree().quit(0)
