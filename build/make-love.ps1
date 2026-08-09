# build/make-love.ps1 — package the game into dist/space-z.love
# The .love is the universal artifact: runs on desktop LÖVE and the Android
# LÖVE player, and is the input to the Windows/Android bundling scripts.
#
#   pwsh build/make-love.ps1 [-IncludeTests]
param(
  [switch]$IncludeTests
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  New-Item -ItemType Directory -Force "dist" | Out-Null
  $items = @("conf.lua", "main.lua", "src", "lib")
  if ($IncludeTests) { $items += "tests" }

  $zip = "dist/space-z.zip"
  $love = "dist/space-z.love"
  if (Test-Path $zip) { Remove-Item $zip -Force }
  if (Test-Path $love) { Remove-Item $love -Force }

  Compress-Archive -Path $items -DestinationPath $zip -Force
  Rename-Item $zip "space-z.love"
  $size = [math]::Round((Get-Item $love).Length / 1KB)
  Write-Host "OK: $love ($size KB)"
} finally {
  Pop-Location
}
