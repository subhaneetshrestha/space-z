-- tests/test_input.lua — 1:1 relative-drag steering, driven through the REAL
-- Movement.update so the input->movement contract is covered end to end.
-- Note: under `lovec . --test` love.keyboard is live and the keyboard branch
-- preempts dragging, so don't hold WASD while running these.
local Input = require("src.ui.input")
local Movement = require("src.systems.movement")

local T = {}

local STEP = 1 / 60

local function fakeWorld(over)
  local w = {
    time = 0,
    player = { x = 240, y = 600, vx = 0, vy = 0, r = 7, t = 0 },
    stats = { speed = 300 },
    enemies = {}, bullets = {}, ebullets = {}, pickups = {},
    zone = nil,
  }
  for k, v in pairs(over or {}) do w[k] = v end
  return w
end

-- one simulation step: steer, then integrate exactly like states/game.lua does
local function step(input, world)
  input:update(world, STEP)
  Movement.update(world, STEP)
end

-- ------------------------------------------------------------------- grabbing

function T.grab_does_not_move_the_hull(t)
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 100, 400)
  step(i, w)
  t.near(w.player.x, 240, 1e-9, "x unchanged by the grab")
  t.near(w.player.y, 600, 1e-9, "y unchanged by the grab")
end

function T.lift_and_replace_far_away_moves_nothing(t)
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 100, 400)
  step(i, w)
  i:touchmoved(1, 130, 400)
  step(i, w)
  t.near(w.player.x, 270, 1e-9, "dragged 30")
  -- lift, then press again on the far side of the screen
  i:touchreleased(1)
  step(i, w)
  i:touchpressed(2, 400, 800)
  step(i, w)
  t.near(w.player.x, 270, 1e-9, "re-place does not teleport the hull")
  t.near(w.player.y, 600, 1e-9, "re-place does not teleport the hull")
end

-- ------------------------------------------------------------------ 1:1 drag

function T.drag_is_one_to_one_over_many_steps(t)
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 100, 400)
  step(i, w)
  local fx, fy = 100, 400
  for _ = 1, 8 do
    fx, fy = fx + 12, fy - 7
    i:touchmoved(1, fx, fy)
    step(i, w)
  end
  t.near(w.player.x, 240 + 8 * 12, 1e-6, "x tracked the finger exactly")
  t.near(w.player.y, 600 - 8 * 7, 1e-6, "y tracked the finger exactly")
end

function T.drag_is_one_to_one_under_zone_speed_mult(t)
  -- movement.lua scales vx by playerSpeedMult; input divides it back out so a
  -- drag stays 1:1 in heavy zones (their weight lands via gravity/wind instead)
  local w = fakeWorld({ zone = { modifiers = { playerSpeedMult = 0.5 } } })
  local i = Input.new()
  i:touchpressed(1, 100, 400)
  step(i, w)
  i:touchmoved(1, 140, 400)
  step(i, w)
  t.near(w.player.x, 280, 1e-6, "0.5x zone still tracks 1:1")
end

function T.sensitivity_scales_with_the_speed_stat(t)
  local fast = fakeWorld({ stats = { speed = 600 } })  -- sens 2.0
  local i = Input.new()
  i:touchpressed(1, 100, 400)
  step(i, fast)
  i:touchmoved(1, 120, 400)
  step(i, fast)
  t.near(fast.player.x, 240 + 40, 1e-6, "600 speed => 2x per finger px")

  local slow = fakeWorld({ stats = { speed = 150 } })  -- sens 0.5
  local j = Input.new()
  j:touchpressed(1, 100, 400)
  step(j, slow)
  j:touchmoved(1, 120, 400)
  step(j, slow)
  t.near(slow.player.x, 240 + 10, 1e-6, "150 speed => 0.5x per finger px")
end

-- --------------------------------------------------------------------- walls

function T.wall_overdrag_banks_no_slack(t)
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 300, 400)
  step(i, w)
  -- walk the finger well past the left wall in sub-cap increments
  local fx = 300
  for _ = 1, 10 do
    fx = fx - 40
    i:touchmoved(1, fx, 400)
    step(i, w)
  end
  t.near(w.player.x, 20, 1e-9, "pinned to the left wall")
  -- one small move back must answer immediately, not retrace the overshoot
  i:touchmoved(1, fx + 15, 400)
  step(i, w)
  t.near(w.player.x, 35, 1e-6, "no slack to retrace")
end

function T.wall_does_not_eat_the_free_axis(t)
  -- clamp happens before the rate cap, so a diagonal drag into a wall keeps
  -- tracking exactly on the axis that is still free
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 300, 400)
  step(i, w)
  local fx = 300
  for _ = 1, 10 do
    fx = fx - 40
    i:touchmoved(1, fx, 400)
    step(i, w)
  end
  t.near(w.player.x, 20, 1e-9, "pinned")
  i:touchmoved(1, fx - 40, 425)
  step(i, w)
  t.near(w.player.x, 20, 1e-9, "still pinned")
  t.near(w.player.y, 625, 1e-6, "vertical tracking unaffected by the wall")
end

-- --------------------------------------------------------------- multi-touch

function T.oldest_touch_steers_and_a_stray_finger_is_ignored(t)
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 100, 400)
  step(i, w)
  i:touchpressed(2, 300, 700) -- stray second contact
  step(i, w)
  t.near(w.player.x, 240, 1e-9, "stray finger does not steal steering")
  i:touchmoved(2, 340, 700)
  step(i, w)
  t.near(w.player.x, 240, 1e-9, "stray finger's motion is ignored")
  i:touchmoved(1, 125, 400)
  step(i, w)
  t.near(w.player.x, 265, 1e-6, "owner still steers")
end

function T.promotion_on_release_does_not_move_the_hull(t)
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 100, 400)
  step(i, w)
  i:touchpressed(2, 300, 700)
  step(i, w)
  i:touchreleased(1)
  step(i, w)
  t.near(w.player.x, 240, 1e-9, "hand-off is free")
  t.near(w.player.y, 600, 1e-9, "hand-off is free")
  i:touchmoved(2, 320, 700)
  step(i, w)
  t.near(w.player.x, 260, 1e-6, "survivor steers after promotion")
end

function T.reset_drops_the_grab_without_moving_the_hull(t)
  -- what game.lua:resume does when a level-up card pops with the thumb still down
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 100, 400)
  step(i, w)
  i:touchmoved(1, 200, 400)  -- finger travelled while the overlay was up
  i:reset()
  step(i, w)
  t.near(w.player.x, 240, 1e-9, "stale delta is discarded, not applied")
  t.eq(w.player.vx, 0, "and no velocity survives")
end

-- ---------------------------------------------------------------- no coasting

function T.release_after_a_fast_drag_stops_dead(t)
  -- positional control carries no momentum: coasting the last step's pseudo-
  -- velocity would fling the ship across the screen on every finger lift
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 100, 400)
  step(i, w)
  i:touchmoved(1, 145, 400) -- 45 px in one step ~= 2700 px/s
  step(i, w)
  t.near(w.player.x, 285, 1e-6, "fast drag tracked")
  i:touchreleased(1)
  local before = w.player.x
  step(i, w)
  t.eq(w.player.vx, 0, "no residual velocity")
  t.near(w.player.x, before, 1e-9, "hull stops dead")
end

function T.jitter_below_the_gate_is_banked_not_lost(t)
  local w, i = fakeWorld(), Input.new()
  i:touchpressed(1, 100, 400)
  step(i, w)
  -- four 0.3 px nudges: each below the gate, but the total must still land
  local fx = 100
  for _ = 1, 4 do
    fx = fx + 0.3
    i:touchmoved(1, fx, 400)
    step(i, w)
  end
  t.near(w.player.x, 241.2, 1e-6, "sub-eps travel accumulates rather than drifting")
end

return T
