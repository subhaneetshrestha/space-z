-- src/meta/runsave.lua — snapshot and validation of an in-progress run.
-- Pure data: no love.* calls, so it runs headless under tests/run.lua.
-- Version 2 also holds the player (position, velocity, i-frames), the running timers
-- and every weapon's cooldown. Enemies, bullets, pickups and the boss are not saved
-- yet, so every snapshot still resumes in the "waves" phase.
local RNG = require("src.core.rng")
local Viewport = require("src.core.viewport")
local Ships = require("src.content.ships")
local Weapons = require("src.content.weapons")
local Upgrades = require("src.content.upgrades")
local Zones = require("src.content.zones")
local Leveling = require("src.systems.leveling")

local M = {}

local floor, huge = math.floor, math.huge

local RUN_VERSION = 2
local LEGACY_VERSION = 1 -- before the exact snapshot: no player, timers or cooldowns
local MAX_WEAPONS = Leveling.MAX_WEAPONS
local MAX_PASSIVES = Leveling.MAX_PASSIVES
local STREAMS = { "spawn", "drops", "cards", "misc" }

-- -------------------------------------------------------------- snapshot

local function ids(owned)
  local list = {}
  for i = 1, #owned do
    list[i] = { id = owned[i].def.id, level = owned[i].level }
  end
  return list
end

-- Weapons also keep their fire timer and scratch (homing launch side, beam / aura
-- tick), so a save never refills a weapon. `side` and `tickT` only exist once a
-- weapon has used them, and are saved only then.
local function weaponList(owned)
  local list = ids(owned)
  for i = 1, #owned do
    local w = owned[i]
    list[i].cooldown = w.cooldown or 0
    list[i].side = w.side
    list[i].tickT = w.tickT
  end
  return list
end

-- spawnerState.timers is sparse (a stream's timer exists once it has opened),
-- which JSON cannot hold, so it is saved as sorted { index, value } pairs.
local function timerPairs(state)
  local list = {}
  local timers = state and state.timers
  if type(timers) ~= "table" then return list end
  for i, v in pairs(timers) do list[#list + 1] = { i, v } end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  return list
end

-- RunSave.snapshot(world, opts) -> run table, or nil when the run must not be saved
-- (dead, over, daily, autopilot, or already won). opts.draftOpen: a level-up draft
-- is on screen right now; it was already taken off pendingLevelUps, so put it back.
function M.snapshot(world, opts)
  if world.phase == "over" or world.player.dead then return nil end
  if world.daily or world.autopilot then return nil end

  local run = {
    version = RUN_VERSION,
    mode = world.mode,
    seed = world.seed,
    ship = world.player.shipDef.id,
    time = world.time,
    distance = world.distance,
    zoneIndex = world.zoneIndex,
    zoneTime = world.zoneTime,
    zoneStartDistance = world.zoneStartDistance,
    level = world.level,
    xp = world.xp,
    xpNext = world.xpNext,
    pendingLevelUps = world.pendingLevelUps + ((opts and opts.draftOpen) and 1 or 0),
    kills = world.kills,
    bossKills = world.bossKills,
    noDamage = world.noDamage,
    stardustEarned = world.stardustEarned,
    hp = world.player.hp,
    player = {
      x = world.player.x, y = world.player.y,
      vx = world.player.vx, vy = world.player.vy,
      invulnT = world.player.invulnT,
    },
    timers = {
      freezeT = world.freezeT, shieldT = world.shieldT,
      pulseT = world.pulseT, hpRingT = world.hpRingT,
    },
    weapons = weaponList(world.weapons),
    passives = ids(world.passives),
    rng = {},
    spawnerTimers = timerPairs(world.spawnerState),
  }
  for i = 1, #STREAMS do
    run.rng[STREAMS[i]] = world.rng[STREAMS[i]]:getState()
  end

  if world.phase == "boss" then
    -- the boss itself is not saved: rewind to the moment it was triggered, when
    -- the field is empty, so the spawner brings it in again at full health
    run.zoneTime = world.zone.duration
    run.spawnerTimers = {}
  elseif world.phase == "warp" then
    -- boss just died: resume at the start of the next zone
    if not Zones[world.zoneIndex + 1] then return nil end
    run.zoneIndex = world.zoneIndex + 1
    run.zoneTime = 0
    run.zoneStartDistance = world.distance
    run.spawnerTimers = {}
  end
  return run
end

-- -------------------------------------------------------------- validate

local function isNum(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function isInt(v)
  return isNum(v) and v == floor(v)
end

local function nonNeg(v) return isNum(v) and v >= 0 end

-- A weapon timer above this would silence the weapon for good (real cooldowns are
-- seconds), so a larger one can only come from a corrupt or edited file.
local MAX_WEAPON_TIMER = 3600
-- Nothing in the game moves anywhere near this fast (the fastest bullet is ~700).
local MAX_SPEED = 5000

-- version 2: a weapon entry also carries its timer and optional scratch
local function validWeaponState(e)
  if not (isNum(e.cooldown) and e.cooldown >= 0 and e.cooldown <= MAX_WEAPON_TIMER) then
    return false
  end
  if e.side ~= nil and e.side ~= 1 and e.side ~= -1 then return false end
  if e.tickT ~= nil and not (isNum(e.tickT) and e.tickT >= -1 and e.tickT <= MAX_WEAPON_TIMER) then
    return false
  end
  return true
end

-- list of { id, level } entries: known ids from `defs`, unique, level 1..maxLevel.
-- withState: also check the weapon timers (version 2 saves).
local function validOwned(list, defs, cap, wantKind, withState)
  if type(list) ~= "table" or #list > cap then return false end
  local seen = {}
  for i = 1, #list do
    local e = list[i]
    if type(e) ~= "table" or type(e.id) ~= "string" or seen[e.id] then return false end
    local def = defs[e.id]
    if not def or def.kind ~= wantKind then return false end
    if not isInt(e.level) or e.level < 1 or e.level > def.maxLevel then return false end
    if withState and not validWeaponState(e) then return false end
    seen[e.id] = true
  end
  return true
end

-- version 2: where the ship is and how it is moving. Only what could crash or
-- hang the game is bounded; invulnT is not capped, since an edited save can
-- already hand out anything, and the test harness holds it at 1e9.
local function validPlayer(p)
  if type(p) ~= "table" then return false end
  return isNum(p.x) and p.x >= 0 and p.x <= Viewport.VW
    and isNum(p.y) and p.y >= 0 and p.y <= Viewport.VH
    and isNum(p.vx) and math.abs(p.vx) <= MAX_SPEED
    and isNum(p.vy) and math.abs(p.vy) <= MAX_SPEED
    and nonNeg(p.invulnT)
end

-- version 2: hit-stop, shield recharge, gravity pulse and hull-ring timers
local function validRunning(tm)
  if type(tm) ~= "table" then return false end
  return nonNeg(tm.freezeT) and nonNeg(tm.shieldT)
    and nonNeg(tm.pulseT) and nonNeg(tm.hpRingT)
end

-- { waveIndex, secondsLeft } pairs. Spawner.update loops `while timer <= 0` (adding
-- the wave's interval each pass), so a live timer is always in (0, interval]; a
-- value outside that from a corrupt file would spawn for ~forever on resume.
-- The small tolerance covers json.lua's 14-digit float round trip.
local TIMER_TOLERANCE = 1e-9

local function validTimers(list, zone)
  if type(list) ~= "table" or #list > #zone.waves then return false end
  for i = 1, #list do
    local e = list[i]
    if type(e) ~= "table" or not isInt(e[1]) or e[1] < 1 or e[1] > #zone.waves
        or not isNum(e[2]) then
      return false
    end
    if e[2] <= 0 or e[2] > zone.waves[e[1]].interval * (1 + TIMER_TOLERANCE) then
      return false
    end
  end
  return true
end

-- RunSave.validate(run) -> true only if every field is present, well-typed and in
-- range. The save file is untrusted input: anything else counts as "no save".
function M.validate(run)
  if type(run) ~= "table" then return false end
  local exact = run.version == RUN_VERSION
  if not exact and run.version ~= LEGACY_VERSION then return false end
  if run.mode ~= "standard" and run.mode ~= "blackhole" then return false end
  if not isNum(run.seed) then return false end
  if type(run.ship) ~= "string" or not Ships[run.ship] then return false end

  if not (nonNeg(run.time) and nonNeg(run.distance) and nonNeg(run.zoneTime)
      and nonNeg(run.zoneStartDistance) and nonNeg(run.xp)
      and nonNeg(run.stardustEarned)) then
    return false
  end
  if not isInt(run.zoneIndex) or run.zoneIndex < 1 or run.zoneIndex > #Zones then
    return false
  end
  if not isInt(run.level) or run.level < 1 then return false end
  if not isNum(run.xpNext) or run.xpNext <= 0 then return false end
  -- one draft opens per frame while this is > 0; it can never exceed the level
  if not isInt(run.pendingLevelUps) or run.pendingLevelUps < 0
      or run.pendingLevelUps > run.level then
    return false
  end
  if not isInt(run.kills) or run.kills < 0 then return false end
  if not isInt(run.bossKills) or run.bossKills < 0 then return false end
  if type(run.noDamage) ~= "boolean" then return false end
  if not isNum(run.hp) or run.hp <= 0 then return false end

  if not validOwned(run.weapons, Weapons, MAX_WEAPONS, "weapon", exact)
      or #run.weapons < 1 then
    return false
  end
  if not validOwned(run.passives, Upgrades, MAX_PASSIVES, "passive") then return false end
  if exact and not (validPlayer(run.player) and validRunning(run.timers)) then
    return false
  end

  if type(run.rng) ~= "table" then return false end
  for i = 1, #STREAMS do
    -- RNG:setState is the one place that knows the legal state range
    if not RNG.new(1):setState(run.rng[STREAMS[i]]) then return false end
  end

  return validTimers(run.spawnerTimers, Zones[run.zoneIndex])
end

-- ----------------------------------------------------------------- apply

local function fill(list, owned, defs)
  for i = #list, 1, -1 do list[i] = nil end
  for i = 1, #owned do
    list[i] = { def = defs[owned[i].id], level = owned[i].level }
  end
end

-- RunSave.apply(world, run) -> true, or false (world untouched) if the run is invalid.
-- `world` is a fresh world built by game:enter; this overwrites its progression
-- with the saved one. A version 1 save has no player, timers or cooldowns, so those
-- keep their new-run values.
function M.apply(world, run)
  if not M.validate(run) then return false end

  local ship = Ships[run.ship]
  local player = world.player
  player.shipDef = ship
  player.sprite = ship.sprite

  world.mode = run.mode
  world.seed = run.seed
  world.time = run.time
  world.distance = run.distance
  world.zoneIndex = run.zoneIndex
  world.zone = Zones[run.zoneIndex]
  world.zoneTime = run.zoneTime
  world.zoneStartDistance = run.zoneStartDistance
  world.phase = "waves"
  world.boss = nil
  world.warpT = 0

  world.level = run.level
  world.xp = run.xp
  world.xpNext = run.xpNext
  world.pendingLevelUps = run.pendingLevelUps
  world.kills = run.kills
  world.bossKills = run.bossKills
  world.noDamage = run.noDamage
  world.stardustEarned = run.stardustEarned

  -- the tables are filled in place: other code may already hold them
  local exact = run.version == RUN_VERSION
  fill(world.weapons, run.weapons, Weapons)
  for i = 1, #world.weapons do
    local w, saved = world.weapons[i], run.weapons[i]
    if exact then
      w.cooldown, w.side, w.tickT = saved.cooldown, saved.side, saved.tickT
    else
      w.cooldown = 0 -- a version 1 save never held it: ready to fire
    end
  end
  fill(world.passives, run.passives, Upgrades)

  for i = 1, #STREAMS do
    world.rng[STREAMS[i]]:setState(run.rng[STREAMS[i]])
  end
  local timers = {}
  for i = 1, #run.spawnerTimers do
    timers[run.spawnerTimers[i][1]] = run.spawnerTimers[i][2]
  end
  world.spawnerState = { timers = timers }

  if exact then
    local p, tm = run.player, run.timers
    player.x, player.y, player.vx, player.vy = p.x, p.y, p.vx, p.vy
    player.invulnT = p.invulnT
    world.freezeT, world.shieldT = tm.freezeT, tm.shieldT
    world.pulseT, world.hpRingT = tm.pulseT, tm.hpRingT
  else
    -- a version 1 save: spawn point, nothing running
    player.vx, player.vy, player.invulnT = 0, 0, 0
    world.shieldT, world.hpRingT, world.freezeT, world.pulseT = 0, 0, 0, 0
  end

  -- rebuild stats from the restored ship + passives, then set the saved hull
  -- (recomputeStats alone would leave a full hull)
  Leveling.recomputeStats(world)
  player.hp = math.max(1, math.min(run.hp, player.maxhp))
  return true
end

return M
