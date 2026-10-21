# build/mirror-love.ps1 — pack the pinned LÖVE Windows build for mirroring as a release of this repo.
#
#   pwsh build/mirror-love.ps1                # zip dist/love12 -> dist/mirror/<asset>, print its sha256
#   (set love_win64_sha256 in LOVE_VERSION to that hash)
#   pwsh build/mirror-love.ps1 -Publish       # upload that same zip as the pre-release (needs `gh auth login`)
#
# love2d/love's CI artifacts expire after about 90 days, so the build the pin names is also kept as a
# pre-release of this repo (tag love-<commit>, never marked Latest, ignored by the version and changelog
# logic, which only look at v* tags). build/get-love.ps1 downloads it from there and trusts it only by the
# `love_win64_sha256` pin in LOVE_VERSION, so after packing, that value must be set to the printed hash.
#
# dist/love12 must hold the pinned commit (run build/get-love.ps1 -NoMirror first). Publishing goes to
# this repository's releases and is public; it is a flag, never the default.
param(
  [switch]$Publish
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  . "$PSScriptRoot/love-version.ps1"
  $pin = Get-LoveVersion
  $mirror = Get-LoveMirror $pin

  $src = "dist/love12"
  if (-not ((Test-Path "$src/COMMIT") -and (Test-Path "$src/love.exe"))) {
    throw "$src is missing: run build/get-love.ps1 -NoMirror first"
  }
  $held = (Get-Content "$src/COMMIT" -Raw).Trim()
  if ($held -ne $pin["love_commit"]) {
    throw "$src holds $held, LOVE_VERSION pins $($pin['love_commit']): run build/get-love.ps1 -NoMirror -Force"
  }

  $outDir = "dist/mirror"
  New-Item -ItemType Directory -Force $outDir | Out-Null
  $zip = Join-Path $outDir $mirror.asset
  # A zip is not reproducible (every pack hashes differently), so one that exists is kept: pack,
  # pin its hash in LOVE_VERSION, then run again with -Publish to upload that same file.
  # Delete dist/mirror to pack again.
  if (Test-Path $zip) {
    Write-Host "using the zip already packed at $zip"
  } else {
    # COMMIT is written by get-love.ps1 after unpacking, so it is not part of the mirrored build
    $items = Get-ChildItem $src | Where-Object { $_.Name -ne "COMMIT" }
    Compress-Archive -Path $items.FullName -DestinationPath $zip -CompressionLevel Optimal
  }

  $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
  Write-Host "packed $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
  Write-Host "sha256 $hash"
  $pinned = $pin["love_win64_sha256"]
  if ($pinned -and $pinned.ToUpper() -ne $hash) {
    Write-Host "NOTE: LOVE_VERSION pins $pinned, which is not this file. Zips are not reproducible, so keep the one that was published."
  }

  if ($Publish) {
    if (-not $pinned -or $pinned.ToUpper() -ne $hash) {
      throw "refusing to publish: set love_win64_sha256=$hash in LOVE_VERSION first, so the pin and the upload are the same file"
    }
    $self = gh repo view --json nameWithOwner --jq .nameWithOwner
    if ($LASTEXITCODE -ne 0) { throw "could not tell which repository this is (gh logged in?)" }
    gh release view $mirror.tag --repo $self 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "release $($mirror.tag) already exists in $self; a mirror is written once" }
    $notes = "Mirror of the LÖVE Windows build for love2d/love commit $($pin['love_commit']) " +
      "(love2d/love's CI artifacts expire after about 90 days). Used by build/get-love.ps1, " +
      "checked against love_win64_sha256 in LOVE_VERSION: $hash. Not a game release."
    gh release create $mirror.tag $zip --repo $self --prerelease --latest=false `
      --title "LÖVE $($pin['love']) build $($mirror.tag.Substring(5)) (mirror)" --notes $notes
    if ($LASTEXITCODE -ne 0) { throw "could not create release $($mirror.tag)" }
    Write-Host "published release $($mirror.tag) in $self"
  } else {
    Write-Host "not published (add -Publish to create release $($mirror.tag))"
  }
} finally {
  Pop-Location
}
