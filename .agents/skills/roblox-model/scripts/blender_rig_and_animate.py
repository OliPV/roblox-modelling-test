"""
Headless Blender Stage 4 & 5 rigging and animation script for Roblox.
Executed via:
  blender --background 03_clean.blend --python blender_rig_and_animate.py -- --rig-type humanoid ...

Supports:
  --rig-type prop       : Root + Body bone for floating/hinged props
  --rig-type humanoid   : Roblox-friendly 15-bone biped skeleton fitted to mesh bounds
  --rig-type quadruped  : Spine, Neck, Head, Tail + 4 3-segment legs fitted to mesh bounds
  --animate idle,walk   : Generates loopable Action clips in the NLA track for FBX export
"""

import argparse
import json
import math
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
    parser.add_argument("--rig-type", choices=["prop", "humanoid", "quadruped"], required=True)
    parser.add_argument("--animate", default="idle,walk")
    parser.add_argument("--output-blend", required=True)
    parser.add_argument("--output-fbx", required=True)
    parser.add_argument("--manifest", required=True)
    return parser.parse_args(argv)


def add_bone(edit_bones, name: str, head: tuple[float, float, float], tail: tuple[float, float, float], parent=None):
    b = edit_bones.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    if parent is not None:
        b.parent = parent
    return b


def build_prop_rig(edit_bones, h: float):
    root = add_bone(edit_bones, "Root", (0, 0, 0), (0, 0, max(0.2 * h, 0.25)))
    add_bone(edit_bones, "Body", (0, 0, 0.2 * h), (0, 0, 0.9 * h), parent=root)


def build_humanoid_rig(edit_bones, w: float, h: float):
    pelvis_z = 0.48 * h
    waist_z = 0.58 * h
    chest_z = 0.76 * h
    neck_z = 0.83 * h
    head_z = 0.98 * h
    shoulder_x = max(0.22 * w, 0.15 * h)
    hip_x = max(0.10 * w, 0.08 * h)

    root = add_bone(edit_bones, "HumanoidRootPart", (0, 0, pelvis_z * 0.9), (0, 0, pelvis_z))
    lower_torso = add_bone(edit_bones, "LowerTorso", (0, 0, pelvis_z), (0, 0, waist_z), parent=root)
    upper_torso = add_bone(edit_bones, "UpperTorso", (0, 0, waist_z), (0, 0, chest_z), parent=lower_torso)
    neck = add_bone(edit_bones, "Neck", (0, 0, chest_z), (0, 0, neck_z), parent=upper_torso)
    add_bone(edit_bones, "Head", (0, 0, neck_z), (0, 0, head_z), parent=neck)

    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        sx = sign * shoulder_x
        elbow_x = sign * (shoulder_x + 0.14 * h)
        wrist_x = sign * (shoulder_x + 0.28 * h)
        hand_x = sign * (shoulder_x + 0.34 * h)
        u_arm = add_bone(edit_bones, f"{side}UpperArm", (sx * 0.6, 0, chest_z * 0.96), (elbow_x, 0, chest_z * 0.94), parent=upper_torso)
        l_arm = add_bone(edit_bones, f"{side}LowerArm", (elbow_x, 0, chest_z * 0.94), (wrist_x, 0, chest_z * 0.92), parent=u_arm)
        add_bone(edit_bones, f"{side}Hand", (wrist_x, 0, chest_z * 0.92), (hand_x, 0, chest_z * 0.91), parent=l_arm)

        hx = sign * hip_x
        knee_z = 0.25 * h
        ankle_z = 0.05 * h
        u_leg = add_bone(edit_bones, f"{side}UpperLeg", (hx, 0, pelvis_z), (hx, 0, knee_z), parent=lower_torso)
        l_leg = add_bone(edit_bones, f"{side}LowerLeg", (hx, 0, knee_z), (hx, 0, ankle_z), parent=u_leg)
        add_bone(edit_bones, f"{side}Foot", (hx, 0, ankle_z), (hx, -0.08 * h, 0.01 * h), parent=l_leg)


def build_quadruped_rig(edit_bones, w: float, d: float, h: float):
    body_z = 0.58 * h
    front_y = -0.30 * d
    back_y = 0.30 * d
    leg_x = max(0.22 * w, 0.10 * h)

    root = add_bone(edit_bones, "Root", (0, 0, body_z * 0.85), (0, 0, body_z))
    torso = add_bone(edit_bones, "Torso", (0, back_y, body_z), (0, front_y, body_z), parent=root)
    neck = add_bone(edit_bones, "Neck", (0, front_y, body_z), (0, front_y - 0.14 * d, 0.80 * h), parent=torso)
    add_bone(edit_bones, "Head", (0, front_y - 0.14 * d, 0.80 * h), (0, front_y - 0.26 * d, 0.78 * h), parent=neck)
    add_bone(edit_bones, "Tail", (0, back_y, body_z), (0, back_y + 0.22 * d, 0.42 * h), parent=torso)

    for fb, y_pos in (("F", front_y * 0.9), ("B", back_y * 0.9)):
        for lr, sign in (("L", 1.0), ("R", -1.0)):
            lx = sign * leg_x
            mid_z = 0.30 * h
            low_z = 0.06 * h
            top = add_bone(edit_bones, f"{fb}_UpperLeg_{lr}", (lx, y_pos, body_z), (lx, y_pos, mid_z), parent=torso)
            mid = add_bone(edit_bones, f"{fb}_LowerLeg_{lr}", (lx, y_pos, mid_z), (lx, y_pos, low_z), parent=top)
            add_bone(edit_bones, f"{fb}_Hoof_{lr}", (lx, y_pos, low_z), (lx, y_pos - 0.04 * d, 0.0), parent=mid)


def bake_procedural_actions(arm_obj: bpy.types.Object, rig_type: str, requested: list[str]) -> list[str]:
    created: list[str] = []
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")

    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "XYZ"

    if "idle" in requested:
        act = bpy.data.actions.new(name="Idle")
        arm_obj.animation_data.action = act
        target_name = "UpperTorso" if rig_type == "humanoid" else ("Torso" if rig_type == "quadruped" else "Body")
        pb = arm_obj.pose.bones.get(target_name) or arm_obj.pose.bones[0]
        for frame, z_off, pitch in ((1, 0.0, 0.0), (20, 0.04, 0.03), (40, 0.0, 0.0)):
            pb.location = (0.0, 0.0, z_off)
            pb.rotation_euler = (pitch, 0.0, 0.0)
            pb.keyframe_insert(data_path="location", frame=frame)
            pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        track = arm_obj.animation_data.nla_tracks.new()
        track.name = "Idle"
        track.strips.new("Idle", 1, act)
        created.append("Idle")

    if "walk" in requested and rig_type in ("humanoid", "quadruped"):
        act = bpy.data.actions.new(name="Walk")
        arm_obj.animation_data.action = act
        if rig_type == "humanoid":
            swing_pairs = [
                ("LeftUpperLeg", 1.0),
                ("RightUpperLeg", -1.0),
                ("LeftUpperArm", -0.6),
                ("RightUpperArm", 0.6),
            ]
        else:
            swing_pairs = [
                ("F_UpperLeg_L", 1.0),
                ("B_UpperLeg_R", 1.0),
                ("F_UpperLeg_R", -1.0),
                ("B_UpperLeg_L", -1.0),
            ]

        for bone_name, mult in swing_pairs:
            pb = arm_obj.pose.bones.get(bone_name)
            if not pb:
                continue
            for frame, angle in ((1, 0.35 * mult), (15, -0.35 * mult), (30, 0.35 * mult)):
                pb.rotation_euler = (angle, 0.0, 0.0)
                pb.keyframe_insert(data_path="rotation_euler", frame=frame)

        track = arm_obj.animation_data.nla_tracks.new()
        track.name = "Walk"
        track.strips.new("Walk", 1, act)
        created.append("Walk")

    bpy.ops.object.mode_set(mode="OBJECT")
    return created


def main() -> None:
    args = parse_args()
    mesh_obj = bpy.data.objects.get("RobloxAsset")
    if mesh_obj is None:
        meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        if not meshes:
            raise RuntimeError("No mesh object found in scene for rigging.")
        mesh_obj = meshes[0]

    bbox = [mesh_obj.matrix_world @ Vector(c) for c in mesh_obj.bound_box]
    w = max(max(v.x for v in bbox) - min(v.x for v in bbox), 0.2)
    d = max(max(v.y for v in bbox) - min(v.y for v in bbox), 0.2)
    h = max(max(v.z for v in bbox) - min(v.z for v in bbox), 0.2)

    arm_data = bpy.data.armatures.new("RobloxRig")
    arm_obj = bpy.data.objects.new("RobloxRig", arm_data)
    bpy.context.collection.objects.link(arm_obj)

    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    if args.rig_type == "prop":
        build_prop_rig(arm_data.edit_bones, h)
    elif args.rig_type == "humanoid":
        build_humanoid_rig(arm_data.edit_bones, w, h)
    elif args.rig_type == "quadruped":
        build_quadruped_rig(arm_data.edit_bones, w, d, h)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Parent mesh to armature with automatic heat weights (fallback to envelope weights if heat fails on non-manifold parts)
    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    if not mesh_obj.vertex_groups:
        bpy.ops.object.parent_set(type="ARMATURE_ENVELOPE")

    requested_anims = [a.strip().lower() for a in args.animate.split(",") if a.strip()]
    baked_anims = bake_procedural_actions(arm_obj, args.rig_type, requested_anims)

    out_blend = Path(args.output_blend)
    bpy.ops.wm.save_as_mainfile(filepath=str(out_blend))

    out_fbx = Path(args.output_fbx)
    bpy.ops.export_scene.fbx(
        filepath=str(out_fbx),
        use_selection=False,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Y",
        axis_up="Z",
        add_leaf_bones=False,
        bake_anim=True,
        bake_anim_use_nla_strips=True,
        bake_anim_use_all_actions=True,
        path_mode="COPY",
        embed_textures=True,
    )

    manifest_path = Path(args.manifest)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else {}
    manifest.update(
        {
            "rig_type": args.rig_type,
            "bone_count": len(arm_data.bones),
            "baked_animations": baked_anims,
            "rigged_blend": str(out_blend),
            "rigged_fbx": str(out_fbx),
        }
    )
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
