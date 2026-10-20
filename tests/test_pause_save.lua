-- tests/test_pause_save.lua — the pause menu's save behaviour: it saves on open,
-- SAVE & QUIT keeps the run, daily runs are not resumable.
local StateM = require("src.core.state")
local Save = require("src.meta.save")
local Support = require("tests.support")
local H = require("tests.game_harness")

local T = {}
local test = H.guarded(T)

local start, seconds, played = H.start, H.seconds, H.played

test("opening_pause_saves_the_run", function(t)
  played()
  StateM.keypressed("escape")
  t.eq(H.top(), "pause")
  local run = Save.run()
  t.ok(run, "a save exists as soon as the pause menu is up")
  t.eq(run.hp, 37.5)
end)

test("pause_offers_save_and_quit_for_standard_and_blackhole", function(t)
  start({ mode = "standard" })
  StateM.keypressed("escape")
  t.eq(H.Pause.rows[1], "RESUME")
  t.eq(H.Pause.rows[2], "SAVE & QUIT")
  StateM.pop() -- close pause

  start({ mode = "blackhole" })
  StateM.keypressed("escape")
  t.eq(H.Pause.rows[2], "SAVE & QUIT")
end)

test("save_and_quit_keeps_the_run_and_goes_to_the_menu", function(t)
  played()
  StateM.keypressed("escape")
  Save.clearRun() -- prove the quit itself writes, not just the pause entry
  H.Pause.selected = 2
  StateM.keypressed("return")
  t.eq(H.top(), "menu")
  local run = Save.run()
  t.ok(run, "the run survives quitting to the menu")
  t.eq(run.hp, 37.5)
  t.eq(run.level, 6)
end)

-- ------------------------------------------------------ with a fight on screen

-- the countdown, played out through the real state stack
local function throughTheCountdown()
  local n = 0
  while StateM.current() == H.Countdown and n < 600 do H.step(1); n = n + 1 end
end

test("pausing_in_a_boss_fight_saves_the_fight_as_it_stands", function(t)
  local w = H.bossFight(2)
  w.boss.hp = w.boss.maxhp * 0.6
  StateM.keypressed("escape")
  t.eq(H.top(), "pause")
  local run = Save.run()
  t.ok(run, "the fight is a valid save")
  t.eq(run.phase, "boss")
  t.ok(run.boss, "with the boss linked")
  t.eq(run.enemies[run.boss].hp, w.boss.maxhp * 0.6, "at the health it has: no heal")
end)

test("save_and_quit_in_a_boss_fight_then_continue_brings_back_the_same_fight", function(t)
  local w = H.bossFight(5)
  H.stepUntil(function() return w.boss.state == "drift" or w.boss.state == "telegraph" end, 1800)
  w.boss.hp = w.boss.maxhp * 0.35
  local view = Support.worldView(w)
  StateM.keypressed("escape")
  H.Pause.selected = 2
  StateM.keypressed("return")
  t.eq(H.top(), "menu")

  local run = Save.run()
  StateM.switch("game", { resume = run, mode = run.mode, seed = run.seed })
  local w2 = H.Game.world
  t.eq(w2.phase, "boss")
  t.ok(w2.boss and w2.boss.hp == w.boss.maxhp * 0.35, "the boss, hurt as it was")
  t.eq(Support.firstDiff(Support.worldView(w2), view), nil,
    "everything on screen is as it was when the player quit")
end)

test("pause_then_resume_changes_nothing_in_the_world", function(t)
  local w = H.bossFight(3)
  local view = Support.worldView(w)
  StateM.keypressed("escape")          -- pause
  H.step(120)                          -- sitting in the pause menu
  StateM.keypressed("escape")          -- RESUME: through the 3-2-1
  throughTheCountdown()
  t.eq(H.top(), "game")
  t.eq(Support.firstDiff(Support.worldView(w), view), nil,
    "pausing is not a way out of an attack either: nothing moved")
end)

test("save_and_quit_during_the_warp_keeps_the_warp", function(t)
  local w = H.bossFight(1)
  H.killBoss(w)
  H.step(30)
  t.eq(w.phase, "warp", "fixture: the boss died")
  StateM.keypressed("escape")
  H.Pause.selected = 2
  StateM.keypressed("return")
  local run = Save.run()
  t.ok(run, "the warp is a valid save")
  t.eq(run.phase, "warp")
  t.ok(run.warpT > 0 and run.warpT < 2.5, "with the time it has left")
  t.eq(run.bossKills, 1)
end)

test("daily_runs_keep_quit_to_menu_and_leave_no_save", function(t)
  start({ daily = true, mode = "standard" })
  seconds(12)
  StateM.keypressed("escape")
  t.eq(H.Pause.rows[2], "QUIT TO MENU")
  t.eq(Save.run(), nil, "opening pause saves nothing for a daily run")
  H.Pause.selected = 2
  StateM.keypressed("return")
  t.eq(H.top(), "menu")
  t.eq(Save.run(), nil, "and quitting discards it, as before")
end)

test("pause_without_a_game_still_works_for_resume", function(t)
  StateM.switch("menu")
  StateM.push("pause") -- no params: no save callback, default labels
  t.eq(H.Pause.rows[2], "SAVE & QUIT")
end)

return T
