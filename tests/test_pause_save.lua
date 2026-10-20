-- tests/test_pause_save.lua — the pause menu's save behaviour: it saves on open,
-- SAVE & QUIT keeps the run, daily runs are not resumable.
local StateM = require("src.core.state")
local Save = require("src.meta.save")
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
