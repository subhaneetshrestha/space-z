-- src/systems/boss.lua — boss spawning + the seven per-zone behaviors
-- (keyed on bossDef.behavior). Shared bullet-pattern helpers up top; each
-- behavior is a small state machine on the boss entity's scratch fields.
-- Events emitted for game.lua to dress with sfx/particles:
--   boss_dash (storm), boss_pulse (storm gravity pulse), boss_wall (guardian).
local Viewport = require("src.core.viewport")
local Bosses = require("src.content.bosses")

local M = {}

local sin, cos, sqrt, atan2 = math.sin, math.cos, math.sqrt, math.atan2
local floor = math.floor
local pi = math.pi
local TWO_PI = 2 * pi

local VW, VH = Viewport.VW, Viewport.VH

-- entrance descent: px/s cruise speed, slow-down gain (1/s), and minimum speed
local ENTER_SPEED, ENTER_K, ENTER_FLOOR = 95, 2.2, 20

-- ------------------------------------------------------------ shared helpers

local function spawnEbullet(world, x, y, vx, vy, damage)
  local eb = world.pools.ebullets:acquire()
  eb.kind = "ebullet"
  eb.x, eb.y = x, y
  eb.vx, eb.vy = vx, vy
  eb.r = 6
  eb.sprite = "bullet_enemy"
  eb.rot = 0
  eb.scale = 1
  eb.t = 0
  eb.dead = false
  eb.damage = damage
  eb.life = 9
  world.ebullets[#world.ebullets + 1] = eb
end

local function fireRadial(world, e, n, speed, damage, a0)
  a0 = a0 or world.rng.spawn:range(0, TWO_PI)
  for i = 0, n - 1 do
    local a = a0 + i * TWO_PI / n
    spawnEbullet(world, e.x, e.y, cos(a) * speed, sin(a) * speed, damage)
  end
end

-- n-shot fan aimed at the player; spread in radians across the whole fan
local function fireFan(world, e, n, spread, speed, damage)
  local player = world.player
  if not player or player.dead then return end
  local dx, dy = player.x - e.x, player.y - e.y
  local d = sqrt(dx * dx + dy * dy)
  if d < 1e-4 then return end
  local base = atan2(dy, dx)
  for i = 0, n - 1 do
    local a = base + (n > 1 and spread * (i / (n - 1) - 0.5) or 0)
    spawnEbullet(world, e.x, e.y, cos(a) * speed, sin(a) * speed, damage)
  end
end

local function spawnAdd(world, enemyId, x, y, opts)
  local Spawner = require("src.systems.spawner") -- late require (spawner requires boss)
  return Spawner.spawnEnemy(world, enemyId, x, y, opts)
end

-- ------------------------------------------------------------------- spawn

function M.spawn(world, bossId)
  local def = Bosses[bossId]
  if not def then error("unknown boss: " .. tostring(bossId)) end
  local e = world.pools.enemies:acquire()
  e.kind = "enemy"
  e.isBoss = true
  e.bossDef = def
  e.def = nil
  e.x, e.y = VW * 0.5, -80
  e.vx, e.vy = 0, 0
  e.r = def.r
  e.sprite = def.sprite
  e.rot = 0
  e.scale = def.scale or 1
  e.t = 0
  e.bt = 0 -- behavior clock: starts at arrival so sin() positions begin at 0
  e.dead = false
  e.maxhp = def.hp
  e.hp = def.hp
  e.touchDamage = def.touchDamage
  e.xp = def.xpReward or 40
  e.flashT = 0
  e.elite = false
  e.entering = true -- invulnerable + harmless until in position
  e.bossPhase = 1
  world.enemies[#world.enemies + 1] = e
  world.boss = e
  return e
end

-- --------------------------------------------------------------- behaviors

local behaviors = {}

-- Zone 1 — Kessler Swarm: radial debris + aimed fans, phase 2 sheds adds.
behaviors.kessler = {
  arenaY = 200,
  init = function(e)
    e.burstT, e.fanT, e.addT = 2.8, 1.7, 6
  end,
  update = function(world, e, dt, phase2)
    e.rot = e.rot + (phase2 and 0.6 or 0.35) * dt
    e.x = VW * 0.5 + sin(e.bt * (phase2 and 1.1 or 0.7)) * (VW * 0.5 - 90)

    e.burstT = e.burstT - dt
    if e.burstT <= 0 then
      e.burstT = e.burstT + (phase2 and 1.9 or 2.8)
      fireRadial(world, e, 12, 130, 10)
    end
    e.fanT = e.fanT - dt
    if e.fanT <= 0 then
      e.fanT = e.fanT + 1.7
      fireFan(world, e, 3, 0.44, 170, 12)
    end
    if phase2 then
      e.addT = e.addT - dt
      if e.addT <= 0 then
        e.addT = e.addT + 6
        spawnAdd(world, "drifter", e.x - 60, e.y + 20)
        spawnAdd(world, "drifter", e.x + 60, e.y + 20)
      end
    end
  end,
}

-- Zone 2 — Mining Leviathan: hovers dropping meteors, telegraphs, then drills
-- straight down at the player's column and grinds back up.
local HOVER_BLEND = 0.6 -- s to ease from the post-dive pose back onto the hover path

local function hoverPos(bt)
  return VW * 0.5 + sin(bt * 0.8) * 130, 170 + sin(bt * 2.1) * 8
end

behaviors.leviathan = {
  arenaY = 170,
  init = function(e)
    e.state, e.stateT, e.meteorT = "hover", 4, 2.2
    e.baseX = e.x
    e.hoverOffX, e.hoverOffY, e.hoverT = 0, 0, HOVER_BLEND
  end,
  update = function(world, e, dt, phase2)
    local player = world.player
    e.stateT = e.stateT - dt

    if e.state == "hover" then
      -- the hover path is absolute, so after a dive carry the leftover offset
      -- and let it fade out instead of snapping onto the path
      local hx, hy = hoverPos(e.bt)
      e.hoverT = e.hoverT + dt
      local k = e.hoverT / HOVER_BLEND
      k = k >= 1 and 1 or k * k * (3 - 2 * k)
      e.x = hx + e.hoverOffX * (1 - k)
      e.y = hy + e.hoverOffY * (1 - k)
      e.meteorT = e.meteorT - dt
      if e.meteorT <= 0 then
        e.meteorT = e.meteorT + (phase2 and 1.5 or 2.2)
        local n = phase2 and 5 or 3
        for i = 1, n do
          local vx = (i - (n + 1) / 2) * 70
          spawnAdd(world, "meteor", e.x + vx * 0.3, e.y + 30, { vx = vx, vy = 240 })
        end
      end
      if e.stateT <= 0 then
        e.state, e.stateT = "telegraph", 0.7
        e.diveX = player and player.x or VW * 0.5
      end

    elseif e.state == "telegraph" then
      -- shudder before the drill drops (132 = the old per-step 2.2 px at 60 Hz,
      -- dt-scaled so the amplitude doesn't double on a high-refresh display)
      e.x = e.x + sin(e.t * 40) * 132 * dt
      if e.stateT <= 0 then
        e.state = "dive"
      end

    elseif e.state == "dive" then
      local speed = phase2 and 540 or 420
      local dx = e.diveX - e.x
      e.x = e.x + (dx > 0 and 1 or -1) * math.min(math.abs(dx), 90 * dt)
      e.y = e.y + speed * dt
      if e.y >= VH * 0.62 then
        e.state = "rise"
      end

    else -- rise
      e.y = e.y - 170 * dt
      if e.y <= 170 then
        e.y = 170
        e.state, e.stateT = "hover", phase2 and 2.5 or 4
        local hx, hy = hoverPos(e.bt)
        e.hoverOffX, e.hoverOffY, e.hoverT = e.x - hx, e.y - hy, 0
      end
    end
  end,
}

-- Zone 3 — War Machine: alternating rotating spiral barrages and aimed fans.
behaviors.warmachine = {
  arenaY = 160,
  init = function(e)
    e.state, e.stateT = "fans", 3
    e.shotT, e.spiralA, e.fanShots = 0, 0, 0
  end,
  update = function(world, e, dt, phase2)
    e.x = VW * 0.5 + sin(e.bt * 0.9) * 120
    e.stateT = e.stateT - dt
    e.shotT = e.shotT - dt

    if e.state == "spiral" then
      if e.shotT <= 0 then
        e.shotT = e.shotT + 0.09
        e.spiralA = e.spiralA + 0.5
        spawnEbullet(world, e.x, e.y,
          cos(e.spiralA) * 150, sin(e.spiralA) * 150, 12)
        if phase2 then
          spawnEbullet(world, e.x, e.y,
            cos(-e.spiralA) * 150, sin(-e.spiralA) * 150, 12)
        end
      end
      if e.stateT <= 0 then
        e.state, e.stateT, e.fanShots = "fans", 3.4, 0
      end
    else
      if e.shotT <= 0 and e.fanShots < (phase2 and 4 or 3) then
        e.shotT = e.shotT + 0.6
        e.fanShots = e.fanShots + 1
        fireFan(world, e, 5, 0.5, 200, 12)
      end
      if e.stateT <= 0 then
        e.state, e.stateT = "spiral", 2.4
      end
    end
  end,
}

-- Zone 4 — Asteroid Titan: heavy radial rock bursts + sheds live asteroids.
behaviors.titan = {
  arenaY = 190,
  init = function(e)
    e.burstT, e.addT = 3.2, 7
  end,
  update = function(world, e, dt, phase2)
    e.rot = e.rot + (phase2 and 0.9 or 0.4) * dt
    e.x = VW * 0.5 + sin(e.bt * 0.55) * 150

    e.burstT = e.burstT - dt
    if e.burstT <= 0 then
      e.burstT = e.burstT + (phase2 and 2.4 or 3.2)
      fireRadial(world, e, phase2 and 16 or 10, 120, 14)
    end
    e.addT = e.addT - dt
    if e.addT <= 0 then
      e.addT = e.addT + (phase2 and 8 or 7)
      local id = phase2 and "asteroid_l" or "asteroid_s"
      spawnAdd(world, id, e.x - 50, e.y + 30, { vx = -60, vy = 110 })
      spawnAdd(world, id, e.x + 50, e.y + 30, { vx = 60, vy = 110 })
    end
  end,
}

-- Zone 5 — The Great Storm: lightning dashes across the sky, rings on arrival;
-- every third attack is a gravity pulse that drags the ship toward the deck.
behaviors.storm = {
  arenaY = 180,
  init = function(e)
    e.state, e.stateT = "drift", 2.2
    e.dashes = 0
  end,
  update = function(world, e, dt, phase2)
    e.y = 180 + sin(e.bt * 1.6) * 22
    e.stateT = e.stateT - dt

    if e.state == "drift" then
      e.x = e.x + sin(e.t * 0.7) * 30 * dt
      if e.stateT <= 0 then
        e.dashes = e.dashes + 1
        if e.dashes % 3 == 0 then
          e.state, e.stateT = "pulse", 0.6
          world.pulseT = 1.4
          world.events:emit("boss_pulse", e)
          fireRadial(world, e, 6, 90, 12)
        else
          e.state, e.stateT = "telegraph", 0.5
          e.dashX = world.rng.spawn:range(70, VW - 70)
        end
      end

    elseif e.state == "telegraph" then
      if e.stateT <= 0 then e.state = "dash" end

    elseif e.state == "dash" then
      local dx = e.dashX - e.x
      local step = 900 * dt
      if math.abs(dx) <= step then
        e.x = e.dashX
        e.state, e.stateT = "drift", phase2 and 1.3 or 2.2
        world.events:emit("boss_dash", e)
        fireRadial(world, e, phase2 and 14 or 10, 170, 13)
      else
        e.x = e.x + (dx > 0 and step or -step)
      end

    else -- pulse recovery
      if e.stateT <= 0 then
        e.state, e.stateT = "drift", phase2 and 1.3 or 2.2
      end
    end
  end,
}

-- Zone 6 — Ring Guardian: descending ice walls with dodge gaps + shard fans.
behaviors.guardian = {
  arenaY = 150,
  init = function(e)
    e.wallT, e.fanT, e.wallFlip = 2.2, 1.5, false
  end,
  update = function(world, e, dt, phase2)
    e.x = VW * 0.5 + sin(e.bt * 0.5) * 170

    e.wallT = e.wallT - dt
    if e.wallT <= 0 then
      e.wallT = e.wallT + (phase2 and 2.6 or 3.6)
      e.wallFlip = not e.wallFlip
      local rng = world.rng.spawn
      local step = 30
      local slots = floor((VW - 40) / step)
      local g1 = rng:random(0, slots - 3)
      local g2 = phase2 and rng:random(0, slots - 3) or g1
      for s = 0, slots do
        local inGap = (s >= g1 and s <= g1 + 2) or (s >= g2 and s <= g2 + 2)
        if not inGap then
          local x = 20 + s * step + (e.wallFlip and step * 0.5 or 0)
          spawnEbullet(world, x, -20, 0, phase2 and 165 or 140, 13)
        end
      end
      world.events:emit("boss_wall", e)
    end

    e.fanT = e.fanT - dt
    if e.fanT <= 0 then
      e.fanT = e.fanT + 1.5
      fireFan(world, e, phase2 and 5 or 3, 0.5, 190, 13)
    end
  end,
}

-- Zone 7 — The Space Z Overlord: three phases by hp thirds.
behaviors.overlord = {
  arenaY = 190,
  init = function(e)
    e.fanT, e.spiralT, e.spiralA, e.radialT, e.addT, e.wallT = 1.6, 0, 0, 3, 5, 3
  end,
  update = function(world, e, dt, phase2)
    local third = e.hp / e.maxhp
    e.x = VW * 0.5 + sin(e.bt * (third < 1 / 3 and 1.0 or 0.6)) * 140
    e.rot = sin(e.bt * 0.8) * 0.15

    if third > 2 / 3 then
      e.fanT = e.fanT - dt
      if e.fanT <= 0 then
        e.fanT = e.fanT + 1.6
        fireFan(world, e, 5, 0.55, 190, 14)
      end
      e.addT = e.addT - dt
      if e.addT <= 0 then
        e.addT = e.addT + 5
        spawnAdd(world, "hive_dart", e.x - 40, e.y + 30)
        spawnAdd(world, "hive_dart", e.x + 40, e.y + 30)
      end

    elseif third > 1 / 3 then
      e.spiralT = e.spiralT - dt
      if e.spiralT <= 0 then
        e.spiralT = e.spiralT + 0.1
        e.spiralA = e.spiralA + 0.42
        spawnEbullet(world, e.x, e.y,
          cos(e.spiralA) * 160, sin(e.spiralA) * 160, 14)
      end
      e.radialT = e.radialT - dt
      if e.radialT <= 0 then
        e.radialT = e.radialT + 3
        fireRadial(world, e, 12, 140, 14)
      end

    else -- desperation
      e.wallT = e.wallT - dt
      if e.wallT <= 0 then
        e.wallT = e.wallT + 3
        local rng = world.rng.spawn
        local step = 34
        local slots = floor((VW - 40) / step)
        local g = rng:random(0, slots - 3)
        for s = 0, slots do
          if s < g or s > g + 2 then
            spawnEbullet(world, 20 + s * step, -20, 0, 150, 14)
          end
        end
      end
      e.radialT = e.radialT - dt
      if e.radialT <= 0 then
        e.radialT = e.radialT + 2.2
        fireRadial(world, e, 16, 150, 14)
      end
      e.addT = e.addT - dt
      if e.addT <= 0 then
        e.addT = e.addT + 6
        spawnAdd(world, "hive_dart", e.x, e.y + 40)
      end
    end
  end,
}

-- ------------------------------------------------------------------ update

function M.update(world, dt)
  local e = world.boss
  if not e or e.dead then return end
  local b = behaviors[e.bossDef and e.bossDef.behavior]
  if not b then return end

  e.t = e.t + dt
  if e.flashT and e.flashT > 0 then
    e.flashT = e.flashT - dt
    if e.flashT < 0 then e.flashT = 0 end
  end

  if e.entering then
    -- cruise at ENTER_SPEED, then slow in proportion to the distance left; the
    -- floor keeps it from stalling short of the arena
    local speed = (b.arenaY - e.y) * ENTER_K
    if speed > ENTER_SPEED then speed = ENTER_SPEED
    elseif speed < ENTER_FLOOR then speed = ENTER_FLOOR end
    e.y = e.y + speed * dt
    if e.y >= b.arenaY then
      e.y = b.arenaY
      e.entering = false
      e.bt = 0
      b.init(e)
    end
    return
  end

  e.bt = e.bt + dt
  local phase2 = e.hp < e.maxhp * 0.5
  if phase2 and e.bossPhase == 1 then e.bossPhase = 2 end
  b.update(world, e, dt, phase2)
end

return M
