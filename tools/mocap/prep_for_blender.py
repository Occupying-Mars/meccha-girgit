"""Convert GVHMR output + SMPL rest pose into plain .npz files for Blender.

Blender ships with its own Python and only has numpy. So we strip out
the torch/scipy/chumpy dependencies up front: run this in GVHMR's venv
to produce two small .npz files that the blender retarget script reads.

Usage:
    python tools/mocap/prep_for_blender.py \\
        --pred /tmp/mocap_runs/<name>/hmr4d_results.pt \\
        --smpl ~/Public/experiments/gvhmr/inputs/checkpoints/body_models/smpl/SMPL_NEUTRAL.pkl \\
        --out  /tmp/mocap_runs/<name>/blender_input.npz
"""
from __future__ import annotations

import argparse
import pickle
from pathlib import Path

import numpy as np


def load_smpl_rest(smpl_path: Path):
    with open(smpl_path, "rb") as f:
        d = pickle.load(f, encoding="latin1")
    kintree = d["kintree_table"]
    parents = np.array([int(p) if int(p) < 24 else -1 for p in kintree[0]], dtype=np.int32)
    v_template = np.asarray(d["v_template"])
    J_regressor = d["J_regressor"]
    if hasattr(J_regressor, "toarray"):
        J_regressor = J_regressor.toarray()
    rest_joints = (np.asarray(J_regressor) @ v_template).astype(np.float32)
    return parents, rest_joints


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--pred", required=True, help="GVHMR hmr4d_results.pt")
    p.add_argument("--smpl", required=True, help="SMPL_NEUTRAL.pkl")
    p.add_argument("--out", required=True, help="Output .npz")
    p.add_argument("--space", choices=["global", "incam"], default="global")
    p.add_argument("--zero-transl", action="store_true", help="Zero out root translation (debug)")
    p.add_argument("--zero-root-rot", action="store_true", help="Zero out global_orient (debug)")
    p.add_argument("--zero-wrists", action="store_true",
                   help="Zero L_Wrist + R_Wrist body_pose. GVHMR's wrist predictions "
                        "for full-body clips are noisy (~10°) and the bone-axis "
                        "mismatch makes them look like sideways twists. Set for clips "
                        "where hands aren't carrying meaning (walks, idles, locomotion).")
    args = p.parse_args()

    import torch
    pred = torch.load(args.pred, map_location="cpu", weights_only=False)
    key = "smpl_params_global" if args.space == "global" else "smpl_params_incam"
    smpl = pred[key]
    body_pose = smpl["body_pose"].cpu().numpy().astype(np.float32)        # (L, 63)
    global_orient = smpl["global_orient"].cpu().numpy().astype(np.float32) # (L, 3)
    transl = smpl["transl"].cpu().numpy().astype(np.float32)              # (L, 3)
    if args.zero_transl:
        transl = np.zeros_like(transl)
    if args.zero_root_rot:
        global_orient = np.zeros_like(global_orient)
    if args.zero_wrists:
        # body_pose covers SMPL joints 1..21. L_Wrist=20, R_Wrist=21 → idx 19, 20.
        bp = body_pose.reshape(-1, 21, 3)
        bp[:, 19] = 0.0
        bp[:, 20] = 0.0
        body_pose = bp.reshape(-1, 63)

    parents, rest_joints = load_smpl_rest(Path(args.smpl))

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    np.savez(
        out,
        body_pose=body_pose,
        global_orient=global_orient,
        transl=transl,
        parents=parents,
        rest_joints=rest_joints,
    )
    print(f"[prep] wrote {out}  (L={body_pose.shape[0]})")


if __name__ == "__main__":
    main()
