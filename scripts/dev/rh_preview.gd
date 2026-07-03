extends Node3D
func _ready() -> void:
	var body := HiderBody.new()
	add_child(body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.65, 0.7, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.global_position = Vector3(0.4, 1.0, 3.0)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	await get_tree().process_frame
	body.apply_pose("raised_hand", false)
	for _i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("D:/meccha_verify/rh_iso.png")
	print("[rh] saved")
	get_tree().quit()
