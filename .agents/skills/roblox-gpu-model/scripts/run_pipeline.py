#!/usr/bin/env python3
"""
Local GPU AI 3D modelling pipeline runner for Roblox (Windows, Linux & macOS).

Standard library only, so `doctor` runs before any venv exists. Launch it through
`scripts/rgm.ps1` (Windows) or `scripts/rgm.sh` (macOS/Linux): they pick the tools venv,
then `uv run`, then a system Python.

Subcommands:
  doctor   GPU, model catalog filtered for this machine, model server, Blender CLI & Blender MCP
  serve    Start/stop the local model server (127.0.0.1:8085) from the tools venv
  build    Image -> isolate -> Image-to-3D -> Blender cleanup -> optional rig/animation

Execution modes:
  A. AI inference (Stages 1 & 2): HTTP model server (preferred) or direct venv subprocess
  B. Blender (Stages 3-5): headless Blender CLI; Blender MCP can inspect/refine the result
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

MODEL_SERVER_URL = os.environ.get("ROBLOX_MODEL_SERVER", "http://127.0.0.1:8085")
BLENDER_MCP_HOST = os.environ.get("BLENDER_MCP_HOST", "127.0.0.1")
BLENDER_MCP_PORT = int(os.environ.get("BLENDER_MCP_PORT", "9876"))
ROBLOX_TRI_LIMIT = 10000
SKILL_NAME = "roblox-gpu-model"
# Tools folder created by earlier versions of this skill; still used when present.
LEGACY_TOOLS_NAME = "roblox-model"


def find_repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def skill_dir() -> Path:
    return Path(__file__).resolve().parents[1]


def tools_dir(repo_root: Path) -> Path:
    env = os.environ.get("ROBLOX_GPU_MODEL_TOOLS")
    if env:
        return Path(env).resolve()
    current = repo_root / ".tools" / SKILL_NAME
    legacy = repo_root / ".tools" / LEGACY_TOOLS_NAME
    if not current.exists() and legacy.exists():
        return legacy
    return current


def find_blender_exe() -> str | None:
    env_blender = os.environ.get("BLENDER_EXE")
    if env_blender and Path(env_blender).is_file():
        return env_blender

    which_blender = shutil.which("blender")
    if which_blender:
        return which_blender

    system = platform.system()
    candidates: list[Path] = []
    if system == "Windows":
        prog_files = Path(os.environ.get("PROGRAMFILES", "/Program Files"))
        blender_foundation = prog_files / "Blender Foundation"
        if blender_foundation.is_dir():
            for folder in sorted(blender_foundation.glob("Blender*"), reverse=True):
                candidates.append(folder / "blender.exe")
    elif system == "Darwin":
        candidates.append(Path("/Applications/Blender.app/Contents/MacOS/Blender"))
        candidates.append(Path.home() / "Applications/Blender.app/Contents/MacOS/Blender")

    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return None


def venv_bin(repo_root: Path, name: str) -> Path:
    venv = tools_dir(repo_root) / "venv"
    if platform.system() == "Windows":
        return venv / "Scripts" / f"{name}.exe"
    return venv / "bin" / name


def find_venv_python(repo_root: Path) -> str | None:
    cand = venv_bin(repo_root, "python")
    return str(cand) if cand.is_file() else None


def check_model_server(timeout: float = 5.0) -> dict[str, object] | None:
    try:
        req = urllib.request.Request(f"{MODEL_SERVER_URL}/health", method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None
    return None


def check_blender_mcp_socket() -> bool:
    try:
        with socket.create_connection((BLENDER_MCP_HOST, BLENDER_MCP_PORT), timeout=1.0):
            return True
    except OSError:
        return False


def post_json(url: str, payload: dict[str, object], timeout: float = 3600.0) -> dict[str, object]:
    # Generous timeout: the first Stage 2 request downloads several GB of model weights.
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Model server {url} returned HTTP {exc.code}: {detail[:2000]}") from exc


def to_container_path(repo_root: Path, host_path: Path, server_info: dict[str, object]) -> str:
    ws_root = str(server_info.get("workspace_root", "/workspace"))
    if ws_root == "/workspace":
        rel = host_path.resolve().relative_to(repo_root.resolve())
        return "/workspace/" + str(rel).replace("\\", "/")
    return str(host_path.resolve())


# ---------------------------------------------------------------------------
# GPU detection and model catalog
# ---------------------------------------------------------------------------


def probe_gpu(repo_root: Path, server_health: dict[str, object] | None) -> dict[str, object]:
    """Best available GPU description: model server -> venv torch -> nvidia-smi -> macOS sysctl."""
    if server_health and isinstance(server_health.get("gpu"), dict):
        gpu = dict(server_health["gpu"])  # type: ignore[arg-type]
        gpu["source"] = "model_server"
        return gpu

    venv_py = find_venv_python(repo_root)
    if venv_py:
        code = (
            "import json,torch\n"
            "d={'torch':torch.__version__}\n"
            "if torch.cuda.is_available():\n"
            "  p=torch.cuda.get_device_properties(0)\n"
            "  d.update(device='cuda',name=p.name,vram_gb=round(p.total_memory/1024**3,1),"
            "compute_capability=f'{p.major}.{p.minor}',torch_arch_list=torch.cuda.get_arch_list())\n"
            "elif getattr(torch.backends,'mps',None) and torch.backends.mps.is_available():\n"
            "  d.update(device='mps',name='Apple Silicon (Metal)')\n"
            "else:\n"
            "  d.update(device='cpu')\n"
            "print(json.dumps(d))\n"
        )
        try:
            res = subprocess.run([venv_py, "-c", code], capture_output=True, text=True, timeout=120)
            if res.returncode == 0 and res.stdout.strip():
                gpu = json.loads(res.stdout.strip().splitlines()[-1])
                if gpu.get("device") == "mps":
                    gpu.update(mac_memory())
                gpu["source"] = "venv_torch"
                return gpu
        except Exception:
            pass

    if shutil.which("nvidia-smi"):
        try:
            res = subprocess.run(
                ["nvidia-smi", "--query-gpu=name,memory.total,compute_cap", "--format=csv,noheader,nounits"],
                capture_output=True,
                text=True,
                timeout=20,
            )
            name, mem, cap = [x.strip() for x in res.stdout.strip().splitlines()[0].split(",")]
            return {
                "device": "cuda",
                "name": name,
                "vram_gb": round(float(mem) / 1024, 1),
                "compute_capability": cap,
                "source": "nvidia-smi",
            }
        except Exception:
            pass

    if platform.system() == "Darwin" and platform.machine() == "arm64":
        gpu = {"device": "mps", "name": "Apple Silicon (Metal)", "source": "sysctl"}
        gpu.update(mac_memory())
        return gpu
    return {"device": "cpu", "source": "none"}


def mac_memory() -> dict[str, object]:
    try:
        out = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, check=True)
        return {"unified_memory_gb": round(int(out.stdout.strip()) / 1024**3, 1)}
    except Exception:
        return {}


# min_vram_gb: NVIDIA VRAM as reported by the driver (a "16 GB" card reports ~15.9);
# min_unified_gb: Apple Silicon unified memory.
# None means the model does not run on that platform.
MODEL_CATALOG: list[dict[str, object]] = [
    {
        "id": "hunyuan3d",
        "label": "Hunyuan3D-2 shape (DiT)",
        "stage": "image-to-3d",
        "cli": "--backend hunyuan3d",
        "min_vram_gb": 7.5,
        "min_unified_gb": 24,
        "notes": "Best general quality; watertight mesh. ~6 GB VRAM for shape generation.",
    },
    {
        "id": "triposr",
        "label": "TripoSR (fast)",
        "stage": "image-to-3d",
        "cli": "--backend triposr",
        "min_vram_gb": 5.5,
        "min_unified_gb": 16,
        "notes": "2-6 s blockouts and simple props; lower detail. Needs torchmcubes (C++ build).",
    },
    {
        "id": "hunyuan3d_paint",
        "label": "Hunyuan3D-Paint texture",
        "stage": "texture",
        "cli": "--texture hunyuan",
        "min_vram_gb": 15,
        "min_unified_gb": None,
        "notes": "Local PBR texture. NVIDIA only; needs the compiled custom_rasterizer CUDA extension.",
    },
    {
        "id": "studio_texture",
        "label": "Roblox Studio AI texture (generate_texture)",
        "stage": "texture",
        "cli": "--texture studio",
        "min_vram_gb": 0,
        "min_unified_gb": 0,
        "notes": "Runs in Roblox's cloud after import; needs Studio MCP. Re-scales the mesh (fix-up required).",
    },
    {
        "id": "none",
        "label": "No texture (shape only)",
        "stage": "texture",
        "cli": "--texture none",
        "min_vram_gb": 0,
        "min_unified_gb": 0,
        "notes": "Untextured mesh; colour it in Studio or Blender.",
    },
]


def model_catalog(gpu: dict[str, object], server_health: dict[str, object] | None) -> dict[str, object]:
    device = gpu.get("device")
    backends = (server_health or {}).get("backends") or {}
    visible: list[dict[str, object]] = []
    hidden: list[dict[str, object]] = []

    for model in MODEL_CATALOG:
        entry = dict(model)
        need_cuda, need_mac = model["min_vram_gb"], model["min_unified_gb"]
        reason = ""
        if model["id"] in ("studio_texture", "none"):
            fits = True
        elif device == "cuda":
            fits = float(gpu.get("vram_gb") or 0) >= float(need_cuda)  # type: ignore[arg-type]
            if not fits:
                reason = f"needs {need_cuda} GB VRAM, this GPU has {gpu.get('vram_gb')} GB"
        elif device == "mps":
            fits = need_mac is not None and float(gpu.get("unified_memory_gb") or 0) >= float(need_mac)
            if not fits:
                reason = "NVIDIA CUDA only" if need_mac is None else f"needs {need_mac} GB unified memory"
        else:
            fits, reason = False, "no supported GPU (CUDA or Apple Silicon) detected"

        status = backends.get(model["id"]) if isinstance(backends, dict) else None
        if isinstance(status, dict):
            entry["installed"] = bool(status.get("ready"))
            if status.get("reason"):
                entry["install_note"] = status["reason"]
        elif model["id"] in ("studio_texture", "none"):
            entry["installed"] = True
        else:
            entry["installed"] = None  # unknown until the model server is running

        if fits:
            visible.append(entry)
        else:
            entry["hidden_reason"] = reason
            hidden.append(entry)

    for stage in ("image-to-3d", "texture"):
        candidates = [m for m in visible if m["stage"] == stage]
        preferred = [m for m in candidates if m.get("installed") is not False] or candidates
        if stage == "texture":
            # Local paint when it is installed, otherwise Studio's cloud texture.
            order = ["hunyuan3d_paint", "studio_texture", "none"]
            preferred = [m for m in preferred if m["id"] != "hunyuan3d_paint" or m.get("installed")]
            preferred.sort(key=lambda m: order.index(str(m["id"])))
        if preferred:
            preferred[0]["recommended"] = True

    return {"visible": visible, "hidden": hidden}


def blender_mcp_addon_commit(repo_root: Path) -> str | None:
    repo = tools_dir(repo_root) / "blender-mcp"
    if not (repo / ".git").exists() or not shutil.which("git"):
        return None
    try:
        res = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=10)
        return res.stdout.strip() or None
    except Exception:
        return None


def cmd_doctor(repo_root: Path) -> int:
    tdir = tools_dir(repo_root)
    venv_py = find_venv_python(repo_root)
    blender_exe = find_blender_exe()
    server_health = check_model_server()
    gpu = probe_gpu(repo_root, server_health)
    catalog = model_catalog(gpu, server_health)

    report: dict[str, object] = {
        "os": platform.system(),
        "arch": platform.machine(),
        "python_running_doctor": sys.executable,
        "tools_dir": str(tdir),
        "venv_python": venv_py,
        "gpu": gpu,
        "models": catalog,
        "model_server_url": MODEL_SERVER_URL,
        "model_server_online": server_health is not None,
        "model_server_backends": (server_health or {}).get("backends"),
        "blender_cli_exe": blender_exe,
        "blender_mcp_socket_online": check_blender_mcp_socket(),
        "blender_mcp_endpoint": f"{BLENDER_MCP_HOST}:{BLENDER_MCP_PORT}",
        "blender_mcp_addon_commit": blender_mcp_addon_commit(repo_root),
    }

    if blender_exe:
        try:
            bres = subprocess.run([blender_exe, "--version"], capture_output=True, text=True, check=True, timeout=60)
            report["blender_version"] = bres.stdout.splitlines()[0] if bres.stdout else "unknown"
        except Exception as exc:
            report["blender_error"] = str(exc)

    problems: list[str] = []
    arch_list = gpu.get("torch_arch_list")
    cap = str(gpu.get("compute_capability") or "")
    if isinstance(arch_list, list) and cap:
        sm = "sm_" + cap.replace(".", "")
        if sm not in arch_list:
            problems.append(f"Installed torch has no kernels for {sm}; reinstall torch from the cu128 index.")
    if not venv_py and not server_health:
        problems.append(f"No tools venv at {tdir / 'venv'} and no model server; follow references/setup.md.")
    elif not server_health:
        problems.append("Model server offline; start it with `rgm serve --background`.")
    if not blender_exe:
        problems.append("Blender not found; install Blender 4.2+ or set BLENDER_EXE.")
    if not any(m["stage"] == "image-to-3d" for m in catalog["visible"]):  # type: ignore[index]
        problems.append("No local Image-to-3D model fits this machine; consider Studio generate_mesh instead.")
    report["problems"] = problems

    print(json.dumps(report, indent=2))
    return 1 if problems else 0


# ---------------------------------------------------------------------------
# serve
# ---------------------------------------------------------------------------


def server_pid_file(repo_root: Path) -> Path:
    return repo_root / "work" / "model-server.pid"


def cmd_serve(args: argparse.Namespace, repo_root: Path) -> int:
    pid_file = server_pid_file(repo_root)

    if args.stop:
        try:
            post_json(f"{MODEL_SERVER_URL}/unload", {}, timeout=30)
        except Exception:
            pass
        if not pid_file.is_file():
            print("No pid file; nothing to stop (a server started elsewhere must be stopped there).")
            return 0
        pid = int(pid_file.read_text().strip())
        try:
            if platform.system() == "Windows":
                subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True, check=False)
            else:
                os.killpg(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        pid_file.unlink(missing_ok=True)
        print(f"Stopped model server (pid {pid}).")
        return 0

    if check_model_server(timeout=2.0):
        print(f"Model server already running at {MODEL_SERVER_URL}.")
        return 0

    uvicorn = venv_bin(repo_root, "uvicorn")
    if not uvicorn.is_file():
        print(f"Error: {uvicorn} not found. Create the tools venv first (references/setup.md).", file=sys.stderr)
        return 1

    tdir = tools_dir(repo_root)
    env = os.environ.copy()
    env.update(
        {
            "MODEL_TOOLS_DIR": str(tdir),
            "MODEL_WORKSPACE": str(repo_root),
            "HF_HOME": str(tdir / "hf-cache"),
            "PYTHONUNBUFFERED": "1",
            # Keep __pycache__ out of the skill folder (template validation lists its files).
            "PYTHONDONTWRITEBYTECODE": "1",
        }
    )
    cmd = [
        str(uvicorn),
        "server:app",
        "--app-dir",
        str(skill_dir() / "containers"),
        "--host",
        "127.0.0.1",
        "--port",
        MODEL_SERVER_URL.rsplit(":", 1)[-1].strip("/"),
    ]

    if not args.background:
        return subprocess.call(cmd, env=env)

    log_path = repo_root / "work" / "model-server.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log = open(log_path, "ab")  # noqa: SIM115 - handed to the detached child
    kwargs: dict[str, object] = {"stdout": log, "stderr": subprocess.STDOUT, "stdin": subprocess.DEVNULL, "env": env}
    if platform.system() == "Windows":
        kwargs["creationflags"] = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP  # type: ignore[attr-defined]
    else:
        kwargs["start_new_session"] = True
    proc = subprocess.Popen(cmd, **kwargs)  # type: ignore[call-overload]
    pid_file.write_text(str(proc.pid))

    for _ in range(60):
        time.sleep(1)
        if proc.poll() is not None:
            print(f"Error: model server exited early; see {log_path}", file=sys.stderr)
            return 1
        health = check_model_server(timeout=2.0)
        if health:
            print(json.dumps({"started": True, "pid": proc.pid, "log": str(log_path), "health": health}, indent=2))
            return 0
    print(f"Error: model server did not answer within 60 s; see {log_path}", file=sys.stderr)
    return 1


# ---------------------------------------------------------------------------
# build
# ---------------------------------------------------------------------------


def stage1_isolate_image(
    repo_root: Path,
    server_info: dict[str, object] | None,
    venv_py: str | None,
    input_image: Path,
    output_image: Path,
    skip_rembg: bool,
) -> None:
    if skip_rembg:
        shutil.copy2(input_image, output_image)
        return

    if server_info is not None:
        post_json(
            f"{MODEL_SERVER_URL}/isolate",
            {
                "input_path": to_container_path(repo_root, input_image, server_info),
                "output_path": to_container_path(repo_root, output_image, server_info),
            },
        )
        return

    if not venv_py:
        raise RuntimeError("Model server offline and no tools venv; run `rgm serve --background` first.")
    code = """
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGBA")
try:
    from rembg import remove
    img = remove(img)
except ImportError:
    print("[stage1] rembg not installed; keeping input alpha/RGB as-is.")

bbox = img.getbbox()
if bbox:
    img = img.crop(bbox)

w, h = img.size
side = int(max(w, h) * 1.15)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.paste(img, ((side - w) // 2, (side - h) // 2), img)
canvas = canvas.resize((1024, 1024), Image.Resampling.LANCZOS)
canvas.save(sys.argv[2])
"""
    subprocess.run([venv_py, "-c", code, str(input_image), str(output_image)], check=True)


def stage2_image_to_3d(
    repo_root: Path,
    server_info: dict[str, object] | None,
    venv_py: str | None,
    backend: str,
    isolated_image: Path,
    raw_glb: Path,
    with_texture: bool,
) -> None:
    if server_info is not None:
        post_json(
            f"{MODEL_SERVER_URL}/image-to-3d",
            {
                "input_path": to_container_path(repo_root, isolated_image, server_info),
                "output_glb": to_container_path(repo_root, raw_glb, server_info),
                "backend": backend,
                "with_texture": with_texture,
            },
        )
        return

    if not venv_py:
        raise RuntimeError("Model server offline and no tools venv; run `rgm serve --background` first.")
    if backend == "hunyuan3d":
        code = """
import sys
import torch
from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline

img_path, out_glb, with_tex = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
device = "cuda" if torch.cuda.is_available() else ("mps" if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available() else "cpu")
pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained("tencent/Hunyuan3D-2", device=device)
mesh = pipe(image=img_path)[0]
if with_tex:
    from hy3dgen.texgen import Hunyuan3DPaintPipeline
    mesh = Hunyuan3DPaintPipeline.from_pretrained("tencent/Hunyuan3D-2")(mesh, image=img_path)
mesh.export(out_glb)
"""
        subprocess.run(
            [venv_py, "-c", code, str(isolated_image), str(raw_glb), "1" if with_texture else "0"],
            check=True,
        )
    elif backend == "triposr":
        run_py = tools_dir(repo_root) / "TripoSR" / "run.py"
        if not run_py.is_file():
            raise RuntimeError(f"TripoSR not found at {run_py}. See references/setup.md.")
        out_dir = raw_glb.parent / "triposr_tmp"
        out_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [venv_py, str(run_py), str(isolated_image), "--output-dir", str(out_dir), "--model-save-format", "glb"],
            check=True,
        )
        generated = list(out_dir.rglob("*.glb"))
        if not generated:
            raise RuntimeError("TripoSR did not produce a .glb output.")
        shutil.copy2(generated[0], raw_glb)


def update_manifest(manifest_path: Path, extra: dict[str, object]) -> dict[str, object]:
    manifest: dict[str, object] = {}
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest.update(extra)
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def run_build(args: argparse.Namespace, repo_root: Path) -> int:
    if args.no_texture:
        args.texture = "none"
    if args.target_tris > ROBLOX_TRI_LIMIT:
        print(f"Error: --target-tris must be <= {ROBLOX_TRI_LIMIT} (Roblox MeshPart limit).", file=sys.stderr)
        return 1

    server_info = check_model_server()
    venv_py = find_venv_python(repo_root)
    scripts_dir = Path(__file__).resolve().parent

    # Intermediate AI scratch files stay in git-ignored work/models/<name>/
    work_dir = repo_root / "work" / "models" / args.name
    work_dir.mkdir(parents=True, exist_ok=True)
    isolated_img = work_dir / "01_isolated.png"
    raw_glb = Path(args.input_mesh).resolve() if args.input_mesh else (work_dir / "02_raw_mesh.glb")
    mode_label = "model server" if server_info else "local venv"

    if not args.input_mesh:
        if args.reuse_isolated:
            if not isolated_img.is_file():
                print(f"Error: --reuse-isolated given but {isolated_img} does not exist.", file=sys.stderr)
                return 1
            print(f"[Stage 1/4] Reusing approved isolation: {isolated_img}")
        else:
            if not args.input:
                print("Error: Either --input <image> or --input-mesh <mesh> is required.", file=sys.stderr)
                return 1
            input_image = Path(args.input).resolve()
            if not input_image.is_file():
                print(f"Error: Input image not found: {input_image}", file=sys.stderr)
                return 1
            print(f"[Stage 1/4] Isolating subject ({mode_label}) -> {isolated_img}")
            stage1_isolate_image(repo_root, server_info, venv_py, input_image, isolated_img, args.skip_rembg)
            if args.isolate_only:
                print(f"\nCheckpoint: review {isolated_img}, then re-run with --reuse-isolated.")
                return 0

        print(f"[Stage 2/4] Generating 3D mesh with '{args.backend}' ({mode_label}) -> {raw_glb}")
        stage2_image_to_3d(
            repo_root, server_info, venv_py, args.backend, isolated_img, raw_glb, args.texture == "hunyuan"
        )
    else:
        print(f"[Stage 1-2/4] Using existing input mesh: {raw_glb}")

    blender_exe = find_blender_exe()
    if not blender_exe:
        print("Error: Blender executable not found. Install Blender 4.2+ or set BLENDER_EXE.", file=sys.stderr)
        return 1

    # Final editable .blend and exported .fbx live in the game repository's assets/models/<name>/ (or --output-dir)
    asset_dir = Path(args.output_dir).resolve() if args.output_dir else repo_root / "assets" / "models" / args.name
    asset_dir.mkdir(parents=True, exist_ok=True)
    clean_blend = asset_dir / f"{args.name}.blend"
    static_fbx = asset_dir / f"{args.name}_static.fbx"
    rigged_blend = asset_dir / f"{args.name}_rigged.blend"
    rigged_fbx = asset_dir / f"{args.name}_rigged.fbx"
    manifest_path = asset_dir / "manifest.json"

    print(f"[Stage 3/4] Running Blender cleanup & Roblox prep -> {clean_blend}")
    subprocess.run(
        [
            blender_exe,
            "--background",
            "--python",
            str(scripts_dir / "blender_process.py"),
            "--",
            "--input",
            str(raw_glb),
            "--output-blend",
            str(clean_blend),
            "--output-fbx",
            str(static_fbx),
            "--target-tris",
            str(args.target_tris),
            "--height-studs",
            str(args.height_studs),
            "--manifest",
            str(manifest_path),
        ],
        check=True,
    )

    if args.rig_type != "none":
        print(f"[Stage 4/4] Running Blender rigging ({args.rig_type}) & animation ({args.animate}) -> {rigged_fbx}")
        subprocess.run(
            [
                blender_exe,
                "--background",
                str(clean_blend),
                "--python",
                str(scripts_dir / "blender_rig_and_animate.py"),
                "--",
                "--rig-type",
                args.rig_type,
                "--animate",
                args.animate,
                "--output-blend",
                str(rigged_blend),
                "--output-fbx",
                str(rigged_fbx),
                "--manifest",
                str(manifest_path),
            ],
            check=True,
        )

    for backup in asset_dir.glob("*.blend[0-9]*"):
        backup.unlink()

    manifest = update_manifest(
        manifest_path,
        {
            "name": args.name,
            "backend": None if args.input_mesh else args.backend,
            "texture": args.texture,
            "output_target": args.output_target,
            "rig_type": args.rig_type,
        },
    )
    print(f"\nGame assets saved in: {asset_dir}")
    print(json.dumps(manifest, indent=2))

    final_tris = int(manifest.get("final_triangles") or 0)
    if not manifest.get("within_budget", final_tris <= args.target_tris) or final_tris > ROBLOX_TRI_LIMIT:
        print(
            f"\nError: final mesh has {final_tris} triangles; budget is {args.target_tris} "
            f"(Roblox limit {ROBLOX_TRI_LIMIT}). Do not import; lower detail or split the mesh.",
            file=sys.stderr,
        )
        return 2

    next_step = {
        "studio": "Import the static/rigged FBX into Roblox Studio (references/pipeline-and-import.md).",
        "blender": "Blender-only target: open the .blend (or inspect via Blender MCP); skip Studio import.",
    }[args.output_target]
    print(f"\nPipeline complete. Next: {next_step}")
    if args.texture == "studio":
        print("Texture: apply Studio generate_texture after import, then run the rescale fix-up.")
    return 0


def main() -> int:
    repo_root = find_repo_root()
    parser = argparse.ArgumentParser(description="Local GPU AI 3D modelling pipeline for Roblox")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("doctor", help="Report GPU, models that fit it, model server, Blender CLI and Blender MCP")

    serve_p = sub.add_parser("serve", help="Start or stop the local model server from the tools venv")
    serve_p.add_argument("--background", action="store_true", help="Detach and log to work/model-server.log")
    serve_p.add_argument("--stop", action="store_true", help="Unload models and stop a background server")

    build_p = sub.add_parser("build", help="Run the Image-to-3D -> Blender -> Rig/Animate pipeline")
    build_p.add_argument("--input", help="Path to input concept/reference image")
    build_p.add_argument("--input-mesh", help="Existing .glb/.obj/.fbx mesh (skips Stages 1 & 2)")
    build_p.add_argument("--name", required=True, help="Asset slug name (saved to assets/models/<name>/)")
    build_p.add_argument("--output-dir", help="Custom output directory (default: assets/models/<name>/)")
    build_p.add_argument(
        "--backend", choices=["hunyuan3d", "triposr"], default="hunyuan3d", help="Image-to-3D backend"
    )
    build_p.add_argument(
        "--texture",
        choices=["none", "hunyuan", "studio"],
        default="none",
        help="none = shape only; hunyuan = local Hunyuan3D-Paint; studio = Studio generate_texture after import",
    )
    build_p.add_argument("--no-texture", action="store_true", help=argparse.SUPPRESS)
    build_p.add_argument(
        "--output-target",
        choices=["studio", "blender"],
        default="studio",
        help="studio = prepare for Roblox Studio import; blender = Blender model only",
    )
    build_p.add_argument("--isolate-only", action="store_true", help="Stop after Stage 1 so the image can be reviewed")
    build_p.add_argument("--reuse-isolated", action="store_true", help="Skip Stage 1 and use the reviewed image")
    build_p.add_argument("--skip-rembg", action="store_true", help="Skip background removal if already isolated")
    build_p.add_argument("--target-tris", type=int, default=6000, help="Triangle budget (<= 10000 for Roblox)")
    build_p.add_argument("--height-studs", type=float, default=5.0, help="Target model height in Roblox studs")
    build_p.add_argument(
        "--rig-type", choices=["none", "prop", "humanoid", "quadruped"], default="none", help="Auto-rig preset"
    )
    build_p.add_argument("--animate", default="idle,walk", help="Animations to bake when rigged (e.g. idle,walk)")

    args = parser.parse_args()
    if args.command == "doctor":
        return cmd_doctor(repo_root)
    if args.command == "serve":
        return cmd_serve(args, repo_root)
    if args.command == "build":
        return run_build(args, repo_root)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
