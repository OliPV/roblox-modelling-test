#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if (!$IsWindows) { throw 'This bootstrap targets Windows. On macOS install pinned Rokit locally; see docs/SETUP.md.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
$releases = @{
    X64 = @('x86_64', 'f9ba1704014ff67d51e8005f605955c7c26d2429a5312a9419dc477fc310e96d')
    Arm64 = @('aarch64', 'aff0e76e304fdc938cffa5b7ee1e183a052acac541868b4271192f20c734282a')
}
if (!$releases.ContainsKey($arch)) { throw "Unsupported Windows architecture: $arch" }
$toolPath = Join-Path $projectRoot '.tools/bin/rokit.exe'
if (Test-Path -LiteralPath $toolPath) {
    & $toolPath --version
    if ($LASTEXITCODE -ne 0) { throw 'Existing Rokit failed; inspect it before replacing.' }
    Write-Output 'Existing local Rokit retained. Run scripts/dev.ps1 install to install pinned tools.'
    return
}
$stage = Join-Path $projectRoot ('work/bootstrap-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$release = $releases[$arch]
$archive = Join-Path $stage 'rokit.zip'
$url = "https://github.com/rojo-rbx/rokit/releases/download/v1.2.0/rokit-1.2.0-windows-$($release[0]).zip"
Invoke-WebRequest -Uri $url -OutFile $archive
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $release[1]) {
    throw 'Rokit archive checksum mismatch. Nothing installed.'
}
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $stage 'unpacked')
$binary = @(Get-ChildItem -LiteralPath (Join-Path $stage 'unpacked') -Recurse -File -Filter rokit.exe)
if ($binary.Count -ne 1) { throw 'Unexpected Rokit archive layout.' }
New-Item -ItemType Directory -Path (Split-Path $toolPath) -Force | Out-Null
Copy-Item -LiteralPath $binary[0].FullName -Destination $toolPath
& $toolPath --version
if ($LASTEXITCODE -ne 0) { throw 'Installed Rokit could not run.' }
Write-Output 'Verified Rokit installed locally. Next: ./scripts/dev.ps1 install. No global PATH changes.'
