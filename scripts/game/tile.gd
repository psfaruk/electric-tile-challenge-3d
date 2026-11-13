# Tile — one electric floor tile: a state controller driving its LED edge
# instance inside the shared TileField MultiMesh (3 draw calls for the whole
# grid). Public state API is identical to v1 so challenge.gd logic is
# unchanged; the visuals now live in the field (steel lip + smoked-glass top
# + per-instance emissive LED ring).
#
# Edge states (colors/energies match v1 gameplay readability):
#   NORMAL teal @0.16 | SAFE green (shared pulse) | DANGER red (shared pulse)
#   WARNING amber pulse (flippers) | ACTIVATED green flash->settle
#   FAILED red flash->cool | REVEAL safe/danger steady
extends Node

const COL_TEAL := Color(0.16, 0.9, 0.78)
const COL_SAFE := Color(0.27, 0.97, 0.51)
const COL_DANGER := Color(1.0, 0.30, 0.30)
const COL_WARN := Color(1.0, 0.48, 0.16)

var cell := Vector2i(-99, -99)
var _field = null
var _idx := -1

var _hue: Color = COL_TEAL
var _energy := 0.16
var _target := 0.16
var _rate := 4.0            # energy approach speed
var _pulse_amp := 0.0       # warn-pulse amplitude (0 = off)
var _pulse_base := 0.0
var _phase2_at := -1.0      # scheduled second target (flash settle)
var _phase2_target := 0.0
var _t := 0.0

func setup(tile_cell: Vector2i, field) -> void:
        cell = tile_cell
        _field = field
        _idx = field.idx_of(cell)

func _process(delta: float) -> void:
        _t += delta
        if _field == null or _idx < 0:
                return
        if _field.is_shared(_idx, 1) or _field.is_shared(_idx, 0):
                return  # field-level pulse drives shared reveal modes
        if _pulse_amp > 0.0:
                _energy = _pulse_base + _pulse_amp * absf(sin(_t * 8.0))
        else:
                var d := _target - _energy
                if absf(d) > 0.002:
                        _energy += d * clampf(_rate * delta, 0.0, 1.0)
                if _phase2_at > 0.0 and _t >= _phase2_at:
                        _phase2_at = -1.0
                        _target = _phase2_target
        _field.set_edge_color(_idx, _hue * _energy)

# ---------------- state control (v1 API) ----------------

func set_shared(safe: bool) -> void:
        _pulse_amp = 0.0
        _phase2_at = -1.0
        _field.set_shared_mode(_idx, 1 if safe else 0)

func set_own() -> void:
        _field.set_shared_mode(_idx, -1)

func reset_visual() -> void:
        set_own()
        _hue = COL_TEAL
        _energy = 0.16
        _target = 0.16
        _pulse_amp = 0.0
        _phase2_at = -1.0
        _field.set_edge_color(_idx, _hue * _energy)

func flash_correct(_index_in_path: int) -> void:
        set_own()
        _hue = COL_SAFE
        _energy = 2.2
        _target = 0.75
        _rate = 3.5
        _pulse_amp = 0.0
        _phase2_at = _t + 1.75
        _phase2_target = 0.22

func flash_neutral() -> void:
        set_own()
        _hue = COL_TEAL
        _energy = 1.4
        _target = 0.16
        _rate = 3.2
        _pulse_amp = 0.0
        _phase2_at = -1.0

func set_flip(safe: bool, warn: bool) -> void:
        set_own()
        _phase2_at = -1.0
        if warn:
                _hue = COL_WARN
                _pulse_base = 0.75
                _pulse_amp = 0.65
        elif safe:
                _hue = COL_SAFE
                _pulse_amp = 0.0
                _energy = 0.55
                _target = 0.55
        else:
                _hue = COL_DANGER
                _pulse_amp = 0.0
                _energy = 0.4
                _target = 0.4

func mark_failed() -> void:
        set_own()
        _hue = COL_DANGER
        _energy = 3.2
        _target = 1.3
        _rate = 1.1
        _pulse_amp = 0.0
        _phase2_at = -1.0

func reveal_safe() -> void:
        set_own()
        _hue = COL_SAFE
        _energy = 0.9
        _target = 0.9
        _pulse_amp = 0.0
        _field.set_edge_color(_idx, _hue * _energy)

func reveal_danger() -> void:
        set_own()
        _hue = COL_DANGER
        _energy = 0.4
        _target = 0.4
        _pulse_amp = 0.0
        _field.set_edge_color(_idx, _hue * _energy)
