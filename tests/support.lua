-- tests/support.lua — helpers shared by several test files (not a test file:
-- it is not in tests/run.lua's FILES list).
local M = {}

-- Path of the first difference between two plain tables, or nil when equal.
-- Numbers compare within 1e-9: json.lua writes floats with 14 significant
-- digits, so accumulated clocks (20 s of 1/60 steps) come back a hair off.
function M.firstDiff(a, b, path)
  path = path or "run"
  if type(a) ~= type(b) then return path .. " (type " .. type(a) .. " vs " .. type(b) .. ")" end
  if type(a) == "number" then
    if math.abs(a - b) > 1e-9 * math.max(1, math.abs(a)) then
      return path .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")"
    end
    return nil
  end
  if type(a) ~= "table" then
    if a ~= b then return path .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")" end
    return nil
  end
  for k, v in pairs(a) do
    local d = M.firstDiff(v, b[k], path .. "." .. tostring(k))
    if d then return d end
  end
  for k in pairs(b) do
    if a[k] == nil then return path .. "." .. tostring(k) .. " (missing in first)" end
  end
  return nil
end

-- In-memory stand-in for love.filesystem: read / write / remove over a table, with
-- a log of written names. Lets tests exercise Save's real file code path without
-- touching the player's actual save files.
function M.memoryFilesystem()
  local fs = { files = {}, writes = {} }
  function fs.read(name)
    local contents = fs.files[name]
    if contents == nil then return nil, "not found: " .. name end
    return contents, #contents
  end
  function fs.write(name, data)
    fs.files[name] = data
    fs.writes[#fs.writes + 1] = name
    return true
  end
  function fs.remove(name)
    local existed = fs.files[name] ~= nil
    fs.files[name] = nil
    return existed
  end
  return fs
end

-- Run fn(fs) with `love.filesystem` replaced by a fresh memory filesystem (works
-- with or without a real `love` global), restoring everything afterwards.
function M.withMemoryFs(fn)
  local hadLove, realLove = love ~= nil, love
  local fs = M.memoryFilesystem()
  if hadLove then
    love = setmetatable({ filesystem = fs }, { __index = realLove })
  else
    love = { filesystem = fs }
  end
  local ok, err = pcall(fn, fs)
  love = realLove
  if not ok then error(err, 0) end
end

-- A valid saved run (zone 2, damaged hull, one weapon), for tests that need one
-- without building a world.
function M.validRun(over)
  local run = {
    version = 1, mode = "standard", seed = 5, ship = "pathfinder",
    time = 61.5, distance = 7400.5, zoneIndex = 2, zoneTime = 20, zoneStartDistance = 5000,
    level = 5, xp = 3, xpNext = 30, pendingLevelUps = 0, kills = 30, bossKills = 1,
    noDamage = false, stardustEarned = 0, hp = 42.5,
    weapons = { { id = "blaster", level = 2 } }, passives = {},
    rng = { spawn = 1234, drops = 2345, cards = 3456, misc = 4567 },
    spawnerTimers = {},
  }
  for k, v in pairs(over or {}) do run[k] = v end
  return run
end

return M
