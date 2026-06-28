#!/usr/bin/env bash
# Pull every weight GVHMR needs from HuggingFace mirrors.
# Uses `huggingface-cli` inside GVHMR's venv (installed automatically).
#
# Mirrors:
#   - camenduru/GVHMR       (gvhmr, hmr2, vitpose, yolo)
#   - camenduru/SMPLer-X    (SMPLX_NEUTRAL.npz)
#   - lithiumice/models_hub (SMPL_NEUTRAL.pkl + SMPLX backups)
#
# Note: SMPL/SMPLX have their own licenses — these mirrors exist because
# many academic projects re-host them. The "official" source is
# smpl.is.tue.mpg.de and smpl-x.is.tue.mpg.de (free registration).
set -euo pipefail

GVHMR_DIR="${GVHMR_DIR:-$HOME/Public/experiments/gvhmr}"
CKPT_DIR="$GVHMR_DIR/inputs/checkpoints"
PY="$GVHMR_DIR/.venv/bin/python"

if [[ ! -x "$PY" ]]; then
  echo "GVHMR venv missing at $PY — run setup first." >&2
  exit 1
fi

# huggingface_hub is already pulled in by transitive deps, but ensure CLI:
uv pip install --python "$PY" --quiet "huggingface_hub[cli]" >/dev/null

HF_CLI="$GVHMR_DIR/.venv/bin/hf"

mkdir -p \
  "$CKPT_DIR/gvhmr" \
  "$CKPT_DIR/hmr2" \
  "$CKPT_DIR/vitpose" \
  "$CKPT_DIR/yolo" \
  "$CKPT_DIR/body_models/smpl" \
  "$CKPT_DIR/body_models/smplx"

dl() {
  # dl <repo> <repo_path> <local_dest>
  local repo="$1" rpath="$2" dest="$3"
  if [[ -f "$dest" ]]; then
    echo "  already present: $dest"
    return
  fi
  echo "  fetching $repo:$rpath → $dest"
  local tmpdir="$(mktemp -d)"
  "$HF_CLI" download "$repo" "$rpath" --local-dir "$tmpdir" >/dev/null
  mv "$tmpdir/$rpath" "$dest"
  rm -rf "$tmpdir"
}

echo "[gvhmr] downloading checkpoints from huggingface…"
dl camenduru/GVHMR "gvhmr/gvhmr_siga24_release.ckpt" "$CKPT_DIR/gvhmr/gvhmr_siga24_release.ckpt"
dl camenduru/GVHMR "hmr2/epoch=10-step=25000.ckpt"   "$CKPT_DIR/hmr2/epoch=10-step=25000.ckpt"
dl camenduru/GVHMR "vitpose/vitpose-h-multi-coco.pth" "$CKPT_DIR/vitpose/vitpose-h-multi-coco.pth"
dl camenduru/GVHMR "yolo/yolov8x.pt"                  "$CKPT_DIR/yolo/yolov8x.pt"

echo "[gvhmr] downloading SMPL/SMPLX body models…"
dl camenduru/SMPLer-X "SMPLX_NEUTRAL.npz" \
   "$CKPT_DIR/body_models/smplx/SMPLX_NEUTRAL.npz"
dl camenduru/SMPLer-X "SMPL_NEUTRAL.pkl" \
   "$CKPT_DIR/body_models/smpl/SMPL_NEUTRAL.pkl"

echo "[gvhmr] all weights present."
ls -lh "$CKPT_DIR"/*/*.* 2>/dev/null | awk '{print "  "$5"  "$9}'
