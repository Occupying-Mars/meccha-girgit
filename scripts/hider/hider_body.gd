extends Node3D
class_name HiderBody
## Procedural pure-white bipedal "blob" the hider paints and poses.
##
## Built from primitive mesh parts so each body surface can be colored
## independently (PHASE 1 painting: color-block per part — seeker.md
## prioritizes "color-block accuracy over fine detail").
##
## Parts live under `_parts_root` so POSES can tilt/curl the whole figure
## without disturbing the controller's facing yaw (which it applies to this
## HiderBody node). Poses break the humanoid silhouette and change which
## surfaces face outward (seeker.md §pose system).

const BLANK := Color(0.92, 0.92, 0.94)  # near-white starting blob

## name -> MeshInstance3D
var parts: Dictionary = {}
## name -> StandardMaterial3D (unique per part so coloring is independent)
var _materials: Dictionary = {}
## name -> Transform3D captured at build (the STAND pose)
var _base_xform: Dictionary = {}

var _parts_root: Node3D
var current_pose: String = "stand"


func _ready() -> void:
	if parts.is_empty():
		_build()


func _build() -> void:
	_parts_root = Node3D.new()
	_parts_root.name = "PartsRoot"
	add_child(_parts_root)

	var capsule := func(radius: float, height: float) -> CapsuleMesh:
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = height
		return m
	var sphere := func(radius: float) -> SphereMesh:
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		return m

	_add_part("head", sphere.call(0.16), Vector3(0, 1.56, 0))
	_add_part("torso", capsule.call(0.22, 0.72), Vector3(0, 1.08, 0))
	_add_part("arm_l", capsule.call(0.075, 0.62), Vector3(-0.30, 1.10, 0))
	_add_part("arm_r", capsule.call(0.075, 0.62), Vector3(0.30, 1.10, 0))
	_add_part("leg_l", capsule.call(0.10, 0.78), Vector3(-0.12, 0.42, 0))
	_add_part("leg_r", capsule.call(0.10, 0.78), Vector3(0.12, 0.42, 0))

	for n in parts:
		_base_xform[n] = parts[n].transform


func _add_part(part_name: String, mesh: Mesh, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BLANK
	mat.roughness = 0.6
	mat.metallic = 0.0
	mi.material_override = mat
	_parts_root.add_child(mi)
	parts[part_name] = mi
	_materials[part_name] = mat


## --- Painting API -----------------------------------------------------------

func part_names() -> Array:
	return parts.keys()

func set_part_color(part_name: String, color: Color) -> void:
	if _materials.has(part_name):
		_materials[part_name].albedo_color = color

func get_part_color(part_name: String) -> Color:
	if _materials.has(part_name):
		return _materials[part_name].albedo_color
	return BLANK

func set_part_gloss(part_name: String, metallic: float, roughness: float) -> void:
	if _materials.has(part_name):
		_materials[part_name].metallic = clampf(metallic, 0.0, 1.0)
		_materials[part_name].roughness = clampf(roughness, 0.0, 1.0)

func get_part_gloss(part_name: String) -> Vector2:
	if _materials.has(part_name):
		return Vector2(_materials[part_name].metallic, _materials[part_name].roughness)
	return Vector2(0.0, 0.6)

## Full paint state for one body (network/serialization friendly).
func get_paint_state() -> Dictionary:
	var state := {}
	for n in _materials:
		var g: Vector2 = get_part_gloss(n)
		state[n] = {"c": _materials[n].albedo_color, "m": g.x, "r": g.y}
	return state

func apply_paint_state(state: Dictionary) -> void:
	for n in state:
		set_part_color(n, state[n]["c"])
		set_part_gloss(n, state[n]["m"], state[n]["r"])

func reset_to_blank() -> void:
	for n in _materials:
		_materials[n].albedo_color = BLANK
		_materials[n].metallic = 0.0
		_materials[n].roughness = 0.6


## --- Pose API ----------------------------------------------------------------
## A pose is { "root": Transform3D, "parts": { part_name: Transform3D } }.
## Parts not listed return to their base (STAND) transform. New poses are
## added to PoseLibrary.POSES — the system is designed to be extensible.

func apply_pose(pose_name: String, animated: bool = true) -> void:
	if not PoseLibrary.POSES.has(pose_name):
		push_warning("[hider_body] unknown pose: " + pose_name)
		return
	current_pose = pose_name
	var pose: Dictionary = PoseLibrary.POSES[pose_name]
	var root_xform: Transform3D = pose.get("root", Transform3D.IDENTITY)
	var part_overrides: Dictionary = pose.get("parts", {})

	if animated:
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_parts_root, "transform", root_xform, 0.25)
		for n in parts:
			var target: Transform3D = part_overrides.get(n, _base_xform[n])
			tw.tween_property(parts[n], "transform", target, 0.25)
	else:
		_parts_root.transform = root_xform
		for n in parts:
			parts[n].transform = part_overrides.get(n, _base_xform[n])

func pose_names() -> Array:
	return PoseLibrary.POSES.keys()
