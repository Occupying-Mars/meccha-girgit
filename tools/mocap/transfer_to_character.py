"""Transfer a baked animation from X Bot (or any source mixamo rig) onto a
target character that shares mixamorig bone names but has different rest
matrices.

Bypasses our retarget's per-character matrix quirks by copying *world*
pose matrices per frame, not local rotations. Each shared bone:
    target.pose_bone.matrix = source.pose_bone.matrix
Blender computes matrix_basis from parent + rest automatically.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \\
        tools/mocap/transfer_to_character.py -- \\
        --source assets/animations/walk.glb \\
        --target assets/models/characters/main_blend.glb \\
        --out    assets/animations/walk_main.glb \\
        --fps 30
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
import mathutils


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    p = argparse.ArgumentParser()
    p.add_argument("--source", required=True, help="GLB with the source animation (X Bot)")
    p.add_argument("--target", required=True, help="GLB of the target character (any mixamorig rig)")
    p.add_argument("--out", required=True, help="Output GLB (target + transferred animation)")
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--skip-fingers", action="store_true", default=True,
                   help="Leave finger bones at target's own rest (default). "
                        "X Bot's finger rest pose differs from most characters "
                        "and transferring it produces spiky hand distortion.")
    p.add_argument("--include-fingers", action="store_false", dest="skip_fingers",
                   help="Override --skip-fingers and transfer finger bones too.")
    p.add_argument("--shoulder-spread", type=float, default=0.0,
                   help="Extra outward rotation (degrees) applied to LeftArm/RightArm "
                        "to widen shoulder span. Useful when character's rig has "
                        "shoulders closer together than the source rig, causing "
                        "hands to clip the chest during arm swing.")
    return p.parse_args(argv)


FINGER_BONE_KEYWORDS = ("Thumb", "Index", "Middle", "Ring", "Pinky", "HandTop", "Hand",
                        "Toe", "ToeBase")


def main() -> None:
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)

    bpy.ops.import_scene.gltf(filepath=args.source)
    src_arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    src_arm.name = "Source_X"
    src_action = max(bpy.data.actions, key=lambda a: a.frame_range[1] - a.frame_range[0])
    if src_arm.animation_data is None:
        src_arm.animation_data_create()
    src_arm.animation_data.action = src_action
    f_start = int(src_action.frame_range[0])
    f_end = int(src_action.frame_range[1])
    L = f_end - f_start + 1
    print(f"[transfer] source action {src_action.name}, frames {f_start}-{f_end} ({L} frames)")

    bpy.ops.import_scene.gltf(filepath=args.target)
    tgt_arm = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.name != "Source_X")
    tgt_arm.name = "Target"
    # Clear any baked action on target so it starts from rest
    if tgt_arm.animation_data is not None:
        tgt_arm.animation_data_clear()
    print(f"[transfer] target {tgt_arm.name}, bones={len(tgt_arm.data.bones)}")

    # Mapped bones = intersection by name
    src_names = {b.name for b in src_arm.data.bones}
    tgt_names = {b.name for b in tgt_arm.data.bones}
    common = sorted(src_names & tgt_names)
    if args.skip_fingers:
        before = len(common)
        common = [n for n in common if not any(k in n for k in FINGER_BONE_KEYWORDS)]
        print(f"[transfer] skip-fingers ON: dropped {before - len(common)} finger bones")
    only_src = sorted(src_names - tgt_names)
    only_tgt = sorted(tgt_names - src_names)
    print(f"[transfer] common bones: {len(common)} | source-only: {len(only_src)} | target-only: {len(only_tgt)}")

    scn = bpy.context.scene
    scn.render.fps = args.fps
    scn.frame_start = 1
    scn.frame_end = L

    bpy.context.view_layer.objects.active = tgt_arm
    bpy.ops.object.mode_set(mode="POSE")

    # Topological order: process parents before children so each child reads
    # its parent's already-set pose when computing matrix_basis.
    def bone_depth(arm, bone_name):
        b = arm.data.bones[bone_name]
        d = 0
        while b.parent is not None:
            d += 1
            b = b.parent
        return d
    common_ordered = sorted(common, key=lambda n: bone_depth(tgt_arm, n))

    # Direct local-pose-quaternion copy. Source's matrix_basis represents
    # its rotation relative to its own rest; copying that 1:1 preserves
    # "bend joint X°" semantics regardless of how the target's rest matrix
    # is oriented. Tried world-pose copy and FK-delta-from-rest variants
    # earlier; both introduced spike artifacts when rest matrices diverged.
    # Local copy is the only formulation that consistently keeps the target
    # mesh deforming relative to its own bind pose.
    # Pre-compute shoulder-spread quats (applied on LeftArm/RightArm to widen
    # the apparent shoulder span). The arm bone in mixamo points along its
    # local +Y toward the elbow; rotating around local Z swings it outward
    # (left vs right gets opposite sign).
    spread_rad = math.radians(args.shoulder_spread)
    spread_L = mathutils.Quaternion((0.0, 0.0, 1.0), -spread_rad)
    spread_R = mathutils.Quaternion((0.0, 0.0, 1.0),  spread_rad)

    for i, f in enumerate(range(f_start, f_end + 1)):
        scn.frame_set(f)
        bpy.context.view_layer.update()
        for name in common_ordered:
            src_pb = src_arm.pose.bones[name]
            tgt_pb = tgt_arm.pose.bones[name]
            tgt_pb.rotation_mode = "QUATERNION"
            q = src_pb.rotation_quaternion.copy()
            if spread_rad != 0.0:
                if name == "mixamorig:LeftArm":
                    q = spread_L @ q
                elif name == "mixamorig:RightArm":
                    q = spread_R @ q
            tgt_pb.rotation_quaternion = q
            tgt_pb.keyframe_insert("rotation_quaternion", frame=i + 1)
            if tgt_pb.parent is None:
                tgt_pb.location = src_pb.location.copy()
                tgt_pb.keyframe_insert("location", frame=i + 1)

    bpy.ops.object.mode_set(mode="OBJECT")

    # Drop everything except the target armature + its meshes
    keep_collection = {tgt_arm}
    for o in bpy.data.objects:
        if o.parent == tgt_arm or o == tgt_arm:
            keep_collection.add(o)
    for o in list(bpy.data.objects):
        if o not in keep_collection:
            bpy.data.objects.remove(o, do_unlink=True)

    # Drop source actions; keep only the new baked one
    new_action = tgt_arm.animation_data.action if tgt_arm.animation_data else None
    for act in list(bpy.data.actions):
        if act is not new_action:
            bpy.data.actions.remove(act)

    out_path = Path(args.out).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        export_animations=True,
        export_skins=True,
        export_force_sampling=True,
    )
    print(f"[transfer] WROTE {out_path}")


if __name__ == "__main__":
    main()
