extends SceneTree
## Dev-only: sculpt the hider body (HiderRig SDF volumes -> marching cubes),
## auto-skin it to the HiderRig bones, and save the skinned ArrayMesh to
##   res://assets/characters/hider_mesh.res
## Runtime never runs marching cubes — it just loads this resource. Run:
##   godot --headless --path . --script res://scripts/dev/bake_hider_mesh.gd

const CELL := 0.02
const BOUNDS_MIN := Vector3(-0.40, -0.02, -0.30)
const BOUNDS_MAX := Vector3(0.40, 1.80, 0.30)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var nx := int(ceil((BOUNDS_MAX.x - BOUNDS_MIN.x) / CELL))
	var ny := int(ceil((BOUNDS_MAX.y - BOUNDS_MIN.y) / CELL))
	var nz := int(ceil((BOUNDS_MAX.z - BOUNDS_MIN.z) / CELL))
	print("[bake] grid %dx%dx%d" % [nx, ny, nz])

	# Sample the field once per grid corner.
	var field := PackedFloat32Array()
	field.resize((nx + 1) * (ny + 1) * (nz + 1))
	var stride_y := nx + 1
	var stride_z := (nx + 1) * (ny + 1)
	for k in nz + 1:
		for j in ny + 1:
			for i in nx + 1:
				var p := BOUNDS_MIN + Vector3(i, j, k) * CELL
				field[i + j * stride_y + k * stride_z] = HiderRig.sdf(p)
	print("[bake] field sampled in %dms" % (Time.get_ticks_msec() - t0))

	# Marching cubes.
	var verts := PackedVector3Array()
	for k in nz:
		for j in ny:
			for i in nx:
				var corner_d: Array = []
				corner_d.resize(8)
				var cube := 0
				for c in 8:
					var o: Vector3i = MCTables.VERT_OFFSET[c]
					var d := field[(i + o.x) + (j + o.y) * stride_y + (k + o.z) * stride_z]
					corner_d[c] = d
					if d < 0.0:
						cube |= 1 << c
				var eflags: int = MCTables.EDGE_TABLE[cube]
				if eflags == 0:
					continue
				var epos: Array = []
				epos.resize(12)
				for e in 12:
					if eflags & (1 << e):
						var c0: int = MCTables.EDGE_CONN[e][0]
						var c1: int = MCTables.EDGE_CONN[e][1]
						var p0 := BOUNDS_MIN + Vector3(Vector3i(i, j, k) + MCTables.VERT_OFFSET[c0]) * CELL
						var p1 := BOUNDS_MIN + Vector3(Vector3i(i, j, k) + MCTables.VERT_OFFSET[c1]) * CELL
						var d0: float = corner_d[c0]
						var d1: float = corner_d[c1]
						var t := clampf(d0 / (d0 - d1), 0.0, 1.0) if absf(d0 - d1) > 1e-9 else 0.5
						epos[e] = p0.lerp(p1, t)
				var row: Array = MCTables.TRI_TABLE[cube]
				var ti := 0
				while row[ti] != -1:
					# table order already winds outward for negative-inside fields
					verts.append(epos[row[ti]])
					verts.append(epos[row[ti + 1]])
					verts.append(epos[row[ti + 2]])
					ti += 3
	print("[bake] %d tris in %dms" % [verts.size() / 3, Time.get_ticks_msec() - t0])

	# Normals from the SDF gradient (perfectly smooth, no welding needed).
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	var bones := PackedInt32Array()
	bones.resize(verts.size() * 4)
	var weights := PackedFloat32Array()
	weights.resize(verts.size() * 4)
	var eps := 0.008
	for vi in verts.size():
		var p := verts[vi]
		var g := Vector3(
			HiderRig.sdf(p + Vector3(eps, 0, 0)) - HiderRig.sdf(p - Vector3(eps, 0, 0)),
			HiderRig.sdf(p + Vector3(0, eps, 0)) - HiderRig.sdf(p - Vector3(0, eps, 0)),
			HiderRig.sdf(p + Vector3(0, 0, eps)) - HiderRig.sdf(p - Vector3(0, 0, eps)))
		norms[vi] = g.normalized()
		# Skinning inline — packed arrays are copy-on-write, so writes inside a
		# helper function would be silently lost.
		var best := {}
		for prim in HiderRig.PRIMS:
			var d := maxf(HiderRig.prim_sdf(p, prim), 0.0)
			var bn: int = prim["bone"]
			if not best.has(bn) or d < best[bn]:
				best[bn] = d
		var infl: Array = []
		for bn in best:
			# Tight falloff + hard cutoff, so e.g. the hand's bone can't drag
			# nearby thigh vertices (cross-limb bleed smears the body).
			var d2: float = best[bn]
			if d2 > 0.055:
				continue
			infl.append([pow(1.0 - d2 / 0.055, 3.0), bn])
		infl.sort_custom(func(x, y): return x[0] > y[0])
		var total := 0.0
		var n: int = mini(4, infl.size())
		for x in n:
			total += infl[x][0]
		for x in 4:
			if x < n:
				bones[vi * 4 + x] = infl[x][1]
				weights[vi * 4 + x] = infl[x][0] / total
			else:
				bones[vi * 4 + x] = 0
				weights[vi * 4 + x] = 0.0
	# Per-FACE paint-atlas UVs: the whole face maps into ONE limb's atlas rect
	# (group chosen at the centroid), so stamps stay limb-local — no bleed.
	for f in range(0, verts.size(), 3):
		var centroid := (verts[f] + verts[f + 1] + verts[f + 2]) / 3.0
		var grp := HiderRig.group_of(centroid)
		for c in 3:
			uvs[f + c] = HiderRig.group_uv(verts[f + c], grp)
	print("[bake] attrs in %dms" % (Time.get_ticks_msec() - t0))

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	DirAccess.make_dir_recursive_absolute("res://assets/characters")
	var err := ResourceSaver.save(mesh, "res://assets/characters/hider_mesh.res")
	print("[bake] saved err=%s  total %dms" % [error_string(err), Time.get_ticks_msec() - t0])
	quit()


