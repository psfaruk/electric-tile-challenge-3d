# CameraRig — dual-mode third-person camera.
# SMART: smooth follow, gently auto-aligns behind the player's heading.
# MANUAL: drag to orbit, pinch/wheel to zoom (auto-follow resumes after a pause).
# Ray-cast clipping prevention keeps the camera out of walls and floor.
extends Node3D

var player
var cam: Camera3D
var mode := 0            # 0 smart / 1 manual
var yaw := 0.0
var pitch := 0.5
var dist := 5.4

var _pos := Vector3.ZERO
var _shake := 0.0
var _manual_t := 0.0

func setup(p, _vp: Viewport) -> void:
	player = p
	cam = Camera3D.new()
	cam.fov = 66.0
	cam.near = 0.1
	cam.far = 60.0
	add_child(cam)
	mode = int(GameState.settings.get("cam_mode", 0))
	_pos = player.global_position + Vector3(0, 1.0, 0)
	global_position = _pos

func set_mode(m: int) -> void:
	mode = m

func rotate_input(raw_dx: float, raw_dy: float) -> void:
	var s: float = GameState.settings.get("sens", 1.0)
	yaw -= raw_dx * 0.0045 * s
	pitch = clampf(pitch + raw_dy * 0.003 * s, 0.12, 1.15)
	_manual_t = 2.2

func zoom_input(dz: float) -> void:
	dist = clampf(dist + dz, 3.2, 9.0)
	_manual_t = 2.2

func shake(amount: float) -> void:
	_shake = minf(1.4, _shake + amount)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var target: Vector3 = player.global_position
	var kx := 1.0 - exp(-8.0 * delta)
	var ky := 1.0 - exp(-4.0 * delta)
	_pos.x = lerpf(_pos.x, target.x, kx)
	_pos.z = lerpf(_pos.z, target.z, kx)
	_pos.y = lerpf(_pos.y, target.y, ky)

	if mode == 0 and _manual_t <= 0.0:
		var v: Vector3 = player.velocity
		var h := Vector2(v.x, v.z).length()
		if h > 1.5:
			var want := atan2(v.x, v.z) + PI
			yaw = lerp_angle(yaw, want, 1.0 - exp(-1.7 * delta))
	_manual_t = maxf(0.0, _manual_t - delta)
	global_position = _pos

	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var desired := global_position + off
	var from := global_position + Vector3.UP * 1.2
	if from.distance_to(desired) > 0.3:
		var q := PhysicsRayQueryParameters3D.create(from, desired, 1, [player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
		if hit.has("position"):
			desired = hit["position"].lerp(from, 0.08)
	cam.global_position = desired
	cam.look_at(global_position + Vector3(0, 1.15, 0), Vector3.UP)
	if _shake > 0.004:
		_shake = maxf(0.0, _shake - delta * 1.8)
		cam.global_position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * _shake * 0.35
