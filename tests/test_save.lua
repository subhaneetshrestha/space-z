-- tests/test_save.lua — defaults, headless behavior, and Progress.endRun accounting.
local Save = require("src.meta.save")
local Progress = require("src.meta.progress")
local Support = require("tests.support")

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
  t.eq(d.run, nil, "the run does not live in save.json")
  t.eq(d.version, 1, "no schema bump")
end

-- In the browser build (love.js) love.filesystem.read of a file that does not exist raises
-- a fatal error, even inside pcall, and a first visit has neither file. So loading may only
-- read what getInfo says is there. (Found by running the web build in Edge, 2026-10-21.)
function T.a_first_launch_reads_no_file_that_is_not_there(t)
  Support.withMemoryFs(function(fs)
    local data = Save.load()
    t.eq(Save.rawRun(), nil)
    t.eq(fs.missingReads, 0, "no read of a missing save.json or run.json")
    t.eq(data.stardust, 0, "and the defaults are in place")
  end)
end

function T.a_launch_with_a_save_but_no_run_reads_only_the_save(t)
  Support.withMemoryFs(function(fs)
    Save.reset()
    Save.data().stardust = 12
    Save.write()
    Save.clearRun()
    local data = Save.load()
    t.eq(Save.rawRun(), nil)
    t.eq(fs.missingReads, 0, "run.json is not read when it is not there")
    t.eq(data.stardust, 12, "the file that is there is still read")
  end)
end

-- ------------------------------------------------------- the run's own file
-- The saved run lives in run.json, never in save.json: it is rewritten every
-- ~10 s, and a torn write of save.json would wipe permanent progress.

local function validRun(over) return Support.validRun(over) end

function T.run_is_written_to_run_json_and_never_touches_save_json(t)
  Support.withMemoryFs(function(fs)
    Save.reset()
    local metaBefore = fs.files["save.json"]
    t.ok(metaBefore, "fixture: reset wrote save.json")
    fs.writes = {}
    t.eq(Save.setRun(validRun()), true)
    for i = 1, 5 do Save.setRun(validRun({ time = 60 + i })) end -- autosaves
    t.ok(fs.files["run.json"], "the run is in run.json")
    t.eq(fs.files["save.json"], metaBefore, "save.json untouched")
    for _, name in ipairs(fs.writes) do
      t.eq(name, "run.json", "every autosave write goes to run.json")
    end
  end)
end

function T.the_run_survives_a_reload_from_disk(t)
  Support.withMemoryFs(function()
    Save.reset()
    Save.setRun(validRun({ hp = 33.25, kills = 77 }))
    Save.load() -- what the next app start does
    local run = Save.run()
    t.ok(run, "run read back from run.json")
    t.eq(run.hp, 33.25)
    t.eq(run.kills, 77)
    t.eq(Support.firstDiff(run, validRun({ hp = 33.25, kills = 77 })), nil)
  end)
end

function T.load_rereads_run_json_instead_of_trusting_the_cache(t)
  Support.withMemoryFs(function(fs)
    Save.reset()
    Save.setRun(validRun())
    t.ok(Save.run(), "fixture: run cached")
    fs.files["run.json"] = nil -- deleted behind the game's back
    Save.load()
    t.eq(Save.run(), nil, "a reload sees the file as it is on disk")
  end)
end

function T.a_corrupt_run_file_never_affects_the_meta_save(t)
  Support.withMemoryFs(function(fs)
    fs.files["save.json"] = '{"stardust":123,"totalRuns":4}'
    fs.files["run.json"] = "{not json at all"
    Save.load()
    t.eq(Save.data().stardust, 123, "permanent progress intact")
    t.eq(Save.data().totalRuns, 4)
    t.eq(Save.run(), nil, "and the unreadable run is simply absent")
  end)
end

function T.a_parseable_but_invalid_run_file_is_ignored(t)
  Support.withMemoryFs(function(fs)
    for _, junk in ipairs({ '{"version":1}', "5", "[]", '"run"', "null" }) do
      fs.files["run.json"] = junk
      Save.load()
      t.eq(Save.run(), nil, "ignored: " .. junk)
    end
  end)
end

function T.clearrun_deletes_the_file(t)
  Support.withMemoryFs(function(fs)
    Save.reset()
    Save.setRun(validRun())
    Save.clearRun()
    t.eq(fs.files["run.json"], nil)
    t.eq(Save.run(), nil)
    Save.load()
    t.eq(Save.run(), nil, "still gone after a reload")
  end)
end

function T.clearrun_with_no_run_writes_nothing(t)
  Support.withMemoryFs(function(fs)
    Save.reset()
    fs.writes = {}
    Save.clearRun()
    t.eq(#fs.writes, 0)
  end)
end

function T.reset_removes_the_run_file_too(t)
  Support.withMemoryFs(function(fs)
    Save.setRun(validRun())
    Save.reset()
    t.eq(fs.files["run.json"], nil)
    t.eq(Save.run(), nil)
  end)
end

function T.rawrun_returns_the_stored_run_without_validating_it(t)
  Support.withMemoryFs(function()
    Save.reset()
    t.eq(Save.rawRun(), nil)
    Save.setRun({ version = 1, mode = "standard" })
    t.ok(Save.rawRun(), "raw run is there")
    t.eq(Save.run(), nil, "but it is not a usable run")
  end)
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
