# Contributing to Girgit

Thanks for wanting to help! This is a small, actively-developed game and
contributions of all sizes are welcome — bug fixes, new maps, new poses, game
modes, polish, docs. This guide gets you set up and explains how we work.

## Ground rules

- **Be kind and constructive.** It's a hobby project; keep it fun.
- **One thing per PR.** A PR should do a single coherent thing (one fix, one
  feature). Small PRs get reviewed and merged faster.
- **Open an issue first for anything big.** For a new system or a large change,
  [file an issue](https://github.com/Occupying-Mars/meccha-girgit/issues) to
  discuss it before you build — it saves everyone rework. Small fixes can go
  straight to a PR.

## Getting set up

1. Install **[Godot 4.6](https://godotengine.org/download)** (standard build) and
   **[Git LFS](https://git-lfs.com)**.
2. Fork the repo, then:
   ```bash
   git lfs install
   git clone https://github.com/<your-username>/meccha-girgit.git
   cd meccha-girgit
   godot --path .        # or open project.godot in the editor
   ```
3. Make a branch: `git checkout -b fix/short-description`.

## Development workflow

The fast inner loop uses the headless **recorder** so you can verify changes
without playing by hand:

```bash
godot --headless --quit                                  # parse-check (catches syntax errors)
godot --path . -- --record=NAME --frames=4 --screen=1    # capture frames to inspect
# open /tmp/meccha_runs/NAME/frame_NNNN.png  (app user-data dir on Windows)
```

For multiplayer changes, run two instances (a headless server + a windowed
client) — see the two-instance pattern in `CLAUDE.md`. Full tooling reference:
`tools/README.md`.

**Always parse-check before you commit** (`godot --headless --quit`). Note that
this only compiles autoloads + the main scene — to catch an error in a specific
scene's scripts, load that scene: `godot --headless <scene.tscn> --quit`.

## Code style

- **GDScript**, matching the surrounding code. Use **tabs** for indentation
  (Godot's default).
- **Type your variables and function signatures** where it helps the compiler and
  the reader (`var who: String = ...`, `func foo(x: int) -> void:`).
- **Name things clearly.** Scripts, nodes, and signals should say what they are.
- **Comment the "why", not the "what".** Explain non-obvious decisions; skip
  narrating obvious lines.
- Keep the folder structure clean — scripts under `scripts/<area>/`, scenes under
  `scenes/<area>/`. Don't add throwaway/scratch files.

## Commits

- **Atomic commits with descriptive messages.** One logical change per commit.
- Use a conventional prefix where it fits: `feat(area): …`, `fix(area): …`,
  `docs: …`, `refactor(area): …`.
- Explain *why* in the body if it isn't obvious from the summary.

## Adding content (the easy wins)

- **A new pose:** add an entry to `scripts/characters/pose_library.gd` — it's
  data-driven.
- **A new map:** add it to the `MAPS` dict in `scripts/net/net_game.gd` (script,
  spawn point, lighting) and provide a build function. Look at how `arena`,
  `sponza`, and the house map are wired.
- **A new game mode:** extend the mode handling in the round loop
  (`scripts/core/game_state.gd`) and the lobby picker.

## Submitting a PR

1. Push your branch and open a PR against `main`.
2. In the description, say **what** it does, **why**, and **how you tested it**
   (recorder frames, a two-instance run, manual play — whatever applies).
3. Link any related issue.
4. Expect a little back-and-forth — that's normal and how things stay clean.

## Reporting bugs

Not writing code? Bug reports are hugely valuable. See the "Reporting bugs"
section in the [README](README.md#reporting-bugs).

## Licensing of contributions

By submitting a PR you agree that your contribution is licensed under the
project's [MIT License](LICENSE). Don't add third-party assets/code unless their
license permits redistribution — and if you do, record it in
[NOTICES.md](NOTICES.md).
