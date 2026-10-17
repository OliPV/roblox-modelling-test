#!/usr/bin/env python3
"""
Local AI 3D modelling pipeline runner for Roblox (Windows & macOS).

Supports two execution modes for each part of the pipeline:
  A. AI Model Inference (Stages 1 & 2):
     1. Local HTTP Container / Microservice (`http://127.0.0.1:8085` — Docker CUDA on Windows, native MPS server on macOS)
     2. Direct local `.tools/roblox-model/venv` subprocess fallback
  B. Blender Processing, Rigging & Animation (Stages 3, 4 & 5):
     1. Live Blender MCP socket (`127.0.0.1:9876`) or Claude/Codex `blender-mcp` tool
     2. Headless Blender CLI (`blender --background --python ...`)
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

MODEL_SERVER_URL = os.environ.get("ROBLOX_MODEL_SERVER", "http://127.0.0.1:8085")
BLENDER_MCP_HOST = os.environ.get("BLENDER_MCP_HOST", "127.0.0.1")
BLENDER_MCP_PORT = int(os.environ.get("BLENDER_MCP_PORT", "9876"))


def find_repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


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


def find_venv_python(repo_root: Path) -> str:
    venv_dir = repo_root / ".tools" / "roblox-model" / "venv"
    if platform.system() == "Windows":
        cand = venv_dir / "Scripts" / "python.exe"
    else:
        cand = venv_dir / "bin" / "python"
    if cand.is_file():
        return str(cand)
    return sys.executable


def check_model_server() -> dict[str, object] | None:
    try:
        req = urllib.request.Request(f"{MODEL_SERVER_URL}/health", method="GET")
        with urllib.request.urlopen(req, timeout=2.0) as resp:
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


def post_json(url: str, payload: dict[str, object]) -> dict[str, object]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=600.0) as resp:
        return json.loads(resp.read().decode("utf-8"))


def to_container_path(repo_root: Path, host_path: Path, server_info: dict[str, object]) -> str:
    ws_root = str(server_info.get("workspace_root", "/workspace"))
    if ws_root == "/workspace":
        rel = host_path.resolve().relative_to(repo_root.resolve())
        return "/workspace/" + str(rel).replace("\\", "/")
    return str(host_path.resolve())


def cmd_doctor(repo_root: Path) -> int:
    tools_dir = repo_root / ".tools" / "roblox-model"
    venv_py = find_venv_python(repo_root)
    blender_exe = find_blender_exe()
    server_health = check_model_server()
    blender_mcp_live = check_blender_mcp_socket()

    report: dict[str, object] = {
        "os": platform.system(),
        "arch": platform.machine(),
        "model_server_url": MODEL_SERVER_URL,
        "model_server_online": server_health is not None,
        "model_server_health": server_health,
        "blender_mcp_socket_online": blender_mcp_live,
        "blender_mcp_endpoint": f"{BLENDER_MCP_HOST}:{BLENDER_MCP_PORT}",
        "blender_cli_exe": blender_exe,
        "venv_python": venv_py,
        "venv_isolated": str(tools_dir) in venv_py,
    }

    if blender_exe:
        try:
            bres = subprocess.run([blender_exe, "--version"], capture_output=True, text=True, check=True)
            report["blender_version"] = bres.stdout.splitlines()[0] if bres.stdout else "unknown"
        except Exception as exc:
            report["blender_error"] = str(exc)

    print(json.dumps(report, indent=2))
    if not server_health and not (tools_dir / "venv").is_dir():
        print(
            "\n[!] Local model server (127.0.0.1:8085) is offline and .tools/roblox-model/venv is not set up.\n"
            "    See .agents/skills/roblox-model/references/setup.md to start the Docker container (Windows) or MPS service (macOS).",
            file=sys.stderr,
        )
        return 1
    return 0


def stage1_isolate_image(
    repo_root: Path,
    server_info: dict[str, object] | None,
    venv_py: str,
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

    code = """
import sys
from pathlib import Path
from PIL import Image

inp = Path(sys.argv[1])
out = Path(sys.argv[2])
img = Image.open(inp).convert("RGBA")

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
canvas.save(out)
"""
    subprocess.run([venv_py, "-c", code, str(input_image), str(output_image)], check=True)


def stage2_image_to_3d(
    repo_root: Path,
    server_info: dict[str, object] | None,
    venv_py: str,
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

    tools_dir = repo_root / ".tools" / "roblox-model"
    if backend == "hunyuan3d":
        code = """
import sys
import torch
from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline

img_path, out_glb, with_tex = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
device = "cuda" if torch.cuda.is_available() else ("mps" if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available() else "cpu")
pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained("tencent/Hunyuan3D-2", device=device)
mesh = pipe(image=img_path)[0]
if with_tex and device == "cuda":
    try:
        from hy3dgen.texgen import Hunyuan3DPaintPipeline
        tex_pipe = Hunyuan3DPaintPipeline.from_pretrained("tencent/Hunyuan3D-2")
        mesh = tex_pipe(mesh, image=img_path)
    except Exception as exc:
        print(f"[stage2] Texture synthesis skipped ({exc}); exporting geometry.")
mesh.export(out_glb)
"""
        subprocess.run(
            [venv_py, "-c", code, str(isolated_image), str(raw_glb), "1" if with_texture else "0"],
            check=True,
        )
    elif backend == "triposr":
        run_py = tools_dir / "TripoSR" / "run.py"
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


def run_build(args: argparse.Namespace, repo_root: Path) -> int:
    blender_exe = find_blender_exe()
    if not blender_exe:
        print("Error: Blender executable not found. Install Blender 4.2+ or set BLENDER_EXE.", file=sys.stderr)
        return 1

    server_info = check_model_server()
    venv_py = find_venv_python(repo_root)
    scripts_dir = Path(__file__).resolve().parent

    # Intermediate AI scratch files stay in git-ignored work/models/<name>/
    work_dir = repo_root / "work" / "models" / args.name
    work_dir.mkdir(parents=True, exist_ok=True)

    # Final editable .blend and exported .fbx live in the game repository's assets/models/<name>/ (or --output-dir)
    if args.output_dir:
        asset_dir = Path(args.output_dir).resolve()
    else:
        asset_dir = repo_root / "assets" / "models" / args.name
    asset_dir.mkdir(parents=True, exist_ok=True)

    isolated_img = work_dir / "01_isolated.png"
    raw_glb = Path(args.input_mesh).resolve() if args.input_mesh else (work_dir / "02_raw_mesh.glb")
    clean_blend = asset_dir / f"{args.name}.blend"
    static_fbx = asset_dir / f"{args.name}_static.fbx"
    rigged_blend = asset_dir / f"{args.name}_rigged.blend"
    rigged_fbx = asset_dir / f"{args.name}_rigged.fbx"
    manifest_path = asset_dir / "manifest.json"

    if not args.input_mesh:
        if not args.input:
            print("Error: Either --input <image> or --input-mesh <mesh> is required.", file=sys.stderr)
            return 1
        input_image = Path(args.input).resolve()
        if not input_image.is_file():
            print(f"Error: Input image not found: {input_image}", file=sys.stderr)
            return 1
        mode_label = "container/HTTP server" if server_info else "local venv"
        print(f"[Stage 1/4] Isolating subject ({mode_label}) -> {isolated_img}")
        stage1_isolate_image(repo_root, server_info, venv_py, input_image, isolated_img, args.skip_rembg)

        print(f"[Stage 2/4] Generating 3D mesh with '{args.backend}' ({mode_label}) -> {raw_glb}")
        stage2_image_to_3d(repo_root, server_info, venv_py, args.backend, isolated_img, raw_glb, not args.no_texture)
    else:
        print(f"[Stage 1-2/4] Using existing input mesh: {raw_glb}")

    print(f"[Stage 3/4] Running Blender cleanup & Roblox prep -> {clean_blend}")
    blender_process_script = scripts_dir / "blender_process.py"
    subprocess.run(
        [
            blender_exe,
            "--background",
            "--python",
            str(blender_process_script),
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
        blender_rig_script = scripts_dir / "blender_rig_and_animate.py"
        subprocess.run(
            [
                blender_exe,
                "--background",
                str(clean_blend),
                "--python",
                str(blender_rig_script),
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

    print(f"\nPipeline complete. Game assets saved in: {asset_dir}")
    print(f"Manifest written to: {manifest_path}")
    if manifest_path.is_file():
        print(manifest_path.read_text(encoding="utf-8"))
    return 0


def main() -> int:
    repo_root = find_repo_root()
    parser = argparse.ArgumentParser(description="Local AI 3D modelling pipeline for Roblox")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("doctor", help="Check Model Container/Server, Blender MCP socket, and Blender CLI")

    build_p = sub.add_parser("build", help="Run the Image-to-3D -> Blender -> Rig/Animate pipeline")
    build_p.add_argument("--input", help="Path to input concept/reference image")
    build_p.add_argument("--input-mesh", help="Optional existing .glb/.obj/.fbx mesh (skips Stage 1 & 2)")
    build_p.add_argument("--name", required=True, help="Asset slug name (saved to assets/models/<name>/)")
    build_p.add_argument(
        "--output-dir",
        help="Optional custom output directory inside the game repo (default: assets/models/<name>/)",
    )
    build_p.add_argument(
        "--backend",
        choices=["hunyuan3d", "triposr"],
        default="hunyuan3d",
        help="Local Image-to-3D backend (default: hunyuan3d)",
    )
    build_p.add_argument("--skip-rembg", action="store_true", help="Skip background removal if already isolated")
    build_p.add_argument("--no-texture", action="store_true", help="Skip texture stage in Hunyuan3D-2")
    build_p.add_argument("--target-tris", type=int, default=6000, help="Target triangle budget (< 10000 for Roblox)")
    build_p.add_argument("--height-studs", type=float, default=5.0, help="Target model height in Roblox studs")
    build_p.add_argument(
        "--rig-type",
        choices=["none", "prop", "humanoid", "quadruped"],
        default="none",
        help="Auto-rigging preset in Blender",
    )
    build_p.add_argument(
        "--animate",
        default="idle,walk",
        help="Comma-separated procedural animations to bake when rigged (e.g. idle,walk)",
    )

    args = parser.parse_args()
    if args.command == "doctor":
        return cmd_doctor(repo_root)
    if args.command == "build":
        return run_build(args, repo_root)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
