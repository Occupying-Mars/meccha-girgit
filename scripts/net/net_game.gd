extends Node3D
class_name NetGame
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
## Selectable maps. The host picks one in the menu; it's replicated to everyone
## at match start (NetSession._begin) so all players build the same arena.
## `require` (optional) is an asset that must exist, else we fall back to arena.
const MAPS := {
	"sponza": {
		"label": "Sponza",
		"script": "res://scripts/core/sponza_map.gd",
		"spawn": Vector3(-4.0, 0.6, -2.0),
		"require": "res://assets/arenas/sponza/Sponza.gltf",
		# Brightened to match the standalone Sponza scene's tuning.
		"ambient": 1.5, "sun": 1.8, "exposure": 1.1,
	},
	"backrooms": {
		"label": "Backrooms",
		"script": "res://scripts/core/backrooms_builder.gd",
		"spawn": Vector3(-10.5, 0.4, 0.0),
		"ambient": 0.85, "sun": 0.5, "exposure": 1.0,
	},
	"warehouse": {
		"label": "Warehouse",
		"script": "res://scripts/core/warehouse_builder.gd",
		"spawn": Vector3(0.0, 0.5, 12.0),
		"ambient": 0.7, "sun": 1.1, "exposure": 1.0,
	},
	"dungeon": {
		"label": "Dungeon (KayKit)",
		"script": "res://scripts/core/kaykit_dungeon_builder.gd",
		"spawn": Vector3(-6.0, 0.6, -8.0),
		"require": "res://assets/maps/kaykit/floor.glb",
		"dark_bg": true, "ambient_color": Color(0.40, 0.42, 0.55),
		"ambient": 0.55, "sun": 0.55, "exposure": 0.85,
	},
	"arena": {
		"label": "Test Arena",
		"script": "res://scripts/core/arena_builder.gd",
		"spawn": Vector3(-5.0, 0.1, 6.0),
		"ambient": 0.6, "sun": 1.0, "exposure": 1.0,
	},
}
## Scoring: hiders earn points while visible to a seeker; closer = faster.
const VIS_RANGE := 30.0
const SCORE_RATE := 60.0
const VIEW_HALF_COS := 0.5  # ~60° half-cone

## Where avatars spawn (per-map). Overridden in the scene for each arena.
@export var spawn_base: Vector3 = Vector3(-5.0, 0.1, 6.0)

@onready var _players: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var _map_root: Node3D = $MapRoot
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun


var _started: bool = false
var _built_map: String = ""


func _ready() -> void:
	# Custom spawn function runs on every peer with the same data, so initial
	# position + role are set deterministically (no spawn-vs-sync race).
	_spawner.spawn_function = _spawn_player
	if "--dedicated" in OS.get_cmdline_user_args():
		_start_dedicated_server()
	elif NetSession.active:
		_start_session_mode()
		_add_minimap()
	else:
		_build_map.call_deferred(_cli_map())  # CLI: --map=NAME (default arena)
		_start_cli_mode()
		_add_minimap()


func _add_minimap() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mm: CanvasLayer = load("res://scripts/ui/minimap.gd").new()
	mm.setup(_players)
	add_child(mm)


func _cli_map() -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--map="):
			return s.substr("--map=".length())
	return "arena"  # light + always-bundled; safe default for a small VPS


func _start_dedicated_server() -> void:
	# VPS entry: a server with no player of its own; clients connect outbound by
	# the VPS public IP (works through any NAT). Configured via CLI args:
	#   --dedicated [--map=backrooms] [--mode=random|decided] [--prep=N] [--seek=N]
	var map_id := "backrooms"  # default needs no downloaded assets
	var gmode := NetSession.Mode.RANDOM
	var play_mode := 0  # game mode: 0 Normal · 1 Infection · 2 Double
	var prep := 45.0
	var seek := 120.0
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--map="):
			map_id = a.substr("--map=".length())
		elif a.begins_with("--mode="):
			gmode = NetSession.Mode.DECIDED if a.substr("--mode=".length()) == "decided" else NetSession.Mode.RANDOM
		elif a.begins_with("--gamemode="):
			var gm := a.substr("--gamemode=".length())
			play_mode = 1 if gm == "infection" else (2 if gm == "double" else 0)
		elif a.begins_with("--prep="):
			prep = float(a.substr("--prep=".length()))
		elif a.begins_with("--seek="):
			seek = float(a.substr("--seek=".length()))
	NetSession.selected_map = map_id
	NetSession.game_mode = play_mode
	NetSession.prep_seconds = prep
	NetSession.seek_seconds = seek
	var err := NetSession.host_dedicated(gmode)
	if err != OK:
		push_error("[net] dedicated server failed to start: %s" % error_string(err))
		get_tree().quit(1)
		return
	print("[net] DEDICATED server listening on :%d  map=%s mode=%s prep=%.0f seek=%.0f" %
		[NetSession.PORT, map_id, "decided" if gmode == NetSession.Mode.DECIDED else "random", prep, seek])
	_start_session_mode()


func _build_map(map_id: String) -> void:
	# Build the chosen map under MapRoot (each peer does this locally — map
	# geometry is deterministic and not networked). Falls back to the arena if a
	# map's assets aren't bundled.
	_built_map = map_id
	for c in _map_root.get_children():
		_map_root.remove_child(c)
		c.queue_free()
	var info: Dictionary = MAPS.get(map_id, MAPS["arena"])
	if info.has("require") and not ResourceLoader.exists(info["require"]):
		push_warning("[net] map '%s' assets missing — using arena" % map_id)
		info = MAPS["arena"]
	var node := Node3D.new()
	node.name = "Map"
	node.set_script(load(info["script"]))
	_map_root.add_child(node)
	spawn_base = info["spawn"]
	_apply_lighting(info)
	print("[net] built map: ", map_id)


func _apply_lighting(info: Dictionary) -> void:
	# Per-map lighting so Sponza is bright while the dungeon stays dark/moody.
	var env: Environment = _world_env.environment
	if info.get("dark_bg", false):
		# Dark indoor look — no bright sky, ambient from a dim color so hiders
		# can actually disappear into the gloom.
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.03, 0.05)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = info.get("ambient_color", Color(0.45, 0.45, 0.55))
	else:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	if info.has("ambient"):
		env.ambient_light_energy = info["ambient"]
	if info.has("exposure"):
		env.tonemap_exposure = info["exposure"]
	if info.has("sun"):
		_sun.light_energy = info["sun"]


func _start_session_mode() -> void:
	# Connection was established by the menu/lobby; roles come from NetSession,
	# assigned when the host starts. Avatars spawn at start (lobby has none).
	NetSession.started.connect(_on_session_started)
	NetSession.map_changed.connect(_on_map_changed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Build the map NOW, during the lobby — so the heavy build (Sponza collision)
	# is done well before players spawn at match start. Clients build their menu
	# default first, then converge to the host's map when it syncs (_on_map_changed).
	# Deferred because _ready runs while the tree is still "busy" being built.
	_build_map.call_deferred(NetSession.selected_map)
	if multiplayer.is_server():
		GameState.authoritative = true
		GameState.phase_changed.connect(_on_phase_changed)
		multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		GameState.authoritative = false


func _start_cli_mode() -> void:
	# Headless/test entry: self-host or self-join from CLI args.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a == "--server":
			host.call_deferred()  # deferred so the map is built before we spawn
		elif a.begins_with("--client="):
			join.call_deferred(a.substr("--client=".length()))


func _on_map_changed() -> void:
	# Host's chosen map arrived on a client — converge to it while still in the
	# lobby (no players yet, so the rebuild is safe).
	if NetSession.selected_map != _built_map:
		_build_map(NetSession.selected_map)


func _on_session_started() -> void:
	# Map was already built during the lobby; only rebuild as a safety net if a
	# client somehow never received the sync (so we never spawn on the wrong map).
	if NetSession.selected_map != _built_map:
		_build_map(NetSession.selected_map)
	if multiplayer.is_server():
		_started = true
		GameState.prep_seconds = NetSession.prep_seconds
		GameState.seek_seconds = NetSession.seek_seconds
		for id in NetSession.players.keys():
			_add_player(int(id))
		GameState.start_match()


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
	if not multiplayer.is_server():
		return
	if NetSession.active and not _started:
		return  # still in the lobby; avatars spawn when the host starts
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
		# A dedicated server must return to the lobby so the next round can start
		# (and late joiners aren't stuck staring at an old results screen).
		if NetSession.dedicated:
			_dedicated_reset_after(10.0)
	_sync_phase.rpc(phase, GameState.time_left())


## Dedicated server: after the results linger a bit, clear avatars and drop back
## to ASSIGN — the lobby re-opens and the admin can pick map/mode and start again.
func _dedicated_reset_after(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if GameState.phase != GameState.Phase.RESULTS:
		return  # something already moved us on
	for p in _players.get_children():
		p.queue_free()
	_started = false
	GameState.set_phase(GameState.Phase.ASSIGN)
	print("[dedicated] round over — back to lobby")


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
	# Roles from the lobby (random/decided) when a session is active; otherwise
	# the CLI test default: host is the lone seeker.
	var role: int
	if NetSession.active:
		role = NetSession.role_for(id)
	elif "--ashider" in OS.get_cmdline_user_args():
		role = NetPlayer.Role.HIDER  # CLI preview: be a hider to test paint/pose
	else:
		role = NetPlayer.Role.SEEKER if id == 1 else NetPlayer.Role.HIDER
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
	if NetSession.game_mode == 1:  # INFECTION — caught hider joins the seekers
		target.become_seeker.rpc()
		print("[net] infected hider ", target_id)
	else:
		target.set_caught.rpc()
		print("[net] eliminated hider ", target_id)
	_check_round_end()


## Host-only: clear the round and start a fresh one (from the results menu).
func restart_match() -> void:
	if not multiplayer.is_server():
		return
	for p in _players.get_children():
		p.queue_free()
	_started = false
	await get_tree().process_frame
	await get_tree().process_frame
	_on_session_started()  # respawns everyone + start_match (re-applies durations)


func _check_round_end() -> void:
	# Round ends when no hider is left "in play": caught (Normal/Double) or
	# converted to a seeker (Infection). Either way, no active hiders remain.
	if GameState.phase != GameState.Phase.SEEK:
		return
	var active_hiders := 0
	for p in _players.get_children():
		if p.role == NetPlayer.Role.HIDER and not p.caught:
			active_hiders += 1
	if active_hiders == 0:
		GameState.set_phase(GameState.Phase.RESULTS)
		print("[net] no hiders left -> RESULTS")


func _spawn_pos(slot: int) -> Vector3:
	# Spread spawns by join order so avatars never overlap (grid from base).
	var col := slot % 6
	var row := slot / 6
	return spawn_base + Vector3(float(col) * 2.0, 0.0, float(row) * 2.0)
