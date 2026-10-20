-- src/states/countdown.lua — translucent 3-2-1 overlay shown before control
-- returns to a frozen run (after pause RESUME or a saved-run CONTINUE).
-- core/state.lua only updates the top state, so while this is up the world below
-- is frozen and receives no input; it has no input handlers of its own.
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")
local Audio = require("src.audio.audio")

local VW, VH = Viewport.VW, Viewport.VH

local M = { translucent = true }

local STEPS = 3 -- digits shown, one second each: 3-2-1 lasts 3 s

-- 3 for the first second, then 2, then 1; nil once the count is over.
function M.digit(t)
  local n = STEPS - math.floor(t)
  if n < 1 or n > STEPS then return nil end
  return n
end

function M:enter()
  self.t = 0
  self.lastDigit = nil
end

function M:update(dt)
  self.t = self.t + dt
  local d = M.digit(self.t)
  if d and d ~= self.lastDigit then
    self.lastDigit = d
    Audio.play("tick", { pitch = d == 1 and 1.6 or 1.0 })
  end
  if not d then
    StateM.pop() -- game:resume() drops stale steering pointers on the way back
  end
end

function M:draw()
  local d = M.digit(self.t)
  if not d then return end
  local lg = love.graphics

  lg.setColor(0, 0, 0, 0.35) -- light dim: the HUD and hull stay readable
  lg.rectangle("fill", 0, 0, VW, VH)

  -- each digit pops in large and settles, then fades out over its last 30%
  local frac = self.t - math.floor(self.t)
  local pop = math.min(frac * 5, 1)
  local scale = 1 + 0.35 * (1 - pop) * (1 - pop)
  local alpha = frac > 0.7 and (1 - frac) / 0.3 or 1

  local cx, cy = VW * 0.5, VH * 0.42
  lg.push()
  lg.translate(cx, cy)
  lg.scale(scale, scale)
  lg.setFont(Util.font(96))
  lg.setColor(0.3, 1, 1, 0.25 * alpha)
  lg.printf(tostring(d), -VW * 0.5, -48 + 3, VW, "center")
  lg.setColor(0.9, 1, 1, 0.95 * alpha)
  lg.printf(tostring(d), -VW * 0.5, -48, VW, "center")
  lg.pop()

  lg.setFont(Util.font(14))
  lg.setColor(0.5, 0.8, 0.9, 0.8)
  lg.printf("GET READY", 0, cy + 70, VW, "center")
  lg.setColor(1, 1, 1, 1)
end

return M
