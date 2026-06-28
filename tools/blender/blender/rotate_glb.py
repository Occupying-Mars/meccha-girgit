"""Rigidly rotate a GLB (armature + mesh + animation) and bake the transform.

Per-clip yaw correction baked into the asset itself — preserves every key's
relative motion (unlike pre-multiplying each Hips quaternion in Godot, which
conjugates multi-axis bone motion through the rotation and can amplify
secondary sway).

    blender --background --python tools/blender/rotate_glb.py -- \\
        --in  assets/animations/run.glb \\
        --out assets/animations/run_rotated.glb \\
        --ry 90
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--in", dest="inp", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--rx", type=float, default=0.0)
    p.add_argument("--ry", type=float, default=0.0)
    p.add_argument("--rz", type=float, default=0.0)
    return p.parse_args(argv)


def main() -> None:
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.inp)

    roots = [o for o in bpy.data.objects if o.parent is None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in roots:
        o.select_set(True)
    bpy.context.view_layer.objects.active = roots[0]
    for o in roots:
        o.rotation_euler[0] += math.radians(args.rx)
        o.rotation_euler[1] += math.radians(args.ry)
        o.rotation_euler[2] += math.radians(args.rz)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

    out_path = Path(args.out).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        export_animations=True,
        export_skins=True,
        export_force_sampling=True,
    )
    print(f"[rotate_glb] WROTE {out_path}  (rx={args.rx} ry={args.ry} rz={args.rz})")


if __name__ == "__main__":
    main()
