# Level select — 50 level cards in 5 tier sections, locked/unlocked states,
# earned stars, best-time feel. Scrollable grid with touch-friendly targets.
extends CanvasLayer

const U := preload("res://scripts/ui/ui.gd")
const IconWidget := preload("res://scripts/ui/widgets/icon_widgets.gd")

const TIERS := [
	{"label": "BEGINNER", "from": 1, "to": 10, "color": Color(0.27, 0.97, 0.51)},
	{"label": "INTERMEDIATE", "from": 11, "to": 20, "color": Color(0.18, 0.90, 0.78)},
	{"label": "ADVANCED", "from": 21, "to": 30, "color": Color(1.0, 0.77, 0.24)},
	{"label": "EXPERT", "from": 31, "to": 40, "color": Color(1.0, 0.48, 0.16)},
	{"label": "MASTER", "from": 41, "to": 50, "color": Color(1.0, 0.30, 0.30)},
]

var main

func _ready() -> void:
	layer = 10
	AudioManager.play_music("menu")
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(U.tint(U.C.bg))
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	root.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	# header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	vb.add_child(header)
	var back_btn := U.button("BACK", _back, false, Vector2(120, 52), 22)
	header.add_child(back_btn)
	var title_mid := VBoxContainer.new()
	title_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_mid.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(title_mid)
	title_mid.add_child(U.title("SELECT LEVEL", 38, U.C.accent))
	var stars_box := HBoxContainer.new()
	stars_box.alignment = BoxContainer.ALIGNMENT_END
	stars_box.add_theme_constant_override("separation", 8)
	header.add_child(stars_box)
	stars_box.add_child(U.icon(0, Vector2(24, 24), true, U.C.gold))
	var total := U.label("%d / 150" % GameState.total_stars(), 24, U.C.gold)
	total.custom_minimum_size = Vector2(90, 24)
	stars_box.add_child(total)

	# scrollable grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	for tier in TIERS:
		var header_l := U.label("%s  —  %d to %d" % [tier.label, tier.from, tier.to], 20, tier.color)
		header_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		header_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		header_l.add_theme_constant_override("outline_size", 7)
		content.add_child(header_l)
		var grid := GridContainer.new()
		grid.columns = 10
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		content.add_child(grid)
		for id in range(tier.from, tier.to + 1):
			grid.add_child(_make_level_button(id, tier.color))

	_wire_back()

func _make_level_button(id: int, tier_color: Color) -> Button:
	var unlocked: bool = GameState.is_unlocked(id)
	var stars := GameState.get_stars(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(92, 84)
	b.text = str(id)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", U.C.text)
	b.add_theme_color_override("font_hover_color", U.C.accent)
	b.add_theme_color_override("font_pressed_color", tier_color)
	b.add_theme_color_override("font_disabled_color", Color(0.34, 0.4, 0.46))
	var normal := U.flat(Color(0.07, 0.11, 0.15), 12, 2, tier_color * 0.55)
	var disabled := U.flat(Color(0.05, 0.07, 0.09), 12, 2, Color(0.08, 0.1, 0.13))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", U.flat(Color(0.1, 0.16, 0.2), 12, 3, tier_color))
	b.add_theme_stylebox_override("pressed", U.flat(Color(0.12, 0.2, 0.24), 12, 3, tier_color))
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.disabled = not unlocked
	b.pressed.connect(_on_level.bind(id))
	# star pips
	for i in 3:
		var star := IconWidget.new()
		star.kind = 0
		star.fill = 1.0 if i < stars else 0.0
		star.fill_color = tier_color
		star.position = Vector2(22 + i * 19, 58)
		star.size = Vector2(15, 15)
		b.add_child(star)
	if not unlocked:
		var lock := IconWidget.new()
		lock.kind = 1
		lock.position = Vector2(36, 24)
		lock.size = Vector2(20, 20)
		b.add_child(lock)
	return b

func _on_level(id: int) -> void:
	AudioManager.play_sfx("unlock", 1.0 + 0.02 * id)
	main.goto("gameplay", {"level": id})

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
