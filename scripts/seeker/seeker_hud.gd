extends CanvasLayer
class_name SeekerHud
## Minimal seeker HUD: crosshair + shot/hit counters with hit flash.
## Connects to the SeekerController (its parent) signals.

@onready var _crosshair: Label = $Center/Crosshair
@onready var _status: Label = $Status

var _shots: int = 0
var _hits: int = 0


func _ready() -> void:
	var seeker := get_parent()
	if seeker is SeekerController:
		seeker.shot_fired.connect(_on_shot)
		seeker.hider_hit.connect(_on_hit)
	_update()


func _on_shot(hit: bool) -> void:
	_shots += 1
	if hit:
		_hits += 1
		_flash(Color(0.2, 1.0, 0.2))
	else:
		_flash(Color(1.0, 0.3, 0.3))
	_update()


func _on_hit(_hider: Node) -> void:
	pass  # counted in _on_shot via the hit flag


func _flash(c: Color) -> void:
	_crosshair.modulate = c
	var tw := create_tween()
	tw.tween_property(_crosshair, "modulate", Color.WHITE, 0.3)


func _update() -> void:
	_status.text = "Caught: %d    Shots: %d" % [_hits, _shots]
