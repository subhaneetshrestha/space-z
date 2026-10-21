-- tests/test_build_config.lua — the build scripts and CI take the LÖVE version from
-- LOVE_VERSION (via build/get-love.ps1) instead of repeating it. These are static checks
-- of the files themselves: the scripts need PowerShell and the network, which the headless
-- suite does not have, so what they actually do is checked by running them (see
-- docs/enemy-state-save/todo.md, B3 to B6).
local T = {}

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return (s:gsub("\r\n", "\n")) -- the repo's files may be checked out with CRLF
end

local function has(text, needle) return text:find(needle, 1, true) ~= nil end

-- the text of one job of the workflow: from `  <name>:` to the next job
local function job(name)
  local text = assert(readFile(".github/workflows/build.yml"), "build.yml not found")
  local first = text:find("\n  " .. name .. ":\n", 1, true)
  assert(first, "no job named " .. name)
  local rest = text:sub(first + 1)
  local nextJob = rest:find("\n  [%w_-]+:\n", 3)
  return nextJob and rest:sub(1, nextJob) or rest
end

function T.the_windows_build_does_not_hard_code_a_love_version(t)
  local text = assert(readFile("build/build-windows.ps1"))
  t.ok(not has(text, "11.5"), "build-windows.ps1 still names LÖVE 11.5")
  t.ok(not has(text, "love-11"), "build-windows.ps1 still points at a love-11.x folder")
end

function T.the_windows_build_gets_its_love_from_the_pinned_commit(t)
  local text = assert(readFile("build/build-windows.ps1"))
  t.ok(has(text, "get-love.ps1"), "build-windows.ps1 should fetch the pinned build with get-love.ps1")
  t.ok(has(text, "love-version.ps1"), "build-windows.ps1 should check the folder against the pinned commit")
end

function T.get_love_defaults_to_the_commit_in_love_version(t)
  local text = assert(readFile("build/get-love.ps1"))
  t.ok(has(text, "love_commit"), "get-love.ps1 should read love_commit")
  t.ok(not has(text, "Mandatory = $true)][string]$Commit"), "-Commit must be optional")
end

function T.the_love_version_helper_reads_the_file_the_game_reads(t)
  local helper = assert(readFile("build/love-version.ps1"), "build/love-version.ps1 is missing")
  t.ok(has(helper, "LOVE_VERSION"), "the helper must read LOVE_VERSION")
  local version = assert(readFile("LOVE_VERSION"))
  for key in version:gmatch("\n([%w_]+)=") do
    t.ok(key == "love" or key == "love_commit" or key == "love_android_commit", "unexpected key " .. key)
  end
end

function T.the_ci_windows_job_no_longer_downloads_love_11(t)
  local windows = job("windows")
  t.ok(not has(windows, "11.5"), "the windows job still downloads LÖVE 11.5")
  t.ok(not has(windows, "love-11"), "the windows job still names a love-11.x folder")
end

function T.the_ci_windows_job_fetches_the_pinned_build_and_caches_it(t)
  local windows = job("windows")
  t.ok(has(windows, "get-love.ps1"), "the windows job should run build/get-love.ps1")
  t.ok(has(windows, "GH_TOKEN"), "gh needs a token to download the artifact")
  t.ok(has(windows, "hashFiles('LOVE_VERSION')"), "the cache key should follow LOVE_VERSION, so a new pin refetches")
  t.ok(has(windows, "actions/cache"), "the downloaded build should be cached")
end

-- ------------------------------------------------------------- engine tests in CI
-- The Lua 5.1 suite does not touch LÖVE at all. This job runs the same suite, and a full
-- smoke run that really renders, inside the pinned LÖVE 12, on a runner with no GPU
-- (Mesa's software OpenGL, forced), so a LÖVE 12 problem fails the build.

function T.ci_has_an_engine_job_that_runs_the_tests_and_the_smoke_run_in_love(t)
  local engine = job("engine")
  t.ok(has(engine, "windows-latest"), "the engine job runs on Windows, where the shipped exe's LÖVE runs")
  t.ok(has(engine, "lovec.exe"), "it should run lovec.exe")
  t.ok(has(engine, "--test"), "it should run the suite inside LÖVE")
  t.ok(has(engine, "--smoke"), "it should run the smoke run")
  t.ok(has(engine, "--renderers opengl"), "both must force OpenGL, which is what Mesa provides")
  t.ok(has(engine, "GALLIUM_DRIVER"), "and force Mesa's CPU renderer, so a GPU on a runner cannot change the result")
  t.ok(has(engine, "get-love.ps1"), "it runs on the pinned LÖVE")
  t.ok(has(engine, "hashFiles('LOVE_VERSION')"), "and shares the pin-keyed cache")
end

function T.the_engine_job_pins_mesa_by_checksum(t)
  local engine = job("engine")
  t.ok(engine:find("MESA_SHA256:%s*['\"]?%x+['\"]?"), "the Mesa download must be pinned by sha256")
  local sha = engine:match("MESA_SHA256:%s*['\"]?(%x+)")
  t.eq(sha and #sha, 64, "a sha256 is 64 hex digits")
  t.ok(has(engine, "releases/download/24.2.4"), "and by version")
  t.ok(has(engine, "Get-FileHash"), "the download is checked against it before it is used")
end

function T.the_engine_job_fails_the_build_when_the_tests_or_the_smoke_run_fail(t)
  local engine = job("engine")
  local _, checks = engine:gsub("LASTEXITCODE", "")
  t.ok(checks >= 2, "each of the two lovec runs must be checked for a non-zero exit code")
  t.ok(has(engine, "llvmpipe"), "the log must show the run really was on the software renderer")
end

-- dist/love12 is cached under a key the windows job shares, and build-windows.ps1 ships every
-- *.dll in it: Mesa's OpenGL must never be copied in there, or a release would carry it.
function T.the_engine_job_keeps_mesa_out_of_the_cached_love_folder(t)
  local engine = job("engine")
  for line in engine:gmatch("[^\n]+") do
    if line:find("Copy%-Item") and line:find("mesa", 1, true) then
      t.ok(not line:find("dist/love12", 1, true), "Mesa is copied into the cached LÖVE folder: " .. line)
    end
  end
  t.ok(has(engine, "dist/engine"), "the engine job should work in its own copy of the LÖVE folder")
  t.ok(has(engine, "dist/engine/lovec.exe"), "and run lovec.exe from that copy")
end

-- ----------------------------------------------------------------- the Android build
-- Following love-android's default branch made the APK change under us between two pushes
-- (it is how the APK ended up on LÖVE 12 while conf.lua said 11.5). The build now checks out
-- the commit pinned in LOVE_VERSION.

function T.love_version_pins_a_love_android_commit(t)
  local version = assert(readFile("LOVE_VERSION"))
  local sha = version:match("\nlove_android_commit=(%x*)")
  t.ok(sha and #sha == 40, "LOVE_VERSION needs a full 40-character love_android_commit")
end

function T.the_android_build_checks_out_the_pinned_commit(t)
  local text = assert(readFile("build/build-android.ps1"))
  t.ok(has(text, "love-version.ps1"), "build-android.ps1 should read LOVE_VERSION")
  t.ok(has(text, "love_android_commit"), "and use the pinned love-android commit")
  t.ok(has(text, "fetch --depth 1 origin"), "it should fetch exactly that commit")
  t.ok(not has(text, "git clone --depth 1 --recurse-submodules https://github.com/love2d/love-android"),
    "an unpinned clone of the default branch must not come back")
  t.ok(not has(text, "11.5"), "the stale 'LÖVE 11.5' comment about the default branch is gone")
  t.ok(has(text, "-PrepareOnly") or has(text, "PrepareOnly"), "a prepare-only mode lets the pin be checked without a Gradle build")
end

function T.the_android_job_caches_on_the_pin_not_on_upstream_head(t)
  local android = job("android")
  t.ok(not has(android, "ls-remote"), "the cache key must not be derived from upstream HEAD")
  t.ok(has(android, "hashFiles('LOVE_VERSION')"), "the cache key should follow the pin in LOVE_VERSION")
end

function T.releases_wait_for_the_engine_tests(t)
  local text = assert(readFile(".github/workflows/build.yml"))
  local version = job("version")
  t.ok(version:find("needs:%s*%[[^%]]*engine"), "the version job (and so every build and release after it) needs the engine job")
  t.ok(text:find("\n  engine:\n", 1, true), "the engine job exists")
end

return T
