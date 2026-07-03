extends CanvasLayer
## Live scoreboard (top-right): everyone in the match with their current
## status — SEEKER (orange), hiding (green), or CAUGHT (red, struck through).
## Reads names from NetSession.players (falls back to avatar node names in CLI
## test mode) and role/caught straight off the replicated player nodes, so it
## is correct on every peer with zero extra networking. Hidden in the lobby
## (ASSIGN) where the lobby overlay already lists everyone.

const MARGIN := 12.0
const REFRESH := 0.5

var _players: Node3D
var _panel: PanelContainer
var _rows: VBoxContainer
var _accum := 0.0


func setup(players: Node3D) -> void:
	_players = players


func _ready() -> void:
	layer = 3
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -232.0
	_panel.offset_right = -MARGIN
	_panel.offset_top = MARGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.12, 0.72)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_panel.add_child(vbox)
	var title := Label.new()
	title.name = "Title"
	title.text = "PLAYERS"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	vbox.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 1)
	vbox.add_child(_rows)

	GameState.phase_changed.connect(_on_phase)
	_on_phase(GameState.phase)
	_refresh()


func _on_phase(p: int) -> void:
	# The lobby overlay already lists everyone during ASSIGN.
	visible = p != GameState.Phase.ASSIGN


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REFRESH:
		_accum = 0.0
		_refresh()


func _refresh() -> void:
	if _players == null or not is_instance_valid(_players):
		return
	for c in _rows.get_children():
		c.queue_free()
	var seekers := 0
	var alive := 0
	var caught := 0
	for p in _players.get_children():
		var pid := int(String(p.name))
		var pname: String = NetSession.players.get(pid, "Player %d" % pid) \
			if not NetSession.players.is_empty() else String(p.name)
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 14)
		if p.get("role") == 1:  # NetPlayer.Role.SEEKER
			row.text = "► %s  (seeker)" % pname
			row.add_theme_color_override("font_color", Color(1.0, 0.62, 0.3))
			seekers += 1
		elif p.get("caught"):
			row.text = "✗ %s" % pname
			row.add_theme_color_override("font_color", Color(0.9, 0.35, 0.35))
			caught += 1
		else:
			row.text = "● %s" % pname
			row.add_theme_color_override("font_color", Color(0.55, 0.9, 0.65))
			alive += 1
		_rows.add_child(row)
	var title: Label = _panel.get_child(0).get_node("Title")
	title.text = "PLAYERS — %d hiding · %d caught" % [alive, caught] \
		if (alive + caught) > 0 else "PLAYERS"
