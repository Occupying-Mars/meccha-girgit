"""Visualize raw GVHMR SMPL prediction as an animated stick figure.

Renders the SMPL armature (24 bones) driven by the *unmodified* body_pose
+ global_orient + transl from blender_input.npz. No retargeting — this
is what GVHMR's output actually looks like in SMPL coordinates, useful
for comparing against the mixamo-retargeted version.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \\
        tools/mocap/preview_smpl.py -- \\
        --npz /tmp/mocap_runs/<name>/blender_input.npz \\
        --video /tmp/anim_preview/<name>_smpl.mp4 --fps 30
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
import mathutils

# Reuse the bone-build / keying logic from the retarget script.
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
    p.add_argument("--video", required=True)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--resolution", default="800x600")
    return p.parse_args(argv)


def main() -> None:
    args = parse_args()
    w, h = (int(x) for x in args.resolution.lower().split("x"))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    parents, rest_joints, smpl_params = br.load_blender_input(Path(args.npz))
    L = smpl_params["body_pose"].shape[0]

    src = br.build_smpl_armature(parents, rest_joints)
    src.data.display_type = "OCTAHEDRAL"
    src.show_in_front = True
    br.key_smpl_action(src, smpl_params, args.fps)

    # Build joint spheres + bone cylinders as real meshes so EEVEE renders them.
    # Each frame, drivers update sphere positions from pose-bone heads.
    spheres: list[bpy.types.Object] = []
    bone_names = br.SMPL_JOINT_NAMES
    for name in bone_names:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.04, segments=12, ring_count=8)
        sph = bpy.context.object
        sph.name = f"j_{name}"
        # Constrain sphere position to follow the bone head.
        c = sph.constraints.new("COPY_LOCATION")
        c.target = src
        c.subtarget = name
        c.head_tail = 0.0  # head end of the bone
        c.target_space = "WORLD"
        c.owner_space = "WORLD"
        # Magenta so it pops against the dark bg.
        mat = bpy.data.materials.new(f"mat_{name}")
        mat.diffuse_color = (1.0, 0.2, 0.7, 1.0)
        sph.data.materials.append(mat)
        spheres.append(sph)
    # Slightly larger spheres for head + hands so the silhouette reads.
    spheres[bone_names.index("Head")].scale = (2.0, 2.0, 2.0)
    for hand in ("L_Wrist", "R_Wrist"):
        spheres[bone_names.index(hand)].scale = (1.6, 1.6, 1.6)

    # Auto-frame.
    bpy.context.scene.frame_set(L // 2)
    bpy.context.view_layer.update()
    bbox_min = mathutils.Vector((1e9, 1e9, 1e9))
    bbox_max = mathutils.Vector((-1e9, -1e9, -1e9))
    bpy.context.view_layer.objects.active = src
    bpy.ops.object.mode_set(mode="POSE")
    for pb in src.pose.bones:
        for vert in (pb.head, pb.tail):
            wv = src.matrix_world @ vert
            for i in range(3):
                bbox_min[i] = min(bbox_min[i], wv[i])
                bbox_max[i] = max(bbox_max[i], wv[i])
    bpy.ops.object.mode_set(mode="OBJECT")
    center = (bbox_min + bbox_max) * 0.5
    size = max((bbox_max - bbox_min).length, 2.0)
    print(f"[smpl-preview] bbox={tuple(bbox_min)}..{tuple(bbox_max)} size={size:.2f}")

    bpy.ops.object.light_add(type="SUN", location=(2, -2, 3))
    bpy.context.object.data.energy = 3.0

    cam_data = bpy.data.cameras.new("cam")
    cam_obj = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    offset = mathutils.Vector((size * 0.6, -size * 1.2, size * 0.3))
    cam_obj.location = center + offset
    direction = center - mathutils.Vector(cam_obj.location)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 50
    bpy.context.scene.camera = cam_obj

    scn = bpy.context.scene
    if scn.world is None:
        scn.world = bpy.data.worlds.new("World")
    scn.world.use_nodes = True
    scn.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.07, 1.0)
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {e.identifier for e in type(scn.render).bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"
    scn.render.resolution_x = w
    scn.render.resolution_y = h
    scn.render.fps = args.fps
    scn.frame_start = 1
    scn.frame_end = L
    scn.render.image_settings.file_format = "FFMPEG"
    scn.render.ffmpeg.format = "MPEG4"
    scn.render.ffmpeg.codec = "H264"
    scn.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scn.render.filepath = str(Path(args.video).expanduser())
    bpy.ops.render.render(animation=True)
    print(f"[smpl-preview] wrote {scn.render.filepath}")


if __name__ == "__main__":
    main()
