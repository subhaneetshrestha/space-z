-- tests/test_app_lifecycle.lua — main.lua's love.focus / love.quit hooks. The real
-- main.lua is loaded into a sandbox so it is exercised without redefining the live
-- `love` callbacks; `require` inside the hooks is pointed at the test's Game (the
-- one with stubbed rendering, see tests/game_harness.lua).
local StateM = require("src.core.state")
local Save = require("src.meta.save")
local H = require("tests.game_harness")

local T = {}
local test = H.guarded(T)

local played = H.played

-- fn(hooks) runs with `hooks` = the love.* table main.lua filled in
local function withMainHooks(fn, game)
  local env = setmetatable({ love = {} }, { __index = _G })
  local chunk = assert(loadfile("main.lua"))
  setfenv(chunk, env)
  chunk()
  package.loaded["src.states.game"] = game or H.Game
  local ok, err = pcall(fn, env.love)
  package.loaded["src.states.game"] = nil
  assert(ok, err)
end

test("losing_focus_saves_the_run", function(t)
  played()
  Save.clearRun()
  withMainHooks(function(hooks) hooks.focus(false) end)
  local run = Save.run()
  t.ok(run, "backgrounding the app wrote the run")
  t.eq(run.hp, 37.5)
end)

test("gaining_focus_does_not_save", function(t)
  played()
  Save.clearRun()
  withMainHooks(function(hooks) hooks.focus(true) end)
  t.eq(Save.run(), nil)
end)

test("quitting_saves_the_run_and_lets_the_app_close", function(t)
  played()
  Save.clearRun()
  local result
  withMainHooks(function(hooks) result = hooks.quit() end)
  t.eq(result, false, "love.quit must not veto the close")
  t.ok(Save.run(), "closing the window wrote the run")
end)

test("quitting_during_a_levelup_draft_keeps_the_draft", function(t)
  played()
  H.Game.world.pendingLevelUps = 0
  StateM.push("levelup")
  Save.clearRun()
  withMainHooks(function(hooks) hooks.quit() end)
  t.eq(Save.run().pendingLevelUps, 1)
end)

test("losing_focus_in_a_boss_fight_saves_the_fight", function(t)
  local w = H.bossFight(4)
  w.boss.hp = w.boss.maxhp * 0.5
  Save.clearRun()
  withMainHooks(function(hooks) hooks.focus(false) end)
  local run = Save.run()
  t.ok(run, "backgrounding the app mid-boss wrote the run")
  t.eq(run.phase, "boss")
  t.ok(run.boss, "boss linked")
  t.eq(run.enemies[run.boss].hp, w.boss.maxhp * 0.5)
end)

test("quitting_during_the_warp_saves_it_even_after_the_last_boss", function(t)
  local w = H.bossFight(7)
  H.killBoss(w)
  H.step(30)
  t.eq(w.phase, "warp", "fixture: the last boss died")
  Save.clearRun()
  withMainHooks(function(hooks) hooks.quit() end)
  local run = Save.run()
  t.ok(run, "closing the window in the last warp wrote the run (it used to be refused)")
  t.eq(run.phase, "warp")
  t.eq(run.zoneIndex, 7)
end)

test("lifecycle_hooks_save_nothing_when_no_run_is_active", function(t)
  played()
  StateM.switch("menu") -- the run is over; the old world is still referenced
  Save.clearRun()
  withMainHooks(function(hooks)
    hooks.focus(false)
    hooks.quit()
  end)
  t.eq(Save.run(), nil)
end)

test("a_failing_save_never_blocks_backgrounding_or_quitting", function(t)
  local broken = { saveRun = function() error("disk full") end }
  local okFocus, okQuit, result
  withMainHooks(function(hooks)
    okFocus = pcall(hooks.focus, false)
    okQuit, result = pcall(hooks.quit)
  end, broken)
  t.eq(okFocus, true, "focus hook swallowed the error")
  t.eq(okQuit, true, "quit hook swallowed the error")
  t.eq(result, false)
end)

return T
