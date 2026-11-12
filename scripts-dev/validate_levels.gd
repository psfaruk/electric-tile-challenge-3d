# Headless validator for all 50 level configs — CI quality gate.
# Usage: godot --headless --path . --script res://scripts-dev/validate_levels.gd
# Exits with code 1 on any violation.
extends SceneTree

func _initialize() -> void:
	var fails := 0
	for id in range(1, 51):
		var errs: Array = _validate(id)
		if errs.is_empty():
			print("LEVEL %03d OK" % id)
		else:
			fails += 1
			for e in errs:
				push_error("LEVEL %03d FAIL: %s" % [id, e])
				print("LEVEL %03d FAIL: %s" % [id, e])
	if fails > 0:
		print("VALIDATE LEVELS: %d FAILURES" % fails)
		quit(1)
	else:
		print("VALIDATE LEVELS: ALL 50 OK")
		quit(0)

func _validate(id: int) -> Array:
	var errs: Array = []
	var path := "res://data/levels/level_%03d.json" % id
	if not FileAccess.file_exists(path):
		errs.append("missing file " + path)
		return errs
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Dictionary):
		errs.append("invalid JSON")
		return errs
	var d: Dictionary = raw
	for k in ["id", "name", "mode", "tier", "cols", "rows", "mem_time", "time_limit", "path", "flippers", "par_time", "gold_time"]:
		if not d.has(k):
			errs.append("missing key " + k)
	if not errs.is_empty():
		return errs
	if int(d["id"]) != id:
		errs.append("id mismatch")
	var mode: String = str(d["mode"])
	if not (mode == "memory" or mode == "timed" or mode == "pattern"):
		errs.append("bad mode " + mode)
	var cols := int(d["cols"])
	var rows := int(d["rows"])
	if cols < 5 or cols > 12 or rows < 5 or rows > 12:
		errs.append("grid out of range")
	var path_cells: Array = d["path"]
	if path_cells.size() < 4:
		errs.append("path too short")
	var seen := {}
	var prev := Vector2i(9999, 9999)
	var first := true
	for c in path_cells:
		var cell := Vector2i(int(c[0]), int(c[1]))
		if seen.has(cell):
			errs.append("repeated cell " + str(cell))
		seen[cell] = true
		if cell.x < 0 or cell.x >= rows or cell.y < 0 or cell.y >= cols:
			errs.append("out of bounds " + str(cell))
		if first:
			if cell.x != 0:
				errs.append("path does not start at row 0")
			first = false
		else:
			var dist: int = absi(cell.x - prev.x) + absi(cell.y - prev.y)
			if dist != 1:
				errs.append("not adjacent " + str(prev) + " -> " + str(cell))
			if cell.x < prev.x:
				errs.append("row decreased")
		prev = cell
	if prev.x != rows - 1:
		errs.append("path does not end at last row")
	for f in d["flippers"]:
		var fc := Vector2i(int(f[0]), int(f[1]))
		if fc.x < 0 or fc.x >= rows or fc.y < 0 or fc.y >= cols:
			errs.append("flipper out of bounds")
		if float(f[2]) < 2.5:
			errs.append("flipper period too short")
		if int(f[4]) == 1 and not seen.has(fc):
			errs.append("on-path flipper not on path")
		if int(f[4]) == 0 and seen.has(fc):
			errs.append("off-path flipper overlaps path")
	var par := float(d["par_time"])
	if par <= 0.0 or float(d["gold_time"]) >= par:
		errs.append("par/gold invalid")
	if float(d["mem_time"]) < 1.0:
		errs.append("mem_time < 1.0")
	if mode == "timed":
		if float(d["time_limit"]) < par + 3.0:
			errs.append("time_limit too tight")
	else:
		if absf(float(d["time_limit"])) > 0.001:
			errs.append("time_limit must be 0 for non-timed")
	return errs
