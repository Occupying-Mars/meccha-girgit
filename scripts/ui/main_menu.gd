extends Control
## Title screen: username, host (with mode) or join (with invite code).

@onready var _username: LineEdit = $Center/VBox/UsernameRow/Username
@onready var _mode: OptionButton = $Center/VBox/ModeRow/Mode
@onready var _code: LineEdit = $Center/VBox/JoinRow/Code
@onready var _status: Label = $Center/VBox/Status


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mode.clear()
	_mode.add_item("Random seeker", NetSession.Mode.RANDOM)
	_mode.add_item("Decided seeker", NetSession.Mode.DECIDED)
	$Center/VBox/HostBtn.pressed.connect(_on_host)
	$Center/VBox/JoinRow/JoinBtn.pressed.connect(_on_join)


func _on_host() -> void:
	var err := NetSession.host_game(_username.text, _mode.get_selected_id())
	if err != OK:
		_status.text = "Could not host (port busy?)."
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)


func _on_join() -> void:
	var err := NetSession.join_game(_username.text, _code.text)
	if err != OK:
		_status.text = "Bad invite code or connection failed."
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
