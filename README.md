# Girgit — a hide-and-seek body-painting game

<p align="center">
  <img src="assets/logo.png" alt="Girgit logo" width="220">
</p>

**Girgit** is a multiplayer hide-and-seek game built in **Godot 4.6**. Hiders
paint and pose their bodies to camouflage into the environment, while the
**seeker** stalks the map with a gun and has to find and shoot every hider
before the timer runs out. See [Features](#features) for the details.

> ⚠️ **This game is a work in progress.** It's playable end-to-end, but we're
> actively improving it and adding new maps. Expect rough edges. Bug reports and
> pull requests are very welcome — see [Contributing](#contributing).

---

## Features

- **Hider painting** — per-body-part color (wheel / RGB / HSV / hex), metallic +
  roughness gloss to match surrounding materials, and an eyedropper that samples
  the exact color of any wall, floor, or prop in the world.
- **Poses** — stand, crouch, ball-up, lie flat, wall-flatten. Data-driven and
  easy to extend.
- **Seeker** — first-person hitscan gun, crosshair HUD, paint-splash hit FX.
- **Round loop** — assign roles → prep (hiders paint & hide) → seek → results
  with hide-in-plain-sight scoring.
- **Game modes** — Normal (caught hiders are out), Infection (caught hiders
  become seekers), and Double-seeker.
- **Multiple maps** — Sponza, a furnished house, and a procedural test arena,
  with more on the way.
- **Multiplayer** — host-authoritative, several ways to connect (LAN, direct
  internet, a dedicated server, or Epic relay — see [Multiplayer](#multiplayer--how-to-host)).

---

## Requirements

- **[Godot 4.6](https://godotengine.org/download)** (standard build, GDScript —
  no C# / .NET needed), **Forward+** renderer.
- Windows, macOS (Apple Silicon or Intel), or Linux.
- [Git LFS](https://git-lfs.com) (the repo stores meshes/textures via LFS).

---

## Download & run (from source)

```bash
# 1. Install Git LFS once, then clone
git lfs install
git clone https://github.com/Occupying-Mars/meccha-girgit.git
cd meccha-girgit

# 2. Open the project in Godot 4.6
#    - Godot editor → Import → pick this folder's project.godot → Edit
#    - first import builds shaders/textures; give it a minute
#    - press F5 (or the ▶ Play button) to run

# …or launch straight from the CLI:
godot --path .
```

The game starts at the **main menu**. Enter a name, then **Host** or **Join**.

### Optional: a bigger map (Sponza)

The Sponza scene is included. If you ever need to re-fetch it:

```bash
python3 tools/download_sponza.py   # downloads the CC-BY Sponza glTF
```

---

## Multiplayer — how to host

The game is **host-authoritative**: one machine (or a dedicated server) runs the
match, everyone else connects to it. There are **four ways to connect**, in order
of how much setup they need:

| Method | Setup | Best for |
| --- | --- | --- |
| **LAN** | none | friends on the same Wi-Fi |
| **Direct internet** | router must support UPnP | quick internet games |
| **Dedicated server** | a cheap VPS | a reliable group server (works through *any* NAT) |
| **Epic relay (EOS)** | a build with credentials baked in (see below) | zero-config internet play |

### LAN (zero setup)

Host picks a map/mode and clicks **Host** → shares the **invite code**. Friends
on the same network enter it and **Join**. Done.

### Direct internet (UPnP)

Host ticks **Play over internet**; the game asks your router to open a port via
UPnP and gives you an invite code containing your public IP. Works when your
router allows UPnP. If it can't open the port, use a dedicated server instead.

### Dedicated server (most reliable)

Runs the game headless on a VPS; everyone — including hosts behind strict
(symmetric/CGNAT) networks — connects *outbound* to it, so NAT is never a problem.
Full walkthrough in **[docs/DEDICATED_SERVER.md](docs/DEDICATED_SERVER.md)**:

```bash
# on the VPS
./tools/run_server.sh          # runs the headless server on UDP 24565
# players: leave "online" unchecked, paste the VPS ip[:port] into JOIN
```

### Epic relay (EOS)

Uses Epic Online Services' free relay — friends join by a short code from
anywhere, no port-forwarding, no Epic account (anonymous device login). See the
[note on EOS credentials](#a-note-on-eos-credentials) — it only works in a build
that has an Epic **client secret** compiled in.

---

## Releasing a build (for non-technical players)

Players shouldn't need Godot or the source. To ship a playable build:

1. In Godot: **Project → Export**, add a preset (Windows / macOS / Linux), and
   **Export Project** to an executable.
2. Distribute it (GitHub Releases, itch.io, a zip — your call).
3. Players download, run, and host/join with **LAN**, **direct internet**, or a
   **dedicated server** with zero extra setup.

**If you want EOS relay to "just work" for players:** put your Epic app's
`CLIENT_SECRET` into `scripts/net/eos_net.gd` **locally, before exporting** (do
*not* commit it — see below). It gets compiled into your build, so anyone who
downloads that build gets one-click internet hosting. Anyone who clones the
*source* instead won't have EOS until they add their own Epic app secret, but LAN
/ direct / dedicated all still work for them without it.

### Running a downloaded build (unsigned-app warnings)

These are indie builds with no Apple/Microsoft developer signature, so both OSes
throw an "unknown publisher" warning the first time. That's expected — not a
sign anything's wrong with the build.

**macOS:** unzip, then clear the quarantine flag once from Terminal:

```bash
xattr -cr meccha-girgit.app
```

(drag the `.app` onto the Terminal window after typing `xattr -cr ` to paste its
path, or `cd` to the folder it's in first). Then double-click it normally. If you
skip this, macOS reports it as "damaged and can't be opened" — that's Gatekeeper
blocking an unsigned app, not actual file corruption.

**Windows:** SmartScreen shows "Windows protected your PC" — click **More info →
Run anyway**.

### A note on EOS credentials

`scripts/net/eos_net.gd` ships with the four **public** EOS identifiers (Product,
Sandbox, Deployment, Client ID — these are baked into every EOS game and are not
secrets). The sensitive **`CLIENT_SECRET` is intentionally left empty** in the
repo. To use EOS relay you must supply your own from the
[Epic Dev Portal](https://dev.epicgames.com/portal) (Product Settings → Clients),
locally and uncommitted.

---

## Dev tooling

Contributors have a headless **recorder** for capturing frames without driving
the game by hand:

```bash
godot --headless --quit                                  # parse-check
godot --path . -- --record=NAME --frames=4 --screen=1    # capture frames
# frames land in /tmp/meccha_runs/NAME/ (app user-data dir on Windows)
```

See **[tools/README.md](tools/README.md)** for the full recorder / Blender /
Godot-CLI reference.

---

## Reporting bugs

Found a bug or something that feels off? **Please
[open an issue](https://github.com/Occupying-Mars/meccha-girgit/issues)** with:

- what you did, what you expected, what happened,
- your OS + how you were connected (LAN / direct / dedicated / EOS),
- a screenshot or the console output if you have it.

We use issues as a running activity log, so even small reports help.

---

## Contributing

PRs are accepted and appreciated — new maps, poses, game modes, fixes, polish.
Read **[CONTRIBUTING.md](CONTRIBUTING.md)** before you start.

---

## License

The game's original code is released under the **MIT License** — see
[LICENSE](LICENSE). Bundled third-party components (the Epic EOS SDK, Sponza,
netfox, etc.) keep their own licenses — see [NOTICES.md](NOTICES.md).
