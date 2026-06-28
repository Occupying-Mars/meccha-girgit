extends Node
## Headless-friendly screen recorder for autonomous game inspection.
##
## Ported from ../thegame. Activates only when `--record=<run_name>` is in the
## CLI user-args. Captures `frames` viewport snapshots at `interval` seconds
## apart and quits. Output: /tmp/meccha_runs/<run_name>/frame_NNNN.png so a
## separate process (Claude) can inspect them without driving the game.
##
## Usage:
##   godot --path . -- --record=arena_check --frames=4 --warmup=0.5 --screen=1
##
## Flags (all optional except --record):
##   --record=NAME       run name (creates that subdirectory)
##   --frames=N          number of frames to capture (default 4)
##   --interval=SEC      seconds between captures (default 0.5)
##   --warmup=SEC        wait before first capture so scene initializes (default 0.5)
##   --screen=N          display server screen index to spawn the window on
##   --print-screens     list connected screens at startup (for discovery)
##   --no-quit           don't quit after captures (lets the user keep playing)
##   --test=NAME         drive a scripted input sequence in parallel with capture

const OUT_ROOT := "/tmp/meccha_runs"

var run_name: String = ""
var frames: int = 4
var interval: float = 0.5
var warmup: float = 0.5
var quit_after: bool = true
var screen_index: int = -1
var print_screens: bool = false
var test_name: String = ""
var pose_arg: String = ""

var _out_dir: String = ""


func _ready() -> void:
	_parse_args()
	if print_screens:
		_dump_screens()
	if run_name.is_empty():
		return  # recorder is dormant unless invoked

	_out_dir = "%s/%s" % [OUT_ROOT, run_name]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[recorder] run=", run_name, " out=", _out_dir, " frames=", frames, " interval=", interval)

	if screen_index >= 0:
		_move_to_screen(screen_index)

	await get_tree().create_timer(warmup).timeout

	if test_name != "":
		_run_test_async()

	for i in frames:
		await RenderingServer.frame_post_draw
		_capture(i)
		if i < frames - 1:
			await get_tree().create_timer(interval).timeout
	print("[recorder] done. frames in ", _out_dir)
	if quit_after:
		get_tree().quit()


func _run_test_async() -> void:
	# Fire-and-forget: input timeline runs in parallel with the capture loop.
	match test_name:
		"walk_forward":
			_play_input([{"action": "move_forward", "press": 0.0, "release": 3.0}])
		"walk_loop":
			# Long continuous walk (for the moving end of a multiplayer test).
			_play_input([{"action": "move_forward", "press": 0.0, "release": 30.0}])
		"walk_back":
			_play_input([{"action": "move_back", "press": 0.0, "release": 3.0}])
		"walk_diag":
			_play_input([
				{"action": "move_forward", "press": 0.0, "release": 3.0},
				{"action": "move_right", "press": 0.0, "release": 3.0},
			])
		"jump":
			_play_input([{"action": "jump", "press": 0.2, "release": 0.3}])
		"fire":
			_play_input([
				{"action": "fire", "press": 0.3, "release": 0.35},
				{"action": "fire", "press": 0.8, "release": 0.85},
				{"action": "fire", "press": 1.3, "release": 1.35},
			])
		"look_right":
			_play_mouse(Vector2(8.0, 0.0), 60)
		"look_left":
			_play_mouse(Vector2(-8.0, 0.0), 60)
		"look_walk":
			_play_input([{"action": "move_forward", "press": 0.0, "release": 3.0}])
			_play_mouse(Vector2(6.0, 0.0), 80)
		"paint_demo":
			# Paint each body part a different color (proves per-part
			# independence), then open the paint menu so the UI is visible.
			_paint_demo()
		"pose":
			# Apply the pose named by --pose=NAME and hold it.
			_apply_pose(pose_arg)
		"net_paint":
			# (Run on the host.) After clients have joined, the local avatar
			# paints + poses itself and broadcasts — tests paint replication.
			_net_paint()
		"net_check":
			# (Run on a client.) Log remote avatars' torso color + pose to
			# verify paint/pose replication arrived.
			_net_check()
		"net_shoot":
			# (Run on the host/seeker.) Aim at a hider and fire.
			_net_shoot()
		"net_caught":
			# (Run on a client/hider.) Log own caught state.
			_net_caught()
		"net_watch":
			# (Run on the host/seeker.) Keep the seeker aimed at a hider so it
			# accrues "seen in plain sight" score; never fires.
			_net_watch()
		_:
			push_warning("[recorder] unknown test name: " + test_name)


func _paint_demo() -> void:
	# Find the hider body and color parts distinctly, then open the menu.
	var scene := get_tree().current_scene
	var hider := scene.find_child("Hider", true, false)
	if hider == null:
		push_warning("[recorder] paint_demo: no Hider found")
		return
	var body = hider.get("body")
	if body == null:
		body = hider.find_child("HiderBody", true, false)
	var scheme := {
		"head": Color(0.85, 0.83, 0.80),
		"torso": Color(0.28, 0.45, 0.68),
		"arm_l": Color(0.70, 0.30, 0.28),
		"arm_r": Color(0.40, 0.58, 0.34),
		"leg_l": Color(0.74, 0.66, 0.32),
		"leg_r": Color(0.55, 0.50, 0.62),
	}
	for part_name in scheme:
		body.set_part_color(part_name, scheme[part_name])
	# Open the paint menu via the action so the controller suspends movement.
	_schedule_action("paint_menu", 0.2, true)
	_schedule_action("paint_menu", 0.25, false)


func _net_paint() -> void:
	# Wait for a client to join, then paint + pose the local avatar and
	# broadcast it. Scheme matches the blue crate so the client sees camouflage.
	await get_tree().create_timer(2.5).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		push_warning("[recorder] net_paint: no Players node")
		return
	for p in players.get_children():
		if not p.is_multiplayer_authority():
			continue
		var scheme := {
			"head": Color(0.85, 0.83, 0.80),
			"torso": Color(0.28, 0.45, 0.68),
			"arm_l": Color(0.28, 0.45, 0.68),
			"arm_r": Color(0.28, 0.45, 0.68),
			"leg_l": Color(0.28, 0.45, 0.68),
			"leg_r": Color(0.28, 0.45, 0.68),
		}
		for part_name in scheme:
			p.body.set_part_color(part_name, scheme[part_name])
		p._broadcast_paint()
		p.body.apply_pose("crouch", false)
		p._broadcast_pose("crouch")
		print("[recorder] net_paint: painted+posed local avatar ", p.name)


func _net_shoot() -> void:
	await get_tree().create_timer(3.0).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return
	var seeker = null
	var hider = null
	for p in players.get_children():
		if p.is_seeker():
			seeker = p
		elif p.role == 0:
			hider = p
	if seeker == null or hider == null:
		push_warning("[recorder] net_shoot: need a seeker and a hider")
		return
	print("[recorder] net_shoot seeker@%s hider@%s" % [seeker.global_position, hider.global_position])
	# Aim the seeker's camera yaw at the hider's torso, then fire.
	seeker._yaw.look_at(hider.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().physics_frame
	seeker._fire()
	print("[recorder] net_shoot: seeker fired at hider ", hider.name)


func _net_watch() -> void:
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		var players := get_tree().current_scene.get_node_or_null("Players")
		if players == null:
			continue
		var seeker = null
		var hider = null
		for p in players.get_children():
			if p.is_seeker():
				seeker = p
			elif p.role == 0 and not p.caught:
				hider = p
		if seeker != null and hider != null:
			seeker._yaw.look_at(hider.global_position + Vector3(0, 1.0, 0), Vector3.UP)


func _net_caught() -> void:
	await get_tree().create_timer(5.0).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return
	for p in players.get_children():
		if p.is_multiplayer_authority():
			print("[recorder] net_caught: local hider ", p.name, " caught=", p.caught)


func _net_check() -> void:
	await get_tree().create_timer(4.5).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		push_warning("[recorder] net_check: no Players node")
		return
	for p in players.get_children():
		if p.is_multiplayer_authority():
			continue
		var c: Color = p.body.get_part_color("torso")
		print("[recorder] net_check remote %s torso=(%.2f, %.2f, %.2f) pose=%s"
			% [p.name, c.r, c.g, c.b, p.body.current_pose])


func _apply_pose(pose_name: String) -> void:
	var scene := get_tree().current_scene
	var hider := scene.find_child("Hider", true, false)
	if hider == null:
		push_warning("[recorder] pose: no Hider found")
		return
	var body = hider.get("body")
	if body == null:
		body = hider.find_child("HiderBody", true, false)
	body.apply_pose(pose_name, false)
	print("[recorder] applied pose: ", pose_name)


func _play_input(events: Array) -> void:
	for ev_raw in events:
		var ev: Dictionary = ev_raw
		_schedule_action(ev["action"], ev["press"], true)
		_schedule_action(ev["action"], ev["release"], false)


func _schedule_action(action: String, when: float, press: bool) -> void:
	# Synthesize an InputEventAction routed through parse_input_event so
	# is_action_just_pressed() fires correctly the frame the press hits.
	get_tree().create_timer(when).timeout.connect(func ():
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = press
		Input.parse_input_event(ev)
		print("[recorder] %s %s" % ["press" if press else "release", action])
	)


func _play_mouse(relative_per_tick: Vector2, ticks: int) -> void:
	for i in ticks:
		get_tree().create_timer(i * 0.02).timeout.connect(func ():
			var ev := InputEventMouseMotion.new()
			ev.relative = relative_per_tick
			Input.parse_input_event(ev)
		)


func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("--record="):
			run_name = arg.substr("--record=".length())
		elif arg.begins_with("--frames="):
			frames = int(arg.substr("--frames=".length()))
		elif arg.begins_with("--interval="):
			interval = float(arg.substr("--interval=".length()))
		elif arg.begins_with("--warmup="):
			warmup = float(arg.substr("--warmup=".length()))
		elif arg.begins_with("--screen="):
			screen_index = int(arg.substr("--screen=".length()))
		elif arg == "--no-quit":
			quit_after = false
		elif arg == "--print-screens":
			print_screens = true
		elif arg.begins_with("--test="):
			test_name = arg.substr("--test=".length())
		elif arg.begins_with("--pose="):
			pose_arg = arg.substr("--pose=".length())


func _dump_screens() -> void:
	var n := DisplayServer.get_screen_count()
	print("[recorder] screens=", n, " primary=", DisplayServer.get_primary_screen())
	for i in n:
		print("  screen[", i, "] pos=", DisplayServer.screen_get_position(i),
				" size=", DisplayServer.screen_get_size(i),
				" dpi=", DisplayServer.screen_get_dpi(i))


func _move_to_screen(idx: int) -> void:
	if idx < 0 or idx >= DisplayServer.get_screen_count():
		push_warning("[recorder] requested screen %d not available" % idx)
		return
	var screen_pos := DisplayServer.screen_get_position(idx)
	var screen_size := DisplayServer.screen_get_size(idx)
	var win_size := DisplayServer.window_get_size()
	var pos := screen_pos + (screen_size - win_size) / 2
	DisplayServer.window_set_current_screen(idx)
	DisplayServer.window_set_position(pos)
	print("[recorder] moved window to screen ", idx, " at ", pos)


func _capture(idx: int) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/frame_%04d.png" % [_out_dir, idx]
	img.save_png(path)
	print("[recorder] saved ", path)
