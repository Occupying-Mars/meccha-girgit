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
## Emitted on clients when the host's chosen map arrives, so the game scene can
## build it during the lobby (before anyone spawns).
signal map_changed

enum Mode { RANDOM, DECIDED }

const PORT := 24565
const MAX_PLAYERS := 12
const GAME_SCENE := "res://scenes/game/net_game.tscn"
## Default Noray relay. The public test relay is unreliable — self-host one and
## override it with the in-game Relay field (see docs/HOSTING_VPS.md).
const NORAY_HOST := "tomfol.io"
const NORAY_PORT := 8890
## Pre-configured dedicated server ("ip" or "ip:port"). EMPTY in the public repo
## so open-source builds default to peer hosting with invite codes. Set this as a
## LOCAL-ONLY override to point your build at your own VPS — the menu then detects
## it, defaults "Use your own server" on, and connects straight to it.
const DEFAULT_SERVER := ""  # set to your VPS "ip[:port]" as a LOCAL-ONLY override

var active: bool = false
var is_host: bool = false
## Dedicated server: the server runs on a VPS with NO player of its own, and
## everyone connects OUTBOUND to its public IP (works through any NAT, incl.
## symmetric). One connected client is the "admin" who starts the match.
var dedicated: bool = false
var admin_id: int = 1   # who controls the lobby (host=1 on LAN; first client when dedicated)
var username: String = "Player"
var mode: int = Mode.RANDOM
var decided_seeker_id: int = 1
var seeker_id: int = 1
## Map the host picked; replicated to everyone at match start so all players
## load the SAME arena. Keys must match NetGame.MAPS ("sponza" / "arena").
var selected_map: String = "sponza"
## Host-set round durations (seconds).
var prep_seconds: float = 45.0
var seek_seconds: float = 120.0
## id -> username
var players: Dictionary = {}

## Internet relay (Noray) vs LAN/direct-IP.
var online: bool = false
var online_oid: String = ""   # host's relay id == the online invite code
var host_oid: String = ""     # (client) the host's oid we're joining
## Relay server to use (host:port). Empty -> --noray CLI / default const.
## The public test relay is unreliable; point this at your own noray.
var relay_address: String = ""
## How long a client waits for the connection (NAT punch, then relay) to fully
## establish before giving up. We block on this so the menu never drops a player
## into the lobby while still disconnected ("stuck on Waiting for host").
## Generous, because the cross-network path is NAT-punch (fast-fail) + relay
## handshake + relay ENet connect, which adds up.
const CONNECT_TIMEOUT := 45.0
var _client_connected: bool = false
var _relay_tried: bool = false
## Set when noray sends a PID for THIS registration. Noray keeps the previous
## session's PID, so we must wait for a fresh one or re-hosting fails.
var _fresh_pid: bool = false

## --- Connection diagnostics (writes a step-by-step log to the Desktop) -------
var _net_t0: int = 0
var _netlog_lines: PackedStringArray = PackedStringArray()

func _netlog_start(role: String) -> void:
	_net_t0 = Time.get_ticks_msec()
	var ep := _noray_endpoint()
	_netlog_lines = PackedStringArray([
		"=== MECCHA GIRGIT connection log — role: %s ===" % role,
		"relay: %s:%s" % [ep.get("host"), ep.get("port")],
		"(send this whole file to whoever is hosting/debugging)",
		"",
	])
	_netlog("log started")

func _netlog(msg: String) -> void:
	var t := float(Time.get_ticks_msec() - _net_t0) / 1000.0
	var line := "[+%6.1fs] %s" % [t, msg]
	_netlog_lines.append(line)
	print("[netdiag] ", line)
	# Write to the Desktop (easy to find), falling back to the user data dir.
	for dir in [OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP), OS.get_user_data_dir()]:
		if dir == "":
			continue
		var f := FileAccess.open(dir.path_join("meccha_netlog.txt"), FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_netlog_lines))
			f.close()
			return


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
	_connect_once(multiplayer.peer_disconnected, _on_peer_disconnected)
	players_changed.emit()
	return OK


func join_game(uname: String, code: String, want_online: bool = false) -> int:
	username = _clean_name(uname)
	is_host = false
	online = want_online
	if want_online:
		return await _join_online(code.strip_edges())
	# Accept a LAN invite code OR a raw server address (VPS public IP) so people
	# can connect outbound to a dedicated server.
	var info := parse_invite(code)
	if info.is_empty():
		info = _parse_address(code)
	if info.is_empty():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(info["ip"], info["port"])
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	_connect_once(multiplayer.connected_to_server, _on_connected_to_server)
	_connect_once(multiplayer.server_disconnected, _reset)
	return OK


## Raw "host" or "host:port" (a VPS IP) -> {ip, port}. {} if it's not an address.
func _parse_address(s: String) -> Dictionary:
	var t := s.strip_edges()
	if t == "" or not t.contains("."):
		return {}
	var hp := t.split(":")
	return {"ip": hp[0], "port": int(hp[1]) if hp.size() > 1 else PORT}


## --- Dedicated server (runs on a VPS; no local player) ----------------------

func host_dedicated(game_mode: int) -> int:
	is_host = true
	dedicated = true
	mode = game_mode
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	players = {}        # the server is NOT a player
	admin_id = 0        # assigned to the first client that joins
	_connect_once(multiplayer.peer_disconnected, _on_peer_disconnected)
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
	if not Noray.on_pid.is_connected(_on_noray_pid):
		Noray.on_pid.connect(_on_noray_pid)
	var err: int = await Noray.connect_to_host(ep["host"], ep["port"])
	if err != OK:
		_netlog("could NOT reach relay %s:%s (%s)" % [ep["host"], ep["port"], error_string(err)])
		return err
	_netlog("reached relay %s:%s" % [ep["host"], ep["port"]])
	# Wait for a PID issued by THIS register-host. Noray keeps the PID from a
	# previous session, so checking `Noray.pid != ""` would pass instantly with
	# the stale id and register_remote() would fail ("Failed to register local
	# port") — which is why hosting a SECOND game broke. Wait for a fresh one.
	_fresh_pid = false
	Noray.register_host()
	var waited := 0.0
	while not _fresh_pid and waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not _fresh_pid:
		_netlog("relay never issued a PID (timed out)")
		push_error("[net] noray: no fresh PID — relay handshake failed/timed out")
		return ERR_TIMEOUT
	err = await Noray.register_remote()
	_netlog("registered our UDP port with relay: %s (local_port=%s)" % [error_string(err), Noray.local_port])
	return err


func _on_noray_pid(_pid: String) -> void:
	_fresh_pid = true


func _host_online() -> int:
	_netlog_start("HOST")
	var err := await _noray_register()
	if err != OK:
		_netlog("host registration FAILED: %s" % error_string(err))
		return err
	online_oid = Noray.oid  # this is the invite code
	_netlog("hosting OK, invite code = %s" % online_oid)
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
	_connect_once(multiplayer.peer_disconnected, _on_peer_disconnected)
	players_changed.emit()
	return OK


func _host_handshake(address: String, port: int) -> void:
	# A peer wants in — keep punching toward the relay/peer for a good while, so
	# the path stays open until the client's ENet connect (which over a relay can
	# only start ~10s in) actually lands.
	_netlog("host: got connect request, punching toward %s:%d for 25s" % [address, port])
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null:
		await PacketHandshake.over_enet_peer(peer, address, port, 25.0)
		_netlog("host: finished punching toward %s:%d" % [address, port])


func _join_online(oid: String) -> int:
	_netlog_start("JOINER")
	host_oid = oid
	_client_connected = false
	_relay_tried = false
	var err := await _noray_register()
	if err != OK:
		_netlog("joiner registration FAILED: %s" % error_string(err))
		return err
	if not Noray.on_connect_nat.is_connected(_client_connect_nat):
		Noray.on_connect_nat.connect(_client_connect_nat)
		Noray.on_connect_relay.connect(_client_connect_relay)
	_connect_once(multiplayer.connected_to_server, _on_connected_to_server)
	_connect_once(multiplayer.server_disconnected, _reset)
	_netlog("requesting NAT punch to host %s ..." % oid)
	Noray.connect_nat(oid)  # NAT punch first; the handlers fall back to relay
	# Block until we are ACTUALLY connected (via NAT or relay) or time out, so we
	# never hand control back to the menu — and load the lobby — while still
	# disconnected. That stale state is what left joiners on "Waiting for host".
	var waited := 0.0
	while not _client_connected and waited < CONNECT_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not _client_connected:
		_netlog("GAVE UP after %.1fs — never connected (tried relay: %s)" % [waited, _relay_tried])
		_netlog("=> we could SEND to the host/relay but apparently never got replies back.")
		_reset()
		return ERR_TIMEOUT
	_netlog("JOIN SUCCESS after %.1fs" % waited)
	active = true
	return OK


func _client_connect_nat(address: String, port: int) -> void:
	if _client_connected:
		return
	# NAT punch: fail FAST (short handshake + short connect wait) so that, when
	# home NATs won't cooperate (the common cross-house case), we fall through to
	# the relay quickly with most of the budget left.
	_netlog("NAT: host reachable at %s:%d, trying direct punch" % [address, port])
	var err := await _client_connect(address, port, 2.5, 5.0, "NAT")
	if err != OK and not _client_connected and not _relay_tried:
		_netlog("NAT punch failed — falling back to relay")
		_relay_tried = true
		Noray.connect_relay(host_oid)


func _client_connect_relay(address: String, port: int) -> void:
	if _client_connected:
		return
	# Relay: our reliable cross-network fallback — give it a generous budget.
	_netlog("RELAY: noray assigned relay at %s:%d" % [address, port])
	await _client_connect(address, port, 7.0, 22.0, "RELAY")


func _client_connect(address: String, port: int, hs_timeout: float = 7.0, enet_timeout: float = 20.0, via: String = "?") -> int:
	# Free any prior failed attempt first so its UDP port (our registered
	# local_port) is released before we bind it again for the relay attempt.
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		await get_tree().process_frame
	# Handshake from our registered local port, then ENet-connect through it.
	var udp := PacketPeerUDP.new()
	udp.bind(Noray.local_port)
	udp.set_dest_address(address, port)
	var err := await PacketHandshake.over_packet_peer(udp, hs_timeout)
	udp.close()
	# The handshake result is the key signal: OK = packets came BACK (two-way);
	# TIMEOUT = we sent but received NOTHING (our inbound is blocked — firewall/CGNAT).
	_netlog("%s: UDP handshake = %s" % [via, _hs_name(err)])
	if err != OK and err != ERR_BUSY:
		return err
	var peer := ENetMultiplayerPeer.new()
	err = peer.create_client(address, port, 0, 0, 0, Noray.local_port)
	if err != OK:
		_netlog("%s: create_client error: %s" % [via, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	var enet_waited := 0.0
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and enet_waited < enet_timeout:
		enet_waited += get_process_delta_time()
		await get_tree().process_frame
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_netlog("%s: ENet did NOT connect after %.1fs (status=%d) — host replies not reaching us" % [via, enet_waited, peer.get_connection_status()])
		peer.close()
		multiplayer.multiplayer_peer = null
		await get_tree().process_frame
		return ERR_CANT_CONNECT
	_netlog("%s: ENet CONNECTED in %.1fs ✓" % [via, enet_waited])
	_client_connected = true
	return OK


func _hs_name(err: int) -> String:
	match err:
		OK: return "TWO-WAY OK (replies received)"
		ERR_BUSY: return "PARTIAL (sent + read, no full ack)"
		ERR_TIMEOUT: return "TIMEOUT — got NOTHING back (inbound likely blocked: firewall/CGNAT)"
		_: return error_string(err)


## Invite code: the relay OID online, or the encoded host IP on LAN.
func invite_code() -> String:
	return online_oid if online else make_invite()


func _on_connected_to_server() -> void:
	_netlog("connected_to_server — telling host our name")
	_register_player.rpc_id(1, username)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		players.erase(id)
		# If the dedicated-server admin left, hand control to another player.
		if dedicated and id == admin_id:
			admin_id = int(players.keys()[0]) if not players.is_empty() else 0
		_broadcast_players()


@rpc("any_peer", "call_remote", "reliable")
func _register_player(uname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = _clean_name(uname)
	# First client on a dedicated server becomes the admin (can start the match).
	if dedicated and (admin_id == 0 or not players.has(admin_id)):
		admin_id = id
	_netlog("host: peer %d JOINED as '%s' ✓" % [id, _clean_name(uname)])
	_broadcast_players()
	# Tell the newcomer which map to build, so it's ready before the match starts.
	_sync_map.rpc_id(id, selected_map)


@rpc("authority", "call_remote", "reliable")
func _sync_map(map_id: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		selected_map = map_id
		map_changed.emit()


func _broadcast_players() -> void:
	_sync_players.rpc(players)
	if dedicated:
		_sync_admin.rpc(admin_id)
	players_changed.emit()  # host's own UI


@rpc("any_peer", "call_remote", "reliable")
func _sync_players(p: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		players = p
		players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_admin(aid: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		dedicated = true
		admin_id = aid
		players_changed.emit()


## True if THIS peer controls the lobby (LAN host, or the dedicated-server admin).
func is_admin() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	return multiplayer.get_unique_id() == admin_id


## Start the match — works whether we're the server (LAN host) or the admin
## client of a dedicated server.
func request_start() -> void:
	if multiplayer.is_server():
		start_game()
	else:
		_server_start.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _server_start() -> void:
	if multiplayer.is_server() and dedicated and multiplayer.get_remote_sender_id() == admin_id:
		start_game()


## --- Start ------------------------------------------------------------------

func start_game() -> void:
	if not is_host:
		return
	var ids := players.keys()
	if ids.is_empty():
		return
	var sid := decided_seeker_id if mode == Mode.DECIDED else int(ids[randi() % ids.size()])
	# sid == 0 means "nobody seeks" (everyone hides) — keep it; only fix
	# genuinely invalid non-zero ids.
	if sid != 0 and not players.has(sid):
		sid = int(ids[0])
	_begin.rpc(sid, selected_map)
	_begin(sid, selected_map)  # host runs it too


@rpc("authority", "call_remote", "reliable")
func _begin(sid: int, map_id: String) -> void:
	seeker_id = sid
	selected_map = map_id  # everyone builds the host's chosen map
	started.emit()


func role_for(id: int) -> int:
	# 0 = HIDER, 1 = SEEKER (matches NetPlayer.Role).
	return 1 if id == seeker_id else 0


## Client: connect straight to a dedicated server by IP:port (the most
## firewall/CGNAT-friendly path — we only ever initiate outbound to a public IP).
func join_server(uname: String, address: String, port: int = PORT) -> int:
	username = _clean_name(uname)
	is_host = false
	online = false
	dedicated = false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_connect_once(multiplayer.connected_to_server, _on_connected_to_server)
	_connect_once(multiplayer.server_disconnected, _reset)
	# Block until actually connected, so we don't load the lobby while connecting.
	var waited := 0.0
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and waited < CONNECT_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_reset()
		return ERR_CANT_CONNECT
	active = true
	return OK


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
	dedicated = false
	admin_id = 1
	players.clear()
	multiplayer.multiplayer_peer = null


## Leave the current match and tear down networking (used by the results menu).
func leave() -> void:
	if Noray.is_connected_to_host():
		Noray.disconnect_from_host()
	multiplayer.multiplayer_peer = null
	active = false
	is_host = false
	dedicated = false
	admin_id = 1
	online = false
	online_oid = ""
	host_oid = ""
	players.clear()
	GameState.authoritative = true


func _clean_name(n: String) -> String:
	var s := n.strip_edges()
	return s if s != "" else "Player"


## Connect a signal only if not already connected — these handlers persist on
## the MultiplayerAPI across host/join attempts, so re-hosting would otherwise
## raise "Signal is already connected" and pile up duplicate callbacks.
func _connect_once(sig: Signal, cb: Callable) -> void:
	if not sig.is_connected(cb):
		sig.connect(cb)
