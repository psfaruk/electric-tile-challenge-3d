# Sparks — pooled one-shot effects for zaps, arc discharges and confetti.
# v2 (graphics overhaul): adds ARC lightning — short jagged line-bolt meshes
# flickering between the player and the tile (no continuous per-tile systems,
# everything is one-shot from an 8-slot pool, hidden when idle).
extends Node3D

const N := 8
var _pool: Array = []
var _next := 0
var _arc_pool: Array = []
var _arc_next := 0
var _t := 0.0

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
        # arc pool: 8 line-bolt meshes, hidden until used
        for i in N:
                var mi := MeshInstance3D.new()
                var mat := StandardMaterial3D.new()
                mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
                mat.emission_enabled = true
                mat.emission = Color(1.0, 0.62, 0.3)
                mat.emission_energy_multiplier = 5.0
                mi.material_override = mat
                mi.visible = false
                add_child(mi)
                _arc_pool.append({"mi": mi, "mat": mat, "life": 0.0})

func _process(delta: float) -> void:
        _t += delta
        for a in _arc_pool:
                if a["life"] > 0.0:
                        a["life"] -= delta
                        var mi: MeshInstance3D = a["mi"]
                        # flicker: 60Hz strobe then fade
                        mi.visible = a["life"] > 0.06 or fmod(_t * 60.0, 2.0) > 1.0
                        (a["mat"] as StandardMaterial3D).emission_energy_multiplier = 3.0 + 4.0 * a["life"]
                        if a["life"] <= 0.0:
                                mi.visible = false
                                mi.mesh = null

# ---------------- particle bursts ----------------

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

# ---------------- arc lightning ----------------

# One jagged bolt between `from` and `to` (or upward if to == from),
# flickering for ~0.2 s. Pooled; repeated calls reuse the oldest arc.
func arc(from_pos: Vector3, to_pos: Vector3, color := Color(1.0, 0.5, 0.25)) -> void:
        var a: Dictionary = _arc_pool[_arc_next]
        _arc_next = (_arc_next + 1) % N
        var target: Vector3 = to_pos if to_pos != from_pos else from_pos + Vector3(0, 0.9, 0)
        var mesh := ArrayMesh.new()
        var verts := PackedVector3Array()
        var steps := 6
        for i in steps:
                var f0 := from_pos.lerp(target, float(i) / steps)
                var f1 := from_pos.lerp(target, float(i + 1) / steps)
                var jitter := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.28
                if i < steps - 1:
                        f1 += jitter
                verts.append(to_local(f0))
                verts.append(to_local(f1))
        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = verts
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
        var mi: MeshInstance3D = a["mi"]
        mi.mesh = mesh
        (a["mat"] as StandardMaterial3D).emission = color
        a["life"] = 0.2
        mi.visible = true
