extends CanvasLayer
class_name FreehandPaintMenu
## Freehand paint mode UI + interaction (MECCHA-style).
##
## While open:
##   LMB drag (over the 3D view) = brush the current color onto your body
##   RMB drag                    = orbit the camera around yourself
##   Mouse wheel                 = brush size
## The ColorPicker provides the color wheel / RGB / HSV / hex / swatches and a
## built-in screen eyedropper (click the dropper, then click any surface to
## sample its on-screen color). Gloss sliders + Clear round it out.

signal closed

const RETICLE_SCALE := 1.3  # screen px per texture-pixel of brush radius

@onready var _panel: Panel = $Panel
@onready var _reticle: BrushReticle = $Reticle
@onready var _picker: ColorPicker = $Panel/Margin/VBox/ColorPicker
@onready var _brush_slider: HSlider = $Panel/Margin/VBox/BrushRow/BrushSlider
@onready var _metallic: HSlider = $Panel/Margin/VBox/MetallicRow/MetallicSlider
@onready var _roughness: HSlider = $Panel/Margin/VBox/RoughnessRow/RoughnessSlider
@onready var _eyedropper_btn: Button = $Panel/Margin/VBox/EyedropperBtn
@onready var _hint: Label = $Panel/Margin/VBox/Hint

var body: HiderBody
var _camera: Camera3D
var _yaw: Node3D
var _pitch: Node3D

var color: Color = Color(0.8, 0.3, 0.3)
var brush: float = 12.0
var _painting: bool = false
var _orbiting: bool = false
var _eyedropper_active: bool = false
var _last_paint = null
var _pitch_a: float = 0.0


func setup(hider_body: HiderBody, camera: Camera3D, yaw: Node3D, pitch: Node3D) -> void:
	body = hider_body
	_camera = camera
	_yaw = yaw
	_pitch = pitch


func _ready() -> void:
	visible = false
	# Compact tool-palette look — smaller text tightens the whole panel.
	var th := Theme.new()
	th.default_font_size = 13
	_panel.theme = th
	# Always-visible swatch palette of handy camo colors (dungeon stone / wood /
	# metal + a spectrum) so you can grab common tones fast, like the reference.
	_build_swatches()
	_picker.color = color
	_picker.color_changed.connect(func (c): color = c)
	_brush_slider.value = brush
	_brush_slider.value_changed.connect(func (v): brush = v)
	_metallic.value_changed.connect(_on_gloss)
	_roughness.value_changed.connect(_on_gloss)
	_eyedropper_btn.pressed.connect(_on_eyedropper_pressed)
	$Panel/Margin/VBox/ClearBtn.pressed.connect(func (): body.reset_to_blank())


func open() -> void:
	visible = true
	_painting = false
	_orbiting = false
	_pitch_a = _pitch.rotation.x


func _process(delta: float) -> void:
	if not visible:
		return
	# Drive the brush reticle: hide it over the panel, show its size + color.
	var over := _over_panel(get_viewport().get_mouse_position())
	_reticle.visible = not over
	_reticle.radius = brush * RETICLE_SCALE
	_reticle.paint_color = color

	# Trackpad-friendly orbit with arrow keys (no right-click-drag needed).
	var oy := 0.0
	var op := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT): oy += 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT): oy -= 1.0
	if Input.is_physical_key_pressed(KEY_UP): op -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN): op += 1.0
	if oy != 0.0 or op != 0.0:
		_yaw.rotate_y(oy * 1.8 * delta)
		_pitch_a = clampf(_pitch_a + op * 1.8 * delta, -1.3, 1.3)
		_pitch.rotation.x = _pitch_a


func close() -> void:
	visible = false
	closed.emit()


func _build_swatches() -> void:
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	for col in _palette():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(0, 22)
		sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sw.tooltip_text = "#" + col.to_html(false)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(1)
		sb.border_color = Color(0, 0, 0, 0.35)
		sw.add_theme_stylebox_override("normal", sb)
		sw.add_theme_stylebox_override("hover", sb)
		sw.add_theme_stylebox_override("pressed", sb)
		sw.add_theme_stylebox_override("focus", sb)
		sw.pressed.connect(_pick_swatch.bind(col))
		grid.add_child(sw)
	var vbox: VBoxContainer = $Panel/Margin/VBox
	vbox.add_child(grid)
	vbox.move_child(grid, _picker.get_index() + 1)  # right under the picker


func _pick_swatch(c: Color) -> void:
	color = c
	_picker.color = c


func _palette() -> Array:
	return [
		Color8(24, 24, 28), Color8(64, 64, 70), Color8(110, 110, 118), Color8(165, 165, 172), Color8(228, 228, 232),
		Color8(92, 82, 70), Color8(126, 110, 92), Color8(158, 140, 118),       # stone
		Color8(70, 44, 26), Color8(116, 72, 40), Color8(166, 110, 64), Color8(202, 150, 96),  # wood
		Color8(180, 60, 42), Color8(212, 120, 44), Color8(224, 184, 72),       # warm
		Color8(40, 72, 112), Color8(48, 112, 142), Color8(58, 140, 92),        # cool
		Color8(150, 44, 92), Color8(92, 52, 140), Color8(44, 150, 150),        # accents
		Color8(226, 192, 160), Color8(120, 130, 140),                          # skin / metal
	]


func _on_gloss(_v: float) -> void:
	for n in body.part_names():
		body.set_part_gloss(n, _metallic.value, _roughness.value)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# Don't paint when interacting with the panel UI.
				if _over_panel(event.position):
					return
				if _eyedropper_active:
					if event.pressed:
						_sample_world(event.position)
					get_viewport().set_input_as_handled()
					return
				_painting = event.pressed
				_last_paint = null
				if event.pressed:
					_stroke_to(event.position)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_orbiting = event.pressed
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				brush = clampf(brush + 2.0, 2.0, 48.0)
				_brush_slider.set_value_no_signal(brush)
			MOUSE_BUTTON_WHEEL_DOWN:
				brush = clampf(brush - 2.0, 2.0, 48.0)
				_brush_slider.set_value_no_signal(brush)
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw.rotate_y(-event.relative.x * 0.01)
			_pitch_a = clampf(_pitch_a - event.relative.y * 0.01, -1.3, 1.3)
			_pitch.rotation.x = _pitch_a
		elif _painting and not _over_panel(event.position):
			_stroke_to(event.position)


func _over_panel(pos: Vector2) -> bool:
	return _panel.get_global_rect().has_point(pos)


func _stroke_to(screen_pos: Vector2) -> void:
	if _last_paint == null:
		_paint_at(screen_pos)
	else:
		var prev: Vector2 = _last_paint
		var d := prev.distance_to(screen_pos)
		var step := maxf(brush * 0.4, 2.0)
		var n := maxi(1, int(d / step))
		for i in range(1, n + 1):
			_paint_at(prev.lerp(screen_pos, float(i) / n))
	_last_paint = screen_pos


func _paint_at(screen_pos: Vector2) -> void:
	if _camera == null:
		return
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 10.0)
	q.collision_mask = HiderBody.PAINT_LAYER
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is Node:
		var part := (collider as Node).get_parent().name
		body.paint_at(String(part), hit["position"], color, brush, hit.get("face_index", -1))


# ---------------------------------------------------------------------------
# Eyedropper: sample the EXACT base color of a world surface (texture/albedo),
# independent of lighting / shadows / post-processing. The physics ray only
# tells us WHICH object is under the cursor; the precise surface point + UV come
# from intersecting the camera ray against the real mesh triangles.
# ---------------------------------------------------------------------------
func _on_eyedropper_pressed() -> void:
	_eyedropper_active = true
	_hint.text = "EYEDROPPER: click any surface to grab its exact color."


func _sample_world(screen_pos: Vector2) -> void:
	_eyedropper_active = false
	if _camera == null:
		return
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	q.collision_mask = 0xFFFFFFFF & ~HiderBody.PAINT_LAYER  # world, not the body
	var pb := _player_body()
	if pb != null:
		q.exclude = [pb.get_rid()]
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_hint.text = "Eyedropper missed — aim straight at a surface."
		return
	var picked: Variant = _color_at(hit.get("collider"), from, dir)
	if picked == null:
		_hint.text = "Couldn't read that surface's color."
		return
	color = picked
	_picker.color = picked
	_hint.text = "Sampled #%s — now paint with it." % picked.to_html(false)


func _player_body() -> CollisionObject3D:
	var n: Node = body
	while n != null:
		if n is CollisionObject3D:
			return n
		n = n.get_parent()
	return null


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
		var inv: Transform3D = mi.global_transform.affine_inverse()
		var lo: Vector3 = inv * ray_from
		var ld: Vector3 = inv.basis * ray_dir
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
					i0 = indices[t * 3]; i1 = indices[t * 3 + 1]; i2 = indices[t * 3 + 2]
				else:
					i0 = t * 3; i1 = t * 3 + 1; i2 = t * 3 + 2
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
		return _flat_color(meshes[0])
	return _color_from_material(_material_of(best_mi, best_surface), best_uv, best_has_uv)


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


func _color_from_material(mat: Material, uv: Vector2, has_uv: bool) -> Variant:
	if not (mat is StandardMaterial3D) and not (mat is ORMMaterial3D):
		return null
	var sm: BaseMaterial3D = mat
	var tint: Color = sm.albedo_color
	var tex: Texture2D = sm.albedo_texture
	if tex == null:
		return Color(tint.r, tint.g, tint.b, 1.0)
	if sm.uv1_triplanar or not has_uv:
		uv = Vector2(0.5, 0.5)
	var img: Image = tex.get_image()
	if img == null:
		return Color(tint.r, tint.g, tint.b, 1.0)
	if img.is_compressed() and img.decompress() != OK:
		return Color(tint.r, tint.g, tint.b, 1.0)
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return Color(tint.r, tint.g, tint.b, 1.0)
	var px: int = clampi(int(fposmod(uv.x, 1.0) * w), 0, w - 1)
	var py: int = clampi(int(fposmod(uv.y, 1.0) * h), 0, h - 1)
	var texel: Color = img.get_pixel(px, py)
	return Color(texel.r * tint.r, texel.g * tint.g, texel.b * tint.b, 1.0)


func _flat_color(mi: MeshInstance3D) -> Variant:
	var mat: Material = _material_of(mi, 0)
	if not (mat is StandardMaterial3D) and not (mat is ORMMaterial3D):
		return null
	var sm: BaseMaterial3D = mat
	if sm.albedo_texture != null:
		return _color_from_material(sm, Vector2(0.5, 0.5), false)
	var c: Color = sm.albedo_color
	return Color(c.r, c.g, c.b, 1.0)


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
	var vv: float = (d11 * d20 - d01 * d21) / denom
	var ww: float = (d00 * d21 - d01 * d20) / denom
	var uu: float = 1.0 - vv - ww
	return ua * uu + ub * vv + uc * ww


func _find_meshes(node: Node, out: Array = []) -> Array:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_find_meshes(child, out)
	return out
