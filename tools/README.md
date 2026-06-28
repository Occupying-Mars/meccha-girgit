# dev tools reference

Custom tooling we've built to let the agent (Claude) build, inspect, and
play the game without human supervision. **Read this first at the start
of any session** so you don't re-derive what's already here.

This is the agent's reference. It is NOT for the user. The user opens
the editor and clicks things; the agent uses the CLI.

---

## the autonomous loop

The shortest version of the agent dev cycle:

1. Make a code change.
2. `godot --headless --quit` — confirm the project parses cleanly.
3. `godot --path . -- --record=<run_name> [--test=<name>] --screen=1` — drive the game and capture PNGs to `/tmp/thegame_runs/<run_name>/`.
4. `Read /tmp/thegame_runs/<run_name>/frame_NNNN.png` — multimodal read confirms the change visually.
5. If broken, iterate. If good, commit directly to `main` and push (no PRs, per `feedback_workflow` memory).

The recorder is what makes step 3 work. Everything else is conventional Godot.

---

## the recorder

Path: `scripts/dev/recorder.gd` (autoload, dormant unless `--record=...` is passed).

**Always pass `--record=<name>`** to activate it. Without it, the game runs normally — safe to ship.

### Flags

| Flag | Default | What it does |
|---|---|---|
| `--record=NAME` | (required) | Activates recorder; outputs to `/tmp/thegame_runs/NAME/` |
| `--frames=N` | 4 | Number of viewport PNGs to capture |
| `--interval=SEC` | 0.5 | Seconds between captures |
| `--warmup=SEC` | 0.5 | Wait before first capture so the scene initializes |
| `--screen=N` | (none) | Spawn window on display N. **Use `--screen=1` on the dev machine** (laptop) so the user's main monitor isn't interrupted. Screen 0 is the external 5K. |
| `--print-screens` | off | Enumerate displays at startup (good first call on a new machine) |
| `--test=NAME` | (none) | Drive a scripted input sequence in parallel with capture |
| `--no-quit` | off | Don't quit after captures (lets the user keep playing) |

### Scripted input tests (`--test=`)

These synthesize `InputEventAction` and route through `Input.parse_input_event` so `is_action_just_pressed` fires correctly. **`Input.action_press()` alone does NOT trigger that** — we tried, it didn't work, the synthesized event is the path that does.

| Test name | What it does |
|---|---|
| `walk_forward` | Holds `move_forward` for 3s |
| `walk_back` | Holds `move_back` for 3s |
| `walk_diag` | Holds `move_forward` + `move_right` together |
| `jump` | Single jump press |
| `dash` | `move_forward` 1.5s, dash at t=0.4 |
| `fire` | 3 LMB shots at 0.3s apart |
| `morph` | Mouse-look left (~0.4s) to aim at MorphA, then 3 morph presses to cycle states |
| `flash` | One flash press at t=0.3 |
| `world_stop` | Walks forward, toggles world_stop at t=0.6 |
| `mouse_look_right` | Synthesized mouse motion to the right |

Add new tests in `scripts/dev/recorder.gd::_run_test_async()`.

### Example calls

```bash
# enumerate displays
godot --path . -- --print-screens --record=probe --frames=1 --warmup=0.2

# static layout check (no input)
godot --path . -- --record=layout_check --frames=2 --warmup=0.5 --screen=1

# verify a scripted action
godot --path . -- --record=fire_check --test=fire --frames=8 --interval=0.1 --warmup=0.3 --screen=1

# long capture (e.g. watch energy drain through world-stop)
godot --path . -- --record=energy_drain --test=world_stop --frames=10 --interval=0.7 --warmup=0.3 --screen=1
```

After each, `Read /tmp/thegame_runs/<name>/frame_NNNN.png` to inspect.

### Important quirks

- **Action presses fire AFTER `frame_post_draw`** in some captures, so the press you scheduled at t=0.3 may not show in the frame_0 capture (which is also at t≈0.3). Schedule presses slightly before captures, or read frames after the press time.
- **`is_action_just_pressed` is one frame.** If your gun fires 3 times but only 2 hits register before the final capture, that's a race with the recorder's screenshot — not a bug.
- **Mouse motion is split across many small events** in `_play_mouse()` because the controller integrates `rotate_y` per event; one huge delta would still rotate, but small deltas are closer to real mouse input.

---

## Blender CLI tools (`tools/blender/`)

We use Blender for all FBX work because Godot 4.x's native FBX import has
unit-scale bugs with Mixamo files. The pipeline is FBX → Blender → GLB →
Godot.

### Blender path on this machine

```
/Applications/Blender.app/Contents/MacOS/Blender
```

(Blender is NOT on `$PATH`; `which blender` returns nothing. Use the full path.)

### `fbx_to_glb.py`

Convert a Mixamo FBX to a Godot-ready GLB at the correct scale.

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python \
    tools/blender/fbx_to_glb.py -- \
    "assets/animations/Walking.fbx" "assets/animations/walking.glb"
```

Applies `global_scale=100` on import (cm → m) and applies transforms before
gltf export. Without this, the GLB ends up at ~1 cm and the character is
invisible in scenes built at meter scale.

### `inspect_fbx.py`

Confirm a new character/animation's rig before importing.

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python \
    tools/blender/inspect_fbx.py -- "assets/animations/Fighting Idle.fbx" \
    2>&1 | grep -E "^(===|  |Armature)"
```

Reports object hierarchy, armature bone count + how many use `mixamorig`
prefix, mesh poly counts, and bundled animations. **If
`mixamo_prefixed == bone_count`, Mixamo animations will retarget cleanly.**

### `measure_glb.py`

Report the actual world-space bounds of a GLB's skinned mesh.

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python \
    tools/blender/measure_glb.py -- "assets/models/characters/protagonist.glb" \
    2>&1 | grep -E "(MESH|ARMATURE|size|height)"
```

Use after a fresh import to confirm the character is roughly 2 m tall. If
geometry comes back at 0.01 m wide, the FBX conversion forgot to apply
unit scale — re-run `fbx_to_glb.py`. The protagonist's bare GLB is ~1 m
tall and the player scene applies `scale = 2` on the Mesh node to land at
human proportions.

---

## Video → animation pipeline (`tools/mocap/`)

End-to-end: any single-person video → mixamo-rigged GLB animation drop-in.
Uses GVHMR (cloned at `~/Public/experiments/gvhmr`) for SMPL prediction,
bakes onto X Bot as the canonical animation, then transfers onto the
actual gameplay character.

**Current canonical characters** (in `assets/models/characters/`):
- `protagonist.glb` — hero rig, ~6ft, normalized bone names
- `villain.glb` — generic antagonist placeholder
- `x_bot.glb` — clean Mixamo T-pose, used as retarget intermediate

**Current animation library** (in `assets/animations/`):
- `idle.glb` — locomotion (combat idle, converted from `Fighting Idle.fbx`)
- `run.glb` — locomotion (clean X-Bot intermediate)
- `jump.glb` — locomotion (clean X-Bot intermediate)
- `dash.glb` — defensive (clean X-Bot intermediate of the sidestep-dodge)
- `punch_jab.glb` — combat
- `sidestep_dodge.glb` — defensive
- `roundhouse_kick.glb` — combat
- `walk.glb` — **stale/broken** (protagonist-transfer, lies down). Unused;
  needs re-shooting from a new reference. See issue #29.

The locomotion clips are consolidated into `locomotion.res` and driven by an
AnimationTree — see the locomotion pipeline under Godot CLI tools.

**Orientation gotcha (issue #29):** the player is driven by the **X-Bot rig**
(`x_bot.glb`), not `protagonist.glb`. The protagonist placeholder has a broken
rest pose and `transfer_to_character.py` strips the standing rotation, so
transferred clips lie down. Build the library from the clean X-Bot retarget
intermediates (`/tmp/mocap_runs/<name>/xbot.glb`), not protagonist outputs,
until #29 is fixed. **Always verify orientation from a pulled-back camera or a
standalone `preview_anim.py` render — a close-up of a lying-down torso reads as
upright.** Each mocap clip ships with `assets/references/<name>.mp4` +
`.meta.json` (regeneratable).

### One-time setup

```bash
# 1. pull all weights (~5GB) from HF mirrors into ~/Public/experiments/gvhmr
tools/mocap/download_weights.sh
```

Pulls 4 GVHMR checkpoints + SMPL/SMPLX body models from `camenduru/GVHMR`
and `camenduru/SMPLer-X` on Hugging Face. No license-gated registration
needed.

### Per-clip usage (one command, end-to-end)

```bash
# YouTube URL → animation on the protagonist
python tools/mocap/fetch_and_animate.py "https://youtu.be/XYZ" jab_combo --start 5 --end 12

# locomotion clip (preserve root translation)
python tools/mocap/fetch_and_animate.py URL dodge_left --keep-transl

# bake on both protagonist + villain
python tools/mocap/fetch_and_animate.py URL idle_taunt --targets protagonist,villain

# local file instead of YouTube
python tools/mocap/fetch_and_animate.py /path/to/clip.mp4 fight_kick
```

Outputs:
- `assets/references/<name>.mp4`      — trimmed source clip
- `assets/references/<name>.meta.json` — URL, trim, retarget params
- `assets/animations/<name>.glb`     — baked on protagonist (canonical)
- `assets/animations/<name>.villain.glb` — if villain target requested
- `/tmp/mocap_runs/<name>/`           — inference intermediates (regenerable)

Internally chains: yt-dlp → infer.py (GVHMR on MPS/CPU) → prep_for_blender.py →
blender_retarget.py (bakes onto X Bot) → transfer_to_character.py (X Bot → target).

Defaults tuned for game-ready output: wrists zeroed, translation zeroed
(in-place animation), finger/hand/toe bones skipped during transfer (avoids
rest-pose spike artifacts).

### Verification renderers

```bash
# render the retargeted GLB by itself
/Applications/Blender.app/Contents/MacOS/Blender --background --python \
    tools/mocap/preview_anim.py -- \
    --glb assets/animations/myclip.glb --action Action_Armature \
    --out-dir /tmp/anim_preview/myclip --resolution 800x800 --fps 30 \
    --video /tmp/anim_preview/myclip.mp4

# render side-by-side against GVHMR's raw SMPL prediction (sanity check)
cd ~/Public/experiments/gvhmr && .venv/bin/python \
    ~/Public/experiments/thegame/tools/mocap/export_smpl_mesh.py \
    --pred /tmp/mocap_runs/myclip/hmr4d_results.pt \
    --smpl inputs/checkpoints/body_models/smpl/SMPL_NEUTRAL.pkl \
    --space incam --center \
    --out /tmp/mocap_runs/myclip/smpl_mesh.npz

/Applications/Blender.app/Contents/MacOS/Blender --background --python \
    tools/mocap/preview_side_by_side.py -- \
    --smpl-npz /tmp/mocap_runs/myclip/smpl_mesh.npz \
    --target-glb assets/animations/myclip.glb \
    --video /tmp/anim_preview/myclip_sbs.mp4 --fps 30 \
    --resolution 1280x720 --separation 2.5
```

### Key files (`tools/mocap/`)

| File | Role |
|---|---|
| `fetch_and_animate.py` | **The orchestrator.** YouTube URL → game-ready GLB. Call this. |
| `download_weights.sh` | One-time weight pull from HF mirrors |
| `infer.py` | Video → SMPL params (`.pt`). MPS shim for `.cuda()` calls. |
| `prep_for_blender.py` | `.pt` + SMPL pkl → numpy `.npz` (blender-friendly) |
| `blender_retarget.py` | SMPL `.npz` + target rig → animation `.glb` on X Bot canonical |
| `transfer_to_character.py` | X Bot animation → any mixamorig target. Local-pose-quat copy. Skips finger/hand/toe bones (rest-pose mismatch causes spike artifacts). |
| `export_smpl_mesh.py` | SMPL params → per-frame vertex mesh `.npz` for ground-truth viz |
| `preview_anim.py` | Render any retargeted GLB to PNGs or MP4 |
| `preview_side_by_side.py` | Render SMPL prediction next to retargeted target — debugging |
| `preview_smpl.py` | Render raw SMPL skeleton as sphere figure (debug) |
| `compare_rests.py` | Dump per-bone rest-orientation offsets (diagnostic) |

### Pipeline data flow

```
YouTube URL ──yt-dlp──► assets/references/<name>.mp4
                              │
                              ▼
                       GVHMR (infer.py)
                  preproc on MPS / forward on CPU
                              │
                              ▼
                       hmr4d_results.pt
                              │
                              ▼
                  prep_for_blender.py
                  flattens to numpy .npz
                              │
                              ▼
                  blender_retarget.py
              bakes onto X Bot (canonical clean T-pose)
                              │
                              ▼
                  transfer_to_character.py
        local-pose-quat copy → assets/animations/<name>.glb
```

The two-stage retarget (bake on X Bot first, then transfer to character)
is the architectural decision that made the pipeline robust across
character rigs. Direct SMPL→target retarget broke on per-character
rest-matrix variations; X Bot is the known-good intermediate, and
local-pose-quat copy from X Bot to any mixamorig target sidesteps the
rest-matrix divergence entirely.

### Target rig requirements

- Must use mixamo bone names (`mixamorig:Hips`, `mixamorig:LeftArm`, …).
  Confirm with `inspect_fbx.py`. If bones came in as `mixamorigHips`
  (no colon), normalize them with the snippet in `transfer_to_character.py`.
- **Clean T-pose at rest is recommended but not required.** The X Bot
  intermediate absorbs source rest-pose quirks; targets just need
  matching bone names. Tested: `protagonist.glb`, `villain.glb`, `x_bot.glb`.

### Known limitations

- Single person only. Multi-person clips would need the YOLO tracker re-wired.
- HMR4D forward runs on CPU (MPS slice-op assert in the windowed
  transformer). Preproc still runs on MPS. ~15-25 min total per 6-12s clip.
- Root translation zeroed by default (in-place animation, loopable).
  Use `--keep-transl` on locomotion clips that need to travel.
- Wrists zeroed by default (GVHMR's wrist predictions are noisy).
- Finger / hand / toe bones skipped during X Bot→target transfer because
  rest-pose mismatches there produce visible spike artifacts. Body, arms,
  legs transfer fine.

---

## Godot CLI tools (`tools/godot/`)

These are `extends SceneTree` scripts, runnable headlessly via:

```bash
godot --headless --script tools/godot/<name>.gd
```

### `enum_screens.gd`

Lists connected displays. Headless mode usually reports 0; for real
enumeration use the recorder's `--print-screens` with a real window. Kept
here for reference + documented indices.

### `inspect_anims.gd`

Dump every `AnimationPlayer` animation in a GLB, with per-track summary
(name, type, key count, first key value). Pass the GLB path after `--`:

```bash
godot --headless --script tools/godot/inspect_anims.gd -- res://assets/animations/run.glb
```

Useful when an animation does something unexpected — track type 1 is
position, type 2 is rotation; if a Hips position track has a non-trivial Y
value, that's why the character floats.

### locomotion animation pipeline (`build_locomotion_library.gd` + `build_player_anim_tree.gd`)

How loose clip GLBs become the protagonist's playable locomotion. Run both,
in order, any time you add or repoint a clip:

```bash
godot --headless --import                                          # pick up new GLBs
godot --headless --script tools/godot/build_locomotion_library.gd  # -> locomotion.res
godot --headless --script tools/godot/build_player_anim_tree.gd    # -> player_locomotion_tree.tres
```

1. **`build_locomotion_library.gd`** consolidates per-clip GLBs into one
   `AnimationLibrary` (`assets/animations/locomotion.res`) on the protagonist
   rig. Each clip GLB carries a single `TargetAction` whose tracks are rooted
   at the *source* rig's armature node (mocap clips → `Target/Skeleton3D`,
   protagonist → `Armature/Skeleton3D`). The builder **canonicalizes every
   track path to `Armature/Skeleton3D`**, so any mixamo-named clip (mocap or
   Mixamo) drops in identically. Edit the `CLIPS` dict to add/repoint clips
   and set per-clip loop mode. Missing GLBs are skipped, so it degrades
   gracefully while clips are still being generated.
2. **`build_player_anim_tree.gd`** generates the `AnimationTree` root
   (`player_locomotion_tree.tres`): an `AnimationNodeStateMachine` wrapping a
   1D `BlendSpace` (Ground: idle@0 → walk@1 → run@2) plus `Jump`/`Fall`/`Dash`
   states. It only creates states whose clips exist in the library, so
   re-running after adding clips expands the tree automatically.

The scene side (`player.tscn`): a `LocomotionPlayer` (holds `locomotion.res`)
+ an `AnimationTree` (uses the `.tres` root) + an `Animator` node running
`PlayerAnimator`. The controller reports body state (speed, airborne,
dashing); `PlayerAnimator` maps it to blend params / state travel. Verify
changes with the recorder's `walk_forward` / `jump` / `dash` tests.

---

## screen indices on this machine

| Index | Display | Use it for |
|---|---|---|
| 0 | External 5K monitor (5120×2160 @ ~93 dpi) | The user's main work surface — **don't spawn windows here** unless asked |
| 1 | M4 MacBook Pro internal (3024×1964 @ ~256 dpi) | **Default for agent-driven `--record` runs** |

Pass `--screen=1` on every `--record=` call.

---

## Godot 4.6 CLI cheatsheet

| Command | What it does |
|---|---|
| `godot --path .` | Run the game (main scene from `project.godot`) |
| `godot --path . --editor` (or `-e`) | Open the editor |
| `godot --headless --quit` | Parse-check the project and exit — fast sanity check after edits |
| `godot --headless --import` | Re-scan and import any new assets dropped in `assets/` |
| `godot --headless --script PATH.gd` | Run a `extends SceneTree` one-off |
| `godot --path . -- ARG1 ARG2 ...` | Args after the bare `--` go to `OS.get_cmdline_user_args()` — that's how the recorder reads its flags |

---

## input action map (current bindings)

| Action | Key | Notes |
|---|---|---|
| `move_forward` | W |  |
| `move_back` | S |  |
| `move_left` | A |  |
| `move_right` | D |  |
| `jump` | Space |  |
| `dash` | Shift (tap) | Hold becomes Block once #16 lands |
| `fire` | LMB |  |
| `morph` | E |  |
| `flash` | T |  |
| `world_stop` | Q |  |
| `interact` | F |  |
| `lock_on` | MMB | Will move to R3/RMB-hold per deck §15 once #18 lands |

---

## conventions to keep

- **No PRs.** Direct commit to `main`. (`feedback_workflow` memory.)
- **One GitHub issue per "thing".** Open before starting, close in the commit message (`Closes #N`).
- **Prefer ship-quality choices over throwaway shortcuts.** (`feedback_ship_quality_choices` memory.) Throwaway placeholder *meshes* on the correct *rig* are fine; wrong rig is not.
- **Never push `.skip`/dead-code/half-finished stuff.** CLAUDE.md says: "do not push unnecassary scat files."
- **The recorder is the eyes.** If a change is visual, capture and `Read` the PNG before reporting done. If you can't drive it with input (combat feel, etc.), say so and ask the user to playtest.
