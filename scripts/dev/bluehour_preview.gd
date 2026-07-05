extends Node3D
## Dev-only: preview the Blue Hour cliffside map from a hero camera on the
## terrace, looking out over the sea toward the headland — the reference frame.
## Reproduces net_game's node layout (WorldEnvironment + Sun siblings, MapRoot ->
## Map) so the builder's deferred _setup_mood() finds them. Saves PNGs. Not
## shipped. Run windowed:  godot --path . scenes/dev/bluehour_preview.tscn --screen=1


func _ready() -> void:
	# Match net_game's hierarchy so bluehour_builder._setup_mood() resolves.
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = Environment.new()
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)

	var map_root := Node3D.new()
	map_root.name = "MapRoot"
	add_child(map_root)
	var map := Node3D.new()
	map.name = "Map"
	map.set_script(load("res://scripts/core/bluehour_builder.gd"))
	map_root.add_child(map)

	var cam := Camera3D.new()
	cam.fov = 62.0
	add_child(cam)
	# Standing near the sea-facing railing, looking down the coast: sea to the
	# right, cliff + village receding to the left, headland hazed in the distance.
	cam.global_position = Vector3(-9, 8.6, 9)
	cam.look_at(Vector3(34, 1.5, -26), Vector3.UP)
	cam.current = true

	var out_dir := "/tmp/meccha_verify"
	DirAccess.make_dir_recursive_absolute(out_dir)
	for _i in 50:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("bluehour_vista.png"))
	print("[bluehour_preview] saved vista")

	# Second angle: over the railing, down at the surf + rocks (finds the egg).
	cam.global_position = Vector3(-2, 8.0, 2)
	cam.look_at(Vector3(9, 0.5, -1), Vector3.UP)
	for _i in 16:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("bluehour_railing.png"))
	print("[bluehour_preview] saved railing")
	get_tree().quit()
