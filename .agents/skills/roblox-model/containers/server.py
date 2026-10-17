# Local Model Server (`containers/server.py`)
"""
FastAPI microservice exposing local AI 3D models over HTTP on 127.0.0.1:8085.
Runs inside:
  - Windows: Docker container (`nvcr.io/nvidia/pytorch:24.08-py3` with `--gpus all`)
  - macOS:   Native Apple Silicon MPS service (`uv` venv) or CPU Docker fallback

Endpoints:
  GET  /health       -> Device status, available backends
  POST /isolate      -> Stage 1: Strip background (`rembg` BiRefNet/u2net), center & pad
  POST /image-to-3d  -> Stage 2: Convert image to textured .glb (`hunyuan3d` or `triposr`)
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Roblox Local 3D Model Server", version="1.0.0")

WORKSPACE_ROOT = Path(os.environ.get("MODEL_WORKSPACE", "/workspace")).resolve()
TOOLS_ROOT = Path(os.environ.get("MODEL_TOOLS_DIR", "/opt/models")).resolve()


def detect_device() -> str:
    try:
        import torch

        if torch.cuda.is_available():
            return f"cuda ({torch.cuda.get_device_name(0)})"
        if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
            return "mps (Apple Silicon Metal)"
    except Exception:
        pass
    return "cpu"


class IsolateRequest(BaseModel):
    input_path: str
    output_path: str


class ImageTo3DRequest(BaseModel):
    input_path: str
    output_glb: str
    backend: Literal["hunyuan3d", "triposr"] = "hunyuan3d"
    with_texture: bool = True


@app.get("/health")
def health() -> dict[str, object]:
    return {
        "status": "ok",
        "device": detect_device(),
        "workspace_root": str(WORKSPACE_ROOT),
        "backends": {
            "hunyuan3d": (TOOLS_ROOT / "Hunyuan3D-2").is_dir(),
            "triposr": (TOOLS_ROOT / "TripoSR").is_dir(),
        },
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

        img = remove(img)
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
def image_to_3d(req: ImageTo3DRequest) -> dict[str, str]:
    inp = Path(req.input_path)
    out = Path(req.output_glb)
    if not inp.is_file():
        raise HTTPException(status_code=400, detail=f"Isolated image not found: {inp}")
    out.parent.mkdir(parents=True, exist_ok=True)

    if req.backend == "hunyuan3d":
        import torch
        from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline

        device = (
            "cuda"
            if torch.cuda.is_available()
            else ("mps" if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available() else "cpu")
        )
        pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained("tencent/Hunyuan3D-2", device=device)
        mesh = pipe(image=str(inp))[0]
        if req.with_texture and device == "cuda":
            try:
                from hy3dgen.texgen import Hunyuan3DPaintPipeline

                tex_pipe = Hunyuan3DPaintPipeline.from_pretrained("tencent/Hunyuan3D-2")
                mesh = tex_pipe(mesh, image=str(inp))
            except Exception as exc:
                print(f"[warn] Texture synthesis skipped: {exc}")
        mesh.export(str(out))
    elif req.backend == "triposr":
        run_py = TOOLS_ROOT / "TripoSR" / "run.py"
        if not run_py.is_file():
            raise HTTPException(status_code=500, detail=f"TripoSR not installed at {run_py}")
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

    return {"status": "ok", "output_glb": str(out), "backend": req.backend}
