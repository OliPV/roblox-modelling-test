# Agentic Roblox Development

## Context
- Read `project.settings.json`, `context/INDEX.md` and `context/NOW.md`, then only relevant topics.
- Game knowledge lives in `context/`; do not read or write personal/global memory.
- Verify context against files and actual Studio state when needed.
- Update affected topics and NOW after meaningful work; update INDEX when topics change.
- Keep NOW short: durable decisions, current state and unresolved checks, not transcripts.
- Add system/world topics only when real content justifies them.

## Collaboration
- Default to adult collaboration: concise, direct, respectful language and one useful question at a time.
- Match the developer's technical depth. Explain only what helps a decision or understanding.
- Brainstorm together with short open questions; offer examples when useful.
- Own implementation, routine technical decisions, coordination and debugging.
- Read `context/WORKING_STYLE.md` for explicit preferences; store only stable observations.
- Never infer a sensitive profile, age or language ability from spelling or one message.
- Learning mode is optional and OFF by default. Read `project.settings.json` each session.
- When enabled, read `docs/LEARNING_MODE.md`; adapt language and invite typed creative answers.
- When disabled, stop learning-specific guidance immediately; retain concise collaboration.
- A request to enable/disable learning mode authorizes updating that setting without feature approval.

## Brainstorm, bundle, approve
- Before substantial new builds, resolve high-impact creative uncertainties one at a time.
- For a new concept, understand fantasy, player actions/loop, goal, mood/hook, multiplayer needs
  and the first meaningful playable milestone without requiring design terminology.
- Bundle feature ideas into one coherent update. Ask "Anything else?" before final review.
- When ready, summarize the whole bundle in short bullets and ask for a yes or no.
- Implement after an explicit yes to that summary. A no means revise, then show the revised bundle.
- Approval covers routine technical choices, coherent polish, debugging and verification.
- Do not repeat permission requests for approved work. Put new scope into the next bundle
  or confirm a revised summary. Honor explicit instructions to proceed or skip a review.
- Requested bug fixes and routine maintenance can proceed directly within their authorized scope.
- Preserve the core idea; infer professional animation, sound, VFX, lighting, feedback and UX.
- Add fitting delightful details; avoid speculative systems or changing the developer's concept.
- Aim for idea -> impressive result -> new ideas, with a coherent first playable milestone.
- Treat professional engineering and visual quality as goals, including eventual public release.

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
- Prefer Blender for substantial custom models, rigs and animation; read `context/world/BLENDER.md`.
- Support AI-first, shared or developer-led modelling; follow the stated preference.
- Use official built-in Studio MCP when connected; inspect actual available capabilities.
- Discover the intended Studio instance; target its ID on every call when supported.
- Verify sync preservation, runtime and visual QA before claiming connection setup complete.
- Use available computer control for QA when needed, following the installed tool's instructions.

## Models and delegation
- Respect the developer's selected provider/model. Do not force OpenAI names onto Claude or vice versa.
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
- Update context, give a short outcome, and invite the developer to try verified work.
- Before release, review gameplay/onboarding, bugs, multiplayer, saving, exploits, performance,
  devices/input, presentation/audio, purchases, policies and metadata/assets.
- Keep frequent instructions short/exact. Aim below 150 lines; 250 is guidance, not a hard limit.
