# Full Setup Guide: Containers, Native MPS & Blender MCP (Windows & macOS)

This guide covers:
1. **Where the AI models run** (Docker container on Windows vs. Native Apple Silicon MPS service on macOS — and why).
2. **Step-by-step installation** for both Windows and macOS.
3. **Connecting Blender MCP (`ahujasid/blender-mcp`)** to Claude Code and Codex so the agent can control an open Blender session interactively alongside headless batch scripts.

---

## 1. Container & Runtime Architecture (Windows vs. macOS)

| Platform | Recommended Runtime | Exact Container / Base Image | Why this matters |
| --- | --- | --- | --- |
| **Windows (NVIDIA GPU)** | **Docker Desktop (WSL2 backend) + NVIDIA Container Toolkit** | **`nvcr.io/nvidia/pytorch:24.08-py3`** (built via [`containers/Dockerfile.cuda`](../containers/Dockerfile.cuda)) | 3D models (`Hunyuan3D-2`, `TRELLIS`, `TripoSR`) compile custom C++/CUDA rasterizers (`custom_rasterizer`, `mesh_painter`). On native Windows, Visual Studio `cl.exe` + CUDA version mismatches frequently break builds. Inside `nvcr.io/nvidia/pytorch:24.08-py3`, CUDA 12.x, cuDNN, `ninja` and `gcc` are pre-aligned and isolated, exposing a clean HTTP API on `127.0.0.1:8085`. |
| **macOS (Apple Silicon M1/M2/M3/M4)** | **Isolated `uv` Python 3.11 service (Native Metal `mps`)** running [`containers/server.py`](../containers/server.py) | Native `.tools/roblox-model/venv` (Python 3.11 + PyTorch Metal `mps`) | **Critical macOS limitation:** Docker Desktop on macOS runs inside a Linux VM that **cannot pass Apple Silicon Metal (`mps`) GPUs** into Linux containers. Running inside Docker on a Mac forces slow CPU-only inference (10–25x slower). Running the exact same [`containers/server.py`](../containers/server.py) via an isolated `uv` environment gives full Apple Silicon GPU acceleration on `127.0.0.1:8085`. |

Both platforms expose the **exact same local microservice** (`http://127.0.0.1:8085`) and keep all cached Hugging Face weights in `.tools/roblox-model/hf-cache/` and outputs in `work/models/`.

---

## 2. Windows Setup (NVIDIA GPU Container + Blender)

### Step 2.1: Prerequisites on Windows
1. **Install NVIDIA Game Ready or Studio Driver** (550+ recommended).
2. **Install Docker Desktop for Windows** with the **WSL 2 backend** enabled.
   - Verify GPU passthrough in PowerShell:
     ```powershell
     docker run --rm --gpus all nvcr.io/nvidia/pytorch:24.08-py3 nvidia-smi
     ```
3. **Install Blender 4.2 LTS+** from [blender.org](https://www.blender.org/download/) (default location: `%ProgramFiles%\Blender Foundation\Blender 4.2\blender.exe`).

### Step 2.2: Build and Start the CUDA Model Container
From the repository root in PowerShell:

```powershell
# Create git-ignored local cache & work folders
New-Item -ItemType Directory -Force -Path .tools/roblox-model/hf-cache, work/models | Out-Null

# Build and start the container on 127.0.0.1:8085
docker compose -f .agents/skills/roblox-model/containers/docker-compose.yml --profile cuda up -d --build

# Check health endpoint
curl http://127.0.0.1:8085/health
```

- **First run note:** On the first `/image-to-3d` request, Hugging Face weights (`tencent/Hunyuan3D-2` or `VAST-AI/TripoSR`) are downloaded into `.tools/roblox-model/hf-cache/` on the host disk so they persist across container restarts.

---

## 3. macOS Setup (Apple Silicon MPS Service + Blender)

### Step 3.1: Prerequisites on macOS (M1 / M2 / M3 / M4)
1. **Install Homebrew, `uv` and Blender:**
   ```bash
   brew install uv git
   brew install --cask blender
   ```
   Verify Blender is at `/Applications/Blender.app/Contents/MacOS/Blender`.

### Step 3.2: Create the Isolated `uv` Environment & Install Models
From the repository root in `zsh` / `bash`:

```bash
mkdir -p .tools/roblox-model/hf-cache work/models

# Create a pinned Python 3.11 virtual environment using uv
uv venv .tools/roblox-model/venv --python 3.11

# Install PyTorch with Apple Silicon Metal (mps) + FastAPI server + rembg
uv pip install --python .tools/roblox-model/venv/bin/python \
  torch torchvision torchaudio \
  fastapi "uvicorn[standard]" pydantic requests \
  rembg onnxruntime pillow trimesh numpy scipy \
  huggingface_hub transformers diffusers accelerate einops omegaconf

# Clone Hunyuan3D-2 and TripoSR into .tools/roblox-model/
git clone --depth 1 https://github.com/Tencent/Hunyuan3D-2.git .tools/roblox-model/Hunyuan3D-2
uv pip install --python .tools/roblox-model/venv/bin/python -e .tools/roblox-model/Hunyuan3D-2

git clone --depth 1 https://github.com/VAST-AI-Research/TripoSR.git .tools/roblox-model/TripoSR
uv pip install --python .tools/roblox-model/venv/bin/python -r .tools/roblox-model/TripoSR/requirements.txt
```

### Step 3.3: Start the Local Model Server on macOS
Run the same `server.py` microservice natively with Metal (`mps`) acceleration:

```bash
MODEL_TOOLS_DIR="$PWD/.tools/roblox-model" \
MODEL_WORKSPACE="$PWD" \
HF_HOME="$PWD/.tools/roblox-model/hf-cache" \
.tools/roblox-model/venv/bin/uvicorn server:app \
  --app-dir .agents/skills/roblox-model/containers \
  --host 127.0.0.1 --port 8085
```

Check health in another terminal:
```bash
curl http://127.0.0.1:8085/health
# Expect: {"status":"ok","device":"mps (Apple Silicon Metal)", ...}
```

---

## 4. Blender MCP Setup (`blender-mcp` for Interactive Control)

You have **two complementary ways** to drive Blender from Codex or Claude Code:

| Mode | How it works | Best for |
| --- | --- | --- |
| **1. Interactive Blender MCP (`blender-mcp`)** | Connects Claude Code / Codex to a **live open Blender window** over a local socket (`127.0.0.1:9876`). Exposes MCP tools like `execute_blender_code`, `get_scene_info`, `get_object_info`, and `get_viewport_screenshot`. | Inspecting imported AI meshes visually, tweaking bone positions interactively, checking weight painting, previewing animation poses, and taking viewport screenshots before exporting to Roblox. |
| **2. Headless Batch CLI (`blender --background`)** | Runs [`scripts/blender_process.py`](../scripts/blender_process.py) and [`scripts/blender_rig_and_animate.py`](../scripts/blender_rig_and_animate.py) with no GUI window required. | Fast, deterministic batch decimation, pivot alignment, auto-rigging and FBX export. |

### Step 4.1: Install the Blender MCP Add-on in Blender (Windows & macOS)

1. Clone `blender-mcp` into `.tools/roblox-model/blender-mcp`:
   ```bash
   git clone https://github.com/ahujasid/blender-mcp.git .tools/roblox-model/blender-mcp
   ```
2. Open **Blender 4.2+**.
3. Go to **Edit -> Preferences -> Add-ons**.
4. Click the top-right dropdown arrow -> **Install from Disk...** (or **Install...**), and select:
   `.tools/roblox-model/blender-mcp/addon.py`
5. Enable the checkbox next to **Interface: Blender MCP**.
6. In the 3D Viewport, press **`N`** to open the right sidebar, click the **BlenderMCP** tab, and click **Connect to MCP server** (starts listening on `127.0.0.1:9876`).

### Step 4.2: Register `blender-mcp` in Claude Code

In the repository root, add `blender` to your git-ignored `.mcp.json` (alongside Roblox Studio MCP if configured):

```bash
# Or run via Claude Code CLI:
claude mcp add blender -- uvx blender-mcp
```

Example `.mcp.json` (Windows & macOS compatible when `uv` is installed):
```json
{
  "mcpServers": {
    "blender": {
      "command": "uvx",
      "args": ["blender-mcp"]
    }
  }
}
```

### Step 4.3: Register `blender-mcp` in Codex

Add to your local `.codex/config.local.toml` (git-ignored) or user `~/.codex/config.toml`:

```toml
[mcp_servers.blender]
command = "uvx"
args = ["blender-mcp"]
```

### Step 4.4: How the Agent Uses Blender MCP in the Pipeline

Once connected, Codex or Claude Code can execute the entire Stage 3–5 workflow directly inside your open Blender window via the `execute_blender_code` MCP tool (or run `blender_process.py` + `blender_rig_and_animate.py` and then call `get_viewport_screenshot` via Blender MCP to visually inspect the mesh and rig before importing into Roblox Studio).

---

## 5. Verify Everything with `doctor`

Run:
```bash
python .agents/skills/roblox-model/scripts/run_pipeline.py doctor
```
It reports:
- Whether the **Container / HTTP Model Server** (`http://127.0.0.1:8085/health`) is online and which GPU (`cuda` or `mps`) it sees.
- Whether **Blender MCP** (`127.0.0.1:9876`) is currently listening in an open Blender session.
- Whether the **Headless Blender CLI** and local `.tools/roblox-model/` fallback exist.
