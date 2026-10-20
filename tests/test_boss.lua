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
    zoneTime = 0, -- read by Spawner.spawnEnemy when a boss drops adds
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

-- Entrance: starts at 95 px/s, decelerates, never stalls, ends exactly on arenaY.
local ENTER_SPEED, ENTER_FLOOR, ENTER_MAX_SECONDS = 95, 20, 4.0

function T.boss_entrance_decelerates_into_position(t)
  local bad = {}
  for _, id in ipairs(bossIds()) do
    local w = fakeWorld()
    local e = Boss.spawn(w, id)
    local speeds, prevY, arrivedAt = {}, e.y, nil
    for step = 1, 60 * 20 do
      Boss.update(w, DT)
      speeds[#speeds + 1] = (e.y - prevY) / DT
      prevY = e.y
      if not e.entering then arrivedAt = step break end
    end
    if not arrivedAt then
      bad[#bad + 1] = id .. " never arrived"
    else
      local arenaY = e.y
      local secs = arrivedAt * DT
      local problems = {}
      if secs > ENTER_MAX_SECONDS then
        problems[#problems + 1] = string.format("took %.2f s (limit %.1f)", secs, ENTER_MAX_SECONDS)
      end
      if math.abs(speeds[1] - ENTER_SPEED) > 1 then
        problems[#problems + 1] = string.format("starts at %.0f px/s, expected %d", speeds[1], ENTER_SPEED)
      end
      -- last step may be a short snap onto arenaY; judge the ones before it
      local n = #speeds - 1
      for i = 2, n do
        if speeds[i] > speeds[i - 1] + 1e-6 then
          problems[#problems + 1] = string.format("speeds up at step %d", i)
          break
        end
      end
      if n >= 1 and speeds[n] < ENTER_FLOOR - 0.5 then
        problems[#problems + 1] = string.format("slows to %.1f px/s, below floor %d", speeds[n], ENTER_FLOOR)
      end
      if n >= 1 and speeds[n] > ENTER_FLOOR + 0.5 then
        problems[#problems + 1] = string.format("still moving %.0f px/s one step before arrival, expected about %d",
          speeds[n], ENTER_FLOOR)
      end
      if e.y ~= arenaY or prevY > arenaY then
        problems[#problems + 1] = "overshoots arenaY"
      end
      if #problems > 0 then
        bad[#bad + 1] = id .. ": " .. table.concat(problems, ", ")
      end
    end
  end
  expectNone(t, bad, "boss entrance profile")
end

-- Leviathan: hover/telegraph/dive/rise. Dive and rise are fast on purpose; every
-- other step (notably the first one back in hover) must stay smooth.
local HOVER_STEP_LIMIT = 14 -- px per step; the return blend peaks near 12

function T.leviathan_eases_back_to_hover_after_a_dive(t)
  local w = fakeWorld(40) -- far from centre so every dive ends well off-path
  local e = stepToArrival(w, "mining_leviathan")
  local px, py = e.x, e.y
  local dives, worst, worstDesc = 0, 0, ""
  local prevState = e.state
  local hoverSince = nil
  local offPath, offPathDesc = 0, ""
  for step = 1, 60 * 20 do
    Boss.update(w, DT)
    local d = dist(e.x, e.y, px, py)
    if e.state ~= "dive" and e.state ~= "rise" and d > worst then
      worst = d
      worstDesc = string.format("step %d, state %s after %s", step, e.state, prevState)
    end
    if prevState == "dive" and e.state == "rise" then dives = dives + 1 end
    if e.state == "hover" then
      if prevState ~= "hover" then hoverSince = step end
      if dives > 0 and hoverSince and (step - hoverSince) >= 45 then -- 0.75 s in
        local dx = e.x - (VW * 0.5 + math.sin(e.bt * 0.8) * 130)
        if math.abs(dx) > offPath then
          offPath = math.abs(dx)
          offPathDesc = string.format("step %d", step)
        end
      end
    end
    prevState = e.state
    px, py = e.x, e.y
  end
  t.ok(dives >= 2, "simulation saw " .. dives .. " dives, expected at least 2")
  t.ok(worst <= HOVER_STEP_LIMIT, string.format(
    "leviathan moved %.1f px in one step outside dive/rise (%s), limit %d",
    worst, worstDesc, HOVER_STEP_LIMIT))
  t.ok(offPath <= 1, string.format(
    "leviathan still %.1f px off the hover path 0.75 s after returning (%s)",
    offPath, offPathDesc))
end

return T
