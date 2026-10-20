-- tests/test_countdown.lua — the 3-2-1 overlay, driven through the REAL state
-- stack so "the world is frozen while it is up" is proven, not assumed.
local StateM = require("src.core.state")
local Countdown = require("src.states.countdown")
local Pause = require("src.states.pause")

local T = {}

local STEP = 1 / 60

-- Minimal stand-in for states/game.lua: counts what the stack does to it.
local function fakeGame()
  local g = { updates = 0, resumes = 0 }
  function g:update() self.updates = self.updates + 1 end
  function g:resume() self.resumes = self.resumes + 1 end
  return g
end

-- Fresh stack per test: registered once, emptied by popping everything.
local function setup()
  StateM.register("countdown", Countdown)
  StateM.register("pause", Pause)
  while StateM.current() do StateM.pop() end
  local game = fakeGame()
  StateM.register("cd_test_game", game)
  StateM.switch("cd_test_game")
  return game
end

local function teardown()
  while StateM.current() do StateM.pop() end
end

-- steps until `done()` or `limit` steps; returns steps taken
local function runUntil(done, limit)
  local n = 0
  while not done() and n < limit do
    StateM.update(STEP)
    n = n + 1
  end
  return n
end

-- ------------------------------------------------------------------ digits

function T.digit_counts_three_two_one_then_nothing(t)
  t.eq(Countdown.digit(0), 3)
  t.eq(Countdown.digit(0.999), 3)
  t.eq(Countdown.digit(1.0), 2)
  t.eq(Countdown.digit(1.999), 2)
  t.eq(Countdown.digit(2.0), 1)
  t.eq(Countdown.digit(2.999), 1)
  t.eq(Countdown.digit(3.0), nil, "done at 3 s")
end

function T.countdown_is_translucent_so_the_game_shows_through(t)
  t.eq(Countdown.translucent, true)
end

-- ------------------------------------------------------------------ timing

function T.ends_after_three_seconds_within_one_step(t)
  local game = setup()
  StateM.push("countdown")
  local steps = runUntil(function() return StateM.current() == game end, 1000)
  t.ok(math.abs(steps * STEP - 3.0) <= STEP + 1e-9,
    "popped after " .. steps * STEP .. " s, expected 3.0")
  t.eq(StateM.current(), game, "control is back on the game")
  teardown()
end

function T.shows_three_then_two_then_one_in_order(t)
  setup()
  StateM.push("countdown")
  local seen = {}
  while StateM.current() == Countdown and #seen < 20 do
    StateM.update(STEP)
    local d = Countdown.digit(Countdown.t)
    if d and seen[#seen] ~= d then seen[#seen + 1] = d end
  end
  t.eq(table.concat(seen, ","), "3,2,1")
  teardown()
end

function T.pops_exactly_once(t)
  local game = setup()
  StateM.push("countdown") -- push does not call resume: only a pop does
  runUntil(function() return StateM.current() == game end, 1000)
  t.eq(game.resumes, 1, "game:resume (input reset) runs once, on the pop")
  -- more updates now go to the game, never back to the countdown
  StateM.update(STEP)
  t.eq(StateM.current(), game)
  t.eq(game.resumes, 1)
  teardown()
end

function T.entering_again_restarts_the_count(t)
  local game = setup()
  StateM.push("countdown")
  runUntil(function() return StateM.current() == game end, 1000)
  StateM.push("countdown")
  t.eq(Countdown.digit(Countdown.t), 3, "a second countdown starts from 3")
  teardown()
end

-- ------------------------------------------------------------------ frozen

function T.the_game_is_never_updated_while_it_is_up(t)
  local game = setup()
  StateM.push("countdown")
  runUntil(function() return StateM.current() == game end, 1000)
  t.eq(game.updates, 0, "no sim step may reach the game during 3-2-1")
  StateM.update(STEP)
  t.eq(game.updates, 1, "and it updates again once the countdown is gone")
  teardown()
end

function T.input_during_the_countdown_does_nothing(t)
  local game = setup()
  game.touchpressed = function() error("steering input reached the game") end
  game.keypressed = function() error("key reached the game") end
  StateM.push("countdown")
  StateM.touchpressed(1, 100, 100)
  StateM.mousepressed(100, 100, 1)
  StateM.keypressed("space")
  StateM.keypressed("escape")
  t.eq(StateM.current(), Countdown, "still counting down")
  teardown()
end

-- ------------------------------------------------------------ pause resume

function T.pause_resume_row_starts_the_countdown(t)
  local game = setup()
  StateM.push("pause")
  Pause.selected = 1
  StateM.keypressed("return")
  t.eq(StateM.current(), Countdown, "RESUME goes through the countdown")
  t.eq(game.updates, 0)
  runUntil(function() return StateM.current() == game end, 1000)
  t.eq(StateM.current(), game, "then straight back to the game, not the pause menu")
  teardown()
end

function T.pause_escape_starts_the_countdown(t)
  local game = setup()
  StateM.push("pause")
  StateM.keypressed("escape")
  t.eq(StateM.current(), Countdown)
  runUntil(function() return StateM.current() == game end, 1000)
  t.eq(StateM.current(), game)
  teardown()
end

return T
