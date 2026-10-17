---
name: roblox-model
description: "Convert reference images into Roblox-ready 3D meshes, rigs and animations using local AI models and headless Blender or Blender MCP. Use for setting up or running the local Image-to-3D, rigging, animation and Studio import pipeline on Windows or macOS."
---

# Local AI 3D modelling pipeline for Roblox

This skill turns input reference images into Roblox-ready 3D assets (props, characters, mounts and animated creatures) using a local AI model microservice (`127.0.0.1:8085`) plus **Blender MCP** (`ahujasid/blender-mcp`) or headless Blender automation—rather than asking an LLM to guess raw 3D vertex coordinates.

For creative approvals and developer ownership, follow [roblox-collaboration](../roblox-collaboration/SKILL.md). For manual Blender editing, `.blend` source preservation and Roblox Studio verification, use [roblox-blender](../roblox-blender/SKILL.md).

## Architecture: Local Model Server + Blender MCP + Studio MCP

| Component | Windows (NVIDIA GPU) | macOS (Apple Silicon M1–M4) | Role |
| --- | --- | --- | --- |
| **Local AI Model Server** (`127.0.0.1:8085`) | **Docker Container** (`nvcr.io/nvidia/pytorch:24.08-py3` via [`containers/Dockerfile.cuda`](containers/Dockerfile.cuda)) | **Native Metal (`mps`) `uv` Service** running [`containers/server.py`](containers/server.py) *(Docker on Mac cannot access Metal GPUs)* | Runs `rembg` (`BiRefNet`/`u2net`), **Hunyuan3D-2**, and **TripoSR** without polluting host Python |
| **Blender Control** (`127.0.0.1:9876` or CLI) | **Blender MCP** (`uvx blender-mcp`) + Headless CLI (`blender --background`) | **Blender MCP** (`uvx blender-mcp`) + Headless CLI (`blender --background`) | Decimates `< 10,000` tris, scales to Roblox studs, fits armatures, bakes animations, takes viewport screenshots |
| **Roblox Studio Control** | **Official Studio MCP** + Studio 3D Importer / Open Cloud | **Official Studio MCP** + Studio 3D Importer / Open Cloud | Imports `.fbx`, configures `SurfaceAppearance` and verifies runtime behavior |

Detailed model specs and VRAM budgets live in [references/models.md](references/models.md).

## Folder layout in the game repository

| Folder in your game repo | Purpose | Git status |
| --- | --- | --- |
| **`assets/models/<name>/`** (or `--output-dir`) | **Final project deliverables:** `<name>.blend` (editable source of truth), `<name>_static.fbx`, `<name>_rigged.blend`, `<name>_rigged.fbx` and `manifest.json` | Lives in your game repository (commit with Git / Git LFS when versioning game assets; see `docs/SETUP.md`) |
| **`work/models/<name>/`** | **Temporary AI scratch files:** `01_isolated.png` (background stripped) and `02_raw_mesh.glb` (dense raw AI mesh before decimation) | Git-ignored (`work/`) so raw 200k-triangle AI dumps never bloat your repository |
| **`.tools/roblox-model/`** | **Local model weights & venv:** Hugging Face cache (`hf-cache/`) and macOS `uv` venv | Git-ignored (`.tools/`) |

## Pipeline stages

1. **Setup (one-time per machine):** Start the CUDA Docker container (Windows) or MPS service (macOS), install Blender 4.2+, and optionally connect `blender-mcp`. Follow [references/setup.md](references/setup.md).
2. **Stage 1 — Input image isolation:** Strip background (`rembg`), crop, and center on a `1024x1024` alpha canvas (`work/models/<name>/01_isolated.png`).
3. **Stage 2 — Image-to-3D generation:** Call the local model server (`Hunyuan3D-2` primary or `TripoSR` fast fallback) to produce a textured mesh (`work/models/<name>/02_raw_mesh.glb`).
4. **Stage 3 — Blender cleanup & Roblox prep:** Run via **Blender MCP** (`execute_blender_code`) or headless [`scripts/blender_process.py`](scripts/blender_process.py) to decimate under Roblox's 10,000-triangle limit, align bottom-center pivot to `(0, 0, 0)`, scale to target height in studs (`1 Blender meter = 1 Roblox stud`), and save `assets/models/<name>/<name>.blend` + `<name>_static.fbx`.
5. **Stage 4 & 5 — Rigging & animation (optional):** Run via **Blender MCP** or headless [`scripts/blender_rig_and_animate.py`](scripts/blender_rig_and_animate.py) to bind a `humanoid`, `quadruped` or `prop` armature and bake loopable `Idle` / `Walk` actions into `assets/models/<name>/<name>_rigged.blend` + `<name>_rigged.fbx`.
6. **Stage 6 — Roblox Studio import & verification:** Import into Roblox Studio and verify scale, collisions and animation playback at runtime ([references/pipeline-and-import.md](references/pipeline-and-import.md)).

## Triggering from Codex or Claude Code

1. **Check environment readiness first:**
   ```bash
   python .agents/skills/roblox-model/scripts/run_pipeline.py doctor
   ```
   Verifies the `127.0.0.1:8085` model container/service, `127.0.0.1:9876` Blender MCP socket, and Blender CLI. If not yet configured, walk the developer through [references/setup.md](references/setup.md).
2. **Run the pipeline:**
   ```bash
   python .agents/skills/roblox-model/scripts/run_pipeline.py build \
     --input work/inputs/concept.png \
     --name cyber_sword \
     --backend hunyuan3d \
     --target-tris 6000 \
     --height-studs 4.5 \
     --rig-type none
   ```
   Or when **Blender MCP** is active in an open Blender session, use `execute_blender_code` and `get_viewport_screenshot` to inspect and refine the generated `.blend` interactively before exporting to Roblox Studio.

## Reference index

- [references/setup.md](references/setup.md): Full Windows (NVIDIA Docker container) & macOS (Apple Silicon MPS service) setup + Blender MCP installation.
- [references/models.md](references/models.md): Curated local models for background removal, Image-to-3D, auto-rigging and motion generation.
- [references/pipeline-and-import.md](references/pipeline-and-import.md): Stage-by-stage workflow, Blender MCP vs. headless CLI usage, and Roblox Studio import steps.
- [containers/Dockerfile.cuda](containers/Dockerfile.cuda) & [containers/docker-compose.yml](containers/docker-compose.yml): Pinpoint NVIDIA PyTorch container definition for Windows.
