-- tests/test_game_resume.lua — states/game.lua's save integration, run through the
-- REAL game state and state stack: resume path, autosave, Game.saveRun gating,
-- and clearing the save on death / win. Only rendering and audio modules are
-- stubbed (they need a window / sound device); every system and save module is real.
local StateM = require("src.core.state")
local Save = require("src.meta.save")
local RunSave = require("src.meta.runsave")
local Leveling = require("src.systems.leveling")
local Weapons = require("src.content.weapons")
local Upgrades = require("src.content.upgrades")
local Zones = require("src.content.zones")
local json = require("lib.json")
local Support = require("tests.support")

local T = {}

local STEP = 1 / 60

-- ------------------------------------------------------------------ harness

local function noop() end

-- table whose every missing key is a no-op function
local function catchAll()
  return setmetatable({}, { __index = function() return noop end })
end

local STUBBED = {
  "src.render.sprites", "src.render.starfield", "src.render.particles",
  "src.render.hud", "src.audio.audio", "src.audio.music",
}

-- Load a private copy of states/game.lua against stubbed render/audio modules,
-- then put the real modules back so other test files are unaffected.
local function loadGame()
  local saved = {}
  for _, name in ipairs(STUBBED) do saved[name] = package.loaded[name] end
  for _, name in ipairs(STUBBED) do package.loaded[name] = catchAll() end
  package.loaded["src.render.starfield"] = { new = function() return catchAll() end }
  package.loaded["src.render.sprites"] = { batch = function() return catchAll() end, add = noop }
  package.loaded["src.states.game"] = nil
  local Game = require("src.states.game")
  for _, name in ipairs(STUBBED) do package.loaded[name] = saved[name] end
  package.loaded["src.states.game"] = nil
  return Game
end

local Game, Countdown, Pause
local gameoverParams
local hadLove

local function setup()
  hadLove = love ~= nil
  if not hadLove then
    love = { math = { random = math.random } } -- event handlers jitter pitch with it
  end
  Game = Game or loadGame()
  Countdown = require("src.states.countdown")
  Pause = require("src.states.pause")
  while StateM.current() do StateM.pop() end
  StateM.register("game", Game)
  StateM.register("countdown", Countdown)
  StateM.register("pause", Pause)
  StateM.register("levelup", { translucent = true })
  StateM.register("gameover", { enter = function(_, p) gameoverParams = p end })
  StateM.register("menu", {})
  gameoverParams = nil
  Save.reset()
end

local function teardown()
  while StateM.current() do StateM.pop() end
  if not hadLove then love = nil end
end

-- Start a new run; the ship can't be killed by wandering enemies mid-test.
local function start(params)
  params = params or {}
  params.seed = params.seed or 4242
  StateM.switch("game", params)
  Game.world.player.invulnT = 1e9
  return Game.world
end

local function step(n)
  for _ = 1, n or 1 do StateM.update(STEP) end
end

local function seconds(s)
  step(math.floor(s / STEP + 0.5))
end

-- A world that has been played a while: bigger build, damaged, spawner running.
local function played(ship)
  Save.data().settings.ship = ship or "aegis"
  local w = start({ seed = 77 })
  Leveling.addWeapon(w, Weapons.missiles)
  w.weapons[2].level = 3
  Leveling.addPassive(w, Upgrades.hull_plating)
  w.passives[1].level = 2
  Leveling.recomputeStats(w)
  seconds(12)
  w.level, w.xp, w.xpNext, w.kills, w.noDamage = 6, 14.5, 40, 40, false
  w.player.hp = 37.5
  return w
end

-- ------------------------------------------------------------------- resume

function T.a_new_run_has_no_countdown(t)
  setup()
  start()
  t.eq(StateM.current(), Game)
  teardown()
end

function T.resume_restores_the_run_and_shows_the_countdown(t)
  setup()
  local old = played("aegis")
  local run = json.decode(json.encode(RunSave.snapshot(old)))

  Save.data().settings.ship = "pathfinder" -- hangar changed since: the run's ship wins
  StateM.switch("game", { resume = run, mode = run.mode, seed = run.seed })

  t.eq(StateM.current(), Countdown, "3-2-1 is up")
  local w = Game.world
  t.ok(w ~= old, "a new world was built")
  t.eq(w.player.shipDef.id, "aegis")
  t.eq(Support.firstDiff(RunSave.snapshot(w), RunSave.snapshot(old)), nil,
    "restored world matches the saved one field for field")
  teardown()
end

function T.resumed_world_is_frozen_until_the_countdown_ends(t)
  setup()
  local run = RunSave.snapshot(played())
  StateM.switch("game", { resume = run, seed = run.seed })
  local w = Game.world
  local time0 = w.time
  seconds(2.5)
  t.eq(StateM.current(), Countdown, "still counting")
  t.eq(w.time, time0, "no simulation during 3-2-1")
  seconds(0.6)
  t.eq(StateM.current(), Game, "control returned")
  step(10)
  t.ok(w.time > time0, "the run advances again")
  teardown()
end

function T.a_boss_fight_save_resumes_with_the_boss_coming_back_at_full_health(t)
  setup()
  local w = start({ seed = 31 })
  w.zoneTime = w.zone.duration - 0.05
  local n = 0
  while w.phase ~= "boss" and n < 600 do step(); n = n + 1 end
  t.eq(w.phase, "boss", "fixture: the boss was triggered")
  w.boss.hp = 1 -- nearly dead when the player quits
  t.eq(Game.saveRun(), true)

  local run = Save.run()
  StateM.switch("game", { resume = run, seed = run.seed })
  local w2 = Game.world
  t.eq(w2.phase, "waves", "boss is not part of the save")
  t.eq(w2.boss, nil)
  seconds(3.2) -- countdown
  step(5)
  t.eq(w2.phase, "boss", "the spawner brings it back in")
  t.eq(w2.boss.hp, w2.boss.maxhp, "at full health")
  teardown()
end

function T.resuming_does_not_count_as_a_new_run(t)
  setup()
  local run = RunSave.snapshot(played())
  local runsBefore = Save.data().totalRuns
  StateM.switch("game", { resume = run, seed = run.seed })
  t.eq(Save.data().totalRuns, runsBefore)
  teardown()
end

function T.an_invalid_resume_falls_back_to_a_plain_new_run(t)
  setup()
  local run = RunSave.snapshot(played())
  run.weapons[1].id = "bfg"
  StateM.switch("game", { resume = run, seed = 5 })
  t.eq(StateM.current(), Game, "no countdown for a run that was not restored")
  t.eq(Game.world.level, 1)
  teardown()
end

-- ------------------------------------------------------------------ saveRun

function T.saverun_writes_the_active_run(t)
  setup()
  local w = played()
  t.eq(Game.saveRun(), true)
  local run = Save.run()
  t.ok(run, "a valid run is stored")
  t.eq(run.hp, 37.5)
  t.eq(run.level, 6)
  t.eq(run.zoneTime, w.zoneTime)
  teardown()
end

function T.saverun_counts_an_open_level_up_draft(t)
  setup()
  played()
  Game.world.pendingLevelUps = 0
  StateM.push("levelup") -- the draft is on screen; it was already taken off the count
  t.eq(Game.saveRun(), true)
  t.eq(Save.run().pendingLevelUps, 1)
  teardown()
end

function T.saverun_does_nothing_once_the_game_state_is_left(t)
  setup()
  played()
  StateM.switch("menu") -- Game.world is still around, but the run is over
  Save.clearRun()
  t.eq(Game.saveRun(), false)
  t.eq(Save.run(), nil, "a stale world must never be written")
  teardown()
end

function T.saverun_skips_daily_runs(t)
  setup()
  start({ daily = true, mode = "standard" })
  seconds(12)
  t.eq(Game.saveRun(), false)
  t.eq(Save.run(), nil)
  teardown()
end

function T.saverun_skips_autopilot_runs_even_through_autosave(t)
  setup()
  start({ autopilot = true })
  seconds(25)
  t.eq(Game.saveRun(), false)
  t.eq(Save.run(), nil, "smoke runs write no run")
  teardown()
end

-- -------------------------------------------------------------------- pause

local function pauseTop()
  local top = StateM.current()
  return top and top.__name
end

function T.opening_pause_saves_the_run(t)
  setup()
  played()
  StateM.keypressed("escape")
  t.eq(pauseTop(), "pause")
  local run = Save.run()
  t.ok(run, "a save exists as soon as the pause menu is up")
  t.eq(run.hp, 37.5)
  teardown()
end

function T.pause_offers_save_and_quit_for_standard_and_blackhole(t)
  setup()
  start({ mode = "standard" })
  StateM.keypressed("escape")
  t.eq(Pause.rows[1], "RESUME")
  t.eq(Pause.rows[2], "SAVE & QUIT")
  StateM.pop() -- close pause

  start({ mode = "blackhole" })
  StateM.keypressed("escape")
  t.eq(Pause.rows[2], "SAVE & QUIT")
  teardown()
end

function T.save_and_quit_keeps_the_run_and_goes_to_the_menu(t)
  setup()
  played()
  StateM.keypressed("escape")
  Save.clearRun() -- prove the quit itself writes, not just the pause entry
  Pause.selected = 2
  StateM.keypressed("return")
  t.eq(pauseTop(), "menu")
  local run = Save.run()
  t.ok(run, "the run survives quitting to the menu")
  t.eq(run.hp, 37.5)
  t.eq(run.level, 6)
  teardown()
end

function T.daily_runs_keep_quit_to_menu_and_leave_no_save(t)
  setup()
  start({ daily = true, mode = "standard" })
  seconds(12)
  StateM.keypressed("escape")
  t.eq(Pause.rows[2], "QUIT TO MENU")
  t.eq(Save.run(), nil, "opening pause saves nothing for a daily run")
  Pause.selected = 2
  StateM.keypressed("return")
  t.eq(pauseTop(), "menu")
  t.eq(Save.run(), nil, "and quitting discards it, as before")
  teardown()
end

function T.pause_without_a_game_still_works_for_resume(t)
  setup()
  StateM.switch("menu")
  StateM.push("pause") -- no params: no save callback, default labels
  t.eq(Pause.rows[2], "SAVE & QUIT")
  teardown()
end

-- ---------------------------------------------------- app lifecycle (main.lua)

-- main.lua's love.focus / love.quit, loaded into a sandbox so the real file is
-- exercised without redefining the live `love` callbacks. `require` inside the
-- hooks is pointed at the test's Game (the one with stubbed rendering).
local function withMainHooks(fn)
  local env = setmetatable({ love = {} }, { __index = _G })
  local chunk = assert(loadfile("main.lua"))
  setfenv(chunk, env)
  chunk()
  package.loaded["src.states.game"] = Game
  local ok, err = pcall(fn, env.love)
  package.loaded["src.states.game"] = nil
  assert(ok, err)
end

function T.losing_focus_saves_the_run(t)
  setup()
  played()
  Save.clearRun()
  withMainHooks(function(hooks)
    hooks.focus(false)
  end)
  local run = Save.run()
  t.ok(run, "backgrounding the app wrote the run")
  t.eq(run.hp, 37.5)
  teardown()
end

function T.gaining_focus_does_not_save(t)
  setup()
  played()
  Save.clearRun()
  withMainHooks(function(hooks)
    hooks.focus(true)
  end)
  t.eq(Save.run(), nil)
  teardown()
end

function T.quitting_saves_the_run_and_lets_the_app_close(t)
  setup()
  played()
  Save.clearRun()
  local result
  withMainHooks(function(hooks)
    result = hooks.quit()
  end)
  t.eq(result, false, "love.quit must not veto the close")
  t.ok(Save.run(), "closing the window wrote the run")
  teardown()
end

function T.quitting_during_a_levelup_draft_keeps_the_draft(t)
  setup()
  played()
  Game.world.pendingLevelUps = 0
  StateM.push("levelup")
  Save.clearRun()
  withMainHooks(function(hooks)
    hooks.quit()
  end)
  t.eq(Save.run().pendingLevelUps, 1)
  teardown()
end

function T.lifecycle_hooks_save_nothing_when_no_run_is_active(t)
  setup()
  played()
  StateM.switch("menu") -- the run is over; the old world is still referenced
  Save.clearRun()
  withMainHooks(function(hooks)
    hooks.focus(false)
    hooks.quit()
  end)
  t.eq(Save.run(), nil)
  teardown()
end

function T.a_failing_save_never_blocks_backgrounding_or_quitting(t)
  setup()
  local env = setmetatable({ love = {} }, { __index = _G })
  local chunk = assert(loadfile("main.lua"))
  setfenv(chunk, env)
  chunk()
  package.loaded["src.states.game"] = { saveRun = function() error("disk full") end }
  local okFocus = pcall(env.love.focus, false)
  local okQuit, result = pcall(env.love.quit)
  package.loaded["src.states.game"] = nil
  t.eq(okFocus, true, "focus hook swallowed the error")
  t.eq(okQuit, true, "quit hook swallowed the error")
  t.eq(result, false)
  teardown()
end

-- ----------------------------------------------------------------- autosave

function T.autosave_writes_about_every_ten_seconds(t)
  setup()
  start()
  seconds(9.5)
  t.eq(Save.run(), nil, "not yet")
  seconds(1.0)
  local first = Save.run()
  t.ok(first, "written at ~10 s")
  seconds(10.0)
  t.ok(Save.run().time > first.time + 5, "and refreshed ~10 s later")
  teardown()
end

-- ----------------------------------------------------------------- clearing

function T.player_death_clears_the_save(t)
  setup()
  local w = played()
  Game.saveRun()
  t.ok(Save.run(), "precondition: a save exists")
  w.player.dead = true
  w.events:emit("player_died")
  t.eq(Save.run(), nil)
  t.eq(Game.saveRun(), false, "and a dead run can not be saved again")
  t.eq(Save.run(), nil)
  teardown()
end

function T.a_win_clears_the_save_and_counts_the_run_once(t)
  setup()
  local w = played()
  Game.saveRun()
  t.ok(Save.run(), "precondition: a save exists")
  local runsBefore = Save.data().totalRuns
  w.phase, w.zoneIndex, w.zone = "warp", #Zones, Zones[#Zones]
  w.warpT = STEP / 2
  step(2)
  t.eq(Save.run(), nil, "winning clears the save")
  t.eq(Save.data().totalRuns, runsBefore + 1, "endRun ran exactly once")
  t.ok(gameoverParams and gameoverParams.won, "game-over screen got a win")
  teardown()
end

return T
