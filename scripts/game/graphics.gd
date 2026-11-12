# Graphics — environment + quality pipeline (static helpers).
# Low: no shadows/glow, 70% 3D scale. Medium: shadows+glow, MSAA 2x. High: + spot accents, MSAA 4x.
extends Object

const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]

static func build_environment(parent: Node, quality: int) -> void:
        var we := WorldEnvironment.new()
        var env := Environment.new()
        env.background_mode = Environment.BG_COLOR
        env.background_color = Color(0.016, 0.031, 0.045)
        env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color = Color(0.07, 0.13, 0.155)
        env.ambient_light_energy = 1.0 if quality >= 1 else 0.6
        env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
        env.fog_enabled = true
        env.fog_density = 0.006 if quality >= 1 else 0.011
        env.fog_light_color = Color(0.03, 0.055, 0.07)
        env.glow_enabled = quality >= 1
        env.glow_intensity = 0.38
        env.glow_strength = 1.0
        env.glow_bloom = 0.03
        env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
        we.environment = env
        parent.add_child(we)

        var sun := DirectionalLight3D.new()
        sun.name = "Sun"
        sun.rotation_degrees = Vector3(-52, 28, 0)
        sun.light_color = Color(1.0, 0.97, 0.9)
        sun.light_energy = 0.95 if quality >= 1 else 0.85
        sun.shadow_enabled = quality >= 1
        parent.add_child(sun)

        if quality >= 2:
                var accent := SpotLight3D.new()
                accent.light_color = Color(0.4, 0.95, 0.85)
                accent.light_energy = 0.35
                accent.spot_range = 16.0
                accent.spot_angle = 55.0
                accent.shadow_enabled = false
                accent.position = Vector3(2.5, 4.6, -2.0)
                accent.rotation_degrees = Vector3(-70, 0, 0)
                parent.add_child(accent)

static func apply_viewport(vp: Viewport, quality: int) -> void:
        match quality:
                0:
                        vp.scaling_3d_scale = 0.7
                        vp.msaa_3d = Viewport.MSAA_DISABLED
                        vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
                1:
                        vp.scaling_3d_scale = 0.85
                        vp.msaa_3d = Viewport.MSAA_2X
                        vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
                _:
                        vp.scaling_3d_scale = 1.0
                        vp.msaa_3d = Viewport.MSAA_4X
                        vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
