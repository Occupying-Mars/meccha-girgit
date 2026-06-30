extends CanvasLayer
## Live top-down minimap, top-right. A SubViewport re-renders the real World3D
## from straight above (sharing the main world) and follows the local player; a
## cyan arrow marks the player's position + facing. Other players show as blobs.
## Works on any map. Created by net_game for non-dedicated (windowed) clients.

const PX := 200          # on-screen size (px)
const VIEW := 19.0       # world half-extent shown (smaller = more zoomed in)
const MARGIN := 14

var _players: Node3D
var _self_id: int = 1
var _sub: SubViewport
var _cam: Camera3D
var _arrow: Polygon2D
var _me: Node3D


func setup(players_root: Node3D) -> void:
	_players = players_root


func _ready() -> void:
	layer = 20
	if multiplayer.has_multiplayer_peer():  # in-tree now, so `multiplayer` is valid
		_self_id = multiplayer.get_unique_id()
	# --- SubViewport: re-render the live world from above ---
	_sub = SubViewport.new()
	_sub.size = Vector2i(PX, PX)
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.transparent_bg = false
	_sub.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_sub)
	_sub.world_3d = get_viewport().find_world_3d()  # share the main scene
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = VIEW * 2.0
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # straight down, north-up
	_cam.position = Vector3(0, 60, 0)
	_cam.far = 300.0
	# Render the map but NOT player bodies, so nobody's position leaks on the
	# minimap — only your own arrow (drawn in 2D below) shows where you are.
	_cam.cull_mask = 0xFFFFF & ~HiderBody.MINIMAP_HIDE_LAYER
	_sub.add_child(_cam)
	_cam.current = true

	# --- On-screen frame, top-right ---
	var panel := Panel.new()
	# Top-LEFT so it never overlaps the paint panel (which lives on the right).
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.offset_left = MARGIN
	panel.offset_top = MARGIN
	panel.offset_right = MARGIN + PX + 8
	panel.offset_bottom = MARGIN + PX + 8
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.82, 0.70, 0.40, 0.9)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var tr := TextureRect.new()
	tr.texture = _sub.get_texture()
	tr.position = Vector2(4, 4)
	tr.size = Vector2(PX, PX)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	panel.add_child(tr)

	_arrow = Polygon2D.new()
	_arrow.polygon = PackedVector2Array([Vector2(0, -8), Vector2(6, 7), Vector2(0, 3.5), Vector2(-6, 7)])
	_arrow.color = Color(0.30, 0.90, 1.0)
	_arrow.position = Vector2(PX / 2.0 + 4, PX / 2.0 + 4)
	panel.add_child(_arrow)

	var lbl := Label.new()
	lbl.text = "MAP"
	lbl.position = Vector2(7, 1)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(1, 1, 1, 0.55)
	panel.add_child(lbl)


func _process(_dt: float) -> void:
	if _me == null or not is_instance_valid(_me):
		if _players == null or not is_instance_valid(_players):
			return
		_me = _players.get_node_or_null(str(_self_id)) as Node3D
		if _me == null:
			return
	var gp := _me.global_position
	_cam.position = Vector3(gp.x, 60.0, gp.z)
	# Facing: prefer the look yaw (CameraYaw) so the arrow points where you look.
	var yaw := _me.global_rotation.y
	var yawnode := _me.get_node_or_null("CameraYaw") as Node3D
	if yawnode != null:
		yaw = yawnode.global_rotation.y
	_arrow.rotation = yaw  # north-up minimap: screen-down is +Z, so +yaw aligns
