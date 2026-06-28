"""Render N preview frames of a retargeted animation GLB to PNG.

Quick visual sanity check — load the GLB, advance through the action,
render each chosen frame from a fixed front-three-quarter camera.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \\
        tools/mocap/preview_anim.py -- \\
        --glb assets/animations/tennis_smpl.glb \\
        --action Action_Armature \\
        --out-dir /tmp/anim_preview/tennis \\
        --frames 0,60,120,180,240
"""
from __future__ import annotations

import argparse
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
    p.add_argument("--glb", required=True)
    p.add_argument("--action", default=None, help="Action name to play (default: pick last imported)")
    p.add_argument("--out-dir", required=True)
    p.add_argument("--frames", default="0,30,60,90,120", help="comma-separated frame indices")
    p.add_argument("--resolution", default="800x600")
    p.add_argument("--video", default=None, help="If set, write an MP4 spanning the full action instead of stills")
    p.add_argument("--fps", type=int, default=30)
    return p.parse_args(argv)


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    frames = [int(x) for x in args.frames.split(",")]
    w, h = (int(x) for x in args.resolution.lower().split("x"))

    # Empty scene.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.glb)

    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        raise RuntimeError("No armature in GLB")

    # Pick action.
    if args.action and args.action in bpy.data.actions:
        action = bpy.data.actions[args.action]
    else:
        # Heuristic: highest frame count action.
        action = max(bpy.data.actions, key=lambda a: a.frame_range[1] - a.frame_range[0])
    arm.animation_data_create() if arm.animation_data is None else None
    arm.animation_data.action = action
    print(f"[preview] action = {action.name}, range = {action.frame_range}")

    # Light + camera.
    bpy.ops.object.light_add(type="SUN", location=(2, -2, 3))
    bpy.context.object.data.energy = 3.0

    # Compute scene bounds by sampling bone head/tail positions across the
    # whole action (rest-pose bound_box doesn't reflect posed extents).
    F_start = int(action.frame_range[0])
    F_end = int(action.frame_range[1])
    sample_frames = [F_start + (F_end - F_start) * i // 8 for i in range(9)]
    bbox_min = mathutils.Vector((1e9, 1e9, 1e9))
    bbox_max = mathutils.Vector((-1e9, -1e9, -1e9))
    for sf in sample_frames:
        bpy.context.scene.frame_set(sf)
        bpy.context.view_layer.update()
        for pb in arm.pose.bones:
            for vert in (pb.head, pb.tail):
                wv = arm.matrix_world @ vert
                for i in range(3):
                    bbox_min[i] = min(bbox_min[i], wv[i])
                    bbox_max[i] = max(bbox_max[i], wv[i])
    center = (bbox_min + bbox_max) * 0.5
    size = max((bbox_max - bbox_min).length, 2.0)
    print(f"[preview] bbox min={tuple(bbox_min)} max={tuple(bbox_max)} center={tuple(center)} size={size:.2f}")

    cam_data = bpy.data.cameras.new("cam")
    cam_obj = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    # Position camera at a front-three-quarter angle. Tighter framing — we want
    # the figure to fill the shot. Assume ~2m tall character.
    height = max(size * 0.5, 2.0)
    offset = mathutils.Vector((height * 0.5, -height * 1.2, height * 0.0))
    cam_obj.location = center + offset
    direction = center - mathutils.Vector(cam_obj.location)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 50  # mm; ~normal portrait
    bpy.context.scene.camera = cam_obj

    # Render setup.
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {e.identifier for e in type(scn.render).bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"
    scn.render.resolution_x = w
    scn.render.resolution_y = h
    scn.render.image_settings.file_format = "PNG"
    scn.render.film_transparent = False

    # World background colour for contrast.
    if scn.world is None:
        scn.world = bpy.data.worlds.new("World")
    scn.world.use_nodes = True
    bg = scn.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.05, 0.05, 0.07, 1.0)

    if args.video:
        # Render the full action as an mp4.
        scn.render.fps = args.fps
        scn.frame_start = int(action.frame_range[0])
        scn.frame_end = int(action.frame_range[1])
        scn.render.image_settings.file_format = "FFMPEG"
        scn.render.ffmpeg.format = "MPEG4"
        scn.render.ffmpeg.codec = "H264"
        scn.render.ffmpeg.constant_rate_factor = "MEDIUM"
        scn.render.filepath = str(Path(args.video).expanduser())
        bpy.ops.render.render(animation=True)
        print(f"[preview] wrote video → {scn.render.filepath}")
    else:
        for f in frames:
            scn.frame_set(f)
            scn.render.filepath = str(out_dir / f"frame_{f:04d}.png")
            bpy.ops.render.render(write_still=True)
            print(f"[preview] wrote frame {f} → {scn.render.filepath}")


if __name__ == "__main__":
    main()
