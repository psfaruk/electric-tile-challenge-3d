# HUD — gameplay CanvasLayer: level info, memorize bar, timer, sequence counter,
# banner announcements, screen flash, virtual joystick + jump button,
# pause overlay (with quick volume sliders) and results overlay.
extends CanvasLayer

const U := preload("res://scripts/ui/ui.gd")
const IconWidget := preload("res://scripts/ui/widgets/icon_widgets.gd")
const Joystick := preload("res://scripts/ui/widgets/joystick.gd")

var gp
var root: Control
var level_label: Label
var mode_label: Label
var banner_label: Label
var bar: ProgressBar
var timer_label: Label
var seq_label: Label
var pause_btn: Button
var joy: Control
var jump_btn: Button
var flash_rect: ColorRect

var _pause_root: Control
var _results_root: Control
var _results_title: Label
var _results_time: Label
var _results_best: Label
var _results_reason: Label
var _next_btn: Button
var _stars_row: Array = []
var _banner_tween: Tween

func setup(gp_ref) -> void:
        gp = gp_ref
        layer = 10
        root = Control.new()
        root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(root)

        # top-left: level info
        var info_panel := PanelContainer.new()
        _add_style(info_panel, "panel", U.pad(U.flat(Color(0.03, 0.05, 0.08, 0.72), 16, 2, Color(0.1, 0.2, 0.19)), 14))
        _place(info_panel, Control.PRESET_TOP_LEFT, 16, 14, 340, 96)
        root.add_child(info_panel)
        var vb := VBoxContainer.new()
        vb.add_theme_constant_override("separation", 2)
        info_panel.add_child(vb)
        level_label = U.label("LEVEL 1", 28, U.C.text)
        level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        mode_label = U.label("Memory Challenge", 16, U.C.dim)
        mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        vb.add_child(level_label)
        vb.add_child(mode_label)

        # top-center: progress/memorize bar + timer + sequence counter
        bar = ProgressBar.new()
        bar.show_percentage = false
        bar.max_value = 1.0
        bar.min_value = 0.0
        bar.value = 0.0
        _add_style(bar, "background", U.flat(Color(0.04, 0.06, 0.09, 0.8), 5))
        _add_style(bar, "fill", U.flat(U.C.accent, 5))
        _place(bar, Control.PRESET_CENTER_TOP, -160, 84, 160, 95)
        root.add_child(bar)

        timer_label = U.label("", 27, U.C.text)
        timer_label.label_settings = null
        timer_label.add_theme_font_size_override("font_size", 27)
        timer_label.add_theme_color_override("font_color", U.C.text)
        timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
        timer_label.add_theme_constant_override("outline_size", 8)
        _place(timer_label, Control.PRESET_CENTER_TOP, -110, 100, 110, 134)
        timer_label.visible = false
        root.add_child(timer_label)

        seq_label = U.label("", 22, U.C.orange)
        seq_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
        seq_label.add_theme_constant_override("outline_size", 7)
        _place(seq_label, Control.PRESET_CENTER_TOP, -110, 136, 110, 164)
        seq_label.visible = false
        root.add_child(seq_label)

        # banner (full-screen centered)
        banner_label = Label.new()
        banner_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        var bls := LabelSettings.new()
        bls.font_size = 58
        bls.font_color = U.C.accent
        bls.outline_size = 12
        bls.outline_color = Color(0.01, 0.02, 0.04)
        bls.shadow_size = 10
        bls.shadow_color = Color(0, 0, 0, 0.6)
        banner_label.label_settings = bls
        banner_label.modulate.a = 0.0
        root.add_child(banner_label)

        # top-right: pause button
        pause_btn = Button.new()
        pause_btn.text = "II"
        pause_btn.add_theme_font_size_override("font_size", 30)
        pause_btn.add_theme_color_override("font_color", U.C.text)
        _add_style(pause_btn, "normal", U.pad(U.flat(Color(0.03, 0.05, 0.08, 0.72), 18), 4))
        _add_style(pause_btn, "hover", U.pad(U.flat(Color(0.1, 0.16, 0.2, 0.85), 18), 4))
        _add_style(pause_btn, "pressed", U.pad(U.flat(Color(0.14, 0.25, 0.28, 0.9), 18), 4))
        _add_style(pause_btn, "focus", StyleBoxEmpty.new())
        pause_btn.pressed.connect(Callable(gp, "request_pause"))
        _place(pause_btn, Control.PRESET_TOP_RIGHT, -84, 14, -16, 84)
        root.add_child(pause_btn)

        # joystick + jump button
        joy = Joystick.new()
        _place(joy, Control.PRESET_BOTTOM_LEFT, 34, -300, 292, -36)
        root.add_child(joy)

        jump_btn = Button.new()
        jump_btn.text = "JUMP"
        jump_btn.add_theme_font_size_override("font_size", 28)
        jump_btn.add_theme_color_override("font_color", U.C.safe)
        jump_btn.add_theme_color_override("font_pressed_color", Color(0.85, 1.0, 0.9))
        jump_btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
        jump_btn.add_theme_constant_override("outline_size", 8)
        _add_style(jump_btn, "normal", U.flat(Color(0.05, 0.16, 0.1, 0.55), 60, 2, Color(0.16, 0.55, 0.35)))
        _add_style(jump_btn, "hover", U.flat(Color(0.07, 0.22, 0.14, 0.7), 60, 3, U.C.safe))
        _add_style(jump_btn, "pressed", U.flat(Color(0.1, 0.3, 0.2, 0.85), 60, 3, U.C.safe))
        _add_style(jump_btn, "focus", StyleBoxEmpty.new())
        jump_btn.pressed.connect(Callable(gp, "jump_pressed"))
        _place(jump_btn, Control.PRESET_BOTTOM_RIGHT, -158, -162, -32, -36)
        root.add_child(jump_btn)

        # screen flash overlay
        flash_rect = ColorRect.new()
        flash_rect.color = Color(1, 0.3, 0.3, 0)
        flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(flash_rect)

        _build_pause_overlay()
        _build_results_overlay()

# ---------------- small helpers ----------------

func _add_style(c: Control, key: String, sb: StyleBox) -> void:
        c.add_theme_stylebox_override(key, sb)

func _place(c: Control, preset: int, ol: float, ot: float, orr: float, ob: float) -> void:
        c.set_anchors_preset(preset)
        c.offset_left = ol
        c.offset_top = ot
        c.offset_right = orr
        c.offset_bottom = ob

# ---------------- state setters (called by challenge/gameplay) ----------------

func set_level_info(main_txt: String, sub_txt: String) -> void:
        level_label.text = main_txt
        mode_label.text = sub_txt

func show_banner(txt: String, color: Color, dur := 1.4) -> void:
        banner_label.text = txt
        banner_label.label_settings.font_color = color
        if _banner_tween != null and _banner_tween.is_valid():
                _banner_tween.kill()
        banner_label.pivot_offset = banner_label.size / 2.0
        banner_label.scale = Vector2(0.7, 0.7)
        banner_label.modulate.a = 0.0
        _banner_tween = create_tween()
        _banner_tween.tween_property(banner_label, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        _banner_tween.parallel().tween_property(banner_label, "modulate:a", 1.0, 0.14)
        _banner_tween.tween_interval(dur)
        _banner_tween.tween_property(banner_label, "modulate:a", 0.0, 0.45)

func set_reveal_frac(f: float) -> void:
        bar.value = clampf(f, 0.0, 1.0)

func set_progress(n: int, d: int) -> void:
        bar.value = clampf(float(n) / float(maxi(1, d)), 0.0, 1.0)

func set_time(show: bool, txt: String, danger: bool) -> void:
        timer_label.visible = show
        timer_label.text = txt
        timer_label.add_theme_color_override("font_color", U.C.danger if danger else U.C.text)

func set_seq(show: bool, n: int, d: int) -> void:
        seq_label.visible = show
        seq_label.text = "SEQ %d / %d" % [n, d]

func flash_screen(color: Color) -> void:
        flash_rect.color = Color(color.r, color.g, color.b, 0.5)
        var tw := create_tween()
        tw.tween_property(flash_rect, "color:a", 0.0, 0.55)

# ---------------- input plumbing ----------------

func move_output() -> Vector2:
        return joy.output

func joystick_active(idx: int) -> bool:
        return joy.is_active_index(idx)

func is_ui_at(pos: Vector2) -> bool:
        if _pause_root != null and _pause_root.visible:
                return true
        if _results_root != null and _results_root.visible:
                return true
        if pause_btn.get_global_rect().grow(22).has_point(pos):
                return true
        if jump_btn.get_global_rect().grow(14).has_point(pos):
                return true
        if joy.get_global_rect().grow(26).has_point(pos):
                return true
        return false

# ---------------- pause overlay ----------------

func _build_pause_overlay() -> void:
        _pause_root = Control.new()
        _pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
        _pause_root.visible = false
        root.add_child(_pause_root)

        var dim := U.tint(Color(0.01, 0.02, 0.04, 0.78))
        dim.mouse_filter = Control.MOUSE_FILTER_STOP
        _pause_root.add_child(dim)

        var center := CenterContainer.new()
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _pause_root.add_child(center)
        var panel := U.panel(Vector2(430, 420))
        center.add_child(panel)
        var vb := VBoxContainer.new()
        vb.add_theme_constant_override("separation", 12)
        vb.alignment = BoxContainer.ALIGNMENT_CENTER
        panel.add_child(vb)

        var title_l := U.title("PAUSED", 44, U.C.accent)
        vb.add_child(title_l)

        vb.add_child(U.label("MUSIC VOLUME", 17, U.C.dim))
        var music_sl := HSlider.new()
        music_sl.min_value = 0.0
        music_sl.max_value = 10.0
        music_sl.step = 1.0
        music_sl.value = float(GameState.settings.get("music", 0.7)) * 10.0
        music_sl.custom_minimum_size = Vector2(330, 36)
        music_sl.value_changed.connect(_on_volume.bind("music"))
        vb.add_child(music_sl)

        vb.add_child(U.label("SFX VOLUME", 17, U.C.dim))
        var sfx_sl := HSlider.new()
        sfx_sl.min_value = 0.0
        sfx_sl.max_value = 10.0
        sfx_sl.step = 1.0
        sfx_sl.value = float(GameState.settings.get("sfx", 0.8)) * 10.0
        sfx_sl.custom_minimum_size = Vector2(330, 36)
        sfx_sl.value_changed.connect(_on_volume.bind("sfx"))
        vb.add_child(sfx_sl)

        var resume_b := U.button("RESUME", Callable(gp, "resume_pressed"), true, Vector2(330, 58), 24)
        vb.add_child(resume_b)
        var retry_b := U.button("RESTART LEVEL", Callable(gp, "retry"), false, Vector2(330, 58), 24)
        vb.add_child(retry_b)
        var quit_b := U.button("QUIT TO MENU", Callable(gp, "quit_to_menu"), false, Vector2(330, 58), 24)
        vb.add_child(quit_b)

func _on_volume(v: float, key: String) -> void:
        GameState.set_setting(key, v / 10.0)
        if key == "sfx":
                AudioManager.play_sfx("click", 0.9 + v * 0.08)

func show_pause() -> void:
        _pause_root.visible = true

func hide_pause() -> void:
        _pause_root.visible = false

# ---------------- results overlay ----------------

func _build_results_overlay() -> void:
        _results_root = Control.new()
        _results_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _results_root.process_mode = Node.PROCESS_MODE_ALWAYS
        _results_root.visible = false
        root.add_child(_results_root)

        var dim := U.tint(Color(0.01, 0.02, 0.04, 0.7))
        dim.mouse_filter = Control.MOUSE_FILTER_STOP
        _results_root.add_child(dim)

        var center := CenterContainer.new()
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _results_root.add_child(center)
        var panel := U.panel(Vector2(470, 470))
        center.add_child(panel)
        var vb := VBoxContainer.new()
        vb.add_theme_constant_override("separation", 10)
        vb.alignment = BoxContainer.ALIGNMENT_CENTER
        panel.add_child(vb)

        _results_title = U.title("VICTORY!", 50, U.C.gold)
        vb.add_child(_results_title)

        var stars_row := HBoxContainer.new()
        stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
        stars_row.add_theme_constant_override("separation", 14)
        vb.add_child(stars_row)
        for i in 3:
                var star := IconWidget.new()
                star.kind = 0
                star.fill = 0.0
                star.fill_color = U.C.gold
                star.custom_minimum_size = Vector2(46, 46)
                stars_row.add_child(star)
                _stars_row.append(star)

        _results_time = U.label("", 26, U.C.text)
        vb.add_child(_results_time)
        _results_best = U.label("", 20, U.C.dim)
        vb.add_child(_results_best)
        _results_reason = U.label("", 22, U.C.danger)
        _results_reason.visible = false
        vb.add_child(_results_reason)

        var grid := GridContainer.new()
        grid.columns = 2
        grid.add_theme_constant_override("h_separation", 10)
        grid.add_theme_constant_override("v_separation", 10)
        vb.add_child(grid)
        _next_btn = U.button("NEXT LEVEL", Callable(gp, "next_level"), true, Vector2(210, 58), 22)
        grid.add_child(_next_btn)
        var retry_b := U.button("RETRY", Callable(gp, "retry"), false, Vector2(210, 58), 22)
        grid.add_child(retry_b)
        var levels_b := U.button("LEVELS", Callable(gp, "goto_levels"), false, Vector2(210, 58), 22)
        grid.add_child(levels_b)
        var menu_b := U.button("MENU", Callable(gp, "quit_to_menu"), false, Vector2(210, 58), 22)
        grid.add_child(menu_b)

func results_visible() -> bool:
        return _results_root != null and _results_root.visible

func hide_results() -> void:
        _results_root.visible = false

func show_results(win: bool, time_sec: float, stars: int, best: float, level_id: int, reason: String) -> void:
        hide_pause()
        _results_root.visible = true
        _results_title.text = "VICTORY!" if win else "FAILED"
        _results_title.label_settings.font_color = U.C.gold if win else U.C.danger
        for i in 3:
                _stars_row[i].fill = 1.0 if i < stars else 0.0
                _stars_row[i].queue_redraw()
        _results_time.text = "TIME  %.1f s" % time_sec
        if best > 0.0:
                _results_best.text = "BEST  %.1f s" % best
        else:
                _results_best.text = "NO RECORD YET"
        _results_reason.visible = not win
        _results_reason.text = reason
        _next_btn.visible = win and level_id < GameState.LEVEL_COUNT
        _next_btn.disabled = not (win and GameState.is_unlocked(level_id + 1)) if _next_btn.visible else false
        AudioManager.play_sfx("star" if win else "back", 1.1 if win else 0.9)
