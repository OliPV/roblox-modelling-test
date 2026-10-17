---
name: roblox-blender
description: "Create, edit, rig, animate or import custom Blender models for Roblox. Use for Blender asset authoring and integration; Studio Parts alone do not require it."
---

# Blender models and animations

Prefer Blender for substantial custom modelling, rigging and animation. Use simple
Roblox Parts or Studio tools where they fit the asset.
For creative ownership and approvals, use
[roblox-collaboration](../roblox-collaboration/SKILL.md).

When art direction is uncertain, include one representative asset as an experiment
in feature approval: purpose, review checkpoint and pending variants. Inspect it at
the intended in-game light and scale before batch production. Reuse suitable project
materials, rigs and components; continue polish within the approved art direction.

Keep the .blend file as the editable source of truth, including rigs and actions.
Preserve a version before edits and keep editable sources separate from export copies.
For scripted authoring or export, use an isolated background Blender process on
versioned source/export copies, preserving the developer's open GUI document.
Diagnose modelling, shading, UV, texture, rigging and animation issues yourself.

Check installed Blender capabilities before using its scripting API or screen control.
Blender MCP is optional; configure tools only when a requested task needs them and
verify the connection before reporting it ready. Reuse reviewed export helpers and
settings across related assets; batch compatible exports and imports.

For parallel asset work, apply the project's delegation/cost guidance and check actual
agent capacity and local CPU/RAM headroom. Assign independent meaningful assets with
separate files and Blender processes, sharing approved style, palette and export
contract. The main agent coordinates the shared GUI and final Studio integration.

Choose the Roblox movement/animation system before finalizing an animated model;
shape its rig and proportions around that integration. Define model identity, scale,
facing, pivot and applicable rig/bone, seat, muzzle/contact and collider metadata
once alongside the asset; consume it during integration. Author required
doorway clearances with the geometry. Use existing locators, properties or asset
metadata where suitable rather than duplicating values across preparation scripts.

Check scale/orientation, normals, topology, UVs/textures, materials, performance,
rig compatibility, skinning and animation export/import. Choose a currently supported
format for the asset. Bake or convert unsupported features in an export copy while
preserving the editable original. Save and reuse separate Studio import presets for
static and skinned assets where supported; verify textures, mesh separation and rig
hierarchy after import. Imported meshes/scenes remain Studio-owned outside Rojo folders.

Validate the candidate import before replacing known assets. Back up affected content
and reimport only the changed asset, preserving gameplay anchors, placements and
integration settings. Check consumed metadata and affected interactions after replacement.
Inspect appearance at intended light/scale and exercise movement and relevant runtime
behavior in Roblox before calling work ready. Record unavailable Studio checks as
UNVERIFIED. Follow project QA and model-change honesty rules; use strongest available
reasoning for demanding modelling, rigging and animation, less for routine edits.

Official workflow: https://create.roblox.com/docs/art/blender
Importer: https://create.roblox.com/docs/studio/importer
