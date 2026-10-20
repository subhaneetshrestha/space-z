-- tests/test_boss.lua — boss entrance + movement continuity. Every boss in
-- content/bosses.lua is simulated from spawn, so a new boss is covered for free.
local Boss = require("src.systems.boss")
local Bosses = require("src.content.bosses")
local Pool = require("src.core.pool")
local Events = require("src.core.events")
local RNG = require("src.core.rng")
local Viewport = require("src.core.viewport")

local VW = Viewport.VW
local DT = 1 / 60

local T = {}

local function fakeWorld(playerX)
  return {
    events = Events.new(),
    rng = { spawn = RNG.new(1) },
    enemies = {}, ebullets = {},
    pools = { enemies = Pool.new(), ebullets = Pool.new() },
    player = { x = playerX or 240, y = 600 },
    pulseT = 0,
    boss = nil,
  }
end

local function bossIds()
  local ids = {}
  for id in pairs(Bosses) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- steps until the boss finishes its entrance; returns the boss (positioned at
-- arrival) or errors if it never arrives
local function stepToArrival(world, id)
  local e = Boss.spawn(world, id)
  for _ = 1, 60 * 20 do
    Boss.update(world, DT)
    if not e.entering then return e end
  end
  error(id .. ": never finished entering")
end

local function dist(ax, ay, bx, by)
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Natural patrol speed tops out near 1.8 px/step; dashes/dives start no earlier
-- than 2 s after arrival, so this window only sees the idle drift.
local ARRIVAL_WINDOW = 90 -- steps (1.5 s)
local MAX_STEP = 3        -- px

-- collects one line per offending boss so a failure names all of them
local function expectNone(t, bad, what)
  t.ok(#bad == 0, what .. ": " .. table.concat(bad, "; "))
end

function T.boss_continues_from_arrival_pose_without_a_snap(t)
  local bad = {}
  for _, id in ipairs(bossIds()) do
    local w = fakeWorld()
    local e = stepToArrival(w, id)
    local px, py = e.x, e.y
    local worst, worstStep = 0, 0
    for step = 1, ARRIVAL_WINDOW do
      Boss.update(w, DT)
      local d = dist(e.x, e.y, px, py)
      if d > worst then worst, worstStep = d, step end
      px, py = e.x, e.y
    end
    if worst > MAX_STEP then
      bad[#bad + 1] = string.format("%s moved %.1f px in one step (step %d)",
        id, worst, worstStep)
    end
  end
  expectNone(t, bad, "boss snapped after arrival (limit " .. MAX_STEP .. " px)")
end

function T.boss_first_behavior_step_stays_at_arena_position(t)
  local bad = {}
  for _, id in ipairs(bossIds()) do
    local w = fakeWorld()
    local e = stepToArrival(w, id)
    local arenaY = e.y
    Boss.update(w, DT)
    if math.abs(e.x - VW * 0.5) > MAX_STEP or math.abs(e.y - arenaY) > 1 then
      bad[#bad + 1] = string.format("%s at (%.1f, %.1f), expected (%.0f, %.1f)",
        id, e.x, e.y, VW * 0.5, arenaY)
    end
  end
  expectNone(t, bad, "boss left its arrival pose on the first behavior step")
end

return T
