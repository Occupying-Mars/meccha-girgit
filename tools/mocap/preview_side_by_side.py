"""Render side-by-side: GVHMR SMPL mesh (left) vs retargeted X Bot (right).

Drives the SMPL mesh from a precomputed verts npz; drives the X Bot from
its embedded action. Spits out an mp4.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \\
        tools/mocap/preview_side_by_side.py -- \\
        --smpl-npz /tmp/mocap_runs/<name>/smpl_mesh.npz \\
        --target-glb assets/animations/<name>.glb \\
        --video /tmp/anim_preview/<name>_sbs.mp4 \\
        --fps 30
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
import mathutils
import numpy as np


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    p = argparse.ArgumentParser()
    p.add_argument("--smpl-npz", required=True)
    p.add_argument("--target-glb", required=True)
    p.add_argument("--video", required=True)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--resolution", default="1280x720")
    p.add_argument("--separation", type=float, default=2.0, help="X offset between rigs")
    return p.parse_args(argv)


def build_smpl_mesh(verts0: np.ndarray, faces: np.ndarray, x_offset: float) -> bpy.types.Object:
    """Create a mesh object with verts[0] positions; rotate 90°X so SMPL Y-up → Z-up."""
    mesh = bpy.data.meshes.new("SMPL")
    mesh.from_pydata(verts0.tolist(), [], faces.tolist())
    mesh.update()
    obj = bpy.data.objects.new("SMPL", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = (x_offset, 0.0, 1.0)
    # SMPL incam: +Y down → blender +Z up. Rotate -90°X so the standing
    # person's head ends up at +Z.
    obj.rotation_euler = (math.radians(-90.0), 0.0, 0.0)
    # Diffuse material so the mesh actually reads.
    mat = bpy.data.materials.new("smpl_mat")
    mat.diffuse_color = (0.85, 0.65, 0.55, 1.0)
    obj.data.materials.append(mat)
    return obj


def animate_smpl_mesh(obj: bpy.types.Object, verts: np.ndarray) -> None:
    """Install a frame_change_pre handler that overwrites obj's vertex
    positions per frame from the (L, V, 3) array."""
    L, V, _ = verts.shape

    def handler(scene):
        f = scene.frame_current - 1  # action keys start at 1
        if f < 0:
            f = 0
        if f >= L:
            f = L - 1
        flat = verts[f].astype(np.float32).reshape(-1)
        obj.data.vertices.foreach_set("co", flat)
        obj.data.update()

    bpy.app.handlers.frame_change_pre.append(handler)


def main() -> None:
    args = parse_args()
    w, h = (int(x) for x in args.resolution.lower().split("x"))

    bpy.ops.wm.read_factory_settings(use_empty=True)

    # --- SMPL mesh (left) ---
    data = np.load(args.smpl_npz)
    verts = data["verts"]
    faces = data["faces"]
    smpl_obj = build_smpl_mesh(verts[0], faces, x_offset=-args.separation / 2)
    animate_smpl_mesh(smpl_obj, verts)

    # --- X Bot retargeted (right) ---
    bpy.ops.import_scene.gltf(filepath=args.target_glb)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    # Pick the longest action.
    if bpy.data.actions:
        action = max(bpy.data.actions, key=lambda a: a.frame_range[1] - a.frame_range[0])
        if arm.animation_data is None:
            arm.animation_data_create()
        arm.animation_data.action = action
    arm.location = (args.separation / 2, 0.0, 0.0)

    # --- Scene framing ---
    bpy.ops.object.light_add(type="SUN", location=(2, -4, 6))
    bpy.context.object.data.energy = 4.0

    cam_data = bpy.data.cameras.new("cam")
    cam_obj = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, -6.0, 1.0)
    direction = mathutils.Vector((0, 0, 1.0)) - mathutils.Vector(cam_obj.location)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 35
    bpy.context.scene.camera = cam_obj

    scn = bpy.context.scene
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {e.identifier for e in type(scn.render).bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"
    scn.render.resolution_x = w
    scn.render.resolution_y = h
    scn.render.fps = args.fps
    L = verts.shape[0]
    scn.frame_start = 1
    scn.frame_end = L
    if scn.world is None:
        scn.world = bpy.data.worlds.new("World")
    scn.world.use_nodes = True
    scn.world.node_tree.nodes["Background"].inputs[0].default_value = (0.06, 0.06, 0.08, 1.0)
    scn.render.image_settings.file_format = "FFMPEG"
    scn.render.ffmpeg.format = "MPEG4"
    scn.render.ffmpeg.codec = "H264"
    scn.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scn.render.filepath = str(Path(args.video).expanduser())
    bpy.ops.render.render(animation=True)
    print(f"[sbs] wrote {scn.render.filepath}")


if __name__ == "__main__":
    main()
