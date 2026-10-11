---
name: roblox-blender
description: "Create, edit, rig, animate or import custom Blender models for Roblox. Use for Blender asset authoring and integration; Studio Parts alone do not require it."
---

# Blender models and animations

Blender is the preferred tool for substantial custom 3D models, rigging and animations.
Use simple Roblox Parts or Studio tools when appropriate; choose Blender for work that
benefits from custom modelling, rigging or animation.

For AI-first/shared/developer-led work and creative approvals, use
[roblox-collaboration](../roblox-collaboration/SKILL.md).

When art direction is uncertain, propose one representative asset before batch production
as an experiment in the feature approval, including its purpose, review checkpoint and
pending variants. Complete and inspect that asset at the intended in-game light and scale
before making variants. Reuse suitable project materials, rigs and components, and batch
related exports/imports. Continue variants and polish within the approved art direction.

Keep the .blend file as the editable source of truth, including rigs and animation actions.
Preserve an original/version before edits. Keep editable sources separate from export copies.
Help diagnose modelling, shading, UV, texture, rigging, weight-painting and animation issues
without making them responsible for technical troubleshooting.

Use Blender's scripting API or available screen control after checking the installed version
and actual capabilities. Blender MCP is optional. Do not claim integration is configured or
working until tested. Install or connect tools only when needed for an actual requested task.

Choose the Roblox movement/animation system before finalizing an animated model;
shape its rig and proportions around that integration. Author pivots, contact/seat
points, simple colliders and required doorway clearances alongside visible geometry.
For Roblox integration, check scale/orientation, normals, topology, UVs/textures,
materials, performance, rig compatibility, skinning and animation export/import.
Export a currently supported format and inspect the import in Studio. Some Blender features
need baking or conversion; preserve the editable original and prepare a suitable export copy.
Imported meshes/scenes remain Studio-owned, outside Rojo's code folders.
Verify appearance, movement and relevant runtime behavior in Roblox before calling work ready.

Use the strongest available reasoning for demanding modelling, rigging and animation;
routine edits need less. Follow project QA and model-change honesty rules.

Official workflow: https://create.roblox.com/docs/art/blender
Importer: https://create.roblox.com/docs/studio/importer
