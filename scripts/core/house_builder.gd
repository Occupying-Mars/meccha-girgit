extends Node3D
## Maze-style house / mansion interior (CC0 KayKit Furniture Bits).
##
## MECCHA-CHAMELEON-style hide-and-seek in a home: a grid of themed rooms
## (living room, bedroom, library, dining, lounge, study) connected by doorways
## carved as a maze, so a seeker never sees the whole house at once. Cover is
## MEANINGFUL — each room lines up a ROW of IDENTICAL furniture (3 armchairs,
## a row of beds, a run of bookcases, chairs around a table) so a painted, posed
## hider reads as "one more object in the set" instead of a lone silhouette.
##
## The furniture pack ships no walls/floor, so structure is primitive (painted
## drywall + per-room wood/tile floors) and the furniture GLTFs sit on top.
## Layout is DETERMINISTIC (fixed seed) so every networked peer builds an
## identical house. Furniture collision is auto-derived from each piece's mesh
## AABB; everything (incl. floors/walls) is a StaticBody so the seeker's
## eyedropper can sample real surface colors.

const FDIR := "res://assets/maps/furniture/"
const ROOM := 8.0          # interior size of each room (square)
const WALL_H := 3.0
const WALL_T := 0.3
const DOOR_W := 2.8        # doorway gap width
const RX := 3              # rooms across (x)
const RZ := 2              # rooms deep (z)
const SEED := 24601

const WALL_COLOR := Color(0.86, 0.82, 0.73)
const FLOOR_WOOD := Color(0.56, 0.40, 0.26)
const FLOOR_TILE := Color(0.80, 0.80, 0.85)
const FLOOR_RED  := Color(0.55, 0.34, 0.30)

# Each room: which floor + the identical pieces it arranges for camouflage.
const THEME_GRID := [
	["living", "library", "bedroom"],
	["dining", "lounge", "study"],
]

var P := {}                 # piece name -> PackedScene
var _door_v := {}           # Vector2i(rx,rz) -> doorway on EAST wall
var _door_h := {}           # Vector2i(rx,rz) -> doorway on SOUTH wall

var HW := RX * ROOM / 2.0
var HD := RZ * ROOM / 2.0


func _x(v: float) -> float: return v - HW   # local house coord -> centered world x
func _z(v: float) -> float: return v - HD
func _rcx(rx: int) -> float: return rx * ROOM + ROOM / 2.0
func _rcz(rz: int) -> float: return rz * ROOM + ROOM / 2.0


func _ready() -> void:
	_load_pieces()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_carve_maze(rng)
	_build_floor()
	_build_walls()
	for rz in RZ:
		for rx in RX:
			_decorate(rx, rz, THEME_GRID[rz][rx], rng)


func _load_pieces() -> void:
	for n in ["couch", "couch_pillows", "armchair", "armchair_pillows",
			"bed_single_A", "bed_single_B", "bed_double_A", "table_medium",
			"table_medium_long", "table_low", "table_small", "chair_A", "chair_B",
			"chair_stool", "cabinet_medium", "cabinet_medium_decorated", "cabinet_small",
			"shelf_B_large", "rug_rectangle_A", "rug_rectangle_B", "rug_oval_A",
			"lamp_standing", "lamp_table", "cactus_medium_A", "cactus_small_A",
			"pictureframe_large_A", "pictureframe_medium", "book_set", "book_single", "pillow_A"]:
		var path: String = FDIR + n + ".gltf"
		if ResourceLoader.exists(path):
			P[n] = load(path)


# --- Maze: randomized-DFS spanning tree over the RX×RZ room grid + a few loops ---
func _carve_maze(rng: RandomNumberGenerator) -> void:
	var visited := {}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	visited[Vector2i(0, 0)] = true
	while not stack.is_empty():
		var cur: Vector2i = stack[-1]
		var nbrs := _unvisited_neighbors(cur, visited)
		if nbrs.is_empty():
			stack.pop_back()
			continue
		var nxt: Vector2i = nbrs[rng.randi() % nbrs.size()]
		_open(cur, nxt)
		visited[nxt] = true
		stack.push_back(nxt)
	# A couple of extra doorways so the house has alternate routes, not a pure tree.
	for _k in 2:
		var c := Vector2i(rng.randi() % RX, rng.randi() % RZ)
		var ns := _all_neighbors(c)
		if not ns.is_empty():
			_open(c, ns[rng.randi() % ns.size()])


func _all_neighbors(c: Vector2i) -> Array:
	var out := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if n.x >= 0 and n.x < RX and n.y >= 0 and n.y < RZ:
			out.append(n)
	return out


func _unvisited_neighbors(c: Vector2i, visited: Dictionary) -> Array:
	var out := []
	for n in _all_neighbors(c):
		if not visited.has(n):
			out.append(n)
	return out


func _open(a: Vector2i, b: Vector2i) -> void:
	var d := b - a
	if d == Vector2i(1, 0): _door_v[a] = true
	elif d == Vector2i(-1, 0): _door_v[b] = true
	elif d == Vector2i(0, 1): _door_h[a] = true
	elif d == Vector2i(0, -1): _door_h[b] = true


func _north_door(rx: int, rz: int) -> bool: return rz > 0 and _door_h.get(Vector2i(rx, rz - 1), false)
func _south_door(rx: int, rz: int) -> bool: return _door_h.get(Vector2i(rx, rz), false)
func _west_door(rx: int, rz: int) -> bool: return rx > 0 and _door_v.get(Vector2i(rx - 1, rz), false)
func _east_door(rx: int, rz: int) -> bool: return _door_v.get(Vector2i(rx, rz), false)


func _solid_walls(rx: int, rz: int) -> Array:
	var s := []
	if not _north_door(rx, rz): s.append("N")
	if not _south_door(rx, rz): s.append("S")
	if not _west_door(rx, rz): s.append("W")
	if not _east_door(rx, rz): s.append("E")
	if s.is_empty(): s = ["N"]
	return s


# --- structure (primitive) ---
func _build_floor() -> void:
	for rz in RZ:
		for rx in RX:
			var f: String = _theme_floor(THEME_GRID[rz][rx])
			var col := FLOOR_WOOD
			if f == "tile": col = FLOOR_TILE
			elif f == "red": col = FLOOR_RED
			_prim_static("Floor", Vector3(_x(_rcx(rx)), -0.2, _z(_rcz(rz))),
					Vector3(ROOM, 0.4, ROOM), col)  # top face at y=0


func _theme_floor(name: String) -> String:
	match name:
		"dining": return "tile"
		"living", "lounge": return "red"
		_: return "wood"


func _build_walls() -> void:
	# Vertical boundary lines (separate east-west neighbors) at x = c*ROOM.
	for c in range(RX + 1):
		for rz in range(RZ):
			var internal := c > 0 and c < RX
			var door: bool = internal and _door_v.get(Vector2i(c - 1, rz), false)
			_wall_run("z", c * ROOM, rz * ROOM, (rz + 1) * ROOM, door)
	# Horizontal boundary lines at z = r*ROOM.
	for r in range(RZ + 1):
		for rx in range(RX):
			var internal := r > 0 and r < RZ
			var door: bool = internal and _door_h.get(Vector2i(rx, r - 1), false)
			_wall_run("x", r * ROOM, rx * ROOM, (rx + 1) * ROOM, door)


func _wall_run(axis: String, fixed: float, lo: float, hi: float, door: bool) -> void:
	if door:
		var mid := (lo + hi) / 2.0
		var g := DOOR_W / 2.0
		_wall_box(axis, fixed, lo, mid - g)
		_wall_box(axis, fixed, mid + g, hi)
	else:
		_wall_box(axis, fixed, lo, hi)


func _wall_box(axis: String, fixed: float, a: float, b: float) -> void:
	var length := b - a
	if length < 0.1:
		return
	var mid := (a + b) / 2.0
	var pos: Vector3
	var size: Vector3
	if axis == "z":
		pos = Vector3(_x(fixed), WALL_H / 2.0, _z(mid))
		size = Vector3(WALL_T, WALL_H, length)
	else:
		pos = Vector3(_x(mid), WALL_H / 2.0, _z(fixed))
		size = Vector3(length, WALL_H, WALL_T)
	_prim_static("Wall", pos, size, WALL_COLOR)


# --- furniture arrangement per room ---
func _decorate(rx: int, rz: int, theme: String, rng: RandomNumberGenerator) -> void:
	var cx := _rcx(rx)
	var cz := _rcz(rz)
	var solid := _solid_walls(rx, rz)
	var rw: String = solid[rng.randi() % solid.size()]

	match theme:
		"living":
			_rug("rug_rectangle_A", cx, cz)
			_row("armchair", rw, rx, rz, 3, 1.4)
			_piece("couch", cx, cz - 1.6, 0.0)
			_piece("table_low", cx, cz + 0.6, 0.0)
			_corner_accent("lamp_standing", rx, rz, rng)
			_corner_accent("cactus_medium_A", rx, rz, rng)
		"library":
			_row("cabinet_medium_decorated", rw, rx, rz, 3, 1.0)
			_piece("table_medium", cx, cz, 0.0)
			_piece("chair_A", cx - 1.4, cz, 90.0)
			_piece("chair_A", cx + 1.4, cz, -90.0)
			_clutter("book_set", cx, cz, 0.0, 1.0)
			_corner_accent("cactus_small_A", rx, rz, rng)
		"bedroom":
			_row("bed_single_A", rw, rx, rz, 3, 1.8)
			_rug("rug_oval_A", cx, cz)
			_corner_accent("cabinet_small", rx, rz, rng)
			_corner_accent("lamp_standing", rx, rz, rng)
		"dining":
			_piece("table_medium_long", cx, cz, 0.0)
			# A run of identical chairs down both long sides — classic "be a chair" camo.
			for k in 3:
				var t: float = (float(k) + 0.5) / 3.0
				var lx: float = lerp(cx - 1.4, cx + 1.4, t)
				_piece("chair_A", lx, cz - 1.6, 0.0)
				_piece("chair_A", lx, cz + 1.6, 180.0)
			_corner_accent("cabinet_medium", rx, rz, rng)
		"lounge":
			_rug("rug_rectangle_B", cx, cz)
			_row("couch", rw, rx, rz, 2, 1.6)
			_piece("armchair", cx, cz, 180.0)
			_piece("table_low", cx, cz - 1.6, 0.0)
			_corner_accent("cactus_medium_A", rx, rz, rng)
		"study":
			_row("cabinet_medium", rw, rx, rz, 3, 1.0)
			_piece("table_small", cx, cz, 0.0)
			_piece("chair_A", cx, cz + 1.2, 180.0)
			_clutter("book_single", cx, cz, 0.0, 0.9)
			_corner_accent("lamp_standing", rx, rz, rng)

	# Picture frames on a solid wall + a warm ceiling light per room.
	_pictures(rx, rz, solid, rng)
	_ceiling_light(cx, cz)


# Place `count` identical pieces evenly along the inside of a wall, facing in.
func _row(piece: String, wall: String, rx: int, rz: int, count: int, inset: float) -> void:
	if not P.has(piece):
		return
	var x0 := rx * ROOM + 1.3
	var x1 := (rx + 1) * ROOM - 1.3
	var z0 := rz * ROOM + 1.3
	var z1 := (rz + 1) * ROOM - 1.3
	for k in count:
		var t := (float(k) + 0.5) / float(count)
		var lx := 0.0
		var lz := 0.0
		var rot := 0.0
		match wall:
			"N": lx = lerp(x0, x1, t); lz = rz * ROOM + inset; rot = 0.0
			"S": lx = lerp(x0, x1, t); lz = (rz + 1) * ROOM - inset; rot = 180.0
			"W": lx = rx * ROOM + inset; lz = lerp(z0, z1, t); rot = 90.0
			"E": lx = (rx + 1) * ROOM - inset; lz = lerp(z0, z1, t); rot = -90.0
		_piece(piece, lx, lz, rot)


func _corner_accent(piece: String, rx: int, rz: int, rng: RandomNumberGenerator) -> void:
	if not P.has(piece):
		return
	var corners := [
		Vector2(rx * ROOM + 1.2, rz * ROOM + 1.2),
		Vector2((rx + 1) * ROOM - 1.2, rz * ROOM + 1.2),
		Vector2(rx * ROOM + 1.2, (rz + 1) * ROOM - 1.2),
		Vector2((rx + 1) * ROOM - 1.2, (rz + 1) * ROOM - 1.2),
	]
	var c: Vector2 = corners[rng.randi() % corners.size()]
	_piece(piece, c.x, c.y, rng.randf_range(0, 360))


func _clutter(piece: String, cx: float, cz: float, rot: float, on_table_y: float) -> void:
	# Small item resting on a table-height surface (books on a desk, etc.).
	if not P.has(piece):
		return
	var inst: Node3D = P[piece].instantiate()
	inst.position = Vector3(_x(cx), on_table_y, _z(cz))
	inst.rotation_degrees.y = rot
	add_child(inst)


func _pictures(rx: int, rz: int, solid: Array, rng: RandomNumberGenerator) -> void:
	var piece := "pictureframe_large_A" if rng.randi() % 2 == 0 else "pictureframe_medium"
	if not P.has(piece) or solid.is_empty():
		return
	var wall: String = solid[rng.randi() % solid.size()]
	var cx := _rcx(rx)
	var cz := _rcz(rz)
	var h := 1.9
	var inset := 0.18
	var lx := cx
	var lz := cz
	var rot := 0.0
	match wall:
		"N": lz = rz * ROOM + inset; rot = 0.0
		"S": lz = (rz + 1) * ROOM - inset; rot = 180.0
		"W": lx = rx * ROOM + inset; rot = 90.0
		"E": lx = (rx + 1) * ROOM - inset; rot = -90.0
	var inst: Node3D = P[piece].instantiate()
	inst.position = Vector3(_x(lx), h, _z(lz))
	inst.rotation_degrees.y = rot
	add_child(inst)


func _ceiling_light(cx: float, cz: float) -> void:
	var light := OmniLight3D.new()
	light.position = Vector3(_x(cx), 3.4, _z(cz))
	light.light_color = Color(1.0, 0.93, 0.82)
	light.light_energy = 2.2
	light.omni_range = ROOM * 1.4
	light.omni_attenuation = 1.2
	add_child(light)


# --- placement primitives ---
func _piece(piece: String, lx: float, lz: float, rot_y: float) -> void:
	# Furniture GLTF under a StaticBody with an auto-AABB collider. Visual lives
	# UNDER the collider so the eyedropper ray finds the mesh to sample its color.
	if not P.has(piece):
		return
	var body := StaticBody3D.new()
	body.position = Vector3(_x(lx), 0.0, _z(lz))
	body.rotation_degrees.y = rot_y
	var inst: Node3D = P[piece].instantiate()
	body.add_child(inst)
	add_child(body)
	var ab := _aabb_of(inst)
	if ab.size == Vector3.ZERO:
		return
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = ab.size
	cs.shape = shp
	cs.position = ab.position + ab.size * 0.5
	body.add_child(cs)


func _rug(piece: String, cx: float, cz: float) -> void:
	# Flat, no collision — purely visual floor cover.
	if not P.has(piece):
		return
	var inst: Node3D = P[piece].instantiate()
	inst.position = Vector3(_x(cx), 0.02, _z(cz))
	add_child(inst)


func _prim_static(node_name: String, pos: Vector3, size: Vector3, color: Color) -> void:
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
	var shp := BoxShape3D.new()
	shp.size = size
	col.shape = shp
	body.add_child(col)
	add_child(body)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


# Combined AABB of all MeshInstance3D under `node`, in node-local space.
func _aabb_of(node: Node3D) -> AABB:
	var has := false
	var out := AABB()
	var inv := node.global_transform.affine_inverse()
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and n.mesh != null:
			var a: AABB = (inv * n.global_transform) * n.mesh.get_aabb()
			if not has:
				out = a
				has = true
			else:
				out = out.merge(a)
	return out
