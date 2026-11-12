# Arena — procedurally builds the full indoor challenge arena:
# room shell (floor/walls/ceiling + collision), neon trims, corner columns,
# hazard border, glowing start/finish pads, light bars and signage.
# One shared emissive "trim" material pulses for cheap ambience.
extends Node3D

const Grid := preload("res://scripts/game/grid.gd")
const TEX_FLOOR := preload("res://assets/textures/floor_metal.png")
const TEX_WALL := preload("res://assets/textures/wall_panel.png")
const TEX_HAZARD := preload("res://assets/textures/hazard.png")
const TEX_PAD_START := preload("res://assets/textures/pad_start.png")
const TEX_PAD_FINISH := preload("res://assets/textures/pad_finish.png")

var cols := 6
var rows := 6
var quality := 1
var _trim_mat: StandardMaterial3D
var _t := 0.0

func setup(level: Dictionary, q: int) -> void:
        cols = int(level.get("cols", 6))
        rows = int(level.get("rows", 6))
        quality = q
        _trim_mat = _make_trim_mat()
        _build()

func _process(delta: float) -> void:
        _t += delta
        if _trim_mat != null:
                _trim_mat.emission_energy_multiplier = 1.05 + 0.35 * sin(_t * 2.4)

# ---------------- helpers ----------------

func _mat(tex: Texture2D, albedo: Color, uv_scale := Vector3(4, 4, 4), triplanar := true, metallic := 0.25, rough := 0.65) -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.albedo_color = albedo
        if tex != null:
                m.albedo_texture = tex
                if triplanar:
                        m.uv1_triplanar = true
                        m.uv1_scale = uv_scale
        m.metallic = metallic
        m.roughness = rough
        return m

func _make_trim_mat() -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.albedo_color = Color(0.05, 0.14, 0.13)
        m.emission_enabled = true
        m.emission = Color(0.16, 0.92, 0.8)
        m.emission_energy_multiplier = 1.2
        m.metallic = 0.4
        m.roughness = 0.4
        return m

func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.material_override = mat
        mi.position = pos
        add_child(mi)
        return mi

func _box(sz: Vector3) -> BoxMesh:
        var b := BoxMesh.new()
        b.size = sz
        return b

func _add_box_shape(body: StaticBody3D, sz: Vector3, pos: Vector3) -> void:
        var cs := CollisionShape3D.new()
        var sh := BoxShape3D.new()
        sh.size = sz
        cs.shape = sh
        cs.position = pos
        body.add_child(cs)

func _add_label(txt: String, pos: Vector3, font_sz := 64, col := Color(0.7, 0.95, 0.9), billboard := true) -> Label3D:
        var l := Label3D.new()
        l.text = txt
        l.font_size = font_sz
        l.modulate = col
        l.outline_size = 10
        l.outline_modulate = Color(0, 0, 0, 0.8)
        if billboard:
                l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        l.position = pos
        add_child(l)
        return l

# ---------------- construction ----------------

func _build() -> void:
        var gw: float = Grid.grid_width(cols)
        var start_z: float = Grid.start_z()
        var fin_z: float = Grid.finish_z(rows)
        var half_w := gw / 2.0 + 2.6
        var z_near := start_z + 2.2
        var z_far := fin_z - 2.2
        var room_len := z_near - z_far
        var H := 5.6
        var mid_z := (z_near + z_far) / 2.0

        # --- collision ---
        var body := StaticBody3D.new()
        body.name = "ArenaCollision"
        add_child(body)
        _add_box_shape(body, Vector3(half_w * 2.0, 0.5, room_len), Vector3(0, -0.12, mid_z))
        _add_box_shape(body, Vector3(0.4, H, room_len + 0.8), Vector3(-half_w - 0.2, H / 2.0, mid_z))
        _add_box_shape(body, Vector3(0.4, H, room_len + 0.8), Vector3(half_w + 0.2, H / 2.0, mid_z))
        _add_box_shape(body, Vector3(half_w * 2.0 + 0.8, H, 0.4), Vector3(0, H / 2.0, z_near + 0.2))
        _add_box_shape(body, Vector3(half_w * 2.0 + 0.8, H, 0.4), Vector3(0, H / 2.0, z_far - 0.2))

        # --- floor / ceiling / walls (visual) ---
        var floor_mat := _mat(TEX_FLOOR, Color(0.55, 0.62, 0.68), Vector3(6, 6, 6), true, 0.3, 0.6)
        _add_mesh(_box(Vector3(half_w * 2.0 + 0.4, 0.26, room_len + 0.4)), floor_mat, Vector3(0, 0, mid_z))

        var wall_mat := _mat(TEX_WALL, Color(0.6, 0.66, 0.72), Vector3(5, 2.2, 5), true, 0.35, 0.55)
        _add_mesh(_box(Vector3(0.35, H, room_len)), wall_mat, Vector3(-half_w - 0.175, H / 2.0, mid_z))
        _add_mesh(_box(Vector3(0.35, H, room_len)), wall_mat, Vector3(half_w + 0.175, H / 2.0, mid_z))
        _add_mesh(_box(Vector3(half_w * 2.0 + 0.35, H, 0.35)), wall_mat, Vector3(0, H / 2.0, z_near + 0.175))
        _add_mesh(_box(Vector3(half_w * 2.0 + 0.35, H, 0.35)), wall_mat, Vector3(0, H / 2.0, z_far - 0.175))

        var ceil_mat := _mat(null, Color(0.09, 0.11, 0.14), Vector3.ONE, false, 0.2, 0.85)
        _add_mesh(_box(Vector3(half_w * 2.0 + 0.4, 0.3, room_len + 0.4)), ceil_mat, Vector3(0, H + 0.15, mid_z))

        # --- ceiling light bars ---
        var light_mat := StandardMaterial3D.new()
        light_mat.albedo_color = Color(0.85, 0.92, 0.95)
        light_mat.emission_enabled = true
        light_mat.emission = Color(0.9, 0.98, 1.0)
        light_mat.emission_energy_multiplier = 1.5
        var bar_count := 3 if quality >= 1 else 1
        for i in bar_count:
                var z: float
                if bar_count > 1:
                        z = (start_z - 1.2) - i * ((start_z - fin_z) - 2.4) / float(bar_count - 1)
                else:
                        z = mid_z
                _add_mesh(_box(Vector3(gw * 0.8, 0.07, 0.34)), light_mat, Vector3(0, H - 0.28, z))

        # --- neon wall trims (base + top, shared pulsing material) ---
        for wx in [-half_w, half_w]:
                for wy in [0.32, H - 0.65]:
                        _add_mesh(_box(Vector3(0.07, 0.07, room_len - 0.3)), _trim_mat, Vector3(wx, wy, mid_z))
        for wz in [z_near, z_far]:
                for wy in [0.32, H - 0.65]:
                        _add_mesh(_box(Vector3(half_w * 2.0 - 0.3, 0.07, 0.07)), _trim_mat, Vector3(0, wy, wz))

        # --- wall ribs (single MultiMesh for both side walls) ---
        if quality >= 1:
                var rib_count := int(room_len / 2.4) * 2
                if rib_count > 0:
                        var mm := MultiMesh.new()
                        mm.transform_format = MultiMesh.TRANSFORM_3D
                        mm.mesh = _box(Vector3(0.09, H - 0.9, 0.09))
                        mm.instance_count = rib_count
                        var idx := 0
                        var per_wall := rib_count / 2
                        for side in [-1, 1]:
                                for i in per_wall:
                                        var z := z_near - 1.2 - i * (room_len - 2.4) / float(maxf(1, per_wall - 1))
                                        var t := Transform3D(Basis(), Vector3(side * (half_w - 0.09), (H - 0.9) / 2.0 + 0.45, z))
                                        mm.set_instance_transform(idx, t)
                                        idx += 1
                        var mmi := MultiMeshInstance3D.new()
                        mmi.multimesh = mm
                        var rib_mat := _mat(TEX_WALL, Color(0.42, 0.48, 0.55), Vector3(1, 2, 1), true, 0.4, 0.5)
                        mmi.material_override = rib_mat
                        add_child(mmi)

        # --- corner columns with emissive slits ---
        for sx in [-1, 1]:
                for sz in [-1, 1]:
                        var col_pos := Vector3(sx * (half_w - 0.3), H / 2.0, (z_near if sz > 0 else z_far) - sz * 0.3)
                        _add_mesh(_box(Vector3(0.55, H, 0.55)), _mat(TEX_WALL, Color(0.5, 0.56, 0.63), Vector3(1, 2, 1), true, 0.4, 0.5), col_pos)
                        var slit_pos := col_pos - Vector3(sx * 0.3, 0, sz * 0.3)
                        _add_mesh(_box(Vector3(0.08, H - 1.3, 0.08)), _trim_mat, slit_pos)

        # --- hazard + glow frames around the grid ---
        var edge_x := (cols - 1) / 2.0 * Grid.PITCH + 0.66
        var edge_z0 := 0.66
        var edge_z1 := -((rows - 1) * Grid.PITCH + 0.66)
        var hazard_mat := _mat(TEX_HAZARD, Color(0.8, 0.8, 0.8), Vector3(6, 1, 1), false, 0.1, 0.7)
        var frame_len_x := (cols - 1) * Grid.PITCH + 1.32
        var frame_len_z := (rows - 1) * Grid.PITCH + 1.32
        for s in [-1, 1]:
                _add_mesh(_box(Vector3(frame_len_x, 0.035, 0.16)), hazard_mat, Vector3(0, 0.125, (edge_z0 if s > 0 else edge_z1)))
                _add_mesh(_box(Vector3(0.16, 0.035, frame_len_z + 0.2)), hazard_mat, Vector3(s * edge_x, 0.125, (edge_z0 + edge_z1) / 2.0))
                _add_mesh(_box(Vector3(frame_len_x, 0.05, 0.05)), _trim_mat, Vector3(0, 0.185, (edge_z0 if s > 0 else edge_z1) + (0.13 if s > 0 else -0.13)))
                _add_mesh(_box(Vector3(0.05, 0.05, frame_len_z + 0.4)), _trim_mat, Vector3(s * edge_x + (0.13 if s > 0 else -0.13), 0.185, (edge_z0 + edge_z1) / 2.0))

        # --- start / finish pads ---
        var pad_start_mat := _mat(TEX_PAD_START, Color(0.9, 0.95, 0.92), Vector3(1, 1, 1), false, 0.2, 0.5)
        pad_start_mat.emission_enabled = true
        pad_start_mat.emission_texture = TEX_PAD_START
        pad_start_mat.emission = Color(0.25, 1.0, 0.55)
        pad_start_mat.emission_energy_multiplier = 0.75
        _add_mesh(_box(Vector3(gw - 0.15, 0.16, 1.7)), pad_start_mat, Vector3(0, 0.07, start_z))

        var pad_fin_mat := _mat(TEX_PAD_FINISH, Color(0.95, 0.9, 0.8), Vector3(1, 1, 1), false, 0.2, 0.5)
        pad_fin_mat.emission_enabled = true
        pad_fin_mat.emission_texture = TEX_PAD_FINISH
        pad_fin_mat.emission = Color(1.0, 0.8, 0.25)
        pad_fin_mat.emission_energy_multiplier = 0.85
        _add_mesh(_box(Vector3(gw - 0.15, 0.16, 1.7)), pad_fin_mat, Vector3(0, 0.07, fin_z))

        # finish light pillar
        var beam := StandardMaterial3D.new()
        beam.albedo_color = Color(0.2, 0.16, 0.05)
        beam.emission_enabled = true
        beam.emission = Color(1.0, 0.82, 0.3)
        beam.emission_energy_multiplier = 1.6
        _add_mesh(_box(Vector3(0.14, 2.4, 0.14)), beam, Vector3(0, 1.35, fin_z - 0.5))

        # --- signage ---
        _add_label("START", Vector3(0, 1.15, start_z), 72, Color(0.35, 1.0, 0.6))
        _add_label("FINISH", Vector3(0, 1.35, fin_z), 72, Color(1.0, 0.85, 0.4))
        _add_label("ELECTRIC TILE CHALLENGE", Vector3(0, 3.95, z_near - 0.55), 88, Color(0.16, 0.9, 0.8), false)
        if z_near - 0.55 < 1.0:
                pass  # spacing guard, far wall never overlaps start pad

        var far_label := _add_label("GOOD LUCK", Vector3(0, 4.35, z_far + 0.55), 96, Color(0.16, 0.9, 0.8), false)
        far_label.rotation.y = 0.0

func get_spawn() -> Vector3:
        return Grid.spawn_pos()

func get_finish_z() -> float:
        return Grid.finish_z(rows)
