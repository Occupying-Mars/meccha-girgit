extends CanvasLayer
class_name PoseMenu
## Pose picker for the hider (seeker.md §pose system).
##
## Poses break the humanoid silhouette and change which surfaces face the
## seeker. Intended workflow is pose-before-paint, so this is a quick overlay:
## open, pick a pose, close. Wall-flatten exposes a dedicated Unstick action
## (returns to stand) per the spec.

signal closed
signal pose_changed(pose_name: String)

@onready var _list: VBoxContainer = $Panel/Margin/VBox/PoseList
@onready var _status: Label = $Panel/Margin/VBox/Status

var body: HiderBody
var _buttons: Dictionary = {}


func setup(hider_body: HiderBody) -> void:
	body = hider_body
	_build_buttons()


func _ready() -> void:
	visible = false


func open() -> void:
	visible = true
	_status.text = "Current: %s" % body.current_pose

func close() -> void:
	visible = false
	closed.emit()


func _build_buttons() -> void:
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	for pose_name in body.pose_names():
		var b := Button.new()
		b.text = pose_name.replace("_", " ")
		b.pressed.connect(_on_pose.bind(pose_name))
		_list.add_child(b)
		_buttons[pose_name] = b


func _on_pose(pose_name: String) -> void:
	body.apply_pose(pose_name)
	_status.text = "Current: %s" % pose_name
	pose_changed.emit(pose_name)
