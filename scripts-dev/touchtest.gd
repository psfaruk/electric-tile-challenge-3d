# touchtest.gd — End-to-end TOUCH INPUT test (runs in CI + locally).
# Simulates realistic Android touch events (InputEventScreenTouch / ScreenDrag,
# which the engine also converts to emulated mouse for the GUI exactly like a
# real device) and verifies that EVERY on-screen control actually responds:
#   menu buttons, HOW TO PLAY overlay, SETTINGS screen, level-select buttons
#   (incl. locked-state), gameplay JUMP button, virtual joystick, camera drag,
#   PAUSE overlay, fail -> results overlay -> RETRY, QUIT TO MENU.
# Any failure prints "TOUCHTEST FAIL: ..." and exits with code 1.
extends Node

const Grid := preload("res://scripts/game/grid.gd")

var main
var fails := 0
var checks := 0

func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS

# ---------------- harness helpers ----------------

func _check(cond: bool, msg: String) -> bool:
        checks += 1
        if cond:
                print("TOUCHTEST OK: " + msg)
        else:
                fails += 1
                print("TOUCHTEST FAIL: " + msg)
                push_error("TOUCHTEST FAIL: " + msg)
        return cond

func _frames(n: int) -> void:
        for i in n:
                await get_tree().process_frame

func _secs(t: float) -> void:
        await get_tree().create_timer(t).timeout

# Wait until any screen-transition veil has finished — mirrors a real user
# who waits for the new screen to settle before tapping.
func _settle() -> void:
        var guard := 0
        while ("_fading" in main and main._fading) and guard < 600:
                await _frames(1)
                guard += 1
        await _frames(2)

# A realistic tap: wait for any transition to settle, touch down, two frames, touch up.
func _tap(pos: Vector2, idx := 0) -> void:
        await _settle()
        var t := InputEventScreenTouch.new()
        t.index = idx
        t.position = pos
        t.pressed = true
        Input.parse_input_event(t)
        await _frames(2)
        var r := InputEventScreenTouch.new()
        r.index = idx
        r.position = pos
        r.pressed = false
        Input.parse_input_event(r)
        await _frames(2)

func _tap_button(b: Control) -> void:
        if b == null:
                return
        await _tap(b.get_global_rect().get_center())

func _find_buttons(node: Node, txt: String, out: Array = [], include_disabled := false) -> Array:
        if node is BaseButton:
                var bb := node as BaseButton
                if bb.text == txt and bb.is_visible_in_tree() and (include_disabled or not bb.disabled):
                        out.append(bb)
        for c in node.get_children():
                _find_buttons(c, txt, out, include_disabled)
        return out

func _btn(txt: String, include_disabled := false) -> BaseButton:
        var arr := _find_buttons(get_tree().root, txt, [], include_disabled)
        return arr[0] if arr.size() > 0 else null

func _find_by_script(node: Node, frag: String, out: Array = []) -> Array:
        if node.get_script() != null and str(node.get_script().resource_path).contains(frag):
                out.append(node)
        for c in node.get_children():
                _find_by_script(c, frag, out)
        return out

func _screen_path() -> String:
        var s = main._screen
        if s == null or s.get_script() == null:
                return ""
        return str(s.get_script().resource_path)

func _screen_is(frag: String) -> bool:
        return _screen_path().contains(frag)

# ---------------- the test ----------------

func run() -> void:
        print("TOUCHTEST: begin (window size = %s)" % get_tree().root.get_visible_rect().size)
        GameState.reset_progress()
        await _frames(30)  # let the menu build

        # -- 1. HOW TO PLAY overlay (menu buttons) --
        var how_b := _btn("HOW TO PLAY")
        if _check(how_b != null, "menu: HOW TO PLAY button found"):
                await _settle()
                await _tap_button(how_b)
                await _frames(6)
                var got := _btn("GOT IT")
                if _check(got != null, "menu: HOW TO PLAY overlay opens on tap"):
                        await _tap_button(got)
                        await _frames(8)
                        _check(_btn("GOT IT") == null, "menu: GOT IT closes the overlay")

        # -- 2. SETTINGS screen --
        var set_b := _btn("SETTINGS")
        if _check(set_b != null, "menu: SETTINGS button found"):
                await _settle()
                await _tap_button(set_b)
                await _frames(8)
                _check(_screen_is("settings"), "menu: SETTINGS tap opens settings screen")
                var back_b := _btn("BACK")
                if _check(back_b != null, "settings: BACK button found"):
                        await _tap_button(back_b)
                        await _frames(8)
                        _check(_screen_is("main_menu"), "settings: BACK returns to menu")

        # -- 3. PLAY -> level select --
        var play_b := _btn("PLAY")
        if _check(play_b != null, "menu: PLAY button found"):
                await _tap_button(play_b)
                await _frames(8)
                _check(_screen_is("level_select"), "menu: PLAY opens level select")

        # -- 3b. locked levels state --
        var locked2 := _btn("2", true)
        if locked2 != null:
                _check(locked2.disabled, "levels: level 2 is locked (disabled) with no progress")
        var locked11 := _btn("11", true)
        if locked11 != null:
                _check(locked11.disabled, "levels: level 11 is locked (disabled)")

        # -- 4. tap level 1 -> gameplay --
        var lvl1 := _btn("1")
        if _check(lvl1 != null, "levels: level 1 button found/enabled"):
                await _tap_button(lvl1)
                await _frames(12)
                _check(_screen_is("gameplay"), "levels: tapping level 1 starts gameplay")

        # -- 5. gameplay: wait for PLAY phase (fast-forward reveal) --
        var gp = main._screen if _screen_is("gameplay") else null
        if gp != null and gp.challenge != null:
                gp.challenge.mem_speed = 0.12
        var waited := 0
        while gp != null and main._screen == gp and gp.challenge != null and gp.challenge.phase != 2 and waited < 2500:
                await _frames(1)
                waited += 1
        _check(gp != null and gp.challenge != null and gp.challenge.phase == 2, "gameplay: reached PLAY phase after memorize")

        if gp != null and gp.challenge != null and gp.challenge.phase == 2:
                # -- 6. JUMP button (poll for airborne — robust at any render FPS) --
                var jump_b := _btn("JUMP")
                if _check(jump_b != null, "hud: JUMP button found"):
                        var y0: float = gp.player.global_position.y
                        await _tap_button(jump_b)
                        var air := false
                        var jf := 0
                        while not air and jf < 120 and main._screen == gp and gp.player != null:
                                if not gp.player.is_on_floor() or gp.player.global_position.y > y0 + 0.05:
                                        air = true
                                        break
                                await _frames(1)
                                jf += 1
                        _check(air, "hud: JUMP launches the player into the air")
                        var lf := 0
                        while gp.player != null and not gp.player.is_on_floor() and lf < 240 and main._screen == gp:
                                await _frames(1)
                                lf += 1

                # -- 7. camera drag (empty screen area) --
                var yaw0: float = gp.cam_rig.yaw
                var vp_sz: Vector2 = get_tree().root.get_visible_rect().size
                var cpos := Vector2(vp_sz.x * 0.5, vp_sz.y * 0.45)
                var ct := InputEventScreenTouch.new()
                ct.index = 0
                ct.pressed = true
                ct.position = cpos
                Input.parse_input_event(ct)
                await _frames(2)
                for i in 10:
                        var d := InputEventScreenDrag.new()
                        d.index = 0
                        d.position = cpos + Vector2(i * 12.0, 0)
                        d.relative = Vector2(12, 0)
                        Input.parse_input_event(d)
                        await _frames(1)
                var cr := InputEventScreenTouch.new()
                cr.index = 0
                cr.pressed = false
                cr.position = cpos + Vector2(120, 0)
                Input.parse_input_event(cr)
                await _frames(2)
                _check(absf(gp.cam_rig.yaw - yaw0) > 0.02, "gameplay: drag on empty area rotates camera (yaw %.3f -> %.3f)" % [yaw0, gp.cam_rig.yaw])

                # -- 8. PAUSE overlay --
                var pause_b := _btn("II")
                if _check(pause_b != null, "hud: pause button found"):
                        await _tap_button(pause_b)
                        await _frames(4)
                        _check(get_tree().paused, "hud: pause button pauses the tree")
                        var res_b := _btn("RESUME")
                        if _check(res_b != null, "pause: RESUME button visible"):
                                await _tap_button(res_b)
                                await _frames(4)
                                _check(not get_tree().paused, "pause: RESUME unpauses the game")

                # -- 9. virtual joystick --
                var joys := _find_by_script(get_tree().root, "joystick.gd")
                if _check(joys.size() > 0, "hud: joystick control exists"):
                        var joy: Control = joys[0]
                        var jc: Vector2 = joy.get_global_rect().get_center()
                        var p0: Vector3 = gp.player.global_position
                        var jt := InputEventScreenTouch.new()
                        jt.index = 0
                        jt.pressed = true
                        jt.position = jc
                        Input.parse_input_event(jt)
                        await _frames(2)
                        for i in 12:
                                var d := InputEventScreenDrag.new()
                                d.index = 0
                                d.position = jc + Vector2(0, -i * 7.0)
                                d.relative = Vector2(0, -7)
                                Input.parse_input_event(d)
                                await _frames(1)
                        _check(joy.output.length() > 0.3, "joystick: output active while dragged (%.2f,%.2f)" % [joy.output.x, joy.output.y])
                        await _frames(50)  # ~0.8s of walking
                        var jr := InputEventScreenTouch.new()
                        jr.index = 0
                        jr.pressed = false
                        jr.position = jc + Vector2(0, -84)
                        Input.parse_input_event(jr)
                        await _frames(4)
                        var dist: float = gp.player.global_position.distance_to(p0)
                        _check(dist > 0.25, "joystick: player moves while joystick held (dist %.2f m)" % dist)
                        _check(joy.output == Vector2.ZERO, "joystick: output resets on release")

                # -- 10. force a zap -> results overlay -> RETRY --
                var danger := Vector2i(-9, -9)
                for r in gp._rows:
                        for c in gp._cols:
                                var cell := Vector2i(r, c)
                                if not gp.challenge.path_set.has(cell) and gp.challenge._flipper_for(cell) == null:
                                        danger = cell
                                        break
                        if danger.x >= 0:
                                break
                if _check(danger.x >= 0, "gameplay: found a danger tile to trigger zap"):
                        gp.player.global_position = Grid.tile_center(danger, gp._cols) + Vector3(0, 0.02, 0)
                        var zf := 0
                        while main._screen == gp and gp.challenge != null and gp.challenge.phase == 2 and zf < 240:
                                await _frames(1)
                                zf += 1
                        _check(gp.challenge.phase == 3, "gameplay: stepping on danger tile fails the level")
                        await _secs(2.3)
                        var retry_b := _btn("RETRY")
                        if _check(retry_b != null, "results: RETRY button visible after fail"):
                                await _tap_button(retry_b)
                                await _frames(14)
                                _check(main._screen != gp and _screen_is("gameplay"), "results: RETRY reloads the level")

        # -- 11. new gameplay screen: pause -> QUIT TO MENU --
        var gp2 = main._screen
        if _screen_is("gameplay") and gp2 != gp:
                if gp2.challenge != null:
                        gp2.challenge.mem_speed = 0.12
                var w2 := 0
                while gp2.challenge != null and gp2.challenge.phase != 2 and w2 < 2500 and main._screen == gp2:
                        await _frames(1)
                        w2 += 1
                var pb := _btn("II")
                if _check(pb != null, "hud(2): pause button found"):
                        await _tap_button(pb)
                        await _frames(4)
                        var qb := _btn("QUIT TO MENU")
                        if _check(qb != null, "pause(2): QUIT TO MENU visible"):
                                await _tap_button(qb)
                                await _frames(10)
                                _check(_screen_is("main_menu"), "pause: QUIT TO MENU returns to main menu")

        # -- 12. LEVEL SELECT button from the returned menu --
        if _screen_is("main_menu"):
                var sel_b := _btn("LEVEL SELECT")
                if _check(sel_b != null, "menu(2): LEVEL SELECT button found"):
                        await _tap_button(sel_b)
                        await _frames(8)
                        _check(_screen_is("level_select"), "menu(2): LEVEL SELECT opens level select")

        print("TOUCHTEST: %d checks, %d failures" % [checks, fails])
        if fails > 0:
                print("TOUCHTEST: FAILED")
                get_tree().quit(1)
        else:
                print("TOUCHTEST: ALL CHECKS PASSED")
                get_tree().quit(0)
