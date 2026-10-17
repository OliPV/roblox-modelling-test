# Curated local models for Roblox 3D generation

Why local specialist models instead of LLM mesh code?
LLMs excel at orchestrating pipelines and writing Blender Python (`bpy`) scripts, but cannot directly output dense, organic, textured 3D meshes. Dedicated vision-to-3D diffusion and transformer models produce high-detail geometry and PBR textures from a single reference image in seconds.

## 1. Stage 1 — Background Removal & Subject Isolation

Input images from Midjourney, Flux, ChatGPT or concept art often contain backgrounds or gradients that confuse 3D reconstruction.

| Model | Package | Hardware | Why use it |
| --- | --- | --- | --- |
| **BiRefNet** (`birefnet-general`) | `rembg` | 2 GB VRAM / CPU / MPS | Crisp silhouette extraction around weapons, hair, fur and thin straps |
| **U2Net** (`u2net`) | `rembg` (default) | 500 MB RAM | Instant fallback on CPU or low-memory machines |

**Best input image traits for 3D:**
- Single object or character in **front 3/4 view** (or T-pose / A-pose for characters).
- No ground shadow or cropped feet/tips.
- Even, neutral studio lighting (strong directional shadows bake dark patches into the albedo texture).

---

## 2. Stage 2 — Single-Image to 3D Mesh & Textures

| Model | Source | VRAM / Unified RAM | Speed | Strengths for Roblox |
| --- | --- | --- | --- | --- |
| **Hunyuan3D-2 / 2mini** (Default Primary) | `Tencent/Hunyuan3D-2` | 12 GB VRAM (`2mini`: 6–8 GB) / 24 GB+ Mac MPS | 15–45 s | Best overall watertight SDF mesh (`Hunyuan3D-DiT`) + clean multi-view PBR texture synthesis (`Hunyuan3D-Paint`). |
| **TRELLIS** (`TRELLIS-image-large`) | `JeffreyXiang/TRELLIS` | 16 GB+ NVIDIA VRAM | 20–50 s | Structured 3D latents (`SLAT`) produce sharp hard-surface edges (vehicles, sci-fi props, armor, architecture). Requires NVIDIA CUDA. |
| **TripoSR** (Default Fast Fallback) | `VAST-AI-Research/TripoSR` | 4–6 GB VRAM / 16 GB Mac MPS | 2–6 s | Ultra-fast feed-forward transformer. Outputs vertex colors (baked to UV texture in Stage 3). Great for rapid iteration and stylized props. |
| **SF3D (Stable Fast 3D)** | `Stability-AI/stable-fast-3d` | 6–8 GB VRAM / 16 GB Mac MPS | 3–8 s | Fast feed-forward mesh with built-in UV unwrapping and delighting (removes baked shadows from albedo). |

### Selection guide
- **Use `hunyuan3d`** (`Hunyuan3D-2` / `2mini`) as the default for production props, weapons, monsters and NPCs on both Windows (CUDA) and high-memory Macs (MPS).
- **Use `triposr`** when iterating rapidly on blockouts, running on 8 GB GPUs / 16 GB Macs, or generating simple background props.

---

## 3. Stage 3 — Retopology, UV & PBR Baking

AI-generated meshes are typically dense triangle soups (`50,000`–`250,000` triangles) with arbitrary orientation and scale.

- **Tool:** **Blender 4.2+ Headless (`bpy`)** via [`scripts/blender_process.py`](../scripts/blender_process.py).
- **Operations performed automatically:**
  1. Merge duplicate vertices (`remove_doubles`), delete loose geometry and recalculate outward normals.
  2. Planar/quad decimation down to the target Roblox budget (default `6,000` triangles; hard Roblox limit is **`10,000` triangles per MeshPart** for general imports, or **`4,000` triangles** per accessory/avatar part).
  3. Normalize scale so bounding-box height (or longest axis) matches `--height-studs` (`1 Blender meter = 1 Roblox stud` on standard FBX export).
  4. Place pivot at bottom-center `(0, 0, 0)` facing `-Y` in Blender (which exports to `-Z` `LookVector` in Roblox).

---

## 4. Stage 4 — Rigging & Skinning

Roblox supports two main rig styles:
1. **Skinned Mesh (`Bone` hierarchy inside a single or multi-part `MeshPart`)** — smooth organic deformation for creatures, monsters, clothing and modern characters.
2. **Rigid Part Hierarchy (`Motor6D` joints between separate `MeshPart`s)** — classic R6/R15 characters or procedural rigs like [`roblox-horse`](../../roblox-horse/SKILL.md).

| Method | Best for | How it works in this skill |
| --- | --- | --- |
| **Blender Template Projection** (`--rig-type humanoid` / `quadruped` / `prop`) | Biped NPCs, four-legged mounts/pets, weapons/chests | [`scripts/blender_rig_and_animate.py`](../scripts/blender_rig_and_animate.py) fits a proportion-matched Roblox bone hierarchy (`RootPart`, `LowerTorso`, `UpperTorso`, `Head`, limbs) to the mesh bounding volume and binds skin weights using Blender's heat/envelope solver. |
| **UniRig** (`VAST-AI-Research/UniRig`) | Non-standard creatures (dragons, spiders, tentacles, multi-limbed bosses) | Autoregressive transformer predicts custom bone topology and skinning weights directly from the Stage 3 mesh. |

---

## 5. Stage 5 — Animation

| Method | Best for | How it works |
| --- | --- | --- |
| **Procedural Blender Action Generator** (Built-in default) | Immediate verified `Idle`, `Walk`, `Attack` or `Float` loops | [`scripts/blender_rig_and_animate.py`](../scripts/blender_rig_and_animate.py) synthesizes clean, loopable keyframe `Action` clips (`Idle`, `Walk`) in the NLA/Action editor and bakes them into the exported `.fbx`. |
| **Mixamo / `.bvh` Retargeting** | Rich humanoid locomotion, combat and emotes | Pass a local `.fbx` or `.bvh` motion clip to `--retarget-motion` to transfer bone rotations onto the humanoid armature in headless Blender. |
| **Roblox Runtime Procedural / IK** | Ground-adaptive mounts, vehicles, look-at targets | Skip baked clips and drive `Motor6D` / `Bone` transforms or `IKControl` in Luau (see [`roblox-animation`](../../roblox-animation/SKILL.md) and [`roblox-horse`](../../roblox-horse/SKILL.md)). |
