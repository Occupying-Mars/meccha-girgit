extends Node3D
class_name HiderBody
## Procedural pure-white bipedal "blob" the hider paints.
##
## Built from primitive mesh parts so each body surface can be colored
## independently. This is the PHASE 1 painting substrate: color-block per
## part (seeker.md explicitly prioritizes "color-block accuracy over fine
## detail"). A later phase upgrades to freehand texture painting on the same
## part layout.
##
## Each part is a MeshInstance3D with its own StandardMaterial3D, registered
## in `parts` by name. The painting system calls set_part_color() /
## set_part_gloss() and reads part_names() to drive its menu.

const BLANK := Color(0.92, 0.92, 0.94)  # near-white starting blob

## name -> MeshInstance3D
var parts: Dictionary = {}
## name -> StandardMaterial3D (unique per part so coloring is independent)
var _materials: Dictionary = {}


func _ready() -> void:
	if parts.is_empty():
		_build()


func _build() -> void:
	# Proportions for a ~1.7 m chunky humanoid. Root at feet (y = 0).
	# part_name: [mesh, local_position]
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
	add_child(mi)
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

func reset_to_blank() -> void:
	for n in _materials:
		_materials[n].albedo_color = BLANK
		_materials[n].metallic = 0.0
		_materials[n].roughness = 0.6
