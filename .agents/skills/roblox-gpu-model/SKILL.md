---
name: roblox-gpu-model
description: "Turn a reference image into a Roblox-ready 3D mesh, rig and animation with local GPU AI models (NVIDIA CUDA or Apple Silicon) and Blender. Use for setting up or running the local Image-to-3D pipeline, picking models for the machine's GPU, texturing, and Studio or Blender-only output on Windows, Linux or macOS."
---

# Local GPU Image-to-3D pipeline for Roblox

Reference image -> background removal -> local Image-to-3D model -> Blender cleanup (budget,
scale, pivot) -> optional rig/animation -> Roblox Studio import or Blender-only output.
Inference runs on the developer's own GPU through a model server on `127.0.0.1:8085`; Blender
runs headless, and Blender MCP can inspect or refine the result in a live window.

Works in Claude Code and Codex (ChatGPT): both read this canonical skill; every step is a
shell command or an MCP call, with a manual fallback when a client lacks a tool.
Follow [roblox-collaboration](../roblox-collaboration/SKILL.md) for approvals and
[roblox-blender](../roblox-blender/SKILL.md) for manual Blender work and `.blend` ownership.

## Launcher

Run every command through the launcher; it uses the tools venv, else `uv run`, else Python 3,
so it works before anything is installed and never hits the Windows Store `python` alias.

| OS | Command prefix (`rgm` below) |
| --- | --- |
| Windows | `powershell -ExecutionPolicy Bypass -File .agents/skills/roblox-gpu-model/scripts/rgm.ps1` |
| macOS / Linux | `sh .agents/skills/roblox-gpu-model/scripts/rgm.sh` |

`rgm doctor` reports the GPU, the models that fit it, model-server backends (by whether they
actually import), Blender CLI, the Blender MCP socket and a `problems` list (exit code 1 if any).

## Setup (one time per machine)

1. Run `rgm doctor` first, before installing anything, to read the GPU.
2. **Present the model list from `models.visible`** and ask which to install. Mark the
   `recommended` entries, show `notes` and `install_note`, and never offer `models.hidden`
   (they do not fit this GPU or platform); mention in one line that some were hidden and why.
3. Install with [references/setup.md](references/setup.md): native `uv` venv on Windows,
   Linux and macOS (default), or the CUDA Docker image. Always apply
   [containers/constraints.txt](containers/constraints.txt); unpinned installs break Hunyuan3D.
4. `rgm serve --background`, then `rgm doctor` again; `problems` must be empty.
5. Optional: Blender MCP add-on (pinned commit) for live inspection; see setup.md section 5.

## Before every build: confirm options

Show the options below as a short numbered list with proposed values, and let the developer
change any before running. Fill proposals from the image and `rgm doctor`; do not run until
they confirm (a plain "go" is fine). Repeat the list when they ask for a rebuild.

| # | Option | Flag | Proposal guidance |
| --- | --- | --- | --- |
| 1 | Image-to-3D model | `--backend` | `recommended` visible model that is installed |
| 2 | Triangle budget | `--target-tris` | 6000 default; <= 10000 (Roblox MeshPart limit), 4000 for accessories |
| 3 | Height in studs | `--height-studs` | From the subject: ~5 character, ~3 pet, ~4 sword, 8-12 boss |
| 4 | Rig | `--rig-type` | `none` props; `humanoid` bipeds; `quadruped` four-legged; `prop` hinged |
| 5 | Output target | `--output-target` | `studio` (import into Studio) or `blender` (Blender model only, skip Studio) |
| 6 | Texture | `--texture` | `hunyuan` if installed; else `studio` (cloud, after import; Studio target only); `none` |

Also state the asset `--name` and that the first run downloads several GB of weights.

## Run

```text
rgm build --input work/inputs/<image> --name <slug> --isolate-only
```
**Checkpoint:** show `work/models/<slug>/01_isolated.png` to the developer (open/attach the
image, or give the path if the client cannot display images) and ask whether the subject is
cleanly cut out. Ground, plinths or props left in the cut-out become geometry. If it is not
clean, crop or edit the input (or use `--skip-rembg` with a prepared PNG) and repeat.

```text
rgm build --name <slug> --reuse-isolated --backend <b> --target-tris <n> --height-studs <h> \
  --rig-type <r> --output-target <studio|blender> --texture <none|hunyuan|studio>
```
- Outputs: `assets/models/<slug>/<slug>.blend`, `<slug>_static.fbx`, optional `_rigged.*`,
  `manifest.json`. Scratch: `work/models/<slug>/` (git-ignored).
- Exit code 2 means the mesh missed the triangle budget: do not import; report it.
- Re-run only the Blender stage with `--input-mesh work/models/<slug>/02_raw_mesh.glb`.
- After a run, render or `look` at the result before calling it done (VERIFIED needs eyes).

## Output

- **Blender only:** deliver the `.blend` path and a preview render; stop there.
- **Studio:** follow [references/pipeline-and-import.md](references/pipeline-and-import.md).
  Import needs Studio's File -> Import 3D UI (no scripting API) via computer use, or the
  developer does it manually. Importing **uploads the mesh to the developer's Roblox account**
  as a private asset; say so before clicking Import. Then verify size against `manifest.json`.
- **Studio texture:** MCP `generate_texture` on the imported MeshPart, then the rescale
  fix-up in pipeline-and-import.md (the tool returns the mesh ~4x larger and moved).

## Pipeline stages

| Stage | Where | Notes |
| --- | --- | --- |
| 1 Isolate | model server (`rembg`) | 1024x1024 alpha PNG; checkpoint above |
| 2 Image-to-3D | model server (Hunyuan3D-2 / TripoSR) | optional local Hunyuan3D-Paint texture |
| 3 Cleanup | headless Blender ([blender_process.py](scripts/blender_process.py)) | repeats decimation until within budget; bottom-centre pivot; 1 m = 1 stud |
| 4-5 Rig/animate | headless Blender ([blender_rig_and_animate.py](scripts/blender_rig_and_animate.py)) | template rigs, baked `Idle`/`Walk` |
| 6 Import | Studio (computer use or developer) | see Output |

## Reference index

- [references/setup.md](references/setup.md): native uv install (Windows, Linux, macOS), Docker CUDA, Blender MCP, Codex/Claude MCP config.
- [references/models.md](references/models.md): model catalog, VRAM needs, what is integrated.
- [references/pipeline-and-import.md](references/pipeline-and-import.md): outputs, Studio import, texture fix-up, troubleshooting.
- [containers/](containers/): `server.py`, pinned `constraints.txt` / `requirements.txt`, `Dockerfile.cuda`, `docker-compose.yml`.
