"""Strip target character's armature, parent its mesh to X Bot's armature.

Because both rigs use mixamorig:* vertex group names, the mesh's existing
weights re-bind onto X Bot's skeleton automatically. Result: target's
mesh skinned to a known-good T-pose rest, any X Bot animation plays
without per-character retarget math.

    blender --background --python tools/mocap/reskin_to_xbot.py -- \\
        --target assets/models/characters/main_blend.glb \\
        --xbot   assets/models/characters/x_bot.glb \\
        --out    assets/models/characters/main_xbotrig.glb
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--target", required=True, help="character GLB to re-skin")
    p.add_argument("--xbot",   required=True, help="X Bot GLB providing the skeleton")
    p.add_argument("--out",    required=True, help="output GLB (target mesh + X Bot skeleton)")
    return p.parse_args(argv)


def main() -> None:
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # Import target — keep meshes only
    bpy.ops.import_scene.gltf(filepath=args.target)
    target_meshes = [o for o in bpy.data.objects
                     if o.type == "MESH" and not o.name.startswith("Icosphere")]
    target_armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    print(f"[reskin] target: {len(target_meshes)} meshes, {len(target_armatures)} armatures")

    # Drop target's armature modifier references (don't delete the armature yet —
    # mesh vertex groups remain even after we remove the armature)
    for m in target_meshes:
        m.modifiers.clear()
        m.parent = None

    # Delete target's armature
    for a in target_armatures:
        bpy.data.objects.remove(a, do_unlink=True)

    # Import X Bot
    bpy.ops.import_scene.gltf(filepath=args.xbot)
    xbot_armature = next(o for o in bpy.data.objects
                         if o.type == "ARMATURE" and o not in target_armatures)
    # Drop X Bot's own meshes (we only want its skeleton)
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o not in target_meshes and not o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o, do_unlink=True)
        elif o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o, do_unlink=True)

    # Parent each target mesh to X Bot's armature with an armature modifier.
    # Vertex groups (named mixamorig:*) carry over from the original skinning.
    for m in target_meshes:
        m.parent = xbot_armature
        m.matrix_parent_inverse = xbot_armature.matrix_world.inverted()
        mod = m.modifiers.new(name="Armature", type="ARMATURE")
        mod.object = xbot_armature
        mod.use_vertex_groups = True

    # Drop the source action — we want a clean GLB that gets animations transferred later
    if xbot_armature.animation_data is not None:
        xbot_armature.animation_data_clear()
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)

    out_path = Path(args.out).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        export_animations=True,
        export_skins=True,
    )
    print(f"[reskin] WROTE {out_path}")


if __name__ == "__main__":
    main()
