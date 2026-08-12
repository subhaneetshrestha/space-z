-- src/ui/input.lua — steering: 1:1 relative drag (touch + mouse) and keyboard.
-- One instance per run; the only thing it writes is world.player.vx/vy.
--
-- CONTRACT with systems/movement.lua, which integrates once per step:
--     player.x = player.x + player.vx * speedMult * dt   (then zone forces, then clamp)
-- To land the hull `s` px from where movement.lua left it we emit
--     vx = s / (speedMult * dt)
-- a per-step *pseudo* velocity, not a physical one: it spikes to a few thousand
-- px/s on a fast swipe and is recomputed from scratch every step. movement.lua is
-- the only reader of player.vx/vy in the codebase.
--
-- The grab reference is re-baselined from the LIVE pointer and the LIVE hull
-- position every step, so slack can never accumulate: walls, the drag ceiling,
-- zone gravity/wind, keyboard overrides and pointer hand-offs all settle in one
-- step and the next pixel of finger travel is still worth its full pixel of ship.
--
-- Pointer coords from the event handlers arrive already converted to virtual
-- 480x854 space by main.lua; coords read from love.touch/love.mouse are converted
-- here with the same Viewport call.
local Util = require("src.core.util")
local Viewport = require("src.core.viewport")

local Input = {}
Input.__index = Input

local VW, VH = Viewport.VW, Viewport.VH
local sqrt = math.sqrt
local clamp = Util.clamp

-- Playfield bounds — MUST match the clamp at the end of movement.lua's player step.
local MIN_X, MAX_X = 20, VW - 20
local MIN_Y, MAX_Y = 80, VH - 30

local BASE_SPEED     = 300    -- stats.speed at which a drag is exactly 1:1
local SENS_MIN       = 0.5    -- defensive bounds on speed / BASE_SPEED
local SENS_MAX       = 2.5
local MAX_DRAG_RATE  = 3000   -- px/s ceiling on hull travel: anti-teleport guard
local JITTER_EPS     = 0.5    -- px: panel noise below this is banked, not applied
local KEY_DECEL      = 2400   -- px/s^2 keyboard-release coast (keyboard path only)
local MIN_SPEED_MULT = 0.05   -- floor on zone playerSpeedMult (division guard)

local JITTER_EPS2 = JITTER_EPS * JITTER_EPS

function Input.new()
  local self = setmetatable({}, Input)
  self.touches = {}    -- id -> { x, y, src, polled }
  self.order = {}      -- live touch ids, oldest first; order[1] steers
  self.steerId = nil   -- pointer owning steering: a touch id, "mouse", or nil
  self.steerSrc = nil  -- "poll"|"event": stream that set the grab (see update)
  self.grabX, self.grabY = 0, 0
  self.mouseDown, self.mouseSeen = false, false
  self.mouseX, self.mouseY = 0, 0
  self.mouseSrc = nil
  self.decelVx, self.decelVy = 0, 0  -- keyboard-only coast state
  return self
end

-- ------------------------------------------------------------ pointer tracking

local function addTouch(self, id, x, y, src)
  local t = self.touches[id]
  if t then
    t.x, t.y, t.src = x, y, src
    if src == "poll" then t.polled = true end
    return
  end
  self.touches[id] = { x = x, y = y, src = src, polled = (src == "poll") }
  self.order[#self.order + 1] = id
end

local function removeTouch(self, id)
  if self.touches[id] == nil then return end
  self.touches[id] = nil
  local order = self.order
  for i = 1, #order do
    if order[i] == id then
      table.remove(order, i)
      return
    end
  end
end

-- Reconcile the tracked set against the OS touch list. Liveness from love.touch
-- is authoritative for ids it has confirmed at least once: pause / level-up sit
-- ON TOP of the game state (core/state.lua forwards input to the top state only)
-- and swallow touchreleased, which would otherwise strand a phantom steering
-- finger for the rest of the run. Ids only ever seen through events (headless
-- tests, or a platform where getTouches misbehaves) are never reaped here, so the
-- module degrades to pure event tracking instead of losing steering entirely.
local seen = {}  -- module scratch, wiped per call: no per-frame garbage
local function syncTouches(self)
  local touch = love and love.touch
  if not touch or not touch.getTouches then return end
  local list = touch.getTouches()
  Util.wipe(seen)
  for i = 1, #list do
    local id = list[i]
    local sx, sy = touch.getPosition(id)
    local x, y = Viewport.toVirtual(sx, sy)
    addTouch(self, id, x, y, "poll")
    seen[id] = true
  end
  local order = self.order
  for i = #order, 1, -1 do
    local id = order[i]
    local t = self.touches[id]
    if t and t.polled and not seen[id] then
      self.touches[id] = nil
      table.remove(order, i)
    end
  end
end

-- Desktop mirror of syncTouches. Only ever CLEARS a press it has observed held,
-- so a swallowed mousereleased cannot leave the cursor dragging, and a button
-- held over from the menu can never start a drag on its own.
local function syncMouse(self)
  local mouse = love and love.mouse
  if not mouse or not self.mouseDown then return end
  if mouse.isDown(1) then
    self.mouseSeen = true
    local mx, my = mouse.getPosition()
    self.mouseX, self.mouseY = Viewport.toVirtual(mx, my)
    self.mouseSrc = "poll"
  elseif self.mouseSeen then
    self.mouseDown, self.mouseSeen = false, false
  end
end

-- The pointer that owns steering: oldest live touch, else the held mouse button.
-- Oldest-wins means a stray second contact (other hand, knuckle, stray tap) can
-- never steal the hull mid-dodge; when the owner lifts, order[1] promotes and the
-- grab re-baselines, so the hand-off cannot move the ship. (Flip to newest-wins
-- by reading order[#order] instead, if playtest ever asks for it.)
local function pointer(self)
  local id = self.order[1]
  if id ~= nil then
    local t = self.touches[id]
    return id, t.x, t.y, t.src
  end
  if self.mouseDown then
    return "mouse", self.mouseX, self.mouseY, self.mouseSrc
  end
  return nil, 0, 0, nil
end

-- ----------------------------------------------------------------- drag solver

local function dragVelocity(player, mods, dx, dy, dt)
  -- 1. clamp the target to the playfield FIRST, so dragging into a wall spends
  --    none of the step budget and the free axis keeps tracking the finger
  local tx = clamp(player.x + dx, MIN_X, MAX_X)
  local ty = clamp(player.y + dy, MIN_Y, MAX_Y)
  local sx, sy = tx - player.x, ty - player.y
  -- 2. then cap. Overshoot is DROPPED, never banked: the ship falls behind an
  --    absurd flick, but the next pixel of finger travel is 1:1 again.
  local maxStep = MAX_DRAG_RATE * dt
  local l2 = sx * sx + sy * sy
  if l2 > maxStep * maxStep then
    local k = maxStep / sqrt(l2)
    sx, sy = sx * k, sy * k
  end
  -- 3. divide the zone multiplier back out so a drag is 1:1 in every zone. Heavy
  --    worlds still bite through gravity, wind and storm pulses, which
  --    movement.lua adds after this step and which we do not compensate for.
  local m = (mods and mods.playerSpeedMult) or 1
  if m < MIN_SPEED_MULT then m = MIN_SPEED_MULT end
  local inv = 1 / (m * dt)
  return sx * inv, sy * inv
end

-- ----------------------------------------------------------------------- update

function Input:update(world, dt)
  local player = world.player
  if not player or dt <= 0 then return end

  syncTouches(self)
  syncMouse(self)

  -- Pointer delta, consumed EVERY step whoever ends up steering, so switching
  -- between keyboard and drag can never bank a jump.
  local id, px, py, src = pointer(self)
  local dx, dy = 0, 0
  if id ~= nil then
    if id ~= self.steerId or src ~= self.steerSrc then
      -- Fresh grab: first press, re-place after a lift, hand-off to a surviving
      -- finger, or the position stream changing. Contributes no motion this step,
      -- which is exactly why the hull never jumps.
      self.steerId, self.steerSrc = id, src
      self.grabX, self.grabY = px, py
    else
      local ddx, ddy = px - self.grabX, py - self.grabY
      if ddx * ddx + ddy * ddy >= JITTER_EPS2 then
        dx, dy = ddx, ddy
        self.grabX, self.grabY = px, py -- consume; sub-eps noise stays banked
      end
    end
  else
    self.steerId, self.steerSrc = nil, nil
  end

  -- priority: keyboard -> drag -> coast to rest
  local speed = (world.stats and world.stats.speed) or BASE_SPEED
  local kx, ky = 0, 0
  local kb = love and love.keyboard
  if kb then
    if kb.isDown("a", "left")  then kx = kx - 1 end
    if kb.isDown("d", "right") then kx = kx + 1 end
    if kb.isDown("w", "up")    then ky = ky - 1 end
    if kb.isDown("s", "down")  then ky = ky + 1 end
  end

  local vx, vy
  if kx ~= 0 or ky ~= 0 then
    local nx, ny = Util.norm(kx, ky)
    vx, vy = nx * speed, ny * speed
    self.decelVx, self.decelVy = vx, vy
  elseif id ~= nil then
    -- Drag sensitivity rides the speed stat: the baseline hull (300) is exactly
    -- 1:1, faster hulls and thruster upgrades cover more ground per finger-pixel.
    -- Tracking stays lag-free at every value; only the ratio changes.
    local sens = clamp(speed / BASE_SPEED, SENS_MIN, SENS_MAX)
    vx, vy = dragVelocity(player, world.zone and world.zone.modifiers,
      dx * sens, dy * sens, dt)
    -- Positional control carries no momentum: lifting the finger stops the hull
    -- dead instead of coasting the last step's pseudo-velocity across the screen.
    self.decelVx, self.decelVy = 0, 0
  else
    self.decelVx = Util.approach(self.decelVx, 0, KEY_DECEL * dt)
    self.decelVy = Util.approach(self.decelVy, 0, KEY_DECEL * dt)
    vx, vy = self.decelVx, self.decelVy
  end

  player.vx, player.vy = vx, vy
end

-- Drop every live pointer. game.lua calls this when the run resumes from an
-- overlay (pause / level-up): the game state never saw those releases and the
-- tracked positions are a whole card-draft stale. On the next step syncTouches
-- re-adopts fingers that are genuinely still down as brand-new grabs, so a player
-- who held their thumb through a draft keeps steering without the hull moving.
function Input:reset()
  Util.wipe(self.touches)
  local order = self.order
  for i = #order, 1, -1 do order[i] = nil end
  self.steerId, self.steerSrc = nil, nil
  self.mouseDown, self.mouseSeen = false, false
  self.decelVx, self.decelVy = 0, 0
end

-- ------------------------------------------------------------------ event feed

function Input:touchpressed(id, x, y)
  addTouch(self, id, x, y, "event")
end

function Input:touchmoved(id, x, y)
  -- unknown id: its touchpressed went to an overlay state — adopt it here
  addTouch(self, id, x, y, "event")
end

function Input:touchreleased(id)
  removeTouch(self, id)
end

function Input:mousepressed(x, y, b)
  if b ~= 1 then return end
  self.mouseDown = true
  self.mouseX, self.mouseY, self.mouseSrc = x, y, "event"
end

function Input:mousemoved(x, y) -- dx,dy ignored: deltas come from grab tracking
  self.mouseX, self.mouseY, self.mouseSrc = x, y, "event"
end

function Input:mousereleased(x, y, b)
  if b == 1 then self.mouseDown, self.mouseSeen = false, false end
end

return Input
