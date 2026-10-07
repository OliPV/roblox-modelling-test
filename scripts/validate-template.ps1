#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$settings = Get-Content -LiteralPath (Join-Path $projectRoot '.agents/skills/roblox-collaboration/references/settings.json') -Raw | ConvertFrom-Json
if ($settings.learningMode -isnot [bool]) { throw 'learningMode must be a JSON boolean.' }
$rojo = Get-Content -LiteralPath (Join-Path $projectRoot 'default.project.json') -Raw | ConvertFrom-Json
if ($rojo.serveAddress -ne '127.0.0.1' -or !$rojo.tree.'$ignoreUnknownInstances') {
    throw 'Rojo must use localhost and preserve unknown instances.'
}
$paths = @{
    'src/server' = $rojo.tree.ServerScriptService.GameServer
    'src/shared' = $rojo.tree.ReplicatedStorage.GameShared
    'src/client' = $rojo.tree.StarterPlayer.StarterPlayerScripts.GameClient
}
foreach ($path in $paths.Keys) {
    $node = $paths[$path]
    if ($node.'$path' -ne $path -or !$node.'$ignoreUnknownInstances' -or
        !(Test-Path -LiteralPath (Join-Path $projectRoot $path) -PathType Container)) {
        throw "Invalid Rojo source ownership: $path"
    }
}
$claude = Get-Content -LiteralPath (Join-Path $projectRoot '.claude/settings.json') -Raw | ConvertFrom-Json
if ($claude.autoMemoryEnabled -ne $false) { throw 'Claude auto memory must be disabled for repository-owned context.' }
if ((Get-Content -LiteralPath (Join-Path $projectRoot 'CLAUDE.md') -Raw) -notmatch '(?m)^@AGENTS\.md$') {
    throw 'Claude must import the canonical project rules.'
}
& (Join-Path $PSScriptRoot 'sync-claude-skills.ps1') -Check
$skillsRoot = Join-Path $projectRoot '.agents/skills'
$lock = Get-Content -LiteralPath (Join-Path $projectRoot 'docs/roblox-suite.lock.json') -Raw | ConvertFrom-Json -AsHashtable
$files = @(Get-ChildItem -LiteralPath $skillsRoot -Recurse -File)
$owned = Get-Content -LiteralPath (Join-Path $projectRoot 'docs/project-skill-files.json') -Raw | ConvertFrom-Json
$actual = @($files | ForEach-Object { [IO.Path]::GetRelativePath($skillsRoot, $_.FullName).Replace('\', '/') })
$expected = @($lock.files.Keys) + @($owned.files)
if (@(Compare-Object $expected $actual).Count) { throw 'Skill inventory differs from vendored lock + project ownership record.' }
foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($skillsRoot, $file.FullName).Replace('\', '/')
    if ($relative -in $owned.files) { continue }
    if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne $lock.files[$relative]) {
        throw "Vendored skill changed: $relative. Review and update its provenance deliberately."
    }
}
# Local links in shipped Markdown must resolve; external documentation is checked on demand.
$markdown = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.md' |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|\.tools|work|outputs)[\\/]' })
$badLinks = @()
foreach ($file in $markdown) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($match in [regex]::Matches($content, '\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value
        if ($target -match '^(https?://|mailto:|#)') { continue }
        $target = $target.Split('#')[0]
        if ($target -match '[<>\s]') { continue }
        if ($target -and !(Test-Path -LiteralPath (Join-Path $file.DirectoryName $target))) {
            $badLinks += "$($file.Name): $target"
        }
    }
}
if ($badLinks.Count) { throw ('Broken local links: ' + ($badLinks -join '; ')) }
# Check the actual reusable export, including ignored/untracked files before the first commit.
$portableFiles = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|\.tools|work|outputs)[\\/]' })
foreach ($file in $portableFiles) {
    if ($file.Extension -in '.rbxl', '.rbxlx', '.rbxm', '.rbxmx', '.blend', '.glb', '.fbx') {
        throw "Game asset in reusable template: $($file.Name)"
    }
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -match '(?m)[A-Z]:[\\/](Users|code)[\\/]') {
        throw "Machine/private game data in template: $($file.Name)"
    }
}
Write-Output "Template validated: $($lock.files.Count) vendored files and $($owned.files.Count) project skill files; shared rules, adapters, settings, links and narrow Rojo map."
