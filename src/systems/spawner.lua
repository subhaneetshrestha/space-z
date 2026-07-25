-- src/systems/spawner.lua — data-driven wave director for the current zone.
-- Each zone wave entry is an independent stream: active while
-- zoneTime ∈ [t, until_], spawning `count` enemies every `interval` seconds.
local Viewport = require("src.core.viewport")
local Enemies = require("src.content.enemies")
local Boss = require("src.systems.boss")

local M = {}

local ceil = math.ceil

local VW, VH = Viewport.VW, Viewport.VH
local MARGIN = 30
local SPAWN_Y = -30
local ELITE_AFTER = 45     -- zone seconds before elites can appear
local ELITE_CHANCE = 0.06
local BOSS_CLEAR_COUNT = 6 -- live enemies allowed before the boss warps in

-- opts: { elite = bool, vx = n, vy = n } (vx/vy: initial velocity, e.g. side spawns)
function M.spawnEnemy(world, enemyId, x, y, opts)
  local def = Enemies[enemyId]
  if not def then error("unknown enemy: " .. tostring(enemyId)) end
  local e = world.pools.enemies:acquire()
  e.kind = "enemy"
  e.def = def
  e.x, e.y = x, y
  e.vx = (opts and opts.vx) or 0
  e.vy = (opts and opts.vy) or def.speed
  e.r = def.r
  e.sprite = def.sprite
  e.rot = 0
  e.scale = def.scale or 1
  e.t = 0
  e.dead = false
  e.maxhp = def.hp
  e.hp = def.hp
  e.touchDamage = def.touchDamage
  e.xp = def.xp
  e.elite = false
  e.flashT = 0

  -- difficulty: deeper zones and deeper zone-time both scale enemies up;
  -- Black Hole mode ships tankier enemies on top
  local zoneMult = 1 + 0.35 * ((world.zoneIndex or 1) - 1)
  local hpMult = zoneMult * (1 + 0.5 * (world.zoneTime / 60))
  if world.mode == "blackhole" then hpMult = hpMult * 1.5 end
  e.maxhp = ceil(e.maxhp * hpMult)
  e.hp = e.maxhp
  e.touchDamage = ceil(e.touchDamage * (1 + 0.1 * ((world.zoneIndex or 1) - 1)))

  if opts and opts.elite then
    e.elite = true
    e.maxhp = e.maxhp * 4
    e.hp = e.maxhp
    e.scale = e.scale * 1.4
    e.r = e.r * 1.4
    e.touchDamage = ceil(e.touchDamage * 1.5)
    e.xp = def.xp * 5
  end

  world.enemies[#world.enemies + 1] = e
  return e
end

local function spawnFromWave(world, wave)
  local rng = world.rng.spawn
  for _ = 1, wave.count do
    local elite = world.zoneTime > ELITE_AFTER and rng:chance(ELITE_CHANCE)
    local opts = elite and { elite = true } or nil
    if wave.from == "sides" then
      -- crossing hazards (ring ice, belt rocks): enter from a screen edge
      local fromLeft = rng:chance(0.5)
      local x = fromLeft and -30 or (VW + 30)
      local y = rng:range(40, VH * 0.55)
      local vx = rng:range(60, 150) * (fromLeft and 1 or -1)
      local vy = rng:range(20, 80)
      opts = opts or {}
      opts.vx, opts.vy = vx, vy
      M.spawnEnemy(world, wave.enemy, x, y, opts)
    else
      local x = rng:range(MARGIN, VW - MARGIN)
      M.spawnEnemy(world, wave.enemy, x, SPAWN_Y, opts)
    end
  end
end

function M.update(world, dt)
  if world.phase ~= "waves" then return end

  local zone = world.zone
  local zt = world.zoneTime

  local state = world.spawnerState
  if not state then
    state = { timers = {} }
    world.spawnerState = state
  end
  local timers = state.timers

  if zt < zone.duration then
    for i = 1, #zone.waves do
      local wave = zone.waves[i]
      if zt >= wave.t and zt < (wave.until_ or zone.duration) then
        local timer = timers[i]
        if timer == nil then
          timer = 0 -- first spawn fires immediately when the stream opens
        end
        timer = timer - dt
        while timer <= 0 do
          spawnFromWave(world, wave)
          timer = timer + wave.interval
        end
        timers[i] = timer
      end
    end
  else
    -- zone timeline exhausted: let the field clear, then bring in the boss
    local live = 0
    for i = 1, #world.enemies do
      if not world.enemies[i].dead then live = live + 1 end
    end
    if live < BOSS_CLEAR_COUNT then
      world.phase = "boss"
      local boss = Boss.spawn(world, zone.boss)
      world.events:emit("boss_spawned", boss)
    end
  end
end

return M
