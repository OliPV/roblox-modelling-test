# Third-party skills

The 16 Roblox skills, references, example scripts and tests in `.agents/skills` come from
[nonlooped/roblox-suite](https://github.com/nonlooped/roblox-suite), revision
`c914ce65470a6eb1b28000b8c58d5543b48760ca` (vendored on 2026-10-03).

Their MIT notice is preserved in [roblox-suite.LICENSE](roblox-suite.LICENSE).
[roblox-suite.lock.json](roblox-suite.lock.json) records each file's SHA-256.
Upstream guidance is reference material; shared project rules use Rojo instead of Script Sync.
No examples run automatically. Verify current official APIs and adapt/test examples.

`scripts/update-skills.ps1` checks recorded hashes before updating, refuses to overwrite
local edits, backs up changed skills and regenerates the thin Claude discovery adapters.
The adapters and template workflow are maintained by this repository.

Project-owned collaboration and Blender skills are separate from the 16 vendored skills.
[project-skill-files.json](project-skill-files.json) identifies these maintained files; the
upstream updater replaces only the named vendored directories and preserves project skills.
