"""
Measure the actual world-space bounds of a GLB's skinned mesh + armature.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \
        tools/blender/measure_glb.py -- <input.glb>

Why this exists:
    Blender's default bound_box on a skinned mesh returns the rest-position
    bounds, which can be wildly different from what the character actually
    looks like after bones deform it. This script evaluates the depsgraph
    and reports the post-skin bounds — that's what you compare to "how big
    is the character in the test scene."

Reports:
    - per-mesh world bounds + width/height/depth
    - per-armature bone Y/Z ranges (so you can tell which axis is height)

Use to confirm a character is roughly 2 m tall before fighting with scene
transforms. If geometry comes out at 0.01 m wide, the FBX-to-GLB pipeline
forgot to apply unit scale — re-run fbx_to_glb.py.
"""

import bpy
import sys
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])

for obj in bpy.data.objects:
    if obj.type == "MESH":
        deps = bpy.context.evaluated_depsgraph_get()
        eval_obj = obj.evaluated_get(deps)
        verts = [eval_obj.matrix_world @ v.co for v in eval_obj.data.vertices]
        if not verts:
            continue
        xs = [v.x for v in verts]
        ys = [v.y for v in verts]
        zs = [v.z for v in verts]
        print(f"MESH {obj.name}")
        print(f"  world bounds: x[{min(xs):.3f}..{max(xs):.3f}] "
              f"y[{min(ys):.3f}..{max(ys):.3f}] z[{min(zs):.3f}..{max(zs):.3f}]")
        print(f"  size:  w={max(xs)-min(xs):.3f}  "
              f"h={max(ys)-min(ys):.3f}  d={max(zs)-min(zs):.3f}")

for obj in bpy.data.objects:
    if obj.type == "ARMATURE":
        arm = obj.data
        positions = [obj.matrix_world @ b.head_local for b in arm.bones]
        positions += [obj.matrix_world @ b.tail_local for b in arm.bones]
        ys = [p.y for p in positions]
        zs = [p.z for p in positions]
        print(f"ARMATURE {obj.name}")
        print(f"  bone y-range: [{min(ys):.3f}..{max(ys):.3f}] height={max(ys)-min(ys):.3f}")
        print(f"  bone z-range: [{min(zs):.3f}..{max(zs):.3f}]")
