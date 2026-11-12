# probe.gd — isolate where simulated touch input breaks: touch->mouse emulation,
# GUI hit-testing, or button press semantics.
extends SceneTree

var pressed_count := 0
var bg_hits := 0

func _initialize() -> void:
	# background catcher (behind the button)
	var bg := Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev):
		bg_hits += 1
		print("probe: bg gui_input ", ev)
	)
	root.add_child(bg)

	var b := Button.new()
	b.text = "TEST"
	b.position = Vector2(100, 100)
	b.size = Vector2(200, 80)
	b.pressed.connect(func(): pressed_count += 1)
	bg.add_child(b)

	print("probe: emulate_mouse_from_touch = ", Input.emulate_mouse_from_touch)
	print("probe: emulate_touch_from_mouse = ", Input.emulate_touch_from_mouse)
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	# 1) screen touch press/release over the button
	var t := InputEventScreenTouch.new()
	t.pressed = true
	t.position = Vector2(200, 140)
	t.index = 0
	Input.parse_input_event(t)
	await create_timer(0.15).timeout
	var r := InputEventScreenTouch.new()
	r.pressed = false
	r.position = Vector2(200, 140)
	r.index = 0
	Input.parse_input_event(r)
	await create_timer(0.3).timeout
	print("probe: after touch, pressed_count=", pressed_count, " bg_hits=", bg_hits)

	# 2) direct mouse click over the button
	var m := InputEventMouseButton.new()
	m.pressed = true
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = Vector2(200, 140)
	m.global_position = Vector2(200, 140)
	Input.parse_input_event(m)
	await create_timer(0.15).timeout
	var m2 := InputEventMouseButton.new()
	m2.pressed = false
	m2.button_index = MOUSE_BUTTON_LEFT
	m2.position = Vector2(200, 140)
	m2.global_position = Vector2(200, 140)
	Input.parse_input_event(m2)
	await create_timer(0.3).timeout
	print("probe: after mouse, pressed_count=", pressed_count, " bg_hits=", bg_hits)

	# 3) screen touch with same-frame press+release (no gap)
	var t2 := InputEventScreenTouch.new()
	t2.pressed = true
	t2.position = Vector2(200, 140)
	t2.index = 0
	Input.parse_input_event(t2)
	var r2 := InputEventScreenTouch.new()
	r2.pressed = false
	r2.position = Vector2(200, 140)
	r2.index = 0
	Input.parse_input_event(r2)
	await create_timer(0.3).timeout
	print("probe: after instant touch, pressed_count=", pressed_count, " bg_hits=", bg_hits)

	quit(0)
