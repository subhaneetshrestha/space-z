# build/build-windows.ps1 — fuse the game with LÖVE into a shippable Windows folder.
#
#   pwsh build/build-windows.ps1 -LoveDir "C:\path\to\love-11.5-win64"
#
# Produces dist/windows/SpaceZ.exe + required DLLs + license. Zip that folder
# and it runs on any 64-bit Windows machine with no install.
param(
  [Parameter(Mandatory = $true)][string]$LoveDir
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  if (-not (Test-Path "$LoveDir/love.exe")) {
    throw "love.exe not found in '$LoveDir' — point -LoveDir at an extracted love-11.x-win64 folder (https://love2d.org)"
  }

  & pwsh -NoProfile -File "build/make-love.ps1"
  if ($LASTEXITCODE -ne 0) { throw "make-love failed" }

  $out = "dist/windows"
  if (Test-Path $out) { Remove-Item $out -Recurse -Force }
  New-Item -ItemType Directory -Force $out | Out-Null

  # fused exe = love.exe with the .love appended
  $bytes = [System.IO.File]::ReadAllBytes("$LoveDir/love.exe") `
    + [System.IO.File]::ReadAllBytes("dist/space-z.love")
  [System.IO.File]::WriteAllBytes((Join-Path $root "$out/SpaceZ.exe"), $bytes)

  Copy-Item "$LoveDir/*.dll" $out
  if (Test-Path "$LoveDir/license.txt") { Copy-Item "$LoveDir/license.txt" $out }

  $size = [math]::Round((Get-ChildItem $out | Measure-Object Length -Sum).Sum / 1MB, 1)
  Write-Host "OK: $out/SpaceZ.exe ($size MB total) — zip the folder to distribute"
} finally {
  Pop-Location
}
