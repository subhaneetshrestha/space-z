-- tests/test_save.lua — defaults, headless behavior, and Progress.endRun accounting.
local Save = require("src.meta.save")
local Progress = require("src.meta.progress")

local T = {}

local function freshData()
  return Save.reset()
end

function T.defaults_shape(t)
  local d = freshData()
  t.eq(d.version, 1)
  t.eq(d.stardust, 0)
  t.eq(d.totalRuns, 0)
  t.eq(d.unlocked.blackhole, false)
  t.eq(d.settings.quality, "high")
  t.eq(d.settings.steerMode, nil, "steerMode retired: steering is always 1:1 drag")
  t.eq(d.run, nil, "no saved run by default; old saves without the key load fine")
  t.eq(d.version, 1, "adding run needs no schema bump")
end

function T.data_memoizes(t)
  local a = Save.data()
  local b = Save.data()
  t.eq(a, b, "same table")
end

local function fakeWorld(over)
  local w = {
    mode = "standard",
    kills = 100, bossKills = 1, distance = 3000, stardustEarned = 25,
    level = 7, zoneIndex = 1, time = 150, noDamage = false,
  }
  for k, v in pairs(over or {}) do w[k] = v end
  return w
end

function T.endrun_stardust_formula(t)
  freshData()
  local summary = Progress.endRun(fakeWorld(), false)
  -- kills(100) + 5*floor(3000/1000)(15) + 40*bossKills(40) + in-run(25) = 180
  t.eq(summary.stardust, 180, "stardust formula")
  t.eq(Save.data().stardust, 180, "banked into save")
  t.eq(Save.data().totalRuns, 1, "run counted")
end

function T.endrun_best_tracking(t)
  freshData()
  Progress.endRun(fakeWorld({ distance = 5000, level = 9 }), false)
  Progress.endRun(fakeWorld({ distance = 2000, level = 4 }), false)
  t.eq(Save.data().bestDistance, 5000, "best distance keeps max")
  t.eq(Save.data().bestLevel, 9, "best level keeps max")
end

function T.blackhole_unlock_rules(t)
  freshData()
  -- lost run, no damage: no unlock
  Progress.endRun(fakeWorld({ noDamage = true }), false)
  t.eq(Save.data().unlocked.blackhole, false, "loss never unlocks")
  -- won but damaged: no unlock
  Progress.endRun(fakeWorld({ noDamage = false }), true)
  t.eq(Save.data().unlocked.blackhole, false, "damaged win never unlocks")
  -- flawless standard win: unlock
  local summary = Progress.endRun(fakeWorld({ noDamage = true }), true)
  t.eq(Save.data().unlocked.blackhole, true, "flawless win unlocks")
  t.eq(summary.unlockedBlackhole, true, "summary reports the reveal")
  -- second flawless win: already unlocked, no re-reveal
  local again = Progress.endRun(fakeWorld({ noDamage = true }), true)
  t.ok(not again.unlockedBlackhole, "no repeat reveal")
end

return T
