extends SceneTree
## Dump AnimationPlayer animations + per-track summary from a GLB.
##
## Usage:
##     godot --headless --script tools/godot/inspect_anims.gd -- res://path/to.glb
##     godot --headless --script tools/godot/inspect_anims.gd      # defaults to protagonist
##
## Pass the GLB path after the bare `--`. Falls back to GLB_PATH if none given.
##
## Output:
##     anim NAME length=SEC tracks=N
##     for each track: path, type, key count, first key value (if scalar/vec)
##
## Common gotcha: Mixamo animations name the Hips translation track
## `Armature/Skeleton3D:mixamorig_Hips` (type 1 = TYPE_POSITION_3D). If
## the character floats above the floor when the clip plays, this track
## is the suspect — either strip it or compensate in the scene transform.

const GLB_PATH := "res://assets/models/characters/protagonist.glb"


func _init() -> void:
	var glb_path := GLB_PATH
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		glb_path = args[0]
	print("=== ", glb_path, " ===")
	var packed := load(glb_path) as PackedScene
	if packed == null:
		print("could not load ", glb_path)
		quit()
		return
	var inst := packed.instantiate()
	var ap := _find_ap(inst) as AnimationPlayer
	if ap == null:
		print("NO AnimationPlayer found in ", GLB_PATH)
		quit()
		return
	for n in ap.get_animation_list():
		var a := ap.get_animation(n)
		print("anim ", n, " length=", a.length, " tracks=", a.get_track_count())
		for t in a.get_track_count():
			var path := a.track_get_path(t)
			var typ := a.track_get_type(t)
			print("  t=", t, " path=", path, " type=", typ, " keys=", a.track_get_key_count(t))
			if a.track_get_key_count(t) > 0:
				print("    first=", a.track_get_key_value(t, 0))
	quit()


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r:
			return r
	return null
