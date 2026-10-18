# roblox-gpu-model launcher (Windows PowerShell 5.1+ / PowerShell 7).
# Runs run_pipeline.py with the tools venv, else `uv run` (downloads Python 3.11 if needed),
# else a real system Python. Avoids the Microsoft Store `python` alias.
# Usage: .agents/skills/roblox-gpu-model/scripts/rgm.ps1 doctor
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'run_pipeline.py'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$candidates = @()
if ($env:ROBLOX_GPU_MODEL_TOOLS) { $candidates += (Join-Path $env:ROBLOX_GPU_MODEL_TOOLS 'venv/Scripts/python.exe') }
$candidates += (Join-Path $repo '.tools/roblox-gpu-model/venv/Scripts/python.exe')
$candidates += (Join-Path $repo '.tools/roblox-model/venv/Scripts/python.exe')
foreach ($py in $candidates) {
    if (Test-Path -LiteralPath $py) { & $py $script @args; exit $LASTEXITCODE }
}
$uv = Get-Command uv -ErrorAction SilentlyContinue
if ($uv) { & $uv.Source run --no-project --python 3.11 $script @args; exit $LASTEXITCODE }
foreach ($name in 'py', 'python') {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notlike '*\WindowsApps\*') { & $cmd.Source $script @args; exit $LASTEXITCODE }
}
Write-Error 'No Python found. Install uv (winget install astral-sh.uv), then re-run.'
exit 1
