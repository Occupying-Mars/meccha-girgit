extends Node3D
## Procedural "backrooms"-style level: a finite grid of rooms connected by
## doorways, fully enclosed (floor + ceiling), scattered with varied-colour
## furniture to hide behind. Lots of space + sightlines + hiding spots, with
## controlled colours that are perfect for the painting/camouflage game.
##
## Deterministic (fixed seed) so every networked peer builds the IDENTICAL
## layout — the geometry isn't replicated, each peer generates it locally.

const COLS := 6
const ROWS := 5
const ROOM := 7.0      # room size (m)
const WALL_H := 3.0
const WALL_T := 0.3
const DOOR := 2.6      # doorway width

const WALL_COL := Color(0.78, 0.70, 0.42)    # backrooms mono-yellow
const FLOOR_COL := Color(0.42, 0.38, 0.30)
const CEIL_COL := Color(0.85, 0.84, 0.80)
# Furniture palette — varied so hiders have lots to match against.
const PALETTE := [
	Color(0.55, 0.27, 0.20), Color(0.30, 0.34, 0.40), Color(0.62, 0.58, 0.30),
	Color(0.24, 0.42, 0.45), Color(0.70, 0.45, 0.30), Color(0.45, 0.50, 0.55),
	Color(0.66, 0.62, 0.55), Color(0.35, 0.45, 0.32), Color(0.58, 0.30, 0.40),
]

var _w := COLS * ROOM
var _d := ROWS * ROOM
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260628  # identical layout on every peer
	_build_floor_ceiling()
	_build_perimeter()
	_build_internal_walls()
	_scatter_furniture()
	_add_lights()


func room_center(c: int, r: int) -> Vector3:
	return Vector3(-_w * 0.5 + (c + 0.5) * ROOM, 0.0, -_d * 0.5 + (r + 0.5) * ROOM)


func _build_floor_ceiling() -> void:
	_box("Floor", Vector3(0, -0.1, 0), Vector3(_w, 0.2, _d), FLOOR_COL)
	_box("Ceiling", Vector3(0, WALL_H, 0), Vector3(_w, 0.2, _d), CEIL_COL)


func _build_perimeter() -> void:
	var hh := WALL_H * 0.5
	_box("Wall", Vector3(0, hh, -_d * 0.5), Vector3(_w + WALL_T, WALL_H, WALL_T), WALL_COL)
	_box("Wall", Vector3(0, hh, _d * 0.5), Vector3(_w + WALL_T, WALL_H, WALL_T), WALL_COL)
	_box("Wall", Vector3(-_w * 0.5, hh, 0), Vector3(WALL_T, WALL_H, _d + WALL_T), WALL_COL)
	_box("Wall", Vector3(_w * 0.5, hh, 0), Vector3(WALL_T, WALL_H, _d + WALL_T), WALL_COL)


func _build_internal_walls() -> void:
	var hh := WALL_H * 0.5
	# Vertical internal walls (between columns), with a doorway per room.
	for i in range(1, COLS):
		var x := -_w * 0.5 + i * ROOM
		for r in ROWS:
			var z0 := -_d * 0.5 + r * ROOM
			var zmid := z0 + ROOM * 0.5
			var z1 := z0 + ROOM
			_seg_z(x, z0, zmid - DOOR * 0.5, hh)
			_seg_z(x, zmid + DOOR * 0.5, z1, hh)
	# Horizontal internal walls (between rows), with a doorway per room.
	for j in range(1, ROWS):
		var z := -_d * 0.5 + j * ROOM
		for c in COLS:
			var x0 := -_w * 0.5 + c * ROOM
			var xmid := x0 + ROOM * 0.5
			var x1 := x0 + ROOM
			_seg_x(z, x0, xmid - DOOR * 0.5, hh)
			_seg_x(z, xmid + DOOR * 0.5, x1, hh)


func _seg_z(x: float, za: float, zb: float, hh: float) -> void:
	if zb - za <= 0.05:
		return
	_box("Wall", Vector3(x, hh, (za + zb) * 0.5), Vector3(WALL_T, WALL_H, zb - za), WALL_COL)

func _seg_x(z: float, xa: float, xb: float, hh: float) -> void:
	if xb - xa <= 0.05:
		return
	_box("Wall", Vector3((xa + xb) * 0.5, hh, z), Vector3(xb - xa, WALL_H, WALL_T), WALL_COL)


func _scatter_furniture() -> void:
	for c in COLS:
		for r in ROWS:
			var center := room_center(c, r)
			var n := _rng.randi_range(1, 3)
			for k in n:
				var off := Vector3(_rng.randf_range(-2.2, 2.2), 0, _rng.randf_range(-2.2, 2.2))
				_furniture(center + off)


func _furniture(pos: Vector3) -> void:
	var col: Color = PALETTE[_rng.randi() % PALETTE.size()]
	var kind := _rng.randi() % 4
	var size: Vector3
	match kind:
		0: size = Vector3(1.0, 1.0, 1.0)              # crate
		1: size = Vector3(0.5, 2.0, 1.4)              # shelf / locker
		2: size = Vector3(1.5, 0.6, 0.9)              # table / counter
		_: size = Vector3(0.8, 1.5, 0.8)              # cabinet / pillar
	_box("Prop", pos + Vector3(0, size.y * 0.5, 0), size, col)


func _add_lights() -> void:
	# A few dim ceiling lights for atmosphere; ambient (in the scene env) does
	# the heavy lifting so the whole level stays readable.
	for c in range(0, COLS, 2):
		for r in range(0, ROWS, 2):
			var light := OmniLight3D.new()
			light.position = room_center(c, r) + Vector3(0, WALL_H - 0.4, 0)
			light.omni_range = ROOM * 1.6
			light.light_energy = 1.2
			add_child(light)


func _box(node_name: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
