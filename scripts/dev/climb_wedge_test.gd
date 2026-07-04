extends Node3D
## Dev-only: build the house, then validate the two collision fixes against real
## geometry — (1) the wall-climb cap can't rise over a wall, (2) the un-wedge
## finds a clear IN-room spot (never through the perimeter). Headless. Not shipped.

var _ticks := 0


func _ready() -> void:
	var map := Node3D.new()
	map.set_script(load("res://scripts/core/house_builder.gd"))
	add_child(map)


func _physics_process(_d: float) -> void:
	_ticks += 1
	if _ticks != 8:
		return
	var space := get_world_3d().direct_space_state

	print("=== WALL-CLIMB (west perimeter wall, top at y=4) ===")
	# A hider clung just inside the west perimeter wall (world x ~ -11.76).
	var px := -11.76
	var pz := -4.0
	var wn := Vector3(1, 0, 0)  # wall normal points into the room
	var fail := 0
	# Simulate the climb: rise while the wall is still present at HEAD height
	# (hider head ≈ feet + 1.8 * 0.34 = 0.61), mirroring _wall_adjust/_body_top.
	var head := 1.8 * 0.34
	var oy := 0.5
	while oy < 8.0 and _wall_at(space, Vector3(px, oy + head, pz), wn):
		oy += 0.05
	var head_y := oy + head
	var reaches_top: bool = head_y >= 3.8   # head gets to the top = full climb works
	var pokes_out: bool = head_y > 4.15     # body above the wall = visible outside
	if not reaches_top or pokes_out:
		fail += 1
	print("  max feet y = %.2f, head y = %.2f  (wall top = 4.0)" % [oy, head_y])
	print("  head_reaches_top(>=3.8)=%s  body_pokes_out(>4.15)=%s" % [str(reaches_top), str(pokes_out)])

	print("=== UN-WEDGE (full seeker capsule jammed in the NW corner) ===")
	var start := Vector3(-11.6, 0.6, -7.6)  # overlaps both west + north walls
	var free0 := _cap_free(space, start)
	var res := _unwedge(space, start)
	var free1 := _cap_free(space, res)
	var inside := res.x > -11.85 and res.z > -7.85  # clear of both wall faces = in room
	if free0 or not free1 or not inside:
		fail += 1
	print("  start free=%s -> (%.2f, %.2f, %.2f) free=%s inside_room=%s" % [
		str(free0), res.x, res.y, res.z, str(free1), str(inside)])

	print("RESULT: %s" % ("ALL PASS" if fail == 0 else "%d CHECK(S) FAILED" % fail))
	get_tree().quit()


func _wall_at(space: PhysicsDirectSpaceState3D, from: Vector3, wn: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, from - wn * (0.09 + 0.6))
	q.collision_mask = 1
	return not space.intersect_ray(q).is_empty()


func _cap_free(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), pos + Vector3(0, 0.9, 0))
	return space.intersect_shape(q, 1).is_empty()


func _wall_between(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var y := a.y + 1.5
	var q := PhysicsRayQueryParameters3D.create(Vector3(a.x, y, a.z), Vector3(b.x, y, b.z))
	q.collision_mask = 1
	return not space.intersect_ray(q).is_empty()


func _unwedge(space: PhysicsDirectSpaceState3D, start: Vector3) -> Vector3:
	if _cap_free(space, start):
		return start
	for lift in [0.4, 0.9, 1.5]:
		if _cap_free(space, start + Vector3(0, lift, 0)):
			return start + Vector3(0, lift, 0)
	for ring in [0.6, 1.0, 1.5, 2.2, 3.0]:
		for step in 12:
			var ang := TAU * float(step) / 12.0
			var p := start + Vector3(cos(ang) * ring, 0.0, sin(ang) * ring)
			if _cap_free(space, p) and not _wall_between(space, start, p):
				return p
	return start
