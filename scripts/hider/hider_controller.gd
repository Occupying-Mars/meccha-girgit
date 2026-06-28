extends CharacterBody3D
class_name HiderController
## Third-person hider: roam, then paint & pose during the prep phase.
##
## Third-person because the hider must SEE their own body to paint it and
## judge the disguise against the surroundings. Mouse orbits a spring-arm
## camera; WASD moves relative to camera yaw. The body visually faces the
## movement direction.
##
## Camera control / movement is suspended while a menu (paint/pose) is open,
## so the menu can capture the mouse.

@export var move_speed: float = 4.0
@export var mouse_sensitivity: float = 0.0025
@export var gravity: float = 18.0
@export var jump_velocity: float = 6.0

@onready var _yaw: Node3D = $CameraYaw
@onready var _pitch: Node3D = $CameraYaw/CameraPitch
@onready var body: HiderBody = $HiderBody

var input_enabled: bool = true
var _pitch_angle: float = -0.25


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		_yaw.rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch_angle = clampf(_pitch_angle - event.relative.y * mouse_sensitivity, -1.2, 0.6)
		_pitch.rotation.x = _pitch_angle


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif input_enabled and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var move := Vector3.ZERO
	if input_enabled:
		var in_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		# Map input to camera-relative world direction.
		var basis := _yaw.global_transform.basis
		var fwd := -basis.z
		var right := basis.x
		move = (right * in_dir.x + fwd * -in_dir.y)
		move.y = 0.0
		move = move.normalized()

	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed
	move_and_slide()

	# Face movement direction.
	if move.length() > 0.1:
		var target_yaw := atan2(move.x, move.z)
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, 0.2)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE
