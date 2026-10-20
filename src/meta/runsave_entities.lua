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

local M = {}

local VW, VH = Viewport.VW, Viewport.VH

-- Provisional cap: one smoke run peaks at ~190 live entities of all kinds. The final
-- figure is set from measured worst cases (task A6); it only rejects corrupt files.
M.MAX_ENEMIES = 600

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
function M.captureEnemies(list)
  local out = {}
  for i = 1, #list do
    local e = list[i]
    if not e.dead and e.def then
      local s = { def = e.def.id }
      for k in pairs(ENEMY_SAVED) do s[k] = e[k] end
      out[#out + 1] = s
    end
  end
  return out
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

return M
