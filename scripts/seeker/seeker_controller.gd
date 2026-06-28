extends CharacterBody3D
class_name SeekerController
## First-person seeker (seeker.md §seeker system).
##
## No flashlight — detection is purely visual. A hitscan gun eliminates a
## hider on a clean hit. The ray walks up from whatever collider it strikes to
## find a node in the "hider" group, so per-part or capsule colliders both work.

signal hider_hit(hider: Node)
signal shot_fired(hit: bool)

@export var move_speed: float = 5.0
@export var mouse_sensitivity: float = 0.0025
@export var gravity: float = 18.0
@export var jump_velocity: float = 6.0
@export var gun_range: float = 60.0

@onready var _camera: Camera3D = $Camera3D
@onready var _muzzle: RayCast3D = $Camera3D/Muzzle

var input_enabled: bool = true
var _pitch: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_muzzle.target_position = Vector3(0, 0, -gun_range)
	_muzzle.collide_with_areas = true


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.4, 1.4)
		_camera.rotation.x = _pitch
	elif event.is_action_pressed("fire"):
		_fire()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif input_enabled and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var move := Vector3.ZERO
	if input_enabled:
		var in_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var basis := global_transform.basis
		move = (basis.x * in_dir.x + (-basis.z) * -in_dir.y)
		move.y = 0.0
		move = move.normalized()

	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed
	move_and_slide()


func _fire() -> void:
	_muzzle.force_raycast_update()
	if not _muzzle.is_colliding():
		shot_fired.emit(false)
		return
	var collider := _muzzle.get_collider()
	var hider := _find_hider(collider)
	if hider != null:
		hider_hit.emit(hider)
		if hider.has_method("eliminate"):
			hider.eliminate()
		shot_fired.emit(true)
	else:
		shot_fired.emit(false)


func _find_hider(node: Node) -> Node:
	var n := node
	while n != null:
		if n.is_in_group("hider"):
			return n
		n = n.get_parent()
	return null


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE
