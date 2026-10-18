# Local Model Server (`containers/server.py`)
"""
FastAPI microservice exposing local AI 3D models over HTTP on 127.0.0.1:8085.
Runs as:
  - Windows / Linux (NVIDIA): native `uv` venv (CUDA 12.8 wheels) or Docker (`Dockerfile.cuda`)
  - macOS (Apple Silicon):    native `uv` venv using Metal (`mps`)
Start it with `run_pipeline.py serve`, which sets the environment variables below.

Endpoints:
  GET  /health       -> Device, GPU memory and which backends actually import
  POST /isolate      -> Stage 1: Strip background (`rembg`), crop, center & pad
  POST /image-to-3d  -> Stage 2: Convert image to .glb (`hunyuan3d` or `triposr`)
  POST /unload       -> Free cached models and GPU memory
"""

from __future__ import annotations

import gc
import importlib.util
import os
import shutil
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any, Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Roblox Local 3D Model Server", version="1.1.0")

WORKSPACE_ROOT = Path(os.environ.get("MODEL_WORKSPACE", "/workspace")).resolve()
TOOLS_ROOT = Path(os.environ.get("MODEL_TOOLS_DIR", "/opt/models")).resolve()
HUNYUAN_REPO = os.environ.get("HUNYUAN3D_REPO", "tencent/Hunyuan3D-2")

# Loading Hunyuan3D takes far longer than inference, so pipelines stay cached between requests.
_pipelines: dict[str, Any] = {}
_lock = threading.Lock()


def torch_device() -> str:
    try:
        import torch

        if torch.cuda.is_available():
            return "cuda"
        if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
            return "mps"
    except Exception:
        pass
    return "cpu"


def gpu_info() -> dict[str, object]:
    info: dict[str, object] = {"device": torch_device()}
    try:
        import torch

        if info["device"] == "cuda":
            props = torch.cuda.get_device_properties(0)
            info["name"] = props.name
            info["vram_gb"] = round(props.total_memory / 1024**3, 1)
            info["compute_capability"] = f"{props.major}.{props.minor}"
            info["torch_arch_list"] = torch.cuda.get_arch_list()
        elif info["device"] == "mps":
            info["name"] = "Apple Silicon (Metal)"
            try:
                out = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, check=True)
                info["unified_memory_gb"] = round(int(out.stdout.strip()) / 1024**3, 1)
            except Exception:
                pass
        info["torch"] = torch.__version__
    except Exception as exc:
        info["error"] = str(exc)
    return info


def has_module(name: str) -> bool:
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


def backend_status() -> dict[str, dict[str, object]]:
    """Report backends by whether they can actually run, not by whether a folder exists."""
    status: dict[str, dict[str, object]] = {}

    hy_ok, hy_reason = True, ""
    try:
        from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline  # noqa: F401
    except Exception as exc:
        hy_ok, hy_reason = False, f"{type(exc).__name__}: {exc}"
    status["hunyuan3d"] = {"ready": hy_ok, "reason": hy_reason}

    # mesh_processor has a pure-Python fallback; the CUDA rasterizer has none.
    tex_missing = [m for m in ("custom_rasterizer",) if not has_module(m)]
    status["hunyuan3d_paint"] = {
        "ready": hy_ok and not tex_missing and torch_device() == "cuda",
        "reason": (
            "needs CUDA" if torch_device() != "cuda"
            else (f"compiled extensions missing: {', '.join(tex_missing)}" if tex_missing else "")
        ),
    }

    run_py = TOOLS_ROOT / "TripoSR" / "run.py"
    tripo_missing = [m for m in ("torchmcubes",) if not has_module(m)]
    status["triposr"] = {
        "ready": run_py.is_file() and not tripo_missing,
        "reason": (
            f"not cloned at {run_py.parent}" if not run_py.is_file()
            else (f"missing packages: {', '.join(tripo_missing)}" if tripo_missing else "")
        ),
    }
    status["rembg"] = {"ready": has_module("rembg"), "reason": "" if has_module("rembg") else "rembg not installed"}
    return status


def get_pipeline(key: str) -> Any:
    with _lock:
        if key not in _pipelines:
            device = torch_device()
            if key == "shape":
                from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline

                _pipelines[key] = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(HUNYUAN_REPO, device=device)
            elif key == "paint":
                from hy3dgen.texgen import Hunyuan3DPaintPipeline

                _pipelines[key] = Hunyuan3DPaintPipeline.from_pretrained(HUNYUAN_REPO)
            elif key == "rembg":
                from rembg import new_session

                _pipelines[key] = new_session()
        return _pipelines[key]


class IsolateRequest(BaseModel):
    input_path: str
    output_path: str


class ImageTo3DRequest(BaseModel):
    input_path: str
    output_glb: str
    backend: Literal["hunyuan3d", "triposr"] = "hunyuan3d"
    with_texture: bool = False


@app.get("/health")
def health() -> dict[str, object]:
    gpu = gpu_info()
    return {
        "status": "ok",
        "device": f"{gpu['device']} ({gpu.get('name', 'unknown')})",
        "gpu": gpu,
        "workspace_root": str(WORKSPACE_ROOT),
        "tools_root": str(TOOLS_ROOT),
        "backends": backend_status(),
        "cached_pipelines": sorted(_pipelines),
    }


@app.post("/isolate")
def isolate(req: IsolateRequest) -> dict[str, str]:
    inp = Path(req.input_path)
    out = Path(req.output_path)
    if not inp.is_file():
        raise HTTPException(status_code=400, detail=f"Input image not found: {inp}")

    from PIL import Image

    img = Image.open(inp).convert("RGBA")
    try:
        from rembg import remove

        img = remove(img, session=get_pipeline("rembg"))
    except ImportError:
        pass

    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)

    w, h = img.size
    side = int(max(w, h) * 1.15)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2), img)
    canvas = canvas.resize((1024, 1024), Image.Resampling.LANCZOS)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    return {"status": "ok", "output_path": str(out)}


@app.post("/image-to-3d")
def image_to_3d(req: ImageTo3DRequest) -> dict[str, object]:
    inp = Path(req.input_path)
    out = Path(req.output_glb)
    if not inp.is_file():
        raise HTTPException(status_code=400, detail=f"Isolated image not found: {inp}")
    out.parent.mkdir(parents=True, exist_ok=True)
    textured = False

    if req.backend == "hunyuan3d":
        mesh = get_pipeline("shape")(image=str(inp))[0]
        if req.with_texture:
            if not backend_status()["hunyuan3d_paint"]["ready"]:
                raise HTTPException(
                    status_code=400,
                    detail=f"Hunyuan3D-Paint unavailable: {backend_status()['hunyuan3d_paint']['reason']}",
                )
            mesh = get_pipeline("paint")(mesh, image=str(inp))
            textured = True
        mesh.export(str(out))
    elif req.backend == "triposr":
        if not backend_status()["triposr"]["ready"]:
            raise HTTPException(status_code=400, detail=f"TripoSR unavailable: {backend_status()['triposr']['reason']}")
        run_py = TOOLS_ROOT / "TripoSR" / "run.py"
        tmp_dir = out.parent / "triposr_tmp"
        tmp_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [sys.executable, str(run_py), str(inp), "--output-dir", str(tmp_dir), "--model-save-format", "glb"],
            check=True,
        )
        glbs = list(tmp_dir.rglob("*.glb"))
        if not glbs:
            raise HTTPException(status_code=500, detail="TripoSR produced no .glb output")
        shutil.copy2(glbs[0], out)

    return {"status": "ok", "output_glb": str(out), "backend": req.backend, "textured": textured}


@app.post("/unload")
def unload() -> dict[str, object]:
    with _lock:
        freed = sorted(_pipelines)
        _pipelines.clear()
    gc.collect()
    try:
        import torch

        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        elif getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
            torch.mps.empty_cache()
    except Exception:
        pass
    return {"status": "ok", "freed": freed}
