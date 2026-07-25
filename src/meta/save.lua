-- src/meta/save.lua — persistent save data (save.json in the LÖVE save dir).
-- Headless-safe: without love.filesystem the data lives in memory only.
local json = require("lib.json")

local M = {}

local FILENAME = "save.json"
local CURRENT_VERSION = 1

local cache = nil

-- Fresh table every call == deep copy of the defaults.
local function defaults()
  return {
    version = CURRENT_VERSION,
    stardust = 0,
    totalRuns = 0,
    bestDistance = 0,
    bestLevel = 0,
    unlocked = { blackhole = false, ships = { pathfinder = true } },
    settings = { steerMode = "floating", sound = true, quality = "high",
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
    local ok, contents = pcall(love.filesystem.read, FILENAME)
    if ok and type(contents) == "string" then
      local okDecode, loaded = pcall(json.decode, contents)
      if okDecode and type(loaded) == "table" then
        merge(data, loaded)
      end
    end
  end
  data.version = CURRENT_VERSION -- forced migration to the current schema
  cache = data
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

function M.reset()
  cache = defaults()
  M.write()
  return cache
end

return M
