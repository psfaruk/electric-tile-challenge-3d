# Sparks — pooled one-shot CPUParticles3D emitters for zaps, failures and confetti.
extends Node3D

const N := 8
var _pool: Array = []
var _next := 0

func _ready() -> void:
	for i in N:
		var p := CPUParticles3D.new()
		p.amount = 28
		p.lifetime = 0.8
		p.one_shot = true
		p.explosiveness = 0.95
		p.direction = Vector3.UP
		p.spread = 85.0
		p.initial_velocity_min = 2.2
		p.initial_velocity_max = 5.5
		p.gravity = Vector3(0, -9.0, 0)
		p.scale_amount_min = 0.4
		p.scale_amount_max = 1.0
		p.emitting = false
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.05, 0.05, 0.05)
		var em := StandardMaterial3D.new()
		em.emission_enabled = true
		em.emission = Color(1.0, 0.4, 0.2)
		em.emission_energy_multiplier = 4.0
		mesh.material = em
		p.mesh = mesh
		add_child(p)
		_pool.append(p)

func burst(pos: Vector3, color: Color, strong := false) -> void:
	var p: CPUParticles3D = _pool[_next]
	_next = (_next + 1) % N
	if p.mesh != null and p.mesh.material != null:
		(p.mesh.material as StandardMaterial3D).emission = color
	p.gravity = Vector3(0, -4.5 if strong else -9.0, 0)
	p.initial_velocity_min = 2.5 if strong else 2.2
	p.initial_velocity_max = 6.5 if strong else 5.5
	p.global_position = pos
	p.restart()
	p.emitting = true

func confetti(pos: Vector3) -> void:
	burst(pos + Vector3(-0.5, 1.2, 0), Color(1.0, 0.77, 0.24), true)
	burst(pos + Vector3(0.5, 1.2, 0.3), Color(0.27, 0.97, 0.51), true)
	burst(pos + Vector3(0, 1.6, -0.4), Color(0.16, 0.9, 0.78), true)
