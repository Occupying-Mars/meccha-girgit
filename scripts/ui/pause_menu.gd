extends CanvasLayer
class_name PauseMenu
## In-game Esc menu (local). Resume, leave back to the main menu, or quit.
## The game keeps running underneath (multiplayer can't truly pause), so this
## is an overlay — the player's input is suspended by the owner while it's up.

signal resumed

@onready var _resume: Button = $Center/Card/Margin/VBox/Resume
@onready var _leave: Button = $Center/Card/Margin/VBox/Leave
@onready var _quit: Button = $Center/Card/Margin/VBox/Quit


func _ready() -> void:
	visible = false
	_resume.pressed.connect(close)
	_leave.pressed.connect(_on_leave)
	_quit.pressed.connect(func (): get_tree().quit())


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	resumed.emit()


func _on_leave() -> void:
	NetSession.leave()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
