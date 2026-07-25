# build/build-web.ps1 — package the game as a static web app via love.js
# (github.com/Davidobot/love.js: LÖVE compiled to WebAssembly with Emscripten).
#
#   pwsh build/build-web.ps1              # -> dist/web (static site)
#   pwsh build/build-web.ps1 -Serve       # build, then serve on http://localhost:8080
#
# GitHub master is used instead of the npm release: npm's latest (11.4.1) ships
# a LÖVE 11.4 runtime, while master matches the game's LÖVE 11.5. The package
# is npm-installed into dist/web-tools once and its entry script is run with
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

  & pwsh -NoProfile -File "build\make-love.ps1"
  if ($LASTEXITCODE -ne 0) { throw "make-love failed" }

  # ---- fetch tooling once (cached in dist/web-tools) ------------------------
  $tools = "dist\web-tools"
  $lovejs = "$tools\node_modules\love.js\index.js"
  if (-not (Test-Path $lovejs)) {
    New-Item -ItemType Directory -Force $tools | Out-Null
    Push-Location $tools
    try {
      if (-not (Test-Path "package.json")) {
        npm init -y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "npm init failed" }
      }
      npm install --no-audit --no-fund github:Davidobot/love.js http-server
      if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
    } finally {
      Pop-Location
    }
  }

  # ---- convert -------------------------------------------------------------
  if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
  # -c compatibility build: no SharedArrayBuffer/pthreads, so it runs on any
  # static host (itch.io, GitHub Pages) without COOP/COEP response headers.
  node $lovejs dist\space-z.love $OutDir -t "Space Z" -m ($MemoryMB * 1MB) -c
  if ($LASTEXITCODE -ne 0) { throw "love.js failed" }

  Write-Host "OK: $OutDir — static site; upload the folder to any web host"
  if ($Serve) {
    Write-Host "Serving on http://localhost:$Port (Ctrl+C to stop)"
    node "$tools\node_modules\http-server\bin\http-server" $OutDir -p $Port -c-1
  } else {
    Write-Host "Test locally:  pwsh build/build-web.ps1 -Serve"
  }
} finally {
  Pop-Location
}
