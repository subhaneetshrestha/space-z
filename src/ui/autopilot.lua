-- src/ui/autopilot.lua — deterministic smoke-test bot. Weaves, chases XP,
-- dodges the nearest threat. Sets player.vx/vy only (like Input).
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")

local M = {}

local sin, sqrt = math.sin, math.sqrt

local VW, VH = Viewport.VW, Viewport.VH

local DODGE_R2 = 120 * 120
local PICKUP_R2 = 260 * 260

function M.update(world, dt)
  local player = world.player
  if not player or player.dead then return end
  local speed = world.stats.speed

  -- baseline: weave across the safe band
  local tx = VW * 0.5 + sin(world.time * 0.7) * (VW * 0.30)
  local ty = VH * 0.72 + sin(world.time * 0.43) * (VH * 0.10)

  -- bias toward the nearest pickup in range
  local pickups = world.pickups
  local bestP, bestPD2 = nil, PICKUP_R2
  for i = 1, #pickups do
    local p = pickups[i]
    if not p.dead then
      local d2 = Util.dist2(player.x, player.y, p.x, p.y)
      if d2 < bestPD2 then bestP, bestPD2 = p, d2 end
    end
  end
  if bestP then
    tx = tx * 0.35 + bestP.x * 0.65
    ty = ty * 0.55 + bestP.y * 0.45
  end

  -- boss fight: park under the boss so forward fire connects
  local boss = world.boss
  if boss and not boss.dead and not boss.entering then
    tx = boss.x
    ty = VH * 0.70
  end

  -- clamp the goal into the survivable band
  tx = Util.clamp(tx, 40, VW - 40)
  ty = Util.clamp(ty, VH * 0.55, VH * 0.85)

  local vx = (tx - player.x) * 4
  local vy = (ty - player.y) * 4

  -- hard dodge: steer directly away from the nearest close threat
  local bestT, bestTD2 = nil, DODGE_R2
  local enemies = world.enemies
  for i = 1, #enemies do
    local e = enemies[i]
    if not e.dead then
      local d2 = Util.dist2(player.x, player.y, e.x, e.y)
      if d2 < bestTD2 then bestT, bestTD2 = e, d2 end
    end
  end
  local ebullets = world.ebullets
  for i = 1, #ebullets do
    local b = ebullets[i]
    if not b.dead then
      local d2 = Util.dist2(player.x, player.y, b.x, b.y)
      if d2 < bestTD2 then bestT, bestTD2 = b, d2 end
    end
  end
  if bestT then
    local dx, dy = player.x - bestT.x, player.y - bestT.y
    local d = sqrt(bestTD2)
    if d > 1e-4 then
      local urgency = 1 - d / 120
      vx = vx + (dx / d) * speed * 2.2 * urgency
      vy = vy + (dy / d) * speed * 1.6 * urgency
    end
  end

  -- clamp to ship speed
  local sp = sqrt(vx * vx + vy * vy)
  if sp > speed then
    local k = speed / sp
    vx, vy = vx * k, vy * k
  end
  player.vx, player.vy = vx, vy
end

return M
