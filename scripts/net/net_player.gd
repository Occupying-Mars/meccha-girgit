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

## Hiders are small (a third of the seeker) and slower; seekers are full-size
## and faster. Sizes/speeds are applied per role in _configure_role().
const HIDER_SCALE := 0.34
const HIDER_SPEED := 2.6
const SEEKER_SPEED := 5.0
## Wall-stick (hiders): flatten FLUSH against a wall to hide as wall-art.
## Once stuck you only adjust height (raise/lower) to line up with a frame/
## shelf; you don't free-climb. Release to detach (MECCHA behaviour).
const STICK_RANGE := 2.2    # forgiving reach; sticking snaps you flush anyway
const WALL_OFFSET := 0.045  # flush: half the flattened body's depth
const WALL_VSPEED := 1.1    # raise/lower speed while stuck

@export var move_speed: float = 4.0
@export var mouse_sensitivity: float = 0.0025
@export var gravity: float = 18.0
@export var jump_velocity: float = 6.0
## Headless test aid: remote avatars log their synced position. Off by
## default; flip on in the scene when debugging replication.
@export var debug_remote: bool = false

const PAINT_MENU := preload("res://scenes/ui/freehand_paint_menu.tscn")
const POSE_MENU := preload("res://scenes/ui/pose_menu.tscn")
const SEEKER_HUD := preload("res://scenes/ui/net_seeker_hud.tscn")

enum Role { HIDER, SEEKER }

## Synced spawn property — set by the host at spawn; tells every peer this
## avatar's role. Drives local camera mode + abilities.
@export var role: int = Role.HIDER

@onready var _spring: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D
@onready var _yaw: Node3D = $CameraYaw
@onready var _pitch: Node3D = $CameraYaw/CameraPitch
@onready var _camera: Camera3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D
@onready var _muzzle: RayCast3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D/Muzzle
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var body: HiderBody = $HiderBody

var _is_mine: bool = false
var _pitch_angle: float = -0.25
var _paint_menu: FreehandPaintMenu
var _pose_menu: PoseMenu
var _menu_open: bool = false
var _seeker_hud: CanvasLayer
var caught: bool = false
var _stuck: bool = false
var _wall_normal: Vector3 = Vector3.ZERO
## Hider score, accrued by the host while this hider is visible to a seeker
## and close (hiding in plain sight). Broadcast to all at RESULTS.
var score: float = 0.0


@rpc("any_peer", "call_remote", "reliable")
func set_score(value: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		score = value


func is_seeker() -> bool:
	return role == Role.SEEKER


## Seekers are locked at spawn during PREP and released for SEEK; hiders may
## roam during PREP and SEEK but not after RESULTS.
func _can_act() -> bool:
	match GameState.phase:
		GameState.Phase.SEEK:
			return true
		GameState.Phase.PREP:
			return not is_seeker()
		_:
			return false


func _enter_tree() -> void:
	# Name is the owning peer id; set authority for the whole branch.
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	_is_mine = is_multiplayer_authority()
	_camera.current = _is_mine
	_configure_role()
	if _is_mine:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if is_seeker():
			_seeker_hud = SEEKER_HUD.instantiate()
			add_child(_seeker_hud)
		else:
			_setup_menus()
	elif debug_remote:
		# Remote players are driven by the synchronizer. Log their synced
		# position periodically so headless tests can verify replication.
		_debug_remote_loop()


func _configure_role() -> void:
	# Seekers are first-person hunters; hiders are small, slow, third-person.
	if is_seeker():
		move_speed = SEEKER_SPEED
		_spring.spring_length = 0.0
		_yaw.position.y = 1.6
		_camera.transform.origin = Vector3.ZERO
		_pitch_angle = 0.0
		_pitch.rotation.x = 0.0
		# The muzzle sits inside the seeker's own capsule — don't shoot self.
		_muzzle.add_exception(self)
	else:
		add_to_group("hider")
		move_speed = HIDER_SPEED
		# Shrink the blob + its collider to a third; bring the camera down so
		# the small hider still frames well in third person.
		body.scale = Vector3.ONE * HIDER_SCALE
		_collision.scale = Vector3.ONE * HIDER_SCALE
		_collision.position.y = 0.85 * HIDER_SCALE
		_yaw.position.y = 1.4 * HIDER_SCALE + 0.15
		_spring.spring_length = 1.4


func _debug_remote_loop() -> void:
	while is_inside_tree() and not _is_mine:
		print("[net_player] remote %s pos=(%.2f, %.2f, %.2f)" % [name, position.x, position.y, position.z])
		await get_tree().create_timer(0.4).timeout


func _setup_menus() -> void:
	_paint_menu = PAINT_MENU.instantiate()
	add_child(_paint_menu)
	_paint_menu.setup(body, _camera, _yaw, _pitch)
	_paint_menu.closed.connect(_on_menu_closed)
	_paint_menu.closed.connect(_broadcast_paint)  # lock-in: replicate paint

	_pose_menu = POSE_MENU.instantiate()
	add_child(_pose_menu)
	_pose_menu.setup(body)
	_pose_menu.closed.connect(_on_menu_closed)
	_pose_menu.pose_changed.connect(_broadcast_pose)


func _process(_delta: float) -> void:
	if not _is_mine or caught:
		return
	if is_seeker():
		if Input.is_action_just_pressed("fire") and _can_act():
			_fire()
		return
	# Hider wall-stick toggle (F).
	if Input.is_action_just_pressed("interact") and not _menu_open and _can_act():
		if _stuck:
			_unstick()
		else:
			_try_stick()
		return
	# Hider menus.
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
	if _menu_open or caught or not _can_act():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	if _stuck:
		_wall_adjust(delta)
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


## --- Wall-stick (hiders cling to and climb walls) ----------------------------

func _try_stick() -> void:
	# Cast toward where the camera looks; stick FLUSH to a vertical wall.
	# Mask = world only (layer 1) so we ignore our own paint colliders.
	var dir := -_yaw.global_transform.basis.z
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var from := global_position + Vector3(0, 0.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * STICK_RANGE)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or absf((hit["normal"] as Vector3).y) > 0.5:
		return  # nothing to stick to, or it's floor/ceiling not a wall
	_stuck = true
	_wall_normal = hit["normal"]
	# Snap so the flattened body sits flush against the wall (keep height).
	var p := hit["position"] as Vector3
	global_position = Vector3(p.x, global_position.y, p.z) + _wall_normal * WALL_OFFSET
	# Align the body's thin (flattened) axis with the wall normal.
	body.rotation.y = atan2(_wall_normal.x, _wall_normal.z)
	velocity = Vector3.ZERO
	# Pinned, not colliding — disable the movement capsule so it's truly flush.
	_collision.disabled = true
	body.apply_pose("wall_flatten", true)
	_broadcast_pose("wall_flatten")


func _wall_adjust(delta: float) -> void:
	# Stuck: only raise/lower to line up with a frame/shelf edge (no climbing).
	var v := 0.0
	if Input.is_action_pressed("jump") or Input.is_action_pressed("move_forward"):
		v += 1.0
	if Input.is_action_pressed("move_back"):
		v -= 1.0
	velocity = Vector3.ZERO
	global_position.y = clampf(global_position.y + v * WALL_VSPEED * delta, 0.1, 6.0)


func _unstick() -> void:
	if not _stuck:
		return
	_stuck = false
	global_position += _wall_normal * 0.12  # step off so the capsule clears
	_collision.disabled = false
	velocity = _wall_normal * 1.5
	body.apply_pose("stand", true)
	_broadcast_pose("stand")
	_wall_normal = Vector3.ZERO


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


## --- Seeker gun + elimination -----------------------------------------------

func _fire() -> void:
	_muzzle.force_raycast_update()
	var target_id := -1
	var collider: Object = _muzzle.get_collider() if _muzzle.is_colliding() else null
	if collider != null:
		var np := _find_net_player(collider)
		if np != null and np != self and np.role == Role.HIDER and not np.caught:
			target_id = np.name.to_int()
	if _seeker_hud != null and _seeker_hud.has_method("register_shot"):
		_seeker_hud.register_shot(target_id != -1)
	if target_id == -1:
		return
	var game := get_tree().current_scene
	if multiplayer.is_server():
		game._request_eliminate(target_id)  # direct — we are the host
	else:
		game._request_eliminate.rpc_id(1, target_id)


func _find_net_player(node: Node) -> NetPlayer:
	var n := node
	while n != null:
		if n is NetPlayer:
			return n
		n = n.get_parent()
	return null


## Host-authoritative: only accepted from the server (sender 1, or 0 = local
## call on the host itself).
@rpc("any_peer", "call_local", "reliable")
func set_caught() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1 and sender != 0:
		return
	_apply_caught()


func _apply_caught() -> void:
	if caught:
		return
	caught = true
	for part_name in body.part_names():
		body.set_part_color(part_name, Color(0.9, 0.1, 0.1))
	print("[net_player] caught: ", name)


## Host-only: push this avatar's full current state to a late joiner so it
## sees paint/pose/caught that happened before it connected. Goes through the
## same get/apply_paint_state path, so it survives the freehand-paint upgrade.
@rpc("any_peer", "call_remote", "reliable")
func sync_full_state(paint: Dictionary, pose_name: String, is_caught: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	body.apply_paint_state(paint)
	body.apply_pose(pose_name, false)
	if is_caught:
		_apply_caught()
