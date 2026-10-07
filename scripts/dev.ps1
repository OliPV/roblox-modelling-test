#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('versions', 'install', 'check', 'format', 'build', 'serve', 'refresh-roblox-std')]
    [string]$Action
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$oldRokitRoot = $env:ROKIT_ROOT
$oldPath = $env:PATH
function Invoke-ProjectTool([string]$Name, [string[]]$ToolArgs) {
    $suffix = if ($IsWindows) { '.exe' } else { '' }
    $toolPath = if ($Name -eq 'rokit') { Join-Path $projectRoot ".tools/bin/rokit$suffix" }
        else { Join-Path $projectRoot ".tools/rokit/bin/$Name$suffix" }
    if (!(Test-Path -LiteralPath $toolPath)) { throw "Missing local tool: $Name. See docs/SETUP.md." }
    & $toolPath @ToolArgs
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE." }
}
Push-Location $projectRoot
try {
    $env:ROKIT_ROOT = Join-Path $projectRoot '.tools/rokit'
    New-Item -ItemType Directory -Path $env:ROKIT_ROOT -Force | Out-Null
    $env:PATH = (Join-Path $env:ROKIT_ROOT 'bin') + [IO.Path]::PathSeparator + $oldPath
    switch ($Action) {
        'versions' {
            foreach ($tool in @('rokit', 'rojo', 'stylua', 'selene')) { Invoke-ProjectTool $tool @('--version') }
        }
        'install' { Invoke-ProjectTool 'rokit' @('install') }
        'check' {
            Invoke-ProjectTool 'selene' @('validate-config')
            $sources = @(Get-ChildItem src -File -Recurse | Where-Object { $_.Extension -in '.lua', '.luau' })
            if ($sources.Count -gt 0) {
                Invoke-ProjectTool 'stylua' @('--check', 'src')
                Invoke-ProjectTool 'selene' @('src')
            } else { Write-Output 'No game scripts yet; source checks deferred until code exists.' }
            New-Item -ItemType Directory -Force work/checks | Out-Null
            Invoke-ProjectTool 'rojo' @('build', 'default.project.json', '-o', 'work/checks/code-layout.rbxlx')
            Invoke-ProjectTool 'rojo' @('sourcemap', 'default.project.json', '--include-non-scripts', '-o', 'work/checks/sourcemap.json')
        }
        'format' { Invoke-ProjectTool 'stylua' @('src') }
        'build' {
            New-Item -ItemType Directory -Force work/build | Out-Null
            Invoke-ProjectTool 'rojo' @('build', 'default.project.json', '-o', 'work/build/code-layout.rbxlx')
            Write-Output 'Code-layout build only. Studio-owned scenes are not included; this is not a complete game backup.'
        }
        'serve' { Invoke-ProjectTool 'rojo' @('serve', 'default.project.json', '--address', '127.0.0.1', '--port', '34872') }
        'refresh-roblox-std' { Invoke-ProjectTool 'selene' @('generate-roblox-std') }
    }
} finally {
    $env:ROKIT_ROOT = $oldRokitRoot
    $env:PATH = $oldPath
    Pop-Location
}
