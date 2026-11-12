# Settings — audio volumes, graphics quality, camera mode/sensitivity,
# haptics, progress reset (with confirmation).
extends CanvasLayer

const U := preload("res://scripts/ui/ui.gd")

var main
var _quality_btns: Array = []
var _cam_btns: Array = []
var _haptics_cb: CheckButton
var _confirm_root: Control

func _ready() -> void:
	layer = 10
	AudioManager.play_music("menu")
	_build()
	_wire_back()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(U.tint(U.C.bg))
	add_child(root)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := U.panel(Vector2(620, 620))
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(U.title("SETTINGS", 42, U.C.accent))

	# --- audio ---
	vb.add_child(_section_label("AUDIO"))
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 12)
	vb.add_child(music_row)
	var music_l := U.label("MUSIC", 20, U.C.dim)
	music_l.custom_minimum_size = Vector2(110, 20)
	music_row.add_child(music_l)
	var music_sl := _slider(0, 10, 1, float(GameState.settings.get("music", 0.7)) * 10.0)
	music_sl.value_changed.connect(func(v: float): GameState.set_setting("music", v / 10.0))
	music_row.add_child(music_sl)

	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 12)
	vb.add_child(sfx_row)
	var sfx_l := U.label("SFX", 20, U.C.dim)
	sfx_l.custom_minimum_size = Vector2(110, 20)
	sfx_row.add_child(sfx_l)
	var sfx_sl := _slider(0, 10, 1, float(GameState.settings.get("sfx", 0.8)) * 10.0)
	sfx_sl.value_changed.connect(_on_sfx_volume)
	sfx_row.add_child(sfx_sl)

	# --- graphics ---
	vb.add_child(_section_label("GRAPHICS QUALITY"))
	var q_row := HBoxContainer.new()
	q_row.add_theme_constant_override("separation", 10)
	vb.add_child(q_row)
	for i in 3:
		var b := U.button(["LOW", "MEDIUM", "HIGH"][i], _set_quality.bind(i), false, Vector2(150, 56), 22)
		q_row.add_child(b)
		_quality_btns.append(b)
	_refresh_quality()

	# --- controls ---
	vb.add_child(_section_label("CAMERA & CONTROLS"))
	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 10)
	vb.add_child(cam_row)
	for i in 2:
		var b := U.button(["SMART FOLLOW", "MANUAL"][i], _set_cam.bind(i), false, Vector2(205, 56), 20)
		cam_row.add_child(b)
		_cam_btns.append(b)
	_refresh_cam()

	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 12)
	vb.add_child(sens_row)
	var sens_l := U.label("SENSITIVITY", 20, U.C.dim)
	sens_l.custom_minimum_size = Vector2(110, 20)
	sens_row.add_child(sens_l)
	var sens_sl := _slider(4, 20, 1, float(GameState.settings.get("sens", 1.0)) * 10.0)
	sens_sl.value_changed.connect(func(v: float): GameState.set_setting("sens", v / 10.0))
	sens_row.add_child(sens_sl)

	var h_row := HBoxContainer.new()
	h_row.add_theme_constant_override("separation", 12)
	vb.add_child(h_row)
	var h_l := U.label("HAPTIC FEEDBACK", 20, U.C.dim)
	h_l.custom_minimum_size = Vector2(110, 20)
	h_row.add_child(h_l)
	_haptics_cb = CheckButton.new()
	_haptics_cb.button_pressed = bool(GameState.settings.get("haptics", true))
	_haptics_cb.add_theme_font_size_override("font_size", 18)
	_haptics_cb.toggled.connect(func(on: bool): GameState.set_setting("haptics", on))
	h_row.add_child(_haptics_cb)

	# --- data ---
	vb.add_child(_section_label("PROGRESS"))
	var reset_b := U.button("RESET ALL PROGRESS", _confirm_reset, false, Vector2(300, 54), 20)
	reset_b.add_theme_color_override("font_color", U.C.danger)
	vb.add_child(reset_b)

	var back_b := U.button("BACK", _back, true, Vector2(300, 62), 26)
	vb.add_child(back_b)

func _section_label(txt: String) -> Label:
	var l := U.label(txt, 18, U.C.accent)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l

func _slider(min_v: float, max_v: float, step_v: float, value: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = value
	sl.custom_minimum_size = Vector2(380, 36)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sl

func _on_sfx_volume(v: float) -> void:
	GameState.set_setting("sfx", v / 10.0)
	AudioManager.play_sfx("click", 0.8 + v * 0.1)

func _set_quality(i: int) -> void:
	AudioManager.click()
	GameState.set_setting("quality", i)
	_refresh_quality()

func _refresh_quality() -> void:
	var cur := int(GameState.settings.get("quality", 1))
	for i in _quality_btns.size():
		var on := i == cur
		_quality_btns[i].add_theme_stylebox_override("normal", U.flat(Color(0.07, 0.2, 0.18) if on else Color(0.07, 0.11, 0.15), 12, 2, U.C.accent if on else Color(0.12, 0.15, 0.18)))

func _set_cam(i: int) -> void:
	AudioManager.click()
	GameState.set_setting("cam_mode", i)
	_refresh_cam()

func _refresh_cam() -> void:
	var cur := int(GameState.settings.get("cam_mode", 0))
	for i in _cam_btns.size():
		var on := i == cur
		_cam_btns[i].add_theme_stylebox_override("normal", U.flat(Color(0.07, 0.2, 0.18) if on else Color(0.07, 0.11, 0.15), 12, 2, U.C.accent if on else Color(0.12, 0.15, 0.18)))

func _confirm_reset() -> void:
	AudioManager.play_sfx("warn")
	if _confirm_root != null:
		_confirm_root.queue_free()
	_confirm_root = Control.new()
	_confirm_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_root)
	_confirm_root.add_child(U.tint(Color(0.01, 0.02, 0.04, 0.8)))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_root.add_child(center)
	var panel := U.panel(Vector2(460, 230))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	vb.add_child(U.title("RESET PROGRESS?", 34, U.C.danger))
	vb.add_child(U.label("All stars and best times will be erased.", 19, U.C.dim))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	row.add_child(U.button("YES, ERASE", _do_reset, false, Vector2(190, 56), 22))
	row.add_child(U.button("CANCEL", func(): _confirm_root.queue_free(), true, Vector2(190, 56), 22))

func _do_reset() -> void:
	GameState.reset_progress()
	AudioManager.play_sfx("fail")
	_confirm_root.queue_free()
	main.goto("levels")

func _back() -> void:
	AudioManager.play_sfx("back")
	main.goto("menu")

func _wire_back() -> void:
	var win := get_window()
	if win.has_signal("go_back_requested"):
		win.go_back_requested.connect(_on_back)

func _on_back() -> void:
	_back()

func _exit_tree() -> void:
	var win := get_window()
	if win != null and win.has_signal("go_back_requested") and win.go_back_requested.is_connected(_on_back):
		win.go_back_requested.disconnect(_on_back)
