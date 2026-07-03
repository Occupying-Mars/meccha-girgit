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
## Built for a polished, lit look: rooms are ROOFED (ceiling panels block the
## sky so interiors are lit by warm shadow-casting ceiling spotlights + lamp
## glows, giving real pools of light and shadows under the furniture). Ceilings
## live on the minimap-hidden render layer so the top-down map still reads the
## rooms. Walls/floors carry surface-relief normals so they aren't flat blocks.
##
## Layout is DETERMINISTIC (fixed seed) so every networked peer builds an
## identical house. Furniture collision is auto-derived from each piece's mesh
## AABB; everything (incl. floors/walls) is a StaticBody so the seeker's
## eyedropper can sample real surface colors.

const FDIR := "res://assets/maps/furniture/"
const ROOM := 8.0          # interior size of each room (square)
const WALL_H := 4.0        # tall enough that the roof clears a full-size seeker's head
const WALL_T := 0.3
const DOOR_W := 2.8        # doorway gap width
const RX := 3              # rooms across (x)
const RZ := 2              # rooms deep (z)
const SEED := 24601
const MINIMAP_HIDE_LAYER := 1 << 9  # matches HiderBody — minimap camera culls this

const WALL_COLOR := Color(0.87, 0.83, 0.75)
const CEIL_COLOR := Color(0.90, 0.89, 0.86)
const FLOOR_WOOD := Color(0.52, 0.36, 0.22)
const FLOOR_TILE := Color(0.80, 0.80, 0.85)
const FLOOR_RED  := Color(0.52, 0.31, 0.27)

const THEME_GRID := [
	["living", "library", "bedroom"],
	["dining", "lounge", "study"],
]

var P := {}                 # piece name -> PackedScene
var _door_v := {}           # Vector2i(rx,rz) -> doorway on EAST wall
var _door_h := {}           # Vector2i(rx,rz) -> doorway on SOUTH wall

var HW := RX * ROOM / 2.0
var HD := RZ * ROOM / 2.0

var _wall_material: StandardMaterial3D
var _ceil_material: StandardMaterial3D
var _floor_materials := {}
var _furn_detail: Texture2D
var _furn_done := {}


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
	_build_ceiling()
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


# --- structure (primitive, textured-feel materials) ---
func _build_floor() -> void:
	for rz in RZ:
		for rx in RX:
			var f: String = _theme_floor(THEME_GRID[rz][rx])
			_surface("Floor", Vector3(_x(_rcx(rx)), -0.2, _z(_rcz(rz))),
					Vector3(ROOM, 0.4, ROOM), _floor_mat(f), 0)


func _theme_floor(name: String) -> String:
	match name:
		"dining": return "tile"
		"living", "lounge": return "red"
		_: return "wood"


func _build_walls() -> void:
	for c in range(RX + 1):
		for rz in range(RZ):
			var internal := c > 0 and c < RX
			var door: bool = internal and _door_v.get(Vector2i(c - 1, rz), false)
			_wall_run("z", c * ROOM, rz * ROOM, (rz + 1) * ROOM, door)
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
		# A header/lintel over the doorway so it reads as a framed opening.
		_lintel(axis, fixed, mid - g, mid + g)
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
	_surface("Wall", pos, size, _wall_mat(), 0)


func _lintel(axis: String, fixed: float, a: float, b: float) -> void:
	var length := b - a
	var mid := (a + b) / 2.0
	var pos: Vector3
	var size: Vector3
	if axis == "z":
		pos = Vector3(_x(fixed), WALL_H - 0.35, _z(mid))
		size = Vector3(WALL_T, 0.7, length)
	else:
		pos = Vector3(_x(mid), WALL_H - 0.35, _z(fixed))
		size = Vector3(length, 0.7, WALL_T)
	_surface("Lintel", pos, size, _wall_mat(), 0)


func _build_ceiling() -> void:
	# Visual-only roof panels (no collision) on the minimap-hidden layer; they
	# cast shadow so the sky is blocked and rooms are lamp-lit.
	for rz in RZ:
		for rx in RX:
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(ROOM, 0.2, ROOM)
			mi.mesh = mesh
			mi.material_override = _ceil_mat()
			mi.position = Vector3(_x(_rcx(rx)), WALL_H + 0.1, _z(_rcz(rz)))
			mi.layers = MINIMAP_HIDE_LAYER
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)


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

	_pictures(rx, rz, solid, rng)
	_ceiling_light(cx, cz)


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
	# A standing lamp throws its own warm glow.
	if piece == "lamp_standing":
		var gl := OmniLight3D.new()
		gl.position = Vector3(_x(c.x), 2.1, _z(c.y))
		gl.light_color = Color(1.0, 0.83, 0.55)
		gl.light_energy = 3.0
		gl.omni_range = 4.5
		gl.omni_attenuation = 1.6
		add_child(gl)


func _clutter(piece: String, cx: float, cz: float, rot: float, on_table_y: float) -> void:
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
	# A downward spotlight from the ceiling — a real pool of warm light that
	# casts shadows under the furniture. Physical-ish distance falloff
	# (attenuation > 1) and slightly relaxed energy: with SDFGI on, the bounce
	# adds the fill that used to need brute-force direct light.
	var sl := SpotLight3D.new()
	sl.position = Vector3(_x(cx), WALL_H - 0.25, _z(cz))
	sl.rotation_degrees = Vector3(-90, 0, 0)
	sl.light_color = Color(1.0, 0.94, 0.86)
	sl.light_energy = 7.5
	sl.spot_range = WALL_H + 3.5
	sl.spot_angle = 66.0
	sl.spot_angle_attenuation = 0.4
	sl.spot_attenuation = 1.4
	sl.shadow_enabled = true
	sl.shadow_bias = 0.05
	add_child(sl)


# --- placement primitives ---
func _piece(piece: String, lx: float, lz: float, rot_y: float) -> void:
	if not P.has(piece):
		return
	var body := StaticBody3D.new()
	body.position = Vector3(_x(lx), 0.0, _z(lz))
	body.rotation_degrees.y = rot_y
	var inst: Node3D = P[piece].instantiate()
	body.add_child(inst)
	_detail_furniture(inst)
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
	if not P.has(piece):
		return
	var inst: Node3D = P[piece].instantiate()
	inst.position = Vector3(_x(cx), 0.02, _z(cz))
	add_child(inst)


func _surface(node_name: String, pos: Vector3, size: Vector3, mat: Material, layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	if layer != 0:
		mi.layers = layer
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = size
	col.shape = shp
	body.add_child(col)
	add_child(body)


# --- materials: triplanar CC0 PBR textures (Poly Haven) so surfaces read as real
# wood / tile / plaster instead of flat colour. World triplanar = no UV stretch
# on the primitive boxes and a seamless run across the whole house. ---
func _wall_mat() -> StandardMaterial3D:
	if _wall_material == null:
		_wall_material = _pbr("wall", 0.95, 0.35)
	return _wall_material


func _ceil_mat() -> StandardMaterial3D:
	# Textured plaster (near-white tint) instead of a flat untextured colour —
	# the ceiling is a huge part of every indoor frame, and a surface with real
	# normal/roughness response catches bounced light instead of reading as a
	# dead grey plane.
	if _ceil_material == null:
		_ceil_material = _pbr("wall", 0.96, 0.8)
		_ceil_material.albedo_color = Color(0.93, 0.93, 0.91)
	return _ceil_material


func _floor_mat(kind: String) -> StandardMaterial3D:
	if not _floor_materials.has(kind):
		var texname := "tile"
		var rough := 0.55
		var scale := 0.6
		if kind == "red":
			texname = "wood2"; rough = 0.68; scale = 0.45
		elif kind != "tile":
			texname = "wood"; rough = 0.7; scale = 0.45
		_floor_materials[kind] = _pbr(texname, rough, scale)
	return _floor_materials[kind]


## Triplanar PBR material from a Poly Haven CC0 set (diffuse + normal + roughness).
## Strong normals + a real roughness map = visible relief and varied gloss, so
## the surface doesn't read as flat/smooth plastic.
func _pbr(texname: String, rough: float, world_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var d := "res://assets/maps/house_tex/" + texname + "_diff.jpg"
	var nor := "res://assets/maps/house_tex/" + texname + "_nor.jpg"
	var rgh := "res://assets/maps/house_tex/" + texname + "_rough.jpg"
	if ResourceLoader.exists(d):
		m.albedo_texture = load(d)
	if ResourceLoader.exists(nor):
		m.normal_enabled = true
		m.normal_texture = load(nor)
		m.normal_scale = 2.2
	if ResourceLoader.exists(rgh):
		m.roughness_texture = load(rgh)
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(world_scale, world_scale, world_scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Break up the KayKit furniture's flat plastic look: matte it down and add a
## fine detail-normal so surfaces read as fabric/wood micro-texture, not smooth
## blobs. Each shared material is touched once.
func _detail_furniture(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var nd = stack.pop_back()
		for c in nd.get_children():
			stack.push_back(c)
		if nd is MeshInstance3D and nd.mesh != null:
			for s in nd.mesh.get_surface_count():
				var mat = nd.mesh.surface_get_material(s)
				if mat is StandardMaterial3D and not _furn_done.has(mat.get_instance_id()):
					_furn_done[mat.get_instance_id()] = true
					mat.roughness = maxf(mat.roughness, 0.88)
					mat.metallic = 0.0
					mat.detail_enabled = true
					# White detail albedo + MUL = colour unchanged; only the detail
					# normal adds fabric/wood micro-relief (MIX would wash it white).
					mat.detail_albedo = _white_tex()
					mat.detail_normal = _furniture_detail_normal()
					mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL


func _white_tex() -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _furniture_detail_normal() -> Texture2D:
	if _furn_detail == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.32
		var t := NoiseTexture2D.new()
		t.width = 256
		t.height = 256
		t.seamless = true
		t.as_normal_map = true
		t.bump_strength = 1.4
		t.noise = n
		_furn_detail = t
	return _furn_detail


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
