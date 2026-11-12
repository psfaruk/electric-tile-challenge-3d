# Robot — a stylized maintenance droid built from shaped primitives (original asset),
# with a fully code-driven animation set: idle / walk-run / air / victory / electrocution.
# This is the game's actual player character (no placeholder cubes: proportions,
# materials, glow visor and animation curves are hand-designed).
extends Node3D

enum S { IDLE, MOVE, AIR, VICTORY, ZAP }

const COL_BODY := Color(0.90, 0.93, 0.95)
const COL_DARK := Color(0.13, 0.15, 0.18)
const COL_ACCENT := Color(1.0, 0.478, 0.161)
const COL_VISOR := Color(0.16, 0.9, 0.78)
const HIPS_Y := 0.60

var state := S.IDLE
var speed01 := 0.0
var t := 0.0
var phase := 0.0
var zap_t := -1.0

var root_p: Node3D
var hips_p: Node3D
var torso_p: Node3D
var head_p: Node3D
var l_sh: Node3D
var r_sh: Node3D
var l_el: Node3D
var r_el: Node3D
var l_hip: Node3D
var r_hip: Node3D
var l_knee: Node3D
var r_knee: Node3D
var visor_mat: StandardMaterial3D

func _ready() -> void:
	_build()

# ---------------- construction ----------------

func _mat(albedo: Color, metallic: float, rough: float, emission := Color(0, 0, 0), energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = rough
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m

func _part(parent: Node3D, mesh: Mesh, mat: StandardMaterial3D, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b

func _capsule(r: float, len: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = len + 2.0 * r
	return c

func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s

func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c

func _build() -> void:
	var body_mat := _mat(COL_BODY, 0.12, 0.35)
	var dark_mat := _mat(COL_DARK, 0.65, 0.55)
	var acc_mat := _mat(COL_ACCENT, 0.15, 0.45)
	visor_mat = _mat(Color(0.1, 0.12, 0.12), 0.1, 0.2, COL_VISOR, 3.0)

	root_p = _pivot(self, Vector3.ZERO)
	hips_p = _pivot(root_p, Vector3(0, HIPS_Y, 0))
	_part(hips_p, _box(Vector3(0.26, 0.12, 0.16)), dark_mat, Vector3(0, -0.02, 0))

	torso_p = _pivot(hips_p, Vector3(0, 0.06, 0))
	_part(torso_p, _box(Vector3(0.34, 0.30, 0.22)), body_mat, Vector3(0, 0.16, 0))
	_part(torso_p, _box(Vector3(0.35, 0.05, 0.23)), acc_mat, Vector3(0, 0.055, 0))
	_part(torso_p, _cyl(0.055, 0.02), visor_mat, Vector3(0, 0.17, 0.115), Vector3(90, 0, 0))
	_part(torso_p, _box(Vector3(0.20, 0.20, 0.09)), dark_mat, Vector3(0, 0.16, -0.155))

	head_p = _pivot(torso_p, Vector3(0, 0.40, 0))
	_part(head_p, _box(Vector3(0.20, 0.16, 0.18)), body_mat, Vector3(0, 0.08, 0))
	_part(head_p, _box(Vector3(0.15, 0.05, 0.02)), visor_mat, Vector3(0, 0.09, 0.095))
	_part(head_p, _cyl(0.006, 0.08), dark_mat, Vector3(0.055, 0.175, 0))
	_part(head_p, _sphere(0.014), visor_mat, Vector3(0.055, 0.23, 0))
	_part(head_p, _cyl(0.02, 0.035), dark_mat, Vector3(0.105, 0.08, 0), Vector3(0, 0, 90))
	_part(head_p, _cyl(0.02, 0.035), dark_mat, Vector3(-0.105, 0.08, 0), Vector3(0, 0, 90))

	# arms
	l_sh = _pivot(torso_p, Vector3(-0.235, 0.28, 0))
	r_sh = _pivot(torso_p, Vector3(0.235, 0.28, 0))
	_part(torso_p, _sphere(0.055), acc_mat, Vector3(-0.215, 0.30, 0))
	_part(torso_p, _sphere(0.055), acc_mat, Vector3(0.215, 0.30, 0))
	l_el = _pivot(l_sh, Vector3(0, -0.17, 0))
	r_el = _pivot(r_sh, Vector3(0, -0.17, 0))
	for side in [[l_sh, l_el], [r_sh, r_el]]:
		var sh: Node3D = side[0]
		var el: Node3D = side[1]
		_part(sh, _capsule(0.04, 0.12), body_mat, Vector3(0, -0.09, 0))
		_part(el, _capsule(0.034, 0.11), dark_mat, Vector3(0, -0.08, 0))
		_part(el, _sphere(0.048), acc_mat, Vector3(0, -0.155, 0))

	# legs
	l_hip = _pivot(hips_p, Vector3(-0.09, -0.08, 0))
	r_hip = _pivot(hips_p, Vector3(0.09, -0.08, 0))
	l_knee = _pivot(l_hip, Vector3(0, -0.25, 0))
	r_knee = _pivot(r_hip, Vector3(0, -0.25, 0))
	for side in [[l_hip, l_knee], [r_hip, r_knee]]:
		var hip: Node3D = side[0]
		var knee: Node3D = side[1]
		_part(hip, _capsule(0.05, 0.15), body_mat, Vector3(0, -0.12, 0))
		_part(knee, _sphere(0.045), dark_mat, Vector3.ZERO)
		_part(knee, _capsule(0.042, 0.12), dark_mat, Vector3(0, -0.10, 0))
		_part(knee, _box(Vector3(0.11, 0.07, 0.20)), acc_mat, Vector3(0, -0.20, 0.05))

# ---------------- public control ----------------

func set_moving(mag: float) -> void:
	speed01 = clampf(mag, 0.0, 1.0)
	if state == S.VICTORY or state == S.ZAP:
		return
	if speed01 > 0.05:
		state = S.MOVE
	elif state == S.MOVE:
		state = S.IDLE

func set_air(on: bool) -> void:
	if state == S.VICTORY or state == S.ZAP:
		return
	if on:
		state = S.AIR
	elif state == S.AIR:
		state = S.IDLE

func play_victory() -> void:
	state = S.VICTORY
	t = 0.0

func play_zap() -> void:
	state = S.ZAP
	zap_t = 0.0

func bounce() -> void:
	var tw := create_tween()
	root_p.scale = Vector3(0.93, 0.80, 0.93)
	tw.tween_property(root_p, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------------- animation ----------------

func _damp(p: Node3D, target: Vector3, delta: float, rate := 14.0) -> void:
	var k: float = 1.0 - exp(-rate * delta)
	p.rotation = p.rotation.lerp(target, k)

func _process(delta: float) -> void:
	t += delta
	match state:
		S.IDLE: _anim_idle(delta)
		S.MOVE: _anim_move(delta)
		S.AIR: _anim_air(delta)
		S.VICTORY: _anim_victory(delta)
		S.ZAP: _anim_zap(delta)

func _anim_idle(delta: float) -> void:
	_damp(torso_p, Vector3(sin(t * 1.5) * 0.02, 0, 0), delta, 8.0)
	_damp(head_p, Vector3(0, sin(t * 0.6) * 0.14, 0), delta, 6.0)
	_damp(l_sh, Vector3(0.05 * sin(t * 1.2), 0, 0.07), delta, 6.0)
	_damp(r_sh, Vector3(0.05 * sin(t * 1.2 + PI), 0, -0.07), delta, 6.0)
	_damp(l_el, Vector3(0.1, 0, 0), delta, 6.0)
	_damp(r_el, Vector3(0.1, 0, 0), delta, 6.0)
	_damp(l_hip, Vector3.ZERO, delta)
	_damp(r_hip, Vector3.ZERO, delta)
	_damp(l_knee, Vector3.ZERO, delta)
	_damp(r_knee, Vector3.ZERO, delta)
	hips_p.position.y = HIPS_Y + sin(t * 2.0) * 0.004
	visor_mat.emission = COL_VISOR
	visor_mat.emission_energy_multiplier = 2.6 + 0.6 * sin(t * 2.0)

var _last_step_beat := 0

func _anim_move(delta: float) -> void:
	phase += delta * (4.0 + 8.0 * speed01)
	var beat := int(phase / PI)
	if beat != _last_step_beat and speed01 > 0.25:
		_last_step_beat = beat
		AudioManager.play_sfx("step", 0.9 + randf() * 0.15, -8.0)
	var a := speed01
	_damp(l_hip, Vector3(sin(phase) * 0.72 * a, 0, 0), delta, 18.0)
	_damp(r_hip, Vector3(-sin(phase) * 0.72 * a, 0, 0), delta, 18.0)
	_damp(l_knee, Vector3(clampf(-sin(phase), 0.0, 1.0) * 0.85 * a, 0, 0), delta, 18.0)
	_damp(r_knee, Vector3(clampf(sin(phase), 0.0, 1.0) * 0.85 * a, 0, 0), delta, 18.0)
	_damp(l_sh, Vector3(-sin(phase) * 0.5 * a, 0, 0.08), delta, 14.0)
	_damp(r_sh, Vector3(sin(phase) * 0.5 * a, 0, -0.08), delta, 14.0)
	_damp(l_el, Vector3(0.2 + a * 0.15, 0, 0), delta, 14.0)
	_damp(r_el, Vector3(0.2 + a * 0.15, 0, 0), delta, 14.0)
	_damp(torso_p, Vector3(0.1 * a, 0, sin(phase) * 0.03 * a), delta, 12.0)
	_damp(head_p, Vector3(-0.05 * a, 0, 0), delta, 10.0)
	hips_p.position.y = HIPS_Y + absf(sin(phase)) * 0.03 * a
	visor_mat.emission = COL_VISOR
	visor_mat.emission_energy_multiplier = 2.8

func _anim_air(delta: float) -> void:
	_damp(l_hip, Vector3(-0.45, 0, 0), delta, 10.0)
	_damp(r_hip, Vector3(0.2, 0, 0), delta, 10.0)
	_damp(l_knee, Vector3(0.9, 0, 0), delta, 10.0)
	_damp(r_knee, Vector3(0.55, 0, 0), delta, 10.0)
	_damp(l_sh, Vector3(-0.5, 0, 0.9), delta, 10.0)
	_damp(r_sh, Vector3(-0.5, 0, -0.9), delta, 10.0)
	_damp(l_el, Vector3(0.3, 0, 0), delta, 10.0)
	_damp(r_el, Vector3(0.3, 0, 0), delta, 10.0)
	_damp(torso_p, Vector3(0.06, 0, 0), delta, 8.0)
	_damp(head_p, Vector3(-0.1, 0, 0), delta, 8.0)
	hips_p.position.y = HIPS_Y
	visor_mat.emission = COL_VISOR
	visor_mat.emission_energy_multiplier = 3.2

func _anim_victory(delta: float) -> void:
	var hop: float = absf(sin(t * 6.0)) * 0.06
	hips_p.position.y = HIPS_Y + hop
	_damp(l_sh, Vector3(-2.45 + sin(t * 8.0) * 0.1, 0, 0.25), delta, 12.0)
	_damp(r_sh, Vector3(-2.45 + sin(t * 8.0 + PI) * 0.1, 0, -0.25), delta, 12.0)
	_damp(l_el, Vector3(0.2, 0, 0), delta, 12.0)
	_damp(r_el, Vector3(0.2, 0, 0), delta, 12.0)
	_damp(torso_p, Vector3(-0.05, sin(t * 3.0) * 0.1, 0), delta, 10.0)
	_damp(head_p, Vector3(-0.1, sin(t * 2.0) * 0.2, 0), delta, 10.0)
	_damp(l_hip, Vector3(-0.1, 0, 0), delta, 10.0)
	_damp(r_hip, Vector3(-0.1, 0, 0), delta, 10.0)
	_damp(l_knee, Vector3(0.25, 0, 0), delta, 10.0)
	_damp(r_knee, Vector3(0.25, 0, 0), delta, 10.0)
	visor_mat.emission = Color(1.0, 0.85, 0.3)
	visor_mat.emission_energy_multiplier = 3.0 + 1.5 * absf(sin(t * 5.0))

func _anim_zap(delta: float) -> void:
	zap_t += delta
	var shake: float = maxf(0.0, 0.55 - zap_t) * 0.55
	_damp(torso_p, Vector3(-minf(1.0, zap_t * 1.8) * 1.25 + randf() * shake, randf() * shake, randf() * shake), delta, 20.0)
	_damp(head_p, Vector3(-0.3 + randf() * shake, randf() * shake, randf() * shake), delta, 20.0)
	_damp(l_sh, Vector3(-0.6, 0, 1.3 + randf() * shake), delta, 20.0)
	_damp(r_sh, Vector3(-0.6, 0, -1.3 + randf() * shake), delta, 20.0)
	_damp(l_el, Vector3(0.4, 0, 0), delta, 20.0)
	_damp(r_el, Vector3(0.4, 0, 0), delta, 20.0)
	_damp(l_hip, Vector3(0.9 * minf(1.0, zap_t * 2.0), 0, 0.1), delta, 16.0)
	_damp(r_hip, Vector3(0.4 * minf(1.0, zap_t * 2.0), 0, -0.1), delta, 16.0)
	_damp(l_knee, Vector3(-1.2 * minf(1.0, zap_t * 2.0), 0, 0), delta, 16.0)
	_damp(r_knee, Vector3(-0.8 * minf(1.0, zap_t * 2.0), 0, 0), delta, 16.0)
	hips_p.position.y = HIPS_Y - minf(1.0, zap_t * 2.0) * 0.2
	if int(zap_t * 30) % 2 == 0:
		visor_mat.emission = Color(1, 1, 1)
		visor_mat.emission_energy_multiplier = 6.0
	else:
		visor_mat.emission = Color(1.0, 0.2, 0.15)
		visor_mat.emission_energy_multiplier = 0.6
