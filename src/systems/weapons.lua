-- Weapon firing timers, bullet/drone spawning, homing steering, drone orbits.
local Util = require("src.core.util")
local Damage = require("src.systems.damage")

local M = {}

local sin, cos, sqrt, rad = math.sin, math.cos, math.sqrt, math.rad
local atan2 = math.atan2
local pi = math.pi
local TWO_PI = 2 * pi

local NOSE_OFFSET = 16       -- fire origin above player center (ship visual ~34px)
local BULLET_R = 5
local MISSILE_R = 6
local DRONE_R = 8
local HOMING_TURN = 3.5      -- rad/s
local DRONE_HIT_CD = 0.5
local ARC_RETRY = 0.2        -- retry delay when no target in range
local CHAIN_RANGE2 = 120 * 120
local ARC_LIFE = 0.15

-- Nearest live, targetable enemy to (x, y); optional squared max distance and
-- exclusion set (map enemy -> true).
local function nearestEnemy(enemies, x, y, maxD2, exclude)
  local best, bestD2 = nil, maxD2 or math.huge
  for i = 1, #enemies do
    local e = enemies[i]
    if not e.dead and not e.entering and not (exclude and exclude[e]) then
      local dx, dy = e.x - x, e.y - y
      local d2 = dx * dx + dy * dy
      if d2 < bestD2 then
        best, bestD2 = e, d2
      end
    end
  end
  return best
end

-- ang is clockwise from straight up; pooled tables come back empty, so every
-- field read downstream is set here.
local function spawnBullet(world, def, lv, x, y, ang, r)
  local b = world.pools.bullets:acquire()
  b.kind = "bullet"
  b.x, b.y = x, y
  b.vx = sin(ang) * lv.speed
  b.vy = -cos(ang) * lv.speed
  b.r = r
  b.sprite = def.sprite
  b.rot = ang
  b.scale = 1
  b.t = 0
  b.dead = false
  b.damage = lv.damage
  b.pierce = lv.pierce or 0
  b.life = lv.life or 1.6
  b.weaponId = def.id
  b.slowT = lv.slowT       -- cryo: chill on hit
  b.slowMult = lv.slowMult
  b.aoe = lv.aoe           -- nuclear: blast radius on contact
  world.bullets[#world.bullets + 1] = b
  return b
end

-- hit every live enemy in the vertical column above the ship (laser/railgun)
local function hitColumn(world, px, py, halfW, damage)
  local enemies = world.enemies
  local any = false
  for i = 1, #enemies do
    local e = enemies[i]
    if not e.dead and not e.entering and e.y < py then
      local dx = e.x - px
      if dx < 0 then dx = -dx end
      if dx <= halfW + e.r then
        Damage.direct(world, e, damage, true)
        any = true
      end
    end
  end
  return any
end

local function fireForward(world, w, def, lv)
  local player = world.player
  local px, py = player.x, player.y - NOSE_OFFSET
  local n = lv.count + world.stats.projectileBonus
  if n <= 1 then
    spawnBullet(world, def, lv, px, py, 0, BULLET_R)
    return
  end
  local spread = rad(lv.spreadDeg or 0)
  local x0 = px - (n - 1) * 5 -- 10px spacing, centered
  for i = 0, n - 1 do
    local ang = spread * (i / (n - 1) - 0.5)
    spawnBullet(world, def, lv, x0 + i * 10, py, ang, BULLET_R)
  end
end

local function fireSpread(world, w, def, lv)
  local player = world.player
  local px, py = player.x, player.y - NOSE_OFFSET
  local n = lv.count + world.stats.projectileBonus
  if n <= 1 then
    spawnBullet(world, def, lv, px, py, 0, BULLET_R)
    return
  end
  local spread = rad(lv.spreadDeg or 0)
  for i = 0, n - 1 do
    local ang = spread * (i / (n - 1) - 0.5)
    spawnBullet(world, def, lv, px, py, ang, BULLET_R)
  end
end

local function fireHoming(world, w, def, lv)
  local player = world.player
  local px, py = player.x, player.y - NOSE_OFFSET
  local target = nearestEnemy(world.enemies, px, py)
  local n = lv.count
  for i = 1, n do
    local ang
    if n == 1 then
      -- alternate launch side for feel
      local side = w.side or 1
      w.side = -side
      ang = 0.35 * side
    else
      ang = 0.9 * ((i - 1) / (n - 1) - 0.5)
    end
    local b = spawnBullet(world, def, lv, px, py, ang, MISSILE_R)
    b.homing = HOMING_TURN
    b.target = target
  end
end

-- Returns true if it zapped something (else caller sets the short retry).
local function fireArc(world, w, def, lv)
  local player = world.player
  local enemies = world.enemies
  local first = nearestEnemy(enemies, player.x, player.y, lv.range * lv.range)
  if not first then return false end
  local hit = w.hit
  if hit then Util.wipe(hit) else hit = {}; w.hit = hit end
  local arcs = world.arcs
  Damage.direct(world, first, lv.damage, true)
  arcs[#arcs + 1] = {
    x1 = player.x, y1 = player.y - NOSE_OFFSET,
    x2 = first.x, y2 = first.y, t = 0, life = ARC_LIFE,
  }
  hit[first] = true
  local last = first
  for _ = 1, lv.chains or 0 do
    local nxt = nearestEnemy(enemies, last.x, last.y, CHAIN_RANGE2, hit)
    if not nxt then break end
    Damage.direct(world, nxt, lv.damage, true)
    arcs[#arcs + 1] = {
      x1 = last.x, y1 = last.y, x2 = nxt.x, y2 = nxt.y, t = 0, life = ARC_LIFE,
    }
    hit[nxt] = true
    last = nxt
  end
  return true
end

-- continuous cutting beam: damage ticks + a per-frame visual segment
local function updateBeam(world, w, def, lv, dt)
  local player = world.player
  if player.dead or world.phase == "over" then return end
  w.tickT = (w.tickT or 0) - dt
  if w.tickT <= 0 then
    w.tickT = w.tickT + lv.tick / world.stats.fireRateMult
    hitColumn(world, player.x, player.y, lv.width * 0.5, lv.damage)
  end
  local beams = world.beams
  beams[#beams + 1] = {
    x = player.x, y2 = player.y - 14, width = lv.width,
    t = 0, life = 0.05, kind = "laser",
  }
end

-- burning halo: periodic damage to everything inside the radius
local function updateAura(world, w, def, lv, dt)
  local player = world.player
  if player.dead or world.phase == "over" then return end
  w.tickT = (w.tickT or 0) - dt
  if w.tickT <= 0 then
    w.tickT = w.tickT + lv.tick
    local enemies = world.enemies
    local px, py = player.x, player.y
    for i = 1, #enemies do
      local e = enemies[i]
      if not e.dead and not e.entering then
        local dx, dy = e.x - px, e.y - py
        local rr = lv.radius + e.r
        if dx * dx + dy * dy <= rr * rr then
          Damage.direct(world, e, lv.damage, true)
        end
      end
    end
  end
  if lv.radius > (world.auraR or 0) then world.auraR = lv.radius end
end

-- graviton shockwave: damage + slow everything in the radius (bosses resist slow)
local function firePulse(world, w, def, lv)
  local player = world.player
  local enemies = world.enemies
  local px, py = player.x, player.y
  for i = 1, #enemies do
    local e = enemies[i]
    if not e.dead and not e.entering then
      local dx, dy = e.x - px, e.y - py
      local rr = lv.radius + e.r
      if dx * dx + dy * dy <= rr * rr then
        Damage.direct(world, e, lv.damage, true)
        if not e.isBoss then
          if not e.slowT or e.slowT < lv.slowT then e.slowT = lv.slowT end
          e.slowMult = lv.slowMult
        end
      end
    end
  end
  local pulses = world.pulses
  pulses[#pulses + 1] = { x = px, y = py, r = lv.radius, t = 0, life = 0.45 }
end

local function fireRail(world, w, def, lv)
  local player = world.player
  hitColumn(world, player.x, player.y, lv.width * 0.5, lv.damage)
  local beams = world.beams
  beams[#beams + 1] = {
    x = player.x, y2 = player.y - 14, width = lv.width,
    t = 0, life = 0.16, kind = "rail",
  }
end

local function updateOrbital(world, w, def, lv, dt)
  local drones = world.drones
  local pool = world.pools.drones
  local player = world.player
  local desired = lv.count
  local n = #drones
  if n ~= desired then
    while n > desired do
      pool:release(drones[n])
      drones[n] = nil
      n = n - 1
    end
    while n < desired do
      local d = pool:acquire()
      d.kind = "drone"
      d.x, d.y = player.x, player.y
      d.vx, d.vy = 0, 0
      d.r = DRONE_R
      d.sprite = "drone"
      d.rot = 0
      d.scale = 1
      d.t = 0
      d.dead = false
      d.angle = 0
      d.hitCd = {}
      d.hitCdN = 0
      n = n + 1
      drones[n] = d
    end
    for i = 1, n do -- always re-space evenly on count change
      drones[i].angle = (i - 1) * TWO_PI / n
    end
  end
  local enemies = world.enemies
  local now = world.time
  for i = 1, n do
    local d = drones[i]
    d.damage = lv.damage
    d.orbitR = lv.orbitR
    d.angVel = lv.angVel
    local a = d.angle + lv.angVel * dt
    if a > TWO_PI then a = a - TWO_PI end
    d.angle = a
    d.x = player.x + cos(a) * lv.orbitR
    d.y = player.y + sin(a) * lv.orbitR
    d.rot = a + pi * 0.5
    d.t = d.t + dt
    local hitCd = d.hitCd
    for j = 1, #enemies do
      local e = enemies[j]
      if not e.dead and not e.entering then
        local dx, dy = e.x - d.x, e.y - d.y
        local rr = e.r + d.r
        if dx * dx + dy * dy <= rr * rr then
          local cd = hitCd[e]
          if not cd or cd <= now then
            Damage.direct(world, e, d.damage, true)
            if not cd then d.hitCdN = d.hitCdN + 1 end
            hitCd[e] = now + DRONE_HIT_CD
          end
        end
      end
    end
    -- keep the per-enemy cooldown map small: drop expired keys once it grows
    if d.hitCdN > 32 then
      local live = 0
      for k, expiry in pairs(hitCd) do
        if expiry <= now then hitCd[k] = nil else live = live + 1 end
      end
      d.hitCdN = live
    end
  end
end

function M.update(world, dt)
  local weapons = world.weapons
  local stats = world.stats
  local player = world.player
  local canFire = not (player.dead or world.phase == "over")

  for i = 1, #weapons do
    local w = weapons[i]
    local def = w.def
    local lv = def.levels[w.level] or def.levels[#def.levels]
    local behavior = def.behavior
    if behavior == "orbital" then
      updateOrbital(world, w, def, lv, dt)
    elseif behavior == "beam" then
      updateBeam(world, w, def, lv, dt)
    elseif behavior == "aura" then
      updateAura(world, w, def, lv, dt)
    else
      w.cooldown = w.cooldown - dt
      if w.cooldown <= 0 then
        if canFire then
          if behavior == "forward" then
            fireForward(world, w, def, lv)
            w.cooldown = lv.cooldown / stats.fireRateMult
            world.events:emit("weapon_fired", def)
          elseif behavior == "spread" then
            fireSpread(world, w, def, lv)
            w.cooldown = lv.cooldown / stats.fireRateMult
            world.events:emit("weapon_fired", def)
          elseif behavior == "homing" then
            fireHoming(world, w, def, lv)
            w.cooldown = lv.cooldown / stats.fireRateMult
            world.events:emit("weapon_fired", def)
          elseif behavior == "arc" then
            if fireArc(world, w, def, lv) then
              w.cooldown = lv.cooldown / stats.fireRateMult
              world.events:emit("weapon_fired", def)
            else
              w.cooldown = ARC_RETRY
            end
          elseif behavior == "pulse" then
            firePulse(world, w, def, lv)
            w.cooldown = lv.cooldown / stats.fireRateMult
            world.events:emit("weapon_fired", def)
          elseif behavior == "rail" then
            fireRail(world, w, def, lv)
            w.cooldown = lv.cooldown / stats.fireRateMult
            world.events:emit("weapon_fired", def)
          end
        else
          w.cooldown = 0 -- hold ready while firing is suppressed
        end
      end
    end
  end

  -- homing steering (movement.lua integrates positions; we only turn velocity)
  local bullets = world.bullets
  local enemies = world.enemies
  for i = 1, #bullets do
    local b = bullets[i]
    local turn = b.homing
    if turn and not b.dead then
      local tgt = b.target
      -- a released pool table is wiped (kind == nil): treat stale refs as dead
      if not tgt or tgt.dead or tgt.kind ~= "enemy" then
        tgt = nearestEnemy(enemies, b.x, b.y)
        b.target = tgt
      end
      if tgt then
        local cur = atan2(b.vx, -b.vy)
        local desired = atan2(tgt.x - b.x, -(tgt.y - b.y))
        local diff = (desired - cur + pi) % TWO_PI - pi
        local maxTurn = turn * dt
        if diff > maxTurn then diff = maxTurn
        elseif diff < -maxTurn then diff = -maxTurn end
        local na = cur + diff
        local spd = sqrt(b.vx * b.vx + b.vy * b.vy)
        b.vx = sin(na) * spd
        b.vy = -cos(na) * spd
        b.rot = na
      end
    end
  end
end

return M
