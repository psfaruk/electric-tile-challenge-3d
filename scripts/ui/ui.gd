# UI — static factory helpers + shared palette for every screen.
# Built entirely in code so the project ships with a single .tscn file.
# Usage:  const U := preload("res://scripts/ui/ui.gd")
#         U.button("PLAY", cb)
extends Object

const C := {
	"bg": Color(0.039, 0.063, 0.086),        # 0A1016 deep charcoal-teal
	"panel": Color(0.071, 0.106, 0.145),     # 121B25
	"panel2": Color(0.11, 0.16, 0.22),       # 1C2938
	"text": Color(0.914, 0.957, 0.949),
	"dim": Color(0.576, 0.651, 0.706),
	"accent": Color(0.18, 0.902, 0.784),    # 2EE6C8 electric teal
	"accent_dark": Color(0.075, 0.31, 0.28),
	"safe": Color(0.271, 0.973, 0.51),       # 45F882
	"danger": Color(1.0, 0.302, 0.302),     # FF4D4D
	"gold": Color(1.0, 0.773, 0.239),        # FFC53D
	"orange": Color(1.0, 0.478, 0.161),     # FF7A29
}

static func flat(bg: Color, radius := 14, border_w := 0, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	if border_w > 0:
		sb.border_width_left = border_w
		sb.border_width_right = border_w
		sb.border_width_top = border_w
		sb.border_width_bottom = border_w
		sb.border_color = border
	return sb

static func pad(sb: StyleBoxFlat, m: float) -> StyleBoxFlat:
	sb.content_margin_left = m
	sb.content_margin_right = m
	sb.content_margin_top = m
	sb.content_margin_bottom = m
	return sb

static func label(txt: String, size := 24, color: Color = C.text) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func title(txt: String, size := 56, color: Color = C.text, outline := true) -> Label:
	var l := label(txt, size, color)
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	if outline:
		ls.outline_size = int(size / 6.0)
		ls.outline_color = Color(0.01, 0.02, 0.04)
	ls.shadow_size = int(size / 8.0)
	ls.shadow_color = Color(0, 0, 0, 0.55)
	l.label_settings = ls
	return l

static func button(txt: String, cb: Callable, accent := false, min_size := Vector2(240, 64), font_size := 26) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", C.text)
	b.add_theme_color_override("font_hover_color", C.accent)
	b.add_theme_color_override("font_pressed_color", C.accent)
	b.add_theme_color_override("font_disabled_color", Color(0.35, 0.4, 0.45))
	var normal := flat(C.panel2, 14)
	var hover := flat(C.panel2.lightened(0.35), 14, 2, C.accent)
	var pressed := flat(C.accent_dark, 14, 2, C.accent)
	if accent:
		normal = flat(C.accent_dark, 14, 2, C.accent)
		hover = flat(Color(0.1, 0.4, 0.36), 14, 3, C.accent)
		pressed = flat(Color(0.08, 0.34, 0.31), 14, 3, C.accent)
	b.add_theme_stylebox_override("normal", pad(normal, 10))
	b.add_theme_stylebox_override("hover", pad(hover, 10))
	b.add_theme_stylebox_override("pressed", pad(pressed, 10))
	b.add_theme_stylebox_override("disabled", pad(flat(Color(0.06, 0.08, 0.11), 14), 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func panel(min_size := Vector2(420, 200)) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = min_size
	p.add_theme_stylebox_override("panel", pad(flat(Color(0.05, 0.08, 0.12, 0.97), 18, 2, Color(0.18, 0.35, 0.33)), 18))
	return p

# ---------------- input-space hardening ----------------
# Engine input events should carry CANVAS coordinates (window pixels already
# transformed by the root viewport's stretch transform). Device reports and
# certain driver/OS paths can deliver raw WINDOW pixels instead, which makes
# every rect hit-test silently miss at any stretch scale != 1.0 (dead joystick
# / dead buttons on real phones). These helpers accept either space.

static func norm_pos(pos: Vector2, root: Viewport) -> Vector2:
	if root == null:
		return pos
	var vr := root.get_visible_rect()
	if vr.has_point(pos):
		return pos  # already canvas coordinates
	var p2: Vector2 = root.get_final_transform().affine_inverse() * pos
	if vr.has_point(p2):
		return p2  # was raw window pixels -> map to canvas
	return pos  # outside either space (shouldn't happen) -> trust as-is

static func hit(rect: Rect2, pos: Vector2, pad: float, root: Viewport) -> bool:
	return rect.grow(pad).has_point(norm_pos(pos, root))

static func screen_root() -> Control:
	var r := Control.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func tint(color: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.color = color
	cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cr

# Star / lock vector icon (custom-drawn, no font glyphs needed)
static func icon(kind_i: int, size := Vector2(22, 22), filled := true, fill_color: Color = C.gold) -> Control:
	var ic := preload("res://scripts/ui/widgets/icon_widgets.gd").new()
	ic.kind = kind_i
	ic.fill = 1.0 if filled else 0.0
	ic.fill_color = fill_color
	ic.custom_minimum_size = size
	return ic
