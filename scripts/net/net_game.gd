extends Node3D
## Multiplayer game root (Step A): host/join over ENet (LAN/direct-IP),
## host-authoritative. The server spawns one avatar per peer under Players;
## a MultiplayerSpawner replicates spawns (incl. to late joiners). Each avatar
## is client-authoritative for its own movement (see net_player.gd).
##
## CLI autostart (for headless/recorder testing):
##   godot --path . scenes/game/net_game.tscn -- --server
##   godot --path . scenes/game/net_game.tscn -- --client=127.0.0.1

const PORT := 24565
const MAX_PLAYERS := 12
const PLAYER_SCENE := preload("res://scenes/characters/net_player.tscn")
## Scoring: hiders earn points while visible to a seeker; closer = faster.
const VIS_RANGE := 30.0
const SCORE_RATE := 60.0
const VIEW_HALF_COS := 0.5  # ~60° half-cone

## Where avatars spawn (per-map). Overridden in the scene for each arena.
@export var spawn_base: Vector3 = Vector3(-5.0, 0.1, 6.0)

@onready var _players: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $MultiplayerSpawner


func _ready() -> void:
	# Custom spawn function runs on every peer with the same data, so initial
	# position + role are set deterministically (no spawn-vs-sync race).
	_spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a == "--server":
			host()
		elif a.begins_with("--client="):
			join(a.substr("--client=".length()))


func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("[net] failed to host on %d: %s" % [PORT, error_string(err)])
		return
	multiplayer.multiplayer_peer = peer
	print("[net] hosting on port ", PORT)
	_apply_phase_overrides()
	GameState.authoritative = true
	GameState.phase_changed.connect(_on_phase_changed)
	_add_player(1)  # host's own avatar
	GameState.start_match()


func _apply_phase_overrides() -> void:
	# Optional CLI tuning for tests: --prep=SEC --seek=SEC
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--prep="):
			GameState.prep_seconds = float(a.substr("--prep=".length()))
		elif a.begins_with("--seek="):
			GameState.seek_seconds = float(a.substr("--seek=".length()))


func join(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		push_error("[net] failed to connect to %s: %s" % [ip, error_string(err)])
		return
	multiplayer.multiplayer_peer = peer
	GameState.authoritative = false  # host drives phases; we just reflect them
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	print("[net] connecting to ", ip, ":", PORT)


func _on_connected_to_server() -> void:
	# Our avatars are spawned by now; ask the host to replay everyone's state.
	_request_full_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_full_state() -> void:
	if not multiplayer.is_server():
		return
	var who := multiplayer.get_remote_sender_id()
	for p in _players.get_children():
		if p.name == str(who):
			continue  # the joiner's own avatar is still blank
		# Host's copy already has each player's broadcast paint/pose/caught.
		p.sync_full_state.rpc_id(who, p.body.get_paint_state(), p.body.current_pose, p.caught)
	print("[net] replayed state to late joiner ", who)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[net] peer connected: ", id)
		_add_player(id)
		# Bring the late joiner into the current phase.
		_sync_phase.rpc_id(id, GameState.phase, GameState.time_left())


func _process(delta: float) -> void:
	if multiplayer.is_server() and GameState.phase == GameState.Phase.SEEK:
		_accumulate_scores(delta)


func _accumulate_scores(delta: float) -> void:
	# Award uncaught hiders for being seen up close (hide-in-plain-sight).
	var seeker: NetPlayer = _find_seeker()
	if seeker == null:
		return
	var cam := seeker.get_node("CameraYaw/CameraPitch/SpringArm3D/Camera3D") as Camera3D
	var eye: Vector3 = cam.global_transform.origin
	var fwd: Vector3 = -cam.global_transform.basis.z
	var space: PhysicsDirectSpaceState3D = seeker.get_world_3d().direct_space_state
	for p in _players.get_children():
		if p.role != NetPlayer.Role.HIDER or p.caught:
			continue
		var torso: Vector3 = p.global_transform.origin + Vector3(0, 1.0, 0)
		var to: Vector3 = torso - eye
		var dist: float = to.length()
		if dist > VIS_RANGE or dist < 0.01:
			continue
		var dir: Vector3 = to / dist
		if fwd.dot(dir) < VIEW_HALF_COS:
			continue  # outside the seeker's view cone
		var q := PhysicsRayQueryParameters3D.create(eye, torso)
		q.exclude = [seeker.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty() or hit.get("collider") != p:
			continue  # occluded — not actually visible
		p.score += delta * SCORE_RATE * clampf(1.0 - dist / VIS_RANGE, 0.0, 1.0)


func _find_seeker() -> NetPlayer:
	for p in _players.get_children():
		if p.role == NetPlayer.Role.SEEKER:
			return p
	return null


func _on_phase_changed(phase: int) -> void:
	if not multiplayer.is_server():
		return
	if phase == GameState.Phase.RESULTS:
		# Lock in and broadcast final hider scores for the results screen.
		for p in _players.get_children():
			if p.role == NetPlayer.Role.HIDER:
				p.set_score.rpc(p.score)
	_sync_phase.rpc(phase, GameState.time_left())


@rpc("any_peer", "call_remote", "reliable")
func _sync_phase(phase: int, time_left: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		GameState.sync_phase(phase, time_left)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		var n := _players.get_node_or_null(str(id))
		if n != null:
			n.queue_free()


func _add_player(id: int) -> void:
	# Normal mode for now: the host is the lone seeker, everyone else hides.
	var role := NetPlayer.Role.SEEKER if id == 1 else NetPlayer.Role.HIDER
	var data := {
		"id": id,
		"pos": _spawn_pos(_players.get_child_count()),
		"role": role,
	}
	_spawner.spawn(data)
	print("[net] spawning player ", id, " role=", role)


func _spawn_player(data: Dictionary) -> Node:
	# Runs on every peer (server via spawn(), clients via replication).
	var p := PLAYER_SCENE.instantiate()
	p.name = str(data["id"])
	p.position = data["pos"]
	p.role = data["role"]
	return p


@rpc("any_peer", "call_remote", "reliable")
func _request_eliminate(target_id: int) -> void:
	# Host validates the seeker's claimed hit, then broadcasts the catch.
	if not multiplayer.is_server():
		return
	var target := _players.get_node_or_null(str(target_id))
	if target == null or target.caught or target.role != NetPlayer.Role.HIDER:
		return
	target.set_caught.rpc()
	print("[net] eliminated hider ", target_id)
	_check_all_caught()


func _check_all_caught() -> void:
	# Seekers win as soon as every hider has been found.
	var hiders := 0
	var caught := 0
	for p in _players.get_children():
		if p.role == NetPlayer.Role.HIDER:
			hiders += 1
			if p.caught:
				caught += 1
	if hiders > 0 and caught == hiders and GameState.phase == GameState.Phase.SEEK:
		GameState.set_phase(GameState.Phase.RESULTS)
		print("[net] all hiders caught -> RESULTS")


func _spawn_pos(slot: int) -> Vector3:
	# Spread spawns by join order so avatars never overlap (grid from base).
	var col := slot % 6
	var row := slot / 6
	return spawn_base + Vector3(float(col) * 2.0, 0.0, float(row) * 2.0)
