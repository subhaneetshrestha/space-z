# build/love-version.ps1 — read LOVE_VERSION, the one file that says which LÖVE the game
# is built and tested against (conf.lua reads the same file at startup).
#
#   . "$PSScriptRoot/love-version.ps1"      # dot-source it, then:
#   $pin = Get-LoveVersion                  # @{ love = "12.0"; love_commit = "..."; love_android_commit = "" }
function Get-LoveVersion {
  param([string]$Root = (Split-Path -Parent $PSScriptRoot))

  $path = Join-Path $Root "LOVE_VERSION"
  if (-not (Test-Path $path)) { throw "LOVE_VERSION not found at '$path'" }

  $pin = @{}
  foreach ($line in Get-Content $path) {
    # `key=value`; comment and blank lines never match
    if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$') { $pin[$Matches[1]] = $Matches[2] }
  }
  foreach ($key in "love", "love_commit") {
    if (-not $pin[$key]) { throw "LOVE_VERSION has no value for '$key'" }
  }
  return $pin
}

# Where the pinned Windows build is mirrored (a pre-release of THIS repo, so the build outlives
# love2d/love's 90-day CI artifacts). Both names come from the pinned commit, so a new pin
# means a new mirror and the old one is left alone. See build/mirror-love.ps1.
function Get-LoveMirror {
  param([hashtable]$Pin = (Get-LoveVersion))

  $short = $Pin["love_commit"].Substring(0, 7)
  return @{ tag = "love-$short"; asset = "love-$short-win64.zip" }
}
