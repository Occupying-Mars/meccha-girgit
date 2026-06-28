extends StaticBody3D
class_name HiderDummy
## A non-player hider used as a seeker target: a painted, posed blob with a
## collider, in the "hider" group. Lets us test seeking/shooting before
## networking exists (these become AI/remote hiders later).

@export var pose: String = "stand"
## Whole-body camouflage color. If left near-white, the blob stays blank.
@export var camo: Color = Color(0.92, 0.92, 0.94)
## Optionally tint the head separately (faces/eyes break camouflage).
@export var head_color: Color = Color(0.92, 0.92, 0.94)

@onready var _body: HiderBody = $HiderBody

var caught: bool = false


func _ready() -> void:
	add_to_group("hider")
	if _body.parts.is_empty():
		_body._build()
	for part_name in _body.part_names():
		_body.set_part_color(part_name, camo)
	_body.set_part_color("head", head_color)
	_body.apply_pose(pose, false)


func eliminate() -> void:
	if caught:
		return
	caught = true
	# Reveal: flash the whole blob red so the seeker sees the catch.
	for part_name in _body.part_names():
		_body.set_part_color(part_name, Color(0.9, 0.1, 0.1))
	$CollisionShape3D.disabled = true
	print("[hider_dummy] caught: ", name)
