# meccha-chameleon

A hide-and-seek **body-painting** game in Godot 4.6, inspired by MECCHA
CHAMELEON. Hiders are pure-white bipedal blobs who paint themselves and pose
to blend into the environment; seekers hunt and shoot them before a timer ends.

This is a standalone project (its own git repo) that **shares the dev tooling**
from the parent `thegame` project — see `tools/README.md`.

## Design source

`seeker.md` (in the parent repo) is the full spec. Core systems, in build order:

1. **Arena** — colored test environment (camouflage test bed). ✅
2. **Hider** — third-person blob, roam movement. ✅
3. **Painting** — per body part: color (wheel/RGB/HSV/hex), metallic+roughness
   gloss, eyedropper ("spoid") that samples world surface colors. ✅
   (Phase 1 = color-block per part; freehand texture paint is a later upgrade.)
4. **Poses** — stand/crouch/ball/lie-flat/wall-flatten (data-driven, extensible). ✅
5. **Seeker** — first-person camera + hitscan gun, shoot to eliminate. ✅
6. **Round loop** — assign → prep → seek → results (phase/timer HUD). ✅
7. **Multiplayer** — peer/host (NEXT, user-directed).

## Dev loop

```bash
godot --headless --quit                              # parse-check
godot --path . -- --record=NAME --screen=1 [--test=] # capture frames
# then Read /tmp/meccha_runs/NAME/frame_NNNN.png
```

Recorder output goes to `/tmp/meccha_runs/` (note: NOT `thegame_runs`).
See `tools/README.md` for the full recorder + Blender + Godot CLI reference
(inherited from the parent project).
