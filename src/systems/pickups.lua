-- src/systems/pickups.lua — XP energy cells: drop/merge, magnet, collect, leveling curve.
local M = {}

local floor, sqrt, min = math.floor, math.sqrt, math.min

local MERGE_R2 = 24 * 24
local COLLECT_R2 = 18 * 18
local MAGNET_MAX_SPEED = 700
local MAGNET_ACCEL = 2600
local DRIFT_VY = 30

local function tierSprite(value)
  if value >= 25 then return "pickup_xp3"
  elseif value >= 5 then return "pickup_xp2" end
  return "pickup_xp1"
end

M.tierSprite = tierSprite -- run saves rebuild a gem's sprite from its value

function M.xpForLevel(level)
  return floor(8 + 6 * (level - 1) ^ 1.35)
end

function M.dropXp(world, x, y, value)
  if value <= 0 then return end
  -- clutter control: merge into a nearby non-magnetized gem instead of spawning
  local pickups = world.pickups
  for i = 1, #pickups do
    local p = pickups[i]
    if not p.dead and not p.magnet and p.ptype == "xp" then
      local dx, dy = p.x - x, p.y - y
      if dx * dx + dy * dy <= MERGE_R2 then
        p.value = p.value + value
        p.sprite = tierSprite(p.value)
        return p
      end
    end
  end
  local p = world.pools.pickups:acquire()
  p.kind = "pickup"
  p.ptype = "xp"
  p.x, p.y = x, y
  p.vx, p.vy = 0, DRIFT_VY
  p.r = 8
  p.sprite = tierSprite(value)
  p.rot = 0
  p.scale = 1
  p.t = 0
  p.dead = false
  p.value = value
  p.magnet = false
  world.pickups[#world.pickups + 1] = p
  return p
end

local function addXp(world, amount)
  world.xp = world.xp + amount
  while world.xp >= world.xpNext do
    world.xp = world.xp - world.xpNext
    world.level = world.level + 1
    world.pendingLevelUps = world.pendingLevelUps + 1
    world.xpNext = M.xpForLevel(world.level)
    world.events:emit("level_up", world.level)
  end
end

function M.update(world, dt)
  local player = world.player
  if not player then return end
  local px, py = player.x, player.y
  local magnetR2 = world.stats.magnetRadius * world.stats.magnetRadius

  local pickups = world.pickups
  for i = 1, #pickups do
    local p = pickups[i]
    if not p.dead then
      local dx, dy = px - p.x, py - p.y
      local d2 = dx * dx + dy * dy

      if not p.magnet and d2 <= magnetR2 then
        p.magnet = true
      end

      if p.magnet then
        local d = sqrt(d2)
        if d > 1e-4 then
          local nx, ny = dx / d, dy / d
          p.vx = p.vx + nx * MAGNET_ACCEL * dt
          p.vy = p.vy + ny * MAGNET_ACCEL * dt
          local sp = sqrt(p.vx * p.vx + p.vy * p.vy)
          if sp > MAGNET_MAX_SPEED then
            local k = MAGNET_MAX_SPEED / sp
            p.vx, p.vy = p.vx * k, p.vy * k
          end
        end
      end

      if d2 <= COLLECT_R2 and not player.dead then
        p.dead = true
        if p.ptype == "xp" then
          addXp(world, p.value * world.stats.xpMult)
        end
        world.events:emit("pickup_collected", p)
      end
    end
  end
end

return M
