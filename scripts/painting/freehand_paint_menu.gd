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

var body: HiderBody
var _camera: Camera3D
var _yaw: Node3D
var _pitch: Node3D

var color: Color = Color(0.8, 0.3, 0.3)
var brush: float = 12.0
var _painting: bool = false
var _orbiting: bool = false
var _last_paint = null
var _pitch_a: float = 0.0


func setup(hider_body: HiderBody, camera: Camera3D, yaw: Node3D, pitch: Node3D) -> void:
	body = hider_body
	_camera = camera
	_yaw = yaw
	_pitch = pitch


func _ready() -> void:
	visible = false
	_picker.color = color
	_picker.color_changed.connect(func (c): color = c)
	_brush_slider.value = brush
	_brush_slider.value_changed.connect(func (v): brush = v)
	_metallic.value_changed.connect(_on_gloss)
	_roughness.value_changed.connect(_on_gloss)
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
		body.paint_at(String(part), hit["position"], color, brush)
