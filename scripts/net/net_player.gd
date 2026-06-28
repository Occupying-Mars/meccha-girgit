extends CharacterBody3D
class_name NetPlayer
## Networked player avatar (Step A: movement only).
##
## Every player is a blob. Authority is client-authoritative: the owning peer
## runs input + physics and a MultiplayerSynchronizer replicates its position
## and facing to everyone else. Remote copies just display the synced state.
##
## Authority is derived from the node name (which the spawner sets to the
## peer id) in _enter_tree so it is identical on every peer. set_multiplayer_
## authority is recursive, so the child MultiplayerSynchronizer inherits it.

@export var move_speed: float = 4.0
@export var mouse_sensitivity: float = 0.0025
@export var gravity: float = 18.0
@export var jump_velocity: float = 6.0
## Headless test aid: remote avatars log their synced position. Off by
## default; flip on in the scene when debugging replication.
@export var debug_remote: bool = false

const PAINT_MENU := preload("res://scenes/ui/paint_menu.tscn")
const POSE_MENU := preload("res://scenes/ui/pose_menu.tscn")

@onready var _yaw: Node3D = $CameraYaw
@onready var _pitch: Node3D = $CameraYaw/CameraPitch
@onready var _camera: Camera3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D
@onready var body: HiderBody = $HiderBody

var _is_mine: bool = false
var _pitch_angle: float = -0.25
var _paint_menu: PaintMenu
var _pose_menu: PoseMenu
var _menu_open: bool = false


func _enter_tree() -> void:
	# Name is the owning peer id; set authority for the whole branch.
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	_is_mine = is_multiplayer_authority()
	_camera.current = _is_mine
	if _is_mine:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_setup_menus()
	elif debug_remote:
		# Remote players are driven by the synchronizer. Log their synced
		# position periodically so headless tests can verify replication.
		_debug_remote_loop()


func _debug_remote_loop() -> void:
	while is_inside_tree() and not _is_mine:
		print("[net_player] remote %s pos=(%.2f, %.2f, %.2f)" % [name, position.x, position.y, position.z])
		await get_tree().create_timer(0.4).timeout


func _setup_menus() -> void:
	_paint_menu = PAINT_MENU.instantiate()
	add_child(_paint_menu)
	_paint_menu.setup(body)
	_paint_menu.closed.connect(_on_menu_closed)
	_paint_menu.closed.connect(_broadcast_paint)  # lock-in: replicate paint

	_pose_menu = POSE_MENU.instantiate()
	add_child(_pose_menu)
	_pose_menu.setup(body)
	_pose_menu.closed.connect(_on_menu_closed)
	_pose_menu.pose_changed.connect(_broadcast_pose)


func _process(_delta: float) -> void:
	if not _is_mine:
		return
	if Input.is_action_just_pressed("paint_menu"):
		_toggle_menu(_paint_menu)
	elif Input.is_action_just_pressed("pose_menu"):
		_toggle_menu(_pose_menu)
	elif Input.is_action_just_pressed("ui_cancel"):
		if _paint_menu.visible:
			_paint_menu.close()
		elif _pose_menu.visible:
			_pose_menu.close()


func _toggle_menu(menu) -> void:
	if menu.visible:
		menu.close()
		return
	if _paint_menu.visible:
		_paint_menu.close()
	if _pose_menu.visible:
		_pose_menu.close()
	_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.open()


func _on_menu_closed() -> void:
	if not _paint_menu.visible and not _pose_menu.visible:
		_menu_open = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _is_mine or _menu_open:
		return
	if event is InputEventMouseMotion:
		_yaw.rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch_angle = clampf(_pitch_angle - event.relative.y * mouse_sensitivity, -1.2, 0.6)
		_pitch.rotation.x = _pitch_angle


func _physics_process(delta: float) -> void:
	if not _is_mine:
		return  # remote: position/rotation come from the synchronizer
	if _menu_open:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var in_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := _yaw.global_transform.basis
	var move := (basis.x * in_dir.x + (-basis.z) * -in_dir.y)
	move.y = 0.0
	move = move.normalized()

	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed
	move_and_slide()

	if move.length() > 0.1:
		var target_yaw := atan2(move.x, move.z)
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, 0.2)


## --- Paint / pose replication (RPC, reliable, on lock-in) --------------------
## Paint is set rarely and locked in during prep, so we replicate it once via
## a reliable RPC instead of streaming it. The owner broadcasts; receivers
## apply it to this same player node (routed by its peer-id name).
## NOTE: a peer joining mid-prep won't get paint applied earlier; late-join
## state sync is a planned follow-up.

func _broadcast_paint() -> void:
	if _is_mine:
		_receive_paint.rpc(body.get_paint_state())

func _broadcast_pose(pose_name: String) -> void:
	if _is_mine:
		_receive_pose.rpc(pose_name)


@rpc("authority", "call_remote", "reliable")
func _receive_paint(state: Dictionary) -> void:
	body.apply_paint_state(state)

@rpc("authority", "call_remote", "reliable")
func _receive_pose(pose_name: String) -> void:
	body.apply_pose(pose_name, false)
