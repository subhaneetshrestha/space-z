# build/build-web.ps1 — package the game as a static web app via love.js
# (github.com/Davidobot/love.js: LÖVE compiled to WebAssembly with Emscripten).
#
#   pwsh build/build-web.ps1              # -> dist/web (static site)
#   pwsh build/build-web.ps1 -Serve       # build, then serve on http://localhost:8080
#
# THE ONE EXCEPTION TO "LÖVE 12". love.js has no LÖVE 12 port (upstream stops at 11.5), so
# the browser build runs an 11.x runtime, while everything else in the repo is on the LÖVE
# pinned in LOVE_VERSION. To keep that honest the game is packaged with its OWN LOVE_VERSION
# declaring web_love (see there), so conf.lua tells the runtime the truth and it shows no
# version-mismatch warning; the package is a separate file (dist/space-z-web.love) and the
# desktop and Android packages are never touched. The game keeps running on 11.x through
# src/compat.lua. This build is not run in CI. Remove this script's exception when a LÖVE 12
# web port exists: set web_love to 12.x or delete the script.
#
# love.js is installed at the commit pinned in LOVE_VERSION (lovejs_commit), not from its
# moving default branch. npm's release (11.4.1) ships a LÖVE 11.4 runtime; the pinned commit
# is the one with 11.5. It goes into dist/web-tools once and its entry script is run with
# node directly — npx's Windows cmd shim chokes on the bin name "love.js".
#
# Prerequisites: Node.js (node + npm) — https://nodejs.org or `volta install node`
param(
  [switch]$Serve,
  [int]$Port = 8080,
  [int]$MemoryMB = 64,
  [string]$OutDir = "dist\web"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  foreach ($cmd in "node", "npm") {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
      Write-Host "Missing prerequisite: Node.js ($cmd) — https://nodejs.org or 'volta install node'" -ForegroundColor Yellow
      exit 1
    }
  }

  . "$PSScriptRoot/love-version.ps1"
  $pin = Get-LoveVersion
  $webLove = $pin.web_love
  $lovejsCommit = $pin.lovejs_commit
  if (-not $webLove -or -not $lovejsCommit) {
    throw "LOVE_VERSION needs web_love and lovejs_commit for the web build"
  }
  Write-Host "web build: love.js $lovejsCommit, running LÖVE $webLove (the repo itself is on LÖVE $($pin.love): see the exception in LOVE_VERSION)" -ForegroundColor Yellow

  & pwsh -NoProfile -File "build\make-love.ps1" -LoveVersion $webLove -Out "dist/space-z-web.love"
  if ($LASTEXITCODE -ne 0) { throw "make-love failed" }

  # ---- fetch tooling once (cached in dist/web-tools, re-fetched when the pin changes) ----
  $tools = "dist\web-tools"
  $lovejs = "$tools\node_modules\love.js\index.js"
  $pinFile = "$tools\LOVEJS_COMMIT"
  $installed = if (Test-Path $pinFile) { (Get-Content $pinFile -Raw).Trim() } else { "" }
  if (-not (Test-Path $lovejs) -or $installed -ne $lovejsCommit) {
    if (Test-Path $tools) { Remove-Item -Recurse -Force $tools }
    New-Item -ItemType Directory -Force $tools | Out-Null
    Push-Location $tools
    try {
      npm init -y | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "npm init failed" }
      npm install --no-audit --no-fund "github:Davidobot/love.js#$lovejsCommit" http-server
      if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
    } finally {
      Pop-Location
    }
    Set-Content $pinFile $lovejsCommit -NoNewline
  }

  # ---- convert -------------------------------------------------------------
  if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
  # -c compatibility build: no SharedArrayBuffer/pthreads, so it runs on any
  # static host (itch.io, GitHub Pages) without COOP/COEP response headers.
  node $lovejs dist\space-z-web.love $OutDir -t "Space Z" -m ($MemoryMB * 1MB) -c
  if ($LASTEXITCODE -ne 0) { throw "love.js failed" }

  Write-Host "OK: $OutDir — static site on LÖVE $webLove; upload the folder to any web host"
  if ($Serve) {
    Write-Host "Serving on http://localhost:$Port (Ctrl+C to stop)"
    node "$tools\node_modules\http-server\bin\http-server" $OutDir -p $Port -c-1
  } else {
    Write-Host "Test locally:  pwsh build/build-web.ps1 -Serve"
  }
} finally {
  Pop-Location
}
