# Virtual joystick — floating behavior: touch anywhere inside the joystick zone.
# Emits nothing; gameplay polls `output` (Vector2, x right / y down, length 0..1).
extends Control

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

func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed and _touch_index == -1 and get_global_rect().grow(30.0).has_point(t.position):
			_touch_index = t.index
			_center = t.position
			knob = Vector2.ZERO
			output = Vector2.ZERO
			queue_redraw()
		elif not t.pressed and t.index == _touch_index:
			_release()
	elif ev is InputEventScreenDrag and ev.index == _touch_index:
		var d := ev as InputEventScreenDrag
		var v: Vector2 = d.position - _center
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
