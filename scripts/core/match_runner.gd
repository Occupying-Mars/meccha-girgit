extends Node3D
## Drives a local match through the GameState phases for single-player testing.
## Starts the round on load so the prep timer runs. Networking will later own
## this on the host; for now it lets us see the round loop end to end.

func _ready() -> void:
	GameState.start_match()
