extends SceneTree
## Minimal direct Noray connectivity probe (instantiates Noray manually since
## --script mode doesn't load autoloads). Run:
##   godot --headless --script tools/godot/test_noray.gd

var noray

func _init() -> void:
	_run()

func _run() -> void:
	noray = load("res://addons/netfox.noray/noray.gd").new()
	get_root().add_child(noray)
	noray.on_command.connect(func (c, d): print("[noray-test] CMD: '", c, "' data='", d, "'"))
	noray.on_oid.connect(func (o): print("[noray-test] on_oid: ", o))
	noray.on_pid.connect(func (p): print("[noray-test] on_pid: ", p))

	print("[noray-test] connecting to tomfol.io:8890 ...")
	var err = await noray.connect_to_host("tomfol.io", 8890)
	print("[noray-test] connect err=", err, " connected=", noray.is_connected_to_host())
	if err != OK:
		quit(1)
		return
	noray.register_host()
	print("[noray-test] register_host sent; polling...")
	for i in 300:
		await process_frame
		if noray.pid != "" and noray.oid != "":
			break
	print("[noray-test] RESULT pid='", noray.pid, "' oid='", noray.oid, "' local_port=", noray.local_port)
	quit(0)
