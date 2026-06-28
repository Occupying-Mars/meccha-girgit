"""Import a Mixamo FBX character and normalize its height to a target.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \\
        tools/blender/import_mixamo_character.py -- <input.fbx> <output.glb> [height_m]

Height defaults to 1.83m (6ft) — the protagonist baseline for thegame.
See project_character_scale memory for why.

What it does:
    1. import_scene.fbx(global_scale=100)  — standard Mixamo cm→m
    2. apply scale on everything so the GLB ships at 1:1
    3. measure character height via armature Z-span (NOT mesh bound_box —
       FBX→GLB swaps axes and the bbox max isn't always height)
    4. rescale to match `height_m` if requested
    5. export GLB with skins + animations

Used by `tools/mocap/` to ensure new gameplay characters land at 6ft
regardless of source FBX scale conventions.
"""
import bpy
import sys
from pathlib import Path

import mathutils


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    fbx_path = Path(argv[0])
    glb_path = Path(argv[1])
    target_height = float(argv[2]) if len(argv) > 2 else 1.83

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(fbx_path), global_scale=100.0)

    # Apply scale so the GLB ships at 1:1.
    for obj in bpy.data.objects:
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Measure via armature Z-span (the only reliable axis after FBX import).
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        raise SystemExit("no armature in FBX")
    zs = []
    for bone in arm.data.bones:
        head = arm.matrix_world @ bone.head_local
        tail = arm.matrix_world @ bone.tail_local
        zs.extend([head.z, tail.z])
    current_height = max(zs) - min(zs)
    factor = target_height / current_height
    print(f"[import_mixamo_character] current={current_height:.3f}m "
          f"target={target_height:.3f}m factor={factor:.3f}")

    if abs(factor - 1.0) > 0.01:
        for obj in bpy.data.objects:
            obj.scale = (obj.scale.x * factor, obj.scale.y * factor, obj.scale.z * factor)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        export_animations=True,
        export_skins=True,
    )
    print(f"[import_mixamo_character] WROTE {glb_path}")


if __name__ == "__main__":
    main()
