# TileField — the rendering layer of the electric tile floor.
# Every tile is 3 instances in shared MultiMeshes (144 tiles -> 3 draw calls):
#   * glass top    (BoxMesh        + PBR smoked-glass material)
#   * steel lip    (ring mesh      + painted-steel PBR)
#   * LED edge     (ring mesh      + custom shader: per-instance COLOR -> EMISSION)
# State colors are written per-instance via MultiMesh instance colors, so the
# per-tile feedback of v1 is preserved with none of the per-tile materials.
# tile.gd keeps its v1 state API and drives this field.
extends Node3D

const Grid := preload("res://scripts/game/grid.gd")
const TEX_GLASS := preload("res://assets/textures/pbr/tile_top_glass_albedo.png")
const TEX_GLASS_N := preload("res://assets/textures/pbr/tile_top_glass_normal.png")
const TEX_GLASS_R := preload("res://assets/textures/pbr/tile_top_glass_rough.png")
const TEX_PAINT := preload("res://assets/textures/pbr/steel_painted_dark_albedo.webp")
const TEX_PAINT_N := preload("res://assets/textures/pbr/steel_painted_dark_normal.webp")
const TEX_PAINT_O := preload("res://assets/textures/pbr/steel_painted_dark_orm.webp")

# Edge shader: instance color IS the emission (color already scaled by energy).
const EDGE_SHADER := "
shader_type spatial;
render_mode specular_schlick_ggx;
void fragment() {
        ALBEDO = COLOR.rgb * 0.04 + vec3(0.008, 0.009, 0.012);
        EMISSION = COLOR.rgb;
        ROUGHNESS = 0.38;
        SPECULAR = 0.4;
}
"

var _cols := 6
var _rows := 6
var _edges: MultiMesh
var _edges_mat: ShaderMaterial
var _base_colors: Array = []      # per-tile hue (Color)
var _cur_energy: Array = []       # per-tile energy multiplier (float)
var _shared_flags: Array = []     # per-tile shared mode: -1 own / 0 danger / 1 safe
var _pulse_t := 0.0
var _glow: OmniLight3D

func setup(level: Dictionary) -> void:
        _cols = int(level.get("cols", 6))
        _rows = int(level.get("rows", 6))
        var n := _cols * _rows

        # --- meshes ---
        var glass := BoxMesh.new()
        glass.size = Vector3(1.10, 0.035, 1.10)
        var lip := _ring_mesh(0.60, 0.53, 0.118, 0.158)
        var edge := _ring_mesh(0.635, 0.525, 0.115, 0.128)

        # --- materials ---
        var glass_mat := StandardMaterial3D.new()
        glass_mat.albedo_texture = TEX_GLASS
        glass_mat.albedo_color = Color(0.85, 0.9, 0.95)
        glass_mat.normal_enabled = true
        glass_mat.normal_texture = TEX_GLASS_N
        glass_mat.normal_scale = 0.6
        glass_mat.roughness_texture = TEX_GLASS_R
        glass_mat.roughness = 0.7   # glossier tops -> SSR sheen reads (VLM final)
        glass_mat.metallic = 0.25
        glass_mat.uv1_triplanar = true
        glass_mat.uv1_scale = Vector3(1, 1, 1)

        var lip_mat := StandardMaterial3D.new()
        lip_mat.albedo_texture = TEX_PAINT
        lip_mat.albedo_color = Color(0.95, 0.97, 1.0)
        lip_mat.normal_enabled = true
        lip_mat.normal_texture = TEX_PAINT_N
        lip_mat.normal_scale = 0.8
        # photoscan ORM: AO(R) rough(G) metal(B) — painted steel is dielectric,
        # so the map's metal channel (~0) drives metalness
        lip_mat.orm_texture = TEX_PAINT_O
        lip_mat.ao_enabled = true
        lip_mat.roughness = 1.0
        lip_mat.metallic = 1.0
        lip_mat.uv1_triplanar = true
        lip_mat.uv1_scale = Vector3(0.45, 0.45, 0.45)

        _edges_mat = ShaderMaterial.new()
        _edges_mat.shader = Shader.new()
        _edges_mat.shader.code = EDGE_SHADER

        # --- three multimeshes over the whole grid ---
        _build_mm(glass, glass_mat, n, false)
        _build_mm(lip, lip_mat, n, false)
        _edges = _build_mm(edge, _edges_mat, n, true)

        _base_colors.resize(n)
        _cur_energy.resize(n)
        _shared_flags.resize(n)
        for i in n:
                _base_colors[i] = Color(0.16, 0.9, 0.78)
                _cur_energy[i] = 0.16
                _shared_flags[i] = -1

        # one soft light above the grid whose color echoes the tile states —
        # sells "the floor glows" with real light instead of emission only
        _glow = OmniLight3D.new()
        _glow.name = "GridGlow"
        _glow.light_energy = 0.0
        _glow.omni_range = 9.0
        _glow.position = Vector3(0, 2.2, -((_rows - 1) * Grid.PITCH) / 2.0)
        add_child(_glow)

func _build_mm(mesh: Mesh, mat: Material, n: int, colors: bool) -> MultiMesh:
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.mesh = mesh
        mm.instance_count = n
        mm.use_colors = colors
        var idx := 0
        for r in _rows:
                for c in _cols:
                        var center: Vector3 = Grid.tile_center(Vector2i(r, c), _cols)
                        mm.set_instance_transform(idx, Transform3D(Basis(), Vector3(center.x, 0.0, center.z)))
                        if colors:
                                mm.set_instance_color(idx, Color(0.16, 0.9, 0.78) * 0.16)
                        idx += 1
        var mmi := MultiMeshInstance3D.new()
        mmi.multimesh = mm
        mmi.material_override = mat
        add_child(mmi)
        return mm

# Flat rectangular ring: 4 side segments, each with a top face, an outer
# wall and an inner wall (with correct outward/inward normals). Wound CCW
# as seen from outside/above so no face is backface-culled.
func _ring_mesh(outer: float, inner: float, y0: float, y1: float) -> ArrayMesh:
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var o := Vector2(outer, outer)
        var iv := Vector2(inner, inner)
        var corners := [Vector2(-o.x, -o.y), Vector2(o.x, -o.y), Vector2(o.x, o.y), Vector2(-o.x, o.y)]
        var icorners := [Vector2(-iv.x, -iv.y), Vector2(iv.x, -iv.y), Vector2(iv.x, iv.y), Vector2(-iv.x, iv.y)]
        var up := Vector3(0, 1, 0)
        for ci in 4:
                var n := (ci + 1) % 4
                var a: Vector2 = corners[ci]
                var b: Vector2 = corners[n]
                var ia: Vector2 = icorners[ci]
                var ib: Vector2 = icorners[n]
                # top face ring segment (two CCW triangles seen from above)
                _vtx(st, Vector3(a.x, y1, a.y), up)
                _vtx(st, Vector3(ib.x, y1, ib.y), up)
                _vtx(st, Vector3(b.x, y1, b.y), up)
                _vtx(st, Vector3(a.x, y1, a.y), up)
                _vtx(st, Vector3(ia.x, y1, ia.y), up)
                _vtx(st, Vector3(ib.x, y1, ib.y), up)
                # outer wall
                var wm: Vector2 = (a + b) * 0.5
                var wall_n := Vector3(wm.x, 0.0, wm.y).normalized()
                _vtx(st, Vector3(a.x, y1, a.y), wall_n)
                _vtx(st, Vector3(b.x, y1, b.y), wall_n)
                _vtx(st, Vector3(b.x, y0, b.y), wall_n)
                _vtx(st, Vector3(a.x, y1, a.y), wall_n)
                _vtx(st, Vector3(b.x, y0, b.y), wall_n)
                _vtx(st, Vector3(a.x, y0, a.y), wall_n)
                # inner wall (normal points inward toward the tile center)
                var im: Vector2 = (ia + ib) * 0.5
                var in_n := Vector3(-im.x, 0.0, -im.y).normalized()
                _vtx(st, Vector3(ib.x, y0, ib.y), in_n)
                _vtx(st, Vector3(ia.x, y1, ia.y), in_n)
                _vtx(st, Vector3(ia.x, y0, ia.y), in_n)
                _vtx(st, Vector3(ib.x, y0, ib.y), in_n)
                _vtx(st, Vector3(ib.x, y1, ib.y), in_n)
                _vtx(st, Vector3(ia.x, y1, ia.y), in_n)
        # triplanar materials build their own tangents in-shader; no UVs needed
        return st.commit()

func _vtx(st: SurfaceTool, v: Vector3, n: Vector3) -> void:
        st.set_normal(n)
        st.add_vertex(v)

# ---------------- per-tile color control (used by tile.gd) ----------------

func idx_of(cell: Vector2i) -> int:
        return cell.x * _cols + cell.y

func set_edge_color(idx: int, color: Color) -> void:
        if idx >= 0 and idx < _edges.instance_count:
                _edges.set_instance_color(idx, color)

func set_base_hue(idx: int, color: Color) -> void:
        _base_colors[idx] = color

func set_shared_mode(idx: int, mode: int) -> void:
        _shared_flags[idx] = mode

func is_shared(idx: int, mode: int) -> bool:
        return _shared_flags[idx] == mode

func _process(delta: float) -> void:
        _pulse_t += delta
        var hi := 1.85 + 0.45 * sin(_pulse_t * 5.2)
        var lo := 1.2 + 0.35 * sin(_pulse_t * 4.4)
        var safe_n := 0
        var danger_n := 0
        for i in _shared_flags.size():
                var m: int = _shared_flags[i]
                if m > 0:
                        set_edge_color(i, Color(0.27, 0.97, 0.51) * hi)
                        safe_n += 1
                elif m == 0:
                        set_edge_color(i, Color(1.0, 0.3, 0.3) * lo)
                        danger_n += 1
        if _glow != null:
                if safe_n + danger_n > 0:
                        # mix the glow toward whichever mode dominates
                        var f := float(safe_n) / float(safe_n + danger_n)
                        _glow.light_color = Color(0.27, 0.97, 0.51).lerp(Color(1.0, 0.3, 0.3), 1.0 - f)
                        _glow.light_energy = 0.55 + 0.18 * sin(_pulse_t * 5.2)
                else:
                        _glow.light_energy = 0.12
                        _glow.light_color = Color(0.16, 0.9, 0.78)
