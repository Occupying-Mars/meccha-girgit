extends CanvasLayer
class_name PaintMenu
## Hider painting UI (seeker.md §hider painting system).
##
## PHASE 1: color-block per body part. Select a part, then:
##   - pick a color (ColorPicker = wheel + RGB + HSV, built in)
##   - set gloss (metallic / roughness sliders) to match surroundings
##   - or use the eyedropper ("spoid") to sample the exact color of any
##     wall / floor / prop in the world via a 3D raycast.
##
## Opened/closed by the hider controller; while open the world input is
## suspended and the mouse is freed so the menu is usable.

signal closed

@onready var _part_list: VBoxContainer = $Panel/Margin/VBox/PartScroll/PartList
@onready var _picker: ColorPicker = $Panel/Margin/VBox/ColorPicker
@onready var _metallic: HSlider = $Panel/Margin/VBox/MetallicRow/MetallicSlider
@onready var _roughness: HSlider = $Panel/Margin/VBox/RoughnessRow/RoughnessSlider
@onready var _eyedropper_btn: Button = $Panel/Margin/VBox/EyedropperBtn
@onready var _status: Label = $Panel/Margin/VBox/Status

var body: HiderBody
var _selected_part: String = ""
var _eyedropper_active: bool = false
var _part_buttons: Dictionary = {}


func setup(hider_body: HiderBody) -> void:
	body = hider_body
	_build_part_buttons()
	_select_part(body.part_names()[0] if body.part_names().size() > 0 else "")


func _ready() -> void:
	visible = false
	_picker.color_changed.connect(_on_color_changed)
	_metallic.value_changed.connect(_on_gloss_changed)
	_roughness.value_changed.connect(_on_gloss_changed)
	_eyedropper_btn.pressed.connect(_on_eyedropper_pressed)


func open() -> void:
	visible = true
	_eyedropper_active = false
	_refresh_from_part()
	_status.text = "Pick a part, then paint or sample."


func close() -> void:
	visible = false
	_eyedropper_active = false
	closed.emit()


func _build_part_buttons() -> void:
	for c in _part_list.get_children():
		c.queue_free()
	_part_buttons.clear()
	for part_name in body.part_names():
		var b := Button.new()
		b.text = part_name
		b.toggle_mode = true
		b.pressed.connect(_select_part.bind(part_name))
		_part_list.add_child(b)
		_part_buttons[part_name] = b


func _select_part(part_name: String) -> void:
	_selected_part = part_name
	for n in _part_buttons:
		_part_buttons[n].button_pressed = (n == part_name)
	_refresh_from_part()


func _refresh_from_part() -> void:
	if _selected_part == "" or body == null:
		return
	# Reflect the part's current color without re-emitting change signals.
	_picker.color = body.get_part_color(_selected_part)


func _on_color_changed(c: Color) -> void:
	if _selected_part != "" and body != null:
		body.set_part_color(_selected_part, c)


func _on_gloss_changed(_v: float) -> void:
	if _selected_part != "" and body != null:
		body.set_part_gloss(_selected_part, _metallic.value, _roughness.value)


func _on_eyedropper_pressed() -> void:
	_eyedropper_active = true
	_status.text = "EYEDROPPER: click any surface to sample its color."


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _eyedropper_active and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_sample_world(event.position)
		get_viewport().set_input_as_handled()


func _sample_world(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	# Exclude the hider so we sample the world, not the body.
	if body != null:
		query.exclude = [body.get_parent().get_rid()] if body.get_parent() is CollisionObject3D else []
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_status.text = "Eyedropper missed — aim at a surface."
		return
	# Sample the EXACT base color from material data (texture/albedo), not the
	# lit/post-processed framebuffer. We use the physics hit only to know WHICH
	# object is under the cursor; the precise surface point + UV come from
	# intersecting the camera ray against the real mesh triangles.
	var color: Variant = _color_at(hit.get("collider"), from, dir)
	if color == null:
		_status.text = "No color on that surface."
		return
	_picker.color = color
	_on_color_changed(color)
	_eyedropper_active = false
	_status.text = "Sampled %s onto %s." % [color.to_html(false), _selected_part]


## Resolve the surface base color of the object under the cursor by intersecting
## the camera ray (ray_from, ray_dir) against every MeshInstance3D triangle.
## Returns a Color (alpha forced to 1) or null if nothing usable was found.
func _color_at(collider, ray_from: Vector3, ray_dir: Vector3) -> Variant:
	if collider == null or not (collider is Node):
		return null
	var meshes := _find_meshes(collider)
	if meshes.is_empty():
		return null

	var best_t: float = INF
	var best_mi: MeshInstance3D = null
	var best_surface: int = -1
	var best_uv: Vector2 = Vector2.ZERO
	var best_has_uv: bool = false

	for mi in meshes:
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		# Camera ray in this instance's local space.
		var inv: Transform3D = mi.global_transform.affine_inverse()
		var lo: Vector3 = inv * ray_from
		var ld: Vector3 = (inv.basis * ray_dir)
		if ld.length() < 0.0000001:
			continue
		ld = ld.normalized()
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts == null or verts.size() == 0:
				continue
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var has_uv: bool = uvs != null and uvs.size() == verts.size()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var tri_count: int = (indices.size() / 3) if (indices != null and indices.size() > 0) else (verts.size() / 3)
			for t in tri_count:
				var i0: int
				var i1: int
				var i2: int
				if indices != null and indices.size() > 0:
					i0 = indices[t * 3]
					i1 = indices[t * 3 + 1]
					i2 = indices[t * 3 + 2]
				else:
					i0 = t * 3
					i1 = t * 3 + 1
					i2 = t * 3 + 2
				var a: Vector3 = verts[i0]
				var b: Vector3 = verts[i1]
				var c: Vector3 = verts[i2]
				var ipt: Variant = Geometry3D.ray_intersects_triangle(lo, ld, a, b, c)
				if ipt == null:
					continue
				var dist: float = (ipt - lo).length()
				if dist >= best_t:
					continue
				best_t = dist
				best_mi = mi
				best_surface = s
				best_has_uv = has_uv
				if has_uv:
					best_uv = _bary_uv(ipt, a, b, c, uvs[i0], uvs[i1], uvs[i2])

	if best_mi == null:
		# Ray missed every triangle (e.g. collider box bigger than mesh).
		# Fall back to the first mesh's flat/base color so we still return
		# something plausible rather than failing outright.
		return _flat_color(meshes[0])

	var mat: Material = _material_of(best_mi, best_surface)
	return _color_from_material(mat, best_uv, best_has_uv)


## Pick the active material for a mesh surface (override > surface > active).
func _material_of(mi: MeshInstance3D, surface: int) -> Material:
	if mi.material_override != null:
		return mi.material_override
	if surface >= 0:
		var sm := mi.get_surface_override_material(surface)
		if sm != null:
			return sm
		if mi.mesh != null and surface < mi.mesh.get_surface_count():
			return mi.get_active_material(surface)
	if mi.mesh != null and mi.mesh.get_surface_count() > 0:
		return mi.get_active_material(0)
	return null


## Extract the base color from a material at the given UV.
func _color_from_material(mat: Material, uv: Vector2, has_uv: bool) -> Variant:
	if not (mat is StandardMaterial3D) and not (mat is ORMMaterial3D):
		return null
	var sm: BaseMaterial3D = mat
	var tint: Color = sm.albedo_color
	var tex: Texture2D = sm.albedo_texture
	if tex == null:
		# Flat-colored procedural surface — current behavior preserved.
		return Color(tint.r, tint.g, tint.b, 1.0)

	# Triplanar materials don't use the mesh UVs meaningfully. Without a real
	# projection we can't compute the texel, so sample the texture center.
	if sm.uv1_triplanar or not has_uv:
		uv = Vector2(0.5, 0.5)

	var img: Image = tex.get_image()
	if img == null:
		return Color(tint.r, tint.g, tint.b, 1.0)
	if img.is_compressed():
		if img.decompress() != OK:
			return Color(tint.r, tint.g, tint.b, 1.0)
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return Color(tint.r, tint.g, tint.b, 1.0)
	# Wrap UVs into [0,1) then to pixel coords.
	var u: float = fposmod(uv.x, 1.0)
	var v: float = fposmod(uv.y, 1.0)
	var px: int = clampi(int(u * w), 0, w - 1)
	var py: int = clampi(int(v * h), 0, h - 1)
	var texel: Color = img.get_pixel(px, py)
	# Multiply by albedo tint (white = no-op for KayKit).
	var out := Color(texel.r * tint.r, texel.g * tint.g, texel.b * tint.b, 1.0)
	return out


## Flat base color of the first mesh under a collider (no ray needed).
## Used as a fallback and by headless tests; mirrors the pre-UV behavior.
func _color_of(collider) -> Variant:
	if collider == null or not (collider is Node):
		return null
	var mi := _find_mesh(collider)
	if mi == null:
		return null
	return _flat_color(mi)


## Flat/base color of a mesh (used when ray missed triangles but we still want
## a sensible result). Returns null if no readable material.
func _flat_color(mi: MeshInstance3D) -> Variant:
	var mat: Material = _material_of(mi, 0)
	if not (mat is StandardMaterial3D) and not (mat is ORMMaterial3D):
		return null
	var sm: BaseMaterial3D = mat
	if sm.albedo_texture != null:
		return _color_from_material(sm, Vector2(0.5, 0.5), false)
	var c: Color = sm.albedo_color
	return Color(c.r, c.g, c.b, 1.0)


## Barycentric UV interpolation of point p inside triangle (a,b,c).
func _bary_uv(p: Vector3, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> Vector2:
	var v0: Vector3 = b - a
	var v1: Vector3 = c - a
	var v2: Vector3 = p - a
	var d00: float = v0.dot(v0)
	var d01: float = v0.dot(v1)
	var d11: float = v1.dot(v1)
	var d20: float = v2.dot(v0)
	var d21: float = v2.dot(v1)
	var denom: float = d00 * d11 - d01 * d01
	if absf(denom) < 0.0000001:
		return ua
	var v: float = (d11 * d20 - d01 * d21) / denom
	var w: float = (d00 * d21 - d01 * d20) / denom
	var u: float = 1.0 - v - w
	return ua * u + ub * v + uc * w


## Collect all MeshInstance3D nodes under a node (objects may nest several).
func _find_meshes(node: Node, out: Array = []) -> Array:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_find_meshes(child, out)
	return out


## Backwards-compatible: first MeshInstance3D under a node.
func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
