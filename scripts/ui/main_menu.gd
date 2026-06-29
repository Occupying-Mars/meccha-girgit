extends Control
## Title screen: username, host (with mode) or join (with invite code).

const ROOT := "Center/Card/Margin/VBox"

@onready var _username: LineEdit = get_node(ROOT + "/UsernameRow/Username")
@onready var _mode: OptionButton = get_node(ROOT + "/ModeRow/Mode")
@onready var _hide_spin: SpinBox = get_node(ROOT + "/TimerRow/Hide")
@onready var _seek_spin: SpinBox = get_node(ROOT + "/TimerRow/Seek")
@onready var _map: OptionButton = get_node(ROOT + "/MapRow/Map")
@onready var _server_ip: LineEdit = get_node(ROOT + "/ServerRow/ServerIP")
@onready var _join_server_btn: Button = get_node(ROOT + "/JoinServerBtn")
@onready var _online: CheckBox = get_node(ROOT + "/OnlineCheck")
@onready var _relay_row: HBoxContainer = get_node(ROOT + "/RelayRow")
@onready var _relay: LineEdit = get_node(ROOT + "/RelayRow/Relay")
@onready var _code: LineEdit = get_node(ROOT + "/JoinRow/Code")
@onready var _status: Label = get_node(ROOT + "/Status")
@onready var _host_btn: Button = get_node(ROOT + "/HostBtn")
@onready var _join_btn: Button = get_node(ROOT + "/JoinRow/JoinBtn")


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
	_mode.add_item("Random seeker", NetSession.Mode.RANDOM)
	_mode.add_item("Decided seeker", NetSession.Mode.DECIDED)
	_map.clear()
	for id in NetGame.MAPS:
		_map.add_item(NetGame.MAPS[id]["label"])
		_map.set_item_metadata(_map.item_count - 1, id)
	_map.select(0)  # default = first map (Sponza)
	_host_btn.pressed.connect(_on_host)
	_join_btn.pressed.connect(_on_join)
	_join_server_btn.pressed.connect(_on_join_server)
	_online.toggled.connect(func (on): _relay_row.visible = on)


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
	NetSession.relay_address = _relay.text if _online.button_pressed else ""
	NetSession.prep_seconds = _hide_spin.value
	NetSession.seek_seconds = _seek_spin.value
	NetSession.selected_map = _map.get_item_metadata(_map.selected)
	_set_busy("Connecting to relay…" if _online.button_pressed else "Hosting…")
	var err: int = await NetSession.host_game(_username.text, _mode.get_selected_id(), _online.button_pressed)
	if err != OK:
		_set_error("Could not host (%s)." % error_string(err))
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)


func _on_join() -> void:
	NetSession.relay_address = _relay.text if _online.button_pressed else ""
	_set_busy("Connecting…")
	var err: int = await NetSession.join_game(_username.text, _code.text, _online.button_pressed)
	if err != OK:
		_set_error("Bad invite code or connection failed (%s)." % error_string(err))
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
