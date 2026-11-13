# Graphics — environment + quality pipeline (static helpers).
# v2 (graphics overhaul): balanced TV-studio lighting — dim directional fill
# (the arena owns the dramatic key/rim/wash spots), warm ambient, light haze,
# controlled glow, filmic tonemapping. Three profiles preserved: LOW / MEDIUM / HIGH.
#   LOW:    no shadows, no glow, no fog, 70% render scale, FXAA
#   MEDIUM: key shadow + glow + haze, 85% scale, MSAA 2x
#   HIGH:   + brighter glow, finer shadow, 100% scale, MSAA 4x
extends Object

const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]

static func build_environment(parent: Node, quality: int) -> void:
        var we := WorldEnvironment.new()
        var env := Environment.new()
        env.background_mode = Environment.BG_COLOR
        # deep warm studio darkness (not pure black — stage haze reads depth)
        env.background_color = Color(0.03, 0.028, 0.036)
        env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color = Color(0.2, 0.185, 0.17)
        env.ambient_light_energy = 1.0 if quality >= 1 else 0.7
        env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
        env.tonemap_exposure = 1.0 if quality >= 1 else 1.08
        # faint atmospheric haze — sells the light beams on MED/HIGH
        env.fog_enabled = quality >= 1
        env.fog_density = 0.0045 if quality >= 2 else 0.006
        env.fog_light_color = Color(0.055, 0.05, 0.06)
        env.glow_enabled = quality >= 1
        env.glow_intensity = 0.5 if quality >= 2 else 0.35
        env.glow_strength = 1.0
        env.glow_bloom = 0.04 if quality >= 2 else 0.02
        env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
        # subtle vignette frames the "broadcast" look on capable devices
        env.adjustment_enabled = quality >= 2
        env.adjustment_contrast = 1.04
        env.adjustment_saturation = 1.05
        we.environment = env
        parent.add_child(we)

        # soft studio fill (the show lighting lives in the arena's spot rig)
        var fill := DirectionalLight3D.new()
        fill.name = "StudioFill"
        fill.rotation_degrees = Vector3(-58, 24, 0)
        fill.light_color = Color(0.9, 0.93, 1.0)
        fill.light_energy = 0.32 if quality >= 1 else 0.24
        fill.shadow_enabled = false  # shadows come from the arena key spot only
        parent.add_child(fill)

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
