extends Node3D
class_name HiderBody
## The hider avatar — an original in-engine sculpt in the MECCHA style: soft
## one-piece white figure (round head, sloped shoulders, thick arms, sturdy
## legs) baked from smooth-blended volumes (see dev/bake_hider_mesh.gd) and
## auto-skinned to a real Skeleton3D (HiderRig.BONES).
##
## Because it has actual bones it moves like a person: walk/run cycles swing
## the arms opposite the legs with a body bob, idling breathes, jumps tuck the
## legs — all procedural, driven from the avatar's real velocity (net_player).
##
## Painting: the whole body is ONE paintable part ("body") with a cylindrical-
## unwrapped canvas; the brush raycast lands on a trimesh collider on the PAINT
## layer and stamps into the texture via the hit's face_index (O(1) UV lookup).
## Hiding poses (crouch/ball/lie/flatten/...) are whole-root transforms so the
## paint/shot collider keeps matching the silhouette; fun poses (raised hand,
## thinker, eagle...) articulate the bones.

const BLANK := Color(0.92, 0.92, 0.94)
const TEX_SIZE := 512
const PAINT_LAYER := 1 << 2
const MINIMAP_HIDE_LAYER := 1 << 9
const MESH_RES := "res://assets/characters/hider_mesh.res"

var parts: Dictionary = {}
var _materials: Dictionary = {}
var _images: Dictionary = {}
var _textures: Dictionary = {}
var _arrays: Dictionary = {}
var _base_xform: Dictionary = {}

var _parts_root: Node3D
var _skeleton: Skeleton3D
var _bone_idx: Dictionary = {}      # bone name -> index
var current_pose: String = "stand"
var _pose_bones: Dictionary = {}    # active pose's bone rotations (name -> Quaternion)
var _idle_t: float = 0.0
var _air_lean: float = 0.0          # -1..1 vertical motion (jump/fall) for leg tuck


func _ready() -> void:
	if parts.is_empty():
		_build()


func _build() -> void:
	_parts_root = Node3D.new()
	_parts_root.name = "PartsRoot"
	add_child(_parts_root)

	# Skeleton from the shared rig table (rest = parent-relative, identity basis).
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	_parts_root.add_child(_skeleton)
	for b in HiderRig.BONES:
		var idx := _skeleton.add_bone(b["name"])
		_bone_idx[b["name"]] = idx
		var parent: int = b["parent"]
		var parent_origin: Vector3 = HiderRig.BONES[parent]["origin"] if parent >= 0 else Vector3.ZERO
		if parent >= 0:
			_skeleton.set_bone_parent(idx, parent)
		_skeleton.set_bone_rest(idx, Transform3D(Basis(), b["origin"] - parent_origin))
	_skeleton.reset_bone_poses()

	var mesh: ArrayMesh = load(MESH_RES)
	var mi := MeshInstance3D.new()
	mi.name = "body"
	mi.mesh = mesh
	mi.skin = _skeleton.create_skin_from_rest_transforms()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = MINIMAP_HIDE_LAYER
	_skeleton.add_child(mi)
	mi.skeleton = mi.get_path_to(_skeleton)  # bind — the default path doesn't resolve

	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(BLANK)
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.6
	mat.metallic = 0.0
	mi.material_override = mat

	# Paint/shot surface: trimesh of the rest mesh on the PAINT layer. It follows
	# root-transform poses (crouch/flatten/...) since it's under PartsRoot.
	var static_body := StaticBody3D.new()
	static_body.collision_layer = PAINT_LAYER
	static_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var tri_shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	tri_shape.backface_collision = true  # paint/shoot from any angle
	cs.shape = tri_shape
	static_body.add_child(cs)
	mi.add_child(static_body)

	var arr := mesh.surface_get_arrays(0)
	parts["body"] = mi
	_materials["body"] = mat
	_images["body"] = img
	_textures["body"] = tex
	_arrays["body"] = {
		"v": arr[Mesh.ARRAY_VERTEX],
		"uv": arr[Mesh.ARRAY_TEX_UV],
		# baked mesh is non-indexed; store an empty index array (face_index -> vertex*3)
		"i": arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(),
	}
	for n in parts:
		_base_xform[n] = parts[n].transform


## --- Locomotion (procedural, bone-driven) ------------------------------------
## Called every frame by net_player with the avatar's real motion: `phase`
## advances with distance travelled, `amount` 0..1 is speed, `vy` vertical m/s.
func walk(phase: float, amount: float, vy: float = 0.0) -> void:
	if _skeleton == null:
		return
	_idle_t += get_process_delta_time()
	# Smoothed so per-frame vy noise (steps/slopes) can't jitter the posture.
	_air_lean = lerpf(_air_lean, clampf(vy / 8.0, -1.0, 1.0), 0.15)
	if current_pose != "stand":
		return  # a hide pose owns the body

	var amt := clampf(amount, 0.0, 1.0)
	var run := smoothstep(0.55, 1.0, amt)  # extra lean/energy at running speed
	var swing := sin(phase) * (0.28 + 0.20 * run) * amt  # walk ~±16°, run ~±27°
	var air := absf(_air_lean)

	# Legs stride (thigh swing + knee follow-through), tucking when airborne.
	var tuck := air * 0.7
	_rot("thigh_l", Vector3(1, 0, 0), swing - tuck * 0.6)
	_rot("thigh_r", Vector3(1, 0, 0), -swing - tuck * 0.6)
	_rot("shin_l", Vector3(1, 0, 0), maxf(-swing, 0.0) * 0.6 + tuck)
	_rot("shin_r", Vector3(1, 0, 0), maxf(swing, 0.0) * 0.6 + tuck)
	# Arms swing opposite the legs; breathe subtly when idle.
	var breathe := sin(_idle_t * 1.6) * 0.03 * (1.0 - amt)
	_rot("uarm_l", Vector3(1, 0, 0), -swing * 0.7 + breathe)
	_rot("uarm_r", Vector3(1, 0, 0), swing * 0.7 + breathe)
	_rot("farm_l", Vector3(1, 0, 0), -maxf(swing, 0.0) * 0.35)
	_rot("farm_r", Vector3(1, 0, 0), maxf(-swing, 0.0) * 0.35)
	# Torso: forward run lean + tiny counter-sway; head steadies the gaze.
	_rot("spine", Vector3(1, 0, 0), run * 0.10 + _air_lean * -0.10 + sin(_idle_t * 1.6) * 0.015 * (1.0 - amt))
	_rot("head", Vector3(1, 0, 0), -run * 0.06)
	# Per-step hip bob (weight) + a barely-there roll. No slow whole-body sway —
	# that read as drifting/wobbling when the camera orbited.
	var hips: int = _bone_idx["hips"]
	var rest: Vector3 = _skeleton.get_bone_rest(hips).origin
	_skeleton.set_bone_pose_position(hips, rest + Vector3(0, absf(sin(phase)) * 0.04 * amt, 0))
	_skeleton.set_bone_pose_rotation(hips, Quaternion(Vector3(0, 0, 1), sin(phase) * 0.018 * amt))


func _rot(bone: String, axis: Vector3, angle: float) -> void:
	_skeleton.set_bone_pose_rotation(_bone_idx[bone], Quaternion(axis.normalized(), angle))


## --- Freehand painting ------------------------------------------------------
func paint_at(part_name: String, hit_pos: Vector3, color: Color, radius_px: float, face_index: int = -1) -> bool:
	if not parts.has(part_name):
		return false
	var uv: Vector2
	if face_index >= 0 and _arrays.has(part_name):
		var local: Vector3 = parts[part_name].global_transform.affine_inverse() * hit_pos
		uv = _uv_from_face(part_name, face_index, local)
	else:
		uv = _uv_at(part_name, hit_pos)
	if uv == Vector2(-1, -1):
		return false
	_stamp(part_name, uv, color, radius_px)
	return true


func _uv_from_face(part_name: String, face_index: int, local: Vector3) -> Vector2:
	var data: Dictionary = _arrays[part_name]
	var v: PackedVector3Array = data["v"]
	var uv: PackedVector2Array = data["uv"]
	var idx: PackedInt32Array = data["i"]
	var ia: int
	var ib: int
	var ic: int
	if idx.size() > 0:
		var t := face_index * 3
		if t < 0 or t + 2 >= idx.size():
			return Vector2(-1, -1)
		ia = idx[t]
		ib = idx[t + 1]
		ic = idx[t + 2]
	else:
		ia = face_index * 3
		if ia < 0 or ia + 2 >= v.size():
			return Vector2(-1, -1)
		ib = ia + 1
		ic = ia + 2
	var bary := _barycentric(local, v[ia], v[ib], v[ic])
	return uv[ia] * bary.x + uv[ib] * bary.y + uv[ic] * bary.z


func _uv_at(part_name: String, world_pos: Vector3) -> Vector2:
	var mi: MeshInstance3D = parts[part_name]
	var local := mi.global_transform.affine_inverse() * world_pos
	var data: Dictionary = _arrays[part_name]
	var v: PackedVector3Array = data["v"]
	var uv: PackedVector2Array = data["uv"]
	# brute force nearest triangle (fallback path only)
	var best_uv := Vector2(-1, -1)
	var best_d := INF
	for t in range(0, v.size(), 3):
		var bary := _barycentric(local, v[t], v[t + 1], v[t + 2])
		if bary.x < -0.05 or bary.y < -0.05 or bary.z < -0.05:
			continue
		var n := (v[t + 1] - v[t]).cross(v[t + 2] - v[t])
		if n.length_squared() < 1e-12:
			continue
		var dist := absf((local - v[t]).dot(n.normalized()))
		if dist < best_d:
			best_d = dist
			best_uv = uv[t] * bary.x + uv[t + 1] * bary.y + uv[t + 2] * bary.z
	return best_uv


func _barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
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
	# Clamp the stamp to the limb atlas rect the hit landed in, so a brush on
	# an arm can never smear onto the chest region of the canvas.
	var x0 := 0
	var y0 := 0
	var x1 := TEX_SIZE
	var y1 := TEX_SIZE
	for grp in HiderRig.PAINT_GROUPS:
		var rect: Rect2 = grp["rect"]
		if rect.has_point(uv):
			x0 = int(rect.position.x * TEX_SIZE)
			y0 = int(rect.position.y * TEX_SIZE)
			x1 = int(rect.end.x * TEX_SIZE)
			y1 = int(rect.end.y * TEX_SIZE)
			break
	var r := int(ceil(radius_px))
	var r2 := radius_px * radius_px
	for y in range(maxi(y0, cy - r), mini(y1, cy + r + 1)):
		for x in range(maxi(x0, cx - r), mini(x1, cx + r + 1)):
			var dx := float(x - cx)
			var dy := float(y - cy)
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, color)
	_textures[part_name].update(img)


## --- Solid fill / gloss ------------------------------------------------------
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


## --- Serialization (network sync of the painted texture) ---------------------
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
		elif entry.has("c"):
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
	var bone_rots: Dictionary = pose.get("bones", {})

	_skeleton.reset_bone_poses()
	_pose_bones.clear()
	for bname in bone_rots:
		var e: Vector3 = bone_rots[bname]
		var q := Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
		_pose_bones[bname] = q
	if animated:
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_parts_root, "transform", root_xform, 0.25)
		var start := {}
		for bname in _pose_bones:
			start[bname] = _skeleton.get_bone_pose_rotation(_bone_idx[bname])
		tw.parallel().tween_method(func (t: float):
			for bname in _pose_bones:
				_skeleton.set_bone_pose_rotation(_bone_idx[bname], (start[bname] as Quaternion).slerp(_pose_bones[bname], t)),
			0.0, 1.0, 0.25)
	else:
		_parts_root.transform = root_xform
		for bname in _pose_bones:
			_skeleton.set_bone_pose_rotation(_bone_idx[bname], _pose_bones[bname])


func pose_names() -> Array:
	return PoseLibrary.POSES.keys()
