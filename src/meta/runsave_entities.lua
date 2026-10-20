-- src/meta/runsave_entities.lua — the live field inside a run save: capture, restore
-- and validation of entities. Pure data (no love.*), used by runsave.lua.
--
-- Every entity kind has an explicit list of saved fields. Anything else on a live
-- entity is either DERIVED (rebuilt from its def on restore) or an error: the
-- completeness test runs long simulations and fails on any key that is neither, so a
-- new behaviour field cannot be silently dropped from saves.
--
-- A save is untrusted input. Besides types and ranges, validation enforces what the
-- movement code assumes after its lazy init: an entry that carries part of a
-- movement's scratch state (a shooter holding position without its x anchor) would
-- index nil on the first frame after the resume, so it rejects the whole save.
local Viewport = require("src.core.viewport")
local Enemies = require("src.content.enemies")
local Bosses = require("src.content.bosses")
local Weapons = require("src.content.weapons")
local Pickups = require("src.systems.pickups")
local WeaponSystem = require("src.systems.weapons")

local M = {}

local VW, VH = Viewport.VW, Viewport.VH
local TWO_PI = 2 * math.pi

-- Provisional caps: one smoke run peaks at ~190 live entities of all kinds. The final
-- figures are set from measured worst cases (task A6); they only reject corrupt files.
M.MAX_ENEMIES = 600
M.MAX_BULLETS = 1500
M.MAX_EBULLETS = 2000
M.MAX_PICKUPS = 1500
M.MAX_DRONES = 16 -- the biggest weapon level has 6

-- ------------------------------------------------------------------ helpers

local function isNum(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function inRange(v, lo, hi)
  return isNum(v) and v >= lo and v <= hi
end

local function set(list)
  local s = {}
  for i = 1, #list do s[list[i]] = true end
  return s
end

-- the list is a plain sequence: no holes, no named keys
local function isSequence(list)
  if type(list) ~= "table" then return false end
  local n = 0
  for _ in pairs(list) do n = n + 1 end
  return n == #list
end

-- ------------------------------------------------------------------ enemies

-- Always present on a live enemy (Spawner.spawnEnemy sets every one of them).
local ENEMY_REQUIRED = {
  "x", "y", "vx", "vy", "r", "rot", "scale", "t", "hp", "maxhp",
  "touchDamage", "xp", "elite", "flashT",
}
-- Created lazily by a movement pattern or by damage; nil until then.
local ENEMY_SCRATCH = { "phase", "baseX", "spin", "spd", "fireT", "lungeT", "slowT", "slowMult" }

local ENEMY_SAVED = set(ENEMY_REQUIRED)
for _, k in ipairs(ENEMY_SCRATCH) do ENEMY_SAVED[k] = true end

-- On a live enemy but not saved: `def` is saved as an id, `sprite` is the def's, and
-- `kind` / `dead` are constants of a live entity (dead ones are not saved at all).
local ENEMY_DERIVED = set({ "kind", "def", "sprite", "dead" })

-- Keys of a live enemy that are neither saved nor derived (the completeness check).
function M.unclassifiedEnemyKeys(e)
  local out = {}
  for k in pairs(e) do
    if not ENEMY_SAVED[k] and not ENEMY_DERIVED[k] then out[#out + 1] = k end
  end
  return out
end

-- ------------------------------------------------------------------- bosses
-- A boss is an enemy in the same list, with a `boss` id where an enemy has `def`.
-- (boss.lua) It has the common fields below, plus what its pattern grows. A pattern
-- sets its fields in an init that runs when the entrance ends, so an entering boss has
-- none of them and a finished one has all of them.

local BOSS_FIELDS = set({
  "x", "y", "vx", "vy", "r", "rot", "scale", "t", "bt", "hp", "maxhp",
  "touchDamage", "xp", "elite", "flashT", "entering", "bossPhase",
})
-- On a live boss but not saved: the def is saved as an id, the sprite is the def's
local BOSS_DERIVED = set({ "kind", "isBoss", "bossDef", "sprite", "dead" })

-- how a pattern field is checked: { lo, hi } a number, { lo, hi, int = true } an
-- integer, { enum = set } a state name, "bool"
local TIMER = { -30, 120 } -- stateT runs below zero while a state that never reads it plays
local SCREEN_X = { -300, VW + 300 }
local ANGLE = { -1e7, 1e7 } -- spiral angles only ever grow
local OFFSET = { -2000, 2000 }

local BOSS_PATTERNS = {
  kessler = { burstT = TIMER, fanT = TIMER, addT = TIMER },
  leviathan = {
    state = { enum = set({ "hover", "telegraph", "dive", "rise" }) },
    stateT = TIMER, meteorT = TIMER, baseX = SCREEN_X,
    hoverOffX = OFFSET, hoverOffY = OFFSET, hoverT = { 0, 1e7 },
    diveX = SCREEN_X,
  },
  warmachine = {
    state = { enum = set({ "fans", "spiral" }) },
    stateT = TIMER, shotT = TIMER, spiralA = ANGLE, fanShots = { 0, 100, int = true },
  },
  titan = { burstT = TIMER, addT = TIMER },
  storm = {
    state = { enum = set({ "drift", "telegraph", "dash", "pulse" }) },
    stateT = TIMER, dashes = { 0, 1e7, int = true }, dashX = SCREEN_X,
  },
  guardian = { wallT = TIMER, fanT = TIMER, wallFlip = "bool" },
  overlord = {
    fanT = TIMER, spiralT = TIMER, spiralA = ANGLE, radialT = TIMER, addT = TIMER, wallT = TIMER,
  },
}
-- set when a state first needs them, and left behind after: absent until then
local PATTERN_OPTIONAL = { leviathan = set({ "diveX" }), storm = set({ "dashX" }) }
-- states that read an optional field the moment they run
local STATE_NEEDS = {
  leviathan = { telegraph = "diveX", dive = "diveX" },
  storm = { telegraph = "dashX", dash = "dashX" },
}

-- Keys of a live boss that are neither saved, derived, nor its own pattern's.
function M.unclassifiedBossKeys(e)
  local pattern = e.bossDef and BOSS_PATTERNS[e.bossDef.behavior] or {}
  local out = {}
  for k in pairs(e) do
    if not BOSS_FIELDS[k] and not BOSS_DERIVED[k] and not pattern[k] then out[#out + 1] = k end
  end
  return out
end

-- Entities are saved in list order: collision stops at the first hit in list order,
-- and Pool.sweep swap-removes, so the order is part of the state.
-- Returns the entries and a map enemy table -> slot, which is how other entities
-- (a homing missile's target, world.boss) point at an enemy in the save.
function M.captureEnemies(list)
  local out, slotOf = {}, {}
  for i = 1, #list do
    local e = list[i]
    if not e.dead and e.bossDef then
      local s = { boss = e.bossDef.id }
      for k in pairs(BOSS_FIELDS) do s[k] = e[k] end
      for k in pairs(BOSS_PATTERNS[e.bossDef.behavior]) do s[k] = e[k] end
      out[#out + 1] = s
      slotOf[e] = #out
    elseif not e.dead and e.def then
      local s = { def = e.def.id }
      for k in pairs(ENEMY_SAVED) do s[k] = e[k] end
      out[#out + 1] = s
      slotOf[e] = #out
    end
  end
  return out, slotOf
end

-- Replace world.enemies with the saved ones, same order, as fresh pooled tables.
function M.restoreEnemies(world, entries)
  local list, pool = world.enemies, world.pools.enemies
  for i = #list, 1, -1 do
    pool:release(list[i])
    list[i] = nil
  end
  for i = 1, #entries do
    local s = entries[i]
    local e = pool:acquire()
    e.kind = "enemy"
    e.dead = false
    if s.boss then
      local def = Bosses[s.boss]
      e.isBoss = true
      e.bossDef = def
      e.sprite = def.sprite
      for k in pairs(BOSS_FIELDS) do e[k] = s[k] end
      for k in pairs(BOSS_PATTERNS[def.behavior]) do e[k] = s[k] end
    else
      local def = Enemies[s.def]
      e.def = def
      e.sprite = def.sprite
      for k in pairs(ENEMY_SAVED) do e[k] = s[k] end
    end
    list[i] = e
  end
end

-- Which scratch fields each movement pattern grows, and whether they come as a set.
-- (movement.lua: drift / shooter / lunge test `e.phase == nil` once and initialise a
-- group together; sine / chaser / ballistic test a single field.)
local SCRATCH_OF = {
  drift = { "phase", "baseX", "spin" },
  sine = { "baseX" },
  chaser = { "spd" },
  shooter = { "phase", "baseX", "fireT" },
  lunge = { "phase", "lungeT" },
  ballistic = { "spin" },
}
local ALL_OR_NONE = { drift = true, shooter = true, lunge = true }
local PHASES = { -- string phases; drift's phase is a number
  shooter = { descend = true, hold = true },
  lunge = { descend = true, dash = true },
}

-- Sane bounds. They only have to keep a corrupt value from crashing or hanging the
-- game: timers that the movement code counts down with a single `if` (not a loop)
-- are bounded above so they cannot silence an enemy for good.
local RANGE = {
  x = { -300, VW + 300 }, y = { -300, VH + 300 },
  vx = { -5000, 5000 }, vy = { -5000, 5000 },
  r = { 0.1, 200 }, scale = { 0.1, 10 }, rot = { -1e4, 1e4 }, t = { 0, 1e7 },
  touchDamage = { 0, 1e4 }, xp = { 0, 1e6 }, flashT = { 0, 10 },
  baseX = { -300, VW + 300 }, spin = { -100, 100 }, spd = { 0.1, 5000 },
  fireT = { -1, 60 }, lungeT = { -1, 60 },
  slowT = { -1, 600 }, slowMult = { 0.01, 1 },
}

local function validEnemy(s)
  if type(s) ~= "table" then return false end
  local def = type(s.def) == "string" and Enemies[s.def]
  if not def then return false end
  for k in pairs(s) do
    if k ~= "def" and not ENEMY_SAVED[k] then return false end
  end

  for k, bounds in pairs(RANGE) do
    if s[k] ~= nil and k ~= "phase" and not inRange(s[k], bounds[1], bounds[2]) then
      return false
    end
  end
  for _, k in ipairs({ "x", "y", "vx", "vy", "r", "rot", "scale", "t", "touchDamage", "xp", "flashT" }) do
    if s[k] == nil then return false end
  end
  if type(s.elite) ~= "boolean" then return false end
  if not (isNum(s.maxhp) and s.maxhp > 0 and s.maxhp <= 1e9) then return false end
  -- a live enemy has hp left; the tolerance covers json.lua's 14-digit round trip
  if not (isNum(s.hp) and s.hp > 0 and s.hp <= s.maxhp * (1 + 1e-9)) then return false end

  -- scratch: only what this enemy's movement grows (slow state is common to all)
  local movement = def.movement
  local own = set(SCRATCH_OF[movement] or {})
  for _, k in ipairs(ENEMY_SCRATCH) do
    if s[k] ~= nil and not own[k] and k ~= "slowT" and k ~= "slowMult" then return false end
  end
  if ALL_OR_NONE[movement] then
    local present = 0
    for _, k in ipairs(SCRATCH_OF[movement]) do
      if s[k] ~= nil then present = present + 1 end
    end
    if present ~= 0 and present ~= #SCRATCH_OF[movement] then return false end
  end

  if s.phase ~= nil then
    local allowed = PHASES[movement]
    if allowed then
      if type(s.phase) ~= "string" or not allowed[s.phase] then return false end
    elseif not inRange(s.phase, -1e4, 1e4) then -- drift: a number
      return false
    end
  end
  return true
end

local function fieldOk(spec, v)
  if spec == "bool" then return type(v) == "boolean" end
  if spec.enum then return type(v) == "string" and spec.enum[v] == true end
  if spec.int and not (isNum(v) and v == math.floor(v)) then return false end
  return inRange(v, spec[1], spec[2])
end

local BOSS_RANGE = {
  x = SCREEN_X, y = { -300, VH + 300 }, vx = { -5000, 5000 }, vy = { -5000, 5000 },
  r = { 0.1, 200 }, rot = { -1e4, 1e4 }, scale = { 0.1, 10 }, t = { 0, 1e7 }, bt = { 0, 1e7 },
  touchDamage = { 0, 1e4 }, xp = { 0, 1e6 }, flashT = { 0, 10 },
}

local function validBoss(s)
  local def = type(s.boss) == "string" and Bosses[s.boss]
  local pattern = def and BOSS_PATTERNS[def.behavior]
  if not pattern then return false end
  for k in pairs(s) do
    if k ~= "boss" and not BOSS_FIELDS[k] and not pattern[k] then return false end
  end

  for k, bounds in pairs(BOSS_RANGE) do
    if not inRange(s[k], bounds[1], bounds[2]) then return false end
  end
  if s.elite ~= false or type(s.entering) ~= "boolean" then return false end
  if s.bossPhase ~= 1 and s.bossPhase ~= 2 then return false end
  if not (isNum(s.maxhp) and s.maxhp > 0 and s.maxhp <= 1e9) then return false end
  if not (isNum(s.hp) and s.hp > 0 and s.hp <= s.maxhp * (1 + 1e-9)) then return false end

  -- the pattern's init runs when the entrance ends: an entering boss has none of its
  -- fields, a finished one has every one that init sets
  local optional = PATTERN_OPTIONAL[def.behavior] or {}
  for k, spec in pairs(pattern) do
    local v = s[k]
    if s.entering then
      if v ~= nil then return false end
    elseif v == nil then
      if not optional[k] then return false end
    elseif not fieldOk(spec, v) then
      return false
    end
  end
  local needs = STATE_NEEDS[def.behavior]
  if needs and not s.entering and s[needs[s.state] or false] == nil and needs[s.state] then
    return false
  end
  return true
end

-- The saved `enemies` list of a version 2 run: enemies and, in a boss fight, the boss.
function M.validEnemies(list)
  if not isSequence(list) or #list > M.MAX_ENEMIES then return false end
  for i = 1, #list do
    local s = list[i]
    if type(s) ~= "table" then return false end
    if s.boss ~= nil then
      if not validBoss(s) then return false end
    elseif not validEnemy(s) then
      return false
    end
  end
  return true
end

-- A boss is in the list exactly in the boss phase, once, as world.boss, and it is the
-- boss of the run's zone. `slot` is the saved world.boss. Needs a validated list.
function M.validBossLink(list, bossPhase, slot, zoneBossId)
  local count, found = 0, nil
  for i = 1, #list do
    if list[i].boss ~= nil then
      count = count + 1
      found = i
    end
  end
  if not bossPhase then return count == 0 and slot == nil end
  return count == 1 and slot == found and list[found].boss == zoneBossId
end

-- ------------------------------------------------------------------ bullets
-- Player bullets (weapons.lua spawnBullet) and enemy bullets (movement.lua / boss.lua).
-- The sprite comes from the weapon (or is the enemy-bullet sprite), so it is derived.

local BULLET_FIELDS = set({
  "x", "y", "vx", "vy", "r", "rot", "scale", "t", "damage", "pierce", "life",
  "slowT", "slowMult", "aoe", "homing",
})
local BULLET_REQUIRED = set({
  "x", "y", "vx", "vy", "r", "rot", "scale", "t", "damage", "pierce", "life",
})
-- saved by hand, not by name: `weaponId` as is, `target` as a slot in the enemy list
local BULLET_SPECIAL = set({ "weaponId", "target" })
local BULLET_DERIVED = set({ "kind", "sprite", "dead" })

local EBULLET_FIELDS = set({ "x", "y", "vx", "vy", "r", "rot", "scale", "t", "damage", "life" })
local EBULLET_DERIVED = set({ "kind", "sprite", "dead" })

local function unclassified(e, saved, special, derived)
  local out = {}
  for k in pairs(e) do
    if not saved[k] and not (special and special[k]) and not derived[k] then out[#out + 1] = k end
  end
  return out
end

function M.unclassifiedBulletKeys(b)
  return unclassified(b, BULLET_FIELDS, BULLET_SPECIAL, BULLET_DERIVED)
end

function M.unclassifiedEbulletKeys(b)
  return unclassified(b, EBULLET_FIELDS, nil, EBULLET_DERIVED)
end

-- slotOf: the map captureEnemies returned. A target that is dead, or a pool table
-- that was wiped, has no slot and saves as nil: the steering code retargets the
-- nearest enemy for exactly those two cases. A table recycled into a new live enemy
-- is in the map, and that is also what the original would keep chasing.
function M.captureBullets(list, slotOf)
  local out = {}
  for i = 1, #list do
    local b = list[i]
    if not b.dead then
      local s = { weaponId = b.weaponId }
      for k in pairs(BULLET_FIELDS) do s[k] = b[k] end
      s.target = b.target and slotOf[b.target] or nil
      out[#out + 1] = s
    end
  end
  return out
end

function M.captureEbullets(list)
  local out = {}
  for i = 1, #list do
    local b = list[i]
    if not b.dead then
      local s = {}
      for k in pairs(EBULLET_FIELDS) do s[k] = b[k] end
      out[#out + 1] = s
    end
  end
  return out
end

local function clear(list, pool)
  for i = #list, 1, -1 do
    pool:release(list[i])
    list[i] = nil
  end
end

-- Call after restoreEnemies: a missile's target is a slot in world.enemies.
function M.restoreBullets(world, entries)
  local list, pool = world.bullets, world.pools.bullets
  clear(list, pool)
  for i = 1, #entries do
    local s = entries[i]
    local b = pool:acquire()
    b.kind = "bullet"
    b.sprite = Weapons[s.weaponId].sprite
    b.dead = false
    b.weaponId = s.weaponId
    for k in pairs(BULLET_FIELDS) do b[k] = s[k] end
    b.target = s.target and world.enemies[s.target] or nil
    list[i] = b
  end
end

function M.restoreEbullets(world, entries)
  local list, pool = world.ebullets, world.pools.ebullets
  clear(list, pool)
  for i = 1, #entries do
    local s = entries[i]
    local b = pool:acquire()
    b.kind = "ebullet"
    b.sprite = "bullet_enemy"
    b.dead = false
    for k in pairs(EBULLET_FIELDS) do b[k] = s[k] end
    list[i] = b
  end
end

-- Bounds that keep a corrupt value from crashing or hanging the game. Bullets are
-- culled 60 px outside the screen, so a live one is inside that, plus slack.
local BULLET_RANGE = {
  x = { -100, VW + 100 }, y = { -100, VH + 100 },
  vx = { -5000, 5000 }, vy = { -5000, 5000 },
  r = { 0.1, 100 }, scale = { 0.1, 10 }, rot = { -1e4, 1e4 }, t = { 0, 1e4 },
  damage = { 0, 1e7 }, life = { 1e-9, 60 },
  slowT = { 1e-3, 600 }, slowMult = { 0.01, 1 }, aoe = { 1, 1000 }, homing = { 0.01, 50 },
}
local EBULLET_RANGE = {
  x = BULLET_RANGE.x, y = BULLET_RANGE.y, vx = BULLET_RANGE.vx, vy = BULLET_RANGE.vy,
  r = BULLET_RANGE.r, scale = BULLET_RANGE.scale, rot = BULLET_RANGE.rot, t = BULLET_RANGE.t,
  damage = { 0, 1e4 }, life = BULLET_RANGE.life,
}

-- the weapons whose behaviour spawns bullets (weapons.lua: fireForward / Spread / Homing)
local FIRES_BULLETS = { forward = true, spread = true, homing = true }

local function validBullet(s, nEnemies)
  if type(s) ~= "table" then return false end
  local def = type(s.weaponId) == "string" and Weapons[s.weaponId]
  if not def or not FIRES_BULLETS[def.behavior] then return false end
  for k in pairs(s) do
    if k ~= "weaponId" and k ~= "target" and not BULLET_FIELDS[k] then return false end
  end
  for k in pairs(BULLET_REQUIRED) do
    if s[k] == nil then return false end
  end
  for k, bounds in pairs(BULLET_RANGE) do
    if s[k] ~= nil and not inRange(s[k], bounds[1], bounds[2]) then return false end
  end
  -- pierce counts down one per enemy hit and kills the bullet below zero
  if not (isNum(s.pierce) and s.pierce == math.floor(s.pierce) and s.pierce >= 0 and s.pierce <= 100) then
    return false
  end
  -- steering (weapons.lua) only touches bullets with `homing`, and missiles always have it
  if (def.behavior == "homing") ~= (s.homing ~= nil) then return false end
  if s.target ~= nil then
    local n = s.target
    if s.homing == nil or not isNum(n) or n ~= math.floor(n) or n < 1 or n > nEnemies then
      return false
    end
  end
  return true
end

local function validEbullet(s)
  if type(s) ~= "table" then return false end
  for k in pairs(s) do
    if not EBULLET_FIELDS[k] then return false end
  end
  for k in pairs(EBULLET_FIELDS) do
    if not inRange(s[k], EBULLET_RANGE[k][1], EBULLET_RANGE[k][2]) then return false end
  end
  return true
end

-- nEnemies: how many enemies the same save holds (a target is a slot among them)
function M.validBullets(list, nEnemies)
  if not isSequence(list) or #list > M.MAX_BULLETS then return false end
  for i = 1, #list do
    if not validBullet(list[i], nEnemies) then return false end
  end
  return true
end

function M.validEbullets(list)
  if not isSequence(list) or #list > M.MAX_EBULLETS then return false end
  for i = 1, #list do
    if not validEbullet(list[i]) then return false end
  end
  return true
end

-- ------------------------------------------------------------------ pickups
-- XP gems (pickups.lua). The sprite is a tier of the value, so it is derived.

local PICKUP_FIELDS = set({
  "ptype", "x", "y", "vx", "vy", "r", "rot", "scale", "t", "value", "magnet",
})
local PICKUP_DERIVED = set({ "kind", "sprite", "dead" })

function M.unclassifiedPickupKeys(p)
  return unclassified(p, PICKUP_FIELDS, nil, PICKUP_DERIVED)
end

function M.capturePickups(list)
  local out = {}
  for i = 1, #list do
    local p = list[i]
    if not p.dead then
      local s = {}
      for k in pairs(PICKUP_FIELDS) do s[k] = p[k] end
      out[#out + 1] = s
    end
  end
  return out
end

function M.restorePickups(world, entries)
  local list, pool = world.pickups, world.pools.pickups
  clear(list, pool)
  for i = 1, #entries do
    local s = entries[i]
    local p = pool:acquire()
    p.kind = "pickup"
    p.dead = false
    for k in pairs(PICKUP_FIELDS) do p[k] = s[k] end
    p.sprite = Pickups.tierSprite(s.value)
    list[i] = p
  end
end

-- a gem is culled once it falls 40 px below the screen; the magnet pulls it at <= 700
local PICKUP_RANGE = {
  x = { -400, VW + 400 }, y = { -400, VH + 200 },
  vx = { -5000, 5000 }, vy = { -5000, 5000 },
  r = { 0.1, 100 }, rot = { -1e4, 1e4 }, scale = { 0.1, 10 }, t = { 0, 1e7 },
  value = { 1e-6, 1e6 },
}

local function validPickup(s)
  if type(s) ~= "table" or s.ptype ~= "xp" or type(s.magnet) ~= "boolean" then return false end
  for k in pairs(s) do
    if not PICKUP_FIELDS[k] then return false end
  end
  for k, bounds in pairs(PICKUP_RANGE) do
    if not inRange(s[k], bounds[1], bounds[2]) then return false end
  end
  return true
end

function M.validPickups(list)
  if not isSequence(list) or #list > M.MAX_PICKUPS then return false end
  for i = 1, #list do
    if not validPickup(list[i]) then return false end
  end
  return true
end

-- ------------------------------------------------------------------- drones
-- Orbit drones (weapons.lua updateOrbital). `damage`, `orbitR` and `angVel` are
-- rewritten from the weapon level every frame but are saved too, so a restored drone
-- is complete before its first update. `hitCd` is keyed by enemy table, so it is saved
-- as { enemy slot, expiry } pairs, and only the cooldowns still running: an expired
-- one acts exactly like none. `hitCdN` only decides when that cache is tidied, so it
-- is rebuilt.

local DRONE_FIELDS = set({
  "x", "y", "vx", "vy", "r", "rot", "scale", "t", "angle", "damage", "orbitR", "angVel",
})
local DRONE_SPECIAL = set({ "hitCd" })
local DRONE_DERIVED = set({ "kind", "sprite", "dead", "hitCdN" })

function M.unclassifiedDroneKeys(d)
  return unclassified(d, DRONE_FIELDS, DRONE_SPECIAL, DRONE_DERIVED)
end

-- time: world.time; slotOf: the map captureEnemies returned
function M.captureDrones(list, slotOf, time)
  local out = {}
  for i = 1, #list do
    local d = list[i]
    if not d.dead then
      local s = { hitCd = {} }
      for k in pairs(DRONE_FIELDS) do s[k] = d[k] end
      for enemy, expiry in pairs(d.hitCd or {}) do
        local slot = slotOf[enemy]
        if slot and expiry > time then s.hitCd[#s.hitCd + 1] = { slot, expiry } end
      end
      table.sort(s.hitCd, function(a, b) return a[1] < b[1] end)
      out[#out + 1] = s
    end
  end
  return out
end

-- Call after restoreEnemies: a cooldown is a slot in world.enemies.
function M.restoreDrones(world, entries)
  local list, pool = world.drones, world.pools.drones
  clear(list, pool)
  for i = 1, #entries do
    local s = entries[i]
    local d = pool:acquire()
    d.kind = "drone"
    d.sprite = "drone"
    d.dead = false
    for k in pairs(DRONE_FIELDS) do d[k] = s[k] end
    d.hitCd = {}
    for j = 1, #s.hitCd do
      d.hitCd[world.enemies[s.hitCd[j][1]]] = s.hitCd[j][2]
    end
    d.hitCdN = #s.hitCd
    list[i] = d
  end
end

local DRONE_RANGE = {
  x = { -300, VW + 300 }, y = { -300, VH + 300 },
  vx = { -5000, 5000 }, vy = { -5000, 5000 },
  r = { 0.1, 100 }, rot = { -1e4, 1e4 }, scale = { 0.1, 10 }, t = { 0, 1e7 },
  angle = { 0, TWO_PI * (1 + 1e-9) }, -- updateOrbital wraps it at a full turn
  damage = { 0, 1e7 }, orbitR = { 1, 500 }, angVel = { -50, 50 },
}

local function validDrone(s, nEnemies, time)
  if type(s) ~= "table" then return false end
  for k in pairs(s) do
    if not DRONE_FIELDS[k] and not DRONE_SPECIAL[k] then return false end
  end
  for k, bounds in pairs(DRONE_RANGE) do
    if not inRange(s[k], bounds[1], bounds[2]) then return false end
  end
  local cds = s.hitCd
  if not isSequence(cds) or #cds > nEnemies then return false end
  local seen = {}
  for j = 1, #cds do
    local c = cds[j]
    if not isSequence(c) or #c ~= 2 then return false end
    local slot, expiry = c[1], c[2]
    if not (isNum(slot) and slot == math.floor(slot) and slot >= 1 and slot <= nEnemies) or seen[slot] then
      return false
    end
    seen[slot] = true
    -- still running: it started at or before `time`, and lasts DRONE_HIT_CD
    if not inRange(expiry, time + 1e-12, time + WeaponSystem.DRONE_HIT_CD * (1 + 1e-9)) then
      return false
    end
  end
  return true
end

-- Whether the saved build holds an orbital weapon: without one nothing updates the
-- drones, so a save that has drones anyway is not one the game could have written.
function M.ownsOrbital(weaponList)
  for i = 1, #weaponList do
    local def = Weapons[weaponList[i].id]
    if def and def.behavior == "orbital" then return true end
  end
  return false
end

-- nEnemies and time come from the same save; ownsOrbital from its weapons
function M.validDrones(list, nEnemies, time, ownsOrbital)
  if not isSequence(list) or #list > M.MAX_DRONES then return false end
  if #list > 0 and not ownsOrbital then return false end
  for i = 1, #list do
    if not validDrone(list[i], nEnemies, time) then return false end
  end
  return true
end

return M
