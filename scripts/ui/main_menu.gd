extends Control
## Title screen: username, host (with mode) or join (with invite code).

const ROOT := "Center/Card/Margin/VBox"
## How friends reach a peer-hosted game (irrelevant when "Use your own server"
## is on — that always connects outbound to the configured dedicated server).
## LAN: same Wi-Fi/network only. DIRECT: host's own PC, reachable over the
## internet via a UPnP-forwarded port + public IP (no relay needed). RELAY:
## routed through a Noray relay server (works even if UPnP is unavailable).
enum HostVia { LAN, DIRECT, RELAY }

@onready var _username: LineEdit = get_node(ROOT + "/UsernameRow/Username")
@onready var _mode: OptionButton = get_node(ROOT + "/ModeRow/Mode")
@onready var _hide_spin: SpinBox = get_node(ROOT + "/TimerRow/Hide")
@onready var _seek_spin: SpinBox = get_node(ROOT + "/TimerRow/Seek")
@onready var _map: OptionButton = get_node(ROOT + "/MapRow/Map")
@onready var _server_ip: LineEdit = get_node(ROOT + "/ServerRow/ServerIP")
@onready var _join_server_btn: Button = get_node(ROOT + "/JoinServerBtn")
@onready var _host_via_row: HBoxContainer = get_node(ROOT + "/HostViaRow")
@onready var _host_via: OptionButton = get_node(ROOT + "/HostViaRow/HostVia")
@onready var _relay_row: HBoxContainer = get_node(ROOT + "/RelayRow")
@onready var _relay: LineEdit = get_node(ROOT + "/RelayRow/Relay")
@onready var _code: LineEdit = get_node(ROOT + "/JoinRow/Code")
@onready var _status: Label = get_node(ROOT + "/Status")
@onready var _host_btn: Button = get_node(ROOT + "/HostBtn")
@onready var _join_btn: Button = get_node(ROOT + "/JoinRow/JoinBtn")
@onready var _use_server: CheckBox = get_node(ROOT + "/UseServerCheck")
@onready var _mode_row: HBoxContainer = get_node(ROOT + "/ModeRow")
@onready var _map_row: HBoxContainer = get_node(ROOT + "/MapRow")
@onready var _timer_row: HBoxContainer = get_node(ROOT + "/TimerRow")
@onready var _server_row: HBoxContainer = get_node(ROOT + "/ServerRow")
@onready var _join_row: HBoxContainer = get_node(ROOT + "/JoinRow")
@onready var _sep: HSeparator = get_node(ROOT + "/Sep")
var _advanced: CheckBox


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Headless launch hooks (the exported build boots into this menu scene):
	#   --dedicated [--port=N] [--map=NAME]  -> run as a dedicated server
	#   --joinserver=IP[:port]               -> auto-join a dedicated server
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s == "--dedicated":
			get_tree().change_scene_to_file(NetSession.GAME_SCENE)  # net_game handles it
			return
		if s.begins_with("--joinserver="):
			_auto_join(s.substr("--joinserver=".length()))
			return
	_mode.clear()
	_mode.add_item("Normal", 0)         # caught hiders are out
	_mode.add_item("Infection", 1)      # caught hiders turn seeker
	_mode.add_item("Double seeker", 2)  # two seekers (needs 3+ players)
	_map.clear()
	for id in NetGame.MAPS:
		_map.add_item(NetGame.MAPS[id]["label"])
		_map.set_item_metadata(_map.item_count - 1, id)
	_map.select(0)  # default = first map (Sponza)
	_host_btn.pressed.connect(_on_host)
	_join_btn.pressed.connect(_on_join)
	_join_server_btn.pressed.connect(_on_join_server)
	_host_via.clear()
	_host_via.add_item("Local network (LAN)", HostVia.LAN)
	_host_via.add_item("Direct — auto port-forward (internet)", HostVia.DIRECT)
	_host_via.add_item("Relay (Noray) — works anywhere", HostVia.RELAY)
	_host_via.select(HostVia.DIRECT)  # best default: no relay to run/own, works over the internet
	_host_via.item_selected.connect(_on_host_via_selected)
	# Server vs peer-host. A configured DEFAULT_SERVER (your VPS) pre-fills the
	# field and defaults "Use your own server" on; open-source builds (empty)
	# default to peer hosting with invite codes.
	_server_ip.text = NetSession.DEFAULT_SERVER
	_use_server.button_pressed = NetSession.DEFAULT_SERVER.strip_edges() != ""
	_use_server.toggled.connect(_on_use_server_toggled)
	# "More options" reveals the host timers + relay override (off by default).
	_advanced = CheckBox.new()
	_advanced.text = "More options"
	_advanced.add_theme_font_size_override("font_size", 13)
	var vbox: VBoxContainer = _timer_row.get_parent()
	vbox.add_child(_advanced)
	vbox.move_child(_advanced, _timer_row.get_index())
	_advanced.toggled.connect(func (_v): _on_use_server_toggled(_use_server.button_pressed))
	_style_menu()
	_on_use_server_toggled(_use_server.button_pressed)


func _set_busy(text: String) -> void:
	_status.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
	_status.text = text
	_host_btn.disabled = true
	_join_btn.disabled = true


func _set_error(text: String) -> void:
	_status.add_theme_color_override("font_color", Color(1, 0.42, 0.42))
	_status.text = text
	_host_btn.disabled = false
	_join_btn.disabled = false


func _style_menu() -> void:
	# Clean, consistent styling so the card reads as a tidy panel, not a stack of
	# default grey widgets. Accent-green buttons, dark rounded inputs.
	var th := Theme.new()
	th.default_font_size = 15
	th.set_stylebox("normal", "Button", _sb(Color(0.22, 0.46, 0.33)))
	th.set_stylebox("hover", "Button", _sb(Color(0.28, 0.56, 0.40)))
	th.set_stylebox("pressed", "Button", _sb(Color(0.17, 0.36, 0.26)))
	th.set_stylebox("focus", "Button", _sb(Color(0.22, 0.46, 0.33)))
	th.set_color("font_color", "Button", Color(0.93, 1.0, 0.96))
	var inp := _sb(Color(0.07, 0.08, 0.12))
	inp.set_border_width_all(1)
	inp.border_color = Color(0.24, 0.26, 0.34)
	for cls in ["LineEdit", "OptionButton", "SpinBox"]:
		th.set_stylebox("normal", cls, inp)
	th.set_color("font_color", "OptionButton", Color(0.88, 0.9, 0.95))
	get_node("Center/Card").theme = th


func _sb(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(7)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


func _on_use_server_toggled(on: bool) -> void:
	# ON: connect to a dedicated VPS — it controls the map / mode / timing, so we
	# hide those. OFF: host or join peer-to-peer with an invite code.
	_server_row.visible = on
	_join_server_btn.visible = on
	_mode_row.visible = not on
	_map_row.visible = not on
	_host_via_row.visible = not on
	_host_btn.visible = not on
	_sep.visible = not on
	_join_row.visible = not on
	_advanced.visible = not on  # host-only knobs; irrelevant when joining a server
	# Tucked away to declutter — sensible defaults (45s hide / 120s seek) and the
	# relay address from config are used unless the player opens "More options".
	_timer_row.visible = _advanced.button_pressed and not on
	_relay_row.visible = _advanced.button_pressed and not on and _host_via.selected == HostVia.RELAY


func _on_host_via_selected(_index: int) -> void:
	_relay_row.visible = _advanced.button_pressed and _host_via.selected == HostVia.RELAY


func _on_join_server() -> void:
	var addr := _server_ip.text.strip_edges()
	if addr == "":
		_set_error("Enter a server IP.")
		return
	var parts := addr.split(":")
	var ip := parts[0]
	var port := int(parts[1]) if parts.size() > 1 else NetSession.PORT
	_set_busy("Connecting to server…")
	var err: int = await NetSession.join_server(_username.text, ip, port)
	if err != OK:
		_set_error("Could not reach server (%s)." % error_string(err))
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)


func _auto_join(addr: String) -> void:
	var parts := addr.split(":")
	var ip := parts[0]
	var port := int(parts[1]) if parts.size() > 1 else NetSession.PORT
	var err: int = await NetSession.join_server("Bot%d" % (randi() % 1000), ip, port)
	print("[joinserver] connect to %s:%d -> %s" % [ip, port, error_string(err)])
	if err == OK:
		get_tree().change_scene_to_file(NetSession.GAME_SCENE)
	else:
		get_tree().quit(1)


func _on_host() -> void:
	var via := _host_via.selected
	NetSession.relay_address = _relay.text if via == HostVia.RELAY else ""
	NetSession.prep_seconds = _hide_spin.value
	NetSession.seek_seconds = _seek_spin.value
	NetSession.selected_map = _map.get_item_metadata(_map.selected)
	NetSession.game_mode = _mode.get_selected_id()  # 0 Normal · 1 Infection · 2 Double
	var err: int
	match via:
		HostVia.RELAY:
			_set_busy("Connecting to relay…")
			err = await NetSession.host_game(_username.text, NetSession.Mode.RANDOM, true)
		HostVia.DIRECT:
			_set_busy("Hosting… checking your router for internet access…")
			err = NetSession.host_direct(_username.text, NetSession.Mode.RANDOM)
		_:
			_set_busy("Hosting…")
			err = await NetSession.host_game(_username.text, NetSession.Mode.RANDOM, false)
	if err != OK:
		_set_error("Could not host (%s)." % error_string(err))
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)


func _on_join() -> void:
	var via_relay := _host_via.selected == HostVia.RELAY
	NetSession.relay_address = _relay.text if via_relay else ""
	_set_busy("Connecting…")
	# LAN and DIRECT joins are identical on the client side — both are just an
	# outbound connect to an ip:port decoded from the invite code.
	var err: int = await NetSession.join_game(_username.text, _code.text, via_relay)
	if err != OK:
		_set_error("Bad invite code or connection failed (%s)." % error_string(err))
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
