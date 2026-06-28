extends SceneTree
## Headless check: the eyedropper's surface-color extraction returns the
## actual albedo of arena props. Run:
##   godot --headless --script tools/godot/test_eyedropper.gd

func _init() -> void:
	var arena := Node3D.new()
	arena.set_script(load("res://scripts/core/arena_builder.gd"))
	arena._ready()  # build props now (deferred _ready won't run before we iterate)

	var menu := CanvasLayer.new()
	menu.set_script(load("res://scripts/painting/paint_menu.gd"))

	var failures := 0
	var checked := 0
	for child in arena.get_children():
		if not (child is StaticBody3D):
			continue
		var mi := _first_mesh(child)
		if mi == null or not (mi.material_override is StandardMaterial3D):
			continue
		var expected: Color = mi.material_override.albedo_color
		var got = menu._color_of(child)
		checked += 1
		if got == null or not (got is Color) or not got.is_equal_approx(expected):
			push_error("MISMATCH on %s: expected %s got %s" % [child.name, expected, str(got)])
			failures += 1
		else:
			print("OK  ", child.name, " -> ", expected.to_html(false))

	print("\n[test_eyedropper] checked=%d failures=%d" % [checked, failures])
	quit(1 if failures > 0 else 0)


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var f := _first_mesh(c)
		if f != null:
			return f
	return null
