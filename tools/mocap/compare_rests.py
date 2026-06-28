"""Diagnostic: render SMPL and Mixamo rest poses side-by-side, and dump the
per-bone rest-orientation offset that retargeting needs to compensate for.

Outputs:
- /tmp/anim_preview/rest_compare.png  (side-by-side render)
- stdout: a table of (smpl_idx, mix_name, offset_quat) — copy into retarget config

Run:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \\
        tools/mocap/compare_rests.py -- \\
        --npz /tmp/mocap_runs/<name>/blender_input.npz \\
        --rig assets/models/characters/protagonist.glb \\
        --out /tmp/anim_preview/rest_compare.png
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
import mathutils

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blender_retarget as br  # type: ignore


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    p = argparse.ArgumentParser()
    p.add_argument("--npz", required=True)
    p.add_argument("--rig", required=True)
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


def world_rot_at_rest(arm: bpy.types.Object, bone_name: str) -> mathutils.Matrix:
    """Bone's 3x3 world rotation in rest pose."""
    bone = arm.data.bones[bone_name]
    return (arm.matrix_world @ bone.matrix_local).to_3x3()


def main() -> None:
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)

    parents, rest_joints, _ = br.load_blender_input(Path(args.npz))

    # Build SMPL armature on the left, mixamo on the right.
    src = br.build_smpl_armature(parents, rest_joints)
    src.location = (-1.5, 0, 0)
    src.show_in_front = True

    tgt = br.load_target_rig(Path(args.rig))
    tgt.location = (1.5, 0, 0)

    bpy.context.view_layer.update()

    # Per-bone diagnostic dump.
    print("\n=== rest-pose comparison ===")
    print(f"{'idx':>3} {'smpl bone':<14} {'mixamo bone':<28} | offset_quat (w,x,y,z)")
    print("-" * 100)
    for smpl_idx, mix_name in br.SMPL_TO_MIXAMO.items():
        if mix_name not in tgt.pose.bones:
            continue
        smpl_name = br.SMPL_JOINT_NAMES[smpl_idx]
        smpl_rest = world_rot_at_rest(src, smpl_name)
        mix_rest = world_rot_at_rest(tgt, mix_name)
        # Offset = the rotation that takes mixamo rest world → SMPL rest world.
        offset = (smpl_rest @ mix_rest.transposed()).to_quaternion()
        print(f"{smpl_idx:>3} {smpl_name:<14} {mix_name:<28} | "
              f"({offset.w:+.3f}, {offset.x:+.3f}, {offset.y:+.3f}, {offset.z:+.3f})")

    # ── Render side-by-side ─────────────────────────────────────────────────
    # Light
    bpy.ops.object.light_add(type="SUN", location=(0, -5, 5))
    bpy.context.object.data.energy = 3.0

    # Camera
    cam_data = bpy.data.cameras.new("cam")
    cam_obj = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, -5, 1.5)
    direction = mathutils.Vector((0, 0, 1.0)) - mathutils.Vector(cam_obj.location)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 35
    bpy.context.scene.camera = cam_obj

    scn = bpy.context.scene
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {e.identifier for e in type(scn.render).bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"
    scn.render.resolution_x = 1600
    scn.render.resolution_y = 900
    if scn.world is None:
        scn.world = bpy.data.worlds.new("World")
    scn.world.use_nodes = True
    scn.world.node_tree.nodes["Background"].inputs[0].default_value = (0.06, 0.06, 0.08, 1.0)

    # Make SMPL armature bones renderable as magenta tubes (since EEVEE skips bone display).
    for pb in src.pose.bones:
        bone = src.data.bones[pb.name]
        head = src.matrix_world @ bone.head_local
        tail = src.matrix_world @ bone.tail_local
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.025, location=head)
        sph = bpy.context.object
        m = bpy.data.materials.new(f"m_{pb.name}")
        m.diffuse_color = (1.0, 0.2, 0.7, 1.0)
        sph.data.materials.append(m)

    scn.render.image_settings.file_format = "PNG"
    scn.render.filepath = str(Path(args.out).expanduser())
    bpy.ops.render.render(write_still=True)
    print(f"\nwrote {scn.render.filepath}")


if __name__ == "__main__":
    main()
