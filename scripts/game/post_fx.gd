# PostFX — broadcast-camera post-processing between the 3D world and the UI.
#
# A full-rect ColorRect on a CanvasLayer below the UI (layer -1) running a
# screen-space canvas shader:
#   * subtle vignette (broadcast lens framing)
#   * radial chromatic aberration (lens dispersion, strongest at corners)
#   * animated fine film grain (sensor noise)
#
# Quality gating: LOW skips the layer entirely (weak/fallback devices keep
# every pixel of headroom). The rect's mouse filter is IGNORE — a full-screen
# rect that eats taps was the v1.0.1 touch bug; this can never happen again.
extends CanvasLayer

const SHADER := "
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.30;
uniform float aberration : hint_range(0.0, 0.01) = 0.0018;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.035;
uniform float grain_cells = 720.0;

float hash12(vec2 p) {
        vec3 p3 = fract(vec3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
        vec2 uv = SCREEN_UV;
        vec2 c = uv - 0.5;
        float r2 = dot(c, c);

        // chromatic aberration — radial, grows toward the corners
        vec2 ca = c * aberration * (0.35 + 6.0 * r2);
        vec3 col;
        col.r = texture(screen_tex, uv + ca).r;
        col.g = texture(screen_tex, uv).g;
        col.b = texture(screen_tex, uv - ca).b;

        // vignette — smooth, only the far corners darken
        col *= 1.0 - vignette_strength * smoothstep(0.08, 0.62, r2);

        // film grain — animated per-frame, fine cells, luminance-neutral
        float cell = hash12(floor(uv * grain_cells) + vec2(fract(TIME * 61.7) * 100.0));
        col += (cell - 0.5) * grain_amount;

        COLOR = vec4(col, 1.0);
}
"

func setup(quality: int) -> void:
        if quality < 1:
                return  # LOW: skip post entirely — headroom for weak devices
        layer = -1  # above the 3D world, below the UI (canvas layer 0)
        var rect := ColorRect.new()
        rect.name = "PostFX"
        rect.anchor_right = 1.0
        rect.anchor_bottom = 1.0
        rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat a tap
        var mat := ShaderMaterial.new()
        var sh := Shader.new()
        sh.code = SHADER
        mat.shader = sh
        if quality >= 2:
                mat.set_shader_parameter("vignette_strength", 0.32)
                mat.set_shader_parameter("aberration", 0.0020)
                mat.set_shader_parameter("grain_amount", 0.038)
        else:
                mat.set_shader_parameter("vignette_strength", 0.24)
                mat.set_shader_parameter("aberration", 0.0013)
                mat.set_shader_parameter("grain_amount", 0.026)
        rect.material = mat
        add_child(rect)
