extends SceneTree
## Consolidate individual animation GLBs into one AnimationLibrary on the
## protagonist's rig, so a single AnimationPlayer + AnimationTree can drive
## them all.
##
## Usage:
##     godot --headless --script tools/godot/build_locomotion_library.gd
##
## Why this exists: each clip ships as its own GLB with a `TargetAction`
## animation whose tracks are rooted at `Target/Skeleton3D:mixamorig_*`
## (the X Bot retarget intermediate names its armature "Target"). The
## protagonist's own rig roots at `Armature/Skeleton3D:mixamorig_*`. To play
## an external clip on the protagonist we must rewrite every track's node
## path onto the protagonist's skeleton layout. This script canonicalizes
## ALL track paths to `Armature/Skeleton3D` regardless of the source rig's
## armature node name, so the builder is source-agnostic (mocap or Mixamo).
##
## Output: res://assets/animations/locomotion.res (AnimationLibrary)

const OUT_PATH := "res://assets/animations/locomotion.res"

## Canonical skeleton node path. The player mesh is walk.glb's good protagonist
## rig, whose skeleton sits under "Target" (named by transfer_to_character).
const CANON_SKEL := "Target/Skeleton3D"

## clip definitions: anim_name -> { glb, loop }
## loop=true for cyclic locomotion, false for one-shot actions.
## Missing GLBs are skipped with a warning so the build degrades gracefully
## while clips are still being generated.
## Clips are the clean X-Bot retarget intermediates (standing rotation baked
## into the Hips). The protagonist-transfer step strips that rotation and
## bakes its broken lying-down rest instead, so we drive the X-Bot rig
## directly until a correctly-rested hero asset exists. See README.
const CLIPS := {
	# All clips are now on walk.glb's good protagonist rig. `yaw` (per-clip,
	# about world-up) re-normalizes each clip's facing to -Z — dialed in after
	# testing since footage angles differ. Start at 0 and adjust.
	# idle = Mixamo Fighting Idle. Its baked Hips yaw is stripped by
	# _freeze_hips_rotation, so it shares the identity Hips baseline with
	# every other clip — no rotation pop on transitions. The fighting-stance
	# pose (arms up, slight crouch) is encoded in spine/arms/head bones,
	# untouched by the freeze, so the visual pose survives.
	"idle": {"glb": "res://assets/animations/idle.glb", "loop": true,  "yaw": 0.0},
	"walk": {"glb": "res://assets/animations/walk.glb", "loop": true,  "yaw": 0.0},
	# run is sourced from Mixamo's XBOT run-cycle preview (fwKSOzv_NIE) —
	# real-time game cadence, no slow-mo correction needed. The turntable
	# rotation in the source is absorbed by _freeze_hips_rotation; only the
	# clean limb motion survives.
	"run":  {"glb": "res://assets/animations/run.glb",  "loop": true,  "yaw": 0.0,  "trim_start": 0.1},
	"jump": {"glb": "res://assets/animations/jump.glb", "loop": false, "yaw": 0.0},
	"dash": {"glb": "res://assets/animations/dash.glb", "loop": false, "yaw": 90.0},
}


func _init() -> void:
	var lib := AnimationLibrary.new()
	var added := 0
	for anim_name in CLIPS:
		var spec: Dictionary = CLIPS[anim_name]
		var glb_path: String = spec["glb"]
		if not ResourceLoader.exists(glb_path):
			print("SKIP  ", anim_name, "  (missing ", glb_path, ")")
			continue
		var anim := _extract_animation(glb_path)
		if anim == null:
			print("FAIL  ", anim_name, "  (no animation in ", glb_path, ")")
			continue
		_canonicalize_tracks(anim)
		_ground_hips(anim)
		_freeze_hips_rotation(anim)
		if spec.get("yaw", 0.0) != 0.0:
			_apply_yaw(anim, spec["yaw"])
		if spec.get("trim_start", 0.0) > 0.0:
			_trim_start(anim, spec["trim_start"])
		if spec.get("speed", 1.0) != 1.0:
			_rescale_speed(anim, spec["speed"])
		anim.loop_mode = Animation.LOOP_LINEAR if spec["loop"] else Animation.LOOP_NONE
		lib.add_animation(anim_name, anim)
		print("ADD   ", anim_name, "  len=", String.num(anim.length, 2),
			"s  tracks=", anim.get_track_count(), "  loop=", spec["loop"])
		added += 1

	if added == 0:
		print("ERROR: no clips added; nothing written.")
		quit(1)
		return

	var err := ResourceSaver.save(lib, OUT_PATH)
	if err != OK:
		print("ERROR: save failed (", err, ")")
		quit(1)
		return
	print("\nWROTE ", OUT_PATH, "  (", added, " clips)")
	quit()


## Load a GLB and return a deep copy of its first animation, or null.
func _extract_animation(glb_path: String) -> Animation:
	var packed := load(glb_path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var ap := _find_ap(inst)
	if ap == null:
		return null
	var names := ap.get_animation_list()
	if names.is_empty():
		return null
	# Duplicate so we own a mutable copy independent of the imported resource.
	return ap.get_animation(names[0]).duplicate(true)


## Rewrite every track's node path so the skeleton resolves at CANON_SKEL,
## preserving the bone subname. Tracks not targeting a Skeleton3D are left
## untouched (none expected for these clips, but safe).
func _canonicalize_tracks(anim: Animation) -> void:
	for t in anim.get_track_count():
		var np := anim.track_get_path(t)
		var names := []
		for i in np.get_name_count():
			names.append(np.get_name(i))
		var skel_idx := names.find("Skeleton3D")
		if skel_idx == -1:
			continue
		# Rebuild as Armature/Skeleton3D + any names below the skeleton,
		# carrying the original subnames (the bone, e.g. mixamorig_Hips).
		var rebuilt := CANON_SKEL
		for i in range(skel_idx + 1, names.size()):
			rebuilt += "/" + String(names[i])
		var subs := ""
		for i in np.get_subname_count():
			subs += ":" + np.get_subname(i)
		anim.track_set_path(t, NodePath(rebuilt + subs))


## Grounded baseline Hips height. The mocap locomotion clips share this value;
## the Mixamo-sourced idle comes in ~0.5m higher, which floats it off the floor
## and makes the character dip when transitioning to movement. Shift each clip's
## Hips Y so its first frame sits at this baseline (preserves the natural bob).
const REF_HIPS_Y := 0.0906

func _ground_hips(anim: Animation) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not String(anim.track_get_path(t)).ends_with("mixamorig_Hips"):
			continue
		if anim.track_get_key_count(t) == 0:
			return
		var first: Vector3 = anim.track_get_key_value(t, 0)
		var dy := REF_HIPS_Y - first.y
		# Lock X and Z to the first frame so the character runs/walks IN PLACE.
		# Mocap preserves the runner's natural lateral hip sway as a per-frame X
		# drift, which reads as the character sliding left/right mid-stride —
		# fine for free motion, wrong for an in-place game clip the controller
		# is driving forward.
		for k in anim.track_get_key_count(t):
			var v: Vector3 = anim.track_get_key_value(t, k)
			v.x = first.x
			v.y += dy
			v.z = first.z
			anim.track_set_key_value(t, k, v)
		return


## Drop keys before `t_offset` and shift remaining keys back by t_offset.
## Used to skip the leading T-pose / rest frames Mixamo-style clips include at
## the start, so a looped clip closes onto a running pose instead of snapping
## to rest.
func _trim_start(anim: Animation, t_offset: float) -> void:
	if t_offset <= 0.0:
		return
	for t in anim.get_track_count():
		var n := anim.track_get_key_count(t)
		if n == 0:
			continue
		# Read all (time, value) pairs first so we can fully rewrite the track.
		var keys := []
		for k in n:
			var kt := anim.track_get_key_time(t, k)
			if kt < t_offset:
				continue
			keys.append({"t": kt - t_offset, "v": anim.track_get_key_value(t, k)})
		# Remove existing keys (back to front).
		for k in range(n - 1, -1, -1):
			anim.track_remove_key(t, k)
		# Insert the shifted keys.
		for kv in keys:
			anim.track_insert_key(t, kv.t, kv.v)
	anim.length = max(0.0, anim.length - t_offset)


## Rescale every key time and the clip's length by 1/factor, so the same
## motion plays back `factor` times faster. Used for clips sourced from
## slow-motion footage (GVHMR processes per-frame; the resulting clip plays
## at the source's slow-mo cadence, not real-time). factor=2 means 2x speed.
func _rescale_speed(anim: Animation, factor: float) -> void:
	if factor <= 0.0:
		return
	var inv := 1.0 / factor
	# Read all keys first, then rewrite times — track_set_key_time reorders.
	for t in anim.get_track_count():
		var n := anim.track_get_key_count(t)
		if n == 0:
			continue
		var times := []
		times.resize(n)
		for k in n:
			times[k] = anim.track_get_key_time(t, k) * inv
		# Apply in reverse so each successive set doesn't re-sort earlier keys
		# into the wrong index.
		for k in range(n - 1, -1, -1):
			anim.track_set_key_time(t, k, times[k])
	anim.length *= inv


## Freeze the torso rotation tracks to identity across all keys. Originally
## just Hips (to kill body yaw at blend transitions), now also extends to the
## Spine chain because the Mixamo idle bakes a fighting-stance body cant into
## Spine/Spine1/Spine2 that read as a slight east rotation. Body direction
## comes purely from the controller's _face_movement; clips animate the limbs
## (arms, head, legs) only. Trade-off: no breathing torso bob or pelvic
## counter-rotation. Swap for swing-twist (zero Y only) if more life is needed.
const FROZEN_BONES := [
	"mixamorig_Hips",
	"mixamorig_Spine",
	"mixamorig_Spine1",
	"mixamorig_Spine2",
]

func _freeze_hips_rotation(anim: Animation) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := String(anim.track_get_path(t))
		var matched := false
		for bone in FROZEN_BONES:
			if path.ends_with(bone):
				matched = true
				break
		if not matched:
			continue
		for k in anim.track_get_key_count(t):
			anim.track_set_key_value(t, k, Quaternion.IDENTITY)


## Yaw the clip's facing by pre-rotating the Hips rotation track. The standing
## rotation (~-90 deg X) is baked into the Hips keys, so world-up maps to the
## Hips parent's Z axis — pre-multiplying each key by a rotation about Z turns
## the standing character left/right.
const YAW_AXIS := Vector3(0, 1, 0)

func _apply_yaw(anim: Animation, yaw_deg: float) -> void:
	var q := Quaternion(YAW_AXIS, deg_to_rad(yaw_deg))
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		if not String(anim.track_get_path(t)).ends_with("mixamorig_Hips"):
			continue
		for k in anim.track_get_key_count(t):
			var key: Quaternion = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, q * key)
		return


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r:
			return r
	return null
