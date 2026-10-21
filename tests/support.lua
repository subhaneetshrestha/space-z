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

-- ----------------------------------------------------------------- worldDiff
-- Plain-data view of everything that decides how a run plays out, and nothing that
-- is only drawn (particles, arcs, beams, pulses, toasts, shake). Two worlds with
-- equal views play out identically, so firstDiff over views is the "did the resume
-- change anything?" check used by the behavioural-identity tests.

local WORLD_SCALARS = {
  "mode", "seed", "time", "distance", "zoneIndex", "zoneTime", "zoneStartDistance",
  "phase", "warpT", "level", "xp", "xpNext", "pendingLevelUps", "kills", "bossKills",
  "noDamage", "stardustEarned", "freezeT", "shieldT", "pulseT", "hpRingT",
}
local PLAYER_FIELDS = { "x", "y", "vx", "vy", "hp", "maxhp", "invulnT", "dead" }

-- bookkeeping that only decides when a cache is tidied, never what happens
local BOOKKEEPING = { hitCdN = true }

-- every number / string / boolean field of an entity; a def is reduced to its id
local function entityView(e)
  local v = {}
  for k, val in pairs(e) do
    local ty = type(val)
    if BOOKKEEPING[k] then
      -- left out
    elseif ty == "number" or ty == "string" or ty == "boolean" then
      v[k] = val
    elseif (k == "def" or k == "bossDef") and type(val) == "table" then
      v[k] = val.id
    end
  end
  return v
end

function M.worldView(w)
  local view = {}
  for _, k in ipairs(WORLD_SCALARS) do view[k] = w[k] end

  view.player = {}
  for _, k in ipairs(PLAYER_FIELDS) do view.player[k] = w.player[k] end
  view.player.ship = w.player.shipDef and w.player.shipDef.id

  view.weapons, view.passives = {}, {}
  for i, o in ipairs(w.weapons or {}) do
    view.weapons[i] = { id = o.def.id, level = o.level, cooldown = o.cooldown,
                        side = o.side, tickT = o.tickT }
  end
  for i, o in ipairs(w.passives or {}) do
    view.passives[i] = { id = o.def.id, level = o.level }
  end

  view.rng = {}
  for name, r in pairs(w.rng or {}) do view.rng[name] = r:getState() end
  view.spawnerTimers = {}
  for i, v in pairs(w.spawnerState and w.spawnerState.timers or {}) do
    view.spawnerTimers[i] = v
  end

  -- Lists keep their order: collision stops at the first hit in list order. Entities
  -- that point at others (a missile's target, a drone's hit cooldowns, world.boss) are
  -- compared by the pointed-at enemy's slot, so a lost or wrong link shows up.
  local slotOf = {}
  view.enemies = {}
  for _, e in ipairs(w.enemies or {}) do
    if not e.dead then
      view.enemies[#view.enemies + 1] = entityView(e)
      slotOf[e] = #view.enemies
    end
  end
  view.boss = w.boss and slotOf[w.boss] or nil

  for _, name in ipairs({ "ebullets", "bullets", "pickups", "drones" }) do
    local list = {}
    for _, e in ipairs(w[name] or {}) do
      if not e.dead then
        local v = entityView(e)
        if name == "bullets" and e.target then v.targetSlot = slotOf[e.target] end
        if name == "drones" then
          -- only cooldowns still running count: an expired one acts like none
          v.hitCd = {}
          for enemy, expiry in pairs(e.hitCd or {}) do
            if slotOf[enemy] and expiry > w.time then v.hitCd[slotOf[enemy]] = expiry end
          end
        end
        list[#list + 1] = v
      end
    end
    view[name] = list
  end
  return view
end

-- Path of the first difference between two worlds' simulation state, or nil.
function M.worldDiff(a, b)
  local va, vb = M.worldView(a), M.worldView(b)
  return M.firstDiff(va, vb, "world")
end

function M.noop() end

-- A table whose every missing key is a no-op function (stands in for a render or
-- audio module that needs a window / sound device).
function M.catchAll()
  return setmetatable({}, { __index = function() return M.noop end })
end

-- Load a private copy of `moduleName` with the modules in `stubs` (name -> table,
-- or true for a catch-all) replaced, then restore the real ones so other test
-- files are unaffected. Returns the loaded module.
function M.loadWithStubs(moduleName, stubs)
  local saved = {}
  for name in pairs(stubs) do saved[name] = package.loaded[name] end
  for name, stub in pairs(stubs) do
    package.loaded[name] = stub == true and M.catchAll() or stub
  end
  package.loaded[moduleName] = nil
  local ok, mod = pcall(require, moduleName)
  for name in pairs(stubs) do package.loaded[name] = saved[name] end
  package.loaded[moduleName] = nil
  if not ok then error(mod, 0) end
  return mod
end

-- Returns test(name, fn): registers T[name] so that setup() runs first and
-- teardown() ALWAYS runs afterwards, even when the test body fails; a failing
-- test therefore cannot leak stubs or registered states into later tests.
function M.guarded(T, setup, teardown)
  return function(name, fn)
    T[name] = function(t)
      setup()
      local ok, err = pcall(fn, t)
      teardown()
      if not ok then error(err, 0) end
    end
  end
end

-- In-memory stand-in for love.filesystem: read / write / remove over a table, with
-- a log of written names. Lets tests exercise Save's real file code path without
-- touching the player's actual save files.
-- missingReads counts read() calls for a file that is not there: LÖVE returns nil for
-- them, but the browser runtime (love.js) raises a fatal error even inside pcall, so the
-- game must never make one.
function M.memoryFilesystem()
  local fs = { files = {}, writes = {}, missingReads = 0 }
  function fs.getInfo(name)
    local contents = fs.files[name]
    if contents == nil then return nil end
    return { type = "file", size = #contents }
  end
  function fs.read(name)
    local contents = fs.files[name]
    if contents == nil then
      fs.missingReads = fs.missingReads + 1
      return nil, "not found: " .. name
    end
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

-- The same run as a version 2 (exact snapshot) save: player, running timers, weapon
-- cooldowns, and an empty field.
function M.validRun2(over)
  local run = M.validRun({
    version = 2, phase = "waves", warpT = 0,
    player = { x = 240, y = 518, vx = 0, vy = 0, invulnT = 0 },
    timers = { freezeT = 0, shieldT = 0, pulseT = 0, hpRingT = 0 },
    weapons = { { id = "blaster", level = 2, cooldown = 0.15 } },
    enemies = {}, bullets = {}, ebullets = {}, pickups = {}, drones = {},
  })
  for k, v in pairs(over or {}) do run[k] = v end
  return run
end

return M
