# Setup: model server, Blender and Blender MCP (Windows, Linux, macOS)

Run `rgm doctor` (see the launcher table in [SKILL.md](../SKILL.md)) before and after each step.
Paths below are relative to the repository root. Everything machine-local lives in the
git-ignored `.tools/roblox-gpu-model/` (older installs in `.tools/roblox-model/` keep working).

## 1. Choose a runtime

| Runtime | Platforms | Status | Notes |
| --- | --- | --- | --- |
| **Native `uv` venv** (default) | Windows + NVIDIA, Linux + NVIDIA, macOS Apple Silicon | Verified on Windows 11 / RTX 5070 Ti (2026-10-18) | No Docker, no reboot. Hunyuan3D-2 shape generation needs no compiler. |
| **Docker CUDA image** | Windows (WSL2 Docker Desktop) or Linux + NVIDIA Container Toolkit | Not re-verified since the 25.01 base bump | Builds the texture extensions inside the image. Needs WSL2/Docker admin install and a reboot on Windows. |

macOS cannot use Docker for inference: Docker Desktop's Linux VM has no access to Metal.

**GPU generations:** RTX 50-series (Blackwell, compute capability 12.0 / `sm_120`) needs
PyTorch CUDA 12.8 wheels (`cu128`) or NVIDIA image 25.01+. `doctor` flags a torch build that
lacks kernels for the detected GPU.

## 2. Prerequisites

| | Windows | macOS (Apple Silicon) | Linux |
| --- | --- | --- | --- |
| GPU driver | NVIDIA driver 570+ | built in | NVIDIA driver 570+ |
| uv | `winget install astral-sh.uv` | `brew install uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| git | Git for Windows | `xcode-select --install` or `brew install git` | distro package |
| Blender 4.2+ (5.2 verified) | blender.org installer | `brew install --cask blender` | blender.org tarball or distro |

Open a new terminal after installing uv so `uv`/`uvx` are on `PATH`.

## 3. Native install

Pinned versions live in [`containers/constraints.txt`](../containers/constraints.txt); always pass
`-c` with it. Pinned upstream commits:

| Repo | Commit |
| --- | --- |
| Tencent/Hunyuan3D-2 | `f8db63096c8282cb27354314d896feba5ba6ff8a` |
| VAST-AI-Research/TripoSR (optional) | `107cefdc244c39106fa830359024f6a2f1c78871` |
| ahujasid/blender-mcp add-on | `7a0373ec9199183cb460068c4f96aed9c579fb4f` |

### Windows (PowerShell)

```powershell
$skill = ".agents/skills/roblox-gpu-model"
$tools = ".tools/roblox-gpu-model"
New-Item -ItemType Directory -Force "$tools/hf-cache", "work/models" | Out-Null
uv venv "$tools/venv" --python 3.11
$py = "$tools/venv/Scripts/python.exe"
uv pip install --python $py torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 -c "$skill/containers/constraints.txt"
uv pip install --python $py -r "$skill/containers/requirements.txt" -c "$skill/containers/constraints.txt"
git clone https://github.com/Tencent/Hunyuan3D-2.git "$tools/Hunyuan3D-2"
git -C "$tools/Hunyuan3D-2" checkout f8db63096c8282cb27354314d896feba5ba6ff8a
uv pip install --python $py -e "$tools/Hunyuan3D-2" -c "$skill/containers/constraints.txt"
& $py -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0), torch.cuda.get_arch_list())"
```

### macOS / Linux (bash or zsh)

```bash
skill=.agents/skills/roblox-gpu-model
tools=.tools/roblox-gpu-model
mkdir -p "$tools/hf-cache" work/models
uv venv "$tools/venv" --python 3.11
py="$tools/venv/bin/python"
# Linux + NVIDIA: add  --index-url https://download.pytorch.org/whl/cu128  to the torch line.
uv pip install --python "$py" torch torchvision torchaudio -c "$skill/containers/constraints.txt"
uv pip install --python "$py" -r "$skill/containers/requirements.txt" -c "$skill/containers/constraints.txt"
git clone https://github.com/Tencent/Hunyuan3D-2.git "$tools/Hunyuan3D-2"
git -C "$tools/Hunyuan3D-2" checkout f8db63096c8282cb27354314d896feba5ba6ff8a
uv pip install --python "$py" -e "$tools/Hunyuan3D-2" -c "$skill/containers/constraints.txt"
"$py" -c "import torch; print('cuda', torch.cuda.is_available(), 'mps', torch.backends.mps.is_available())"
```

macOS (Metal) support for Hunyuan3D-2 is upstream-provided and has not been verified with
this skill yet; check `rgm doctor` and the first build log, and report results in context.

### Optional backends (only when the developer picked them from the model list)

- **TripoSR** needs `torchmcubes`, a C++ extension (Visual Studio Build Tools "Desktop C++" on
  Windows, Xcode command-line tools on macOS). Do not install TripoSR's own `requirements.txt`:
  it pins `transformers==4.35.0` and breaks Hunyuan3D.
  ```bash
  git clone https://github.com/VAST-AI-Research/TripoSR.git .tools/roblox-gpu-model/TripoSR
  git -C .tools/roblox-gpu-model/TripoSR checkout 107cefdc244c39106fa830359024f6a2f1c78871
  uv pip install --python <venv python> "git+https://github.com/tatsy/torchmcubes.git" "imageio[ffmpeg]" moderngl xatlas -c .agents/skills/roblox-gpu-model/containers/constraints.txt
  ```
- **Hunyuan3D-Paint** (NVIDIA only, ~16 GB VRAM) needs the `custom_rasterizer` CUDA extension:
  CUDA Toolkit matching the torch build (12.8) plus a C++ compiler (Visual Studio Build Tools on
  Windows). Native Windows build is unverified; the Docker image builds it automatically.
  ```bash
  uv pip install --python <venv python> --no-build-isolation .tools/roblox-gpu-model/Hunyuan3D-2/hy3dgen/texgen/custom_rasterizer
  ```
  Without it, use Studio `generate_texture` (`--texture studio`) or `--texture none`.

## 4. Start the model server

```text
rgm serve --background   # detached; log: work/model-server.log, pid: work/model-server.pid
rgm doctor               # model_server_online: true, backends report ready/false with a reason
rgm serve --stop         # unload models (frees VRAM) and stop
```
`serve` sets `MODEL_TOOLS_DIR`, `MODEL_WORKSPACE` and `HF_HOME` (weights cache in
`<tools>/hf-cache/`) and binds only to `127.0.0.1`. Models load on first use and stay cached.

### Docker alternative (Windows WSL2 / Linux)

```bash
docker run --rm --gpus all nvcr.io/nvidia/pytorch:25.01-py3 nvidia-smi   # GPU passthrough check
docker compose -f .agents/skills/roblox-gpu-model/containers/docker-compose.yml --profile cuda up -d --build
```
The container mounts `work/`, `assets/` and `.tools/roblox-gpu-model/hf-cache/`; `doctor`
detects it on port 8085 the same way.

## 5. Blender MCP (optional, for live inspection)

1. Clone the add-on at the pinned commit (review upstream changes before bumping it):
   ```bash
   git clone https://github.com/ahujasid/blender-mcp.git .tools/roblox-gpu-model/blender-mcp
   git -C .tools/roblox-gpu-model/blender-mcp checkout 7a0373ec9199183cb460068c4f96aed9c579fb4f
   ```
2. Blender -> **Edit -> Preferences -> Add-ons** -> top-right dropdown -> **Install from Disk...**
   -> select the **file** `.tools/roblox-gpu-model/blender-mcp/addon.py` (selecting only the folder
   fails with "Error extracting archive"). It appears as **MCP for Blender**, enabled.
3. Start its socket (`127.0.0.1:9876`): 3D Viewport -> `N` -> **MCP for Blender** tab -> Connect.
   If the tab does not respond (seen with automated clicks), open the **Scripting** workspace and
   run `bpy.ops.blendermcp.start_server()` in the Python console ("Server is already running" is fine).
   Only one Blender instance can own the port; close extra Blender windows.
4. Register the MCP server in the client (machine-local, never in committed config):
   - **Claude Code:** project `.mcp.json` (git-ignored) or `claude mcp add blender -- uvx blender-mcp`
     ```json
     { "mcpServers": { "blender": { "command": "uvx", "args": ["blender-mcp"] } } }
     ```
   - **Codex:** `codex mcp add blender -- uvx blender-mcp`, or in `~/.codex/config.toml`
     (or the git-ignored `.codex/config.local.toml`):
     ```toml
     [mcp_servers.blender]
     command = "uvx"
     args = ["blender-mcp"]
     ```
   Restart the client; check that `blender` tools appear and `rgm doctor` shows the socket online.

## 6. Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Python was not found; run without arguments to install from the Microsoft Store` | Use the `rgm` launcher; it never calls the Store alias. |
| `uv` on Windows: `Missing expected target directory for Python minor version link` | uv's junction step failed; the interpreter is still installed. Remove the broken `%APPDATA%\uv\python\cpython-3.11-windows-*` junction (`cmd /c rmdir`), then re-run `uv venv`. |
| HTTP 500 from `/image-to-3d`; log shows `Missing key(s) in state_dict ... q_proj` | `transformers` too new; reinstall with `-c constraints.txt`. |
| `cannot import name 'resolve_revision' from 'huggingface_hub'` | `diffusers` too new for the pinned hub; reinstall with `-c constraints.txt`. |
| `CUDA error: no kernel image is available` on RTX 50-series | torch without `sm_120`; reinstall torch from the `cu128` index. |
| Any server error | Read `work/model-server.log`. |
