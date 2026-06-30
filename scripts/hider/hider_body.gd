extends Node3D
class_name HiderBody
## Procedural white bipedal "blob" the hider FREEHAND-paints (MECCHA-style).
##
## Each body part is a primitive mesh with its OWN paint texture (an Image the
## brush stamps into) plus a trimesh collider on the PAINT layer so a cursor
## raycast can land on the visible surface. Painting = raycast the cursor onto
## a part, find the UV at that point, and stamp a brush disc into that part's
## Image. The camera orbits the body so every surface can be reached.
##
## Parts live under `_parts_root` so POSES can tilt/curl the figure without
## disturbing the controller's facing yaw.

const BLANK := Color(0.92, 0.92, 0.94)  # near-white starting blob
const TEX_SIZE := 256
const PAINT_LAYER := 1 << 2  # layer 3: only the paint cursor ray probes this
## Render layer 10 — body parts go here so the minimap camera can cull them and
## never reveal player positions (the seeker must not see hiders on the minimap).
const MINIMAP_HIDE_LAYER := 1 << 9

## name -> MeshInstance3D
var parts: Dictionary = {}
var _materials: Dictionary = {}          # name -> StandardMaterial3D
var _images: Dictionary = {}             # name -> Image (the paint canvas)
var _textures: Dictionary = {}           # name -> ImageTexture (albedo)
var _arrays: Dictionary = {}             # name -> {v, uv, i} local mesh data
var _base_xform: Dictionary = {}         # name -> Transform3D (STAND pose)

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
		m.radial_segments = 24
		m.rings = 12
		return m
	var sphere := func(radius: float) -> SphereMesh:
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 24
		m.rings = 16
		return m

	_add_part("head", sphere.call(0.17), Vector3(0, 1.57, 0))
	_add_part("torso", capsule.call(0.23, 0.74), Vector3(0, 1.08, 0))
	# Arms tucked closer to the torso (no floating gap) and a touch thicker.
	_add_part("arm_l", capsule.call(0.085, 0.60), Vector3(-0.255, 1.10, 0))
	_add_part("arm_r", capsule.call(0.085, 0.60), Vector3(0.255, 1.10, 0))
	# Legs a bit sturdier and set slightly apart for a stable stance.
	_add_part("leg_l", capsule.call(0.115, 0.76), Vector3(-0.13, 0.42, 0))
	_add_part("leg_r", capsule.call(0.115, 0.76), Vector3(0.13, 0.42, 0))

	for n in parts:
		_base_xform[n] = parts[n].transform


func _add_part(part_name: String, mesh: Mesh, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	# No body shadow — a person-shaped shadow on the floor/wall would give a
	# painted, posed hider away instantly.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = MINIMAP_HIDE_LAYER  # invisible to the minimap camera (see const)

	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(BLANK)
	var tex := ImageTexture.create_from_image(img)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.6
	mat.metallic = 0.0
	mi.material_override = mat
	_parts_root.add_child(mi)

	# Trimesh collider on the PAINT layer (moves with the part during poses).
	var body := StaticBody3D.new()
	body.collision_layer = PAINT_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	mi.add_child(body)

	parts[part_name] = mi
	_materials[part_name] = mat
	_images[part_name] = img
	_textures[part_name] = tex
	var arr := mesh.surface_get_arrays(0)
	_arrays[part_name] = {
		"v": arr[Mesh.ARRAY_VERTEX],
		"uv": arr[Mesh.ARRAY_TEX_UV],
		"i": arr[Mesh.ARRAY_INDEX],
	}


## --- Walk cycle -------------------------------------------------------------
## Procedural gait: swing the arms + legs around their joints (arms opposite the
## legs, like a real stride). Driven each frame by net_player from the avatar's
## speed (`amount` 0..1; 0 = standing still). Overlays on the STAND pose and is
## skipped while a hide pose owns the limb transforms.
func walk(phase: float, amount: float) -> void:
	if current_pose != "stand":
		return
	var amp := 0.6 * clampf(amount, 0.0, 1.0)
	_swing("leg_l", Vector3(-0.13, 0.80, 0.0), sin(phase) * amp)
	_swing("leg_r", Vector3(0.13, 0.80, 0.0), sin(phase + PI) * amp)
	_swing("arm_l", Vector3(-0.255, 1.40, 0.0), sin(phase + PI) * amp)
	_swing("arm_r", Vector3(0.255, 1.40, 0.0), sin(phase) * amp)


## Rotate a limb around a joint (its top) by `angle` on the X axis (fwd/back).
func _swing(part: String, pivot: Vector3, angle: float) -> void:
	if not parts.has(part):
		return
	var base: Transform3D = _base_xform[part]
	var rot := Basis(Vector3(1, 0, 0), angle)
	var origin: Vector3 = pivot + rot * (base.origin - pivot)
	parts[part].transform = Transform3D(rot * base.basis, origin)


## --- Freehand painting ------------------------------------------------------

## Stamp a brush disc of `color` onto whichever part owns `part_name` at the
## world-space `hit_pos`. `radius_px` is the brush radius in texture pixels.
func paint_at(part_name: String, hit_pos: Vector3, color: Color, radius_px: float) -> bool:
	if not parts.has(part_name):
		return false
	var uv := _uv_at(part_name, hit_pos)
	if uv == Vector2(-1, -1):
		return false
	_stamp(part_name, uv, color, radius_px)
	return true


func _uv_at(part_name: String, world_pos: Vector3) -> Vector2:
	var mi: MeshInstance3D = parts[part_name]
	var local := mi.global_transform.affine_inverse() * world_pos
	var data: Dictionary = _arrays[part_name]
	var v: PackedVector3Array = data["v"]
	var uv: PackedVector2Array = data["uv"]
	var idx: PackedInt32Array = data["i"]
	var best_uv := Vector2(-1, -1)
	var best_d := INF
	for t in range(0, idx.size(), 3):
		var a := v[idx[t]]
		var b := v[idx[t + 1]]
		var c := v[idx[t + 2]]
		var bary := _barycentric(local, a, b, c)
		if bary.x < -0.01 or bary.y < -0.01 or bary.z < -0.01:
			continue
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		var dist := absf((local - a).dot(n.normalized()))
		if dist < best_d:
			best_d = dist
			best_uv = uv[idx[t]] * bary.x + uv[idx[t + 1]] * bary.y + uv[idx[t + 2]] * bary.z
	return best_uv


func _barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Barycentric coords of p projected onto triangle (a,b,c).
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denom := d00 * d11 - d01 * d01
	if absf(denom) < 1e-12:
		return Vector3(-1, -1, -1)
	var vv := (d11 * d20 - d01 * d21) / denom
	var ww := (d00 * d21 - d01 * d20) / denom
	return Vector3(1.0 - vv - ww, vv, ww)


func _stamp(part_name: String, uv: Vector2, color: Color, radius_px: float) -> void:
	var img: Image = _images[part_name]
	var cx := int(round(clampf(uv.x, 0.0, 1.0) * (TEX_SIZE - 1)))
	var cy := int(round(clampf(uv.y, 0.0, 1.0) * (TEX_SIZE - 1)))
	var r := int(ceil(radius_px))
	var r2 := radius_px * radius_px
	for y in range(maxi(0, cy - r), mini(TEX_SIZE, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(TEX_SIZE, cx + r + 1)):
			var dx := float(x - cx)
			var dy := float(y - cy)
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, color)
	_textures[part_name].update(img)


## --- Solid fill / gloss (camo presets, caught flash, dummies) ----------------

func part_names() -> Array:
	return parts.keys()

func set_part_color(part_name: String, color: Color) -> void:
	if not _images.has(part_name):
		return
	_images[part_name].fill(color)
	_textures[part_name].update(_images[part_name])

func get_part_color(part_name: String) -> Color:
	if _images.has(part_name):
		return _images[part_name].get_pixel(TEX_SIZE / 2, TEX_SIZE / 2)
	return BLANK

func set_part_gloss(part_name: String, metallic: float, roughness: float) -> void:
	if _materials.has(part_name):
		_materials[part_name].metallic = clampf(metallic, 0.0, 1.0)
		_materials[part_name].roughness = clampf(roughness, 0.0, 1.0)

func get_part_gloss(part_name: String) -> Vector2:
	if _materials.has(part_name):
		return Vector2(_materials[part_name].metallic, _materials[part_name].roughness)
	return Vector2(0.0, 0.6)

func reset_to_blank() -> void:
	for n in _images:
		_images[n].fill(BLANK)
		_textures[n].update(_images[n])
		_materials[n].metallic = 0.0
		_materials[n].roughness = 0.6


## --- Serialization (network sync of the painted textures) --------------------

func get_paint_state() -> Dictionary:
	var state := {}
	for n in _images:
		var g: Vector2 = get_part_gloss(n)
		state[n] = {"png": _images[n].save_png_to_buffer(), "m": g.x, "r": g.y}
	return state

func apply_paint_state(state: Dictionary) -> void:
	for n in state:
		if not _images.has(n):
			continue
		var entry: Dictionary = state[n]
		if entry.has("png"):
			var img := Image.new()
			if img.load_png_from_buffer(entry["png"]) == OK:
				_images[n] = img
				_textures[n].update(img)
		elif entry.has("c"):  # legacy solid-color payload
			set_part_color(n, entry["c"])
		set_part_gloss(n, entry.get("m", 0.0), entry.get("r", 0.6))


## --- Pose API ----------------------------------------------------------------

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
