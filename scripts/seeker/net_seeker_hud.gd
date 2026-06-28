extends CanvasLayer
## Seeker HUD for the networked player: crosshair + shot/hit counters with a
## green/red hit flash. The owning NetPlayer calls register_shot() on fire.

@onready var _crosshair: Label = $Center/Crosshair
@onready var _status: Label = $Status

var _shots: int = 0
var _hits: int = 0


func register_shot(hit: bool) -> void:
	_shots += 1
	if hit:
		_hits += 1
	_crosshair.modulate = Color(0.2, 1.0, 0.2) if hit else Color(1.0, 0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(_crosshair, "modulate", Color.WHITE, 0.3)
	_status.text = "Caught: %d    Shots: %d" % [_hits, _shots]
