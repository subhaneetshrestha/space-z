-- src/render/particles.lua — pooled cosmetic particles (sparks, explosions, trails).
-- Hard cap keeps the frame budget bounded; bursts silently truncate at the cap.
local Sprites = require("src.render.sprites")

local M = {}

local sin, cos = math.sin, math.cos
local TWO_PI = math.pi * 2

local CAP = 600 -- quality tier adjusts this via M.setCap

-- cosmetic randomness only — gameplay streams stay untouched
local function rnd()
  return love.math.random()
end

-- quality tiers: "high" = 600 live particles, "low" = 220
function M.setCap(n)
  CAP = n
end

local function spawn(world, x, y, vx, vy, life, size, cr, cg, cb, sprite, drag)
  local list = world.particles
  if #list >= CAP then return nil end
  local p = world.pools.particles:acquire()
  p.kind = "particle"
  p.x, p.y = x, y
  p.vx, p.vy = vx, vy
  p.r = 0
  p.sprite = sprite or "dot"
  p.rot = 0
  p.scale = size
  p.t = 0
  p.dead = false
  p.life = life
  p.maxlife = life
  p.size = size
  p.drag = drag or 2.5
  p.cr, p.cg, p.cb, p.ca = cr, cg, cb, 1
  list[#list + 1] = p
  return p
end

function M.update(world, dt)
  local list = world.particles
  for i = 1, #list do
    local p = list[i]
    if not p.dead then
      p.t = p.t + dt
      p.life = p.life - dt
      if p.life <= 0 then
        p.dead = true
      else
        local damp = 1 - p.drag * dt
        if damp < 0 then damp = 0 end
        p.vx = p.vx * damp
        p.vy = p.vy * damp
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        local f = p.life / p.maxlife
        p.ca = f
        p.scale = p.size * (0.4 + 0.6 * f)
      end
    end
  end
end

function M.draw(world, batch)
  local list = world.particles
  for i = 1, #list do
    local p = list[i]
    if not p.dead then
      Sprites.add(batch, p.sprite, p.x, p.y, p.rot, p.scale, p.cr, p.cg, p.cb, p.ca)
    end
  end
end

-- spec: { n=, speed=, life=, size=, color={r,g,b}, spread=angle (default full circle) }
function M.burst(world, x, y, spec)
  local n = spec.n or 10
  local speed = spec.speed or 120
  local life = spec.life or 0.5
  local size = spec.size or 0.8
  local c = spec.color or { 1, 1, 1 }
  local spread = spec.spread or TWO_PI
  local a0 = rnd() * TWO_PI
  for i = 1, n do
    local a = a0 + (i / n) * spread + (rnd() - 0.5) * 0.4
    local sp = speed * (0.4 + rnd() * 0.8)
    spawn(world, x, y, cos(a) * sp, sin(a) * sp,
      life * (0.6 + rnd() * 0.7), size * (0.6 + rnd() * 0.8),
      c[1], c[2], c[3], "dot", 2.5)
  end
end

function M.explosion(world, x, y, size, color)
  local c = color or { 1, 0.6, 0.2 }
  -- core flash
  local flash = spawn(world, x, y, 0, 0, 0.22, size * 1.6, 1, 1, 1, "glow", 0)
  if flash then flash.drag = 0 end
  -- expanding ring: fake it with a fast-fading ring sprite that grows via size curve
  local ring = spawn(world, x, y, 0, 0, 0.3, size * 0.5, c[1], c[2], c[3], "ring", 0)
  if ring then ring.size = size * 1.4 end -- scale curve runs 0.4->1.0 of this
  -- debris sparks
  M.burst(world, x, y, {
    n = 8 + math.floor(size * 8),
    speed = 90 + size * 90,
    life = 0.55,
    size = 0.7 + size * 0.25,
    color = c,
  })
end

function M.trail(world, x, y, color)
  local c = color or { 0.4, 0.9, 1.0 }
  spawn(world, x + (rnd() - 0.5) * 3, y, (rnd() - 0.5) * 12, 55 + rnd() * 25,
    0.30 + rnd() * 0.12, 0.5 + rnd() * 0.3, c[1], c[2], c[3], "glow", 1.2)
end

return M
