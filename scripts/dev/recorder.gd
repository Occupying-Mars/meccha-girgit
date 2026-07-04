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

const OUT_ROOT := "D:/meccha_runs"

var run_name: String = ""
var frames: int = 4
var interval: float = 0.5
var warmup: float = 0.5
var quit_after: bool = true
var screen_index: int = -1
var print_screens: bool = false
var test_name: String = ""
var pose_arg: String = ""
var oid_arg: String = ""

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

	# Force a fixed windowed size for consistent captures (the game ships
	# fullscreen, but the recorder needs a positionable, known-size window).
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
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
		"net_stick":
			# (Run on a client/hider.) Move next to the pillar, face it, stick.
			_net_stick()
		"menu_host":
			# Drive the lobby as host (DECIDED, host=seeker) then start.
			_menu_host()
		"menu_join":
			# Join the host via an invite code and report assigned role.
			_menu_join()
		"online_host":
			# Host over the Noray internet relay; print the OID invite code.
			_online_host()
		"online_join":
			# Join the relay host given by --oid=OID.
			_online_join()
		"paint_stroke":
			# (paint_test scene.) Brush a stroke down the blob to verify
			# freehand surface painting renders.
			_paint_stroke()
		"net_paint_fh":
			# (net hider client.) Freehand-paint a stroke on the real scaled
			# avatar via raycast from its own camera.
			_net_paint_fh()
		"net_whistle":
			# (net hider client.) Trigger a whistle and show the popup.
			_net_whistle()
		"net_pause":
			# (net hider client.) Open the Esc pause menu.
			_net_pause()
		"dedi_join":
			# Join a dedicated server at 127.0.0.1; first joiner (admin) starts.
			_dedi_join()
		"eos_host":
			# Host over EOS; write the assigned lobby code to a scratch file so
			# a separate eos_join process (same machine, --test only) can read it.
			_eos_host()
		"eos_join":
			# Join the EOS lobby whose code was written by an eos_host run.
			_eos_join()
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


func _dedi_join() -> void:
	await get_tree().create_timer(0.4).timeout
	var err: int = await NetSession.join_game("Guest%d" % (randi() % 9000 + 1000), "127.0.0.1")
	print("[recorder] dedi_join err=%s" % error_string(err))
	if err != OK:
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
	await get_tree().create_timer(4.0).timeout
	print("[recorder] is_admin=%s admin_id=%d players=%s" % [NetSession.is_admin(), NetSession.admin_id, str(NetSession.players)])
	if NetSession.is_admin():
		print("[recorder] I'm the admin -> request_start")
		NetSession.request_start()
	await get_tree().create_timer(3.0).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players != null:
		for p in players.get_children():
			print("[recorder] spawned %s role=%d mine=%s" % [p.name, p.role, str(p.is_multiplayer_authority())])


func _net_pause() -> void:
	await get_tree().create_timer(0.3).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return
	for p in players.get_children():
		if p.is_multiplayer_authority() and not p.is_seeker():
			p._toggle_pause()
			print("[recorder] net_pause opened on ", p.name)
			return


func _net_whistle() -> void:
	await get_tree().create_timer(0.3).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return
	for p in players.get_children():
		if p.is_multiplayer_authority() and not p.is_seeker():
			p._do_whistle()
			print("[recorder] net_whistle triggered on ", p.name)
			return


func _net_paint_fh() -> void:
	await get_tree().create_timer(0.3).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return
	for p in players.get_children():
		if not p.is_multiplayer_authority() or p.is_seeker():
			continue
		var cam := p.get_node("CameraYaw/CameraPitch/SpringArm3D/Camera3D") as Camera3D
		var space := cam.get_world_3d().direct_space_state
		var vp := cam.get_viewport().get_visible_rect().size
		var hits := 0
		for i in 24:
			var t := float(i) / 23.0
			var sp := Vector2(vp.x * 0.5, vp.y * (0.32 + 0.42 * t))
			var from := cam.project_ray_origin(sp)
			var dir := cam.project_ray_normal(sp)
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * 10.0)
			q.collision_mask = HiderBody.PAINT_LAYER
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var part := (hit["collider"] as Node).get_parent().name
				p.body.paint_at(String(part), hit["position"], Color(0.9, 0.2, 0.2), 9.0)
				hits += 1
		print("[recorder] net_paint_fh: painted %d points on %s" % [hits, p.name])
		return


func _paint_stroke() -> void:
	var scene := get_tree().current_scene
	if not scene.has_method("demo_stroke"):
		push_warning("[recorder] paint_stroke: scene has no demo_stroke()")
		return
	for k in 4:
		scene.demo_stroke()
		await get_tree().create_timer(0.15).timeout
	print("[recorder] paint_stroke done")


func _online_host() -> void:
	var err: int = await NetSession.host_game("HostUser", NetSession.Mode.DECIDED, true)
	print("[recorder] online_host err=%s OID=%s" % [error_string(err), NetSession.online_oid])
	if err != OK:
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
	await get_tree().create_timer(12.0).timeout
	print("[recorder] online_host roster: ", NetSession.players)
	NetSession.decided_seeker_id = 1
	NetSession.start_game()
	await get_tree().create_timer(2.0).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players != null:
		for p in players.get_children():
			print("[recorder] online_host spawned %s role=%d" % [p.name, p.role])


func _online_join() -> void:
	await get_tree().create_timer(0.5).timeout
	var err: int = await NetSession.join_game("GuestUser", oid_arg, true)
	print("[recorder] online_join err=%s (oid=%s)" % [error_string(err), oid_arg])
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
	await get_tree().create_timer(10.0).timeout
	print("[recorder] online_join roster: ", NetSession.players)


func _menu_host() -> void:
	NetSession.host_game("HostUser", NetSession.Mode.DECIDED)
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
	await get_tree().create_timer(5.0).timeout
	print("[recorder] lobby roster: ", NetSession.players)
	NetSession.decided_seeker_id = 1  # host is the chosen seeker
	NetSession.start_game()
	await get_tree().create_timer(2.5).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players != null:
		for p in players.get_children():
			print("[recorder] host: spawned %s role=%d" % [p.name, p.role])


func _menu_join() -> void:
	await get_tree().create_timer(1.0).timeout  # let the host come up
	NetSession.join_game("GuestUser", "7F0000015FF5")  # 127.0.0.1:24565
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
	await get_tree().create_timer(8.0).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players != null:
		for p in players.get_children():
			print("[recorder] client: %s role=%d mine=%s"
				% [p.name, p.role, str(p.is_multiplayer_authority())])


const EOS_CODE_FILE := "D:/meccha_runs/eos_lobby_code.txt"


func _eos_host() -> void:
	var err: int = await NetSession.host_eos("HostUser", NetSession.Mode.DECIDED)
	print("[recorder] eos_host err=%s code=%s" % [error_string(err), NetSession.eos_code])
	if err != OK:
		return
	var f := FileAccess.open(EOS_CODE_FILE, FileAccess.WRITE)
	f.store_string(NetSession.eos_code)
	f.close()
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
	await get_tree().create_timer(15.0).timeout
	print("[recorder] eos_host roster: ", NetSession.players)


func _eos_join() -> void:
	var code := ""
	for i in 20:
		if FileAccess.file_exists(EOS_CODE_FILE):
			code = FileAccess.get_file_as_string(EOS_CODE_FILE).strip_edges()
			if not code.is_empty():
				break
		await get_tree().create_timer(0.5).timeout
	print("[recorder] eos_join: using code=", code)
	var err: int = await NetSession.join_eos("GuestUser", code)
	print("[recorder] eos_join err=%s" % error_string(err))
	if err != OK:
		return
	get_tree().change_scene_to_file(NetSession.GAME_SCENE)
	await get_tree().create_timer(10.0).timeout
	print("[recorder] eos_join roster: ", NetSession.players)


func _net_stick() -> void:
	await get_tree().create_timer(0.3).timeout
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return
	for p in players.get_children():
		if not p.is_multiplayer_authority() or p.is_seeker():
			continue
		# Approach the flat RED perimeter wall (face at z = -11.75) from +z,
		# camera level and facing -z — the natural way a player walks up to it.
		p.global_position = Vector3(0, 0.1, -10.6)
		p._yaw.rotation.y = 0.0
		p._pitch.rotation.x = 0.0
		p._pitch_angle = 0.0
		await get_tree().physics_frame
		p._try_stick()
		await get_tree().create_timer(0.5).timeout
		print("[recorder] net_stick stuck=%s pose=%s pos=%s"
			% [p._stuck, p.body.current_pose, str(p.global_position)])
		return


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
		elif arg.begins_with("--oid="):
			oid_arg = arg.substr("--oid=".length())


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
