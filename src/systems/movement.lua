-- src/systems/movement.lua
-- Integrates player / bullets / ebullets / pickups and runs the five enemy
-- movement patterns. Boss entities are skipped (systems/boss.lua owns them);
-- drones are owned by weapons.lua. Stateless: everything lives on `world`.

local Viewport = require("src.core.viewport")
local Util = require("src.core.util")

local M = {}

local VW, VH = Viewport.VW, Viewport.VH
local sin, cos, sqrt, atan2 = math.sin, math.cos, math.sqrt, math.atan2
local approach, clamp = Util.approach, Util.clamp

local EBULLET_LIFE = 8

local function spawnEbulletAt(world, x, y, tx, ty, speed, damage)
  local dx, dy = tx - x, ty - y
  local d = sqrt(dx * dx + dy * dy)
  if d < 1e-4 then dx, dy, d = 0, 1, 1 end
  local eb = world.pools.ebullets:acquire()
  eb.kind = "ebullet"
  eb.x, eb.y = x, y
  eb.vx, eb.vy = dx / d * speed, dy / d * speed
  eb.r = 6
  eb.sprite = "bullet_enemy"
  eb.rot = atan2(dx, -dy)
  eb.scale = 1
  eb.t = 0
  eb.dead = false
  eb.damage = damage
  eb.life = EBULLET_LIFE
  world.ebullets[#world.ebullets + 1] = eb
end

-- px/py: player position (or a fallback aim point when the player is gone).
local function updateEnemy(world, e, dt, px, py)
  local def = e.def
  local mv = def and def.movement

  if e.flashT and e.flashT > 0 then
    e.flashT = e.flashT - dt
    if e.flashT < 0 then e.flashT = 0 end
  end

  -- graviton/cryo slow: time dilation for everything below this line
  -- (movement, pattern phase, shooter fire timers — all crawl together)
  if e.slowT and e.slowT > 0 then
    e.slowT = e.slowT - dt
    dt = dt * (e.slowMult or 0.5)
  end

  e.t = e.t + dt

  if mv == "drift" then
    -- pattern scratch is initialized lazily: pooled tables come back empty
    if e.phase == nil then
      e.phase = e.x * 0.7
      e.baseX = e.x
      e.spin = (e.x % 2 < 1) and 0.9 or -0.9
      e.vy = def.speed
    end
    e.vx = sin(e.t * 1.7 + e.phase) * 14
    e.rot = e.rot + e.spin * dt
    e.x = e.x + e.vx * dt
    e.y = e.y + e.vy * dt

  elseif mv == "sine" then
    if e.baseX == nil then
      e.baseX = e.x
      e.vx = 0
      e.vy = def.speed
    end
    e.x = e.baseX + sin(e.t * 2.2) * 70
    e.y = e.y + e.vy * dt
    e.rot = cos(e.t * 2.2) * 0.35

  elseif mv == "chaser" then
    if e.spd == nil then
      e.spd = def.speed * 1.6
      e.vx = e.vx or 0
      e.vy = e.vy or def.speed
    end
    local accel = def.accel or 180
    local dx, dy = px - e.x, py - e.y
    local d = sqrt(dx * dx + dy * dy)
    if d > 1e-4 then
      e.vx = e.vx + dx / d * accel * dt
      e.vy = e.vy + dy / d * accel * dt
    end
    local sp = sqrt(e.vx * e.vx + e.vy * e.vy)
    if sp > e.spd then
      local k = e.spd / sp
      e.vx, e.vy = e.vx * k, e.vy * k
    end
    e.x = e.x + e.vx * dt
    e.y = e.y + e.vy * dt
    e.rot = atan2(e.vx, -e.vy)

  elseif mv == "shooter" then
    local holdY = def.holdY or 180
    if e.phase == nil then
      e.phase = "descend"
      e.baseX = e.x
      e.fireT = def.fire and def.fire.cooldown or 2
      e.vx, e.vy = 0, def.speed
    end
    if e.phase == "descend" then
      e.y = e.y + def.speed * dt
      if e.y >= holdY then
        e.y = holdY
        e.phase = "hold"
      end
    else
      e.x = e.baseX + sin(e.t * 1.3) * 46
      if def.fire then
        e.fireT = e.fireT - dt
        if e.fireT <= 0 then
          e.fireT = e.fireT + def.fire.cooldown
          spawnEbulletAt(world, e.x, e.y + e.r, px, py, def.fire.speed, def.fire.damage)
        end
      end
    end
    e.rot = atan2(px - e.x, -(py - e.y))

  elseif mv == "lunge" then
    if e.phase == nil then
      e.phase = "descend"
      e.lungeT = 2.5
      e.vx = e.vx or 0
      e.vy = def.speed * 0.4
    end
    if e.phase == "descend" then
      e.vy = approach(e.vy, def.speed * 0.4, 300 * dt)
      e.vx = approach(e.vx, 0, 300 * dt)
      e.lungeT = e.lungeT - dt
      if e.lungeT <= 0 then
        local dx, dy = px - e.x, py - e.y
        local d = sqrt(dx * dx + dy * dy)
        local nx, ny
        if d < 1e-4 then nx, ny = 0, 1 else nx, ny = dx / d, dy / d end
        local dashSpd = def.speed * 2.4
        e.vx, e.vy = nx * dashSpd, ny * dashSpd
        e.rot = atan2(nx, -ny)
        e.phase = "dash"
        e.lungeT = 0.45
      end
    else
      e.lungeT = e.lungeT - dt
      if e.lungeT <= 0 then
        e.phase = "descend"
        e.lungeT = 2.5
      end
    end
    e.x = e.x + e.vx * dt
    e.y = e.y + e.vy * dt

  elseif mv == "ballistic" then
    -- keeps its spawn velocity (asteroids, meteors, ring ice); only tumbles
    if e.spin == nil then
      e.spin = (def.spin or 1) * ((e.x % 2 < 1) and 1 or -1)
      if e.vx == 0 and e.vy == 0 then e.vy = def.speed end
      -- travel-aligned sprites (meteors) face their velocity once at spawn
      if def.spin and def.spin >= 3 then
        e.rot = atan2(e.vx, -e.vy)
        e.spin = 0
      end
    end
    e.rot = e.rot + e.spin * dt
    e.x = e.x + e.vx * dt
    e.y = e.y + e.vy * dt
    -- side-spawned rocks cull once they exit the far edge
    if (e.vx < 0 and e.x < -70) or (e.vx > 0 and e.x > VW + 70) then
      e.dead = true
    end

  else
    -- unknown pattern: plain downward drift so nothing ever freezes on screen
    if e.vy == nil then e.vx, e.vy = 0, (def and def.speed) or 60 end
    e.x = e.x + e.vx * dt
    e.y = e.y + e.vy * dt
  end

  -- shooters hold position on-screen and never fly past; bosses handled elsewhere
  if e.y > VH + 60 and mv ~= "shooter" then
    e.dead = true
  end
end

function M.update(world, dt)
  local player = world.player
  local mods = world.zone and world.zone.modifiers

  if player then
    player.t = (player.t or 0) + dt
    -- zone environment: heavy worlds steer sluggishly and drag the ship down,
    -- dust storms shove it sideways, storm-boss pulses yank it toward the deck
    local speedMult = (mods and mods.playerSpeedMult) or 1
    player.x = player.x + player.vx * speedMult * dt
    player.y = player.y + player.vy * speedMult * dt
    if mods and mods.gravity then
      player.y = player.y + mods.gravity * dt
    end
    if mods and mods.wind then
      local w = mods.wind
      player.x = player.x + sin(world.time * (2 * math.pi) / w.period) * w.amp * dt
    end
    if world.pulseT and world.pulseT > 0 then
      player.y = player.y + 150 * dt
    end
    player.x = clamp(player.x, 20, VW - 20)
    player.y = clamp(player.y, 80, VH - 30)
  end

  local px, py
  if player then
    px, py = player.x, player.y
  else
    px, py = VW * 0.5, VH - 120
  end

  local enemies = world.enemies
  for i = 1, #enemies do
    local e = enemies[i]
    if not e.dead and not e.isBoss then
      updateEnemy(world, e, dt, px, py)
    end
  end

  local bullets = world.bullets
  for i = 1, #bullets do
    local b = bullets[i]
    if not b.dead then
      b.t = b.t + dt
      b.x = b.x + b.vx * dt
      b.y = b.y + b.vy * dt
      b.life = b.life - dt
      if b.life <= 0
        or b.x < -60 or b.x > VW + 60
        or b.y < -60 or b.y > VH + 60 then
        b.dead = true
      end
    end
  end

  local ebullets = world.ebullets
  for i = 1, #ebullets do
    local b = ebullets[i]
    if not b.dead then
      b.t = b.t + dt
      b.x = b.x + b.vx * dt
      b.y = b.y + b.vy * dt
      b.life = b.life - dt
      if b.life <= 0
        or b.x < -60 or b.x > VW + 60
        or b.y < -60 or b.y > VH + 60 then
        b.dead = true
      end
    end
  end

  local pickups = world.pickups
  for i = 1, #pickups do
    local p = pickups[i]
    if not p.dead then
      p.t = p.t + dt
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      if p.y > VH + 40 then
        p.dead = true
      end
    end
  end
end

return M
