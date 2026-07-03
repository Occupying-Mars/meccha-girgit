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
const SMOOTH_K := 0.07  # smooth-min blend radius (shoulders/hips/neck softness)

## Bone table: name -> {parent, origin}. Rest basis is identity for every bone,
## so pose rotations read as world-axis rotations about the bone origin.
const BONES := [
	{"name": "hips",    "parent": -1, "origin": Vector3(0, 0.78, 0)},
	{"name": "spine",   "parent": 0,  "origin": Vector3(0, 1.06, 0)},
	{"name": "head",    "parent": 1,  "origin": Vector3(0, 1.34, 0)},
	{"name": "uarm_l",  "parent": 1,  "origin": Vector3(-0.16, 1.21, 0)},
	{"name": "farm_l",  "parent": 3,  "origin": Vector3(-0.195, 0.95, 0)},
	{"name": "uarm_r",  "parent": 1,  "origin": Vector3(0.16, 1.21, 0)},
	{"name": "farm_r",  "parent": 5,  "origin": Vector3(0.195, 0.95, 0)},
	{"name": "thigh_l", "parent": 0,  "origin": Vector3(-0.088, 0.74, 0)},
	{"name": "shin_l",  "parent": 7,  "origin": Vector3(-0.092, 0.40, 0)},
	{"name": "thigh_r", "parent": 0,  "origin": Vector3(0.088, 0.74, 0)},
	{"name": "shin_r",  "parent": 9,  "origin": Vector3(0.092, 0.40, 0)},
]

## Sculpt volumes: round-cone capsules {bone, a, b, ra, rb} blended smooth-min.
## Proportions measured off the reference: big round head (~22% of height),
## sloped shoulders, arms ending mid-hip, legs with a small gap.
## NOTE: limb segment pairs are COLLINEAR with matched radii at the joint, so
## the surface has no kink/welt at elbows and knees; z-offsets are all zero for
## the same reason. Hands stay clear of the thighs to avoid webbing at the hip.
const PRIMS := [
	# head (round, chin merging into the shoulders)
	{"bone": 2, "a": Vector3(0, 1.505, 0), "b": Vector3(0, 1.560, 0), "ra": 0.167, "rb": 0.163},
	# torso upper (chest/shoulder mass) + lower (belly/hips)
	{"bone": 1, "a": Vector3(0, 1.20, 0), "b": Vector3(0, 1.02, 0), "ra": 0.146, "rb": 0.142},
	{"bone": 0, "a": Vector3(0, 1.02, 0), "b": Vector3(0, 0.80, 0), "ra": 0.142, "rb": 0.134},
	# arms: hang mostly clear of the torso (merged only at the shoulder) so the
	# skin weights stay separable — buried arms drag chest skin like a membrane.
	{"bone": 3, "a": Vector3(-0.168, 1.19, 0), "b": Vector3(-0.192, 0.975, 0), "ra": 0.074, "rb": 0.068},
	{"bone": 4, "a": Vector3(-0.192, 0.975, 0), "b": Vector3(-0.214, 0.76, 0), "ra": 0.068, "rb": 0.060},
	{"bone": 5, "a": Vector3(0.168, 1.19, 0), "b": Vector3(0.192, 0.975, 0), "ra": 0.074, "rb": 0.068},
	{"bone": 6, "a": Vector3(0.192, 0.975, 0), "b": Vector3(0.214, 0.76, 0), "ra": 0.068, "rb": 0.060},
	# legs: straight vertical taper hip->foot, split at the knee
	{"bone": 7, "a": Vector3(-0.086, 0.73, 0), "b": Vector3(-0.088, 0.405, 0), "ra": 0.103, "rb": 0.089},
	{"bone": 8, "a": Vector3(-0.088, 0.405, 0), "b": Vector3(-0.089, 0.082, 0), "ra": 0.089, "rb": 0.077},
	{"bone": 9, "a": Vector3(0.086, 0.73, 0), "b": Vector3(0.088, 0.405, 0), "ra": 0.103, "rb": 0.089},
	{"bone": 10, "a": Vector3(0.088, 0.405, 0), "b": Vector3(0.089, 0.082, 0), "ra": 0.089, "rb": 0.077},
]


## Paint-atlas regions: each limb group unwraps into its OWN rect of the canvas
## (cylindrical around its own axis), so brush stamps can be clamped to the hit
## limb's rect — no cross-body bleed (an arm stamp can't smear onto the chest).
## {bones, rect(u0,v0,u1,v1), y0..y1 vertical extent, cx/cz local axis}
const PAINT_GROUPS := [
	{"bones": [0, 1], "rect": Rect2(0.00, 0.00, 0.50, 0.50), "y0": 0.62, "y1": 1.38, "cx": 0.0},    # torso
	{"bones": [2], "rect": Rect2(0.50, 0.00, 0.50, 0.50), "y0": 1.28, "y1": 1.76, "cx": 0.0},        # head
	{"bones": [3, 4], "rect": Rect2(0.00, 0.50, 0.25, 0.50), "y0": 0.66, "y1": 1.30, "cx": -0.19},   # arm_l
	{"bones": [5, 6], "rect": Rect2(0.25, 0.50, 0.25, 0.50), "y0": 0.66, "y1": 1.30, "cx": 0.19},    # arm_r
	{"bones": [7, 8], "rect": Rect2(0.50, 0.50, 0.25, 0.50), "y0": -0.02, "y1": 0.80, "cx": -0.088}, # leg_l
	{"bones": [9, 10], "rect": Rect2(0.75, 0.50, 0.25, 0.50), "y0": -0.02, "y1": 0.80, "cx": 0.088}, # leg_r
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
