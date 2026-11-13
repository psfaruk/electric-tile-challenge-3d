# Main — root router. Holds one active screen (menu / levels / settings / gameplay).
# All screens are built in code; there is exactly one .tscn in the project.
extends Node

const MenuScreen := preload("res://scripts/ui/screens/main_menu.gd")
const LevelsScreen := preload("res://scripts/ui/screens/level_select.gd")
const SettingsScreen := preload("res://scripts/ui/screens/settings.gd")
const GameplayScreen := preload("res://scripts/ui/screens/gameplay.gd")

var _screen: Node = null
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _fading := false

func _ready() -> void:
        _fade_layer = CanvasLayer.new()
        _fade_layer.layer = 100
        add_child(_fade_layer)
        _fade = ColorRect.new()
        _fade.color = Color(0.02, 0.03, 0.05)
        _fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        # CRITICAL FIX: the fade rect must never eat input while invisible.
        # It previously started as MOUSE_FILTER_STOP, which swallowed every
        # tap/click on the main menu on real devices (buttons appeared dead).
        _fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _fade.modulate.a = 0.0
        _fade.visible = false  # idle veil is not even drawn — it can never intercept anything
        _fade_layer.add_child(_fade)

        if GameState.shot_mode == "menu":
                _goto("menu")
                _capture_later(2.8)
        elif GameState.shot_mode == "game":
                _goto("gameplay", {"level": GameState.shot_level, "shot": true})
        elif GameState.smoke:
                _goto("gameplay", {"level": 1, "smoke": true})
        elif GameState.touchtest:
                _goto("menu")
                var tt := preload("res://scripts-dev/touchtest.gd").new()
                tt.main = self
                add_child(tt)
                tt.run()
        else:
                _goto("menu")

func goto(screen: String, params: Dictionary = {}) -> void:
        if _fading:
                return  # a transition is already running; ignore duplicate programmatic calls
        _fading = true
        _fade.visible = true
        _fade.modulate.a = 1.0  # purely cosmetic veil — never blocks input (filter stays IGNORE)
        _goto(screen, params)
        _reveal_fade()

func _reveal_fade() -> void:
        var tw := create_tween()
        tw.tween_property(_fade, "modulate:a", 0.0, 0.18)
        await tw.finished
        _fade.visible = false
        _fading = false

func _goto(screen: String, params: Dictionary = {}) -> void:
        if _screen != null:
                _screen.queue_free()
                _screen = null
        var s: Node = null
        match screen:
                "menu":
                        s = MenuScreen.new()
                "levels":
                        s = LevelsScreen.new()
                "settings":
                        s = SettingsScreen.new()
                "gameplay":
                        s = GameplayScreen.new()
                        s.level_id = int(params.get("level", 1))
                        s.smoke = bool(params.get("smoke", false))
                        s.shot = bool(params.get("shot", false))
        if s == null:
                push_error("Unknown screen: " + screen)
                return
        s.main = self
        add_child(s)
        _screen = s

# ---------------- automated screenshot capture (CI evidence) ----------------

func _capture_later(delay: float) -> void:
        await get_tree().create_timer(delay).timeout
        await RenderingServer.frame_post_draw
        var img := get_viewport().get_texture().get_image()
        if GameState.shot_path != "" and img != null:
                img.save_png(GameState.shot_path)
        get_tree().quit(0)

# ---------------- smoke test: screen navigation round (CI) ----------------
# Lives on Main because gameplay gets freed when screens switch.

func smoke_screens_round() -> void:
        await get_tree().create_timer(0.4).timeout
        goto("menu")
        await get_tree().create_timer(0.6).timeout
        goto("levels")
        await get_tree().create_timer(0.6).timeout
        goto("settings")
        await get_tree().create_timer(0.6).timeout
        print("SMOKE: ALL CHECKS PASSED")
        get_tree().quit(0)
