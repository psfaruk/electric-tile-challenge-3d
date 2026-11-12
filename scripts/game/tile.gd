# Tile — one electric floor tile. Visual-only (collision handled by the arena floor).
# Own material per tile for individual feedback states; the challenge controller
# can swap in SHARED materials during reveal phases (cheap + batched look).
extends MeshInstance3D

const TEX_FACE := preload("res://assets/textures/tile_face.png")

const COL_TEAL := Color(0.16, 0.9, 0.78)
const COL_SAFE := Color(0.27, 0.97, 0.51)
const COL_DANGER := Color(1.0, 0.30, 0.30)
const COL_GOLD := Color(1.0, 0.77, 0.24)
const COL_WARN := Color(1.0, 0.48, 0.16)

var cell := Vector2i(-99, -99)
var _own_mat: StandardMaterial3D
var _tween: Tween

func setup(tile_cell: Vector2i) -> void:
        cell = tile_cell
        var bm := BoxMesh.new()
        bm.size = Vector3(1.15, 0.15, 1.15)
        mesh = bm
        _own_mat = _make_own()
        material_override = _own_mat
        _dampen()

static func _make_own() -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.albedo_texture = TEX_FACE
        m.metallic = 0.45
        m.roughness = 0.55
        m.emission_enabled = true
        m.emission_texture = TEX_FACE
        m.emission = COL_TEAL
        m.emission_energy_multiplier = 0.16
        return m

func set_shared(mat: Material) -> void:
        if _tween != null and _tween.is_valid():
                _tween.kill()
        material_override = mat

func set_own() -> void:
        material_override = _own_mat

func _dampen() -> void:
        _own_mat.emission = COL_TEAL
        _own_mat.emission_energy_multiplier = 0.16

func reset_visual() -> void:
        set_own()
        _dampen()

func flash_correct(index_in_path: int) -> void:
        set_own()
        if _tween != null and _tween.is_valid():
                _tween.kill()
        _own_mat.emission = COL_SAFE
        _own_mat.emission_energy_multiplier = 2.2
        _tween = create_tween()
        _tween.tween_property(_own_mat, "emission_energy_multiplier", 0.75, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
        _tween.tween_interval(1.2)
        _tween.tween_property(_own_mat, "emission_energy_multiplier", 0.22, 0.6)

func flash_neutral() -> void:
        set_own()
        if _tween != null and _tween.is_valid():
                _tween.kill()
        _own_mat.emission = COL_TEAL
        _own_mat.emission_energy_multiplier = 1.4
        _tween = create_tween()
        _tween.tween_property(_own_mat, "emission_energy_multiplier", 0.16, 0.5)

func set_flip(safe: bool, warn: bool) -> void:
        set_own()
        if _tween != null and _tween.is_valid():
                _tween.kill()
        if warn:
                _own_mat.emission = COL_WARN
                _own_mat.emission_energy_multiplier = 0.75 + 0.65 * absf(sin(float(Time.get_ticks_msec()) * 0.008))
        elif safe:
                _own_mat.emission = COL_SAFE
                _own_mat.emission_energy_multiplier = 0.55
        else:
                _own_mat.emission = COL_DANGER
                _own_mat.emission_energy_multiplier = 0.4

func mark_failed() -> void:
        set_own()
        if _tween != null and _tween.is_valid():
                _tween.kill()
        _own_mat.emission = COL_DANGER
        _own_mat.emission_energy_multiplier = 3.2
        _tween = create_tween()
        _tween.tween_property(_own_mat, "emission_energy_multiplier", 1.3, 1.8)

func reveal_safe() -> void:
        set_own()
        _own_mat.emission = COL_SAFE
        _own_mat.emission_energy_multiplier = 0.9

func reveal_danger() -> void:
        set_own()
        _own_mat.emission = COL_DANGER
        _own_mat.emission_energy_multiplier = 0.4
