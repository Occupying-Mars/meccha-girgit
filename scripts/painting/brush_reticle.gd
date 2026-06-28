extends Control
class_name BrushReticle
## A paintbrush cursor: a ring at the mouse showing the brush footprint, so the
## hider can see where and how big the brush is. Driven by FreehandPaintMenu.

var radius: float = 18.0
var paint_color: Color = Color.WHITE


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var m := get_local_mouse_position()
	# Dark backing ring + bright inner ring so it reads on any surface.
	draw_arc(m, radius + 1.0, 0.0, TAU, 48, Color(0, 0, 0, 0.7), 2.5, true)
	draw_arc(m, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.95), 1.5, true)
	# Center dot tinted with the current paint color.
	draw_circle(m, 2.5, Color(0, 0, 0, 0.7))
	draw_circle(m, 1.5, paint_color)
