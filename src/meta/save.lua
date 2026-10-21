-- src/meta/save.lua — persistent save data (save.json in the LÖVE save dir) and
-- the in-progress run (run.json, a separate file: it is rewritten every ~10 s, and
-- a torn write there must never be able to wipe the permanent progress in save.json).
-- Headless-safe: without love.filesystem the data lives in memory only.
local json = require("lib.json")
local Compat = require("src.compat")

local M = {}

local FILENAME = "save.json"
local RUN_FILENAME = "run.json"
local CURRENT_VERSION = 1

local cache = nil
local runCache = nil      -- decoded run.json (unvalidated), or nil
local runLoaded = false   -- runCache reflects the file (or a later setRun/clearRun)

-- Fresh table every call == deep copy of the defaults.
local function defaults()
  return {
    version = CURRENT_VERSION,
    stardust = 0,
    totalRuns = 0,
    bestDistance = 0,
    bestLevel = 0,
    unlocked = { blackhole = false, ships = { pathfinder = true } },
    settings = { sound = true, quality = "high",
                 ship = "pathfinder", mode = "standard" },
    tech = {},
    achievements = {},
    stats = { kills = 0, wins = 0, bhWins = 0, stardust = 0 },
    bestDistanceBH = 0,
    tutorialDone = false,
    daily = nil, -- { date = "YYYYMMDD", bestStardust, bestDistance, runs }
  }
end

-- Merge loaded data over defaults: missing keys keep defaults,
-- unknown keys are preserved, nested tables merge recursively.
local function merge(base, over)
  for k, v in pairs(over) do
    if type(v) == "table" and type(base[k]) == "table" then
      merge(base[k], v)
    else
      base[k] = v
    end
  end
  return base
end

function M.load()
  local data = defaults()
  if love and love.filesystem then
    local ok, contents = pcall(Compat.readFile, FILENAME)
    if ok and type(contents) == "string" then
      local okDecode, loaded = pcall(json.decode, contents)
      if okDecode and type(loaded) == "table" then
        merge(data, loaded)
      end
    end
  end
  data.version = CURRENT_VERSION -- forced migration to the current schema
  -- retired setting: steering is now always 1:1 relative drag. merge() preserves
  -- unknown keys, so without this the orphan lives in every old save forever.
  data.settings.steerMode = nil
  cache = data
  runCache, runLoaded = nil, false -- load() is a full reload: re-read run.json too
  return cache
end

function M.data()
  return cache or M.load()
end

function M.write()
  local data = M.data()
  data.version = CURRENT_VERSION
  if love and love.filesystem then
    local ok, success = pcall(love.filesystem.write, FILENAME, json.encode(data))
    return ok and success or false
  end
  return true
end

-- ---------------------------------------------------------------- run.json

-- The stored run exactly as read, unvalidated (nil if absent or not a table).
-- An unreadable or corrupt file is just "no run"; it can never touch save.json.
function M.rawRun()
  if not runLoaded then
    runLoaded = true
    runCache = nil
    if love and love.filesystem then
      local ok, contents = pcall(Compat.readFile, RUN_FILENAME)
      if ok and type(contents) == "string" then
        local okDecode, loaded = pcall(json.decode, contents)
        if okDecode and type(loaded) == "table" then runCache = loaded end
      end
    end
  end
  return runCache
end

-- The saved run, or nil if there is none or it fails validation (the file is
-- untrusted: a bad run counts as no run). Lazy require: runsave reaches content
-- modules that must not load while save.lua itself is still loading.
function M.run()
  local run = M.rawRun()
  if run ~= nil and require("src.meta.runsave").validate(run) then
    return run
  end
  return nil
end

-- Store a run (writes only run.json). Returns true on success.
function M.setRun(run)
  if run == nil then return M.clearRun() end
  runCache, runLoaded = run, true
  if love and love.filesystem then
    local ok, success = pcall(love.filesystem.write, RUN_FILENAME, json.encode(run))
    return ok and success or false
  end
  return true
end

-- Forget the run and delete its file (an unreadable file is deleted too).
function M.clearRun()
  runCache, runLoaded = nil, true
  if love and love.filesystem then
    pcall(love.filesystem.remove, RUN_FILENAME)
  end
  return true
end

function M.reset()
  cache = defaults()
  M.clearRun()
  M.write()
  return cache
end

return M
