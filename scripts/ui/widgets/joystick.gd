# Virtual joystick — floating behavior: touch anywhere inside the joystick zone.
# Emits nothing; gameplay polls `output` (Vector2, x right / y down, length 0..1).
# HARDENED (v1.0.2): accepts raw touch events AND plain mouse events (different
# devices/driver paths deliver one or the other), and normalizes both canvas and
# window coordinate spaces, so the joystick can never go dead on real hardware.
extends Control

const U := preload("res://scripts/ui/ui.gd")

const MOUSE_TRACK := -100  # sentinel tracking id when driven by mouse events

var radius := 128.0
var output := Vector2.ZERO
var knob := Vector2.ZERO

var _touch_index := -1
var _center := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func is_active_index(idx: int) -> bool:
	return _touch_index == idx

func _grab(track_id: int, pos: Vector2) -> void:
	_touch_index = track_id
	_center = pos
	knob = Vector2.ZERO
	output = Vector2.ZERO
	queue_redraw()

func _input(ev: InputEvent) -> void:
	var root := get_tree().root
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed and _touch_index == -1 and U.hit(get_global_rect(), t.position, 30.0, root):
			_grab(t.index, U.norm_pos(t.position, root))
		elif not t.pressed and t.index == _touch_index:
			_release()
	elif ev is InputEventScreenDrag and ev.index == _touch_index:
		_drag(U.norm_pos(ev.position, root))
	# Mouse fallback: some environments deliver plain mouse events instead of
	# (or without synthesizing) touch. Grab only while no touch is tracking;
	# whichever pathway arrives first wins, the other is ignored.
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var b := ev as InputEventMouseButton
		if b.pressed and _touch_index == -1 and U.hit(get_global_rect(), b.position, 30.0, root):
			_grab(MOUSE_TRACK, U.norm_pos(b.position, root))
		elif not b.pressed and _touch_index == MOUSE_TRACK:
			_release()
	elif ev is InputEventMouseMotion and _touch_index == MOUSE_TRACK:
		_drag(U.norm_pos(ev.position, root))

func _drag(pos: Vector2) -> void:
	var v: Vector2 = pos - _center
	var max_l := radius * 0.62
	if v.length() > max_l:
		v = v.normalized() * max_l
	knob = v
	output = v / max_l
	queue_redraw()

func _release() -> void:
	_touch_index = -1
	knob = Vector2.ZERO
	output = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var center := c
	if _touch_index != -1:
		center = _center - get_global_rect().position
	var r := radius * 0.62
	draw_circle(center, r, Color(1, 1, 1, 0.05))
	draw_arc(center, r, 0, TAU, 48, Color(0.18, 0.9, 0.784, 0.4), 3.0)
	draw_circle(center + knob, radius * 0.26, Color(0.18, 0.9, 0.784, 0.85))
	draw_circle(center + knob, radius * 0.13, Color(0.92, 1, 0.98, 0.95))
