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
	var color: Variant = _color_of(hit.get("collider"))
	if color == null:
		_status.text = "No color on that surface."
		return
	_picker.color = color
	_on_color_changed(color)
	_eyedropper_active = false
	_status.text = "Sampled %s onto %s." % [color.to_html(false), _selected_part]


func _color_of(collider) -> Variant:
	# Find the first MeshInstance3D under the collider and read its albedo.
	if collider == null or not (collider is Node):
		return null
	var mi := _find_mesh(collider)
	if mi == null:
		return null
	var mat: Material = mi.material_override
	if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		mat = mi.get_active_material(0)
	if mat is StandardMaterial3D:
		return mat.albedo_color
	return null


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
