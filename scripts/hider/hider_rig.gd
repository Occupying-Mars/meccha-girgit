extends Object
class_name HiderRig
## Shared definition of the hider's skeleton and the smooth-blended volumes
## ("SDF primitives") that sculpt its body. Used by BOTH:
##   - scripts/dev/bake_hider_mesh.gd  (dev-only: marching-cubes bake -> .res)
##   - scripts/hider/hider_body.gd     (runtime: builds the Skeleton3D)
##
## The body is sculpted like the MECCHA reference: a soft one-piece figure —
## round head, smoothly sloped shoulders, thick arms hanging close, sturdy legs
## — all blended seamlessly (smooth-min), then auto-skinned to these bones.

const HEIGHT := 1.74
## Small blend radius = defined CREASES where limbs meet the body (the big-K
## version read as melted/clumped; the reference has crisp limb separation).
const SMOOTH_K := 0.028

## Bone table: name -> {parent, origin}. Rest basis is identity for every bone,
## so pose rotations read as world-axis rotations about the bone origin.
const BONES := [
	{"name": "hips",    "parent": -1, "origin": Vector3(0, 0.70, 0)},
	{"name": "spine",   "parent": 0,  "origin": Vector3(0, 1.00, 0)},
	{"name": "head",    "parent": 1,  "origin": Vector3(0, 1.30, 0)},
	{"name": "uarm_l",  "parent": 1,  "origin": Vector3(-0.19, 1.18, 0)},
	{"name": "farm_l",  "parent": 3,  "origin": Vector3(-0.235, 0.90, 0)},
	{"name": "uarm_r",  "parent": 1,  "origin": Vector3(0.19, 1.18, 0)},
	{"name": "farm_r",  "parent": 5,  "origin": Vector3(0.235, 0.90, 0)},
	{"name": "thigh_l", "parent": 0,  "origin": Vector3(-0.10, 0.62, 0)},
	{"name": "shin_l",  "parent": 7,  "origin": Vector3(-0.103, 0.32, 0)},
	{"name": "thigh_r", "parent": 0,  "origin": Vector3(0.10, 0.62, 0)},
	{"name": "shin_r",  "parent": 9,  "origin": Vector3(0.103, 0.32, 0)},
]

## Sculpt volumes: round-cone capsules {bone, a, b, ra, rb} blended smooth-min.
## Proportions matched to the clean reference figure: big round head (~24% of
## height), THICK rounded arms bowed slightly outward with a visible groove
## against the torso, legs touching at the crotch with a crease between them.
## Limb segment pairs stay collinear-ish with matched joint radii (no welts).
const PRIMS := [
	# head (rounded egg — equal radii so the surface has no tangent ledge)
	{"bone": 2, "a": Vector3(0, 1.465, 0), "b": Vector3(0, 1.555, 0), "ra": 0.180, "rb": 0.180},
	# torso: chest/shoulder mass tapering to the hips
	{"bone": 1, "a": Vector3(0, 1.22, 0), "b": Vector3(0, 0.98, 0), "ra": 0.170, "rb": 0.160},
	{"bone": 0, "a": Vector3(0, 0.98, 0), "b": Vector3(0, 0.70, 0), "ra": 0.160, "rb": 0.145},
	# arms: thick, rounded, bowing slightly OUT from the shoulder so a clear
	# groove separates them from the torso; club ends just above the crotch.
	{"bone": 3, "a": Vector3(-0.195, 1.16, 0), "b": Vector3(-0.235, 0.90, 0), "ra": 0.088, "rb": 0.084},
	{"bone": 4, "a": Vector3(-0.235, 0.90, 0), "b": Vector3(-0.245, 0.66, 0), "ra": 0.084, "rb": 0.079},
	{"bone": 5, "a": Vector3(0.195, 1.16, 0), "b": Vector3(0.235, 0.90, 0), "ra": 0.088, "rb": 0.084},
	{"bone": 6, "a": Vector3(0.235, 0.90, 0), "b": Vector3(0.245, 0.66, 0), "ra": 0.084, "rb": 0.079},
	# legs: touch at the crotch (crease, not a melt), slight taper to round feet
	{"bone": 7, "a": Vector3(-0.100, 0.60, 0), "b": Vector3(-0.103, 0.32, 0), "ra": 0.100, "rb": 0.090},
	{"bone": 8, "a": Vector3(-0.103, 0.32, 0), "b": Vector3(-0.105, 0.085, 0), "ra": 0.090, "rb": 0.080},
	{"bone": 9, "a": Vector3(0.100, 0.60, 0), "b": Vector3(0.103, 0.32, 0), "ra": 0.100, "rb": 0.090},
	{"bone": 10, "a": Vector3(0.103, 0.32, 0), "b": Vector3(0.105, 0.085, 0), "ra": 0.090, "rb": 0.080},
]


## Paint-atlas regions: each limb group unwraps into its OWN rect of the canvas
## (cylindrical around its own axis), so brush stamps can be clamped to the hit
## limb's rect — no cross-body bleed (an arm stamp can't smear onto the chest).
## {bones, rect(u0,v0,u1,v1), y0..y1 vertical extent, cx/cz local axis}
const PAINT_GROUPS := [
	{"bones": [0, 1], "rect": Rect2(0.00, 0.00, 0.50, 0.50), "y0": 0.52, "y1": 1.42, "cx": 0.0},    # torso
	{"bones": [2], "rect": Rect2(0.50, 0.00, 0.50, 0.50), "y0": 1.26, "y1": 1.78, "cx": 0.0},        # head
	{"bones": [3, 4], "rect": Rect2(0.00, 0.50, 0.25, 0.50), "y0": 0.54, "y1": 1.28, "cx": -0.23},   # arm_l
	{"bones": [5, 6], "rect": Rect2(0.25, 0.50, 0.25, 0.50), "y0": 0.54, "y1": 1.28, "cx": 0.23},    # arm_r
	{"bones": [7, 8], "rect": Rect2(0.50, 0.50, 0.25, 0.50), "y0": -0.02, "y1": 0.72, "cx": -0.103}, # leg_l
	{"bones": [9, 10], "rect": Rect2(0.75, 0.50, 0.25, 0.50), "y0": -0.02, "y1": 0.72, "cx": 0.103}, # leg_r
]


## Which paint group a point belongs to (by nearest sculpt volume).
static func group_of(p: Vector3) -> int:
	var best_d := 1e9
	var best_bone := 0
	for prim in PRIMS:
		var d := prim_sdf(p, prim)
		if d < best_d:
			best_d = d
			best_bone = prim["bone"]
	for g in PAINT_GROUPS.size():
		if best_bone in PAINT_GROUPS[g]["bones"]:
			return g
	return 0


## UV of a point within its group's atlas rect (cylindrical around the group axis).
static func group_uv(p: Vector3, g: int) -> Vector2:
	var grp: Dictionary = PAINT_GROUPS[g]
	var rect: Rect2 = grp["rect"]
	var u := atan2(p.x - grp["cx"], p.z) / TAU + 0.5
	var v := clampf((grp["y1"] - p.y) / (grp["y1"] - grp["y0"]), 0.0, 1.0)
	# inset so brush blur never crosses into a neighbouring region
	var inset := 0.02
	return Vector2(
		rect.position.x + (inset + u * (1.0 - 2.0 * inset)) * rect.size.x,
		rect.position.y + (inset + v * (1.0 - 2.0 * inset)) * rect.size.y)


## Distance to a round-cone capsule (segment a-b with radii ra->rb).
static func prim_sdf(p: Vector3, prim: Dictionary) -> float:
	var a: Vector3 = prim["a"]
	var b: Vector3 = prim["b"]
	var ra: float = prim["ra"]
	var rb: float = prim["rb"]
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	var r := lerpf(ra, rb, t)
	return (p - (a + ab * t)).length() - r


## Whole-body field: smooth-min of all volumes (negative inside).
static func sdf(p: Vector3) -> float:
	var d := 1e9
	for prim in PRIMS:
		var pd := prim_sdf(p, prim)
		# polynomial smooth-min
		var h := clampf(0.5 + 0.5 * (d - pd) / SMOOTH_K, 0.0, 1.0)
		d = lerpf(d, pd, h) - SMOOTH_K * h * (1.0 - h)
	return d
