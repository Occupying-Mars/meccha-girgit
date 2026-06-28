extends Node
## Global match state for the hide-and-seek round loop.
##
## Round stages (seeker.md §match structure):
##   ASSIGN  -> PREP -> SEEK -> RESULTS
## Phase durations are host-configurable; defaults here are demo-tuned.
## Singleton autoload — UI and gameplay nodes read `phase` and connect to
## `phase_changed`. Networking will later drive this on the host and
## replicate; for now it runs locally so we can test single-player.

signal phase_changed(new_phase: int)
signal phase_tick(seconds_left: float)

enum Phase { ASSIGN, PREP, SEEK, RESULTS }
enum Mode { NORMAL, INFECTION, DOUBLE }

@export var prep_seconds: float = 45.0
@export var seek_seconds: float = 120.0

var mode: int = Mode.NORMAL
var phase: int = Phase.ASSIGN
## Host (or single-player) advances phases; clients only tick the display and
## apply host-broadcast phase changes via sync_phase().
var authoritative: bool = true
var _time_left: float = 0.0
var _running: bool = false


func _unhandled_input(event: InputEvent) -> void:
	# F11 toggles fullscreen anywhere in the game.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var fs := DisplayServer.WINDOW_MODE_FULLSCREEN
		var win := DisplayServer.WINDOW_MODE_WINDOWED
		DisplayServer.window_set_mode(win if DisplayServer.window_get_mode() == fs else fs)


func _process(delta: float) -> void:
	if not _running:
		return
	_time_left -= delta
	phase_tick.emit(maxf(_time_left, 0.0))
	if _time_left <= 0.0 and authoritative:
		_advance_phase()


func start_match() -> void:
	set_phase(Phase.PREP)


func set_phase(new_phase: int) -> void:
	phase = new_phase
	match phase:
		Phase.PREP:
			_time_left = prep_seconds
			_running = true
		Phase.SEEK:
			_time_left = seek_seconds
			_running = true
		_:
			_running = false
	phase_changed.emit(phase)
	print("[game_state] phase -> ", Phase.keys()[phase])


## Clients apply host-broadcast phase + remaining time (no local advancement).
func sync_phase(new_phase: int, seconds_left: float) -> void:
	phase = new_phase
	_time_left = seconds_left
	_running = new_phase == Phase.PREP or new_phase == Phase.SEEK
	phase_changed.emit(phase)
	print("[game_state] (synced) phase -> ", Phase.keys()[phase])


func _advance_phase() -> void:
	match phase:
		Phase.PREP:
			set_phase(Phase.SEEK)
		Phase.SEEK:
			set_phase(Phase.RESULTS)


func time_left() -> float:
	return maxf(_time_left, 0.0)


func phase_name() -> String:
	return Phase.keys()[phase]
