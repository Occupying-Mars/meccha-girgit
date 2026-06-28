extends CanvasLayer
class_name ControlsHud
## Always-on control reference for the local player, bottom-left. Role-aware
## so seekers and hiders each see exactly what they can do (incl. trackpad-
## friendly alternatives).

const HIDER := [
	["WASD", "Move"],
	["Mouse", "Look"],
	["Space", "Jump"],
	["P", "Paint  (drag LMB · arrows orbit)"],
	["Tab", "Pose"],
	["F", "Wall-stick  (Space/S height)"],
	["T", "Whistle"],
]
const SEEKER := [
	["WASD", "Move"],
	["Mouse", "Look"],
	["Space", "Jump"],
	["LMB", "Shoot"],
	["Esc", "Free cursor"],
]


func show_for(is_seeker: bool) -> void:
	for c in get_children():
		c.queue_free()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(14, -14)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)

	var margin := MarginContainer.new()
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 12)
	for s in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 8)
	panel.add_child(margin)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	margin.add_child(grid)

	var rows: Array = SEEKER if is_seeker else HIDER
	for row in rows:
		var key := Label.new()
		key.text = row[0]
		key.add_theme_color_override("font_color", Color(0.357, 0.878, 0.541))
		key.add_theme_font_size_override("font_size", 15)
		grid.add_child(key)
		var desc := Label.new()
		desc.text = row[1]
		desc.add_theme_color_override("font_color", Color(0.85, 0.87, 0.93))
		desc.add_theme_font_size_override("font_size", 15)
		grid.add_child(desc)
