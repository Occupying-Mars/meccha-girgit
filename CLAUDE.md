# rules (meccha-chameleon)

This is a **separate project** from the parent `thegame`. It has its own git
repo. Do not mix commits between the two.

- make atomic commits, descriptive messages.
- one GitHub issue per "thing" (a system: painting, poses, seeker, etc.) once a
  remote exists; issues are a running activity log. No remote yet → commit to
  `main` locally.
- no PRs. direct to `main`. (solo repo.)
- keep clean, well-named, structured code so things are easy to find.
- don't push clutter / dead files.
- **build the feel first, look second.** test one mechanic at a time with the
  recorder before moving on.

## what this game is

Hide-and-seek body painting (MECCHA CHAMELEON clone). Full spec: `../seeker.md`.
Build order: arena → hider movement → painting → poses → seeker+gun → round
loop → multiplayer (user-directed, last).

## dev tooling

Shared from parent, copied into `tools/`. Read `tools/README.md` first.
Key difference: recorder output dir is `/tmp/meccha_runs/` (not `thegame_runs`).

Dev loop: edit → `godot --headless --quit` → `godot --path . -- --record=NAME
--screen=1 [--test=NAME]` → Read the PNG. Always `--screen=1` on the dev machine.

## current state (single-player core complete; multiplayer is next, user-directed)

Scenes:
- `scenes/game/test_arena.tscn` (main) — colored arena + playable hider +
  round HUD; starts a match (prep countdown).
- `scenes/game/seeker_test.tscn` — arena + camouflaged dummies + FP seeker.

Done & verified (via recorder):
- Arena: `arena_builder.gd` procedural colored test bed.
- Hider: `hider_controller.gd` third-person roam + orbit cam.
- Painting: `paint_menu` — per-part color (wheel/RGB/HSV/hex), metallic +
  roughness gloss, eyedropper ("spoid") raycast world sampler (P to open).
- Poses: `pose_library.gd` + `pose_menu` — stand/crouch/ball/lie_flat/
  wall_flatten (Tab to open). Data-driven; add a pose to the dict.
- Seeker: `seeker_controller.gd` FP hitscan gun, `seeker_hud` crosshair +
  counters; `hider_dummy` painted/posed targets that eliminate() on hit.
- Round loop: `game_state.gd` (assign→prep→seek→results) + `round_hud`.

PHASE-1 caveat: painting is color-block per body PART, not freehand texture
paint. Body is procedural primitive parts (`hider_body.gd`). Freehand
texture painting + per-part hitboxes (so shots match posed visuals) are
planned upgrades.

NEXT: multiplayer (peer/host) — the user will direct this. GameState +
match_runner + round_hud were built host-authoritative-friendly so a
MultiplayerSpawner/Synchronizer layer can drop on top.

## recorder tests (this project)

`--test=`: walk_forward/back/diag, jump, fire, look_left/right, look_walk,
paint_demo, pose (with `--pose=NAME`). Output: `/tmp/meccha_runs/<name>/`.
Non-default scene: `godot --path . scenes/game/seeker_test.tscn -- --record=...`.
