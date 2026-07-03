extends Object
class_name PoseLibrary
## Pose definitions for the hider.
##
## Two kinds, freely combined:
##  - "root": a Transform3D on PartsRoot — whole-silhouette changes (crouch,
##    ball, lie flat, wall-flatten...). The paint/shot collider follows these,
##    so the hitbox always matches what the seeker sees.
##  - "bones": {bone_name: euler degrees} — articulated poses on the skeleton
##    (raise a hand, thinker, eagle...), standing-height so the rest-pose
##    collider stays honest.

static var POSES: Dictionary = _build()


static func _xf(pos: Vector3, euler_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(
		deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)))
	b = b.scaled(scale)
	return Transform3D(b, pos)


static func _build() -> Dictionary:
	return {
		# Upright, arms at the sides.
		"stand": {"root": Transform3D.IDENTITY},
		# Squash down into a compact crouch.
		"crouch": {
			"root": _xf(Vector3(0, 0, 0.02), Vector3(8, 0, 0), Vector3(1.06, 0.58, 1.06)),
			"bones": {"uarm_l": Vector3(-24, 0, -10), "uarm_r": Vector3(-24, 0, 10), "head": Vector3(-12, 0, 0)},
		},
		# Curl into a low rounded lump.
		"ball": {
			"root": _xf(Vector3(0, 0, 0), Vector3(14, 0, 0), Vector3(1.20, 0.42, 1.20)),
			"bones": {"head": Vector3(28, 0, 0), "uarm_l": Vector3(30, 0, -14), "uarm_r": Vector3(30, 0, 14)},
		},
		# Tip over and lie flat on the back.
		"lie_flat": {"root": _xf(Vector3(0, 0.16, 0.44), Vector3(-88, 0, 0))},
		# Press thin against a wall (wall-art camo).
		"wall_flatten": {"root": _xf(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.30))},
		# One hand straight up — "pick me!".
		"raised_hand": {
			"root": Transform3D.IDENTITY,
			"bones": {"uarm_r": Vector3(0, 0, 158), "farm_r": Vector3(0, 0, 12), "head": Vector3(0, 0, -8)},
		},
		# Hand on hip, head tilted — attitude.
		"sassy": {
			"root": _xf(Vector3(0.02, 0, 0), Vector3(0, 0, -4)),
			"bones": {"uarm_l": Vector3(0, 0, -46), "farm_l": Vector3(0, 0, -58), "head": Vector3(0, 0, 14), "thigh_r": Vector3(0, 0, -10)},
		},
		# Arms out level — spread eagle.
		"eagle": {
			"root": _xf(Vector3.ZERO, Vector3(6, 0, 0)),
			"bones": {"uarm_l": Vector3(0, 0, -86), "uarm_r": Vector3(0, 0, 86)},
		},
		# Wide low stance, arms bent out — sumo.
		"sumo": {
			"root": _xf(Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(1.14, 0.74, 1.05)),
			"bones": {"thigh_l": Vector3(0, 0, -26), "thigh_r": Vector3(0, 0, 26), "shin_l": Vector3(0, 0, 22), "shin_r": Vector3(0, 0, -22),
					"uarm_l": Vector3(0, 0, -62), "farm_l": Vector3(-40, 0, 0), "uarm_r": Vector3(0, 0, 62), "farm_r": Vector3(-40, 0, 0)},
		},
		# Lean back like something just whooshed past.
		"lean_back": {
			"root": _xf(Vector3(0, 0, -0.05), Vector3(-20, 0, 0)),
			"bones": {"uarm_l": Vector3(-16, 0, -12), "uarm_r": Vector3(-16, 0, 12), "head": Vector3(10, 0, 0)},
		},
		# Hand curled up to the head — the classic thinker.
		"thinker": {
			"root": Transform3D.IDENTITY,
			"bones": {"uarm_r": Vector3(0, 0, 148), "farm_r": Vector3(0, 0, -70), "head": Vector3(4, 0, 10)},
		},
	}
