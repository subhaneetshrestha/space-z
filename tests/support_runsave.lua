-- tests/support_runsave.lua — helpers the run-save entity tests share: build a world,
-- resume a twin of it through the real game state, and step both to find a divergence.
local StateM = require("src.core.state")
local RunSave = require("src.meta.runsave")
local Enemies = require("src.content.enemies")
local Spawner = require("src.systems.spawner")
local Pickups = require("src.systems.pickups")
local json = require("lib.json")
local Support = require("tests.support")
local H = require("tests.game_harness")

local STEP = H.STEP

local S = {}

function S.roundTrip(run)
  return json.decode(json.encode(run))
end

-- sorted ids, so a fixture is the same on every run
function S.idsWhere(pred)
  local ids = {}
  for id, def in pairs(Enemies) do
    if pred(def) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

function S.updateGame(n)
  for _ = 1, n or 1 do H.Game:update(STEP) end
end

-- A run with one enemy of each id in `ids` on screen and every weapon silenced, so
-- nothing the player does changes the enemies (bullets are saved from A3 on).
function S.arena(ids, opts)
  local w = H.start({ seed = 424 })
  for i = 1, #w.weapons do w.weapons[i].cooldown = 3000 end
  for i, id in ipairs(ids) do
    Spawner.spawnEnemy(w, id, 50 + (i * 53) % 380, 60 + (i * 37) % 160, opts and opts[id])
  end
  return w
end

-- The resumed copy, built by the real game:enter. It lives beside the original
-- (the original is H.Game itself), so both can be stepped with the same call.
function S.resumeTwin(run)
  local twin = setmetatable({}, { __index = H.Game })
  twin:enter({ resume = run, seed = run.seed })
  while StateM.current() ~= H.Game do StateM.pop() end -- drop the 3-2-1
  return twin
end

-- Step both for `frames`; returns the frame and path of the first difference.
function S.stepBoth(twin, frames)
  for f = 1, frames do
    H.Game:update(STEP)
    twin:update(STEP)
    local d = Support.worldDiff(H.Game.world, twin.world)
    if d then return f, d end
  end
end

function S.identical(t, w, frames)
  local run = S.roundTrip(RunSave.snapshot(w))
  local twin = S.resumeTwin(run)
  t.eq(Support.worldDiff(w, twin.world), nil, "the resumed world starts equal")
  local f, d = S.stepBoth(twin, frames)
  t.eq(d, nil, "diverged at frame " .. tostring(f))
end


-- Enemies that take hits but never die: kills drop pickups, and collecting
-- them would change the xp. Wraps Spawner.spawnEnemy, which the
-- spawner and the boss adds call through the module table, so every enemy is covered.
function S.withDurableEnemies(fn)
  local original = Spawner.spawnEnemy
  Spawner.spawnEnemy = function(...)
    local e = original(...)
    e.hp, e.maxhp = 1e8, 1e8
    return e
  end
  local ok, err = pcall(fn)
  Spawner.spawnEnemy = original
  if not ok then error(err, 0) end
end

function S.indexOf(list, item)
  for i = 1, #list do if list[i] == item then return i end end
end

-- keep playing until pred() holds (or `limit` frames pass)
function S.stepUntil(pred, limit)
  for _ = 1, limit or 900 do
    if pred() then return true end
    S.updateGame(1)
  end
  return pred()
end

function S.dropGems(w)
  local p = w.player
  Pickups.dropXp(w, p.x + 150, p.y - 260, 1)   -- far: drifts down, tier 1
  Pickups.dropXp(w, p.x - 150, p.y - 300, 7)   -- tier 2
  Pickups.dropXp(w, p.x + 40, p.y - 30, 30)    -- tier 3, inside the magnet radius (70 px)
  Pickups.dropXp(w, p.x - 25, p.y - 20, 2)     -- inside the magnet radius
end

-- a valid enemy entry, one per movement type with the scratch that movement grows
function S.enemy(def, over)
  local e = {
    def = def or "drifter", x = 100, y = 200, vx = 0, vy = 70, r = 14, rot = 0,
    scale = 1, t = 1.5, hp = 18, maxhp = 18, touchDamage = 8, xp = 1,
    elite = false, flashT = 0,
  }
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end

-- a valid entry per movement type, with the scratch that movement grows
S.VALID = {
  drift = S.enemy("drifter", { phase = 1.2, baseX = 100, spin = 0.9 }),
  sine = S.enemy("shard", { baseX = 100 }),
  chaser = S.enemy("stinger", { spd = 152 }),
  shooter = S.enemy("sentry", { phase = "hold", baseX = 100, fireT = 1.1 }),
  lunge = S.enemy("lunar_hopper", { phase = "dash", lungeT = 0.3 }),
  ballistic = S.enemy("meteor", { spin = 4 }),
}

S.NAN = 0 / 0

function S.with(movement, over)
  local e = {}
  for k, v in pairs(S.VALID[movement]) do e[k] = v end
  for k, v in pairs(over) do e[k] = v end
  return e
end

function S.without(movement, key)
  local e = S.with(movement, {})
  e[key] = nil
  return e
end



function S.ebullet(over)
  local b = { x = 240, y = 100, vx = 0, vy = 150, r = 6, rot = 0, scale = 1, t = 0.5, damage = 10, life = 8 }
  for k, v in pairs(over or {}) do b[k] = v end
  return b
end

return S
