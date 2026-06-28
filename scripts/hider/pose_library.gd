extends Object
class_name PoseLibrary
## Pose definitions for the hider blob (seeker.md §pose system).
##
## A pose maps body parts to local transforms (relative to PartsRoot).
## "root" transforms the whole figure (for lie-flat / wall-flatten); "parts"
## overrides individual limbs (crouch / curl). Parts not listed snap back to
## their STAND base. Add new poses here — the rest of the system iterates this
## dict, so the menu and apply logic pick them up automatically.

static var POSES: Dictionary = _build()


static func _xf(pos: Vector3, euler_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(
		deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)))
	b = b.scaled(scale)
	return Transform3D(b, pos)


static func _build() -> Dictionary:
	return {
		# Default upright silhouette — empty overrides => everything at base.
		"stand": {
			"root": Transform3D.IDENTITY,
			"parts": {},
		},
		# Lower, compact stance; knees forward, head dropped.
		"crouch": {
			"root": Transform3D.IDENTITY,
			"parts": {
				"head": _xf(Vector3(0, 1.10, 0.05)),
				"torso": _xf(Vector3(0, 0.80, 0.02), Vector3.ZERO, Vector3(1, 0.85, 1)),
				"arm_l": _xf(Vector3(-0.28, 0.78, 0.06), Vector3(25, 0, 0)),
				"arm_r": _xf(Vector3(0.28, 0.78, 0.06), Vector3(25, 0, 0)),
				"leg_l": _xf(Vector3(-0.14, 0.30, 0.12), Vector3(40, 0, 0)),
				"leg_r": _xf(Vector3(0.14, 0.30, 0.12), Vector3(40, 0, 0)),
			},
		},
		# Curl into a ball — limbs tuck toward a low center.
		"ball": {
			"root": Transform3D.IDENTITY,
			"parts": {
				"head": _xf(Vector3(0, 0.52, 0.22), Vector3(40, 0, 0)),
				"torso": _xf(Vector3(0, 0.46, 0.02), Vector3(35, 0, 0), Vector3(1, 0.7, 1)),
				"arm_l": _xf(Vector3(-0.22, 0.42, 0.20), Vector3(85, 0, 0)),
				"arm_r": _xf(Vector3(0.22, 0.42, 0.20), Vector3(85, 0, 0)),
				"leg_l": _xf(Vector3(-0.12, 0.40, 0.22), Vector3(105, 0, 0)),
				"leg_r": _xf(Vector3(0.12, 0.40, 0.22), Vector3(105, 0, 0)),
			},
		},
		# Lie flat on the ground (on the back). Whole figure tips horizontal.
		"lie_flat": {
			"root": _xf(Vector3(0, 0.18, 0.0), Vector3(-90, 0, 0)),
			"parts": {},
		},
		# Flatten against a wall: thin front-to-back, arms spread wide.
		"wall_flatten": {
			"root": _xf(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.5)),
			"parts": {
				"arm_l": _xf(Vector3(-0.40, 1.28, 0), Vector3(0, 0, 45)),
				"arm_r": _xf(Vector3(0.40, 1.28, 0), Vector3(0, 0, -45)),
				"leg_l": _xf(Vector3(-0.20, 0.42, 0), Vector3(0, 0, 12)),
				"leg_r": _xf(Vector3(0.20, 0.42, 0), Vector3(0, 0, -12)),
			},
		},
	}
