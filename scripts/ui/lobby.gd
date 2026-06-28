extends CanvasLayer
## Pre-match lobby overlay (session mode only). Shows the invite code, the
## connected players, and — for the host — the mode and a Start button. In
## DECIDED mode the host picks which player is the seeker. Hides once the host
## starts the match (GameState leaves ASSIGN).

@onready var _code: Label = $Panel/Margin/VBox/Code
@onready var _mode: Label = $Panel/Margin/VBox/ModeLabel
@onready var _list: VBoxContainer = $Panel/Margin/VBox/Players
@onready var _seeker_pick: OptionButton = $Panel/Margin/VBox/SeekerPick
@onready var _start: Button = $Panel/Margin/VBox/StartBtn
@onready var _waiting: Label = $Panel/Margin/VBox/Waiting


func _ready() -> void:
	if not NetSession.active or GameState.phase != GameState.Phase.ASSIGN:
		visible = false
		return
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetSession.players_changed.connect(_refresh)
	GameState.phase_changed.connect(_on_phase)

	var host := NetSession.is_host
	_start.visible = host
	_waiting.visible = not host
	_code.text = "Invite code:  %s" % NetSession.invite_code() if host else "Connected — waiting in lobby"
	_mode.text = "Mode:  %s" % ("Random seeker" if NetSession.mode == NetSession.Mode.RANDOM else "Decided seeker")
	_seeker_pick.visible = host and NetSession.mode == NetSession.Mode.DECIDED

	if host:
		_start.pressed.connect(func (): NetSession.start_game())
		_seeker_pick.item_selected.connect(_on_seeker_pick)
	_refresh()


func _on_phase(p: int) -> void:
	if p != GameState.Phase.ASSIGN:
		visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for id in NetSession.players:
		var label := Label.new()
		var tag := "  (host)" if int(id) == 1 else ""
		if NetSession.mode == NetSession.Mode.DECIDED and int(id) == NetSession.decided_seeker_id:
			tag += "  [seeker]"
		label.text = "• %s%s" % [NetSession.players[id], tag]
		_list.add_child(label)

	if _seeker_pick.visible:
		_seeker_pick.clear()
		# Pick who seeks — including "nobody", so the host can be a hider even
		# when alone (everyone hides; seeker can join/seek later).
		_seeker_pick.add_item("Seeker: nobody (everyone hides)", 0)
		var sel := 0
		var idx := 1
		for id in NetSession.players:
			var who: String = NetSession.players[id]
			if int(id) == 1:
				who += " (you)"
			_seeker_pick.add_item("Seeker: %s" % who, int(id))
			if int(id) == NetSession.decided_seeker_id:
				sel = idx
			idx += 1
		_seeker_pick.select(sel)


func _on_seeker_pick(index: int) -> void:
	NetSession.decided_seeker_id = _seeker_pick.get_item_id(index)
	_refresh()
