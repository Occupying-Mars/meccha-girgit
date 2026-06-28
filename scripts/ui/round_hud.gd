extends CanvasLayer
class_name RoundHud
## Round phase + countdown banner, driven by the GameState autoload.
## Reusable across hider and seeker views; networking will later just drive
## GameState on the host and this reflects it everywhere.

@onready var _phase: Label = $Top/Phase
@onready var _timer: Label = $Top/Timer

const PHASE_TEXT := {
	GameState.Phase.ASSIGN: "ASSIGNING TEAMS",
	GameState.Phase.PREP: "HIDE — paint & pose",
	GameState.Phase.SEEK: "SEEK",
	GameState.Phase.RESULTS: "RESULTS",
}


func _ready() -> void:
	GameState.phase_changed.connect(_on_phase)
	GameState.phase_tick.connect(_on_tick)
	_on_phase(GameState.phase)
	_on_tick(GameState.time_left())


func _on_phase(phase: int) -> void:
	_phase.text = PHASE_TEXT.get(phase, "?")

func _on_tick(seconds_left: float) -> void:
	var s := int(ceil(seconds_left))
	_timer.text = "%d:%02d" % [s / 60, s % 60]
