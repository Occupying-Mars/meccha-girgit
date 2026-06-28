"""Compute per-frame SMPL body mesh vertices from GVHMR's prediction.

Run in GVHMR's venv (has smplx + torch). Outputs a .npz with:
    verts:  (L, 6890, 3) float32  — body vertex positions per frame
    faces:  (F, 3) int32           — triangle indices (constant)
    fps:    int

Usage:
    python tools/mocap/export_smpl_mesh.py \\
        --pred /tmp/mocap_runs/<name>/hmr4d_results.pt \\
        --smpl ~/Public/experiments/gvhmr/inputs/checkpoints/body_models/smpl/SMPL_NEUTRAL.pkl \\
        --out  /tmp/mocap_runs/<name>/smpl_mesh.npz
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import torch
import smplx


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--pred", required=True)
    p.add_argument("--smpl", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--space", choices=["global", "incam"], default="incam")
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--center", action="store_true", help="Subtract per-frame transl so mesh stays at origin")
    args = p.parse_args()

    pred = torch.load(args.pred, map_location="cpu", weights_only=False)
    key = "smpl_params_global" if args.space == "global" else "smpl_params_incam"
    sp = pred[key]
    L = sp["body_pose"].shape[0]
    print(f"[smpl-mesh] {L} frames, space={args.space}")

    # smplx.create() expects a directory containing a smpl/ subdir with
    # SMPL_{NEUTRAL,MALE,FEMALE}.pkl. Our --smpl points at the .pkl itself;
    # use SMPL class directly so we can point at the exact file.
    from smplx.body_models import SMPL
    model = SMPL(
        model_path=str(Path(args.smpl)),
        gender="neutral",
        num_betas=10,
        batch_size=L,
    )

    # GVHMR predicts 21 body joints (63 values); SMPL expects 23 joints (69).
    # Pad joints 22, 23 (hands) with zero rotation.
    body_pose_21 = torch.tensor(sp["body_pose"]).reshape(L, 21, 3)
    body_pose_23 = torch.zeros(L, 23, 3)
    body_pose_23[:, :21] = body_pose_21
    transl = torch.tensor(sp["transl"]).reshape(L, 3)
    if args.center:
        transl = torch.zeros_like(transl)
    out = model(
        body_pose=body_pose_23.reshape(L, 23 * 3),
        global_orient=torch.tensor(sp["global_orient"]).reshape(L, 3),
        betas=torch.tensor(sp["betas"]).reshape(L, 10),
        transl=transl,
        return_verts=True,
    )

    verts = out.vertices.detach().cpu().numpy().astype(np.float32)  # (L, 6890, 3)
    faces = model.faces.astype(np.int32)  # (F, 3)

    np.savez(
        Path(args.out),
        verts=verts,
        faces=faces,
        fps=np.int32(args.fps),
    )
    print(f"[smpl-mesh] wrote {args.out}: verts={verts.shape}, faces={faces.shape}")


if __name__ == "__main__":
    main()
