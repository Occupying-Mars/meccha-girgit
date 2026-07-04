extends Node
## Epic Online Services backend (autoload "EOSNet"). Gives open-source, no-VPS
## internet play: anyone hosts from their own PC and hands friends a lobby code
## that works through any NAT/CGNAT — Epic runs the punchthrough + relay for
## free. Players need NO Epic account (anonymous Device-ID auth).
##
## The four IDs below are this product's PUBLIC identifiers (shipped in every
## EOS game — not secrets). CLIENT_SECRET, however, IS sensitive — it's left
## empty in the public repo; set it as a LOCAL-ONLY override from the Epic
## dev portal's Clients page (Product Settings > Clients) to build/run this.
##
## EOSMultiplayerPeer.create_server/create_client preserve the game's existing
## host-authoritative model (host = peer 1), so net_session just swaps this peer
## in for ENet — nothing else in the game changes.

const PRODUCT_NAME := "MecchaGirgit"
const PRODUCT_VERSION := "1.0.0"
const PRODUCT_ID := "54d84ebbd7a54a18aef4a5c6cd062492"
const SANDBOX_ID := "2002e495d95341258d3ded0a789e2e6c"
const DEPLOYMENT_ID := "1110b4ec630b446b8735fe413fc049ed"
const CLIENT_ID := "xyza7891Ayg60Y033PbTZc4mFsl5QSQq"
const CLIENT_SECRET := ""  # set as a LOCAL-ONLY override — get yours from the Epic dev portal
## 64 hex chars; required by platform_create. Not sensitive for P2P/lobbies.
const ENCRYPTION_KEY := "1111111111111111111111111111111111111111111111111111111111111111"
const SOCKET_ID := "meccha"       # shared P2P socket name (host + clients match)
const BUCKET_ID := "meccha_hns"   # lobby bucket

const MAX_MEMBERS := 12

signal login_finished(ok: bool)

var available: bool = false        # EOS classes present + platform created
var logged_in: bool = false
var product_user_id: EOSProductUserId = null
var current_lobby_id: String = ""
var last_error: String = ""

var _init_done: bool = false
var _login_in_flight: bool = false
## Test-only: distinguishes two instances on ONE machine (which otherwise share
## a device id -> the same product user). Empty in production (each real machine
## already has a distinct device id).
var device_suffix: String = ""


func _ready() -> void:
	# GD-EOS may be absent (e.g. a build without the addon) — fail soft so the
	# rest of the menu (LAN / Direct / VPS) keeps working.
	if not ClassDB.class_exists("EOSPlatform"):
		last_error = "EOS plugin not installed in this build."
		return
	_initialize()


func _initialize() -> void:
	if _init_done:
		return
	var init_options := EOSInitializeOptions.new()
	init_options.product_name = PRODUCT_NAME
	init_options.product_version = PRODUCT_VERSION
	var rc: int = EOS.initialize(init_options)
	# AlreadyConfigured is fine (a second instance in the same process).
	if rc != EOS.Success and rc != EOS.AlreadyConfigured:
		last_error = "EOS initialize failed: %s" % EOS.result_to_string(rc)
		push_warning("[eos] " + last_error)
		return
	EOS.set_log_level(EOS.LC_ALL_CATEGORIES, EOS.LOG_Warning)
	EOS.set_logging_callback(_on_eos_log)

	var opts := EOSPlatform_Options.new()
	opts.product_id = PRODUCT_ID
	opts.sandbox_id = SANDBOX_ID
	opts.deployment_id = DEPLOYMENT_ID
	opts.client_credentials = EOSPlatform_ClientCredentials.new()
	opts.client_credentials.client_id = CLIENT_ID
	opts.client_credentials.client_secret = CLIENT_SECRET
	opts.encryption_key = ENCRYPTION_KEY
	if OS.get_name() == "Windows":
		opts.flags |= EOSPlatform.PF_DISABLE_OVERLAY
	else:
		opts.flags = EOSPlatform.PF_DISABLE_OVERLAY
	EOSPlatform.platform_create(opts)
	_init_done = true
	available = true
	set_process(true)  # EOS must be ticked every frame or no async callback fires
	# Route P2P through Epic's relays. Most reliable across NAT/CGNAT (and lets
	# two instances on one machine connect for testing). Godot interpolates
	# remote players so the small relay hop is unnoticeable for this game.
	EOSP2P.set_relay_control(EOSP2P.RC_ForceRelays)
	print("[eos] platform created for product ", PRODUCT_ID)


func _process(_delta: float) -> void:
	if available:
		EOSPlatform.tick()


## Anonymous Device-ID login — no Epic account needed. Idempotent; returns true
## once we have a product user id. Safe to await from host/join paths.
func login_device() -> bool:
	if logged_in:
		return true
	if not available:
		return false
	if _login_in_flight:
		# Another caller is mid-login — wait for it to finish.
		var ok: bool = await login_finished
		return ok
	_login_in_flight = true

	var cdid: int = await EOSConnect.create_device_id(OS.get_name() + ":" + OS.get_model_name() + device_suffix)
	if cdid != EOS.Success and cdid != EOS.DuplicateNotAllowed:
		return _finish_login(false, "create_device_id failed: %s" % EOS.result_to_string(cdid))

	var creds := EOSConnect_Credentials.new()
	creds.type = EOS.ECT_DEVICEID_ACCESS_TOKEN
	var info := EOSConnect_UserLoginInfo.new()
	var dn := OS.get_unique_id()
	if dn.length() > EOSConnect.CONNECT_USERLOGININFO_DISPLAYNAME_MAX_LENGTH:
		dn = dn.substr(0, EOSConnect.CONNECT_USERLOGININFO_DISPLAYNAME_MAX_LENGTH)
	info.display_name = dn if not dn.is_empty() else "Player"

	var res: EOSConnect_LoginCallbackInfo = await EOSConnect.login(creds, info)
	if res.result_code == EOS.InvalidUser:
		# First time on this device — create the product user, then we're in.
		var cu: EOSConnect_CreateUserCallbackInfo = await EOSConnect.create_user(res.continuance_token)
		if cu.result_code != EOS.Success:
			return _finish_login(false, "create_user failed: %s" % EOS.result_to_string(cu.result_code))
		product_user_id = cu.local_user_id
	elif res.result_code != EOS.Success:
		return _finish_login(false, "connect login failed: %s" % EOS.result_to_string(res.result_code))
	else:
		product_user_id = res.local_user_id
	return _finish_login(true, "")


func _finish_login(ok: bool, err: String) -> bool:
	_login_in_flight = false
	logged_in = ok
	if not ok:
		last_error = err
		push_warning("[eos] " + err)
	else:
		print("[eos] logged in, puid=", product_user_id)
	login_finished.emit(ok)
	return ok


## --- Host / join by code ----------------------------------------------------
## Host a game: log in, create an EOS lobby whose id IS the invite `code`, then
## stand up an EOSMultiplayerPeer SERVER (host = peer 1, exactly like ENet).
## Returns OK / an error int; sets multiplayer.multiplayer_peer on success.
func create_and_host(code: String) -> int:
	if not await login_device():
		return FAILED
	var opts := EOSLobby_CreateLobbyOptions.new()
	opts.lobby_id = code                       # the invite code == the lobby id
	opts.local_user_id = product_user_id
	opts.max_lobby_members = MAX_MEMBERS
	opts.bucket_id = BUCKET_ID
	opts.permission_level = EOSLobby.LPL_PUBLICADVERTISED
	opts.enable_join_by_id = true              # friends join with just the code
	opts.presence_enabled = false
	opts.allow_invites = true
	var r: EOSLobby_CreateLobbyCallbackInfo = await EOSLobby.create_lobby(opts)
	if r.result_code != EOS.Success:
		last_error = "create lobby failed: %s" % EOS.result_to_string(r.result_code)
		return FAILED
	current_lobby_id = r.lobby_id
	var peer := EOSMultiplayerPeer.new()
	peer.set_auto_accept_connection_requests(true)  # accept joining clients' P2P
	var pr: int = peer.create_server(current_lobby_id)  # socket keyed to the lobby
	if pr != OK:
		last_error = "create_server failed (%d)" % pr
		return pr
	multiplayer.multiplayer_peer = peer
	print("[eos] hosting lobby ", current_lobby_id)
	return OK


## Join a game by its invite code: log in, join the lobby by id, look up the
## lobby owner (the host) and open an EOSMultiplayerPeer CLIENT toward them.
func join_by_code(code: String) -> int:
	if not await login_device():
		return FAILED
	var opts := EOSLobby_JoinLobbyByIdOptions.new()
	opts.lobby_id = code
	opts.local_user_id = product_user_id
	opts.presence_enabled = false
	var r: EOSLobby_JoinLobbyByIdCallbackInfo = await EOSLobby.join_lobby_by_id(opts)
	if r.result_code != EOS.Success:
		last_error = "join lobby failed: %s" % EOS.result_to_string(r.result_code)
		return FAILED
	current_lobby_id = r.lobby_id
	var details := EOSLobby.copy_lobby_details(current_lobby_id, product_user_id)
	if not is_instance_valid(details):
		last_error = "could not read lobby details"
		return FAILED
	var host_uid: EOSProductUserId = details.get_lobby_owner()
	print("[eos] join: host_uid valid=", is_instance_valid(host_uid), " members=", details.get_member_count())
	var peer := EOSMultiplayerPeer.new()
	peer.set_auto_accept_connection_requests(true)
	var pr: int = peer.create_client(current_lobby_id, host_uid)
	if pr != OK:
		last_error = "create_client failed (%d)" % pr
		return pr
	multiplayer.multiplayer_peer = peer
	print("[eos] joined lobby ", current_lobby_id)
	return OK


## Leave/destroy the current lobby (host destroys it; clients just leave).
func leave_lobby() -> void:
	if current_lobby_id.is_empty() or product_user_id == null:
		return
	var details := EOSLobby.copy_lobby_details(current_lobby_id, product_user_id)
	if is_instance_valid(details) and details.get_lobby_owner() == product_user_id:
		EOSLobby.destroy_lobby(product_user_id, current_lobby_id)
	else:
		EOSLobby.leave_lobby(product_user_id, current_lobby_id)
	current_lobby_id = ""


func _on_eos_log(category: String, message: String, level: int) -> void:
	if level <= EOS.LOG_Warning:  # warnings + errors only
		push_warning("[eos:%s] %s" % [category, message])
