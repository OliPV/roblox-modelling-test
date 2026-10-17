#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$skillsRoot = Join-Path $projectRoot '.agents/skills'
$lockPath = Join-Path $projectRoot 'docs/roblox-suite.lock.json'
$skillNames = @('roblox', 'roblox-core', 'roblox-networking', 'roblox-datastores',
    'roblox-user-interfaces', 'roblox-animation', 'roblox-vfx', 'roblox-audio',
    'roblox-gamepasses', 'roblox-open-cloud', 'roblox-teleport', 'roblox-rojo',
    'roblox-mcp', 'roblox-physics', 'roblox-npcs', 'roblox-testing')
function Get-SkillHashes([string]$Root) {
    $hashes = [ordered]@{}
    foreach ($name in $skillNames) {
        $dir = Join-Path $Root $name
        if (!(Test-Path -LiteralPath (Join-Path $dir 'SKILL.md'))) { throw "Missing skill: $name" }
        foreach ($file in (Get-ChildItem -LiteralPath $dir -File -Recurse | Sort-Object FullName)) {
            $relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
            $hashes[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $hashes
}
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -AsHashtable
$currentHashes = Get-SkillHashes $skillsRoot
if ($currentHashes.Count -ne $lock.files.Count) { throw 'Local skill files changed; update stopped to preserve edits.' }
if ($lock.localPatch) {
    $patchPath = Join-Path $projectRoot $lock.localPatch.path
    if ((Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $lock.localPatch.sha256) {
        throw 'Local skill patch changed; review its provenance before updating.'
    }
}
foreach ($key in $currentHashes.Keys) {
    $expected = if ($lock.localPatch -and $lock.localPatch.files.Contains($key)) { $lock.localPatch.files[$key] } else { $lock.files[$key] }
    if ($currentHashes[$key] -ne $expected) { throw "Local edit detected: $key. Update stopped to preserve edits." }
}
& (Join-Path $PSScriptRoot 'sync-claude-skills.ps1') -Check
$commit = Invoke-RestMethod 'https://api.github.com/repos/nonlooped/roblox-suite/commits/main'
if ($commit.sha -eq $lock.revision) {
    Write-Output "Roblox Suite is current ($($lock.revision)); all 16 installed skills match the recorded upstream/local hashes."
    return
}
$stage = Join-Path $projectRoot ('work/skill-update-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
$archive = Join-Path $stage 'suite.zip'
Invoke-WebRequest "https://codeload.github.com/nonlooped/roblox-suite/zip/$($commit.sha)" -OutFile $archive
Expand-Archive -LiteralPath $archive -DestinationPath $stage
$sourceRoot = Join-Path $stage "roblox-suite-$($commit.sha)"
$stagedHashes = Get-SkillHashes $sourceRoot
foreach ($name in $skillNames) {
    $entry = Get-Content -LiteralPath (Join-Path $sourceRoot "$name/SKILL.md") -Raw
    if ($entry -notmatch '(?m)^name:\s*' -or $entry -notmatch '(?m)^description:\s*') {
        throw "Invalid skill entry: $name. Existing installation preserved."
    }
}
if ($lock.localPatch) {
    # Apply inside the staged archive even when it lives inside another checkout.
    $previousCeiling = $env:GIT_CEILING_DIRECTORIES
    try {
        $env:GIT_CEILING_DIRECTORIES = Split-Path $sourceRoot -Parent
        & git -C $sourceRoot apply --no-index -p3 $patchPath
        $patchExitCode = $LASTEXITCODE
    } finally { $env:GIT_CEILING_DIRECTORIES = $previousCeiling }
    if ($patchExitCode -ne 0) { throw 'Local skill patch needs rebasing; existing installation preserved.' }
    $patchedHashes = Get-SkillHashes $sourceRoot
}
$backup = Join-Path $stage 'previous'
New-Item -ItemType Directory -Path $backup | Out-Null
Copy-Item -LiteralPath $lockPath -Destination (Join-Path $backup 'roblox-suite.lock.json')
$completed = @()
try {
    foreach ($name in $skillNames) {
        $target = [IO.Path]::GetFullPath((Join-Path $skillsRoot $name))
        if (!$target.StartsWith($skillsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Update target is outside project skill folder.'
        }
        Move-Item -LiteralPath $target -Destination (Join-Path $backup $name)
        $completed += $name
        Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination $target -Recurse
    }
    $lock.revision = $commit.sha
    $lock.updated = (Get-Date).ToUniversalTime().ToString('o')
    $lock.files = $stagedHashes
    if ($lock.localPatch) {
        foreach ($key in @($lock.localPatch.files.Keys)) { $lock.localPatch.files[$key] = $patchedHashes[$key] }
    }
    $lock | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath -Encoding utf8
} catch {
    $failedCopies = Join-Path $stage 'failed-copies'
    New-Item -ItemType Directory -Path $failedCopies | Out-Null
    foreach ($name in $completed) {
        $target = [IO.Path]::GetFullPath((Join-Path $skillsRoot $name))
        if (!$target.StartsWith($skillsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw }
        if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination (Join-Path $failedCopies $name) }
        Move-Item -LiteralPath (Join-Path $backup $name) -Destination $target
    }
    Copy-Item -LiteralPath (Join-Path $backup 'roblox-suite.lock.json') -Destination $lockPath -Force
    throw
}
Write-Output "Updated Roblox Suite to $($commit.sha). Previous files preserved at $backup. Reload skills before use."


& (Join-Path $PSScriptRoot 'sync-claude-skills.ps1')
