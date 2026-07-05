extends Node3D
## "Blue Hour" — a Mediterranean cliffside terrace at dusk, just after a storm.
##
## Built to a reference photo: whitewashed houses cascading down a rocky cliff
## into a near-black sea with white surf on the rocks, a distant headland dotted
## with warm town lights across the bay, and a heavy navy storm sky with one pale
## break clearing on the horizon. Deep-blue "blue hour" mood, a few warm pinpoint
## lights as counterpoint, and faint distant lightning still flickering.
##
## Real CC0 models do the heavy lifting (Kenney / Quaternius houses, rocks, a
## boat — see tools/download_bluehour_assets.py; local KayKit furniture for the
## terrace porch). The sea, cliff base, headland, sky and mood are procedural.
##
## GAMEPLAY: the walkable area is the clifftop TERRACE (y=6) — a porch with
## seating, scattered whitewashed houses for cover, and a sea-facing railing.
## Below/beyond the railing (village cascade, sea, headland, sky) is backdrop.
##
## Walkable props are wrapped in StaticBody3D (AABB box collision) so characters
## collide and the seeker's eyedropper samples real surface colors. Layout is
## DETERMINISTIC (fixed seed) so every peer builds the same cliff; the lighting
## mood + lightning are local cosmetic effects.

const A := "res://assets/maps/bluehour/"     # downloaded CC0 props
const F := "res://assets/maps/furniture/"    # local CC0 KayKit furniture

const WHITE := Color(0.90, 0.89, 0.86)
const ROCK := Color(0.06, 0.07, 0.10)
const STONE := Color(0.60, 0.59, 0.58)
const SEA := Color(0.012, 0.03, 0.065)
const RAIL := Color(0.05, 0.05, 0.06)
const WINDOW := Color(1.0, 0.72, 0.36)
const FOAM := Color(0.85, 0.90, 0.95)

const TERRACE_Y := 6.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x8EAC4
	_build_sea()
	_build_cliff_base()
	_build_terrace()
	_build_railing()
	_build_houses()          # whitewashed cover on the terrace
	_build_cascade()         # backdrop villas stepping down to the sea
	_build_rocks()           # boulders along the cliff + shore
	_build_porch()           # table, chairs, lamp, cactus — the terrace nook
	_build_boat()            # moored below the terrace
	_build_headland()        # distant shore + town lights across the bay
	_build_surf()
	call_deferred("_setup_mood")   # must win over net_game's _apply_lighting()


# ------------------------------------------------------------ instanced models

## Instance a glTF/glb, scale + rotate + optionally whitewash it. Visual only.
func _prop(path: String, pos: Vector3, scale: float, yaw: float,
		white: float = 0.0) -> Node3D:
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst := ps.instantiate()
	inst.scale = Vector3(scale, scale, scale)
	inst.rotation_degrees = Vector3(0, yaw, 0)
	inst.position = pos
	add_child(inst)
	if white > 0.0:
		_whitewash(inst, white)
	return inst


## Instance a model AND wrap it in a StaticBody with a box collider from its
## AABB, so characters collide with it and can hide behind it.
func _prop_solid(path: String, pos: Vector3, scale: float, yaw: float,
		white: float = 0.0) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		return
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = Vector3(0, yaw, 0)
	body.scale = Vector3(scale, scale, scale)
	var inst := ps.instantiate()
	body.add_child(inst)
	add_child(body)
	if white > 0.0:
		_whitewash(inst, white)
	# Collider from the model's local AABB (in the body's pre-scale space).
	var ab := _aabb(inst)
	if ab.size != Vector3.ZERO:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = ab.size
		col.shape = shape
		col.position = ab.get_center()
		body.add_child(col)


## Push every material's albedo toward whitewashed, keeping per-surface variation
## (roofs stay relatively darker) so houses read as Cycladic white, not flat.
func _whitewash(node: Node, amt: float) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var mat: Material = node.get_active_material(i)
			if mat is StandardMaterial3D:
				var m: StandardMaterial3D = mat.duplicate()
				m.albedo_color = m.albedo_color.lerp(WHITE, amt)
				m.roughness = maxf(m.roughness, 0.85)
				node.set_surface_override_material(i, m)
	for c in node.get_children():
		_whitewash(c, amt)


func _aabb(node: Node, acc: Variant = null) -> AABB:
	if node is MeshInstance3D and node.mesh != null:
		var a: AABB = node.transform * node.get_aabb()
		acc = a if acc == null else (acc as AABB).merge(a)
	for c in node.get_children():
		acc = _aabb(c, acc)
	return acc if acc != null else AABB()


# ---------------------------------------------------------------- world pieces

func _build_sea() -> void:
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(600, 600)
	mi.mesh = mesh
	mi.position = Vector3(180, 0.0, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = SEA
	m.metallic = 0.30
	m.roughness = 0.06
	m.specular = 0.9
	mi.material_override = m
	mi.name = "Sea"
	add_child(mi)


func _build_cliff_base() -> void:
	# Solid dark rock mass the terrace sits on; its top stays just BELOW the
	# terrace surface (y=5) so no rock pokes up through the plaza.
	_static_box("Cliff", Vector3(-10, -1.5, 0), Vector3(44, 13, 34), ROCK, 0.95)


func _build_terrace() -> void:
	var body := StaticBody3D.new()
	body.name = "Terrace"
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(34, 1.0, 26)
	mi.mesh = mesh
	mi.material_override = _mat(STONE, 0.85)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(-10, TERRACE_Y - 0.5, 0)
	add_child(body)


func _build_railing() -> void:
	var edge_x := 6.8
	var top := TERRACE_Y + 1.0
	_visual_box("RailTop", Vector3(edge_x, top, 0), Vector3(0.12, 0.12, 26), RAIL, 0.4)
	_visual_box("RailMid", Vector3(edge_x, TERRACE_Y + 0.5, 0), Vector3(0.08, 0.08, 26), RAIL, 0.4)
	for i in 14:
		var z := -12.0 + i * 1.85
		_visual_box("RailPost", Vector3(edge_x, TERRACE_Y + 0.5, z), Vector3(0.1, 1.0, 0.1), RAIL, 0.4)
	# Invisible walls around the whole terrace so players stay on the plaza.
	# Terrace spans x[-27, 7], z[-13, 13]; the sea edge is the railing at +6.8.
	_wall_block(Vector3(edge_x, TERRACE_Y + 1.0, 0), Vector3(0.4, 3.0, 26))   # sea (railing)
	_wall_block(Vector3(-27.0, TERRACE_Y + 1.0, 0), Vector3(0.4, 3.0, 26))    # back
	_wall_block(Vector3(-10.0, TERRACE_Y + 1.0, -13.0), Vector3(34, 3.0, 0.4)) # left
	_wall_block(Vector3(-10.0, TERRACE_Y + 1.0, 13.0), Vector3(34, 3.0, 0.4))  # right


func _wall_block(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Bound"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)


func _build_houses() -> void:
	# Whitewashed cover on the terrace (solid). Kenney house_a is small (scale up);
	# Quaternius house_b is a taller building. Mixed sizes + yaws so a painted,
	# posed hider can read as "one more house".
	var y := TERRACE_Y
	_prop_solid(A + "house_a.glb", Vector3(-21, y, -6), 4.0, 25, 0.7)
	_prop_solid(A + "house_a.glb", Vector3(-14, y, 8), 3.4, -60, 0.7)
	_prop_solid(A + "house_a.glb", Vector3(-4, y, -9), 3.8, 110, 0.7)
	_prop_solid(A + "house_a.glb", Vector3(2, y, 6), 3.2, -20, 0.7)
	_prop_solid(A + "house_b.glb", Vector3(-18, y, 4), 1.4, 40, 0.6)
	_prop_solid(A + "house_b.glb", Vector3(-8, y, -3), 1.6, -110, 0.6)
	# a couple of warm windows + glows facing the sea
	for wp in [Vector3(-1.6, y + 1.4, -8.5), Vector3(-6.2, y + 1.6, -3.0), Vector3(0.2, y + 1.2, 6.4)]:
		_window(wp, Vector3(0.06, 0.7, 0.55))
		_warm_light(wp + Vector3(0.4, 0, 0), 5.5, 1.5)


func _build_cascade() -> void:
	# Backdrop: whitewashed houses stepping DOWN the cliff toward the sea.
	for i in 14:
		var t := float(i) / 13.0
		var x := 9.5 + t * 10.0
		var yy := 4.4 - t * 4.4
		var z := _rng.randf_range(-11, 11)
		var s := _rng.randf_range(2.2, 3.6) if _rng.randf() < 0.7 else _rng.randf_range(1.0, 1.4)
		var path := A + ("house_a.glb" if s > 1.6 else "house_b.glb")
		_prop(path, Vector3(x, yy, z), s, _rng.randf_range(0, 360), _rng.randf_range(0.5, 0.75))
		if _rng.randf() < 0.55:
			var wp := Vector3(x + 0.6, yy + 0.5, z)
			_window(wp, Vector3(0.05, 0.4, 0.35))
			if _rng.randf() < 0.5:
				_warm_light(wp, 3.5, 1.1)


func _build_rocks() -> void:
	# Dark wet boulders along the cliff edge + shore, catching the sky's sheen.
	_prop(A + "rock_big.glb", Vector3(8, 3.2, 10), 1.1, 20)
	_prop(A + "rock_big.glb", Vector3(9, 2.4, -9), 0.9, 200)
	_prop(A + "rock_big.glb", Vector3(11, 0.6, 2), 0.7, 90)
	_prop(A + "rock_flat.glb", Vector3(7.6, 5.4, -3), 2.2, 0)
	_prop(A + "rock_flat.glb", Vector3(8.4, 4.2, 6), 2.6, 40)
	for i in 8:
		_prop(A + "rocks_a.glb", Vector3(9.0 + _rng.randf_range(-1, 5), 0.25,
			_rng.randf_range(-11, 11)), _rng.randf_range(4, 8), _rng.randf_range(0, 360))


func _build_porch() -> void:
	# The terrace nook by the railing — a little table + chairs looking out at the
	# sea, a standing lamp, and a cactus in a pot. This is what sells "someone's
	# terrace" like the reference. Local CC0 KayKit furniture, natural scale.
	var y := TERRACE_Y
	_prop(F + "table_medium.gltf", Vector3(2.5, y, 3.0), 1.0, 0)
	_prop(F + "chair_A.gltf", Vector3(1.3, y, 3.0), 1.0, 90)
	_prop(F + "chair_A.gltf", Vector3(3.7, y, 3.0), 1.0, -90)
	_prop(F + "chair_B.gltf", Vector3(2.5, y, 4.3), 1.0, 180)
	_prop(F + "cactus_medium_A.gltf", Vector3(4.6, y, 1.2), 1.2, 0)
	_prop(F + "cactus_small_A.gltf", Vector3(-2.0, y, 5.4), 1.1, 0)
	# a standing lamp casts the nearest warm pool of light
	_prop(F + "lamp_standing.gltf", Vector3(4.2, y, 4.6), 1.0, 0)
	_warm_light(Vector3(4.2, y + 1.6, 4.6), 6.0, 2.0)


func _build_boat() -> void:
	# A small boat moored on the dark water below the terrace.
	_prop(A + "boat.glb", Vector3(13.5, 0.15, 4.5), 2.4, 200)


func _build_headland() -> void:
	var mass := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(150, 34, 60)
	mass.mesh = pm
	mass.position = Vector3(150, 17, -30)
	mass.rotation_degrees = Vector3(0, 24, 0)
	mass.material_override = _mat(Color(0.05, 0.07, 0.13), 1.0)
	mass.name = "Headland"
	add_child(mass)
	for i in 22:
		var x := 95.0 + _rng.randf_range(0, 120)
		var z := -55.0 + _rng.randf_range(-8, 30)
		var y := 1.5 + _rng.randf_range(0, 4)
		var dot := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.6, 0.6)
		dot.mesh = bm
		dot.position = Vector3(x, y, z)
		dot.material_override = _emissive(WINDOW, 3.5)
		add_child(dot)


func _build_surf() -> void:
	for i in 7:
		var mi := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(_rng.randf_range(3, 6), _rng.randf_range(2, 4))
		mi.mesh = mesh
		mi.position = Vector3(8.0 + _rng.randf_range(-1, 5), 0.12, _rng.randf_range(-11, 11))
		mi.material_override = _emissive(FOAM, 0.5)
		mi.name = "Surf"
		add_child(mi)



# ------------------------------------------------------------------- mood pass

func _setup_mood() -> void:
	var root := get_parent().get_parent()   # MapRoot -> NetGame root
	if root == null:
		return
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if we == null or we.environment == null:
		return
	var env := we.environment

	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# Luminous navy storm sky (the reference sky glows — it is NOT near-black),
	# with a brighter blue-grey break on the horizon.
	sm.sky_top_color = Color(0.055, 0.10, 0.21)
	sm.sky_horizon_color = Color(0.34, 0.46, 0.62)
	sm.ground_bottom_color = Color(0.02, 0.03, 0.06)
	sm.ground_horizon_color = Color(0.16, 0.24, 0.38)
	sm.sky_energy_multiplier = 1.15
	sm.ground_energy_multiplier = 0.5
	sm.sun_angle_max = 40.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.23, 0.36)
	env.ambient_light_energy = 1.3

	env.fog_enabled = true
	env.fog_light_color = Color(0.13, 0.21, 0.36)
	env.fog_light_energy = 0.7
	env.fog_density = 0.010
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.3

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.20, 0.28, 0.42)
	env.volumetric_fog_emission = Color(0.02, 0.03, 0.05)

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.10
	env.glow_hdr_threshold = 0.95

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 1.16
	env.adjustment_brightness = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95

	if sun != null:
		sun.light_color = Color(0.58, 0.68, 0.92)
		sun.light_energy = 0.5
		sun.rotation_degrees = Vector3(-9, -88, 0)
		sun.shadow_enabled = true
		_setup_lightning(root)


func _setup_lightning(root: Node) -> void:
	var bolt := DirectionalLight3D.new()
	bolt.name = "Lightning"
	bolt.light_color = Color(0.72, 0.80, 1.0)
	bolt.light_energy = 0.0
	bolt.rotation_degrees = Vector3(-22, -70, 0)
	root.add_child(bolt)
	var timer := Timer.new()
	timer.name = "LightningTimer"
	timer.wait_time = _rng.randf_range(7.0, 16.0)
	add_child(timer)
	timer.timeout.connect(func () -> void:
		if not is_instance_valid(bolt):
			return
		var tw := create_tween()
		tw.tween_property(bolt, "light_energy", 0.9, 0.05)
		tw.tween_property(bolt, "light_energy", 0.1, 0.06)
		tw.tween_property(bolt, "light_energy", 0.7, 0.04)
		tw.tween_property(bolt, "light_energy", 0.0, 0.35)
		timer.wait_time = _rng.randf_range(7.0, 16.0))
	timer.start()


# ----------------------------------------------------------------- primitives

func _static_box(node_name: String, pos: Vector3, size: Vector3, color: Color, rough: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color, rough)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _visual_box(node_name: String, pos: Vector3, size: Vector3, color: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, rough)
	add_child(mi)


func _window(pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Window"
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _emissive(WINDOW, 1.3)
	add_child(mi)


func _warm_light(pos: Vector3, rng: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.name = "WarmLight"
	l.position = pos
	l.light_color = Color(1.0, 0.74, 0.42)
	l.omni_range = rng
	l.light_energy = energy
	l.shadow_enabled = false
	add_child(l)


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.0
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 1.0
	return m
