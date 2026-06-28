"""Run GVHMR inference on a single video, MPS-friendly.

Wraps the official `tools/demo/demo.py` flow, replacing all `.cuda()` calls
with `.to(MPS)` via a runtime monkey-patch, and skipping the renderer
(we only need the SMPL params pickle).

We force `static_cam=True` and `use_dpvo=False` because DPVO is CUDA-only.
For reference clips this matches the demo's recommended path anyway.

Output: `<out-dir>/hmr4d_results.pt` (the pred dict our retarget script
consumes) plus the standard preprocess artefacts (bbx, vitpose, etc.).

Usage:
    python tools/mocap/infer.py --video /path/to/clip.mp4 \\
        --out-dir /tmp/mocap_runs/<name>
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


# ── 1. device + monkey-patches BEFORE GVHMR imports ────────────────────────────

import torch

# Active device target. Held as a single-element list so the monkey-patches
# below can re-read it on each call — allowing us to flip between MPS (preproc)
# and CPU (HMR4D forward, which crashes on MPS for a slice op).
def _pick_device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


DEVICE_HOLDER = [_pick_device()]
HMR4D_DEVICE = torch.device("cpu")


def get_device() -> torch.device:
    return DEVICE_HOLDER[0]


def set_device(dev: torch.device) -> None:
    DEVICE_HOLDER[0] = dev


# Back-compat alias used elsewhere in the file.
DEVICE = DEVICE_HOLDER[0]

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")


def _patch_cuda_calls() -> None:
    """Route every `.cuda()` and `.to('cuda')` to DEVICE."""
    orig_tensor_cuda = torch.Tensor.cuda
    orig_module_cuda = torch.nn.Module.cuda
    orig_tensor_to = torch.Tensor.to
    orig_module_to = torch.nn.Module.to

    def coerce_args(args, kwargs):
        def coerce(d):
            if isinstance(d, str) and d.startswith("cuda"):
                return get_device()
            if isinstance(d, torch.device) and d.type == "cuda":
                return get_device()
            return d

        if "device" in kwargs:
            kwargs["device"] = coerce(kwargs["device"])
        if args:
            args = (coerce(args[0]),) + tuple(args[1:])
        return args, kwargs

    def tensor_cuda(self, *_a, **_k):
        return self.to(get_device())

    def module_cuda(self, *_a, **_k):
        return self.to(get_device())

    def tensor_to(self, *args, **kwargs):
        args, kwargs = coerce_args(args, kwargs)
        return orig_tensor_to(self, *args, **kwargs)

    def module_to(self, *args, **kwargs):
        args, kwargs = coerce_args(args, kwargs)
        return orig_module_to(self, *args, **kwargs)

    torch.Tensor.cuda = tensor_cuda  # type: ignore[assignment]
    torch.nn.Module.cuda = module_cuda  # type: ignore[assignment]
    torch.Tensor.to = tensor_to  # type: ignore[assignment]
    torch.nn.Module.to = module_to  # type: ignore[assignment]

    # Lightning's _DeviceDtypeModuleMixin shadows nn.Module.cuda; patch it too.
    patched = False
    for modpath in (
        "lightning_fabric.utilities.device_dtype_mixin",
        "pytorch_lightning.core.mixins.device_dtype_mixin",
    ):
        try:
            mod = __import__(modpath, fromlist=["*"])
        except Exception:
            continue
        for name in dir(mod):
            if "DeviceDtype" in name and "Mixin" in name:
                cls = getattr(mod, name)
                if isinstance(cls, type):
                    cls.cuda = module_cuda  # type: ignore[assignment]
                    patched = True
    if not patched:
        print("WARN: failed to patch lightning DeviceDtypeMixin.cuda", file=sys.stderr)

    # Avoid crashes in code that calls torch.cuda.synchronize() unconditionally.
    torch.cuda.synchronize = lambda *a, **k: None  # type: ignore[assignment]
    # get_device_properties is called in demo.py for logging.
    class _DummyProps:
        name = f"{DEVICE.type} (mps-shim)"
        total_memory = 0
        major = minor = 0

    torch.cuda.get_device_properties = lambda *a, **k: _DummyProps()  # type: ignore[assignment]


_patch_cuda_calls()


# ── 2. put GVHMR on the path + cd into it (it uses relative checkpoint paths) ─

GVHMR_DIR = Path(os.environ.get("GVHMR_DIR", str(Path.home() / "Public/experiments/gvhmr")))
if not GVHMR_DIR.exists():
    raise SystemExit(f"GVHMR repo not found at {GVHMR_DIR} (set GVHMR_DIR env var)")
sys.path.insert(0, str(GVHMR_DIR))
os.chdir(GVHMR_DIR)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--video", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--f-mm", type=int, default=None)
    args = p.parse_args()

    video_path = Path(args.video).expanduser().resolve()
    out_dir = Path(args.out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    # Drive demo.py via its own argparse — easier than rewiring hydra.
    sys.argv = [
        "demo.py",
        "--video", str(video_path),
        "--output_root", str(out_dir.parent),
        "-s",  # static_cam
    ]
    if args.f_mm:
        sys.argv += ["--f_mm", str(args.f_mm)]

    # Import AFTER cuda patches are in place.
    import hydra  # noqa: F401
    import pytorch_lightning as pl
    from hmr4d.utils.pylogger import Log
    from hmr4d.utils.net_utils import detach_to_cpu

    # demo.py uses video_path.stem for its run name; override to match out_dir.
    from tools.demo import demo as demo_mod

    cfg = demo_mod.parse_args_to_cfg()
    print(f"[infer] device = {DEVICE}, output_dir = {cfg.output_dir}")

    demo_mod.run_preprocess(cfg)
    data = demo_mod.load_data_dict(cfg)

    if not Path(cfg.paths.hmr4d_results).exists():
        Log.info("[HMR4D] Predicting")
        # Flip device so the monkey-patched .cuda() inside predict() also lands
        # on CPU — otherwise predict() moves the batch back to MPS and we get
        # a device-mismatch error against model buffers.
        set_device(HMR4D_DEVICE)
        model = hydra.utils.instantiate(cfg.model, _recursive_=False)
        model.load_pretrained_model(cfg.ckpt_path)
        model = model.eval().to(HMR4D_DEVICE)
        data = {k: (v.to(HMR4D_DEVICE) if torch.is_tensor(v) else v) for k, v in data.items()}
        tic = Log.time()
        with torch.no_grad():
            pred = model.predict(data, static_cam=cfg.static_cam)
        pred = detach_to_cpu(pred)
        Log.info(f"[HMR4D] Elapsed: {Log.time()-tic:.2f}s for L={data['length']}")
        torch.save(pred, cfg.paths.hmr4d_results)

    # Copy the result into our out-dir so the retarget script knows where to look.
    import shutil
    target = out_dir / "hmr4d_results.pt"
    if Path(cfg.paths.hmr4d_results).resolve() != target.resolve():
        shutil.copy2(cfg.paths.hmr4d_results, target)
    print(f"[infer] wrote {target}")


if __name__ == "__main__":
    main()
