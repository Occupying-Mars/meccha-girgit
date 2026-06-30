extends Node3D
## Maze-style KayKit dungeon (CC0 KayKit Dungeon Remastered pieces).
##
## Designed for MECCHA-CHAMELEON-style hide-and-seek: instead of one open room
## with random props, this is a WARREN of themed rooms connected by a carved
## maze (branching paths, dead ends, loops) so a seeker can never see much at
## once. Cover is MEANINGFUL — rooms place ROWS / CLUSTERS of identical objects
## (barrels, kegs, pillars, shelves, chests) so a painted, posed hider becomes
## "one more object in the row" rather than a lone silhouette in the open.
## Torches give pools of warm light and deep shadow corners to hide in.
##
## Layout is DETERMINISTIC (fixed seed) so every networked peer builds an
## identical map — required so collision matches the visuals on all clients.
## Collision is auto-derived from each piece's mesh AABB (no manual measuring).

const T := 4.0
const RX := 2     # rooms across (x)
const RZ := 3     # rooms deep (z)
const RW := 3     # tiles per room (x)
const RD := 2     # tiles per room (z)
const NX := RX * RW
const NZ := RZ * RD
const SEED := 71777

# Theme presets: floor type + the camouflage pieces a room arranges.
# row  = identical pieces lined up along a wall (primary camo: be "one more")
# pile = a cluster/stack in a corner
# wall = flat wall decoration (banner / shelf) to flatten-paint against
# bits = small scattered clutter
const THEMES := {
	"storage":  {"floor": "floor_dirt",      "row": "barrel_large", "pile": "crates_stacked", "wall": "shelf_large",   "bits": ["box_small", "barrel_small"]},
	"cellar":   {"floor": "floor_wood_dark", "row": "keg",          "pile": "box_stacked",    "wall": "banner_blue",   "bits": ["bottle", "barrel_dec"]},
	"library":  {"floor": "floor_wood",      "row": "shelf_large",  "pile": "crates",         "wall": "wall_shelves",  "bits": ["table", "bottle"]},
	"treasure": {"floor": "floor",           "row": "chest",        "pile": "coins",          "wall": "banner_red",    "bits": ["chest_gold", "coins"]},
	"quarters": {"floor": "floor_wood",      "row": "bed",          "pile": "box_stacked",    "wall": "banner_green",  "bits": ["chair", "table_med", "stool"]},
	"ritual":   {"floor": "floor",           "row": "pillar",       "pile": "candles",        "wall": "banner_red",    "bits": ["pillar_dec", "candles"]},
	"armory":   {"floor": "floor",           "row": "barrel_dec",   "pile": "crates_stacked", "wall": "sword_shield",  "bits": ["box_large", "table_long"]},
}
const THEME_GRID := [
	["storage", "library"],
	["treasure", "cellar"],
	["ritual", "armory"],
]

var P := {}                 # piece name -> PackedScene
var _door_v := {}           # Vector2i(rx,rz) -> doorway on EAST wall
var _door_h := {}           # Vector2i(rx,rz) -> doorway on SOUTH wall


func _tx(i: float) -> float: return (i - float(NX - 1) / 2.0) * T
func _tz(j: float) -> float: return (j - float(NZ - 1) / 2.0) * T


func _ready() -> void:
	_load_pieces()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_carve_maze(rng)
	_build_floor()
	_build_walls()
	_decorate_rooms(rng)


func _load_pieces() -> void:
	var dir := "res://assets/maps/kaykit/"
	for n in ["floor", "floor_wood", "floor_wood_dark", "floor_dirt", "floor_grate",
			"wall", "wall_corner", "wall_doorway", "wall_arched", "wall_shelves", "wall_gated", "wall_half",
			"pillar", "pillar_dec", "column", "barrel_large", "barrel_small", "barrel_dec", "barrel_stack",
			"keg", "box_large", "box_small", "box_stacked", "crates", "crates_stacked", "table", "table_long",
			"table_med", "chair", "stool", "bed", "shelf_large", "chest", "chest_gold", "coins", "bottle",
			"candles", "sword_shield", "banner_red", "banner_blue", "banner_green", "torch_wall"]:
		var path: String = dir + n + ".glb"
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
	# extra loop doorways so it's not a pure tree (alternate routes)
	for _k in 5:
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


# Doorway tests for a room's four walls.
func _north_door(rx: int, rz: int) -> bool: return rz > 0 and _door_h.get(Vector2i(rx, rz - 1), false)
func _south_door(rx: int, rz: int) -> bool: return _door_h.get(Vector2i(rx, rz), false)
func _west_door(rx: int, rz: int) -> bool: return rx > 0 and _door_v.get(Vector2i(rx - 1, rz), false)
func _east_door(rx: int, rz: int) -> bool: return _door_v.get(Vector2i(rx, rz), false)


func _build_floor() -> void:
	# Each tile is its own mesh+collider so the eyedropper can sample its color.
	for rz in RZ:
		for rx in RX:
			var ft: String = THEMES[THEME_GRID[rz][rx]]["floor"]
			if not P.has(ft):
				ft = "floor"
			for di in RW:
				for dj in RD:
					_floor_tile(ft, Vector3(_tx(rx * RW + di), 0, _tz(rz * RD + dj)))


func _floor_tile(piece: String, pos: Vector3) -> void:
	if not P.has(piece):
		return
	var body := StaticBody3D.new()
	body.position = pos
	var inst: Node3D = P[piece].instantiate()
	body.add_child(inst)  # mesh under the collider → eyedropper can read the floor
	add_child(body)
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(T, 0.6, T)            # thick enough to stand on safely
	cs.position = Vector3(0, 0.05 - 0.3, 0)  # top face ≈ y 0.05
	cs.shape = shp
	body.add_child(cs)


func _build_walls() -> void:
	var west := _tx(0) - T / 2.0
	var east := _tx(NX - 1) + T / 2.0
	var north := _tz(0) - T / 2.0
	var south := _tz(NZ - 1) + T / 2.0

	# Vertical wall lines at room-column boundaries (x = multiples of RW).
	for bc in range(0, RX + 1):
		var x := _tx(bc * RW) - T / 2.0
		for j in NZ:
			var rz := j / RD
			var internal := bc > 0 and bc < RX
			var is_door: bool = internal and _door_v.get(Vector2i(bc - 1, rz), false) and (j % RD == RD / 2)
			if is_door:
				_visual("wall_arched", Vector3(x, 0, _tz(j)), 90.0)
			else:
				_solid("wall", Vector3(x, 0, _tz(j)), 90.0)

	# Horizontal wall lines at room-row boundaries (z = multiples of RD).
	for br in range(0, RZ + 1):
		var z := _tz(br * RD) - T / 2.0
		for i in NX:
			var rx := i / RW
			var internal := br > 0 and br < RZ
			var is_door: bool = internal and _door_h.get(Vector2i(rx, br - 1), false) and (i % RW == RW / 2)
			if is_door:
				_visual("wall_arched", Vector3(_tx(i), 0, z), 0.0)
			else:
				_solid("wall", Vector3(_tx(i), 0, z), 0.0)

	# Outer corners.
	_visual("wall_corner", Vector3(west, 0, north), 0.0)
	_visual("wall_corner", Vector3(east, 0, north), 90.0)
	_visual("wall_corner", Vector3(east, 0, south), 180.0)
	_visual("wall_corner", Vector3(west, 0, south), 270.0)


func _decorate_rooms(rng: RandomNumberGenerator) -> void:
	for rz in RZ:
		for rx in RX:
			_decorate(rx, rz, THEMES[THEME_GRID[rz][rx]], rng)


func _decorate(rx: int, rz: int, theme: Dictionary, rng: RandomNumberGenerator) -> void:
	var xi0 := rx * RW
	var xi1 := rx * RW + RW - 1
	var zi0 := rz * RD
	var zi1 := rz * RD + RD - 1
	var cx := (_tx(xi0) + _tx(xi1)) * 0.5
	var cz := (_tz(zi0) + _tz(zi1)) * 0.5
	var x0 := _tx(xi0) - T / 2.0
	var x1 := _tx(xi1) + T / 2.0
	var z0 := _tz(zi0) - T / 2.0
	var z1 := _tz(zi1) + T / 2.0

	# Which walls are solid (good to line objects / decor against).
	var solid := []
	if not _north_door(rx, rz): solid.append("N")
	if not _south_door(rx, rz): solid.append("S")
	if not _west_door(rx, rz): solid.append("W")
	if not _east_door(rx, rz): solid.append("E")
	if solid.is_empty():
		solid = ["N"]

	# 1) Primary camo ROW of identical pieces along a solid wall.
	var row_wall: String = solid[rng.randi() % solid.size()]
	_row(theme["row"], row_wall, x0, x1, z0, z1, cx, cz, 3)

	# 2) Cluster/pile in a back corner.
	_solid(theme["pile"], Vector3(lerp(x0, cx, 0.45), 0, lerp(z0, cz, 0.45)), rng.randf_range(0, 360))

	# 3) Wall decoration + a torch on a solid wall (flatten-paint surface + light).
	var dec_wall: String = solid[rng.randi() % solid.size()]
	_on_wall(theme["wall"], dec_wall, x0, x1, z0, z1, cx, cz, 2.2, false)
	_on_wall("torch_wall", dec_wall, x0, x1, z0, z1, cx, cz, 2.6, true)

	# 4) A little scattered clutter (silhouette breakers) — deterministic.
	var bits: Array = theme["bits"]
	for _n in 2:
		var piece: String = bits[rng.randi() % bits.size()]
		var p := Vector3(rng.randf_range(x0 + 1.5, x1 - 1.5), 0, rng.randf_range(z0 + 1.5, z1 - 1.5))
		_solid(piece, p, rng.randf_range(0, 360))


# Place `count` identical pieces evenly along the inside of a wall, facing in.
func _row(piece: String, wall: String, x0: float, x1: float, z0: float, z1: float, cx: float, cz: float, count: int) -> void:
	if not P.has(piece):
		return
	var inset := 1.4
	for k in count:
		var t := (float(k) + 0.5) / float(count)
		var pos: Vector3
		var rot := 0.0
		match wall:
			"N": pos = Vector3(lerp(x0 + 1.0, x1 - 1.0, t), 0, z0 + inset); rot = 180.0
			"S": pos = Vector3(lerp(x0 + 1.0, x1 - 1.0, t), 0, z1 - inset); rot = 0.0
			"W": pos = Vector3(x0 + inset, 0, lerp(z0 + 1.0, z1 - 1.0, t)); rot = 90.0
			"E": pos = Vector3(x1 - inset, 0, lerp(z0 + 1.0, z1 - 1.0, t)); rot = -90.0
		_solid(piece, pos, rot)


# Place a flat decoration (or torch+light) against the inside face of a wall.
func _on_wall(piece: String, wall: String, x0: float, x1: float, z0: float, z1: float, cx: float, cz: float, h: float, lit: bool) -> void:
	if not P.has(piece):
		return
	var inset := 0.25
	var pos: Vector3
	var rot := 0.0
	match wall:
		"N": pos = Vector3(cx, h, z0 + inset); rot = 180.0
		"S": pos = Vector3(cx, h, z1 - inset); rot = 0.0
		"W": pos = Vector3(x0 + inset, h, cz); rot = 90.0
		"E": pos = Vector3(x1 - inset, h, cz); rot = -90.0
	_visual(piece, pos, rot)
	if lit:
		var light := OmniLight3D.new()
		light.position = pos + Vector3(0, 0.2, 0)
		light.light_color = Color(1.0, 0.78, 0.45)
		light.light_energy = 3.0
		light.omni_range = 9.0
		light.omni_attenuation = 1.5
		add_child(light)


# --- placement primitives ---
func _visual(piece: String, pos: Vector3, rot_y: float) -> void:
	if not P.has(piece):
		return
	var inst: Node3D = P[piece].instantiate()
	inst.position = pos
	inst.rotation_degrees.y = rot_y
	add_child(inst)


func _solid(piece: String, pos: Vector3, rot_y: float) -> void:
	if not P.has(piece):
		return
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = rot_y
	var inst: Node3D = P[piece].instantiate()
	body.add_child(inst)  # visual lives UNDER the collider so the eyedropper ray
	add_child(body)       # finds the mesh to sample its exact surface color
	var ab := _aabb_of(inst)
	if ab.size == Vector3.ZERO:
		return
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = ab.size
	cs.shape = shp
	cs.position = ab.position + ab.size * 0.5  # AABB center in the piece's local frame
	body.add_child(cs)


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
