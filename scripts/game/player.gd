# Player — third-person CharacterBody3D driven by the virtual joystick / keyboard,
# with gravity, jump, ground snap, footsteps and facing.
extends CharacterBody3D

const SPEED := 5.2
const ACCEL := 24.0
const FRICTION := 20.0
const JUMP_V := 6.4
const GRAVITY := 16.0

var locked := true
var move_input := Vector2.ZERO   # world-space desired direction (length <= 1)
var model

var _was_floor := true

func _ready() -> void:
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.5
	cs.shape = shape
	cs.position = Vector3(0, 0.75, 0)
	add_child(cs)
	floor_snap_length = 0.12
	model = preload("res://scripts/game/robot_model.gd").new()
	add_child(model)

func _physics_process(delta: float) -> void:
	if not locked and Input.is_action_just_pressed("jump"):
		request_jump()
	var target := Vector3.ZERO
	var accel := FRICTION
	if not locked and move_input.length() > 0.12:
		target = Vector3(move_input.x, 0, move_input.y) * SPEED
		accel = ACCEL
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	if is_on_floor() and not _was_floor:
		AudioManager.play_sfx("land", 1.0, -6.0)
		model.bounce()
	_was_floor = is_on_floor()

	var hspd: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor():
		model.set_moving(clampf(hspd / SPEED, 0.0, 1.0))
		model.set_air(false)
	else:
		model.set_air(true)
	if hspd > 0.35:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z) + PI, 1.0 - exp(-10.0 * delta))

func request_jump() -> void:
	if locked or not is_on_floor():
		return
	velocity.y = JUMP_V
	AudioManager.play_sfx("jump")
	AudioManager.haptic(20)

func play_zap() -> void:
	locked = true
	velocity.x = 0.0
	velocity.z = 0.0
	model.play_zap()

func play_victory() -> void:
	locked = true
	velocity.x = 0.0
	velocity.z = 0.0
	model.play_victory()
