extends Control
## Title screen: username, host (with mode) or join (with invite code).

const ROOT := "Center/Card/Margin/VBox"

@onready var _username: LineEdit = get_node(ROOT + "/UsernameRow/Username")
@onready var _mode: OptionButton = get_node(ROOT + "/ModeRow/Mode")
@onready var _online: CheckBox = get_node(ROOT + "/OnlineCheck")
@onready var _relay_row: HBoxContainer = get_node(ROOT + "/RelayRow")
@onready var _relay: LineEdit = get_node(ROOT + "/RelayRow/Relay")
@onready var _code: LineEdit = get_node(ROOT + "/JoinRow/Code")
@onready var _status: Label = get_node(ROOT + "/Status")
@onready var _host_btn: Button = get_node(ROOT + "/HostBtn")
@onready var _join_btn: Button = get_node(ROOT + "/JoinRow/JoinBtn")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mode.clear()
	_mode.add_item("Random seeker", NetSession.Mode.RANDOM)
	_mode.add_item("Decided seeker", NetSession.Mode.DECIDED)
	_host_btn.pressed.connect(_on_host)
	_join_btn.pressed.connect(_on_join)
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


func _on_host() -> void:
	NetSession.relay_address = _relay.text if _online.button_pressed else ""
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
