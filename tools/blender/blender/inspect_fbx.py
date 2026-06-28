"""
Inspect an FBX (or GLB) to confirm the rig before importing.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \
        tools/blender/inspect_fbx.py -- <input.fbx-or-glb>

Reports:
    - top-level object hierarchy
    - armature bone count + how many use `mixamorig` prefix
    - mesh vert / poly counts
    - bundled animation clips (name + frame range)

Filter the output with:
    | grep -E "^(===|  |Armature)"

Use this first whenever the user drops a new character. If `mixamorig`
prefix count == bone count, animations from Mixamo will retarget
straight onto the rig with no Blender rename pass.
"""

import bpy
import sys

fbx_path = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)

if fbx_path.lower().endswith(".glb") or fbx_path.lower().endswith(".gltf"):
    bpy.ops.import_scene.gltf(filepath=fbx_path)
else:
    bpy.ops.import_scene.fbx(filepath=fbx_path)

print("=== OBJECTS ===")
for obj in bpy.data.objects:
    print(f"  {obj.type}: {obj.name}")

print("=== ARMATURES ===")
for arm in bpy.data.armatures:
    bones = arm.bones
    mixamo_count = sum(1 for b in bones if b.name.startswith("mixamorig"))
    print(f"Armature: {arm.name}  bone_count={len(bones)}  mixamo_prefixed={mixamo_count}")
    for b in list(bones)[:10]:
        print(f"    {b.name}")

print("=== MESHES ===")
for m in bpy.data.meshes:
    print(f"  {m.name}  verts={len(m.vertices)}  polys={len(m.polygons)}")

print("=== ACTIONS ===")
for a in bpy.data.actions:
    print(f"  {a.name}  frames={int(a.frame_range[0])}-{int(a.frame_range[1])}")
