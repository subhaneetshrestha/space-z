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
local Weapons = require("src.content.weapons")

local M = {}

local VW, VH = Viewport.VW, Viewport.VH

-- Provisional caps: one smoke run peaks at ~190 live entities of all kinds. The final
-- figures are set from measured worst cases (task A6); they only reject corrupt files.
M.MAX_ENEMIES = 600
M.MAX_BULLETS = 1500
M.MAX_EBULLETS = 2000

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

-- Entities are saved in list order: collision stops at the first hit in list order,
-- and Pool.sweep swap-removes, so the order is part of the state. A boss (no def) is
-- not captured here; until bosses are saved the snapshot only calls this in waves.
-- Returns the entries and a map enemy table -> slot, which is how other entities
-- (a homing missile's target) point at an enemy in the save.
function M.captureEnemies(list)
  local out, slotOf = {}, {}
  for i = 1, #list do
    local e = list[i]
    if not e.dead and e.def then
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
    local def = Enemies[s.def]
    local e = pool:acquire()
    e.kind = "enemy"
    e.def = def
    e.sprite = def.sprite
    e.dead = false
    for k in pairs(ENEMY_SAVED) do e[k] = s[k] end
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

-- The saved `enemies` list of a version 2 run.
function M.validEnemies(list)
  if not isSequence(list) or #list > M.MAX_ENEMIES then return false end
  for i = 1, #list do
    if not validEnemy(list[i]) then return false end
  end
  return true
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

return M
