"""Strip floating mesh fragments from a noisy GLB (photogrammetry / AI-3D output).

Splits the main mesh into loose pieces, removes pieces below a vertex
threshold (heuristic: real body parts have >100 verts; artifacts have <50).
Optionally also removes pieces whose center is too far from the spine.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \\
        tools/blender/clean_mesh_fragments.py -- \\
        <input.glb> <output.glb> [min_verts=100] [max_dist_x=0.7]
"""
import bpy, sys, mathutils
from pathlib import Path


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    src = Path(argv[0])
    dst = Path(argv[1])
    min_verts = int(argv[2]) if len(argv) > 2 else 100
    max_dist_x = float(argv[3]) if len(argv) > 3 else 0.7

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))

    # Find largest skinned mesh (the body)
    candidates = [o for o in bpy.data.objects
                  if o.type == "MESH" and not o.name.startswith("Icosphere") and len(o.data.vertices) > 1000]
    if not candidates:
        raise SystemExit("no large mesh found to clean")
    main_mesh = max(candidates, key=lambda o: len(o.data.vertices))
    print(f"[clean] cleaning {main_mesh.name}: {len(main_mesh.data.vertices)} verts")

    # Split into loose pieces
    bpy.context.view_layer.objects.active = main_mesh
    main_mesh.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")

    pieces = [o for o in bpy.data.objects
              if o.type == "MESH" and not o.name.startswith("Icosphere")]
    print(f"[clean] split into {len(pieces)} pieces")

    keep, drop = [], []
    for o in pieces:
        if len(o.data.vertices) < min_verts:
            drop.append(o); continue
        bb_min = mathutils.Vector((1e9,1e9,1e9)); bb_max = mathutils.Vector((-1e9,-1e9,-1e9))
        for v in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(v)
            for i in range(3):
                bb_min[i] = min(bb_min[i], w[i]); bb_max[i] = max(bb_max[i], w[i])
        cx = (bb_min.x + bb_max.x) / 2
        if abs(cx) > max_dist_x:
            drop.append(o); continue
        keep.append(o)

    print(f"[clean] keeping {len(keep)} pieces, dropping {len(drop)}")
    for o in drop:
        bpy.data.objects.remove(o, do_unlink=True)

    # Re-join the keepers back into a single mesh
    if len(keep) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for o in keep:
            o.select_set(True)
        bpy.context.view_layer.objects.active = keep[0]
        bpy.ops.object.join()

    final = bpy.context.view_layer.objects.active
    final.name = "geometry_0"
    print(f"[clean] final mesh: {len(final.data.vertices)} verts, {len(final.data.polygons)} polys")

    # Re-select everything for export
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(dst),
        export_format="GLB",
        export_animations=True,
        export_skins=True,
    )
    print(f"[clean] WROTE {dst}")


if __name__ == "__main__":
    main()
