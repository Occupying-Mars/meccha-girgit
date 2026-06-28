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

## current state

- `scenes/game/test_arena.tscn` is the main scene: procedural colored arena +
  one third-person hider blob.
- Hider blob is procedural primitive parts (`scripts/hider/hider_body.gd`) so
  each body part colors independently — PHASE 1 painting is color-block per
  part; freehand texture painting is a later upgrade.
