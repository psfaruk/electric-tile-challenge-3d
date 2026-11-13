# Graphics — environment + quality pipeline (static helpers).
# v3 (photorealism push, Forward+ renderer):
#   LOW:    no shadows/glow/fog/SSAO/SDFGI/SSR, 70% render scale, FXAA
#   MEDIUM: key shadow + glow + haze + SSAO + volumetric fog, 85%, MSAA 2x
#   HIGH:   + SDFGI real-time GI + SSR reflections on glass/steel + far DOF
#           + TAA + debanding, 100% scale
# Forward+-only features (SDFGI/SSAO/SSR/DOF/volumetric fog/TAA) are silently
# ignored by the Compatibility fallback renderer, so the game keeps running on
# non-Vulkan devices — verified by the 39/39 touch E2E under gl_compatibility.
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
        # VLM pass 1: lifted so photoscan albedo detail reads under the rig
        # (dim-studio mood is kept by the key/rim contrast, not by crushing black)
        env.ambient_light_energy = 1.3 if quality >= 1 else 0.85
        env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
        env.tonemap_exposure = 1.0 if quality >= 1 else 1.08

        # ---- SDFGI: real-time global illumination (HIGH, Forward+) ----
        if quality >= 2:
                env.sdfgi_enabled = true
                env.sdfgi_use_occlusion = true
                env.sdfgi_read_sky_light = false  # closed studio, no sky
                env.sdfgi_bounce_feedback = 0.7   # warm bounce off the floor

        # ---- SSAO: contact shadowing in the trusses/bleachers/under tiles ----
        if quality >= 1:
                env.ssao_enabled = true
                env.ssao_radius = 1.0
                env.ssao_intensity = 2.0
                env.ssao_power = 1.5
                env.ssao_detail = 0.5
                env.ssao_light_affect = 0.15

        # ---- SSR: real reflections on the smoked-glass tiles + steel decks ----
        if quality >= 2:
                env.ssr_enabled = true
                env.ssr_max_steps = 48
                env.ssr_fade_in = 0.15
                env.ssr_fade_out = 2.0

        # ---- distance haze + volumetric stage fog ----
        # faint atmospheric haze sells the light beams on MED/HIGH
        env.fog_enabled = quality >= 1
        env.fog_density = 0.0045 if quality >= 2 else 0.006
        env.fog_light_color = Color(0.055, 0.05, 0.06)
        if quality >= 1:
                # volumetric fog = visible light shafts from the key spot rig
                env.volumetric_fog_enabled = true
                env.volumetric_fog_density = 0.012 if quality >= 2 else 0.008
                env.volumetric_fog_albedo = Color(0.88, 0.82, 0.74)
                env.volumetric_fog_emission = Color(0.05, 0.045, 0.05)
                env.volumetric_fog_emission_energy = 0.06
                env.volumetric_fog_length = 48.0
                env.volumetric_fog_detail_spread = 0.6
                env.volumetric_fog_gi_inject = 0.6 if quality >= 2 else 0.0

        # ---- glow ----
        env.glow_enabled = quality >= 1
        env.glow_intensity = 0.55 if quality >= 2 else 0.4
        env.glow_strength = 1.0
        env.glow_bloom = 0.05 if quality >= 2 else 0.02
        env.glow_hdr_threshold = 1.0
        env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

        # ---- far DOF: softly defocus the audience/backdrop, never gameplay ----
        if quality >= 2:
                env.dof_blur_far_enabled = true
                env.dof_blur_far_distance = 16.0   # gameplay stays < 16 m
                env.dof_blur_far_transition = 6.0
                env.dof_blur_far_amount = 0.12

        # ---- broadcast color grade ----
        env.adjustment_enabled = quality >= 2
        env.adjustment_contrast = 1.05
        env.adjustment_saturation = 1.06

        we.environment = env
        parent.add_child(we)

        # soft studio fill (the show lighting lives in the arena's spot rig)
        var fill := DirectionalLight3D.new()
        fill.name = "StudioFill"
        fill.rotation_degrees = Vector3(-58, 24, 0)
        fill.light_color = Color(0.9, 0.93, 1.0)
        fill.light_energy = 0.38 if quality >= 1 else 0.28
        fill.shadow_enabled = false  # shadows come from the arena key spot only
        parent.add_child(fill)

static func apply_viewport(vp: Viewport, quality: int) -> void:
        match quality:
                0:
                        vp.scaling_3d_scale = 0.7
                        vp.msaa_3d = Viewport.MSAA_DISABLED
                        vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
                        vp.use_debanding = false
                        vp.use_taa = false
                1:
                        vp.scaling_3d_scale = 0.85
                        vp.msaa_3d = Viewport.MSAA_2X
                        vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
                        vp.use_debanding = true
                        vp.use_taa = false
                _:
                        # TAA over MSAA on HIGH: temporally stable, fine detail,
                        # works with glow/SSAO/SDFGI; slow-paced game = no ghosting
                        vp.scaling_3d_scale = 1.0
                        vp.msaa_3d = Viewport.MSAA_DISABLED
                        vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
                        vp.use_debanding = true
                        vp.use_taa = true
