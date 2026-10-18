"""
Headless Blender Stage 3 processor for Roblox 3D assets.
Executed via:
  blender --background --python blender_process.py -- --input raw.glb --output-blend clean.blend ...

Performs:
  1. Imports .glb / .obj / .fbx mesh
  2. Joins multi-part static geometry into a single clean mesh (or preserves material slots)
  3. Removes duplicate vertices, deletes loose geometry, recalculates outward normals
  4. Decimates (repeating if needed) to --target-tris, below Roblox's 10,000-triangle limit
  5. Scales mesh to --height-studs (1 Blender meter = 1 Roblox stud) and places bottom-center pivot at (0,0,0)
  6. Saves editable .blend source and exports Roblox-ready .fbx + manifest.json
"""

import argparse
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-blend", required=True)
    parser.add_argument("--output-fbx", required=True)
    parser.add_argument("--target-tris", type=int, default=6000)
    parser.add_argument("--height-studs", type=float, default=5.0)
    parser.add_argument("--manifest", required=True)
    return parser.parse_args(argv)


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_mesh(filepath: Path) -> None:
    ext = filepath.suffix.lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(filepath))
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=str(filepath))
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(filepath))
    else:
        raise ValueError(f"Unsupported mesh extension: {ext}")


def count_triangles(obj: bpy.types.Object) -> int:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(depsgraph)
    mesh = eval_obj.to_mesh()
    mesh.calc_loop_triangles()
    tris = len(mesh.loop_triangles)
    eval_obj.to_mesh_clear()
    return tris


def dec_ratio_str(ratio: float) -> str:
    return f"{ratio:.6f}"


def main() -> None:
    args = parse_args()
    inp = Path(args.input)

    clear_scene()
    import_mesh(inp)

    mesh_objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not mesh_objs:
        raise RuntimeError(f"No mesh objects found in {inp}")

    bpy.ops.object.select_all(action="DESELECT")
    for o in mesh_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objs[0]

    if len(mesh_objs) > 1:
        bpy.ops.object.join()

    obj = bpy.context.view_layer.objects.active
    obj.name = "RobloxAsset"

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Clean topology and normals
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.mesh.delete_loose()
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    initial_tris = count_triangles(obj)
    target_tris = min(max(args.target_tris, 200), 9900)

    # Triangulate for deterministic Roblox triangle budget
    tri_mod = obj.modifiers.new(name="RobloxTriangulate", type="TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=tri_mod.name)

    # Collapse decimation rarely lands exactly on the ratio (and AI meshes can need ratios
    # far below 1%), so repeat with a small safety margin until the budget is met.
    final_tris = count_triangles(obj)
    passes = 0
    while final_tris > target_tris and passes < 4:
        ratio = (float(target_tris) / float(final_tris)) * (1.0 if passes == 0 else 0.97)
        dec = obj.modifiers.new(name="RobloxDecimate", type="DECIMATE")
        dec.ratio = max(1e-5, min(ratio, 1.0))
        bpy.ops.object.modifier_apply(modifier=dec.name)
        tri_mod = obj.modifiers.new(name="RobloxTriangulate", type="TRIANGULATE")
        bpy.ops.object.modifier_apply(modifier=tri_mod.name)
        final_tris = count_triangles(obj)
        passes += 1
        print(f"[blender_process] decimate pass {passes}: ratio={dec_ratio_str(ratio)} -> {final_tris} tris")

    # Compute world-space bounding box and normalize height to target studs
    bbox_corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    min_x = min(v.x for v in bbox_corners)
    max_x = max(v.x for v in bbox_corners)
    min_y = min(v.y for v in bbox_corners)
    max_y = max(v.y for v in bbox_corners)
    min_z = min(v.z for v in bbox_corners)
    max_z = max(v.z for v in bbox_corners)

    current_height = max(max_z - min_z, 1e-4)
    scale_factor = args.height_studs / current_height

    # Shift geometry so bottom-center is at (0, 0, 0)
    center_x = (min_x + max_x) * 0.5
    center_y = (min_y + max_y) * 0.5
    for vert in obj.data.vertices:
        vert.co.x = (vert.co.x - center_x) * scale_factor
        vert.co.y = (vert.co.y - center_y) * scale_factor
        vert.co.z = (vert.co.z - min_z) * scale_factor

    obj.location = (0.0, 0.0, 0.0)
    bpy.ops.object.shade_smooth()

    out_blend = Path(args.output_blend)
    out_blend.parent.mkdir(parents=True, exist_ok=True)
    # No .blend1 backups next to project deliverables.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(out_blend))

    out_fbx = Path(args.output_fbx)
    bpy.ops.export_scene.fbx(
        filepath=str(out_fbx),
        use_selection=False,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Y",
        axis_up="Z",
        path_mode="COPY",
        embed_textures=True,
        add_leaf_bones=False,
    )

    bbox_after = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    size_studs = [
        round(max(v.x for v in bbox_after) - min(v.x for v in bbox_after), 3),
        round(max(v.z for v in bbox_after) - min(v.z for v in bbox_after), 3),
        round(max(v.y for v in bbox_after) - min(v.y for v in bbox_after), 3),
    ]

    manifest_file = Path(args.manifest)
    manifest = {
        "input": str(inp),
        "clean_blend": str(out_blend),
        "static_fbx": str(out_fbx),
        "initial_triangles": initial_tris,
        "final_triangles": final_tris,
        "target_triangles": target_tris,
        "decimate_passes": passes,
        "within_budget": final_tris <= target_tris,
        "roblox_limit_ok": final_tris <= 10000,
        "size_studs_xyz": size_studs,
    }
    manifest_file.write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
