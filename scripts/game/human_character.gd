# HumanCharacter — rigged human player character (CC0 Quaternius male,
# 11 animations, 31 joints, 1.8 m) driven through an AnimationTree state
# machine. Drop-in replacement for the procedural robot (robot_model.gd):
# the PUBLIC API IS IDENTICAL (set_moving / set_air / play_victory /
# play_zap / bounce), so player.gd and main_menu.gd needed no logic changes.
#
# States:
#   GROUND  = BlendSpace1D: Idle -- Walk -- Run blended by speed01
#   AIR     = Man_Jump (arc + landing clip)
#   VICTORY = Man_Clapping (looped)
#   ZAP     = Man_Death (one-shot collapse = electrocution reaction)
extends Node3D

const HUMAN_SCENE := preload("res://assets/characters/human/human_male.glb")

# The GLB's face points +Z (verified visually: front-on camera render). The
# player controller aims with atan2(v.x, v.z) + PI (the old robot's contract,
# whose front was -Z), so FACING_OFFSET = -PI converts it to "face = velocity"
# for this +Z-facing model. Verified in renders: walking shows his back to the
# chase camera, never a moonwalk.
const FACING_OFFSET := -PI

enum S { GROUND, AIR, VICTORY, ZAP }

var state := S.GROUND
var speed01 := 0.0
var menu_attract := false   # attract mode: occasionally claps

var _tree: AnimationTree
var _sm_playback: AnimationNodeStateMachinePlayback
var _t := 0.0
var _attract_t := 0.0
var _step_t := 0.0
var _model_root: Node3D

func _ready() -> void:
        _build()
        travel("GROUND")

# ---------------- construction ----------------

func _build() -> void:
        _model_root = HUMAN_SCENE.instantiate()
        add_child(_model_root)
        _upgrade_materials(_model_root)

        var ap: AnimationPlayer = _find_class(_model_root, "AnimationPlayer")
        # loop the locomotion + celebration clips (glTF import marks clips
        # one-shot by default; loops are a gameplay convention, not data)
        for clip in ["Man_Idle", "Man_Walk", "Man_Run", "Man_Standing", "Man_Clapping"]:
                if ap.has_animation(clip):
                        var a: Animation = ap.get_animation(clip)
                        a.loop_mode = Animation.LOOP_LINEAR

        _tree = AnimationTree.new()
        add_child(_tree)  # must be IN the tree before resolving the player path
        _tree.anim_player = _tree.get_path_to(ap)

        # ---- GROUND: speed-blended locomotion (Idle -> Walk -> Run) ----
        var bs := AnimationNodeBlendSpace1D.new()
        bs.min_space = 0.0
        bs.max_space = 1.0
        bs.add_blend_point(_anim_node("Man_Idle"), 0.0)
        bs.add_blend_point(_anim_node("Man_Walk"), 0.55)
        bs.add_blend_point(_anim_node("Man_Run"), 1.0)

        # ---- state machine ----
        var sm := AnimationNodeStateMachine.new()
        sm.add_node("GROUND", bs, Vector2(400, 200))
        sm.add_node("AIR", _anim_node("Man_Jump"), Vector2(700, 80))
        sm.add_node("VICTORY", _anim_node("Man_Clapping"), Vector2(100, 80))
        sm.add_node("ZAP", _anim_node("Man_Death"), Vector2(400, -60))

        sm.add_transition("GROUND", "AIR", _xfade(0.08))
        sm.add_transition("AIR", "GROUND", _xfade(0.18))
        sm.add_transition("GROUND", "VICTORY", _xfade(0.22))
        sm.add_transition("AIR", "VICTORY", _xfade(0.12))
        sm.add_transition("GROUND", "ZAP", _xfade(0.05))
        sm.add_transition("AIR", "ZAP", _xfade(0.05))
        sm.add_transition("VICTORY", "ZAP", _xfade(0.05))
        sm.add_transition("VICTORY", "GROUND", _xfade(0.3))

        _tree.tree_root = sm
        _tree.active = true
        _sm_playback = _tree.get("parameters/playback")

func _anim_node(clip: String) -> AnimationNodeAnimation:
        var n := AnimationNodeAnimation.new()
        n.animation = clip
        return n

func _xfade(t: float) -> AnimationNodeStateMachineTransition:
        var tr := AnimationNodeStateMachineTransition.new()
        tr.xfade_time = t
        # IMMEDIATE: all transitions are code-driven via travel(); AT_END would
        # stall on looping clips (idle/walk never "end").
        tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
        return tr

func _find_class(n: Node, cls: String) -> Node:
        if n.get_class() == cls:
                return n
        for c in n.get_children():
                var r := _find_class(c, cls)
                if r != null:
                        return r
        return null

# v3 photorealism: per-instance material upgrades (duplicated, never mutated
# in the shared GLB resource). Subsurface scattering only takes effect on the
# Forward+ renderer; on the Compatibility fallback the property is ignored.
func _upgrade_materials(n: Node) -> void:
        if n is MeshInstance3D:
                var mi: MeshInstance3D = n
                for i in mi.get_surface_override_material_count():
                        var mat = mi.get_active_material(i)
                        if mat is StandardMaterial3D:
                                var sm: StandardMaterial3D = mat
                                var tex_name := ""
                                if sm.albedo_texture != null:
                                        tex_name = sm.albedo_texture.resource_path.get_file()
                                var dup: StandardMaterial3D = sm.duplicate()
                                if tex_name.find("Skin") >= 0:
                                        dup.subsurf_scatter_strength = 0.45
                                        dup.roughness = 0.48
                                elif tex_name.find("Hair") >= 0:
                                        dup.subsurf_scatter_strength = 0.15
                                        dup.roughness = 0.55
                                mi.set_surface_override_material(i, dup)
        for c in n.get_children():
                _upgrade_materials(c)

# ---------------- public control (API contract of the old robot) ----------------

func set_moving(mag: float) -> void:
        speed01 = clampf(mag, 0.0, 1.0)
        if state == S.VICTORY or state == S.ZAP:
                return
        if state == S.GROUND:
                _tree.set("parameters/GROUND/blend_position", speed01)

func set_air(on: bool) -> void:
        if state == S.VICTORY or state == S.ZAP:
                return
        if on and state != S.AIR:
                state = S.AIR
                travel("AIR")
        elif not on and state == S.AIR:
                state = S.GROUND
                travel("GROUND")

func play_victory() -> void:
        state = S.VICTORY
        travel("VICTORY")

func play_zap() -> void:
        state = S.ZAP
        travel("ZAP")

func bounce() -> void:
        # landing squash — same feel feedback the robot had
        var tw := create_tween()
        _model_root.scale = Vector3(1.04, 0.86, 1.04)
        tw.tween_property(_model_root, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func face_yaw(vel: Vector3) -> float:
        return atan2(vel.x, vel.z) + PI + FACING_OFFSET

# ---------------- per-frame ----------------

func _process(delta: float) -> void:
        _t += delta
        # footsteps while ground-moving (matches old robot feedback)
        if state == S.GROUND and speed01 > 0.25:
                _step_t -= delta * (2.4 + 3.6 * speed01)
                if _step_t <= 0.0:
                        _step_t = 1.0
                        AudioManager.play_sfx("step", 0.9 + randf() * 0.15, -8.0)
        # attract mode: idle <-> clapping cycle
        if menu_attract and state == S.GROUND:
                _attract_t += delta
                if _attract_t > 4.5:
                        _attract_t = -2.5  # clap for ~2.5s then settle back
                        play_victory_menu()

func play_victory_menu() -> void:
        state = S.VICTORY
        travel("VICTORY")

func end_menu_attract() -> void:
        if state == S.VICTORY:
                state = S.GROUND
                speed01 = 0.0
                _tree.set("parameters/GROUND/blend_position", 0.0)
                travel("GROUND")

func travel(to: String) -> void:
        if _sm_playback != null:
                _sm_playback.travel(to)
