# video-to-animation pipeline

Take a YouTube clip (or any video of a single person) and produce a
mixamo-rigged GLB animation that drops onto our protagonist.

## chain

```
video.mp4 ──► GVHMR (local, MPS) ──► smpl_params.pt
                                          │
              ┌───────────────────────────┘
              ▼
       Blender retarget script ──► assets/animations/<name>.glb
                                          │
                                          ▼
                                   Godot AnimationPlayer
```

## one-time setup

GVHMR repo lives at `~/Public/experiments/gvhmr` (sibling to this repo,
keeps the game checkout small). It owns its own `.venv` (uv-managed,
Python 3.10).

### 1. body models (manual, free account)

Register at:
- https://smpl.is.tue.mpg.de/
- https://smpl-x.is.tue.mpg.de/

Then place:
- `SMPL_NEUTRAL.pkl` → `~/Public/experiments/gvhmr/inputs/checkpoints/body_models/smpl/SMPL_NEUTRAL.pkl`
- `SMPLX_NEUTRAL.npz` → `~/Public/experiments/gvhmr/inputs/checkpoints/body_models/smplx/SMPLX_NEUTRAL.npz`

### 2. GVHMR weights

```bash
tools/mocap/download_weights.sh
```

Pulls 4 checkpoints (~2 GB total) from the official Google Drive into
`~/Public/experiments/gvhmr/inputs/checkpoints/`.

## per-clip usage

```bash
# from a youtube url, frames 5-15 seconds
tools/mocap/run.sh "https://youtu.be/XYZ" --start 5 --end 15 --name fighting_idle

# or a local file
tools/mocap/run.sh /path/to/clip.mp4 --name running_kick
```

Outputs `assets/animations/<name>.glb`, importable as an AnimationPlayer
track on the protagonist.

## notes

- **single person only** (project decision; multi-person retarget is messy)
- **static-camera mode** by default (skips DPVO/colmap which are CUDA-only).
  If the source video has a moving camera, motion will look slightly drifty
  but still usable for reference animations.
- runs on m4 MPS. Expect ~real-time to 5x-realtime per clip depending on
  resolution. 720p clips are the sweet spot.
