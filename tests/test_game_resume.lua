-- tests/test_game_resume.lua — states/game.lua's save integration, through the REAL
-- game state (see tests/game_harness.lua): the resume path, Game.saveRun gating,
-- autosave, and clearing the save on death / win.
local StateM = require("src.core.state")
local Save = require("src.meta.save")
local RunSave = require("src.meta.runsave")
local Zones = require("src.content.zones")
local json = require("lib.json")
local Support = require("tests.support")
local H = require("tests.game_harness")

local T = {}
local test = H.guarded(T)

local STEP = H.STEP
local start, step, seconds, played = H.start, H.step, H.seconds, H.played

-- ------------------------------------------------------------------- resume

test("a_new_run_has_no_countdown", function(t)
  start()
  t.eq(StateM.current(), H.Game)
end)

test("resume_restores_the_run_and_shows_the_countdown", function(t)
  local old = played("aegis")
  local run = json.decode(json.encode(RunSave.snapshot(old)))

  Save.data().settings.ship = "pathfinder" -- hangar changed since: the run's ship wins
  StateM.switch("game", { resume = run, mode = run.mode, seed = run.seed })

  t.eq(StateM.current(), H.Countdown, "3-2-1 is up")
  local w = H.Game.world
  t.ok(w ~= old, "a new world was built")
  t.eq(w.player.shipDef.id, "aegis")
  t.eq(Support.firstDiff(RunSave.snapshot(w), RunSave.snapshot(old)), nil,
    "restored world matches the saved one field for field")
end)

test("resumed_world_is_frozen_until_the_countdown_ends", function(t)
  local run = RunSave.snapshot(played())
  StateM.switch("game", { resume = run, seed = run.seed })
  local w = H.Game.world
  local time0 = w.time
  seconds(2.5)
  t.eq(StateM.current(), H.Countdown, "still counting")
  t.eq(w.time, time0, "no simulation during 3-2-1")
  seconds(0.6)
  t.eq(StateM.current(), H.Game, "control returned")
  step(10)
  t.ok(w.time > time0, "the run advances again")
end)

test("a_boss_fight_save_resumes_with_the_boss_coming_back_at_full_health", function(t)
  local w = start({ seed = 31 })
  w.zoneTime = w.zone.duration - 0.05
  local n = 0
  while w.phase ~= "boss" and n < 600 do step(); n = n + 1 end
  t.eq(w.phase, "boss", "fixture: the boss was triggered")
  w.boss.hp = 1 -- nearly dead when the player quits
  t.eq(H.Game.saveRun(), true)

  local run = Save.run()
  StateM.switch("game", { resume = run, seed = run.seed })
  local w2 = H.Game.world
  t.eq(w2.phase, "waves", "boss is not part of the save")
  t.eq(w2.boss, nil)
  seconds(3.2) -- countdown
  step(5)
  t.eq(w2.phase, "boss", "the spawner brings it back in")
  t.eq(w2.boss.hp, w2.boss.maxhp, "at full health")
end)

test("resuming_does_not_count_as_a_new_run", function(t)
  local run = RunSave.snapshot(played())
  local runsBefore = Save.data().totalRuns
  StateM.switch("game", { resume = run, seed = run.seed })
  t.eq(Save.data().totalRuns, runsBefore)
end)

test("an_invalid_resume_falls_back_to_a_plain_new_run", function(t)
  local run = RunSave.snapshot(played())
  run.weapons[1].id = "bfg"
  StateM.switch("game", { resume = run, seed = 5 })
  t.eq(StateM.current(), H.Game, "no countdown for a run that was not restored")
  t.eq(H.Game.world.level, 1)
end)

-- ------------------------------------------------------------------ saveRun

test("saverun_writes_the_active_run", function(t)
  local w = played()
  t.eq(H.Game.saveRun(), true)
  local run = Save.run()
  t.ok(run, "a valid run is stored")
  t.eq(run.hp, 37.5)
  t.eq(run.level, 6)
  t.eq(run.zoneTime, w.zoneTime)
end)

test("saverun_counts_an_open_level_up_draft", function(t)
  played()
  H.Game.world.pendingLevelUps = 0
  StateM.push("levelup") -- the draft is on screen; it was already taken off the count
  t.eq(H.Game.saveRun(), true)
  t.eq(Save.run().pendingLevelUps, 1)
end)

test("saverun_does_nothing_once_the_game_state_is_left", function(t)
  played()
  StateM.switch("menu") -- Game.world is still around, but the run is over
  Save.clearRun()
  t.eq(H.Game.saveRun(), false)
  t.eq(Save.run(), nil, "a stale world must never be written")
end)

test("saverun_skips_daily_runs", function(t)
  start({ daily = true, mode = "standard" })
  seconds(12)
  t.eq(H.Game.saveRun(), false)
  t.eq(Save.run(), nil)
end)

test("saverun_skips_autopilot_runs_even_through_autosave", function(t)
  start({ autopilot = true })
  seconds(25)
  t.eq(H.Game.saveRun(), false)
  t.eq(Save.run(), nil, "smoke runs write no run")
end)

-- ----------------------------------------------------------------- autosave

test("autosave_writes_about_every_ten_seconds", function(t)
  start()
  seconds(9.5)
  t.eq(Save.run(), nil, "not yet")
  seconds(1.0)
  local first = Save.run()
  t.ok(first, "written at ~10 s")
  seconds(10.0)
  t.ok(Save.run().time > first.time + 5, "and refreshed ~10 s later")
end)

-- ----------------------------------------------------------------- clearing

test("player_death_clears_the_save", function(t)
  local w = played()
  H.Game.saveRun()
  t.ok(Save.run(), "precondition: a save exists")
  w.player.dead = true
  w.events:emit("player_died")
  t.eq(Save.run(), nil)
  t.eq(H.Game.saveRun(), false, "and a dead run can not be saved again")
  t.eq(Save.run(), nil)
end)

test("a_win_clears_the_save_and_counts_the_run_once", function(t)
  local w = played()
  H.Game.saveRun()
  t.ok(Save.run(), "precondition: a save exists")
  local runsBefore = Save.data().totalRuns
  w.phase, w.zoneIndex, w.zone = "warp", #Zones, Zones[#Zones]
  w.warpT = STEP / 2
  step(2)
  t.eq(Save.run(), nil, "winning clears the save")
  t.eq(Save.data().totalRuns, runsBefore + 1, "endRun ran exactly once")
  t.ok(H.gameoverParams() and H.gameoverParams().won, "game-over screen got a win")
end)

return T
