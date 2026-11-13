# Arena — builds a realistic television game-show studio around the electric
# tile grid: concrete/steel shell, ceiling truss grid with spotlight fixtures,
# audience bleachers with crowd billboards, a large LED show wall behind the
# finish line, vertical LED accent columns, hazard curb + recessed grid pit,
# start/finish stage platforms and a lit finish portal.
# Performance-first: every repeated element is a MultiMesh with a shared
# PBR material (truss members, fixtures, crowd, wall ribs, panel grids).
# Public API preserved from v1: setup(level, quality), get_spawn(), get_finish_z().
extends Node3D

const Grid := preload("res://scripts/game/grid.gd")

# PBR texture library.
# v3 PHOTOSCAN LIBRARY (CC0, polyhaven.com — see docs/ASSET_INVENTORY.md):
#   rubber floor  <- rubber_tiles | concrete <- brushed_concrete
#   painted steel <- blue_metal_plate (desaturated to graphite at conversion)
#   tread decks   <- metal_plate (desaturated to neutral steel)
#   stage drape   <- velour_velvet
# ORM maps: AO in R, roughness in G, metallic in B (identical packing to
# Godot's orm_texture). Truss/deck structural steel keeps the fine synthetic
# brushed weave (gen_textures_pbr.py) — photoscans read scaled-wrong on thin
# members (VLM art review, docs/asset_reports/).
const TEX_STEEL := preload("res://assets/textures/pbr/steel_brushed_albedo.png")
const TEX_STEEL_N := preload("res://assets/textures/pbr/steel_brushed_normal.png")
const TEX_STEEL_R := preload("res://assets/textures/pbr/steel_brushed_rough.png")
const TEX_PAINT := preload("res://assets/textures/pbr/steel_painted_dark_albedo.webp")
const TEX_PAINT_N := preload("res://assets/textures/pbr/steel_painted_dark_normal.webp")
const TEX_PAINT_O := preload("res://assets/textures/pbr/steel_painted_dark_orm.webp")
const TEX_TREAD := preload("res://assets/textures/pbr/tread_plate_albedo.webp")
const TEX_TREAD_N := preload("res://assets/textures/pbr/tread_plate_normal.webp")
const TEX_TREAD_O := preload("res://assets/textures/pbr/tread_plate_orm.webp")
const TEX_CONCRETE := preload("res://assets/textures/pbr/concrete_wall_albedo.webp")
const TEX_CONCRETE_N := preload("res://assets/textures/pbr/concrete_wall_normal.webp")
const TEX_CONCRETE_O := preload("res://assets/textures/pbr/concrete_wall_orm.webp")
const TEX_RUBBER := preload("res://assets/textures/pbr/rubber_mat_albedo.webp")
const TEX_RUBBER_N := preload("res://assets/textures/pbr/rubber_mat_normal.webp")
const TEX_RUBBER_O := preload("res://assets/textures/pbr/rubber_mat_orm.webp")
const TEX_CROWD := preload("res://assets/textures/pbr/audience_crowd_albedo.png")
const TEX_LED := preload("res://assets/textures/pbr/led_walls_show_albedo.png")
const TEX_CURTAIN := preload("res://assets/textures/pbr/curtain_stage_albedo.webp")
const TEX_CURTAIN_N := preload("res://assets/textures/pbr/curtain_stage_normal.webp")
const TEX_CURTAIN_O := preload("res://assets/textures/pbr/curtain_stage_orm.webp")
const TEX_HAZARD := preload("res://assets/textures/hazard.png")
const TEX_PAD_START := preload("res://assets/textures/pad_start.png")
const TEX_PAD_FINISH := preload("res://assets/textures/pad_finish.png")

var cols := 6
var rows := 6
var quality := 1

var _t := 0.0
var _led_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _crowd_banks: Array = []

# ---------------- public API (unchanged contract) ----------------

func setup(level: Dictionary, q: int) -> void:
        cols = int(level.get("cols", 6))
        rows = int(level.get("rows", 6))
        quality = q
        _build()

func get_spawn() -> Vector3:
        return Grid.spawn_pos()

func get_finish_z() -> float:
        return Grid.finish_z(rows)

func _process(delta: float) -> void:
        _t += delta
        # LED wall content slowly sweeps; gentle energy breathing. Cheap: one
        # shared material, no per-frame node work.
        if _led_mat != null:
                _led_mat.uv1_offset.x = fmod(_led_mat.uv1_offset.x + delta * 0.018, 1.0)
                _led_mat.emission_energy_multiplier = 1.55 + 0.15 * sin(_t * 1.3)
        if _trim_mat != null:
                _trim_mat.emission_energy_multiplier = 1.15 + 0.25 * sin(_t * 2.2)
        if quality >= 2 and not _crowd_banks.is_empty():
                # audience "sway" on HIGH only — one node scale per bank
                var s := 1.0 + 0.006 * sin(_t * 0.9)
                for bank in _crowd_banks:
                        bank.scale.y = s

# ---------------- material factory ----------------

func _pbr(albedo: Texture2D, normal: Texture2D, rough: Texture2D, scale := Vector3(3, 3, 3), metallic := 0.0, rough_bias := 1.0, triplanar := true, orm: Texture2D = null) -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.albedo_texture = albedo
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 1.0
        if orm != null:
                # photoscan ORM: AO(R) rough(G) metal(B) — scalar multipliers
                # still apply, so metallic=1.0 lets the map drive metalness.
                m.orm_texture = orm
                m.ao_enabled = true
                m.roughness = 1.0
        elif rough != null:
                m.roughness_texture = rough  # grayscale map — any channel reads correctly
                m.roughness = rough_bias
        m.metallic = metallic
        if triplanar:
                m.uv1_triplanar = true
                m.uv1_scale = scale
        return m

func _plain(color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.albedo_color = color
        m.roughness = rough
        m.metallic = metal
        return m

func _emissive(color: Color, energy := 1.6, tex: Texture2D = null) -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.albedo_color = Color(0.04, 0.04, 0.05)
        m.emission_enabled = true
        m.emission = color
        m.emission_energy_multiplier = energy
        if tex != null:
                m.emission_texture = tex
                m.albedo_texture = tex
        m.roughness = 0.6
        return m

# ---------------- mesh helpers ----------------

func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.material_override = mat
        mi.position = pos
        mi.rotation_degrees = rot
        add_child(mi)
        return mi

func _box(sz: Vector3) -> BoxMesh:
        var b := BoxMesh.new()
        b.size = sz
        return b

func _cyl(r: float, h: float) -> CylinderMesh:
        var c := CylinderMesh.new()
        c.top_radius = r
        c.bottom_radius = r
        c.height = h
        c.radial_segments = 10
        return c

func _plane(w: float, h: float) -> PlaneMesh:
        var p := PlaneMesh.new()
        p.size = Vector2(w, h)
        return p

func _add_multimesh(mesh: Mesh, mat: Material, transforms: Array, name := "MultiMesh") -> MultiMeshInstance3D:
        if transforms.is_empty():
                return null
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.mesh = mesh
        mm.instance_count = transforms.size()
        for i in transforms.size():
                mm.set_instance_transform(i, transforms[i])
        var mmi := MultiMeshInstance3D.new()
        mmi.name = name
        mmi.multimesh = mm
        mmi.material_override = mat
        add_child(mmi)
        return mmi

func _box_shape(body: StaticBody3D, sz: Vector3, pos: Vector3) -> void:
        var cs := CollisionShape3D.new()
        var sh := BoxShape3D.new()
        sh.size = sz
        cs.shape = sh
        cs.position = pos
        body.add_child(cs)

# ---------------- construction ----------------

func _build() -> void:
        var gw: float = Grid.grid_width(cols)
        var gl: float = Grid.grid_length(rows)
        var start_z: float = Grid.start_z()
        var fin_z: float = Grid.finish_z(rows)
        var mid_z: float = (start_z + fin_z) / 2.0

        var grid_edge_x := gw / 2.0 + 0.66
        var bleacher_w := 4.3
        var bleed_gap := 0.8
        var half_w := grid_edge_x + bleed_gap + bleacher_w + 0.55
        var z_near := start_z + 3.6
        var z_far := fin_z - 3.9
        var H := 7.3
        var room_len := z_near - z_far
        var mid_y := (z_near + z_far) / 2.0

        # --- collision shell ---
        var body := StaticBody3D.new()
        body.name = "ArenaCollision"
        add_child(body)
        _box_shape(body, Vector3(half_w * 2.0, 0.5, room_len), Vector3(0, -0.12, mid_y))
        _box_shape(body, Vector3(0.4, H, room_len + 0.8), Vector3(-half_w - 0.2, H / 2.0, mid_y))
        _box_shape(body, Vector3(0.4, H, room_len + 0.8), Vector3(half_w + 0.2, H / 2.0, mid_y))
        _box_shape(body, Vector3(half_w * 2.0 + 0.8, H, 0.4), Vector3(0, H / 2.0, z_near + 0.2))
        _box_shape(body, Vector3(half_w * 2.0 + 0.8, H, 0.4), Vector3(0, H / 2.0, z_far - 0.2))

        _build_floor(gw, gl, start_z, fin_z, half_w, mid_y, room_len)
        _build_walls(half_w, z_near, z_far, H, mid_y, room_len, grid_edge_x)
        _build_ceiling_trusses(gw, half_w, H, z_near, z_far)
        _build_audience(gw, start_z, fin_z, mid_y, grid_edge_x, bleed_gap, bleacher_w)
        _build_led_wall(gw, z_far, grid_edge_x)
        _build_stage(start_z, fin_z, gw)
        _build_cameras(gw, start_z, fin_z, grid_edge_x)
        _build_lights(mid_z, fin_z, grid_edge_x, H, start_z)

# ---------------- floor + grid pit ----------------

func _build_floor(gw: float, gl: float, start_z: float, fin_z: float, half_w: float, mid_y: float, room_len: float) -> void:
        # studio floor: photoscan rubber tiles at real-world scale (uv1_scale
        # 0.35 -> ~2.9 m texture period -> ~45 cm floor tiles, triplanar).
        # VLM pass 1: albedo lifted x1.45 so the rubber grain reads under the
        # dim studio rig (photoscan source stays pure; tint is reversible).
        var floor_mat := _pbr(TEX_RUBBER, TEX_RUBBER_N, null, Vector3(0.35, 0.35, 0.35), 1.0, 1.0, true, TEX_RUBBER_O)
        floor_mat.albedo_color = Color(1.45, 1.45, 1.5)
        floor_mat.normal_scale = 1.25  # seams read under grazing show light
        _add_mesh(_box(Vector3(half_w * 2.0 + 0.4, 0.26, room_len + 0.4)), floor_mat, Vector3(0, 0, mid_y))

        # recessed dark pit floor under the tile grid (visual depth)
        var pit_mat := _plain(Color(0.055, 0.06, 0.07), 0.9, 0.25)
        var edge_x := gw / 2.0 + 0.66
        var edge_z0 := 0.66
        var edge_z1 := -((rows - 1) * Grid.PITCH + 0.66)
        var pit_len := edge_z0 - edge_z1
        _add_mesh(_box(Vector3(edge_x * 2.0, 0.1, pit_len)), pit_mat,
                        Vector3(0, -0.03, (edge_z0 + edge_z1) / 2.0))

        # hazard curb around the grid (replaces the old neon frame)
        var hazard_mat := _pbr(TEX_HAZARD, null, null, Vector3(1, 1, 1), 0.1, 0.8, false)
        hazard_mat.uv1_scale = Vector3(6, 1, 1)
        hazard_mat.emission_enabled = true  # safety-stripe visibility in dim studio light
        hazard_mat.emission_texture = TEX_HAZARD
        hazard_mat.emission = Color(0.9, 0.7, 0.25)
        hazard_mat.emission_energy_multiplier = 0.5
        var curb_h := 0.14
        var curb_len_x := (cols - 1) * Grid.PITCH + 1.32
        var curb_len_z := (rows - 1) * Grid.PITCH + 1.32
        for s in [-1, 1]:
                _add_mesh(_box(Vector3(curb_len_x, curb_h, 0.3)), hazard_mat, Vector3(0, curb_h / 2.0, (edge_z0 if s > 0 else edge_z1) + s * 0.15))
                _add_mesh(_box(Vector3(0.3, curb_h, curb_len_z + 0.3)), hazard_mat, Vector3(s * (edge_x + 0.15), curb_h / 2.0, (edge_z0 + edge_z1) / 2.0))

        # subtle warm guide strip along both curbs (way-show feel, not neon)
        _trim_mat = _emissive(Color(1.0, 0.72, 0.35), 1.2)
        for s in [-1, 1]:
                _add_mesh(_box(Vector3(curb_len_x + 0.2, 0.03, 0.05)), _trim_mat, Vector3(0, curb_h + 0.02, (edge_z0 if s > 0 else edge_z1) + s * 0.38))
                _add_mesh(_box(Vector3(0.05, 0.03, curb_len_z + 0.6)), _trim_mat, Vector3(s * (edge_x + 0.38), curb_h + 0.02, (edge_z0 + edge_z1) / 2.0))

# ---------------- walls ----------------

func _build_walls(half_w: float, z_near: float, z_far: float, H: float, mid_y: float, room_len: float, grid_edge_x: float) -> void:
        # photoscan painted-steel wainscot (panels read ~1 m) + brushed concrete
        # upper walls (~1.5 m pour period) — ORM-driven, map-metalled materials.
        # VLM pass 1: both lifted so panel seams/pores read in studio light.
        var paint := _pbr(TEX_PAINT, TEX_PAINT_N, null, Vector3(0.28, 0.28, 0.28), 1.0, 1.0, true, TEX_PAINT_O)
        paint.albedo_color = Color(1.7, 1.72, 1.76)
        var concrete := _pbr(TEX_CONCRETE, TEX_CONCRETE_N, null, Vector3(0.65, 0.65, 0.65), 1.0, 1.0, true, TEX_CONCRETE_O)
        concrete.albedo_color = Color(1.7, 1.7, 1.73)
        concrete.normal_scale = 1.15  # pores/board-form shading read at distance

        # lower half: painted steel wainscot; upper half: concrete acoustics
        for wx in [-half_w, half_w]:
                _add_mesh(_box(Vector3(0.35, 2.6, room_len)), paint, Vector3(wx, 1.3, mid_y))
                _add_mesh(_box(Vector3(0.35, H - 2.6, room_len)), concrete, Vector3(wx, 2.6 + (H - 2.6) / 2.0, mid_y))
        for wz in [z_near, z_far]:
                _add_mesh(_box(Vector3(half_w * 2.0, 2.6, 0.35)), paint, Vector3(0, 1.3, wz - (0.18 if wz == z_near else -0.18)))
                _add_mesh(_box(Vector3(half_w * 2.0, H - 2.6, 0.35)), concrete, Vector3(0, 2.6 + (H - 2.6) / 2.0, wz - (0.18 if wz == z_near else -0.18)))

        # wall ribs (MultiMesh): pilasters on the near wall + side walls
        var rib_tf: Array = []
        var step := 2.6
        var x := -half_w + step
        while x < half_w - 0.1:
                rib_tf.append(Transform3D(Basis(), Vector3(x, H / 2.0 + 0.1, z_near - 0.18)))
                x += step
        var z := z_near - step
        var rot_y := Basis(Vector3.UP, PI / 2.0)  # rotate the rib profile onto side walls
        while z > z_far + 0.1:
                rib_tf.append(Transform3D(rot_y, Vector3(-half_w + 0.18, H / 2.0 + 0.1, z)))
                rib_tf.append(Transform3D(rot_y, Vector3(half_w - 0.18, H / 2.0 + 0.1, z)))
                z -= step
        _add_multimesh(_box(Vector3(0.16, H, 0.16)), paint, rib_tf, "WallRibs")

        # vertical warm LED accent columns on side walls (theatrical, dim)
        var led_col_tf: Array = []
        z = z_near - 1.9
        while z > z_far + 1.2:
                for s in [-1, 1]:
                        led_col_tf.append(Transform3D(Basis(), Vector3(s * (half_w - 0.35), 3.0, z)))
                z -= 3.8
        _add_multimesh(_box(Vector3(0.07, 4.4, 0.07)), _emissive(Color(1.0, 0.62, 0.3), 0.55), led_col_tf, "LEDColumns")

        # near-wall entry drapes for depth (behind the camera start area).
        # VLM pass 1: deep stage red rather than showroom bright.
        var curtain := _pbr(TEX_CURTAIN, TEX_CURTAIN_N, null, Vector3(1.2, 1.2, 1.2), 1.0, 1.0, true, TEX_CURTAIN_O)
        curtain.albedo_color = Color(0.8, 0.68, 0.68)
        _add_mesh(_box(Vector3(half_w * 2.0 - 1.0, 4.6, 0.22)), curtain, Vector3(0, 3.2, z_near - 0.32))

# ---------------- ceiling + trusses + fixtures ----------------

func _build_ceiling_trusses(gw: float, half_w: float, H: float, z_near: float, z_far: float) -> void:
        # dark ceiling
        var ceil_mat := _plain(Color(0.03, 0.035, 0.045), 0.95)
        var room_len := z_near - z_far
        _add_mesh(_box(Vector3(half_w * 2.0 + 0.4, 0.3, room_len + 0.4)), ceil_mat, Vector3(0, H + 0.15, (z_near + z_far) / 2.0))

        # 3 trusses spanning X; members as one MultiMesh (rails + diagonals)
        var steel := _pbr(TEX_STEEL, TEX_STEEL_N, TEX_STEEL_R, Vector3(1.2, 1.2, 1.2), 0.85)
        var truss_count := 3
        var truss_y := H - 0.85
        var truss_span := (half_w - 0.3) * 2.0
        var n_seg := 12
        var seg_len := truss_span / float(n_seg)
        var diag_tf: Array = []
        var rail_tf: Array = []
        var fixture_tf: Array = []
        var lens_tf: Array = []
        for ti in truss_count:
                var tz: float = z_near - 1.6 - ti * ((z_near - z_far) - 3.2) / float(truss_count - 1)
                # top + bottom rail pairs (3 thin rails per level for a truss look)
                for ry in [truss_y, truss_y - 0.45]:
                        for dz in [-0.34, 0.0, 0.34]:
                                rail_tf.append(Transform3D(Basis(), Vector3(0, ry, tz + dz)))
                # diagonal zigzag members
                for si in n_seg:
                        var x0 := -truss_span / 2.0 + si * seg_len
                        var from := Vector3(x0, truss_y - 0.45, tz)
                        var to := Vector3(x0 + seg_len, truss_y, tz)
                        var dir := (to - from).normalized()
                        var mid := (from + to) / 2.0
                        # z-aligned box along the member direction
                        var b := Basis.looking_at(dir, Vector3(0, 0, 1))
                        diag_tf.append(Transform3D(b, mid))
                # hanging spotlight fixtures (vertical cans + warm lenses)
                var fix_n := 4 if quality >= 1 else 2
                for fi in fix_n:
                        var fx: float = -truss_span * 0.3 + fi * (truss_span * 0.6 / float(maxi(1, fix_n - 1)))
                        var fy := truss_y - 0.72
                        fixture_tf.append(Transform3D(Basis(), Vector3(fx, fy, tz)))
                        lens_tf.append(Transform3D(Basis(), Vector3(fx, fy - 0.16, tz)))
        _add_multimesh(_box(Vector3(0.07, 0.07, seg_len + 0.08)), steel, diag_tf, "TrussDiagonals")
        _add_multimesh(_box(Vector3(truss_span, 0.13, 0.13)), steel, rail_tf, "TrussRails")
        if quality >= 1:
                # truss spill: dim warm points at truss height so the steel
                # structure reads against the dark ceiling (fixture leakage)
                for ti in truss_count:
                        var spill := OmniLight3D.new()
                        spill.name = "TrussSpill%d" % ti
                        spill.light_color = Color(1.0, 0.85, 0.65)
                        spill.light_energy = 0.3
                        spill.omni_range = 7.0
                        var tz: float = z_near - 1.6 - ti * ((z_near - z_far) - 3.2) / float(truss_count - 1)
                        spill.position = Vector3(0, truss_y + 0.3, tz)
                        add_child(spill)

        # fixture bodies (dark cans) + warm lenses — belong here where the
        # fixture_tf / lens_tf arrays live
        _add_multimesh(_cyl(0.1, 0.26), _plain(Color(0.05, 0.05, 0.06), 0.5, 0.4), fixture_tf, "SpotFixtures")
        _add_multimesh(_cyl(0.085, 0.05), _emissive(Color(1.0, 0.9, 0.75), 2.2), lens_tf, "SpotLenses")

# ---------------- audience bleachers ----------------

func _build_audience(gw: float, start_z: float, fin_z: float, mid_y: float, grid_edge_x: float, bleed_gap: float, bleacher_w: float) -> void:
        var steel := _pbr(TEX_PAINT, TEX_PAINT_N, null, Vector3(0.4, 0.4, 0.4), 1.0, 1.0, true, TEX_PAINT_O)
        steel.albedo_color = Color(1.3, 1.32, 1.36)
        var rubber := _pbr(TEX_RUBBER, TEX_RUBBER_N, null, Vector3(0.4, 0.4, 0.4), 1.0, 1.0, true, TEX_RUBBER_O)
        rubber.albedo_color = Color(1.45, 1.45, 1.5)
        var crowd_mat := StandardMaterial3D.new()
        crowd_mat.albedo_texture = TEX_CROWD
        crowd_mat.roughness = 0.85
        crowd_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # billboard faces the grid
        crowd_mat.emission_enabled = true  # faint self-light so silhouettes read in dim seats
        crowd_mat.emission_texture = TEX_CROWD
        crowd_mat.emission = Color(0.4, 0.38, 0.36)
        crowd_mat.emission_energy_multiplier = 0.45

        var bank_len := (start_z - fin_z) * 0.8
        var step_tf: Array = []
        for side in [-1, 1]:
                # 4 stepped bleacher rows per bank, ascending away from the grid
                for r_idx in 4:
                        var h := 0.42 + r_idx * 0.44
                        var depth := 0.92
                        var x_off: float = side * (grid_edge_x + bleed_gap + 0.6 + r_idx * depth)
                        step_tf.append(Transform3D(Basis(), Vector3(x_off, h / 2.0, mid_y)))
        var steps_mm := MultiMesh.new()
        steps_mm.transform_format = MultiMesh.TRANSFORM_3D
        steps_mm.mesh = _box(Vector3(0.92, 0.42, bank_len))
        steps_mm.instance_count = step_tf.size()
        for idx in step_tf.size():
                steps_mm.set_instance_transform(idx, step_tf[idx])
        var steps := MultiMeshInstance3D.new()
        steps.name = "BleacherSteps"
        steps.multimesh = steps_mm
        steps.material_override = rubber
        add_child(steps)

        for side in [-1, 1]:
                var bank := Node3D.new()
                bank.name = "CrowdBank%d" % side
                add_child(bank)
                bank.position = Vector3(side * (grid_edge_x + bleed_gap + 1.4), 1.68, mid_y)
                var crowd := MeshInstance3D.new()
                crowd.name = "CrowdPlane"
                crowd.mesh = _plane(bank_len, 2.35)
                crowd.material_override = crowd_mat
                # face the grid: plane normal (+Z) rotated toward the arena center
                crowd.rotation = Vector3(0, -side * PI / 2.0, deg_to_rad(10))
                bank.add_child(crowd)
                _crowd_banks.append(bank)
                # steel barrier between audience and stage floor
                var bar := _box(Vector3(0.12, 1.05, bank_len))
                var barrier := MeshInstance3D.new()
                barrier.mesh = bar
                barrier.material_override = steel
                barrier.position = Vector3(side * (grid_edge_x + bleed_gap + 0.1), 0.52, mid_y)
                add_child(barrier)

# ---------------- LED show wall (behind finish) ----------------

func _build_led_wall(gw: float, z_far: float, grid_edge_x: float) -> void:
        var wall_w := maxf(9.0, gw + 2.6)
        var wall_h := 3.4
        var wall_y := 2.9
        var wz := z_far - 1.55

        # backboard
        var steel := _pbr(TEX_PAINT, TEX_PAINT_N, null, Vector3(0.3, 0.3, 0.3), 1.0, 1.0, true, TEX_PAINT_O)
        steel.albedo_color = Color(1.3, 1.32, 1.36)
        _add_mesh(_box(Vector3(wall_w + 0.6, wall_h + 0.5, 0.3)), steel, Vector3(0, wall_y, wz - 0.2))

        # screen: emissive LED content
        _led_mat = _emissive(Color(1, 1, 1), 1.55, TEX_LED)
        _led_mat.uv1_scale = Vector3(2, 1, 1)
        var screen := _add_mesh(_plane(wall_w, wall_h), _led_mat, Vector3(0, wall_y, wz), Vector3(0, 180, 0))
        screen.name = "LEDWall"

        # panel grid overlay (thin dark mullions) — vertical + horizontal bars
        var vt: Array = []
        var ht: Array = []
        var cols_n := 7
        var rows_n := 3
        for ci in cols_n + 1:
                var mx: float = -wall_w / 2.0 + ci * (wall_w / float(cols_n))
                vt.append(Transform3D(Basis(), Vector3(mx, wall_y, wz + 0.06)))
        for ri in rows_n + 1:
                var my: float = wall_y - wall_h / 2.0 + ri * (wall_h / float(rows_n))
                ht.append(Transform3D(Basis(), Vector3(0, my, wz + 0.06)))
        _add_multimesh(_box(Vector3(0.09, wall_h, 0.06)), _plain(Color(0.03, 0.03, 0.04), 0.6, 0.3), vt, "LEDVBars")
        _add_multimesh(_box(Vector3(wall_w + 0.1, 0.09, 0.06)), _plain(Color(0.03, 0.03, 0.04), 0.6, 0.3), ht, "LEDHBars")

        # warm trim frame around the LED wall
        var trim := _emissive(Color(1.0, 0.72, 0.35), 1.5)
        _add_mesh(_box(Vector3(wall_w + 0.7, 0.08, 0.1)), trim, Vector3(0, wall_y + wall_h / 2.0 + 0.28, wz))
        _add_mesh(_box(Vector3(wall_w + 0.7, 0.08, 0.1)), trim, Vector3(0, wall_y - wall_h / 2.0 - 0.28, wz))
        for s in [-1, 1]:
                _add_mesh(_box(Vector3(0.1, wall_h + 0.6, 0.1)), trim, Vector3(s * (wall_w / 2.0 + 0.33), wall_y, wz))

        # side LED towers framing the wall corners (classic show set)
        for s in [-1, 1]:
                var tower := _add_mesh(_box(Vector3(0.5, 5.2, 0.5)), steel, Vector3(s * (wall_w / 2.0 + 1.35), 2.6, wz - 0.1))
                _add_mesh(_box(Vector3(0.08, 4.4, 0.08)), _emissive(Color(1.0, 0.62, 0.3), 1.4), Vector3(s * (wall_w / 2.0 + 1.35) - s * 0.29, 2.7, wz + 0.2))

# ---------------- start / finish stage ----------------

func _build_stage(start_z: float, fin_z: float, gw: float) -> void:
        # START/FINISH platforms: photoscan diamond-tread deck steel (real
        # construction-stage look at foot level); handrails keep the brushed
        # synthetic weave. VLM pass 1: scale 2.0 -> ~4-6 cm diamonds (real
        # industrial tread pitch instead of oversized bumps).
        var tread := _pbr(TEX_TREAD, TEX_TREAD_N, null, Vector3(2.0, 2.0, 2.0), 1.0, 1.0, true, TEX_TREAD_O)
        tread.albedo_color = Color(1.25, 1.25, 1.28)
        var steel := _pbr(TEX_STEEL, TEX_STEEL_N, TEX_STEEL_R, Vector3(1.5, 1.5, 1.5), 0.85)
        var pad_s := StandardMaterial3D.new()
        pad_s.albedo_texture = TEX_PAD_START
        pad_s.emission_enabled = true
        pad_s.emission_texture = TEX_PAD_START
        pad_s.emission = Color(0.3, 1.0, 0.55)
        pad_s.emission_energy_multiplier = 0.55
        pad_s.roughness = 0.5
        _add_mesh(_box(Vector3(gw - 0.15, 0.16, 1.7)), tread, Vector3(0, 0.07, start_z))
        _add_mesh(_box(Vector3(gw - 0.25, 0.03, 1.55)), pad_s, Vector3(0, 0.165, start_z))
        var strip_s := _emissive(Color(0.27, 0.97, 0.51), 1.1)
        for s in [-1, 1]:
                _add_mesh(_box(Vector3(0.06, 0.04, 1.66)), strip_s, Vector3(s * (gw - 0.08) / 2.0, 0.17, start_z))
                # short entry handrails
                _add_mesh(_cyl(0.03, 0.9), steel, Vector3(s * (gw - 0.1) / 2.0, 0.62, start_z - 0.62))

        # FINISH platform + portal gate
        var pad_f := StandardMaterial3D.new()
        pad_f.albedo_texture = TEX_PAD_FINISH
        pad_f.emission_enabled = true
        pad_f.emission_texture = TEX_PAD_FINISH
        pad_f.emission = Color(1.0, 0.8, 0.3)
        pad_f.emission_energy_multiplier = 0.6
        pad_f.roughness = 0.5
        _add_mesh(_box(Vector3(gw - 0.15, 0.16, 1.7)), tread, Vector3(0, 0.07, fin_z))
        _add_mesh(_box(Vector3(gw - 0.25, 0.03, 1.55)), pad_f, Vector3(0, 0.165, fin_z))
        var strip_f := _emissive(Color(1.0, 0.78, 0.32), 1.25)
        for s in [-1, 1]:
                _add_mesh(_box(Vector3(0.06, 0.04, 1.66)), strip_f, Vector3(s * (gw - 0.08) / 2.0, 0.17, fin_z))
        # portal: two pillars + header beam + warm uplight strips
        var pillar := _pbr(TEX_STEEL, TEX_STEEL_N, TEX_STEEL_R, Vector3(0.8, 2, 0.8), 0.85)
        var portal_glow := _emissive(Color(1.0, 0.85, 0.55), 1.7)
        for s in [-1, 1]:
                var px: float = s * (gw / 2.0 + 0.9)
                _add_mesh(_box(Vector3(0.28, 3.3, 0.28)), pillar, Vector3(px, 1.65 + 0.16, fin_z - 0.85))
                _add_mesh(_box(Vector3(0.06, 2.9, 0.06)), portal_glow, Vector3(px - s * 0.19, 1.75, fin_z - 0.85))
        _add_mesh(_box(Vector3(gw + 2.2, 0.3, 0.3)), pillar, Vector3(0, 3.55, fin_z - 0.85))
        _add_mesh(_box(Vector3(gw + 1.6, 0.07, 0.07)), portal_glow, Vector3(0, 3.38, fin_z - 0.68))

# ---------------- broadcast camera props ----------------

func _build_cameras(gw: float, start_z: float, fin_z: float, grid_edge_x: float) -> void:
        # two manned broadcast cameras on tripods flanking the stage floor
        var steel := _pbr(TEX_STEEL, TEX_STEEL_N, TEX_STEEL_R, Vector3(0.6, 0.6, 0.6), 0.85)
        var dark := _plain(Color(0.045, 0.048, 0.055), 0.5, 0.2)
        var glass := _emissive(Color(0.5, 0.62, 0.75), 0.35)
        for s in [-1, 1]:
                var base := Vector3(s * (grid_edge_x + 2.35), 0.0, start_z - 1.1)
                # tripod: 3 legs + column
                var leg := _cyl(0.025, 1.05)
                for li in 3:
                        var ang := li * TAU / 3.0 + (0.4 if s > 0 else 1.2)
                        var lx := cos(ang) * 0.28
                        var lz := sin(ang) * 0.28
                        var mi := MeshInstance3D.new()
                        mi.mesh = leg
                        mi.material_override = dark
                        mi.position = base + Vector3(lx, 0.5, lz)
                        mi.rotation_degrees = Vector3(-lx * 28.0, 0, lz * 28.0)
                        add_child(mi)
                var col := MeshInstance3D.new()
                col.mesh = _cyl(0.035, 0.5)
                col.material_override = dark
                col.position = base + Vector3(0, 1.3, 0)
                add_child(col)
                # body + lens + tally light, aimed at the grid
                var aim := Vector3(-s * (grid_edge_x + 2.0), 0.6, fin_z + 1.0)
                var cam_head := Node3D.new()
                cam_head.position = base + Vector3(0, 1.62, 0)
                add_child(cam_head)
                cam_head.look_at(aim, Vector3.UP)
                var body := MeshInstance3D.new()
                body.mesh = _box(Vector3(0.24, 0.2, 0.5))
                body.material_override = dark
                body.position = Vector3(0, 0, 0.1)
                cam_head.add_child(body)
                var lens_m := MeshInstance3D.new()
                lens_m.mesh = _cyl(0.075, 0.24)
                lens_m.material_override = steel
                lens_m.rotation_degrees = Vector3(90, 0, 0)
                lens_m.position = Vector3(0, 0, -0.28)
                cam_head.add_child(lens_m)
                var tally := MeshInstance3D.new()
                tally.mesh = _box(Vector3(0.05, 0.03, 0.05))
                tally.material_override = _emissive(Color(1.0, 0.12, 0.1), 2.4)
                tally.position = Vector3(0, 0.12, -0.12)
                cam_head.add_child(tally)

# ---------------- stage lights (real lights; env stays in graphics.gd) ----------------

func _build_lights(mid_z: float, fin_z: float, grid_edge_x: float, H: float, start_z: float) -> void:
        # Key: warm show spot over the grid, the ONE shadow-caster (MED+)
        var key := SpotLight3D.new()
        key.name = "KeyLight"
        key.light_color = Color(1.0, 0.95, 0.86)
        key.light_energy = 3.1
        key.spot_range = 17.0
        key.spot_angle = 40.0
        key.spot_attenuation = 1.1
        key.shadow_enabled = quality >= 1
        key.light_volumetric_fog_energy = 1.6  # shafts must read (VLM final)
        key.position = Vector3(0, H - 1.3, mid_z + 0.5)
        key.look_at(Vector3(0, 0, mid_z - 1.5), Vector3.UP)
        add_child(key)

        if quality >= 1:
                # Rim: cool back light through the finish portal (no shadow)
                var rim := SpotLight3D.new()
                rim.name = "RimLight"
                rim.light_color = Color(0.72, 0.85, 1.0)
                rim.light_energy = 1.35
                rim.spot_range = 15.0
                rim.spot_angle = 34.0
                rim.position = Vector3(0, 4.6, fin_z - 1.2)
                rim.look_at(Vector3(0, 1.0, fin_z + 2.2), Vector3.UP)
                add_child(rim)

                # Start apron warm wash
                var apron := OmniLight3D.new()
                apron.name = "ApronLight"
                apron.light_color = Color(1.0, 0.82, 0.6)
                apron.light_energy = 0.75
                apron.omni_range = 6.5
                apron.light_volumetric_fog_energy = 1.2
                apron.position = Vector3(0, 3.4, start_z + 1.2)
                add_child(apron)

        if quality >= 1:
                # audience washes: one per bank (dim on MED, fuller on HIGH)
                for s in [-1, 1]:
                        var wash := OmniLight3D.new()
                        wash.name = "AudienceWash%d" % s
                        wash.light_color = Color(0.55, 0.42, 0.3)
                        wash.light_energy = 0.4 if quality < 2 else 0.55
                        wash.omni_range = 9.0
                        wash.position = Vector3(s * (grid_edge_x + 3.0), 3.2, mid_z)
                        add_child(wash)
                var ledglow := OmniLight3D.new()
                ledglow.name = "LEDWallGlow"
                ledglow.light_color = Color(1.0, 0.72, 0.35)
                ledglow.light_energy = 1.0
                ledglow.omni_range = 8.0
                ledglow.position = Vector3(0, 2.6, fin_z - 1.0)
                add_child(ledglow)

        # Floor pooling washes: dim warm practicals skimming the deck surface
        # so the rubber grain + tread read at gameplay camera distance (VLM
        # pass 2 fix — "light pooling" reads as a lit set, not a black void).
        # VLM pass 3: widened + spread along the walking surface (the whole
        # grid gets pooling, not just the start decks).
        if quality >= 1:
                var wash_z := [start_z - 2.2, start_z - 2.2 - (start_z - fin_z) * 0.5]
                for s in [-1, 1]:
                        for wz in wash_z:
                                var wash := OmniLight3D.new()
                                wash.name = "FloorWash%d_%d" % [s, int(wz)]
                                wash.light_color = Color(1.0, 0.9, 0.78)
                                wash.light_energy = 0.5
                                wash.omni_range = 8.5
                                wash.position = Vector3(s * (grid_edge_x - 0.4), 1.15, wz)
                                add_child(wash)
