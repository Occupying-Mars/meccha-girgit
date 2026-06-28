extends SceneTree
## List connected displays + their indices.
##
## Usage:
##     godot --headless --script tools/godot/enum_screens.gd
##
## Note: headless mode usually reports screen_count=0. Run via the
## recorder's --print-screens flag with a real window to actually
## enumerate. Kept here for reference.
##
## On the dev machine the indices have been:
##     screen[0] = external 5K monitor (5120x2160 @ ~93 dpi)
##     screen[1] = M4 Mac laptop (3024x1964 @ ~256 dpi)
## Pass --screen=1 to recorder runs so the window doesn't steal focus
## from the user's main monitor.

func _init() -> void:
	var n := DisplayServer.get_screen_count()
	print("screen_count=", n, " primary=", DisplayServer.get_primary_screen())
	for i in n:
		print("  screen[", i, "] pos=", DisplayServer.screen_get_position(i),
				" size=", DisplayServer.screen_get_size(i),
				" dpi=", DisplayServer.screen_get_dpi(i))
	quit()
