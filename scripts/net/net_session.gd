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

var active: bool = false
var is_host: bool = false
var username: String = "Player"
var mode: int = Mode.RANDOM
var decided_seeker_id: int = 1
var seeker_id: int = 1
## id -> username
var players: Dictionary = {}


## --- Connection -------------------------------------------------------------

func host_game(uname: String, game_mode: int) -> int:
	username = _clean_name(uname)
	mode = game_mode
	is_host = true
	decided_seeker_id = 1
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


func join_game(uname: String, code: String) -> int:
	username = _clean_name(uname)
	is_host = false
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
