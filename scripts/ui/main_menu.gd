extends Control
## Title screen: username, host (with mode) or join (with invite code).

@onready var _username: LineEdit = $Center/VBox/UsernameRow/Username
@onready var _mode: OptionButton = $Center/VBox/ModeRow/Mode
@onready var _online: CheckBox = $Center/VBox/OnlineCheck
@onready var _code: LineEdit = $Center/VBox/JoinRow/Code
@onready var _status: Label = $Center/VBox/Status


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mode.clear()
	_mode.add_item("Random seeker", NetSession.Mode.RANDOM)
	_mode.add_item("Decided seeker", NetSession.Mode.DECIDED)
	$Center/VBox/HostBtn.pressed.connect(_on_host)
	$Center/VBox/JoinRow/JoinBtn.pressed.connect(_on_join)


func _set_busy(text: String) -> void:
	_status.modulate = Color(0.8, 0.8, 1.0)
	_status.text = text
	$Center/VBox/HostBtn.disabled = true
	$Center/VBox/JoinRow/JoinBtn.disabled = true


func _set_error(text: String) -> void:
	_status.modulate = Color(1, 0.6, 0.6)
	_status.text = text
	$Center/VBox/HostBtn.disabled = false
	$Center/VBox/JoinRow/JoinBtn.disabled = false


func _on_host() -> void:
	_set_busy("Connecting to relay…" if _online.button_pressed else "Hosting…")
	var err: int = await NetSession.host_game(_username.text, _mode.get_selected_id(), _online.button_pressed)
	if err != OK:
		_set_error("Could not host (%s)." % error_string(err))
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)


func _on_join() -> void:
	_set_busy("Connecting…")
	var err: int = await NetSession.join_game(_username.text, _code.text, _online.button_pressed)
	if err != OK:
		_set_error("Bad invite code or connection failed (%s)." % error_string(err))
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
