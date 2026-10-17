# End-to-end workflow & Roblox Studio import

## 1. Triggering from Codex or Claude Code

Both Codex and Claude Code discover `roblox-model` automatically (Codex via `.agents/skills/roblox-model/SKILL.md`, Claude Code via `.claude/skills/roblox-model/SKILL.md`). Developers can also invoke `/roblox-model` directly.

### Typical agent workflow

1. **Clarify the asset brief:**
   - Input image path (e.g., `work/inputs/dragon_concept.png`).
   - Asset category:
     - `static` — props, weapons, environment pieces, buildings (`--rig-type none`).
     - `prop` — single-bone / hinged interactables like chests, doors, floating pickups (`--rig-type prop`).
     - `humanoid` — biped NPCs, enemies, characters (`--rig-type humanoid`).
     - `quadruped` — four-legged pets, beasts, mounts (`--rig-type quadruped`).
   - Target size in Roblox studs (`--height-studs`, e.g., `5.0` for a character, `4.0` for a sword, `12.0` for a boss).
   - Triangle budget (`--target-tris`, default `6000`, always `< 10000` per mesh).

2. **Execute the local pipeline:**
   ```bash
   python .agents/skills/roblox-model/scripts/run_pipeline.py build \
     --input assets/concepts/dragon_concept.png \
     --name fire_drake \
     --backend hunyuan3d \
     --target-tris 7500 \
     --height-studs 8.0 \
     --rig-type quadruped \
     --animate idle,walk
   ```

3. **Review generated outputs in your game repository:**
   - **Project deliverables in `assets/models/<name>/`** (or custom `--output-dir`):
     - `<name>.blend` — Editable Blender source of truth (decimated, scaled, normals fixed).
     - `<name>_static.fbx` — Static Roblox-ready FBX.
     - `<name>_rigged.blend` — Editable rigged & animated Blender source of truth (when `--rig-type` is used).
     - `<name>_rigged.fbx` — Skinned FBX with baked animation actions (`Idle`, `Walk`).
     - `manifest.json` — Summary of triangle counts, bounding box in studs, bone count, and baked animation names.
   - **Intermediate scratch files in `work/models/<name>/`** (git-ignored):
     - `01_isolated.png` — Background-stripped square reference image.
     - `02_raw_mesh.glb` — Unprocessed dense mesh from the local AI model.

---

## 2. Roblox Mesh & Rig Constraints Checked by the Pipeline

| Constraint | Roblox Engine Limit | Pipeline Default |
| --- | --- | --- |
| **Max triangles per MeshPart** | `10,000` (`20,000` in some beta importers, `4,000` for Avatar accessories) | `6,000` (`--target-tris`) |
| **Max bones per Skinned Mesh** | `256` bones | `15`–`25` bones |
| **Max texture resolution** | `1024x1024` (automatically downsampled by Roblox if larger) | `1024x1024` PNG |
| **Coordinate system & scale** | `1 stud` unit, `-Z` forward (`LookVector`), `+Y` up | `1.0` scale factor (`FBX_SCALE_ALL`), `-Z` forward, `+Y` up, bottom-center at `(0,0,0)` |

---

## 3. Importing into Roblox Studio

Remember project ownership rules (`AGENTS.md`):
- **Meshes, models and scenes belong in Studio** (outside Rojo's `src/server`, `src/client`, `src/shared` code folders).
- Keep `.blend`, `.glb` and `.fbx` files in `work/models/<name>/` (ignored by Git unless deliberately versioned for a specific game).

### Path A: Interactive / Assisted Studio 3D Importer (Recommended for visual QA)

1. In Roblox Studio, select **File -> Import 3D** (or **Avatar -> Import 3D**).
2. Pick `work/models/<name>/03_static.fbx` (or `05_rigged_animated.fbx`).
3. Verify Importer settings:
   - **Scale Unit:** Studs (dimensions in the preview should match `--height-studs`).
   - **Rest Pose / Rig Type:** If importing a skinned rig, ensure **Import As Model** and **Rig Type: Custom / R15** are active.
   - **CollisionFidelity:** Choose `Box` or `Hull` for moving characters/small props (`Default` or `PreciseConvexDecomposition` only for walkable large terrain/structures).
4. Click **Import** and place the model in `Workspace` or `ServerStorage.Assets`.

### Path B: Open Cloud Assets API + Studio MCP Placement (Automated)

If the project has Open Cloud configured ([roblox-open-cloud](../../roblox-open-cloud/SKILL.md)):
1. Upload the `.fbx` via the Open Cloud Assets API (`https://apis.roblox.com/assets/v1/assets` with `assetType: "Model"`).
2. Poll the operation until the `assetId` is returned.
3. If Studio MCP is connected ([roblox-mcp](../../roblox-mcp/SKILL.md)), insert and inspect the imported model in the active Studio session, configure `SurfaceAppearance` if separate PBR maps were generated, and capture the viewport to verify appearance.

### Playing Baked Animations on Imported Skinned Rigs

When `05_rigged_animated.fbx` is imported via the 3D Importer:
1. Open the **Animation Editor** in Roblox Studio and select the imported rig.
2. Click **... -> Import -> From FBX Animation** and select `05_rigged_animated.fbx` to load the `Idle` or `Walk` track, then **Publish to Roblox** to get an `rbxassetid://`.
3. Play the animation at runtime via an `Animator` inside an `AnimationController` (for non-humanoid rigs) or `Humanoid` (see [roblox-animation](../../roblox-animation/SKILL.md)).
