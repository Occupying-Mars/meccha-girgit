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
3. **Painting** — color individual body parts; color wheel / RGB / HSV;
   gloss sliders; eyedropper ("spoid") that samples world surface colors.
4. **Poses** — curl, crouch, lie flat, wall-flatten (+ unstick).
5. **Seeker** — first-person camera + gun, shoot to eliminate.
6. **Round loop** — assign → prep → seek → results.
7. **Multiplayer** — peer/host (later, user-directed).

## Dev loop

```bash
godot --headless --quit                              # parse-check
godot --path . -- --record=NAME --screen=1 [--test=] # capture frames
# then Read /tmp/meccha_runs/NAME/frame_NNNN.png
```

Recorder output goes to `/tmp/meccha_runs/` (note: NOT `thegame_runs`).
See `tools/README.md` for the full recorder + Blender + Godot CLI reference
(inherited from the parent project).
