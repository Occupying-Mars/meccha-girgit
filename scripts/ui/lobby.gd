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
@onready var _copy_btn: Button = $Panel/Margin/VBox/CopyBtn


func _ready() -> void:
	if not NetSession.active or GameState.phase != GameState.Phase.ASSIGN:
		visible = false
		return
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetSession.players_changed.connect(_refresh)
	GameState.phase_changed.connect(_on_phase)

	_mode.text = "Mode:  %s" % ("Random seeker" if NetSession.mode == NetSession.Mode.RANDOM else "Decided seeker")
	# Wire controls once; admin-vs-not visibility is set in _refresh, because on a
	# dedicated server the admin is only known once the first client registers.
	_start.pressed.connect(func (): NetSession.request_start())
	_seeker_pick.item_selected.connect(_on_seeker_pick)
	_copy_btn.pressed.connect(_on_copy)
	_refresh()


func _on_copy() -> void:
	DisplayServer.clipboard_set(NetSession.invite_code())
	_copy_btn.text = "✓ Copied!"
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(_copy_btn):
		_copy_btn.text = "📋 Copy invite code"


func _on_phase(p: int) -> void:
	if p != GameState.Phase.ASSIGN:
		visible = false
		# Capture the mouse for gameplay (PREP/SEEK) only. On RESULTS the results
		# screen needs the cursor visible to click buttons — don't grab it back.
		if p == GameState.Phase.PREP or p == GameState.Phase.SEEK:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	# Who controls the lobby (LAN host, or the dedicated-server admin).
	var admin := NetSession.is_admin()
	_start.visible = admin
	_waiting.visible = not admin
	if NetSession.dedicated:
		_code.text = "Dedicated server" + ("  —  you're the admin" if admin else "")
		_copy_btn.visible = false
	elif NetSession.is_host:
		_code.text = "Invite code:  %s" % NetSession.invite_code()
		_copy_btn.visible = true
	else:
		_code.text = "Connected — waiting in lobby"
		_copy_btn.visible = false
	_seeker_pick.visible = admin and NetSession.mode == NetSession.Mode.DECIDED and not NetSession.dedicated

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
