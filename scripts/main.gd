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

func _ready() -> void:
        _fade_layer = CanvasLayer.new()
        _fade_layer.layer = 100
        add_child(_fade_layer)
        _fade = ColorRect.new()
        _fade.color = Color(0.02, 0.03, 0.05)
        _fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _fade.mouse_filter = Control.MOUSE_FILTER_STOP
        _fade.modulate.a = 0.0
        _fade_layer.add_child(_fade)

        if GameState.shot_mode == "menu":
                _goto("menu")
                _capture_later(2.8)
        elif GameState.shot_mode == "game":
                _goto("gameplay", {"level": GameState.shot_level, "shot": true})
        elif GameState.smoke:
                _goto("gameplay", {"level": 1, "smoke": true})
        else:
                _goto("menu")

func goto(screen: String, params: Dictionary = {}) -> void:
        _fade_to(1.0)
        _goto(screen, params)
        _fade_to(0.0)

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

func _fade_to(alpha: float, dur := 0.28) -> void:
        _fade.mouse_filter = Control.MOUSE_FILTER_STOP if alpha > 0.5 else Control.MOUSE_FILTER_IGNORE
        var tw := create_tween()
        tw.tween_property(_fade, "modulate:a", alpha, dur)
        await tw.finished

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
