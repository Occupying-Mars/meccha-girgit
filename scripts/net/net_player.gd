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
const WALL_OFFSET := 0.09   # body half-depth so the model sits against the wall
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
const PAUSE_MENU := preload("res://scenes/ui/pause_menu.tscn")

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
@onready var _whistle: AudioStreamPlayer3D = $Whistle
@onready var body: HiderBody = $HiderBody

## Auto-whistle: every hider chirps after this long unless they whistle
## manually first (which resets it). Host-toggleable in a fuller build.
const AUTO_WHISTLE_SECS := 45.0
var _auto_whistle_t: float = AUTO_WHISTLE_SECS

var _is_mine: bool = false
var _pitch_angle: float = -0.25
var _paint_menu: FreehandPaintMenu
var _pose_menu: PoseMenu
var _menu_open: bool = false
var _seeker_hud: CanvasLayer
var _pause_menu: PauseMenu
var _pause_open: bool = false
var caught: bool = false
var _stuck: bool = false
var _wall_normal: Vector3 = Vector3.ZERO
var _stick_y: float = 0.0   # body height when we latched on (climb is relative to this)
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
		var controls := ControlsHud.new()
		add_child(controls)
		controls.show_for(is_seeker())
		_pause_menu = PAUSE_MENU.instantiate()
		add_child(_pause_menu)
		_pause_menu.resumed.connect(_on_pause_resumed)
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
		# Full-size collision + body. Also UNDOES the hider shrink when a caught
		# hider is infected into a seeker mid-round (infection mode).
		var fc := CapsuleShape3D.new()
		fc.radius = 0.25
		fc.height = 1.7
		_collision.shape = fc
		_collision.scale = Vector3.ONE
		_collision.position.y = 0.85
		_collision.disabled = false
		body.scale = Vector3.ONE
		# Shots should land on the VISIBLE painted body, so cast against the paint
		# trimesh (matches the mesh, and works even while a hider is wall-stuck and
		# their movement capsule is disabled) + the world. Exclude our own capsule
		# AND body parts so we never shoot ourselves.
		_muzzle.collision_mask = 1 | HiderBody.PAINT_LAYER
		_muzzle.clear_exceptions()
		_muzzle.add_exception(self)
		for sb in _own_static_bodies():
			_muzzle.add_exception(sb)
	else:
		add_to_group("hider")
		move_speed = HIDER_SPEED
		body.scale = Vector3.ONE * HIDER_SCALE
		# Size the capsule DIRECTLY — node scale on a CollisionShape3D is often
		# ignored by the physics server, which left the tiny hider floating a
		# full-size radius off every wall.
		var cap := CapsuleShape3D.new()
		cap.radius = 0.25 * HIDER_SCALE
		cap.height = 1.7 * HIDER_SCALE
		_collision.shape = cap
		_collision.scale = Vector3.ONE
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
	_drive_walk(_delta)  # animate the gait for every avatar (local + remote)
	if not _is_mine:
		return
	# Esc: close an open paint/pose menu first, otherwise toggle the pause menu.
	if Input.is_action_just_pressed("ui_cancel"):
		if _paint_menu != null and _paint_menu.visible:
			_paint_menu.close()
		elif _pose_menu != null and _pose_menu.visible:
			_pose_menu.close()
		else:
			_toggle_pause()
		return
	if _pause_open or caught:
		return
	if is_seeker():
		if Input.is_action_just_pressed("fire") and _can_act():
			_fire()
		return
	# Whistle (taunt): manual press + auto-whistle countdown during SEEK.
	if GameState.phase == GameState.Phase.SEEK:
		_auto_whistle_t -= _delta
		if _auto_whistle_t <= 0.0:
			_do_whistle()
	if Input.is_action_just_pressed("taunt") and not _menu_open:
		_do_whistle()
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


func _toggle_pause() -> void:
	if _pause_open:
		_pause_menu.close()  # emits resumed -> _on_pause_resumed
	else:
		_pause_open = true
		_pause_menu.open()


func _on_pause_resumed() -> void:
	_pause_open = false
	if not _menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	# Stop the camera arm from zooming in on anything behind you while painting /
	# posing — you need the full body in view to colour it. Restored on close.
	_spring.collision_mask = 0
	menu.open()


func _on_menu_closed() -> void:
	if not _paint_menu.visible and not _pose_menu.visible:
		_menu_open = false
		_spring.collision_mask = 1  # camera collides with the world again
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Only mouse-look while actually playing (mouse captured). This skips menus,
	# pause, and the results screen — where the cursor is visible for clicking,
	# so the camera no longer spins while you try to click a results button.
	if not _is_mine or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_yaw.rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch_angle = clampf(_pitch_angle - event.relative.y * mouse_sensitivity, -1.2, 0.6)
		_pitch.rotation.x = _pitch_angle


func _physics_process(delta: float) -> void:
	if not _is_mine:
		return  # remote: position/rotation come from the synchronizer
	if _menu_open or _pause_open or caught or not _can_act():
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

	# Out-of-bounds backstop: if we somehow ended up falling outside the map
	# (any glitch, any map), snap back to the spawn area instead of falling
	# forever in the void.
	if global_position.y < -6.0:
		_respawn_inside()

	if move.length() > 0.1:
		var target_yaw := atan2(move.x, move.z)
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, 0.2)


func _respawn_inside() -> void:
	var scene := get_tree().current_scene
	var fallback: Vector3 = scene.spawn_base if "spawn_base" in scene else Vector3(0, 1, 0)
	global_position = fallback + Vector3(0, 0.5, 0)
	velocity = Vector3.ZERO
	print("[net_player] fell out of bounds — respawned inside")


## --- Wall-stick (hiders cling to and climb walls) ----------------------------

func _try_stick() -> void:
	# Find the NEAREST wall around the player (not just where the camera aims)
	# so it sticks whenever you're near one. Mask = world only (layer 1).
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.4, 0)
	var best := {}
	var best_d := INF
	var dirs := 16
	for i in dirs:
		var ang := TAU * float(i) / float(dirs)
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * STICK_RANGE)
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf((hit["normal"] as Vector3).y) > 0.5:
			continue  # nothing, or it's floor/ceiling not a wall
		var d := from.distance_to(hit["position"])
		if d < best_d:
			best_d = d
			best = hit
	if best.is_empty():
		return
	_stuck = true
	_wall_normal = best["normal"]
	# Snap so the (un-squeezed) model sits against the wall, keep height.
	var p := best["position"] as Vector3
	global_position = Vector3(p.x, global_position.y, p.z) + _wall_normal * WALL_OFFSET
	_stick_y = global_position.y
	# Face out from the wall; the model keeps its current pose (no squeezing).
	body.rotation.y = atan2(_wall_normal.x, _wall_normal.z)
	velocity = Vector3.ZERO
	# Pinned, not colliding — disable the movement capsule so it sits flush.
	_collision.disabled = true
	# Flatten against the wall (visibly stuck + thin profile = wall-art camo),
	# and replicate the pose so the seeker sees it too.
	body.apply_pose("wall_flatten", false)
	_broadcast_pose("wall_flatten")


func _wall_adjust(delta: float) -> void:
	# Climb freely UP the wall face. Two independent limits, both must pass:
	#  1) HEAD vs the wall: check the wall is still there at head height, so
	#     you can never climb OVER a wall (feet-only checks let the model poke
	#     out above the roof at max climb).
	#  2) CAMERA vs the ceiling: on maps where the ceiling sits right at the
	#     wall's own height (e.g. backrooms), reaching the head cap in (1)
	#     still leaves the ORBITING CAMERA — mounted above the yaw pivot, further
	#     out via the spring arm — high enough to poke INSIDE the ceiling slab.
	#     A ray embedded in solid geometry hits nothing in any direction (rays
	#     don't register against the shape they start inside), which is exactly
	#     the "outside the map, seeing a blank void" bug. So before climbing,
	#     also check straight up for the camera's full possible reach
	#     (yaw pivot height + the whole spring arm length + a margin).
	var v := 0.0
	if Input.is_action_pressed("jump") or Input.is_action_pressed("move_forward"):
		v += 1.0
	if Input.is_action_pressed("move_back"):
		v -= 1.0
	velocity = Vector3.ZERO
	if v > 0.0:
		if not _wall_present_at(global_position.y + _body_top()):
			v = 0.0
		elif not _clear_above(_camera_reach()):
			v = 0.0
	var hi := _stick_y + 6.0
	global_position.y = clampf(global_position.y + v * WALL_VSPEED * delta, 0.1, hi)


## Top of the visible body above the feet (head sphere tops at ~1.74 body-local,
## times the avatar's scale — ~0.6 for a shrunken hider).
func _body_top() -> float:
	return 1.8 * body.scale.y


## How high above the feet the orbiting camera can possibly reach (yaw pivot
## height + the full spring arm length + a small margin), regardless of pitch.
func _camera_reach() -> float:
	return _yaw.position.y + _spring.spring_length + 0.3


## Is the wall we're clung to still there at `check_y`? Checked at head height
## while climbing, so you climb until your head meets the top — never past it.
func _wall_present_at(check_y: float) -> bool:
	var space := get_world_3d().direct_space_state
	var from := Vector3(global_position.x, check_y, global_position.z)
	var q := PhysicsRayQueryParameters3D.create(from, from - _wall_normal * (WALL_OFFSET + 0.6))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	return not space.intersect_ray(q).is_empty()


## True if there's clear space straight up from the feet for `height` — used to
## stop climbing before the camera's reach can poke into a ceiling above.
func _clear_above(height: float) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, height, 0))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _unstick() -> void:
	if not _stuck:
		return
	_stuck = false
	global_position += _wall_normal * 0.15  # step off so the capsule clears
	_collision.disabled = false
	velocity = _wall_normal * 1.5
	_wall_normal = Vector3.ZERO
	body.rotation.y = 0.0
	body.apply_pose("stand", false)
	_broadcast_pose("stand")


## If a full standing capsule at our position overlaps geometry, move to the
## nearest clear spot (never through a wall) so a converted seeker is never
## trapped. Authority-peer only — we own this avatar's position here.
func _unwedge_to_clear() -> void:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.exclude = [get_rid()]
	if _capsule_free(space, q, global_position):
		return
	# Straight up first (space above a small hiding spot is usually open)...
	for lift in [0.4, 0.9, 1.5]:
		if _capsule_free(space, q, global_position + Vector3(0, lift, 0)):
			global_position += Vector3(0, lift, 0)
			velocity = Vector3.ZERO
			return
	# ...then spiral outward at the current height, staying in this room.
	for ring in [0.6, 1.0, 1.5, 2.2, 3.0]:
		for step in 12:
			var a := TAU * float(step) / 12.0
			var p := global_position + Vector3(cos(a) * ring, 0.0, sin(a) * ring)
			if _capsule_free(space, q, p) and not _wall_between(global_position, p):
				global_position = p
				velocity = Vector3.ZERO
				return


func _capsule_free(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, pos: Vector3) -> bool:
	q.transform = Transform3D(Basis(), pos + Vector3(0, 0.9, 0))
	return space.intersect_shape(q, 1).is_empty()


## Solid wall between a and b? High ray (above furniture) so it only trips on
## walls — stops the un-wedge nudge from popping someone into another room/outside.
func _wall_between(a: Vector3, b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var y := a.y + 1.5
	var q := PhysicsRayQueryParameters3D.create(Vector3(a.x, y, a.z), Vector3(b.x, y, b.z))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	return not space.intersect_ray(q).is_empty()


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


## --- Whistle / taunt (3D positional, networked) ------------------------------

func _do_whistle() -> void:
	_auto_whistle_t = AUTO_WHISTLE_SECS  # whistling resets the auto timer
	play_whistle.rpc()


@rpc("authority", "call_local", "reliable")
func play_whistle() -> void:
	if _whistle.stream != null:
		_whistle.play()
	_whistle_popup()


func _whistle_popup() -> void:
	# Brief "♪" that floats up and fades above the whistler — a soft tell.
	var note := Label3D.new()
	note.text = "♪"
	note.font_size = 96
	note.pixel_size = 0.004
	note.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	note.modulate = Color(1, 1, 1, 0.9)
	note.position = Vector3(0, 0.85, 0)
	add_child(note)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(note, "position:y", 1.4, 0.8)
	tw.tween_property(note, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(note.queue_free)


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


## Procedural walk: measure how fast this avatar is actually moving (works for
## remote avatars too, off their synced position) and feed the gait. Smoothed so
## the stepped network position updates don't make the legs stutter.
var _walk_phase: float = 0.0
var _walk_amount: float = 0.0
var _walk_last: Vector3 = Vector3.ZERO
var _walk_init: bool = false

func _drive_walk(delta: float) -> void:
	if body == null:
		return
	var p := global_position
	if not _walk_init:
		_walk_last = p
		_walk_init = true
	var horiz := Vector2(p.x - _walk_last.x, p.z - _walk_last.z)
	_walk_last = p
	var speed := horiz.length() / maxf(delta, 0.0001)
	var target := clampf(speed / maxf(move_speed, 0.1), 0.0, 1.0)
	_walk_amount = lerpf(_walk_amount, target, clampf(delta * 6.0, 0.0, 1.0))
	_walk_phase += delta * 9.0 * _walk_amount
	body.walk(_walk_phase, _walk_amount)


## Every StaticBody3D under our own body (the per-part paint colliders) — used to
## exclude ourselves from the shoot raycast now that it hits the paint layer.
func _own_static_bodies() -> Array:
	var out: Array = []
	var stack: Array = [body]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is StaticBody3D:
			out.append(n)
	return out


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


## Infection mode: convert a caught hider into a seeker (they join the hunt).
## Runs on every peer (call_local) so the role swap — full size, FP camera, gun —
## is seen by everyone. Host-validated via the sender check — must be "any_peer"
## (NOT "authority") because the SERVER triggers this on a hider node it is not
## the authority of; an "authority" annotation makes Godot drop the call and the
## hider never converts (the "hunter can't kill in Infection" bug).
@rpc("any_peer", "call_local", "reliable")
func become_seeker() -> void:
	var s := multiplayer.get_remote_sender_id()
	if s != 1 and s != 0:
		return
	if role == Role.SEEKER:
		return
	role = Role.SEEKER
	caught = false
	remove_from_group("hider")
	# A wall-stuck hider had its capsule disabled — drop the stuck state so the
	# newly full-size seeker collides + moves normally again.
	_stuck = false
	_wall_normal = Vector3.ZERO
	body.reset_to_blank()
	body.apply_pose("stand", false)
	_configure_role()  # full size, FP camera, shooting
	if _is_mine:
		# The tiny hider just grew to a full seeker capsule; if that happened in a
		# cramped hiding spot they'd be wedged in geometry. Pop them to the nearest
		# clear standing spot so they never get trapped on conversion.
		_unwedge_to_clear()
		if _paint_menu != null:
			_paint_menu.queue_free()
			_paint_menu = null
		if _pose_menu != null:
			_pose_menu.queue_free()
			_pose_menu = null
		_menu_open = false
		if _seeker_hud == null:
			_seeker_hud = SEEKER_HUD.instantiate()
			add_child(_seeker_hud)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
