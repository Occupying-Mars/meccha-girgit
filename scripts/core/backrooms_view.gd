extends Node3D
## Standalone preview for the backrooms level — points the camera across the
## rooms so we can eyeball the layout/furniture/lighting.

func _ready() -> void:
	$Camera3D.look_at(Vector3(6, 1.0, 5), Vector3.UP)
