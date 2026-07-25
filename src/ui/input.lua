-- src/ui/input.lua — one-thumb / keyboard / mouse steering (instance).
-- Sets world.player.vx/vy only; movement.lua integrates. All pointer coords
-- arrive already converted to virtual space by main.lua.
local Util = require("src.core.util")

local Input = {}
Input.__index = Input

local sqrt = math.sqrt
local min = math.min

local FLOAT_GAIN = 3.0        -- floating: velocity px/s per px of finger offset
local FLOAT_SPEED_MULT = 1.15
local ABS_GAIN = 10           -- absolute/mouse ease gain; d*10/60 per step => no overshoot at 60 Hz
local ABS_SPEED_MULT = 1.6
local ABS_Y_OFFSET = 90       -- ship rides above the finger/cursor
local DECEL = 2400            -- px/s^2 toward rest when no input
local DRIFT_EPS = 6           -- px: finger counts as "still" near the anchor
local DRIFT_DELAY = 0.25      -- s of stillness before anchor re-centers
local DRIFT_SPEED = 60        -- px/s anchor ease toward finger (anti-drift)

function Input.new(settings)
  local self = setmetatable({}, Input)
  self.steerMode = (settings and settings.steerMode) or "floating"
  self.touchId = nil          -- active primary touch (only it steers)
  self.touchX, self.touchY = 0, 0
  self.anchorX, self.anchorY = 0, 0
  self.stillT = 0
  self.mouseDown = false
  self.mouseX, self.mouseY = 0, 0
  self.lastVx, self.lastVy = 0, 0  -- for velocity-preserving re-anchor
  return self
end

local function easeVel(px, py, tx, ty, maxSpeed)
  local dx, dy = tx - px, ty - py
  local d = sqrt(dx * dx + dy * dy)
  if d < 1e-4 then return 0, 0 end
  local s = d * ABS_GAIN
  if s > maxSpeed then s = maxSpeed end
  return dx / d * s, dy / d * s
end

function Input:update(world, dt)
  local player = world.player
  if not player then return end
  local speed = (world.stats and world.stats.speed) or 300
  local vx, vy

  -- priority: keyboard -> touch -> mouse -> decelerate
  local kb = love.keyboard
  local kx, ky = 0, 0
  if kb then
    if kb.isDown("a", "left") then kx = kx - 1 end
    if kb.isDown("d", "right") then kx = kx + 1 end
    if kb.isDown("w", "up") then ky = ky - 1 end
    if kb.isDown("s", "down") then ky = ky + 1 end
  end

  if kx ~= 0 or ky ~= 0 then
    local nx, ny = Util.norm(kx, ky)
    vx, vy = nx * speed, ny * speed
  elseif self.touchId ~= nil then
    if self.steerMode == "absolute" then
      vx, vy = easeVel(player.x, player.y,
        self.touchX, self.touchY - ABS_Y_OFFSET, speed * ABS_SPEED_MULT)
    else
      local dx = self.touchX - self.anchorX
      local dy = self.touchY - self.anchorY
      local d = sqrt(dx * dx + dy * dy)
      if d < DRIFT_EPS then
        -- anti-drift: after a beat of stillness, walk the anchor onto the finger
        self.stillT = self.stillT + dt
        if self.stillT > DRIFT_DELAY and d > 0 then
          local step = min(DRIFT_SPEED * dt, d)
          self.anchorX = self.anchorX + dx / d * step
          self.anchorY = self.anchorY + dy / d * step
          dx = self.touchX - self.anchorX
          dy = self.touchY - self.anchorY
          d = sqrt(dx * dx + dy * dy)
        end
      else
        self.stillT = 0
      end
      vx, vy = dx * FLOAT_GAIN, dy * FLOAT_GAIN
      local maxs = speed * FLOAT_SPEED_MULT
      local l = d * FLOAT_GAIN
      if l > maxs then
        local k = maxs / l
        vx, vy = vx * k, vy * k
      end
    end
  elseif self.mouseDown then
    vx, vy = easeVel(player.x, player.y,
      self.mouseX, self.mouseY - ABS_Y_OFFSET, speed * ABS_SPEED_MULT)
  else
    vx = Util.approach(player.vx or 0, 0, DECEL * dt)
    vy = Util.approach(player.vy or 0, 0, DECEL * dt)
  end

  player.vx, player.vy = vx, vy
  self.lastVx, self.lastVy = vx, vy
end

function Input:keypressed(key)
  -- steering polls love.keyboard.isDown; nothing event-driven here
end

function Input:touchpressed(id, x, y)
  if self.touchId ~= nil then return end -- only the primary touch steers
  self.touchId = id
  self.touchX, self.touchY = x, y
  self.stillT = 0
  -- re-anchor without zeroing velocity: place the anchor so the current
  -- velocity maps back exactly onto (finger - anchor) * FLOAT_GAIN
  self.anchorX = x - self.lastVx / FLOAT_GAIN
  self.anchorY = y - self.lastVy / FLOAT_GAIN
end

function Input:touchmoved(id, x, y)
  if id ~= self.touchId then return end
  self.touchX, self.touchY = x, y
end

function Input:touchreleased(id, x, y)
  if id == self.touchId then self.touchId = nil end
end

function Input:mousepressed(x, y, b)
  if b ~= 1 then return end
  self.mouseDown = true
  self.mouseX, self.mouseY = x, y
end

function Input:mousemoved(x, y, dx, dy)
  self.mouseX, self.mouseY = x, y
end

function Input:mousereleased(x, y, b)
  if b == 1 then self.mouseDown = false end
end

return Input
