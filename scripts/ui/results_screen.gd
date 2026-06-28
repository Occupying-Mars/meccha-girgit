extends CanvasLayer
class_name ResultsScreen
## End-of-round results (seeker.md §results screen + scoring).
##
## Shown to everyone when GameState reaches RESULTS. Reveals each hider: their
## camouflage color, whether they were caught or survived, and their score
## (host-computed: time spent visible to the seeker, weighted by closeness).

@onready var _title: Label = $Panel/Margin/VBox/Title
@onready var _list: VBoxContainer = $Panel/Margin/VBox/List


func _ready() -> void:
	visible = false
	GameState.phase_changed.connect(_on_phase)


func _on_phase(phase: int) -> void:
	if phase == GameState.Phase.RESULTS:
		_show_results()


func _show_results() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for c in _list.get_children():
		c.queue_free()

	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return
	var hiders := 0
	var survivors := 0
	var rows: Array = []
	for p in players.get_children():
		if p.role != NetPlayer.Role.HIDER:
			continue
		hiders += 1
		if not p.caught:
			survivors += 1
		rows.append(p)

	_title.text = ("HIDERS WIN — %d survived" % survivors) if survivors > 0 \
		else "SEEKER WINS — all hiders found"

	# Highest score first (best hide-in-plain-sight).
	rows.sort_custom(func(a, b): return a.score > b.score)
	for p in rows:
		_list.add_child(_make_row(p))


func _make_row(p: Node) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.color = p.body.get_part_color("torso")
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(120, 0)
	name_label.text = "Hider %s" % p.name
	row.add_child(name_label)

	var status := Label.new()
	status.custom_minimum_size = Vector2(110, 0)
	status.text = "CAUGHT" if p.caught else "SURVIVED"
	status.modulate = Color(1, 0.4, 0.4) if p.caught else Color(0.4, 1, 0.4)
	row.add_child(status)

	var score := Label.new()
	score.text = "score %d" % int(round(p.score))
	row.add_child(score)
	return row
