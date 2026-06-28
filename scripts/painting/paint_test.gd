extends Node3D
## Standalone freehand-paint sandbox (no networking) for iterating the brush.
##
## LMB drag  = paint the current color onto the blob where the cursor points
## RMB drag  = orbit the camera around the blob
## Wheel     = brush size
## 1/2/3/4   = quick colors (red/green/blue/yellow)
## C         = clear

var body: HiderBody
var _yaw: Node3D
var _pitch: Node3D
var _camera: Camera3D

var color: Color = Color(0.85, 0.2, 0.2)
var brush: float = 12.0
var _painting: bool = false
var _orbiting: bool = false
var _yaw_a: float = 0.0
var _pitch_a: float = -0.1
var _last_paint = null  # last screen pos painted (for stroke interpolation)


func _ready() -> void:
	# Environment + light
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.52, 0.58)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.72)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	add_child(sun)

	# The paintable blob
	body = HiderBody.new()
	add_child(body)
	if body.parts.is_empty():
		body._build()

	# Orbit camera rig focused on the chest
	_yaw = Node3D.new()
	_yaw.position = Vector3(0, 1.0, 0)
	add_child(_yaw)
	_pitch = Node3D.new()
	_yaw.add_child(_pitch)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 2.2)
	_pitch.add_child(_camera)
	_pitch.rotation.x = _pitch_a

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_painting = event.pressed
				if event.pressed:
					_last_paint = null
					_paint_stroke_to(event.position)
				else:
					_last_paint = null
			MOUSE_BUTTON_RIGHT:
				_orbiting = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				brush = clampf(brush + 2.0, 2.0, 48.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				brush = clampf(brush - 2.0, 2.0, 48.0)
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw_a -= event.relative.x * 0.01
			_pitch_a = clampf(_pitch_a - event.relative.y * 0.01, -1.3, 1.3)
			_yaw.rotation.y = _yaw_a
			_pitch.rotation.x = _pitch_a
		elif _painting:
			_paint_stroke_to(event.position)
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: color = Color(0.85, 0.2, 0.2)
			KEY_2: color = Color(0.3, 0.7, 0.3)
			KEY_3: color = Color(0.25, 0.45, 0.8)
			KEY_4: color = Color(0.85, 0.8, 0.2)
			KEY_C: body.reset_to_blank()


# Paint from the last point to this one, filling gaps so a drag is continuous.
func _paint_stroke_to(screen_pos: Vector2) -> void:
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
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 10.0)
	q.collision_mask = HiderBody.PAINT_LAYER
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is Node:
		var part := (collider as Node).get_parent().name
		body.paint_at(String(part), hit["position"], color, brush)


# Helper for headless tests: paint a continuous stroke down the body front.
func demo_stroke() -> void:
	var vp := get_viewport().get_visible_rect().size
	_last_paint = null
	for i in 40:
		var t := float(i) / 39.0
		_paint_stroke_to(Vector2(vp.x * 0.5, vp.y * (0.28 + 0.48 * t)))
	_last_paint = null
