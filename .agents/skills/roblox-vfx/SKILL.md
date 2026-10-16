---
name: roblox-vfx
description: "Build or tune Roblox lighting, skies, atmosphere, particles, beams, trails and highlights. Use for world mood, reusable effect packs, timed effects, culling and overdraw."
metadata:
  last_reviewed: 2026-06-17
---

# roblox-vfx

**Main sources:** https://create.roblox.com/docs/effects and https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter.

Start with Roblox effect objects and configure their textures, colors and timing for the art direction. Compose world mood with lighting, sky and atmosphere; use emitters, beams, trails and highlights for effects. Custom geometry or visual simulation should fill a specific artistic or behavioral gap. Tune particle lifetime, size, transparency and rate together.

For marker-triggered bursts, read [roblox-animation](../roblox-animation/SKILL.md). For UI particles, read [roblox-user-interfaces](../roblox-user-interfaces/SKILL.md); ParticleEmitters do not render inside ViewportFrame.

## Discover and reuse effect packs

1. Reuse suitable project effects first. When a pack adds value, find a small free kit matching the art direction through official tutorials or the original creator's listing. Confirm authorship and reuse terms; ratings, badges and availability fields are supporting metadata, not proof of rights or safety.
2. Inspect a pinned snapshot with every returned root detached (`Parent = nil`) before insertion or Play. Inventory roots and all descendants, including `LuaSourceContainer`, `PackageLink`, external asset IDs and unexpected services or objects. Read script sources for asset-based `require`, HTTP/loaders and obfuscation as audit data; never execute downloaded code.
3. Extract an explicit allowlist of native visual instances into fresh project-owned presets: emitters, beams, trails, attachments and needed lights/support parts. Copy reviewed properties and rebuild internal references. Keep scripts, package links and unrelated objects out of the extracted hierarchy; re-audit its full tree before parenting it into the game.
4. Record the original listing/creator, snapshot version or file hash, selected instance paths, texture/mesh/audio IDs, reuse terms and modifications in project asset documentation. Pin presets locally and review deliberate updates against this record.
5. Check only selected dependencies with `ContentProvider:PreloadAsync` on their actual instances and record each callback status. Verify experience-owner permissions separately; Studio loading alone does not establish published-client access. Prefer a known accessible fallback when a dependency fails.
6. Adapt color, scale, lifetime, rate and motion to the scene. Use finite `Rate = 0` bursts with cleanup for events and sparse nearby emitters for ambience. Preserve day/night readability, existing gameplay/purchase contracts and local culling/quality budgets.
7. Show a representative in-world day/night sample at an agreed review checkpoint before broad rollout. Reuse existing approval when it covers the sample and rollout; verify visual fit, cleanup, distance culling and relevant multiplayer timing. Label pending owner-permission and device/performance checks UNVERIFIED.

Official references: [asset permissions](https://create.roblox.com/docs/projects/assets/privacy), [packages](https://create.roblox.com/docs/projects/assets/packages), [ContentProvider](https://create.roblox.com/docs/reference/engine/classes/ContentProvider).

## Lighting, sky and atmosphere

- Compose `Lighting` time, ambient light, exposure and `LightingStyle` with the art direction.
- Use `Sky` under Lighting for the skybox/sun/moon/stars, `Atmosphere` for haze and distance, and `Clouds` under Terrain for cloud cover.
- Use local lights to illuminate surroundings and restrained `BloomEffect` for glow; keep play areas and interaction targets readable indoors and at night.
- For day/night cycles, coordinate lighting, sky and atmosphere from a shared clock; blend numeric and color transitions.

Official environment guide: https://create.roblox.com/docs/environment

## Core creation and parenting

- Parent ParticleEmitter to a BasePart (emission fills bounds or chosen EmissionDirection face) **or** (strongly preferred for control) to an Attachment.
- Rotate the parent or the attachment to steer emission. EmissionDirection is ignored when parented to an Attachment; rotate the Attachment itself to aim particles.
- EmissionDirection only matters when parented to a part.

## Tune particle appearance

1. Texture (prefer .png with alpha; grayscale + LightEmission=1 to hide dark areas).
2. Color (ColorSequence; even a single Color3 in Studio is stored as a one-keypoint ColorSequence; use it for gradients over lifetime).
3. Size (NumberSequence, often with envelope for natural variation). **Warning:** Large sizes = high GPU fill-rate cost.
4. Transparency (NumberSequence). Fade particles in or out to avoid popping.
5. Lifetime (or NumberRange for per-particle random).
6. Rate (particles per second; hard caps ~400 desktop / 100 mobile per emitter; keep low and achieve density with other properties).

Then motion (Speed at birth, SpreadAngle, Acceleration for gravity/wind, Drag + WindAffectsDrag when global wind is enabled, VelocityInheritance, LockedToPart, TimeScale).

## Emitter shapes

Shape = Box / Sphere / Cylinder / Disc.
- ShapeStyle = Volume (everywhere inside) or Surface (only the skin).
- ShapeInOut = Inward / Outward / InAndOut.
- ShapePartial further modulates the shape. Cylinder: radius on the emission side. Disc: inner-radius proportion (`0` = fully closed disc, `1` = emission only on the outer rim). Sphere: hemispherical angle (`1` = full sphere, `0.5` = half-dome, `0` = point).

Sphere/Cylinder shapes do **not** display correctly when the emitter is parented to an Attachment. Only use them with a BasePart parent (the part can be tiny and invisible).

## Flipbooks (animated textures over particle life)

Prepare a grid sheet (2x2, 4x4, 8x8, Custom) with transparent spacing between frames (to prevent mip filtering from sampling adjacent frames).
- FlipbookLayout, FlipbookSizeX/Y.
- FlipbookFramerate (or random range, max 30).
- FlipbookMode: Loop, OneShot (explosions; ignores `FlipbookFramerate` and plays exactly once over the particle Lifetime), PingPong, Random (with crossfade; great for organic variation).
- FlipbookBlendFrames: crossfade between adjacent frames in Loop/OneShot/PingPong for smoother animation.
- FlipbookStartRandom: each particle starts at a random frame (useful when framerate is 0 for static but varied look).

**Memory warning:** Flipbooks are heavier. Reuse textures, keep resolution reasonable, limit unique animated emitters on low-memory clients (older phones will auto-disable flipbooks).

## Lighting and rendering controls

- LightEmission: 0 normal, 1 additive/glow (works even in dark scenes).
- LightInfluence: 0 = ignore world light, 1 = fully affected.
- Brightness: scales the light the emitter contributes when `LightInfluence` is 0. No effect when `LightInfluence` is 1.
- Orientation: FacingCamera (classic billboard), FacingCameraWorldUp, VelocityParallel, VelocityPerpendicular.
- ZOffset: render layer offset in studs (layer multiple emitters without moving them in 3D).

## Performance across devices

- Fill rate (pixels covered by overlapping transparent layers) and overdraw are the main GPU costs.
- Rate × Size × average opacity × how many overlap on screen = cost.
- Inspect changed effects during iteration; complete low/high-quality device checks before release. Profile earlier when effect density or observed frame time warrants it.
- Mobile rate is capped lower.
- Use .Enabled = false to pause (existing particles continue until they die or you call :Clear()).
- Many simultaneous high-rate/large/transparent emitters will cause the engine to throttle or drop effects on low-end clients.
- Measure overdraw in Studio with **View → Stats → GPU → Fill Rate** and **Render → Overdraw**. Reduce total opaque pixel area before lowering Rate.

## Replication and client-authoritative emission

- ParticleEmitter state replicates, but individual particles do not. A server-owned emitter will spawn the same particles on every client automatically.
- For one-shot bursts, prefer **client-authoritative emission**: the server signals an event, each affected client spawns the burst locally. This avoids network replication of per-burst timing and respects each client's quality settings.
- Use `RemoteEvent:FireClient` or a local signal so clients own transient visuals; keep gameplay logic authoritative on the server.

## LOD and distance culling

- Stop or reduce expensive emitters when the camera is far away. Common thresholds: disable at 100–300 studs, reduce Rate by half at half-distance.
- Use `workspace.CurrentCamera` distance checks or zone systems. Avoid per-frame `Magnitude` checks for many emitters; instead use a tagged culling heartbeat or spatial partition.
- For ambient weather/large crowds, spawn emitters only in the near-camera region rather than globally.

## Preloading textures

- Preload selected emitter/beam/trail instances with `ContentProvider:PreloadAsync` before prominent effects are needed; inspect callback statuses and provide a fallback for failed dependencies. This reduces mid-burst pop-in without loading an entire pack.

## Effect selection and timing

- `Sparkles`, `Fire` and `Smoke` offer simple built-in looks; choose `ParticleEmitter` for authored textures, motion or precisely timed bursts.
- For footsteps or hoofbeats, emit small dust/sparkle bursts at contact attachments, timed by animation markers. Use `Trail` for a continuous movement ribbon and scale emission with speed.
- For growth or other milestones, set `Rate = 0` and use a brief `ParticleEmitter:Emit()` burst timed to the confirmed state transition; blend model changes with `TweenService` through roblox-animation.
- For ambient magic, fireflies or drifting leaves, use low-rate emitters in nearby zones with varied lifetime and motion. Use `Beam` for directed energy and `Highlight` for selection feedback.
- For wind-reactive particles, enable global wind, set Drag > 0 and WindAffectsDrag = true.

See the references/ folder (particle-emitter-properties.md, shapes-flipbooks-and-advanced.md) for the exhaustive property reference, visual examples, optimization checklists, and concrete code for common effects (integration covered in SKILL and cross-skill notes).

## Related effects (often used alongside particles)

- Beam: textured ribbon between two Attachments (lasers, energy, ropes). Key properties: `Texture`, `TextureMode`/`TextureLength`/`TextureSpeed`, `Color`, `Transparency` (NumberSequence along the beam), `Width0`/`Width1`, `CurveSize0`/`CurveSize1`, `FaceCamera`, `LightEmission`, `LightInfluence`, `ZOffset`.
- Trail: ribbon left behind two Attachments as their parent part moves (sword trails, projectile paths, after-images). Key properties: `Color`, `Transparency`, `Texture`, `TextureMode`, `TextureLength`, `MinLength`, `MaxLength`, `WidthScale`, `LightEmission`, `LightInfluence`, `FaceCamera`, `Lifetime`.
- Highlight: cheap, effective outlines (selection, targeting, "powered up"). Has both an outline and a solid interior fill (`FillColor`/`FillTransparency`, `OutlineColor`/`OutlineTransparency`). `DepthMode` controls whether the highlight is visible through walls (`AlwaysOnTop`) or only when not occluded (`Occluded`). There is a client-side cap of 255 simultaneous `Highlight` instances (disabled instances still count toward the cap).
- PointLight / SpotLight / SurfaceLight for localized illumination; coordinate them with the environment above.

## Cleanup for transient emitters

- Always destroy cloned one-shot emitters after their maximum lifetime (`Debris:AddItem` or `task.delay`). Do not leave disabled emitter instances accumulating in the workspace.
- For attached continuous emitters, set `Enabled = false` and `:Clear()` before reparenting or destroying to avoid orphaned particles.
- When pooling emitters, reset Rate, Lifetime, Size, and Transparency to known defaults before reuse so stale state does not leak into the next burst.

## Scripts

- `scripts/EffectBurst.lua`: clone-and-destroy helper for one-shot particle bursts. Clones every ParticleEmitter under a template Attachment/BasePart, emits a burst locally, and schedules cleanup after the maximum lifetime. Safe for continuous emitters because the original emitters are never mutated.

<!-- catalog:references:start -->
## Reference index

- [particle-emitter-properties.md](references/particle-emitter-properties.md): Tune particle appearance, motion, emission, or rendering cost.
- [shapes-flipbooks-and-advanced.md](references/shapes-flipbooks-and-advanced.md): Configure emitter shapes, animated textures, bursts, or distance culling.
<!-- catalog:references:end -->
