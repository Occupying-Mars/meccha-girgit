extends Node3D
## Procedural colored test arena.
##
## A downloaded environment can replace this later, but a primitive arena
## with KNOWN, varied color blocks is the better camouflage test bed: the
## hider tries to match a wall/crate exactly and we can verify the disguise
## reads correctly. Varied material/sightline surfaces per seeker.md's map
## guidance (walls of different colors, crates, a pillar).
##
## Everything is StaticBody3D so the character collides and the seeker's
## eyedropper can sample real surface colors.

const FLOOR_COLOR := Color(0.45, 0.42, 0.38)

func _ready() -> void:
	_build_floor(24.0)
	# Perimeter walls (4), each a different hue for sightline variety.
	_build_wall(Vector3(0, 1.5, -12), Vector3(24, 3, 0.5), Color(0.70, 0.30, 0.28))   # red-ish
	_build_wall(Vector3(0, 1.5, 12), Vector3(24, 3, 0.5), Color(0.28, 0.45, 0.68))    # blue
	_build_wall(Vector3(-12, 1.5, 0), Vector3(0.5, 3, 24), Color(0.40, 0.58, 0.34))   # green
	_build_wall(Vector3(12, 1.5, 0), Vector3(0.5, 3, 24), Color(0.74, 0.66, 0.32))    # ochre

	# Crates / props of various colors to hide against.
	_build_box(Vector3(-4, 0.5, -6), Vector3(1, 1, 1), Color(0.70, 0.30, 0.28))   # matches red wall
	_build_box(Vector3(4, 0.6, 5), Vector3(1.2, 1.2, 1.2), Color(0.28, 0.45, 0.68))
	_build_box(Vector3(6, 0.4, -4), Vector3(0.8, 0.8, 0.8), Color(0.85, 0.83, 0.80)) # off-white
	_build_box(Vector3(-6, 0.75, 4), Vector3(1.5, 1.5, 0.6), Color(0.40, 0.58, 0.34))
	# A central pillar — high-visibility "hide in plain sight" spot.
	_build_box(Vector3(0, 1.5, 0), Vector3(1, 3, 1), Color(0.55, 0.50, 0.62))


func _build_floor(size: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	mi.mesh = mesh
	mi.material_override = _mat(FLOOR_COLOR)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, 0.2, size)
	col.shape = shape
	col.position = Vector3(0, -0.1, 0)
	body.add_child(col)
	add_child(body)


func _build_wall(pos: Vector3, size: Vector3, color: Color) -> void:
	_static_box("Wall", pos, size, color)

func _build_box(pos: Vector3, size: Vector3, color: Color) -> void:
	_static_box("Crate", pos, size, color)


func _static_box(node_name: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m
