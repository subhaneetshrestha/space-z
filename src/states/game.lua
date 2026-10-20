-- src/states/game.lua — the run itself: owns the world table, orders the
-- systems, wires events to effects, and hands off to levelup/pause/gameover.
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")
local RNG = require("src.core.rng")
local Pool = require("src.core.pool")
local Events = require("src.core.events")

local Movement = require("src.systems.movement")
local Collision = require("src.systems.collision")
local Spawner = require("src.systems.spawner")
local Boss = require("src.systems.boss")
local Weapons = require("src.systems.weapons")
local Pickups = require("src.systems.pickups")
local Leveling = require("src.systems.leveling")

local Sprites = require("src.render.sprites")
local Starfield = require("src.render.starfield")
local Particles = require("src.render.particles")
local HUD = require("src.render.hud")

local Input = require("src.ui.input")
local Autopilot = require("src.ui.autopilot")

local Ships = require("src.content.ships")
local WeaponDefs = require("src.content.weapons")
local Zones = require("src.content.zones")

local Save = require("src.meta.save")
local RunSave = require("src.meta.runsave")
local Progress = require("src.meta.progress")
local Achievements = require("src.meta.achievements")

local Audio = require("src.audio.audio")
local Music = require("src.audio.music")

local VW, VH = Viewport.VW, Viewport.VH
local floor = math.floor

local M = {}

local ORANGE = { 1, 0.6, 0.25 }

-- The boss theme is built a sliver per frame during the last PREWARM_LEAD seconds
-- of a zone, so the boss spawn only has to press play.
local PREWARM_LEAD = 25
local MUSIC_PUMP_BUDGET = 0.002 -- seconds of CPU per frame

local AUTOSAVE_INTERVAL = 10 -- seconds of play between run saves

-- swap-remove entries whose t exceeds life (arcs, beams, pulses, toasts)
local function ageList(list, dt)
  for i = #list, 1, -1 do
    local a = list[i]
    a.t = a.t + dt
    if a.t > a.life then
      list[i] = list[#list]
      list[#list] = nil
    end
  end
end

local WEAPON_SFX = {
  forward = { name = "shoot", vol = 0.7 },
  spread = { name = "flak", vol = 0.8 },
  homing = { name = "missile", vol = 0.9 },
  arc = { name = "zap", vol = 0.8 },
  pulse = { name = "pulse", vol = 0.7 },
  rail = { name = "zap", vol = 1.0, pitch = 0.55 },
}

local function wireEvents(self, world)
  local events = world.events

  events:on("enemy_killed", function(enemy)
    Pickups.dropXp(world, enemy.x, enemy.y, enemy.xp or 1)
    local size = enemy.isBoss and 3.2 or (enemy.elite and 1.6 or 0.9)
    Particles.explosion(world, enemy.x, enemy.y, size, ORANGE)
    world.shake = math.min(world.shake + (enemy.isBoss and 8 or 1), 10)
    -- hit-stop: a beat of frozen time sells the big kills
    if enemy.isBoss then
      world.freezeT = 0.15
    elseif enemy.elite then
      world.freezeT = 0.06
    end
    Audio.play(enemy.isBoss and "boom_b" or "boom_s", {
      pitch = enemy.elite and 0.8 or (0.9 + love.math.random() * 0.25),
      vol = enemy.isBoss and 1 or 0.65,
    })
  end)

  events:on("weapon_fired", function(def)
    local s = WEAPON_SFX[def.behavior]
    if s then
      local base = s.pitch or 1
      Audio.play(s.name, { pitch = base * (0.95 + love.math.random() * 0.1), vol = s.vol })
    end
  end)

  events:on("weapon_evolved", function(def)
    local toasts = world.toasts
    toasts[#toasts + 1] = { text = "EVOLVED: " .. def.name, t = 0, life = 3 }
    Particles.explosion(world, world.player.x, world.player.y, 2.0, { 1, 0.9, 0.3 })
    Audio.play("levelup", { pitch = 1.3 })
  end)

  events:on("shield_blocked", function()
    -- the shield took this hit: the saved run still has it ready, so reloading it would
    -- hand it back. Gone, as for a hit that costs hull (see player_damaged).
    Save.clearRun()
    local toasts = world.toasts
    toasts[#toasts + 1] = { text = "SHIELD DOWN", t = 0, life = 1.6 }
    Particles.burst(world, world.player.x, world.player.y, {
      n = 16, speed = 190, life = 0.3, size = 0.8, color = { 0.4, 0.9, 1 },
    })
    Audio.play("pulse", { pitch = 1.6, vol = 0.6 })
    world.hpRingT = 2.0
  end)

  events:on("aoe_blast", function(x, y, r)
    Particles.explosion(world, x, y, r / 40, { 1, 0.7, 0.2 })
    world.shake = math.min(world.shake + 3, 10)
    Audio.play("boom_b", { vol = 0.7, pitch = 1.2 })
  end)

  events:on("pickup_collected", function()
    -- rapid pickup chains climb in pitch — classic arcade candy
    local now = world.time
    if now - (self.pickupT or -10) < 0.9 then
      self.pickupCombo = math.min((self.pickupCombo or 0) + 1, 12)
    else
      self.pickupCombo = 0
    end
    self.pickupT = now
    Audio.play("pickup", { pitch = 1 + self.pickupCombo * 0.05, vol = 0.8 })
  end)

  events:on("boss_pulse", function(boss)
    Audio.play("pulse")
    Particles.explosion(world, boss.x, boss.y, 2.4, { 1, 0.85, 0.35 })
    world.shake = math.min(world.shake + 5, 12)
  end)

  events:on("boss_dash", function(boss)
    Audio.play("flak", { pitch = 0.7 })
    Particles.burst(world, boss.x, boss.y, {
      n = 14, speed = 220, life = 0.35, size = 0.9, color = { 1, 0.9, 0.4 },
    })
  end)

  events:on("boss_wall", function()
    Audio.play("tick", { pitch = 0.6, vol = 0.9 })
  end)

  events:on("enemy_hit", function(enemy, dmg, isCrit, x, y)
    if #world.particles < 300 then
      Particles.burst(world, x or enemy.x, y or enemy.y, {
        n = isCrit and 6 or 3,
        speed = isCrit and 160 or 100,
        life = 0.25,
        size = isCrit and 0.8 or 0.55,
        color = isCrit and { 1, 0.9, 0.4 } or { 0.6, 0.95, 1 },
      })
    end
  end)

  events:on("player_damaged", function(amount)
    -- A save on disk was written before this hit. Killing the app and continuing would
    -- undo it (the run would come back before the bullet landed), so it is deleted now,
    -- like a death. It is deleted, not rewritten: this runs in the middle of collision
    -- handling, where a snapshot would not be exact. The next autosave, pause,
    -- background or quit writes a fresh one.
    Save.clearRun()
    self.damageFlashT = 0.35
    world.hpRingT = 2.0
    Audio.play("hurt")
  end)

  events:on("player_died", function()
    -- a dead run must never be resumable, even if the app is killed mid-death-anim
    Save.clearRun()
    world.phase = "over"
    self.deathT = 1.2
    Particles.explosion(world, world.player.x, world.player.y, 2.6, { 0.3, 0.9, 1 })
    world.shake = 12
    Audio.play("death")
    Music.stop()
  end)

  events:on("boss_spawned", function()
    Audio.play("alarm")
    Music.play("boss", world.zoneIndex)
  end)

  events:on("boss_killed", function(boss)
    Particles.explosion(world, boss.x, boss.y, 3.5, { 1, 0.5, 0.2 })
    world.phase = "warp"
    world.warpT = 2.5
    events:emit("zone_completed", world.zoneIndex)
    Audio.play("warp")
    Music.stop()
  end)
end

function M:enter(params)
  params = params or {}
  -- resuming: a validated saved run (menu passes Save.run()); its own seed, mode
  -- and ship win over whatever the menu and hangar currently say
  local resume = params.resume
  if resume and not RunSave.validate(resume) then resume = nil end
  local seed = resume and resume.seed or params.seed or os.time()

  local ship = Ships[resume and resume.ship or Save.data().settings.ship]
    or Ships.pathfinder
  local player = {
    kind = "player",
    x = VW * 0.5, y = VH * 0.72,
    vx = 0, vy = 0,
    r = 7, -- forgiving hitbox; the sprite is ~34px
    sprite = ship.sprite,
    rot = 0, scale = 1, t = 0,
    hp = ship.maxhp, maxhp = ship.maxhp,
    invulnT = 0,
    shipDef = ship,
  }

  local world = {
    mode = resume and resume.mode or params.mode or "standard",
    seed = seed,
    rng = {
      spawn = RNG.new(seed),
      drops = RNG.new(seed + 1),
      cards = RNG.new(seed + 2),
      misc = RNG.new(seed + 3),
    },
    events = Events.new(),
    time = 0, distance = 0, scrollSpeed = 120,
    zoneIndex = 1, zone = Zones[1], zoneTime = 0,
    phase = "waves",
    warpT = 0,
    player = player,
    enemies = {}, bullets = {}, ebullets = {}, pickups = {},
    drones = {}, particles = {},
    pools = {
      enemies = Pool.new(), bullets = Pool.new(), ebullets = Pool.new(),
      pickups = Pool.new(), drones = Pool.new(), particles = Pool.new(),
    },
    boss = nil,
    stats = nil,
    weapons = {}, passives = {},
    level = 1, xp = 0, xpNext = 8, pendingLevelUps = 0,
    kills = 0, bossKills = 0, noDamage = true, stardustEarned = 0,
    shake = 0,
    arcs = {},
    beams = {}, pulses = {}, toasts = {},
    auraR = 0, shieldT = 0,
    autopilot = params.autopilot or false,
    hpRingT = 0,
    zoneStartDistance = 0,
    pulseT = 0,
    freezeT = 0,
    daily = params.daily or false,
  }
  world.xpNext = Pickups.xpForLevel(1)

  Leveling.addWeapon(world, WeaponDefs[ship.startingWeapon])
  Leveling.recomputeStats(world)
  player.hp = player.maxhp

  -- overwrite the fresh run's progression with the saved one (same code path
  -- as a new run up to here, so a resumed run cannot drift from a fresh one)
  if resume then RunSave.apply(world, resume) end

  local settings = Save.data().settings
  self.world = world
  self.active = true
  self.saveT = AUTOSAVE_INTERVAL
  self.input = Input.new()
  self.starfield = Starfield.new(seed, settings.quality)
  Particles.setCap(settings.quality == "low" and 220 or 600)
  self.batch = Sprites.batch()
  self.damageFlashT = 0
  self.deathT = 0
  self.trailT = 0
  self.endedOnce = false
  self.gameoverPushed = false
  self.lowHpT = 0
  -- first-ever run: staged steering/goal hints until the tutorial completes
  self.tutorial = not Save.data().tutorialDone and not world.autopilot

  wireEvents(self, world)
  Achievements.live(world)
  Audio.load()
  -- a resumed run picks its music up where it stood: the boss theme during a boss
  -- fight, none during the warp after one (it stops when the boss dies), else the zone's
  if world.phase == "boss" then
    Music.play("boss", world.zoneIndex)
  elseif world.phase == "warp" then
    Music.stop()
  else
    Music.play("zone", world.zoneIndex)
  end

  -- the world is frozen behind a 3-2-1 until the player is ready
  if resume then StateM.push("countdown") end
end

function M:leave()
  -- Game.world outlives the state; saveRun must not snapshot a finished run
  self.active = false
end

-- Write the current run to the save file. The one entry point for every trigger
-- (autosave, pause, quit, app backgrounded). Returns true if a run was written.
-- RunSave.snapshot refuses dead, finished, daily and autopilot runs.
function M.saveRun()
  if not M.active then return false end
  local top = StateM.current()
  local run = RunSave.snapshot(M.world, {
    draftOpen = top ~= nil and top.__name == "levelup",
  })
  if not run then return false end
  return Save.setRun(run)
end

local function endRun(self, won)
  if self.endedOnce then return end
  self.endedOnce = true
  Save.clearRun() -- finished: nothing left to continue
  self.summary = Progress.endRun(self.world, won)
end

function M:update(dt)
  local world = self.world
  local player = world.player

  -- hit-stop: freeze the whole sim for a beat (drawing continues)
  if world.freezeT > 0 then
    world.freezeT = world.freezeT - dt
    return
  end

  -- 1. clocks
  world.time = world.time + dt
  if world.phase ~= "over" then
    world.distance = world.distance + world.scrollSpeed * dt
    world.zoneTime = world.zoneTime + dt
  end

  -- 2. steering
  if not player.dead then
    if world.autopilot then
      Autopilot.update(world, dt)
    else
      self.input:update(world, dt)
    end
  else
    player.vx, player.vy = 0, 0
  end

  -- 3-8. simulation systems
  world.auraR = 0 -- aura weapons re-declare their radius each frame
  Movement.update(world, dt)
  Boss.update(world, dt)
  Spawner.update(world, dt)
  if world.phase == "waves" and world.zoneTime >= world.zone.duration - PREWARM_LEAD then
    Music.prewarm("boss", world.zoneIndex)
  end
  Music.pump(MUSIC_PUMP_BUDGET)
  Weapons.update(world, dt)
  Collision.update(world, dt)
  Pickups.update(world, dt)

  -- 9-10. cosmetics
  Particles.update(world, dt)
  self.starfield:update(dt, world.scrollSpeed)

  -- 11. timers: arcs/beams/pulses/toasts, shake, invuln, regen, shield, flashes
  ageList(world.arcs, dt)
  ageList(world.beams, dt)
  ageList(world.pulses, dt)
  ageList(world.toasts, dt)
  if world.shieldT > 0 then world.shieldT = world.shieldT - dt end
  world.shake = Util.approach(world.shake, 0, 20 * dt)
  if player.invulnT > 0 then player.invulnT = player.invulnT - dt end
  if not player.dead and world.stats.regen > 0 then
    player.hp = math.min(player.maxhp, player.hp + world.stats.regen * dt)
  end
  if self.damageFlashT > 0 then self.damageFlashT = self.damageFlashT - dt end
  if world.hpRingT > 0 then world.hpRingT = world.hpRingT - dt end
  if world.pulseT > 0 then world.pulseT = world.pulseT - dt end

  -- engine trail
  if not player.dead then
    self.trailT = self.trailT - dt
    if self.trailT <= 0 then
      self.trailT = 0.03
      Particles.trail(world, player.x, player.y + 18, { 0.35, 0.9, 1 })
    end
  end

  -- low-hull heartbeat
  if not player.dead and player.hp / player.maxhp < 0.25 then
    self.lowHpT = self.lowHpT - dt
    if self.lowHpT <= 0 then
      self.lowHpT = 1.4
      Audio.play("pulse", { pitch = 0.7, vol = 0.5 })
    end
  else
    self.lowHpT = 0
  end

  -- sweep dead entities back into their pools
  Pool.sweep(world.enemies, world.pools.enemies)
  Pool.sweep(world.bullets, world.pools.bullets)
  Pool.sweep(world.ebullets, world.pools.ebullets)
  Pool.sweep(world.pickups, world.pools.pickups)
  Pool.sweep(world.particles, world.pools.particles)

  -- tutorial completes once the loop has been demonstrated
  if self.tutorial and (world.level >= 2 or world.time > 30) then
    self.tutorial = false
    Save.data().tutorialDone = true
    Save.write()
  end

  -- autosave, before the draft below takes a pending level-up off the count
  self.saveT = self.saveT - dt
  if self.saveT <= 0 then
    self.saveT = AUTOSAVE_INTERVAL
    M.saveRun()
  end

  -- 12. level-up draft (one at a time; never over a dead ship)
  if world.pendingLevelUps > 0 and world.phase ~= "over" then
    world.pendingLevelUps = world.pendingLevelUps - 1
    StateM.push("levelup", { world = world })
    return
  end

  -- 13. warp / run end
  if world.phase == "warp" then
    world.warpT = world.warpT - dt
    if world.warpT <= 0 then
      local nextZone = Zones[world.zoneIndex + 1]
      if nextZone then
        world.zoneIndex = world.zoneIndex + 1
        world.zone = nextZone
        world.zoneTime = 0
        world.spawnerState = nil
        world.phase = "waves"
        world.zoneStartDistance = world.distance
        world.pulseT = 0
        Music.play("zone", world.zoneIndex)
      else
        world.phase = "over"
        endRun(self, true)
        if not self.gameoverPushed then
          self.gameoverPushed = true
          StateM.push("gameover", { won = true, world = world, summary = self.summary })
        end
      end
    end
  elseif world.phase == "over" and player.dead then
    if self.deathT > 0 then
      self.deathT = self.deathT - dt
    elseif not self.gameoverPushed then
      self.gameoverPushed = true
      endRun(self, false)
      StateM.push("gameover", { won = false, world = world, summary = self.summary })
    end
  end
end

local function drawEntities(self, world)
  local batch = self.batch
  batch:clear()

  self.starfield:draw(batch)

  local pickups = world.pickups
  for i = 1, #pickups do
    local p = pickups[i]
    if not p.dead then
      Sprites.add(batch, p.sprite, p.x, p.y, p.rot, p.scale, 1, 1, 1, 1)
    end
  end

  local drones = world.drones
  for i = 1, #drones do
    local d = drones[i]
    if not d.dead then
      Sprites.add(batch, d.sprite, d.x, d.y, d.rot, d.scale, 1, 1, 1, 1)
    end
  end

  local enemies = world.enemies
  for i = 1, #enemies do
    local e = enemies[i]
    if not e.dead then
      local r, g, b = 1, 1, 1
      local tint = e.def and e.def.tint
      if tint then r, g, b = tint[1], tint[2], tint[3] end
      if e.elite then r, g, b = r, g * 0.55, b * 0.55 end
      if e.slowT and e.slowT > 0 then -- chilled: shifted toward ice blue
        r, g, b = r * 0.45, g * 0.8, 1
      end
      Sprites.add(batch, e.sprite, e.x, e.y, e.rot, e.scale, r, g, b, 1)
      if e.flashT and e.flashT > 0 then
        -- additive second pass reads as a white hit-flash
        Sprites.add(batch, e.sprite, e.x, e.y, e.rot, e.scale, 1, 1, 1, 0.8)
      end
    end
  end

  local player = world.player
  if not player.dead then
    -- solar aura halo beneath the ship
    if world.auraR > 0 then
      local pulse = 1 + 0.06 * math.sin(world.time * 6)
      Sprites.add(batch, "glow", player.x, player.y, 0,
        world.auraR * pulse / 14, 1, 0.55, 0.15, 0.5)
      Sprites.add(batch, "ring", player.x, player.y, world.time * 0.6,
        world.auraR * pulse / 24, 1, 0.6, 0.2, 0.35)
    end
    -- shield capacitor ring: bright when ready, dim while recharging
    if world.stats.shieldLevel > 0 then
      local ready = world.shieldT <= 0
      Sprites.add(batch, "ring", player.x, player.y, -world.time * 0.8, 0.83,
        0.4, 0.9, 1, ready and 0.8 or 0.15)
    end
    -- i-frame blink at 8 Hz
    local blink = player.invulnT > 0 and (floor(player.invulnT * 8) % 2 == 0)
    if not blink then
      Sprites.add(batch, player.sprite, player.x, player.y, 0, 1, 1, 1, 1, 1)
    end
  end

  -- graviton pulse rings expanding outward
  local pulses = world.pulses
  for i = 1, #pulses do
    local p = pulses[i]
    local f = p.t / p.life
    Sprites.add(batch, "ring", p.x, p.y, 0, (p.r * (0.2 + 0.8 * f)) / 24,
      0.7, 0.5, 1, (1 - f) * 0.9)
  end

  local bullets = world.bullets
  for i = 1, #bullets do
    local b = bullets[i]
    if not b.dead then
      Sprites.add(batch, b.sprite, b.x, b.y, b.rot, b.scale, 1, 1, 1, 1)
    end
  end

  local ebullets = world.ebullets
  for i = 1, #ebullets do
    local b = ebullets[i]
    if not b.dead then
      Sprites.add(batch, b.sprite, b.x, b.y, b.rot, b.scale, 1, 1, 1, 1)
    end
  end

  Particles.draw(world, batch)

  local lg = love.graphics
  lg.setColor(1, 1, 1, 1) -- lg.draw modulates the batch by the current color
  lg.setBlendMode("add")
  lg.draw(batch)

  -- ion arcs: two-pass additive lines
  local arcs = world.arcs
  if #arcs > 0 then
    for i = 1, #arcs do
      local a = arcs[i]
      local fade = 1 - a.t / a.life
      lg.setColor(0.3, 0.8, 1, 0.25 * fade)
      lg.setLineWidth(4)
      lg.line(a.x1, a.y1, a.x2, a.y2)
      lg.setColor(0.85, 1, 1, 0.9 * fade)
      lg.setLineWidth(1.5)
      lg.line(a.x1, a.y1, a.x2, a.y2)
    end
    lg.setLineWidth(1)
  end

  -- laser/railgun columns: wide faint pass + hot core, up to the top edge
  local beams = world.beams
  for i = 1, #beams do
    local b = beams[i]
    local fade = 1 - b.t / b.life
    local w = b.width
    if b.kind == "rail" then
      lg.setColor(1, 0.95, 0.6, 0.30 * fade)
      lg.rectangle("fill", b.x - w * 0.5, 0, w, b.y2)
      lg.setColor(1, 1, 1, 0.9 * fade)
      lg.rectangle("fill", b.x - w * 0.18, 0, w * 0.36, b.y2)
    else
      -- 2x the old per-segment alpha: the laser used to push a fresh segment every
      -- step and additively stack ceil(life/step) fading copies (~2.0x at 60 Hz).
      -- weapons.lua now keeps exactly one segment so the halo is the same on any
      -- refresh rate; these constants carry the original brightness over.
      lg.setColor(0.3, 0.9, 1, 0.44 * fade)
      lg.rectangle("fill", b.x - w * 0.5, 0, w, b.y2)
      lg.setColor(0.9, 1, 1, 1.0 * fade)
      lg.rectangle("fill", b.x - w * 0.15, 0, w * 0.3, b.y2)
    end
  end

  lg.setBlendMode("alpha")
  lg.setColor(1, 1, 1, 1)
end

function M:draw()
  local world = self.world
  local lg = love.graphics

  lg.setColor(0.004, 0.008, 0.02, 1)
  lg.rectangle("fill", 0, 0, VW, VH)

  self.starfield:drawBackdrop(world.zone, world.distance - world.zoneStartDistance)

  -- screenshake wraps world rendering only, never the HUD
  local shake = world.shake
  lg.push()
  if shake > 0.1 then
    lg.translate(
      (love.math.random() - 0.5) * 2 * shake,
      (love.math.random() - 0.5) * 2 * shake)
  end
  drawEntities(self, world)
  lg.pop()

  if self.damageFlashT > 0 then
    lg.setColor(1, 0.1, 0.1, 0.25 * (self.damageFlashT / 0.35))
    lg.rectangle("fill", 0, 0, VW, VH)
    lg.setColor(1, 1, 1, 1)
  end

  -- low-hull vignette pulse
  local player2 = world.player
  if not player2.dead and player2.hp / player2.maxhp < 0.25 then
    local a = 0.05 + 0.05 * math.sin(world.time * 5)
    lg.setColor(1, 0.1, 0.1, a)
    lg.rectangle("fill", 0, 0, VW, VH)
    lg.setColor(1, 1, 1, 1)
  end

  HUD.draw(world)

  -- first-run tutorial hints, staged over the opening seconds
  if self.tutorial then
    local hint = nil
    if world.time < 7 then
      hint = "DRAG ANYWHERE / WASD TO STEER"
    elseif world.time < 13 then
      hint = "WEAPONS FIRE THEMSELVES - JUST DODGE"
    elseif world.time < 20 then
      hint = "GRAB GREEN ENERGY CELLS TO LEVEL UP"
    end
    if hint then
      lg.setFont(Util.font(13))
      local a = 0.7 + 0.3 * math.sin(world.time * 3)
      lg.setColor(0.9, 1, 1, a)
      lg.printf(hint, 0, VH * 0.62, VW, "center")
      lg.setColor(1, 1, 1, 1)
    end
  end

  -- toast stack (achievements, evolutions, shield down)
  local toasts = world.toasts
  if #toasts > 0 then
    lg.setFont(Util.font(13))
    for i = 1, #toasts do
      local toast = toasts[i]
      local a = 1
      if toast.t < 0.2 then a = toast.t / 0.2
      elseif toast.life - toast.t < 0.5 then a = (toast.life - toast.t) / 0.5 end
      lg.setColor(1, 0.9, 0.3, 0.95 * a)
      lg.printf(toast.text, 0, 86 + (i - 1) * 20, VW, "center")
    end
    lg.setColor(1, 1, 1, 1)
  end

  if world.phase == "warp" then
    HUD.drawBanner(world, "WARP >>>")
  elseif world.zoneTime < 3 and world.phase == "waves" then
    HUD.drawBanner(world, world.zone.name, math.min(1, 3 - world.zoneTime),
      world.zone.subtitle)
  end
end

-- Overlays (levelup/pause/gameover) are pushed on top of this state, and
-- core/state.lua forwards input to the top state only — so while one is up our
-- Input never sees touchreleased and its steering pointer stays latched. Drop
-- every in-flight pointer on the way back in: the tracked positions are a whole
-- card-draft stale. Input re-adopts fingers that are still genuinely down on its
-- next step, and because grabs are delta-based that costs the hull zero motion.
function M:resume()
  self.input:reset()
end

function M:keypressed(key)
  if key == "escape" and self.world.phase ~= "over" then
    StateM.push("pause", { save = M.saveRun, daily = self.world.daily })
  end
end

function M:mousepressed(x, y, b) self.input:mousepressed(x, y, b) end
function M:mousemoved(x, y, dx, dy) self.input:mousemoved(x, y, dx, dy) end
function M:mousereleased(x, y, b) self.input:mousereleased(x, y, b) end
function M:touchpressed(id, x, y) self.input:touchpressed(id, x, y) end
function M:touchmoved(id, x, y) self.input:touchmoved(id, x, y) end
function M:touchreleased(id, x, y) self.input:touchreleased(id, x, y) end

return M
