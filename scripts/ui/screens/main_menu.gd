# Main menu with a live 3D "attract mode": slowly orbiting camera over a
# pulsing tile arena with the robot idling on the floor.
extends Node

const U := preload("res://scripts/ui/ui.gd")
const Graphics := preload("res://scripts/game/graphics.gd")
const TEX_FLOOR := preload("res://assets/textures/floor_metal.png")
const TEX_TILE := preload("res://assets/textures/tile_face.png")

var main
var _orbit := 0.0
var _t := 0.0
var _cam_pivot: Node3D
var _cam: Camera3D
var _tiles: Array = []
var _next_flash := 0.0
var _robot

func _ready() -> void:
	AudioManager.play_music("menu")
	var quality := int(GameState.settings.get("quality", 1))
	Graphics.build_environment(self, quality)
	_build_attract()
	_build_ui()
	_wire_back()

func _build_attract() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.4, 0.45, 0.52)
	floor_mat.albedo_texture = TEX_FLOOR
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_scale = Vector3(5, 5, 5)
	floor_mat.metallic = 0.35
	floor_mat.roughness = 0.55
	var floor_mesh := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(13.0, 0.26, 9.0)
	floor_mesh.mesh = fb
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, 0, 0)
	add_child(floor_mesh)

	for r in 4:
		for c in 5:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = TEX_TILE
			mat.metallic = 0.45
			mat.roughness = 0.55
			mat.emission_enabled = true
			mat.emission_texture = TEX_TILE
			mat.emission = Color(0.16, 0.9, 0.78)
			mat.emission_energy_multiplier = 0.18
			var mi := MeshInstance3D.new()
			var tb := BoxMesh.new()
			tb.size = Vector3(1.15, 0.15, 1.15)
			mi.mesh = tb
			mi.material_override = mat
			mi.position = Vector3((c - 2) * 1.35, 0.075, (r - 1.5) * 1.35)
			add_child(mi)
			_tiles.append({"mat": mat, "phase": randf() * TAU, "speed": 0.5 + randf(), "boost": 0.0})

	_robot = preload("res://scripts/game/robot_model.gd").new()
	add_child(_robot)
	_robot.position = Vector3(0, 0.13, 0.3)
	_robot.rotation.y = PI

	_cam_pivot = Node3D.new()
	add_child(_cam_pivot)
	_cam = Camera3D.new()
	_cam.fov = 64.0
	_cam.position = Vector3(0, 3.4, 7.6)
	_cam_pivot.add_child(_cam)

	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.05, 0.14, 0.13)
	trim.emission_enabled = true
	trim.emission = Color(0.16, 0.92, 0.8)
	trim.emission_energy_multiplier = 1.4
	for s in [-1, 1]:
		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(11.0, 0.07, 0.1)
		strip.mesh = sb
		strip.material_override = trim
		strip.position = Vector3(0, 0.2, s * 4.2)
		add_child(strip)

func _process(delta: float) -> void:
	_t += delta
	_orbit += delta * 0.13
	_cam_pivot.rotation.y = _orbit
	_cam.look_at(Vector3(0, 0.5, 0.2), Vector3.UP)
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = 0.55 + randf() * 0.5
		var idx := randi() % _tiles.size()
		_tiles[idx]["boost"] = 1.0
	for td in _tiles:
		var mat: StandardMaterial3D = td["mat"]
		if td["boost"] > 0.0:
			td["boost"] = maxf(0.0, td["boost"] - delta * 2.2)
			mat.emission = Color(0.27, 0.97, 0.51)
		else:
			mat.emission = Color(0.16, 0.9, 0.78)
		mat.emission_energy_multiplier = 0.18 + 0.16 * sin(_t * td["speed"] + td["phase"]) + td["boost"] * 2.4

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var root := U.screen_root()
	layer.add_child(root)

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -420
	top.offset_right = 420
	top.offset_top = 60
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 4)
	root.add_child(top)
	top.add_child(U.title("ELECTRIC TILE", 66, U.C.text))
	top.add_child(U.title("CHALLENGE 3D", 44, U.C.accent))
	var sub := U.label("MEMORIZE. CROSS. SURVIVE.", 20, U.C.dim)
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	top.add_child(sub)

	var menu := VBoxContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -160
	menu.offset_right = 160
	menu.offset_top = -20
	menu.offset_bottom = 200
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 14)
	root.add_child(menu)
	menu.add_child(U.button("PLAY", _play, true, Vector2(320, 68), 30))
	menu.add_child(U.button("LEVEL SELECT", _levels, false, Vector2(320, 62), 26))
	menu.add_child(U.button("SETTINGS", _settings, false, Vector2(320, 62), 26))
	menu.add_child(U.button("HOW TO PLAY", _how, false, Vector2(320, 62), 26))
	menu.add_child(U.button("EXIT", _exit, false, Vector2(320, 62), 26))

	var ver := U.label("v1.0.0 — 50 levels — native 3D", 16, U.C.dim)
	_place(ver, Control.PRESET_BOTTOM_LEFT, 18, -44, 400, -14)
	root.add_child(ver)

	var star_box := HBoxContainer.new()
	star_box.add_theme_constant_override("separation", 8)
	_place(star_box, Control.PRESET_BOTTOM_RIGHT, -400, -48, 18, -12)
	root.add_child(star_box)
	var star := U.icon(0, Vector2(26, 26), true, U.C.gold)
	star_box.add_child(star)
	var total := U.label("%d / 150" % GameState.total_stars(), 22, U.C.gold)
	star_box.add_child(total)

func _place(c: Control, preset: int, ol: float, ot: float, orr: float, ob: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob

func _play() -> void:
	AudioManager.click()
	main.goto("levels")

func _levels() -> void:
	AudioManager.click()
	main.goto("levels")

func _settings() -> void:
	AudioManager.click()
	main.goto("settings")

func _exit() -> void:
	AudioManager.play_sfx("back")
	get_tree().quit()

func _how() -> void:
	AudioManager.click()
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := U.screen_root()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	root.add_child(U.tint(Color(0.01, 0.02, 0.04, 0.8)))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := U.panel(Vector2(640, 430))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	vb.add_child(U.title("HOW TO PLAY", 38, U.C.accent))
	for line in [
		"1. Watch the safe path when the floor lights up.",
		"2. The tiles go dark — cross the arena from memory.",
		"3. Wrong tile = electric shock. Retry instantly.",
		"PATTERN levels: step the tiles in the exact shown order.",
		"TIMED levels: beat the countdown.",
		"MASTER levels: hazard tiles flip between safe and danger.",
		"Joystick moves. JUMP button hops. Drag right side to look.",
		"1 star = finish, 2 = beat par time, 3 = beat gold time.",
	]:
		var l := U.label(line, 20, U.C.text)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		vb.add_child(l)
	var close_b := U.button("GOT IT", func(): layer.queue_free(), true, Vector2(240, 56), 24)
	vb.add_child(close_b)

func _wire_back() -> void:
	var win := get_window()
	if win.has_signal("go_back_requested"):
		win.go_back_requested.connect(_on_back)

func _on_back() -> void:
	get_tree().quit()

func _exit_tree() -> void:
	var win := get_window()
	if win != null and win.has_signal("go_back_requested") and win.go_back_requested.is_connected(_on_back):
		win.go_back_requested.disconnect(_on_back)
