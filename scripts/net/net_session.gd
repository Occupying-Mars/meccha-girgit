extends Node
## Connection + lobby state that persists across the menu -> game scene change
## (the ENet peer lives on the MultiplayerAPI, not the scene).
##
## Flow: main menu calls host_game()/join_game(); players gather in a lobby
## (usernames synced); the host picks a mode and starts. Roles are assigned at
## start: RANDOM picks a random seeker, DECIDED uses the host's chosen player.
##
## When `active` is false the game runs in CLI test mode (net_game self-hosts
## from --server/--client), so existing headless tests are unaffected.

signal players_changed
signal started

enum Mode { RANDOM, DECIDED }

const PORT := 24565
const MAX_PLAYERS := 12
const GAME_SCENE := "res://scenes/game/net_game_sponza.tscn"
## Public Noray test relay (no accounts). Self-host for shipping.
const NORAY_HOST := "tomfol.io"
const NORAY_PORT := 8890

var active: bool = false
var is_host: bool = false
var username: String = "Player"
var mode: int = Mode.RANDOM
var decided_seeker_id: int = 1
var seeker_id: int = 1
## id -> username
var players: Dictionary = {}

## Internet relay (Noray) vs LAN/direct-IP.
var online: bool = false
var online_oid: String = ""   # host's relay id == the online invite code
var host_oid: String = ""     # (client) the host's oid we're joining
## Relay server to use (host:port). Empty -> --noray CLI / default const.
## The public test relay is unreliable; point this at your own noray.
var relay_address: String = ""


## --- Connection -------------------------------------------------------------

func host_game(uname: String, game_mode: int, want_online: bool = false) -> int:
	username = _clean_name(uname)
	mode = game_mode
	is_host = true
	decided_seeker_id = 1
	online = want_online
	if want_online:
		return await _host_online()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	players = {1: username}
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	players_changed.emit()
	return OK


func join_game(uname: String, code: String, want_online: bool = false) -> int:
	username = _clean_name(uname)
	is_host = false
	online = want_online
	if want_online:
		return await _join_online(code.strip_edges())
	var info := parse_invite(code)
	if info.is_empty():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(info["ip"], info["port"])
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_reset)
	return OK


## --- Internet relay via Noray (NAT punchthrough + relay fallback) ------------

func _noray_endpoint() -> Dictionary:
	# Priority: in-game relay field > --noray CLI override > default const.
	if relay_address.strip_edges() != "":
		return _split_endpoint(relay_address)
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--noray="):
			return _split_endpoint(a.substr("--noray=".length()))
	return {"host": NORAY_HOST, "port": NORAY_PORT}


func _split_endpoint(s: String) -> Dictionary:
	var hp := s.strip_edges().split(":")
	return {"host": hp[0], "port": int(hp[1]) if hp.size() > 1 else NORAY_PORT}


func _noray_register() -> int:
	# Connect to the relay, get our ids, and register our remote address.
	var ep := _noray_endpoint()
	var err: int = await Noray.connect_to_host(ep["host"], ep["port"])
	if err != OK:
		return err
	Noray.register_host()
	# Poll for the PID rather than awaiting on_pid — noray can emit it during
	# the connect step (before we'd await the signal), so the signal is missed.
	var waited := 0.0
	while Noray.pid == "" and waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if Noray.pid == "":
		push_error("[net] noray: no PID — relay handshake failed/timed out")
		return ERR_TIMEOUT
	err = await Noray.register_remote()
	return err


func _host_online() -> int:
	var err := await _noray_register()
	if err != OK:
		return err
	online_oid = Noray.oid  # this is the invite code
	if not Noray.on_connect_nat.is_connected(_host_handshake):
		Noray.on_connect_nat.connect(_host_handshake)
		Noray.on_connect_relay.connect(_host_handshake)
	var peer := ENetMultiplayerPeer.new()
	err = peer.create_server(Noray.local_port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		await get_tree().process_frame
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return FAILED
	multiplayer.server_relay = true
	active = true
	players = {1: username}
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	players_changed.emit()
	return OK


func _host_handshake(address: String, port: int) -> void:
	# A peer wants in — punch a hole so ENet can accept them.
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null:
		await PacketHandshake.over_enet_peer(peer, address, port)


func _join_online(oid: String) -> int:
	host_oid = oid
	var err := await _noray_register()
	if err != OK:
		return err
	active = true
	if not Noray.on_connect_nat.is_connected(_client_connect_nat):
		Noray.on_connect_nat.connect(_client_connect_nat)
		Noray.on_connect_relay.connect(_client_connect_relay)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_reset)
	Noray.connect_nat(oid)  # connection completes async via the handlers
	return OK


func _client_connect_nat(address: String, port: int) -> void:
	var err := await _client_connect(address, port)
	if err != OK:  # NAT punch failed — fall back to the relay
		Noray.connect_relay(host_oid)


func _client_connect_relay(address: String, port: int) -> void:
	await _client_connect(address, port)


func _client_connect(address: String, port: int) -> int:
	# Handshake from our registered local port, then ENet-connect through it.
	var udp := PacketPeerUDP.new()
	udp.bind(Noray.local_port)
	udp.set_dest_address(address, port)
	var err := await PacketHandshake.over_packet_peer(udp)
	udp.close()
	if err != OK and err != ERR_BUSY:
		return err
	var peer := ENetMultiplayerPeer.new()
	err = peer.create_client(address, port, 0, 0, 0, Noray.local_port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		await get_tree().process_frame
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		multiplayer.multiplayer_peer = null
		return ERR_CANT_CONNECT
	return OK


## Invite code: the relay OID online, or the encoded host IP on LAN.
func invite_code() -> String:
	return online_oid if online else make_invite()


func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, username)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		players.erase(id)
		_broadcast_players()


@rpc("any_peer", "call_remote", "reliable")
func _register_player(uname: String) -> void:
	if not multiplayer.is_server():
		return
	players[multiplayer.get_remote_sender_id()] = _clean_name(uname)
	_broadcast_players()


func _broadcast_players() -> void:
	_sync_players.rpc(players)
	players_changed.emit()  # host's own UI


@rpc("any_peer", "call_remote", "reliable")
func _sync_players(p: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		players = p
		players_changed.emit()


## --- Start ------------------------------------------------------------------

func start_game() -> void:
	if not is_host:
		return
	var ids := players.keys()
	if ids.is_empty():
		return
	var sid := decided_seeker_id if mode == Mode.DECIDED else int(ids[randi() % ids.size()])
	if not players.has(sid):
		sid = int(ids[0])
	_begin.rpc(sid)
	_begin(sid)  # host runs it too


@rpc("authority", "call_remote", "reliable")
func _begin(sid: int) -> void:
	seeker_id = sid
	started.emit()


func role_for(id: int) -> int:
	# 0 = HIDER, 1 = SEEKER (matches NetPlayer.Role).
	return 1 if id == seeker_id else 0


## --- Invite code (encodes host IP:port) -------------------------------------

func local_ip() -> String:
	for addr in IP.get_local_addresses():
		var s := String(addr)
		if s.count(".") == 3 and not s.begins_with("127.") and not s.begins_with("169.254"):
			return s
	return "127.0.0.1"

func make_invite() -> String:
	var ip := local_ip()
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var n := (int(parts[0]) << 24) | (int(parts[1]) << 16) | (int(parts[2]) << 8) | int(parts[3])
	return "%08X%04X" % [n, PORT]

func parse_invite(code: String) -> Dictionary:
	var c := code.strip_edges().to_upper().replace("-", "")
	if c.length() != 12 or not c.is_valid_hex_number():
		return {}
	var n := ("0x" + c.substr(0, 8)).hex_to_int()
	var port := ("0x" + c.substr(8, 4)).hex_to_int()
	var ip := "%d.%d.%d.%d" % [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255]
	return {"ip": ip, "port": port}


func _reset() -> void:
	active = false
	is_host = false
	players.clear()
	multiplayer.multiplayer_peer = null


func _clean_name(n: String) -> String:
	var s := n.strip_edges()
	return s if s != "" else "Player"
