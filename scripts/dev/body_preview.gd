extends Node3D
## Dev-only: close-up inspection of the sculpted HiderBody — front/side/back
## stills plus mid-stride walk frames, saved to D:/meccha_verify/body_*.png.

var _body: HiderBody


func _ready() -> void:
	_body = HiderBody.new()
	add_child(_body)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.65, 0.70, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 1.0
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	await _shoot(cam, Vector3(0, 0.95, 3.0), "body_front")
	await _shoot(cam, Vector3(3.0, 0.95, 0.0), "body_side")
	await _shoot(cam, Vector3(2.1, 1.1, -2.1), "body_back34")
	# Walk cycle frames: drive the gait directly at two stride phases.
	_body.walk(PI * 0.5, 1.0)
	await _shoot(cam, Vector3(2.2, 0.95, 2.2), "body_stride_a")
	_body.walk(PI * 1.5, 1.0)
	await _shoot(cam, Vector3(2.2, 0.95, 2.2), "body_stride_b")

	# Paint check: raycast at the chest/head/leg from the front (the exact
	# in-game path: PAINT_LAYER hit -> face_index -> stamp), then screenshot.
	_body.walk(0.0, 0.0)
	_body.apply_pose("stand", false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var painted := 0
	for target in [Vector3(0, 1.5, 0), Vector3(0, 1.0, 0), Vector3(-0.09, 0.4, 0), Vector3(0.19, 0.9, 0)]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(target.x, target.y, 3.0), Vector3(target.x, target.y, -3.0))
		q.collision_mask = HiderBody.PAINT_LAYER
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var part := (hit["collider"] as Node).get_parent().name
			if _body.paint_at(String(part), hit["position"], Color(0.85, 0.2, 0.15), 30.0, hit.get("face_index", -1)):
				painted += 1
	print("[body_preview] painted %d/4 spots" % painted)
	await _shoot(cam, Vector3(0.6, 0.95, 2.9), "body_painted")
	get_tree().quit()


func _shoot(cam: Camera3D, pos: Vector3, tag: String) -> void:
	cam.global_position = pos
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	for _i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("D:/meccha_verify/%s.png" % tag)
	print("[body_preview] saved ", tag)
