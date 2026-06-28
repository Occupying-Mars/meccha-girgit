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
	_add_player(1)  # host's own avatar


func join(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		push_error("[net] failed to connect to %s: %s" % [ip, error_string(err)])
		return
	multiplayer.multiplayer_peer = peer
	print("[net] connecting to ", ip, ":", PORT)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[net] peer connected: ", id)
		_add_player(id)


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


func _spawn_pos(slot: int) -> Vector3:
	# Spread spawns by join order so avatars never overlap (grid along z=6).
	var col := slot % 6
	var row := slot / 6
	return Vector3(-5.0 + float(col) * 2.0, 0.1, 6.0 + float(row) * 2.0)
