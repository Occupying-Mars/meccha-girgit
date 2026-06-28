extends SceneTree
## Build the protagonist's locomotion AnimationTree root (a state machine
## wrapping a 1D locomotion blendspace) and save it as a reusable resource.
##
## Usage:
##     godot --headless --script tools/godot/build_player_anim_tree.gd
##
## Structure produced:
##     AnimationNodeStateMachine (root)
##       Ground : AnimationNodeBlendSpace1D   idle@0 -> walk@1 -> run@2
##       Jump   : AnimationNodeAnimation       (added only if jump clip exists)
##       Fall   : AnimationNodeAnimation       (reuses jump apex; added w/ jump)
##       Dash   : AnimationNodeAnimation       (added only if dash clip exists)
##     transitions: Ground<->Jump, Jump->Fall, Fall->Ground,
##                  Ground<->Dash  (all code-driven via travel())
##
## States referencing a clip are only created when that clip is present in
## the library, so the tree stays valid while clips are still being made.
## Re-run after generating run/jump/dash to expand it.
##
## Output: res://assets/animations/player_locomotion_tree.tres

const LIB_PATH := "res://assets/animations/locomotion.res"
const OUT_PATH := "res://assets/animations/player_locomotion_tree.tres"
const XFADE := 0.15


func _init() -> void:
	var lib := load(LIB_PATH) as AnimationLibrary
	if lib == null:
		print("ERROR: could not load ", LIB_PATH)
		quit(1)
		return
	var has := func(n: String) -> bool: return lib.has_animation(n)

	if not has.call("idle") or not has.call("run"):
		print("ERROR: library needs at least idle + run")
		quit(1)
		return

	var sm := AnimationNodeStateMachine.new()

	# --- Ground: 1D locomotion blendspace driven by horizontal speed ratio.
	# idle@0, walk@1 (if present), run@2. Without walk it collapses to
	# idle@0 -> run@2 (still spans the same 0..2 ratio the controller feeds).
	var ground := AnimationNodeBlendSpace1D.new()
	ground.min_space = 0.0
	ground.max_space = 2.0
	ground.add_blend_point(_clip("idle"), 0.0)
	if has.call("walk"):
		ground.add_blend_point(_clip("walk"), 1.0)
	ground.add_blend_point(_clip("run"), 2.0)
	sm.add_node("Ground", ground, Vector2(300, 100))

	var states := ["Ground"]

	# --- Jump / Fall: one airborne clip split into rise + apex-hold states.
	if has.call("jump"):
		sm.add_node("Jump", _clip("jump"), Vector2(560, 40))
		sm.add_node("Fall", _clip("jump"), Vector2(560, 160))
		states.append_array(["Jump", "Fall"])
		_link(sm, "Ground", "Jump")
		_link(sm, "Jump", "Fall")
		_link(sm, "Fall", "Ground")

	# --- Dash: one-shot horizontal burst.
	if has.call("dash"):
		sm.add_node("Dash", _clip("dash"), Vector2(300, 280))
		states.append("Dash")
		_link(sm, "Ground", "Dash")
		_link(sm, "Dash", "Ground")

	var err := ResourceSaver.save(sm, OUT_PATH)
	if err != OK:
		print("ERROR: save failed (", err, ")")
		quit(1)
		return
	print("WROTE ", OUT_PATH)
	print("  states: ", ", ".join(states))
	print("  ground max_space=", ground.max_space)
	quit()


## An AnimationNodeAnimation pointing at a clip in the (default) library.
func _clip(name: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = name
	return n


## Add a code-driven transition (travel() picks the path).
func _link(sm: AnimationNodeStateMachine, from: String, to: String) -> void:
	var tr := AnimationNodeStateMachineTransition.new()
	tr.xfade_time = XFADE
	tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	sm.add_transition(from, to, tr)
