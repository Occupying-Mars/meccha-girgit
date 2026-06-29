extends Node3D
## Procedural warehouse: concrete floor, perimeter walls, rows of tall shelving
## that form aisles, and scattered colored crates to hide/camouflage against.
## Everything is StaticBody3D so players collide and the eyedropper can sample
## real surface colors.

const FLOOR_COL := Color(0.34, 0.34, 0.36)
const WALL_COL := Color(0.55, 0.52, 0.45)
const SHELF_COL := Color(0.30, 0.32, 0.36)
const CRATE_COLS := [
	Color(0.72, 0.32, 0.28), Color(0.30, 0.46, 0.70),
	Color(0.42, 0.60, 0.36), Color(0.80, 0.70, 0.30), Color(0.78, 0.78, 0.74),
]


func _ready() -> void:
	var half := 16.0
	_floor(Vector2(half * 2.0, half * 2.0))
	# Perimeter walls.
	_box(Vector3(0, 2, -half), Vector3(half * 2, 4, 0.5), WALL_COL)
	_box(Vector3(0, 2, half), Vector3(half * 2, 4, 0.5), WALL_COL)
	_box(Vector3(-half, 2, 0), Vector3(0.5, 4, half * 2), WALL_COL)
	_box(Vector3(half, 2, 0), Vector3(0.5, 4, half * 2), WALL_COL)

	# Three rows of shelving running along Z, leaving aisles between them.
	for x in [-8.0, 0.0, 8.0]:
		_shelf_row(x)

	# Scattered crates of varied colors (camouflage targets).
	var spots := [
		Vector3(-12, 0, 10), Vector3(12, 0, -10), Vector3(4, 0, 11),
		Vector3(-4, 0, -11), Vector3(11, 0, 4), Vector3(-11, 0, -4),
		Vector3(-12, 0, -11), Vector3(12, 0, 11),
	]
	for i in spots.size():
		var s: float = 0.8 + 0.5 * float(i % 3)
		_box(spots[i] + Vector3(0, s * 0.5, 0), Vector3(s, s, s), CRATE_COLS[i % CRATE_COLS.size()])


func _shelf_row(x: float) -> void:
	# A "shelf" = two tall uprights joined by a couple of horizontal planks,
	# repeated down Z with gaps you can slip between.
	for z in range(-12, 13, 6):
		var base := Vector3(x, 0, float(z))
		_box(base + Vector3(-1.4, 1.5, 0), Vector3(0.3, 3, 1.6), SHELF_COL)  # upright L
		_box(base + Vector3(1.4, 1.5, 0), Vector3(0.3, 3, 1.6), SHELF_COL)   # upright R
		_box(base + Vector3(0, 1.0, 0), Vector3(2.8, 0.2, 1.6), SHELF_COL)   # low shelf
		_box(base + Vector3(0, 2.4, 0), Vector3(2.8, 0.2, 1.6), SHELF_COL)   # high shelf
		# A boxed item on the low shelf (random-ish colour for camo variety).
		_box(base + Vector3(0, 1.45, 0), Vector3(0.9, 0.7, 0.9), CRATE_COLS[(z + 12) / 6 % CRATE_COLS.size()])


func _floor(size: Vector2) -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(FLOOR_COL)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)


func _box(pos: Vector3, size: Vector3, col: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(col)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = size
	cs.shape = shp
	body.add_child(cs)
	add_child(body)


func _mat(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.85
	return mat
