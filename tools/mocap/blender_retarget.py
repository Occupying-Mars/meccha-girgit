"""Retarget GVHMR SMPL output onto our mixamo-rigged protagonist.

Pre-step (run in GVHMR's venv, which has torch + scipy + chumpy):
    python tools/mocap/prep_for_blender.py \\
        --pred <gvhmr_out>/hmr4d_results.pt \\
        --smpl <gvhmr>/inputs/checkpoints/body_models/smpl/SMPL_NEUTRAL.pkl \\
        --out  <gvhmr_out>/blender_input.npz

Then run via:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \\
        tools/mocap/blender_retarget.py -- \\
        --npz  <gvhmr_out>/blender_input.npz \\
        --rig  assets/models/characters/protagonist.glb \\
        --out  assets/animations/<name>.glb \\
        --fps 30

Approach
--------
1. Load SMPL_NEUTRAL.pkl: extract `kintree_table` (parent index per joint)
   and the rest joint positions (T-pose, world space).
2. Load GVHMR's pred dict (a torch pickle). Pull `smpl_params_global`:
     - global_orient: (L, 3) axis-angle
     - body_pose:     (L, 63) axis-angle (21 joints × 3)
     - transl:        (L, 3)  root translation
3. Build a temporary SMPL armature in blender (24 head bones, parent chain
   from kintree_table). Set keyframes from the axis-angle stream.
4. Load the protagonist GLB rig. Add per-bone Copy Rotation constraints
   from the SMPL armature, with rest-pose alignment baked in.
5. Bake the constraint chain into a clean action on the mixamo rig.
6. Strip constraints + temp armature, export action-only GLB.

We do the heavy lifting via blender's pose-mode constraints rather than
manual matrix math, because blender handles the rest-pose-aware coord
conversion correctly and consistently — that's the part that bites every
home-grown SMPL→mixamo script.
"""
from __future__ import annotations

import argparse
import math
import pickle
import sys
from pathlib import Path

import bpy
import mathutils


# SMPL joint index → mixamo bone name. Bones not listed stay at rest.
# SMPL has 24 joints (0..23). Indices 22/23 are hands (and are jaw/eyes in
# SMPLX, which GVHMR uses internally but exposes SMPL-compatible params).
SMPL_TO_MIXAMO = {
    0:  "mixamorig:Hips",
    1:  "mixamorig:LeftUpLeg",
    2:  "mixamorig:RightUpLeg",
    3:  "mixamorig:Spine",
    4:  "mixamorig:LeftLeg",
    5:  "mixamorig:RightLeg",
    6:  "mixamorig:Spine1",
    7:  "mixamorig:LeftFoot",
    8:  "mixamorig:RightFoot",
    9:  "mixamorig:Spine2",
    10: "mixamorig:LeftToeBase",
    11: "mixamorig:RightToeBase",
    12: "mixamorig:Neck",
    13: "mixamorig:LeftShoulder",
    14: "mixamorig:RightShoulder",
    15: "mixamorig:Head",
    16: "mixamorig:LeftArm",
    17: "mixamorig:RightArm",
    18: "mixamorig:LeftForeArm",
    19: "mixamorig:RightForeArm",
    20: "mixamorig:LeftHand",
    21: "mixamorig:RightHand",
}

SMPL_JOINT_NAMES = [
    "Pelvis", "L_Hip", "R_Hip", "Spine1", "L_Knee", "R_Knee",
    "Spine2", "L_Ankle", "R_Ankle", "Spine3", "L_Foot", "R_Foot",
    "Neck", "L_Collar", "R_Collar", "Head", "L_Shoulder", "R_Shoulder",
    "L_Elbow", "R_Elbow", "L_Wrist", "R_Wrist", "L_Hand", "R_Hand",
]


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    p = argparse.ArgumentParser()
    p.add_argument("--npz", required=True, help="prep_for_blender.py output (.npz)")
    p.add_argument("--rig", required=True, help="Mixamo rig GLB (protagonist.glb)")
    p.add_argument("--out", required=True, help="Output GLB path")
    p.add_argument("--fps", type=int, default=30)
    return p.parse_args(argv)


def load_blender_input(npz_path: Path) -> tuple[list[int], "numpy.ndarray", dict]:
    """Read prep_for_blender output: parents, rest_joints, and the per-frame params."""
    import numpy as np
    data = np.load(npz_path)
    parents = [int(p) for p in data["parents"]]
    rest_joints = data["rest_joints"]
    smpl_params = {
        "body_pose":     data["body_pose"],
        "global_orient": data["global_orient"],
        "transl":        data["transl"],
    }
    return parents, rest_joints, smpl_params


def axis_angle_to_quat(aa) -> mathutils.Quaternion:
    """3-vector axis-angle → blender Quaternion (w, x, y, z)."""
    angle = math.sqrt(float(aa[0])**2 + float(aa[1])**2 + float(aa[2])**2)
    if angle < 1e-8:
        return mathutils.Quaternion((1.0, 0.0, 0.0, 0.0))
    axis = mathutils.Vector((float(aa[0]) / angle, float(aa[1]) / angle, float(aa[2]) / angle))
    return mathutils.Quaternion(axis, angle)


def build_smpl_armature(parents: list[int], rest_joints) -> bpy.types.Object:
    """Create a 24-bone armature laid out at the SMPL rest pose.

    SMPL stores its rest pose in a Y-up coordinate system. Blender (and our
    mixamo target) are Z-up. We rotate the whole armature object 90° around X
    so the source's "up" aligns with the target's "up" — Copy Rotation in
    POSE space then transfers cleanly between matching axes.
    """
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm_obj = bpy.context.object
    arm_obj.name = "SMPL_src"
    # SMPL rest pose is Y-up; Blender + our mixamo target are Z-up. We rotate
    # the source armature object so its rest "up" matches Blender's up. Done
    # *before* entering edit mode and adding bones, so child bones inherit the
    # transform when matrix_world is applied during pose evaluation.
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    bpy.ops.object.mode_set(mode="EDIT")
    arm_data = arm_obj.data
    # Remove the default "Bone"
    arm_data.edit_bones.remove(arm_data.edit_bones[0])

    bones: list[bpy.types.EditBone] = []
    for i in range(24):
        eb = arm_data.edit_bones.new(SMPL_JOINT_NAMES[i])
        head = mathutils.Vector(rest_joints[i])
        # tail is offset toward the average child; if leaf, use small +Y
        eb.head = head
        eb.tail = head + mathutils.Vector((0.0, 0.05, 0.0))
        bones.append(eb)
    # Parent + position tails using first child's head
    children_of: dict[int, list[int]] = {i: [] for i in range(24)}
    for i in range(24):
        if parents[i] >= 0:
            children_of[parents[i]].append(i)
    for i, eb in enumerate(bones):
        if parents[i] >= 0:
            eb.parent = bones[parents[i]]
            eb.use_connect = False
        kids = children_of[i]
        if kids:
            avg = mathutils.Vector((0.0, 0.0, 0.0))
            for k in kids:
                avg += mathutils.Vector(rest_joints[k])
            avg /= len(kids)
            eb.tail = avg
            if (eb.tail - eb.head).length < 1e-4:
                eb.tail = eb.head + mathutils.Vector((0.0, 0.05, 0.0))

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def key_smpl_action(arm_obj: bpy.types.Object, smpl_params: dict, fps: int) -> None:
    """Drive the SMPL armature from per-frame axis-angle params."""
    L = smpl_params["body_pose"].shape[0]
    body_pose = smpl_params["body_pose"].reshape(L, 21, 3)
    glob_orient = smpl_params["global_orient"].reshape(L, 3)
    transl = smpl_params["transl"].reshape(L, 3)

    bpy.context.scene.render.fps = fps
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = L
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")

    pb = arm_obj.pose.bones

    for f in range(L):
        bpy.context.scene.frame_set(f + 1)
        # Root rotation + translation (joint 0 = pelvis)
        pb[SMPL_JOINT_NAMES[0]].rotation_mode = "QUATERNION"
        pb[SMPL_JOINT_NAMES[0]].rotation_quaternion = axis_angle_to_quat(glob_orient[f])
        pb[SMPL_JOINT_NAMES[0]].location = mathutils.Vector(transl[f])
        pb[SMPL_JOINT_NAMES[0]].keyframe_insert("rotation_quaternion", frame=f + 1)
        pb[SMPL_JOINT_NAMES[0]].keyframe_insert("location", frame=f + 1)
        # 21 body joints, SMPL indices 1..21
        for j in range(21):
            name = SMPL_JOINT_NAMES[j + 1]
            pb[name].rotation_mode = "QUATERNION"
            pb[name].rotation_quaternion = axis_angle_to_quat(body_pose[f, j])
            pb[name].keyframe_insert("rotation_quaternion", frame=f + 1)

    bpy.ops.object.mode_set(mode="OBJECT")


def load_target_rig(glb_path: Path) -> bpy.types.Object:
    """Import protagonist GLB; return its armature object."""
    bpy.ops.import_scene.gltf(filepath=str(glb_path))
    for obj in bpy.context.selected_objects:
        if obj.type == "ARMATURE":
            return obj
    raise RuntimeError("No armature in target GLB")


def direct_retarget(tgt: bpy.types.Object, smpl_params: dict, parents: list[int], rest_joints, fps: int) -> None:
    """FK retarget: compute SMPL joint world rotations, transfer to mixamo
    bones with proper rest-pose alignment (no Copy Rotation constraints).

    Math, per joint i with parent p:
      smpl_world[i]  = smpl_world[p] @ aa_to_quat(body_pose[i] | global_orient)
      target_world[i] = R_correction @ smpl_world[i]
      target_local[i] = target_bone_rest_relative_to_parent^-1
                        @ target_world[parent_mapped]^-1
                        @ target_world[i]
    `R_correction` maps SMPL's Y-up world into Blender's Z-up world.
    """
    L = smpl_params["body_pose"].shape[0]
    body_pose = smpl_params["body_pose"].reshape(L, 21, 3)
    glob_orient = smpl_params["global_orient"].reshape(L, 3)
    transl = smpl_params["transl"].reshape(L, 3)

    bpy.context.scene.render.fps = fps
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = L

    # SMPL Y-up (incam: +Y down, world: +Y up) → Blender Z-up.
    # For incam SMPL the standard CV convention has +Y down — a standing
    # person has head at -Y_cam. Rotating +180° X then +90° X (=270°) is
    # equivalent to -90° X but in practice we want +90° X to also flip the
    # "down→up" — so try +90° X first; tweak if upside-down persists.
    R_correction = mathutils.Quaternion((1.0, 0.0, 0.0), math.radians(90.0))
    R_correction_mat = R_correction.to_matrix()

    # Per-bone rest offset O[i] = (mixamo bone rest world)^-1 @ (smpl bone rest world).
    # The SMPL armature is built with the +90°X rotation so its bones live in
    # blender world frame already.
    bpy.context.view_layer.objects.active = tgt
    bpy.ops.object.mode_set(mode="OBJECT")
    src_hidden = build_smpl_armature(parents, rest_joints)
    src_hidden.hide_viewport = True
    src_hidden.hide_render = True

    bpy.context.view_layer.objects.active = tgt
    bpy.ops.object.mode_set(mode="POSE")

    bone_offset: dict[int, mathutils.Quaternion] = {}
    tgt_world_rot = tgt.matrix_world.to_3x3()
    src_world_rot = src_hidden.matrix_world.to_3x3()
    for smpl_idx, mix_name in SMPL_TO_MIXAMO.items():
        if mix_name not in tgt.pose.bones:
            continue
        mix_rest = tgt_world_rot @ tgt.data.bones[mix_name].matrix_local.to_3x3()
        smpl_rest = src_world_rot @ src_hidden.data.bones[SMPL_JOINT_NAMES[smpl_idx]].matrix_local.to_3x3()
        # Normalize to ensure unit quaternion (rest matrices may carry scale).
        mix_rest_q = mix_rest.to_quaternion().normalized()
        smpl_rest_q = smpl_rest.to_quaternion().normalized()
        bone_offset[smpl_idx] = mix_rest_q.inverted() @ smpl_rest_q

    for f in range(L):
        # FK retarget. Two-step:
        # 1. Compute each SMPL joint's world rotation in SMPL frame via FK.
        # 2. For each mapped bone, target_world_in_armature = δ_blender · rest_world,
        #    where δ_blender = R_corr · smpl_world · R_corrᵀ. At rest (δ=I) this
        #    reduces to the bone's own rest world matrix, so identity-pose
        #    leaves the rig in T-pose.
        # 3. Set pose_bone.matrix to that target and let blender derive the
        #    matrix_basis from parent's pose + rest. Process bones in
        #    topological order and update view_layer between bones so each
        #    child reads its parent's *current* pose matrix.
        cam_undo = mathutils.Quaternion((1.0, 0.0, 0.0), math.radians(180.0))
        smpl_world_q: dict[int, mathutils.Quaternion] = {}
        for i in range(24):
            if i == 0:
                local_q = cam_undo @ axis_angle_to_quat(glob_orient[f])
            elif i <= 21:
                local_q = axis_angle_to_quat(body_pose[f, i - 1])
            else:
                local_q = mathutils.Quaternion()
            if parents[i] < 0:
                smpl_world_q[i] = local_q
            else:
                smpl_world_q[i] = smpl_world_q[parents[i]] @ local_q

        R_corr_mat = R_correction.to_matrix()
        R_corr_mat_T = R_corr_mat.transposed()
        # The target armature object may have its own world rotation (GLB import
        # often bakes Rx(-90°) onto the armature). pose_bone.matrix is in
        # *armature space*, so target world → armature: M_arm = arm_world^-1 · M_world.
        arm_world_inv_3x3 = tgt.matrix_world.inverted().to_3x3()
        arm_world_3x3 = tgt.matrix_world.to_3x3()

        ordered = sorted(SMPL_TO_MIXAMO.keys())
        for smpl_idx in ordered:
            mix_name = SMPL_TO_MIXAMO[smpl_idx]
            if mix_name not in tgt.pose.bones:
                continue
            pb = tgt.pose.bones[mix_name]

            # δ in blender world frame.
            delta_world_3x3 = R_corr_mat @ smpl_world_q[smpl_idx].to_matrix() @ R_corr_mat_T
            # Rest matrix (already in armature space).
            rest_arm_3x3 = tgt.data.bones[mix_name].matrix_local.to_3x3()
            # Target rotation in *world* frame = δ · arm_world · rest_arm.
            target_world_3x3 = delta_world_3x3 @ arm_world_3x3 @ rest_arm_3x3
            # Express target rotation in armature space.
            target_arm_3x3 = arm_world_inv_3x3 @ target_world_3x3

            bpy.context.view_layer.update()
            head_pos = pb.head.copy()
            mat = target_arm_3x3.to_4x4()
            mat.translation = head_pos

            pb.rotation_mode = "QUATERNION"
            pb.matrix = mat
            pb.keyframe_insert("rotation_quaternion", frame=f + 1)

            if smpl_idx == 0:
                t_blender = R_correction_mat @ mathutils.Vector(transl[f])
                pb.location = t_blender
                pb.keyframe_insert("location", frame=f + 1)

    bpy.ops.object.mode_set(mode="OBJECT")


def cleanup_helpers() -> None:
    # Remove orphan icospheres (debug helpers in protagonist scene)
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and obj.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj, do_unlink=True)


def export_glb(out_path: Path) -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        export_animations=True,
        export_bake_animation=False,
        export_force_sampling=True,
        export_nla_strips=False,
    )


def main() -> None:
    args = parse_args()
    npz_path = Path(args.npz).expanduser()
    rig_path = Path(args.rig).expanduser()
    out_path = Path(args.out).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # Wipe default scene.
    bpy.ops.wm.read_factory_settings(use_empty=True)

    parents, rest_joints, smpl_params = load_blender_input(npz_path)
    L = smpl_params["body_pose"].shape[0]
    print(f"[retarget] {L} frames at {args.fps} fps")

    tgt = load_target_rig(rig_path)
    direct_retarget(tgt, smpl_params, parents, rest_joints, args.fps)

    # Remove the hidden SMPL helper armature before export.
    for obj in list(bpy.data.objects):
        if obj.type == "ARMATURE" and obj.name.startswith("SMPL_src"):
            bpy.data.objects.remove(obj, do_unlink=True)

    # Drop any actions other than the one we just baked, then export.
    new_action = tgt.animation_data.action if tgt.animation_data else None
    for act in list(bpy.data.actions):
        if act is not new_action:
            bpy.data.actions.remove(act)
    cleanup_helpers()
    export_glb(out_path)
    print(f"[retarget] wrote {out_path}")


if __name__ == "__main__":
    main()
