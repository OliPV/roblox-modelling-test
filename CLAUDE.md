# Claude Code

@AGENTS.md

Use the shared rules above and the same project context/settings as Codex.
Skills are discovered through `.claude/skills/`; each adapter points to its canonical
`.agents/skills/<name>/SKILL.md`. Resolve that skill's relative references against its
canonical directory. Read resources on demand; do not load all skills at startup.
Use available Claude Code tools and models. Codex-specific names/configuration are not
Claude commands. Studio MCP is optional and must be configured on this machine.
