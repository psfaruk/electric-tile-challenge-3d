# Vector icons drawn with CanvasItem._draw (no texture/font dependency).
# kind: 0 = star, 1 = padlock
extends Control

var kind := 0
var fill := 1.0
var fill_color := Color(1.0, 0.773, 0.239)

func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
        var c := size / 2.0
        if kind == 0:
                var r := minf(size.x, size.y) * 0.5 * 0.92
                var pts := PackedVector2Array()
                for i in 10:
                        var ang := -PI / 2.0 + i * PI / 5.0
                        var rad := r if i % 2 == 0 else r * 0.46
                        pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
                var col := fill_color if fill > 0.5 else Color(0.18, 0.24, 0.30, 0.9)
                draw_colored_polygon(pts, col)
                var outline := PackedVector2Array(pts)
                outline.append(pts[0])
                draw_polyline(outline, Color(0, 0, 0, 0.4), 2.0)
        elif kind == 1:
                var w := minf(size.x, size.y)
                var body := Rect2(c.x - w * 0.28, c.y - w * 0.02, w * 0.56, w * 0.42)
                draw_arc(Vector2(c.x, c.y - w * 0.02), w * 0.20, PI, TAU, 16, Color(0.5, 0.58, 0.64), w * 0.09)
                draw_rect(body, Color(0.25, 0.32, 0.39), true)
                draw_rect(Rect2(body.position, body.size), Color(0.02, 0.04, 0.06), false, 2.0)
                draw_circle(Vector2(c.x, c.y + w * 0.18), w * 0.045, Color(0.02, 0.04, 0.06))
