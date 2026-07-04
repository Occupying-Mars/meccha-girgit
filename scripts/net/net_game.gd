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
		"probe_size": Vector3(43, 4, 36), "probe_pos": Vector3(0, 1.5, 0), "probe_interior": true,
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
		"probe_size": Vector3(25, 7, 25), "probe_pos": Vector3(0, 2.5, 0), "probe_interior": true,
	},
	"house": {
		"label": "House / Mansion",
		"script": "res://scripts/core/house_builder.gd",
		"spawn": Vector3(-8.0, 0.6, -4.0),
		"require": "res://assets/maps/furniture/couch.gltf",
		"ambient": 0.55, "sun": 1.0, "exposure": 1.0, "ssil": true,
		"warm_ambient": Color(0.50, 0.47, 0.44),
		"probe_size": Vector3(25, 5, 17), "probe_pos": Vector3(0, 2, 0), "probe_interior": true,
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
	# Graphics toggle (pause menu) re-applies the lighting stack live.
	GameState.graphics_changed.connect(func ():
		if not _last_light_info.is_empty():
			_apply_lighting(_last_light_info))
	if "--dedicated" in OS.get_cmdline_user_args():
		_start_dedicated_server()
	elif NetSession.active:
		_start_session_mode()
		_add_minimap()
		_add_scoreboard()
	else:
		_build_map.call_deferred(_cli_map())  # CLI: --map=NAME (default arena)
		_start_cli_mode()
		_add_minimap()
		_add_scoreboard()


func _add_minimap() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mm: CanvasLayer = load("res://scripts/ui/minimap.gd").new()
	mm.setup(_players)
	add_child(mm)


func _add_scoreboard() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var sb: CanvasLayer = load("res://scripts/ui/scoreboard.gd").new()
	sb.setup(_players)
	add_child(sb)


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
	# One baked reflection probe covering the map: grounded speculars where SSR
	# can't reach (off-screen / behind-camera surfaces). Baked once, then free.
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = info.get("probe_size", Vector3(40, 12, 40))
	probe.position = info.get("probe_pos", Vector3(0, 4, 0))
	probe.box_projection = info.get("probe_interior", false)
	probe.interior = info.get("probe_interior", false)
	_map_root.add_child(probe)
	spawn_base = info["spawn"]
	_apply_lighting(info)
	print("[net] built map: ", map_id)


var _last_light_info: Dictionary = {}

func _apply_lighting(info: Dictionary) -> void:
	# Per-map lighting so Sponza is bright while the dungeon stays dark/moody.
	_last_light_info = info  # kept so the graphics toggle can re-apply live
	var env: Environment = _world_env.environment
	if info.get("dark_bg", false):
		# Dark indoor look — no bright sky, ambient from a dim color so hiders
		# can actually disappear into the gloom.
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.03, 0.05)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = info.get("ambient_color", Color(0.45, 0.45, 0.55))
	elif info.has("warm_ambient"):
		# Roofed-but-bright interior: sky outside, warm cosy fill within (the
		# rooms are actually lit by their own ceiling spots + lamps).
		env.background_mode = Environment.BG_SKY
		env.sky = _physical_sky()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = info["warm_ambient"]
	else:
		env.background_mode = Environment.BG_SKY
		env.sky = _physical_sky()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	if info.has("ambient"):
		env.ambient_light_energy = info["ambient"]
	if info.has("exposure"):
		env.tonemap_exposure = info["exposure"]
	if info.has("sun"):
		_sun.light_energy = info["sun"]
	_apply_quality(env, info)


## Shared rendering stack, tuned for grounded realism rather than "punch":
## real bounced light (SDFGI) instead of a flat ambient fill, real reflections
## (SSR; a per-map probe is added in _build_map), honest sun shadows (physical
## ~0.5 deg angular size), a NEUTRAL grade (no baked contrast/saturation push),
## and SSAO relaxed to a supporting role now that GI does the true occlusion.
func _apply_quality(env: Environment, info: Dictionary) -> void:
	var high := GameState.graphics_high
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.4
	# Real-time global illumination (HIGH only — it's the GPU-heavy part):
	# light bounces off floors/walls, corners darken naturally, colour bleeds
	# subtly between surfaces. The constant ambient drops to a fraction — GI
	# replaces the fake uniform fill. LOW keeps the full ambient instead.
	env.sdfgi_enabled = high and info.get("gi", true)
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.4
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.15
	env.sdfgi_energy = 1.1
	if env.sdfgi_enabled:
		env.ambient_light_energy *= 0.25
	# Screen-space reflections ground objects on semi-glossy floors (HIGH only).
	env.ssr_enabled = high
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.4
	# On LOW, SSAO works a little harder since there's no GI doing occlusion.
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.4 if high else 1.9
	env.ssao_power = 1.5
	env.ssao_detail = 0.6
	env.ssil_enabled = info.get("ssil", false)
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.1
	# Glow only for true highlights (light fixtures), not a haze on everything.
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.2
	# Neutral grade — realism comes from light transport, not colour pushing.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	if info.get("fog", false):
		env.fog_enabled = true
		env.fog_light_color = info.get("fog_color", Color(0.72, 0.74, 0.80))
		env.fog_density = 0.01
		env.fog_aerial_perspective = 0.3
	else:
		env.fog_enabled = false
	# Honest sun: real angular size (~0.5 deg) gives crisp contact shadows that
	# soften naturally with distance, instead of one uniform blur everywhere.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.shadow_blur = 0.75
	_sun.light_angular_distance = 0.5
	_sun.light_color = Color(1.0, 0.96, 0.89)
	_sun.shadow_bias = 0.05


var _phys_sky_cache: Sky = null

## Physically-based sky — believable atmosphere + correct ambient/reflection
## source for outdoor-visible maps (replaces the cartoon gradient sky).
func _physical_sky() -> Sky:
	if _phys_sky_cache == null:
		_phys_sky_cache = Sky.new()
		_phys_sky_cache.sky_material = PhysicalSkyMaterial.new()
	return _phys_sky_cache


func _start_session_mode() -> void:
	# Connection was established by the menu/lobby; roles come from NetSession,
	# assigned when the host starts. Avatars spawn at start (lobby has none).
	# Force a clean lobby phase first: the GameState autoload persists across the
	# menu->game scene change, so a previous round could leave it at RESULTS/SEEK,
	# which hides the lobby overlay and blocks joiners from entering the new game.
	# (Emitting ASSIGN re-shows the lobby, which already ran _ready with stale state.)
	GameState.reset()
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
		# Let the map's colliders register in the physics space before we
		# shape-query for clear spawn points (else spawns can land in furniture).
		await get_tree().physics_frame
		await get_tree().physics_frame
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
		return  # something already moved us on (e.g. the lobby emptied out)
	_reset_to_lobby()
	print("[dedicated] round over — back to lobby")


@rpc("any_peer", "call_remote", "reliable")
func _sync_phase(phase: int, time_left: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		GameState.sync_phase(phase, time_left)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var n := _players.get_node_or_null(str(id))
	if n != null:
		n.queue_free()
	# Dedicated server, empty now: reset to a fresh lobby immediately instead of
	# leaving the round (PREP/SEEK/RESULTS) running for nobody — the next people
	# to connect must land in a clean ASSIGN lobby, not a stale/empty session.
	if NetSession.dedicated and NetSession.players.is_empty():
		_reset_to_lobby()


## Wipe any leftover avatars and drop to ASSIGN. Used both when the round ends
## (via _dedicated_reset_after) and immediately when the lobby empties out.
func _reset_to_lobby() -> void:
	for p in _players.get_children():
		p.queue_free()
	_started = false
	if GameState.phase != GameState.Phase.ASSIGN:
		GameState.set_phase(GameState.Phase.ASSIGN)
	print("[dedicated] lobby empty — reset to ASSIGN")


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
	# Tight grid CENTERED on spawn_base — the old wide grid pushed later joiners
	# several metres out, landing them inside the room's edge walls. Then nudge
	# the point off any wall/prop it still overlaps.
	var col := slot % 4
	var row := slot / 4
	var base := spawn_base + Vector3((float(col) - 1.5) * 1.4, 0.0, (float(row) - 1.0) * 1.4)
	return _clear_spawn(base)


## Host-side: move a spawn point to the nearest spot where a full STANDING body
## fits, spiralling outward so a cluttered room (couch/table/etc.) can't wedge a
## spawn inside furniture. Checks a body-height capsule (not a small sphere) so
## low furniture like a coffee table is caught too.
func _clear_spawn(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return pos
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1  # walls + furniture (the capsule sits above the floor)
	if _spawn_spot_clear(space, q, pos):
		return pos
	for ring in [1.0, 1.8, 2.6, 3.4]:
		for deg in range(0, 360, 40):
			var a := deg_to_rad(float(deg))
			var p: Vector3 = pos + Vector3(cos(a) * ring, 0.0, sin(a) * ring)
			if _spawn_spot_clear(space, q, p):
				return p
	return spawn_base  # last resort: the room centre


func _spawn_spot_clear(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, p: Vector3) -> bool:
	# (a) a standing-body capsule (~y 0.1..1.6) fits clear of furniture, AND
	# (b) the spot is in the same room as spawn_base — a ray to the room centre,
	#     run high (y 2.8, above the furniture but below the ceiling) so it only
	#     trips on WALLS, must be clear. Stops nudges escaping through a wall to
	#     outside the house.
	q.transform = Transform3D(Basis(), Vector3(p.x, 0.85, p.z))
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, 2.8, p.z), Vector3(spawn_base.x, 2.8, spawn_base.z))
	ray.collision_mask = 1
	return space.intersect_ray(ray).is_empty()
