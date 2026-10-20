# build/build-windows.ps1 — fuse the game with LÖVE into a shippable Windows folder.
#
#   pwsh build/build-windows.ps1                       # LÖVE as pinned in LOVE_VERSION (fetched into dist/love12)
#   pwsh build/build-windows.ps1 -LoveDir <folder>     # a LÖVE win64 folder you already have
#
# Produces dist/windows/SpaceZ.exe + required DLLs + license. Zip that folder
# and it runs on any 64-bit Windows machine with no install.
#
# The LÖVE version is whatever LOVE_VERSION says (build/get-love.ps1 downloads exactly that
# commit). A folder passed with -LoveDir is checked against the pin when it can be: a
# folder fetched by get-love.ps1 records its commit, and on Windows love.exe's version
# resource is read; a mismatch stops the build, because conf.lua declares the pinned
# version and a different runtime would show LÖVE's compatibility dialog.
param(
  [string]$LoveDir
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  . "$PSScriptRoot/love-version.ps1"
  $pin = Get-LoveVersion

  if (-not $LoveDir) {
    & pwsh -NoProfile -File "build/get-love.ps1" -Out "dist/love12"
    if ($LASTEXITCODE -ne 0) { throw "get-love failed" }
    $LoveDir = "dist/love12"
  }

  if (-not (Test-Path "$LoveDir/love.exe")) {
    throw "love.exe not found in '$LoveDir' — run without -LoveDir to fetch the pinned LÖVE $($pin.love) (commit $($pin.love_commit))"
  }

  # is this folder the pinned LÖVE?
  if (Test-Path "$LoveDir/COMMIT") {
    $have = (Get-Content "$LoveDir/COMMIT" -Raw).Trim()
    if ($have -ne $pin.love_commit) {
      throw "'$LoveDir' holds LÖVE commit $have, but LOVE_VERSION pins $($pin.love_commit): run without -LoveDir, or get-love.ps1 -Force"
    }
  } elseif ($IsWindows -or $env:OS -eq "Windows_NT") {
    $version = (Get-Item "$LoveDir/love.exe").VersionInfo.FileVersion
    if ($version -and -not ($version -like "$($pin.love)*")) {
      throw "'$LoveDir/love.exe' is LÖVE $version, but LOVE_VERSION pins $($pin.love)"
    }
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
  Write-Host "OK: $out/SpaceZ.exe on LÖVE $($pin.love) ($size MB total) — zip the folder to distribute"
} finally {
  Pop-Location
}
