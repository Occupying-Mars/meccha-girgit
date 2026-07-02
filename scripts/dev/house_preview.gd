extends Node3D
## Dev-only: build the house map with the real quality stack (SSAO, bloom, ACES,
## soft shadows) under two cameras — an angled overhead (roof culled so the rooms
## show) and an eye-level interior — and save PNGs. Not shipped. Run windowed:
##   godot --path . scenes/test/house_preview.tscn --screen=1

const MINIMAP_HIDE_LAYER := 1 << 9


func _ready() -> void:
	var map := Node3D.new()
	map.set_script(load("res://scripts/core/house_builder.gd"))
	add_child(map)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.4
	sun.light_angular_distance = 1.2
	sun.shadow_bias = 0.05
	add_child(sun)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.50, 0.47, 0.44)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.6
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.6
	env.ssao_power = 1.7
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.07
	env.adjustment_saturation = 1.12
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.cull_mask = 0xFFFFF & ~MINIMAP_HIDE_LAYER  # hide the roof so rooms show
	add_child(cam)
	cam.global_position = Vector3(2, 30, 30)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	cam.current = true

	for _i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("D:/meccha_verify/house_preview.png")
	print("[house_preview] saved overhead")

	# Eye-level interior shot in the living room (room 0,0), roof visible.
	cam.fov = 70.0
	cam.cull_mask = 0xFFFFF
	cam.global_position = Vector3(-8, 1.4, -0.5)
	cam.look_at(Vector3(-8, 0.9, -6.0), Vector3.UP)
	for _i in 16:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("D:/meccha_verify/house_interior.png")
	print("[house_preview] saved interior")
	get_tree().quit()
