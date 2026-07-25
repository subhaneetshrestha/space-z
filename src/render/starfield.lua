-- src/render/starfield.lua — 3-layer parallax starfield + procedural zone backdrop.
-- Cosmetic only: uses its own tiny LCG at init so gameplay streams stay untouched.
local Viewport = require("src.core.viewport")
local Sprites = require("src.render.sprites")

local M = {}

local sin = math.sin

local VW, VH = Viewport.VW, Viewport.VH

local LAYERS = {
  { n = 35, speed = 1.00, scale = 1.0, alpha = 1.00 },
  { n = 60, speed = 0.50, scale = 0.7, alpha = 0.55 },
  { n = 90, speed = 0.25, scale = 0.45, alpha = 0.30 },
}

local Starfield = {}
Starfield.__index = Starfield

-- quality "low" thins the field for weak GPUs
function M.new(seed, quality)
  local self = setmetatable({}, Starfield)
  local density = quality == "low" and 0.55 or 1
  local s = (seed or 1) % 2147483647
  if s <= 0 then s = 1 end
  local function rnd()
    s = (s * 48271) % 2147483647
    return (s - 1) / 2147483646
  end
  self.layers = {}
  for li = 1, #LAYERS do
    local spec = LAYERS[li]
    local stars = {}
    for i = 1, math.floor(spec.n * density) do
      stars[i] = {
        x = rnd() * VW,
        y = rnd() * VH,
        tw = rnd() * 6.28,          -- twinkle phase
        twSpd = 1.5 + rnd() * 2.5,  -- twinkle speed
        sc = 0.7 + rnd() * 0.6,     -- per-star size jitter
      }
    end
    self.layers[li] = { spec = spec, stars = stars }
  end
  self.t = 0
  return self
end

function Starfield:update(dt, scrollSpeed)
  self.t = self.t + dt
  for li = 1, #self.layers do
    local layer = self.layers[li]
    local vy = scrollSpeed * layer.spec.speed
    local stars = layer.stars
    for i = 1, #stars do
      local star = stars[i]
      star.y = star.y + vy * dt
      if star.y > VH + 4 then
        star.y = star.y - (VH + 8)
      end
    end
  end
end

function Starfield:draw(batch)
  local t = self.t
  for li = 1, #self.layers do
    local layer = self.layers[li]
    local spec = layer.spec
    local stars = layer.stars
    for i = 1, #stars do
      local star = stars[i]
      local twinkle = 0.75 + 0.25 * sin(t * star.twSpd + star.tw)
      Sprites.add(batch, "star", star.x, star.y, 0, spec.scale * star.sc,
        1, 1, 1, spec.alpha * twinkle)
    end
  end
end

-- Planet limb low on screen that sinks away as the run climbs (gone by
-- zone-relative distance 12000). body = {r,g,b} triples dark->light.
local function drawLimb(zoneDef, distance, body, bandFn)
  local sink = (distance or 0) / 12000
  if sink >= 1 then return end

  local lg = love.graphics
  local tint = zoneDef.tint or { 0.3, 0.7, 1.0 }
  local R = 700
  local cx = VW * 0.5
  -- ~230px of limb visible at zone start, fully sunk by zone-distance 12000
  local cy = VH + R - 230 + sink * 420

  lg.setColor(body[1][1], body[1][2], body[1][3], 1)
  lg.circle("fill", cx, cy, R, 96)
  lg.setColor(body[2][1], body[2][2], body[2][3], 1)
  lg.circle("fill", cx, cy + 40, R * 0.94, 96)
  lg.setColor(body[3][1], body[3][2], body[3][3], 1)
  lg.circle("fill", cx, cy + 90, R * 0.86, 96)

  if bandFn then bandFn(lg, cx, cy, R) end

  -- atmosphere rim in the zone tint
  local r, g, b = tint[1], tint[2], tint[3]
  lg.setLineWidth(6)
  lg.setColor(r, g, b, 0.10)
  lg.circle("line", cx, cy, R + 4, 96)
  lg.setLineWidth(3)
  lg.setColor(r, g, b, 0.22)
  lg.circle("line", cx, cy, R + 1, 96)
  lg.setLineWidth(1.5)
  lg.setColor(r + (1 - r) * 0.5, g + (1 - g) * 0.5, b + (1 - b) * 0.5, 0.5)
  lg.circle("line", cx, cy, R, 96)
  lg.setColor(1, 1, 1, 1)
end

local BODIES = {
  earth = { { 0.02, 0.05, 0.10 }, { 0.03, 0.08, 0.16 }, { 0.04, 0.11, 0.20 } },
  moon = { { 0.07, 0.07, 0.09 }, { 0.10, 0.10, 0.12 }, { 0.13, 0.13, 0.15 } },
  mars = { { 0.10, 0.03, 0.02 }, { 0.15, 0.05, 0.03 }, { 0.19, 0.07, 0.04 } },
  jupiter = { { 0.12, 0.07, 0.03 }, { 0.16, 0.10, 0.05 }, { 0.20, 0.13, 0.07 } },
  saturn = { { 0.10, 0.09, 0.05 }, { 0.14, 0.12, 0.07 }, { 0.17, 0.15, 0.09 } },
}

-- Zone backdrop, drawn directly (no batch). `distance` is ZONE-RELATIVE.
function Starfield:drawBackdrop(zoneDef, distance)
  if not zoneDef then return end
  local kind = zoneDef.backdrop
  local lg = love.graphics

  if kind == "earth" or kind == "moon" then
    drawLimb(zoneDef, distance, BODIES[kind], kind == "moon" and function(g, cx, cy, R)
      -- craters on the limb
      g.setColor(0.05, 0.05, 0.07, 1)
      g.circle("fill", cx - 140, cy - R + 90, 34, 32)
      g.circle("fill", cx + 90, cy - R + 150, 22, 32)
      g.circle("fill", cx + 190, cy - R + 70, 15, 32)
    end or nil)

  elseif kind == "mars" then
    drawLimb(zoneDef, distance, BODIES.mars)
    -- dust haze bands drifting with time
    local t = self.t
    lg.setColor(0.9, 0.45, 0.25, 0.045)
    for i = 0, 2 do
      local y = (VH * 0.25 * i + t * 14) % (VH + 120) - 60
      lg.rectangle("fill", 0, y, VW, 46 + i * 18)
    end
    lg.setColor(1, 1, 1, 1)

  elseif kind == "belt" then
    -- distant slow rock silhouettes, wrapping vertically
    local t = self.t
    lg.setColor(0.16, 0.12, 0.08, 0.8)
    for i = 1, 7 do
      local seed = i * 137.7
      local x = (seed * 3.1) % VW
      local y = ((seed * 7.7) + t * (8 + i)) % (VH + 160) - 80
      lg.circle("fill", x, y, 14 + (i % 4) * 9, 8)
    end
    lg.setColor(1, 1, 1, 1)

  elseif kind == "jupiter" then
    drawLimb(zoneDef, distance, BODIES.jupiter, function(g, cx, cy, R)
      -- horizontal cloud bands + the great red spot
      g.setColor(0.28, 0.17, 0.08, 0.55)
      g.rectangle("fill", cx - R, cy - R + 60, R * 2, 26)
      g.rectangle("fill", cx - R, cy - R + 130, R * 2, 34)
      g.setColor(0.34, 0.12, 0.06, 0.7)
      g.ellipse("fill", cx + 120, cy - R + 105, 46, 22, 32)
    end)

  elseif kind == "saturn" then
    drawLimb(zoneDef, distance, BODIES.saturn)
    -- ring plane slicing across the sky
    local sink = (distance or 0) / 12000
    if sink < 1 then
      local y0 = VH - 300 + sink * 500
      lg.setLineWidth(10)
      lg.setColor(0.7, 0.85, 1.0, 0.08)
      lg.ellipse("line", VW * 0.5, y0, 480, 70, 48)
      lg.setLineWidth(4)
      lg.setColor(0.7, 0.85, 1.0, 0.16)
      lg.ellipse("line", VW * 0.5, y0, 430, 60, 48)
      lg.setLineWidth(1.5)
      lg.setColor(0.85, 0.95, 1.0, 0.30)
      lg.ellipse("line", VW * 0.5, y0, 390, 52, 48)
      lg.setLineWidth(1)
      lg.setColor(1, 1, 1, 1)
    end

  elseif kind == "void" then
    -- slow-breathing nebula blobs in the hive's colors
    local t = self.t
    for i = 1, 4 do
      local seed = i * 71.3
      local x = (seed * 5.9) % VW
      local y = ((seed * 11.3) + t * 6) % (VH + 300) - 150
      local pulse = 0.7 + 0.3 * sin(t * 0.4 + i * 2)
      lg.setColor(0.30, 0.10, 0.45, 0.05 * pulse)
      lg.circle("fill", x, y, 170, 32)
      lg.setColor(0.5, 0.15, 0.7, 0.04 * pulse)
      lg.circle("fill", x, y, 110, 32)
    end
    lg.setColor(1, 1, 1, 1)
  end
end

return M
