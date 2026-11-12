# AudioManager — global autoload (extends Node)
# Builds Music/SFX audio buses at runtime, pools SFX players, crossfades music.
# All sounds are original, procedurally generated (scripts-dev/gen_audio.py).
extends Node

const SFX := {
        "click": "res://assets/audio/sfx/ui_click.wav",
        "back": "res://assets/audio/sfx/ui_back.wav",
        "step": "res://assets/audio/sfx/step.wav",
        "jump": "res://assets/audio/sfx/jump.wav",
        "land": "res://assets/audio/sfx/land.wav",
        "tile_show": "res://assets/audio/sfx/tile_show.wav",
        "tile_good": "res://assets/audio/sfx/tile_good.wav",
        "seq_note": "res://assets/audio/sfx/seq_note.wav",
        "zap": "res://assets/audio/sfx/zap.wav",
        "fail": "res://assets/audio/sfx/fail.wav",
        "warn": "res://assets/audio/sfx/warn.wav",
        "go": "res://assets/audio/sfx/go.wav",
        "count": "res://assets/audio/sfx/count.wav",
        "star": "res://assets/audio/sfx/star.wav",
        "unlock": "res://assets/audio/sfx/unlock.wav",
        "win": "res://assets/audio/sfx/unlock.wav",
}

const MUSIC_MENU := "res://assets/audio/music/music_menu.wav"
const MUSIC_GAME := "res://assets/audio/music/music_game.wav"

var _cache: Dictionary = {}
var _pool: Array = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _music_volume_db := 0.0

func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        _ensure_bus("Music")
        _ensure_bus("SFX")
        for i in 10:
                var p := AudioStreamPlayer.new()
                p.bus = "SFX"
                add_child(p)
                _pool.append(p)
        _music_a = AudioStreamPlayer.new()
        _music_a.bus = "Music"
        add_child(_music_a)
        _music_b = AudioStreamPlayer.new()
        _music_b.bus = "Music"
        add_child(_music_b)
        _active_music = _music_a
        GameState.settings_changed.connect(apply_volumes)
        apply_volumes()

func _ensure_bus(bus_name: String) -> void:
        if AudioServer.get_bus_index(bus_name) == -1:
                AudioServer.add_bus()
                AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
        # new buses send to "Master" by default

func apply_volumes() -> void:
        var m: float = float(GameState.settings.get("music", 0.7))
        var s: float = float(GameState.settings.get("sfx", 0.8))
        AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _vol_to_db(m))
        AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _vol_to_db(s))

static func _vol_to_db(v: float) -> float:
        if v <= 0.001:
                return -60.0
        return linear_to_db(clampf(v, 0.001, 1.0))

# ---------------- SFX ----------------

func _get_stream(sfx_name: String) -> AudioStream:
        if not _cache.has(sfx_name):
                var path: String = SFX.get(sfx_name, "")
                if path == "":
                        push_error("Unknown SFX: " + sfx_name)
                        return null
                var stream: Variant = load(path)
                if stream is AudioStreamWAV:
                        var w := stream as AudioStreamWAV
                        if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
                                pass
                _cache[sfx_name] = stream
        return _cache[sfx_name]

func play_sfx(sfx_name: String, pitch := 1.0, volume_db := 0.0) -> void:
        var stream: AudioStream = _get_stream(sfx_name)
        if stream == null:
                return
        var p: AudioStreamPlayer = _pool[0]
        for cand in _pool:
                if not cand.playing:
                        p = cand
                        break
        p.stream = stream
        p.pitch_scale = clampf(pitch, 0.05, 4.0)
        p.volume_db = volume_db
        p.play()

func click() -> void:
        play_sfx("click")

# ---------------- Music ----------------

func _load_music(path: String) -> AudioStream:
        var stream: Variant = load(path)
        if stream is AudioStreamWAV:
                var w := stream as AudioStreamWAV
                w.loop_mode = AudioStreamWAV.LOOP_FORWARD
                w.loop_begin = 0
                var bytes_per_frame := 2
                if w.stereo:
                        bytes_per_frame = 4
                w.loop_end = w.data.size() / bytes_per_frame
        return stream

func play_music(which: String) -> void:
        var path := MUSIC_MENU
        if which == "game":
                path = MUSIC_GAME
        var stream: AudioStream = _load_music(path)
        if stream == null:
                return
        if _active_music.playing and _active_music.stream == stream:
                return
        var target: AudioStreamPlayer = _music_b if _active_music == _music_a else _music_a
        target.stream = stream
        target.volume_db = -40.0
        target.play()
        var old: AudioStreamPlayer = _active_music
        _active_music = target
        var tw := create_tween()
        tw.tween_property(target, "volume_db", _music_volume_db, 1.2)
        if old.playing:
                tw.parallel().tween_property(old, "volume_db", -40.0, 1.0)
                tw.tween_callback(old.stop)

func stop_music() -> void:
        if _active_music.playing:
                _active_music.stop()

func haptic(ms := 40) -> void:
        if bool(GameState.settings.get("haptics", true)):
                Input.vibrate_handheld(ms)
