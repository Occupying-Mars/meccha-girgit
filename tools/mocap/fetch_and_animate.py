"""End-to-end: YouTube URL → game-ready animation on protagonist + villain.

    python tools/mocap/fetch_and_animate.py URL NAME [--start S] [--end E]
                                            [--targets protagonist,villain]
                                            [--keep-transl]

Folder layout this builds:
    assets/references/
        NAME.mp4                  the trimmed source clip
        NAME.meta.json            URL, trim range, notes, retarget params
    assets/animations/
        NAME.glb                  baked on the protagonist (canonical)
        NAME.villain.glb          baked on the villain (if requested)
    /tmp/mocap_runs/NAME/         inference intermediates (gitignored)

Defaults are tuned for game-ready output:
    - wrists zeroed (GVHMR's wrist predictions are noisy)
    - translation zeroed (animations are in-place; loop / walk-on-spot)
    - transfer skips finger/hand/toe bones (rest-pose mismatches cause spikes)

Requires (one-time):
    uv tool install lium.io  # not needed for this script
    uv tool install yt-dlp
    ~/Public/experiments/gvhmr/.venv  with weights downloaded
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
REFS = REPO / "assets/references"
ANIMS = REPO / "assets/animations"
GVHMR = Path(os.environ.get("GVHMR_DIR", str(Path.home() / "Public/experiments/gvhmr")))
GVHMR_PY = GVHMR / ".venv/bin/python"
SMPL_PKL = GVHMR / "inputs/checkpoints/body_models/smpl/SMPL_NEUTRAL.pkl"
BLENDER = "/Applications/Blender.app/Contents/MacOS/Blender"
XBOT_GLB = REPO / "assets/models/characters/x_bot.glb"
TARGETS = {
    "protagonist": REPO / "assets/models/characters/protagonist.glb",
    "villain":     REPO / "assets/models/characters/villain.glb",
}


def slugify(name: str) -> str:
    keep = "-_."
    return "".join(c if c.isalnum() or c in keep else "_" for c in name).strip("_")


def run(cmd: list[str], **kw) -> None:
    print(f"\n$ {' '.join(shlex.quote(c) for c in cmd)}")
    subprocess.run(cmd, check=True, **kw)


def yt_download(url: str, dst: Path, start: float | None, end: float | None) -> None:
    """yt-dlp into dst, trimming if --start/--end set."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    args = [
        "yt-dlp",
        "-f", "best[height<=720]",
        "-o", str(dst.with_suffix(".%(ext)s")),
        "--merge-output-format", "mp4",
    ]
    if start is not None or end is not None:
        s = f"{start or 0}" if start else "0"
        e = f"{end}" if end else ""
        args += ["--download-sections", f"*{s}-{e}"]
    args.append(url)
    run(args)
    # yt-dlp may write .mkv/.webm depending on source; normalize to .mp4
    if not dst.exists():
        for alt in dst.parent.glob(dst.stem + ".*"):
            if alt.suffix != ".meta.json":
                shutil.move(str(alt), str(dst))
                break


def gvhmr_infer(video: Path, out_dir: Path) -> Path:
    """video → out_dir/hmr4d_results.pt"""
    out_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
    cmd = [
        str(GVHMR_PY), str(REPO / "tools/mocap/infer.py"),
        "--video", str(video), "--out-dir", str(out_dir),
    ]
    print(f"\n$ {' '.join(shlex.quote(c) for c in cmd)}")
    subprocess.run(cmd, check=True, env=env, cwd=GVHMR)
    return out_dir / "hmr4d_results.pt"


def prep_blender_input(pred: Path, out_npz: Path, keep_transl: bool) -> None:
    args = [str(GVHMR_PY), str(REPO / "tools/mocap/prep_for_blender.py"),
            "--pred", str(pred), "--smpl", str(SMPL_PKL),
            "--space", "incam", "--zero-wrists", "--out", str(out_npz)]
    if not keep_transl:
        args.append("--zero-transl")
    print(f"\n$ {' '.join(shlex.quote(c) for c in args)}")
    subprocess.run(args, check=True, cwd=GVHMR)


def bake_on_xbot(npz: Path, out_glb: Path, fps: int) -> None:
    args = [BLENDER, "--background", "--python",
            str(REPO / "tools/mocap/blender_retarget.py"), "--",
            "--npz", str(npz), "--rig", str(XBOT_GLB),
            "--out", str(out_glb), "--fps", str(fps)]
    run(args)


def transfer(source_glb: Path, target_glb: Path, out_glb: Path, fps: int) -> None:
    args = [BLENDER, "--background", "--python",
            str(REPO / "tools/mocap/transfer_to_character.py"), "--",
            "--source", str(source_glb), "--target", str(target_glb),
            "--out", str(out_glb), "--fps", str(fps)]
    run(args)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("url", help="YouTube URL (or local .mp4 path)")
    p.add_argument("name", help="Animation name, e.g. fight_jab, dodge_left")
    p.add_argument("--start", type=float, default=None, help="Trim start (seconds)")
    p.add_argument("--end", type=float, default=None, help="Trim end (seconds)")
    p.add_argument("--targets", default="protagonist",
                   help="Comma-separated subset of: protagonist,villain. Default: protagonist")
    p.add_argument("--keep-transl", action="store_true",
                   help="Keep root translation (for locomotion clips that need to travel)")
    p.add_argument("--fps", type=int, default=30)
    args = p.parse_args()

    name = slugify(args.name)
    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    for t in targets:
        if t not in TARGETS:
            sys.exit(f"unknown target '{t}'. choose from: {','.join(TARGETS)}")

    # 1. download / copy source
    REFS.mkdir(parents=True, exist_ok=True)
    ANIMS.mkdir(parents=True, exist_ok=True)
    ref_mp4 = REFS / f"{name}.mp4"
    if args.url.startswith(("http://", "https://", "youtu", "www.")):
        yt_download(args.url, ref_mp4, args.start, args.end)
    else:
        src = Path(args.url).expanduser()
        if not src.exists():
            sys.exit(f"local file not found: {src}")
        shutil.copy2(src, ref_mp4)

    meta = {
        "name": name,
        "source_url": args.url,
        "trim_start": args.start,
        "trim_end": args.end,
        "fps": args.fps,
        "keep_transl": args.keep_transl,
        "targets": targets,
    }
    (REFS / f"{name}.meta.json").write_text(json.dumps(meta, indent=2))

    # 2. GVHMR inference
    work = Path("/tmp/mocap_runs") / name
    pred = gvhmr_infer(ref_mp4, work)

    # 3. prep + bake on X Bot (canonical animation)
    npz = work / "blender_input.npz"
    prep_blender_input(pred, npz, args.keep_transl)
    xbot_anim = work / "xbot.glb"
    bake_on_xbot(npz, xbot_anim, args.fps)

    # 4. transfer to each requested target
    for t in targets:
        suffix = "" if t == "protagonist" else f".{t}"
        out_glb = ANIMS / f"{name}{suffix}.glb"
        transfer(xbot_anim, TARGETS[t], out_glb, args.fps)
        print(f"[fetch_and_animate] ✓ {out_glb.relative_to(REPO)}")

    print(f"\n[fetch_and_animate] done. reference: {ref_mp4.relative_to(REPO)}")


if __name__ == "__main__":
    main()
