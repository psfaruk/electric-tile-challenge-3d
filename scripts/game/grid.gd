# Grid — static grid math shared by arena / gameplay / challenge.
# Grid axes: rows advance along -Z (player walks "forward" into the arena),
# columns advance along +X. Cell = Vector2i(row, col).
# Tile (row r, col c) sits at:
#   x = (c - (cols-1)/2) * PITCH
#   z = -r * PITCH
extends Object

const PITCH := 1.25          # distance between tile centers (meters)
const TILE_SIZE := 1.15      # visual tile edge
const TILE_H := 0.15         # tile height; top surface y
const TILE_TOP := 0.15

static func tile_center(cell: Vector2i, cols: int) -> Vector3:
	return Vector3((cell.y - (cols - 1) / 2.0) * PITCH, TILE_TOP, -cell.x * PITCH)

static func cell_from_pos(pos: Vector3, cols: int, rows: int) -> Vector2i:
	var c := int(round(pos.x / PITCH + (cols - 1) / 2.0))
	var r := int(round(-pos.z / PITCH))
	return Vector2i(r, c)

static func in_bounds(cell: Vector2i, cols: int, rows: int) -> bool:
	return cell.x >= 0 and cell.x < rows and cell.y >= 0 and cell.y < cols

static func grid_width(cols: int) -> float:
	return cols * PITCH

static func grid_length(rows: int) -> float:
	return rows * PITCH

# Start pad (safe) center sits one pitch behind row 0; finish pad beyond the last row.
static func start_z() -> float:
	return PITCH * 1.05

static func finish_z(rows: int) -> float:
	return -((rows - 1) * PITCH + PITCH * 1.05)

static func spawn_pos() -> Vector3:
	return Vector3(0.0, TILE_TOP + 0.02, start_z())
