extends Node3D
## Loads the downloaded Sponza glTF (CC-BY, Khronos sample) as a real test map
## and generates trimesh collision for every mesh so players collide, the
## seeker's gun ray hits walls, and hiders can wall-stick to real surfaces.
##
## A downloaded environment replaces the primitive arena for "real map" tests
## (camouflage against varied stone/cloth materials, sightlines, pillars).

const SPONZA_PATH := "res://assets/arenas/sponza/Sponza.gltf"


func _ready() -> void:
	# Loaded at runtime (not preloaded) so the project still opens on a fresh
	# clone before the asset is fetched. Run tools/download_sponza.py first.
	if not ResourceLoader.exists(SPONZA_PATH):
		push_warning("[sponza_map] Sponza not found — run tools/download_sponza.py")
		return
	var scene: PackedScene = load(SPONZA_PATH)
	var inst := scene.instantiate()
	add_child(inst)
	_add_collision(inst)


func _add_collision(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.create_trimesh_collision()  # adds a StaticBody3D + concave shape
		_add_collision(child)
