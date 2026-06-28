"""Move arm bones outward to match a reference rig's joint positions.

Edit-mode translates LeftShoulder/LeftArm/LeftForeArm/LeftHand (and mirror)
head positions to the reference's X coordinates, keeping Y/Z. Mesh follows
the bones via skinning weights — visually the arms get pushed outward, so
the back-swing during walk no longer brings hands through the torso.

Usage:
    blender --background --python tools/blender/fix_arm_proportions.py -- \\
        --target assets/models/characters/new_try.glb \\
        --reference assets/models/characters/villain.glb \\
        --out assets/models/characters/new_try_armfix.glb
"""
import argparse, sys, bpy, mathutils
from pathlib import Path


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--")+1:] if "--" in argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--target", required=True)
    p.add_argument("--reference", required=True)
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


ARM_BONES = [
    "mixamorig:LeftShoulder", "mixamorig:LeftArm",
    "mixamorig:LeftForeArm", "mixamorig:LeftHand",
    "mixamorig:RightShoulder", "mixamorig:RightArm",
    "mixamorig:RightForeArm", "mixamorig:RightHand",
]


def get_bone_x(glb_path: str, name: str) -> float:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    if name not in arm.data.bones:
        return None
    return (arm.matrix_world @ arm.data.bones[name].head_local).x


def main() -> None:
    args = parse_args()

    # Pull reference X-positions for each arm bone (positive = subject's left).
    ref_x = {n: get_bone_x(args.reference, n) for n in ARM_BONES}
    print("[armfix] reference X positions:")
    for n, x in ref_x.items():
        print(f"  {n:32s} x = {x:+.3f}m" if x is not None else f"  {n}: missing")

    # Load target
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.target)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")

    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")

    # For each arm bone: translate the bone (and only this bone, not children)
    # so its head's X matches the reference. Use shift to translate both head
    # and tail equally (preserves bone length and direction).
    arm_world_inv = arm.matrix_world.inverted()
    for name in ARM_BONES:
        if name not in arm.data.edit_bones:
            continue
        if ref_x.get(name) is None:
            continue
        eb = arm.data.edit_bones[name]
        cur_x_world = (arm.matrix_world @ eb.head).x
        delta_x = ref_x[name] - cur_x_world
        if abs(delta_x) < 0.005:
            continue
        # Convert delta from world to armature local
        delta_local = arm_world_inv.to_3x3() @ mathutils.Vector((delta_x, 0, 0))
        # Shift head AND tail by same delta so bone length/direction preserved
        eb.head = eb.head + delta_local
        eb.tail = eb.tail + delta_local
        print(f"[armfix] shifted {name}: world Δx = {delta_x:+.3f}m")

    bpy.ops.object.mode_set(mode="OBJECT")

    bpy.ops.export_scene.gltf(filepath=args.out, export_format="GLB",
                               export_animations=True, export_skins=True)
    print(f"[armfix] WROTE {args.out}")


if __name__ == "__main__":
    main()
