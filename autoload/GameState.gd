# GameState — global autoload (extends Node)
# Owns: save data (stars / best times), settings, level loading, InputMap setup.
# Everything persists to user://save_data.json
extends Node

signal settings_changed

const SAVE_PATH := "user://save_data.json"
const LEVEL_COUNT := 50
const LEVEL_PATH := "res://data/levels/level_%03d.json"

# Test-mode flags (set via environment variables by CI / smoke tests)
var smoke := false
var touchtest := false  # ETC_TOUCHTEST=1 — simulated touch-input E2E test
var shot_mode := ""      # "", "menu", "game"
var shot_path := ""
var shot_level := 1

var settings := {
        "music": 0.7,
        "sfx": 0.8,
        "quality": 1,       # 0 = Low, 1 = Medium, 2 = High
        "sens": 1.0,        # camera sensitivity multiplier
        "haptics": true,
        "cam_mode": 0,      # 0 = smart follow, 1 = manual
}

var stars := {}        # "level_id" -> int (0..3)
var best := {}         # "level_id" -> float seconds

func _ready() -> void:
        randomize()
        _read_env()
        _setup_input_map()
        load_all()

func _read_env() -> void:
        smoke = OS.get_environment("ETC_SMOKE") == "1"
        touchtest = OS.get_environment("ETC_TOUCHTEST") == "1"
        shot_mode = OS.get_environment("ETC_SHOT")
        shot_path = OS.get_environment("ETC_SHOT_PATH")
        var sl := OS.get_environment("ETC_LEVEL")
        shot_level = int(sl) if sl != "" else 1

func _setup_input_map() -> void:
        _add_action("move_forward", [KEY_W, KEY_UP])
        _add_action("move_back", [KEY_S, KEY_DOWN])
        _add_action("move_left", [KEY_A, KEY_LEFT])
        _add_action("move_right", [KEY_D, KEY_RIGHT])
        _add_action("jump", [KEY_SPACE])

func _add_action(action_name: String, keys: Array) -> void:
        if InputMap.has_action(action_name):
                return
        InputMap.add_action(action_name, 0.2)
        for k in keys:
                var ev := InputEventKey.new()
                ev.physical_keycode = k
                InputMap.action_add_event(action_name, ev)

# ---------------- persistence ----------------

func load_all() -> void:
        if not FileAccess.file_exists(SAVE_PATH):
                return
        var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
        if not (raw is Dictionary):
                push_warning("Save file corrupt, starting fresh.")
                return
        var d: Dictionary = raw
        var s: Dictionary = d.get("settings", {})
        for key in s:
                if settings.has(key):
                        settings[key] = s[key]
        if d.has("stars"):
                stars = d["stars"]
        if d.has("best"):
                best = d["best"]

func save_all() -> void:
        var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
        if f == null:
                push_error("Cannot write save file.")
                return
        f.store_string(JSON.stringify({
                "v": 1,
                "settings": settings,
                "stars": stars,
                "best": best,
        }, "\t"))
        f.close()

func set_setting(key: String, value) -> void:
        settings[key] = value
        save_all()
        settings_changed.emit()

# ---------------- progression ----------------

func get_stars(level_id: int) -> int:
        return int(stars.get(str(level_id), 0))

func get_best(level_id: int) -> float:
        return float(best.get(str(level_id), 0.0))

func record_result(level_id: int, time_sec: float, stars_earned: int) -> void:
        var k := str(level_id)
        if stars_earned > int(stars.get(k, 0)):
                stars[k] = stars_earned
        var b := float(best.get(k, 0.0))
        if b <= 0.0 or time_sec < b:
                best[k] = round(time_sec * 10.0) / 10.0
        save_all()

func is_unlocked(level_id: int) -> bool:
        if level_id <= 1:
                return true
        return get_stars(level_id - 1) >= 1

func total_stars() -> int:
        var total := 0
        for v in stars.values():
                total += int(v)
        return total

func reset_progress() -> void:
        stars.clear()
        best.clear()
        save_all()
        settings_changed.emit()

# ---------------- level loading ----------------

func load_level(level_id: int) -> Dictionary:
        var path := LEVEL_PATH % level_id
        if not FileAccess.file_exists(path):
                push_error("Level file missing: " + path)
                return {}
        var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        if not (raw is Dictionary):
                push_error("Level file invalid JSON: " + path)
                return {}
        return raw

func mode_label(mode: String) -> String:
        match mode:
                "memory":
                        return "Memory Challenge"
                "timed":
                        return "Timed Challenge"
                "pattern":
                        return "Pattern Challenge"
                _:
                        return "Challenge"
