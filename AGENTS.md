# Agentic Roblox Development

## Context
- Read `context/INDEX.md` and `context/NOW.md`, then only relevant topics.
- `context/` holds game knowledge, recorded decisions and observations, never instruction manuals.
- Do not read or write personal/global memory; reusable instructions belong in skills.
- Verify context against files and actual Studio state when needed.
- Update affected topics and NOW after meaningful work; update INDEX when topics change.
- Keep NOW short: durable decisions, current state and unresolved checks, not transcripts.
- Add system/world topics only when real content justifies them.

## Collaboration
- Always use [roblox-collaboration](.agents/skills/roblox-collaboration/SKILL.md).

## Impress
- Treat the request as the minimum creative requirement; preserve the developer's core idea.
- Infer professional animation, sound, VFX, feedback, lighting, UI and delightful details
  where they strengthen the idea. Do not require the developer to specify these details.
- A technically correct but dull result is insufficient. Aim for idea -> impressive result -> new ideas.
- Keep the first milestone coherent and playable; avoid speculative systems or replacing the idea.
- Aim for professional engineering and visual quality, including eventual public release.

## Skills and ownership
- Read `.agents/skills/roblox/SKILL.md` as router; load only relevant specialists/references.
- Authority: current official Roblox docs/API, relevant skill, project conventions, model knowledge.
- Adapt and test bundled examples; never execute setup/example scripts blindly.
- Rojo owns `src/server`, `src/client`, `src/shared` -> GameServer/GameClient/GameShared.
- Edit managed scripts on disk, never their Studio copies through MCP.
- Rojo replaces Script Sync here; never enable both for these folders.
- Studio owns scenes, models, graphics and unmapped content. Preserve manually made work.
- Never expand ownership to all Workspace, StarterGui or ServerStorage without a concrete need
  and an approved migration; inspect conflicts and back up relevant content first.
- Keep unknown-instance preservation enabled. Bind Rojo only to `127.0.0.1`.
- Use `scripts/dev.ps1` for pinned project tools/checks; see `docs/SETUP.md`.
- Prefer Blender for substantial custom models, rigs and animation; read
  [roblox-blender](.agents/skills/roblox-blender/SKILL.md).
- For horses or other rideable four-legged mounts, start from
  [roblox-horse](.agents/skills/roblox-horse/SKILL.md).
- Use official built-in Studio MCP when connected; inspect actual available capabilities.
- Discover the intended Studio instance; target its ID on every call when supported.
- Verify sync preservation, runtime and visual QA before claiming connection setup complete.
- Use available computer control for QA when needed, following the installed tool's instructions.

## Models and delegation
- Respect the developer's selected model and use the provider's available controls.
- Use a capable default; increase available reasoning for difficult debugging, architecture,
  networking, persistence, security, monetization and substantial refactoring.
- Use the strongest available reasoning for demanding modelling, rigging and world/visual builds;
  routine transforms and simple Parts do not require it.
- Change models/effort only through actual available controls; never claim an unperformed change.
- Delegate only separable work when permitted and useful, normally at most two subagents.
- Keep writes separate; the main agent integrates and verifies. No context-only delegation
  or custom routing infrastructure. Quality takes precedence over token savings.

## Engineering and boundaries
- Use maintainable Luau, server authority, responsive controls, intentional presentation,
  relevant devices/input, reasonable performance and multiplayer correctness.
- Validate remotes server-side. Clients never authorize currency, inventory, damage, rewards,
  purchases, progression or privileged actions.
- When saving is introduced, isolate test/production data; verify concurrency, failure and retries.
- Inspect third-party assets/scripts; prefer native Roblox and project-owned code.
- Add dependencies only for a clear benefit. Keep credentials and machine-specific paths local.
- Do not spend Robux, alter live player data, or publish a game without explicit authorization.
- Check current policy when monetization/release is requested; never promise income.
- Git/GitHub operations follow the developer's authorization; never commit credentials or
  private assets/context by accident. See `.gitignore` and `docs/SETUP.md`.

## Done means tested
- Run formatting/static checks, then run the game and exercise the changed player experience.
- Read console output; capture and look at useful views. Fix and re-test failures.
- Significant UI needs relevant device sizes/input. Multiplayer needs client/server or
  multi-client checks; solo play and compilation alone are insufficient evidence.
- VERIFIED means runtime behavior exercised and visual work visually inspected.
- If Studio is unavailable, label pending runtime work UNVERIFIED; record checks, never invent evidence.
- Bug reports are evidence: reproduce, inspect, fix the cause, re-test the exact scenario and
  nearby regressions. Ask only the short clarification needed to reproduce.
- Update context after verified work; use the collaboration skill for developer-facing outcomes.
- Before release, review gameplay/onboarding, bugs, multiplayer, saving, exploits, performance,
  devices/input, presentation/audio, purchases, policies and metadata/assets.
- Keep frequent instructions short/exact. Aim below 150 lines; 250 is guidance, not a hard limit.
