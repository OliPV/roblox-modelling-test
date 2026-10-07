# Agentic Roblox Development

A reusable starting point for Roblox development with ChatGPT/Codex and Claude Code.
No game code, scenes, assets or previous project's history are included.

The workflow is simple: brainstorm together, bundle ideas, review short bullets, approve,
build with polish, playtest, and keep concise project context for the next session.
The assistant owns technical work and debugging; the developer owns the creative direction.

## Start a new game

1. Use this repository as a starting point: clone it or copy it into a new game repository.
2. Open that folder in Codex or start Claude Code there. Trust project files as appropriate.
3. Tell the assistant your game idea, for example:
   "Let's brainstorm a co-op exploration game. Help me shape the first playable update."
4. Follow [SETUP.md](docs/SETUP.md) for local tools, Studio and optional MCP connections.

Codex reads [AGENTS.md](AGENTS.md) and discovers `.agents/skills`.
Claude Code reads [CLAUDE.md](CLAUDE.md), which imports the same rules, and discovers
`.claude/skills` adapters pointing at the canonical skills. References work on Windows and macOS without symlinks, administrator rights or duplicated manuals.
Ordinary ChatGPT needs a coding/work environment with filesystem/tool access; a browser chat
alone does not load repository instructions or control Studio.

## Adult by default; learning when wanted

Adult collaboration is concise and direct. Both modes keep brainstorming and bundle approval.
Learning support is OFF in the [collaboration skill settings](.agents/skills/roblox-collaboration/settings.json).
Say "Enable learning mode" or "Disable learning mode", or change `learningMode` yourself.
The optional mode supports reading/writing through creating games, without formal lessons.
All response and approval rules live in [roblox-collaboration](.agents/skills/roblox-collaboration/SKILL.md).

## Included

- Root expectations, dedicated collaboration/Blender skills and fresh `context/` memory files.
- 16 Roblox specialist skills covering core, networking, NPCs, physics, UI, animation,
  VFX, audio, persistence, purchases, teleporting, Open Cloud, Rojo, MCP and testing.
- Empty server/client/shared code folders and a narrow Rojo map preserving Studio content.
- Pinned local tooling, formatting/lint settings, tool bootstrap and safe skill updater.
- Blender collaboration guidance, runtime/visual QA rules and template validation.

Start with `scripts/dev.ps1 check` after installing tools. It validates the empty code layout;
it is not evidence that Studio is connected or gameplay has been playtested.
Machine connections and model selection stay local. Large assets/places/exports are ignored
by default; each real game can explicitly decide which of its assets to version.

## Maintenance

PowerShell 7 is used by the helper scripts (Windows setup is documented).
Run `./scripts/validate-template.ps1` to check skills, adapters, links and configuration.
Run `./scripts/sync-claude-skills.ps1` after changing a canonical skill's discovery metadata.
Run `./scripts/update-skills.ps1` only when you want to update upstream skills.

## Sources and license

Skill discovery follows [official Codex guidance](https://learn.chatgpt.com/docs/build-skills)
and [official Claude Code guidance](https://code.claude.com/docs/en/skills).
The shared import follows [Claude's memory documentation](https://code.claude.com/docs/en/memory).
This template uses the MIT license; vendored skill attribution is in
[THIRD_PARTY.md](docs/THIRD_PARTY.md) and [roblox-suite.LICENSE](docs/roblox-suite.LICENSE).
