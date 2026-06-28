"""
Convert a Mixamo FBX to a Godot-ready GLB.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \
        tools/blender/fbx_to_glb.py -- <input.fbx> <output.glb>

Why this exists:
    Mixamo FBX is authored in centimeters; Godot 4.x's native FBX importer
    sometimes ships skinned meshes at 1/100 scale (Hips bone position keys
    end up off by a factor of 100, character is ~1 cm tall). Going through
    Blender with global_scale=100 and applying transforms before glTF
    export sidesteps the whole class of unit-scale bugs.

What it does:
    1. Imports FBX with global_scale=100 (cm -> m correction).
    2. Selects everything and applies scale so the GLB ships at 1:1.
    3. Exports as GLB with skins + animations.
"""

import bpy
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
fbx_path, glb_path = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx_path, global_scale=100.0)

# Apply scale on every imported object so the exported GLB ships at 1:1.
for obj in bpy.data.objects:
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

bpy.ops.export_scene.gltf(
    filepath=glb_path,
    export_format="GLB",
    export_animations=True,
    export_skins=True,
    export_apply=False,
)
print(f"WROTE {glb_path} size={os.path.getsize(glb_path)}")
