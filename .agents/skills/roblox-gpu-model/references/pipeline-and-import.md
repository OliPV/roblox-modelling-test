# Pipeline outputs, Studio import and texturing

## 1. Outputs

| Location | Files | Git |
| --- | --- | --- |
| `assets/models/<name>/` (or `--output-dir`) | `<name>.blend` (editable source), `<name>_static.fbx`, `<name>_rigged.blend` + `<name>_rigged.fbx` (when rigged), `manifest.json` | `*.blend` is ignored by the template `.gitignore`; opt in per game (Git LFS) when versioning sources |
| `work/models/<name>/` | `01_isolated.png`, `02_raw_mesh.glb` (dense raw AI mesh, often 1M+ triangles) | ignored (`work/`) |

`manifest.json` records `initial_triangles`, `final_triangles`, `target_triangles`,
`within_budget`, `roblox_limit_ok`, `decimate_passes`, `size_studs_xyz` (X, Y-up, Z in studs),
plus the build options (`backend`, `texture`, `output_target`, `rig_type`) and rig/animation data.

`build` exits with code 2 when the mesh is over budget; never import such a mesh.

## 2. Roblox constraints checked

| Constraint | Roblox limit | Pipeline default |
| --- | --- | --- |
| Triangles per MeshPart | 10,000 (4,000 for avatar accessories) | 6,000 (`--target-tris`) |
| Bones per skinned mesh | 256 | 15-25 |
| Texture resolution | 1024x1024 (larger is downsampled) | 1024x1024 |
| Scale and axes | 1 stud; +Y up; -Z forward | 1 Blender metre = 1 stud; bottom-centre pivot at origin |

## 3. Studio import

Meshes are Studio-owned content (outside Rojo's `src/` folders). Studio's MCP and plugin Luau
cannot reach the 3D importer (`AssetImportService` is not scriptable), so import goes through
the UI: with computer use (request access to Roblox Studio), or by the developer.

1. Bring the place window forward. Studio may also have its start-page window open; target the
   window titled `<place> - Roblox Studio` (maximise it if small).
2. **Home** tab -> **Import** (or File -> Import 3D) opens a file dialog. Type the full path of
   `assets/models/<name>/<name>_static.fbx` (or `_rigged.fbx`) into the file name box -> Open.
3. **Import Preview**: check the preview, keep **Import Only as a Model** and **Add to Workspace**,
   set scale to studs if offered. **Upload to Roblox** is on by default and is required for a
   MeshPart: it uploads the mesh to the developer's account as a private asset. Tell the
   developer before clicking **Import**, especially for IP-derived or sensitive content.
4. Wait for the Import Queue to show a green tick. The model lands as
   `Workspace.<name>_static` containing a MeshPart named `RobloxAsset`.
5. Verify with Studio MCP (`execute_luau`, `datamodel_type: Edit`): size equals
   `size_studs_xyz` from the manifest; set `Anchored`, and `CollisionFidelity` to `Box` or `Hull`
   for small or moving objects; then `screen_capture` with the camera aimed at the model.

Without computer use (some Codex setups), give the developer steps 2-4 and continue at step 5.

## 4. Texturing options

- **Hunyuan3D-Paint (`--texture hunyuan`)**: texture is baked into the GLB and carried through
  the FBX (`embed_textures`). NVIDIA only; see setup.md.
- **Studio AI texture (`--texture studio`)**: after import, call MCP `generate_texture` with
  `instance_path` = the MeshPart (e.g. `Workspace.<name>_static.RobloxAsset`) and a prompt
  describing colours and materials from the reference image (`model: "Fast"` takes about a minute).
  It replaces the mesh in place but returns it at a different scale (about 3.8x observed) and
  position, so always run this fix-up:
  ```lua
  local part = workspace["<name>_static"].RobloxAsset
  local targetHeight = 3 -- manifest size_studs_xyz[2]
  part.Size = part.Size * (targetHeight / part.Size.Y)
  part.Anchored = true
  local base = workspace:FindFirstChild("Baseplate")
  local groundY = base and (base.Position.Y + base.Size.Y / 2) or 0
  part.Position = Vector3.new(0, groundY + part.Size.Y / 2, 0)
  part.CollisionFidelity = Enum.CollisionFidelity.Hull
  ```
  Then `screen_capture` again. The texture exists only in the place; the `.blend`/`.fbx` in
  `assets/` stay untextured, so record that in context.
- **None (`--texture none`)**: colour or material the MeshPart in Studio, or texture in Blender.

## 5. Blender-only target

With `--output-target blender`, deliver `assets/models/<name>/<name>.blend` and a preview render
(Blender MCP `look`/viewport screenshot, or a headless Workbench render). Skip section 3.

## 6. Animations on rigged imports

Import `<name>_rigged.fbx` with the importer's rig options. In the Animation Editor use
**Import -> From FBX Animation** to load `Idle`/`Walk`, publish to get an `rbxassetid://`, and
play it through an `Animator` under an `AnimationController` (non-humanoid) or `Humanoid`
(see [roblox-animation](../../roblox-animation/SKILL.md)).

## 7. Automated upload (optional)

With Open Cloud configured ([roblox-open-cloud](../../roblox-open-cloud/SKILL.md)), upload the FBX via
the Assets API (`assetType: "Model"`), poll for the `assetId`, then place it with Studio MCP
`insert_asset` and verify as in section 3, step 5.
