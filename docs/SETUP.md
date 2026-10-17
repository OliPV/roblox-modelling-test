# Setup for a new game

The repository is ready for brainstorming; it contains no game or preconfigured Studio session.
Windows with PowerShell 7 is the documented setup. Roblox Studio also supports macOS;
helper tool lookup supports native executable names there, but macOS setup is not verified here.

## Local tools

Pinned tooling: Rokit 1.2.0; Rojo 7.7.1; StyLua 2.5.2; Selene 0.32.0.
The Windows bootstrap downloads the official Rokit release and checks its recorded SHA-256.
Tool caches/trust/shims remain under `.tools/`, which is ignored. No system PATH edits.

```powershell
./scripts/bootstrap-tools.ps1
./scripts/dev.ps1 install
./scripts/dev.ps1 versions
./scripts/validate-template.ps1
./scripts/dev.ps1 check
```

Rokit may ask you to trust the three tool publishers in `rokit.toml`; review them and answer
in your local terminal. For macOS, obtain Rokit 1.2.0 from its official release, place the
executable at `.tools/bin/rokit`, ensure it is executable, and use PowerShell 7 for dev.ps1.
Studio is not officially available on Linux; file-only checks may work, runtime QA needs Studio.

Commands: `format`, `check`, `build`, `serve`, `refresh-roblox-std`.
`check` validates Selene, formats/lints game source when present, builds the narrow code
layout and generates a sourcemap. `build` exports code layout only to `work/build/`.
Neither output is a full place backup. Save the actual place in Studio for scene preservation.
The committed Roblox Selene standard can be refreshed deliberately as APIs change.
If a Windows sandbox blocks Rojo's file watcher, run the authorized local check outside it;
never claim the build succeeded until it actually has.

## Studio and Rojo

1. Install/update Studio and sign in. Create or open the intended place; save a local backup.
2. Install the matching Rojo 7 Studio plugin from the official Rojo release/installation guide.
3. Run `./scripts/dev.ps1 serve`, then connect the plugin to `127.0.0.1:34872`.
4. If several games are open, use one local server at a time or explicitly choose another
   localhost port in both the project and serve command. Never attach to the wrong place.
5. Create a temporary manual Part in Workspace and an unmapped sibling folder in
   ServerScriptService. Sync a temporary disk script under src/server.
6. Verify creation/update/deletion of that script and preservation of both manual objects,
   including an unknown child in GameServer. Remove only your temporary diagnostics.

Only GameServer, GameClient and GameShared are mapped. Workspace, StarterGui, ServerStorage
and other scene content remain Studio-owned. Unknown instances must stay preserved.
Use `.server.luau` for server scripts, `.client.luau` for client scripts and `.luau` for modules.
Never enable Script Sync over the same code folders.

## Codex / ChatGPT

Open the repository in Codex or a ChatGPT coding/work environment with file access.
[AGENTS.md](../AGENTS.md) is the shared instruction source; canonical skills are in
`.agents/skills`. Normal browser chat has no automatic access to these files.
Trust the project to allow its `.codex/config.toml` settings. That file disables supported
memory injection/generation; model choice remains your client setting. Global instructions
and plugins still exist. Repository context is the workflow's source of game knowledge.

## Claude Code

Start Claude Code in the repository and accept workspace trust if appropriate.
[CLAUDE.md](../CLAUDE.md) imports AGENTS.md; `.claude/skills` adapters use the canonical skills.
Project `.claude/settings.json` disables automatic memory. No model is forced across providers.
Use `/roblox` or another specialist such as `/roblox-npcs` for explicit skill invocation;
normal automatic selection also works through skill descriptions.
Edit canonical `.agents/skills` files; regenerate adapters with `scripts/sync-claude-skills.ps1`.
Vendored skill adaptations are recorded in `docs/roblox-suite-local.patch` with
separate hashes in `docs/roblox-suite.lock.json`; upstream hashes remain unchanged.
`update-skills.ps1` reapplies the patch to a staged update and preserves the current
installation if it needs rebasing.
Both clients always use the [collaboration skill](../.agents/skills/roblox-collaboration/SKILL.md);
its [settings](../.agents/skills/roblox-collaboration/references/settings.json) select the mode.
`context/` contains recorded game facts and observations; it is not an instruction location.

## Optional official Studio MCP

Use the installed Studio's MCP settings. Current official documentation describes
Assistant -> ... -> Manage MCP Servers (or Assistant Settings -> MCP Servers).
Enable Studio as MCP server and use Quick connect for your installed Codex/Claude client.
If your version exposes these under Studio settings, use that panel; trust actual installed UI.
Restart Studio/client when needed. Prefer official built-in MCP, not a community bridge.

For manual setup, copy the actual launcher from Studio. On Windows the official launcher is
`cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat`; on macOS it is
`/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`.
Use your client's current MCP configuration instructions. Resolve environment paths as that
client requires. For Codex, configure the machine connection locally in the app or your user configuration;
keep this machine's absolute launcher path out of the committed project configuration.
For Claude Code, put a project-local server in `.mcp.json` (ignored here).
Verify effective configuration and actual tool access in each client after restarting.

No API key is required for the local Studio MCP connection. Open Cloud is a separate,
optional workflow, only when a later task actually needs it. Never commit secrets.

## Verify the connection

Discover live Studio instances and target the intended ID on every supported call.
Inspect the tree, run a harmless diagnostic, start/stop play, read console output,
capture/look at the viewport and exercise player input. Use device and multiplayer tests
when relevant. Record actual evidence in context. A green connection icon alone is insufficient.
New clones start UNVERIFIED; checks in another project's session do not transfer.

## Versioning a real game

Keep credentials, tool caches, exports and work files out of Git. Places, Blender sources and
models are ignored initially so this template stays clean. Decide explicitly which sources
belong in each real game's repository, remove matching ignore patterns or force-add selected
assets, and consider LFS for large files. Keep private context/assets in a private repository.

## Official references

- [Codex instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex skills](https://learn.chatgpt.com/docs/build-skills)
- [Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Claude instructions/imports and memory](https://code.claude.com/docs/en/memory)
- [Claude skills](https://code.claude.com/docs/en/skills)
- [Studio MCP](https://create.roblox.com/docs/studio/mcp)
- [Rojo installation](https://rojo.space/docs/v7/getting-started/installation/)
- [Rojo project format](https://rojo.space/docs/v7/project-format/)
- [Rokit pinned release](https://github.com/rojo-rbx/rokit/releases/tag/v1.2.0)
