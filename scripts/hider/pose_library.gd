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
		# Squat: whole figure drops, thighs fold up under a leaned torso, arms
		# rest on the knees. Reads as a low compact crouch.
		"crouch": {
			"root": Transform3D.IDENTITY,
			"parts": {
				"head": _xf(Vector3(0, 0.92, 0.16), Vector3(18, 0, 0)),
				"torso": _xf(Vector3(0, 0.66, 0.06), Vector3(20, 0, 0), Vector3(1, 0.8, 1)),
				"arm_l": _xf(Vector3(-0.26, 0.50, 0.20), Vector3(70, 0, 0), Vector3(1, 0.85, 1)),
				"arm_r": _xf(Vector3(0.26, 0.50, 0.20), Vector3(70, 0, 0), Vector3(1, 0.85, 1)),
				"leg_l": _xf(Vector3(-0.14, 0.22, 0.18), Vector3(72, 0, 0), Vector3(1, 0.7, 1)),
				"leg_r": _xf(Vector3(0.14, 0.22, 0.18), Vector3(72, 0, 0), Vector3(1, 0.7, 1)),
			},
		},
		# Curl into a tight ball: head tucks to knees, limbs wrap around a low
		# center. A rounded blob, no human outline.
		"ball": {
			"root": Transform3D.IDENTITY,
			"parts": {
				"head": _xf(Vector3(0, 0.34, 0.26), Vector3(70, 0, 0)),
				"torso": _xf(Vector3(0, 0.36, 0.08), Vector3(70, 0, 0), Vector3(1.1, 0.65, 1.1)),
				"arm_l": _xf(Vector3(-0.20, 0.30, 0.24), Vector3(105, 0, 0), Vector3(1, 0.8, 1)),
				"arm_r": _xf(Vector3(0.20, 0.30, 0.24), Vector3(105, 0, 0), Vector3(1, 0.8, 1)),
				"leg_l": _xf(Vector3(-0.12, 0.28, 0.26), Vector3(135, 0, 0), Vector3(1, 0.7, 1)),
				"leg_r": _xf(Vector3(0.12, 0.28, 0.26), Vector3(135, 0, 0), Vector3(1, 0.7, 1)),
			},
		},
		# Lie flat on the back: the whole figure tips horizontal and rests low
		# on the floor, arms tucked to the sides.
		"lie_flat": {
			"root": _xf(Vector3(0, 0.14, 0.55), Vector3(-90, 0, 0)),
			"parts": {
				"arm_l": _xf(Vector3(-0.24, 1.10, 0), Vector3.ZERO, Vector3(1, 1, 1)),
				"arm_r": _xf(Vector3(0.24, 1.10, 0), Vector3.ZERO, Vector3(1, 1, 1)),
			},
		},
		# Flatten against a wall: thinned front-to-back, arms pressed in at the
		# sides and legs together so it stays a cohesive flat patch (no gaps).
		"wall_flatten": {
			"root": _xf(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.38)),
			"parts": {
				"head": _xf(Vector3(0, 1.54, 0)),
				"arm_l": _xf(Vector3(-0.26, 1.06, 0), Vector3(0, 0, 8)),
				"arm_r": _xf(Vector3(0.26, 1.06, 0), Vector3(0, 0, -8)),
				"leg_l": _xf(Vector3(-0.09, 0.42, 0)),
				"leg_r": _xf(Vector3(0.09, 0.42, 0)),
			},
		},
	}
