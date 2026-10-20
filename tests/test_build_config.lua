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

return T
