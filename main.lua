-- main.lua — LÖVE entry point: boot, fixed timestep, input routing, and the
-- headless-ish harness modes:  love . --test  |  love . --smoke
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Compat = require("src.compat")

local STEP = 1 / 60
local MIN_STEP = 1 / 240 -- sub-steps below this carry to the next frame instead
local MAX_STEPS = 5      -- normal mode: drop time beyond this per frame
local SMOKE_STEPS = 8    -- smoke mode: fixed 8x speed
local SMOKE_LIMIT = 320  -- sim-seconds before the smoke run gives up
local SMOKE_LIMIT_GOD = 2400 -- god runs must cover all 7 zones + bosses

local accumulator = 0
local smoke = nil        -- smoke-run tracking table when --smoke is active

local function hasArg(args, want)
  for i = 1, #(args or {}) do
    if args[i] == want then return true end
  end
  return false
end

local function registerStates()
  StateM.register("menu", require("src.states.menu"))
  StateM.register("game", require("src.states.game"))
  StateM.register("pause", require("src.states.pause"))
  StateM.register("countdown", require("src.states.countdown"))
  StateM.register("levelup", require("src.states.levelup"))
  StateM.register("gameover", require("src.states.gameover"))
  StateM.register("hangar", require("src.states.hangar"))
  StateM.register("starmap", require("src.states.starmap"))
end

-- ---------------------------------------------------------------- smoke mode

local function smokeLog(line)
  smoke.report[#smoke.report + 1] = line
  print("[smoke] " .. line)
end

local function smokeCapture(label)
  if smoke.captured[label] then return end
  smoke.captured[label] = true
  local filename = "smoke_" .. label .. ".png"
  love.graphics.captureScreenshot(filename)
  smokeLog("screenshot: " .. filename .. " (t=" .. string.format("%.1f", smoke.simT) .. "s)")
end

local function smokeFinalize(result)
  if smoke.finalized then return end
  smoke.finalized = true
  local game = require("src.states.game")
  local world = game.world
  if world then
    smokeLog(string.format("final: t=%.1fs zone=%d level=%d kills=%d distance=%.0f phase=%s",
      smoke.simT, world.zoneIndex, world.level, world.kills, world.distance,
      tostring(world.phase)))
    smokeLog(string.format("bosses: spawned=%s killed=%d current_hp=%s",
      tostring(smoke.bossSeen), world.bossKills,
      world.boss and string.format("%.0f/%d", world.boss.hp, world.boss.maxhp) or "-"))
    smokeLog("max live entities: " .. smoke.maxEntities)
    smokeLog(string.format("player: hp=%.0f/%.0f dead=%s",
      world.player.hp, world.player.maxhp, tostring(world.player.dead)))
  end
  smokeLog("RESULT: " .. result)
  love.filesystem.write("smoke_report.txt", table.concat(smoke.report, "\n") .. "\n")
end

local function smokeStep()
  local game = require("src.states.game")
  StateM.update(STEP)
  smoke.simT = smoke.simT + STEP

  -- stage 1: tour the meta screens (menu -> hangar -> star map), capturing
  -- each, then launch the run
  if smoke.stage == "menu" then
    if smoke.simT >= 0.5 then smokeCapture("menu") end
    if smoke.simT >= 1.0 then
      smoke.stage = "hangar"
      StateM.switch("hangar")
    end
    return
  elseif smoke.stage == "hangar" then
    if smoke.simT >= 1.4 then smokeCapture("hangar") end
    if smoke.simT >= 1.8 then
      smoke.stage = "starmap"
      StateM.switch("starmap")
    end
    return
  elseif smoke.stage == "starmap" then
    if smoke.simT >= 2.2 then smokeCapture("starmap") end
    if smoke.simT >= 2.6 then
      smoke.stage = "game"
      StateM.switch("game", { autopilot = true, seed = 12345 })
      if smoke.god then
        -- coverage build: strong enough to see every zone and boss.
        -- Recomputes rebuild stats from shipDef + passives, so durability
        -- must live there: a beefed-up ship copy + a permanent regen passive.
        local world = game.world
        local Leveling = require("src.systems.leveling")
        local Weapons = require("src.content.weapons")
        local Upgrades = require("src.content.upgrades")
        -- covers homing/beam/pulse/rail/orbital behaviors; missiles maxed +
        -- warhead_yield makes the first draft a guaranteed evolution (aoe path)
        for _, id in ipairs({ "missiles", "laser", "graviton", "railgun", "drones" }) do
          Leveling.addWeapon(world, Weapons[id])
          world.weapons[#world.weapons].level = 4
        end
        world.weapons[2].level = Weapons.missiles.maxLevel
        Leveling.addPassive(world, Upgrades.warhead_yield)
        world.weapons[1].level = 6 -- blaster
        local base = world.player.shipDef
        world.player.shipDef = {
          id = base.id, name = base.name, sprite = base.sprite,
          startingWeapon = base.startingWeapon,
          maxhp = 20000, speed = base.speed,
        }
        world.passives[#world.passives + 1] = {
          def = { id = "god_regen", name = "God Regen", kind = "passive",
                  desc = "", stat = "regen", perLevel = 120, maxLevel = 1 },
          level = 1,
        }
        Leveling.recomputeStats(world)
        world.player.hp = world.player.maxhp
        smokeLog("god build granted (coverage run)")
      end
    end
    return
  end

  local world = game.world
  if world then
    local live = #world.enemies + #world.bullets + #world.ebullets
      + #world.pickups + #world.drones + #world.particles
    if live > smoke.maxEntities then smoke.maxEntities = live end
    if world.boss then
      smoke.bossSeen = true
      if world.boss.entering == false then smokeCapture("boss") end
    end
  end

  local cur = StateM.current()
  local name = cur and cur.__name
  if name == "levelup" then smokeCapture("levelup") end
  if name == "gameover" then smokeCapture("gameover") end
  if smoke.simT >= 5 then smokeCapture("early") end
  if smoke.simT >= 40 then smokeCapture("mid") end
  if smoke.simT >= 100 then smokeCapture("late") end
  -- god run: capture every zone once, and every boss once
  if world and smoke.god then
    if world.zoneIndex ~= smoke.lastZone then
      smoke.lastZone = world.zoneIndex
      smoke.captured["zoneshot"] = nil -- re-arm for the new zone
    end
    if world.zoneTime > 20 and world.phase == "waves" then
      if not smoke.captured["zoneshot"] then
        smoke.captured["zoneshot"] = true
        smokeCapture("zone" .. world.zoneIndex)
      end
    end
    if world.boss and world.boss.entering == false then
      smokeCapture("boss" .. world.zoneIndex)
    end
  end

  if smoke.simT >= smoke.limit then
    smokeFinalize("OK (time limit)")
    love.event.quit(0)
  end
end

-- --------------------------------------------------------------------- boot

-- "OpenGL 4.5 (Mesa llvmpipe ...)": which renderer a headless run really used, so a CI
-- log can show a green run was on the software renderer it was meant to be on
local function rendererLine()
  local name, version, vendor, device = love.graphics.getRendererInfo()
  return string.format("%s %s | %s | %s", tostring(name), tostring(version), tostring(vendor), tostring(device))
end

function love.load(args)
  if hasArg(args, "--test") then
    print("[renderer] " .. rendererLine())
    local ok, run = pcall(require, "tests.run")
    if not ok then
      print("FATAL: could not load tests/run.lua: " .. tostring(run))
      love.event.quit(1)
      return
    end
    local failures = run.runAll()
    love.event.quit(failures == 0 and 0 or 1)
    return
  end

  love.graphics.setDefaultFilter("linear", "linear")
  Viewport.resize(love.graphics.getDimensions())
  require("src.render.sprites").build()
  require("src.meta.save").load()
  registerStates()

  -- store-asset export: renders launcher icons to the save dir, then quits
  if hasArg(args, "--icons") then
    local Sprites = require("src.render.sprites")
    local lg = love.graphics
    for _, size in ipairs({ 512, 192, 144, 96, 48 }) do
      local canvas = lg.newCanvas(size, size)
      lg.push("all")
      lg.setCanvas(canvas)
      local s = size / 128 -- design space: 128
      lg.scale(s, s)
      -- night-sky gradient: violet up top fading into blue-black
      for i = 0, 15 do
        local t = i / 15
        lg.setColor(0.10 * (1 - t) + 0.02, 0.03 * (1 - t) + 0.02,
          0.22 * (1 - t) + 0.08, 1)
        lg.rectangle("fill", 0, i * 8, 128, 8)
      end
      -- nebula haze
      lg.setBlendMode("add")
      lg.setColor(0.45, 0.10, 0.50, 0.14)
      lg.circle("fill", 22, 22, 46)
      lg.setColor(0.10, 0.30, 0.60, 0.18)
      lg.circle("fill", 108, 106, 54)
      -- star sprinkle, a few tinted, two with twinkle crosses
      for _, star in ipairs({ {22,24,1.4, 1,1,1},     {104,64,1.0, 1,0.8,0.5},
                              {88,40,1.6, 0.6,1,1},   {14,78,1.0, 1,0.7,0.9},
                              {116,88,1.2, 0.9,0.9,1}, {48,12,0.9, 1,1,0.8},
                              {30,104,1.3, 0.7,0.9,1}, {74,16,1.0, 1,0.9,0.9} }) do
        lg.setColor(star[4], star[5], star[6], 0.9)
        lg.circle("fill", star[1], star[2], star[3])
      end
      lg.setLineWidth(1)
      lg.setColor(1, 1, 1, 0.55)
      lg.line(88, 33, 88, 47); lg.line(81, 40, 95, 40)
      lg.line(22, 18, 22, 30); lg.line(16, 24, 28, 24)
      -- little ringed planet, upper right
      lg.setBlendMode("alpha")
      lg.setColor(1.0, 0.55, 0.30, 1)
      lg.circle("fill", 103, 27, 10)
      lg.setColor(1.0, 0.75, 0.45, 1)
      lg.circle("fill", 100, 24, 5)
      lg.push()
      lg.translate(103, 28)
      lg.rotate(-0.35)
      lg.setLineWidth(2.5)
      lg.setColor(1.0, 0.85, 0.55, 0.9)
      lg.ellipse("line", 0, 0, 16, 4.5)
      lg.pop()
      -- ascent speed-streaks
      lg.setBlendMode("add")
      lg.setLineWidth(2)
      lg.setColor(0.3, 0.9, 1, 0.45)
      lg.line(38, 92, 38, 114)
      lg.line(90, 88, 90, 112)
      lg.line(24, 48, 24, 64)
      -- engine flame: warm core trailing off the tail
      lg.setColor(1, 0.45, 0.10, 0.85)
      lg.polygon("fill", 56, 84, 72, 84, 64, 118)
      lg.setColor(1, 0.85, 0.35, 0.95)
      lg.polygon("fill", 60, 84, 68, 84, 64, 104)
      -- cyan halo + ship, slightly above center
      lg.setColor(0.2, 0.8, 1, 0.4)
      lg.circle("fill", 64, 58, 40, 48)
      lg.setColor(1, 1, 1, 1)
      lg.draw(Sprites.image(), Sprites.quad("ship_pathfinder"), 64, 56, 0,
        2.2, 2.2, Sprites.info("ship_pathfinder").w * 0.5,
        Sprites.info("ship_pathfinder").h * 0.5)
      lg.setBlendMode("alpha")
      lg.setCanvas()
      lg.pop()
      local data = Compat.readbackImageData(canvas, lg)
      data:encode("png", "icon_" .. size .. ".png")
      print("[icons] wrote icon_" .. size .. ".png (save dir)")
      data:release()
      canvas:release()
    end
    love.event.quit(0)
    return
  end

  if hasArg(args, "--smoke") then
    local god = hasArg(args, "god")
    smoke = {
      simT = 0, maxEntities = 0, bossSeen = false,
      captured = {}, report = {}, finalized = false,
      stage = "menu", god = god, lastZone = 1,
      limit = god and SMOKE_LIMIT_GOD or SMOKE_LIMIT,
    }
    smokeLog("renderer: " .. rendererLine())
    smokeLog("smoke run: seed=12345, speed=" .. SMOKE_STEPS .. "x, limit="
      .. smoke.limit .. "s" .. (god and " [GOD]" or ""))
    StateM.switch("menu")
  else
    StateM.switch("menu")
  end
end

function love.update(dt)
  if smoke then
    for _ = 1, SMOKE_STEPS do
      if smoke.finalized then break end
      local ok, err = xpcall(smokeStep, debug.traceback)
      if not ok then
        smokeFinalize("ERROR\n" .. tostring(err))
        love.event.quit(1)
        break
      end
    end
    return
  end

  -- Semi-fixed timestep: always advance by the real elapsed time, in chunks of
  -- at most STEP. The old pure-fixed loop ran ZERO steps on most frames of a
  -- 90/120 Hz display (and beat 0/2 under dt jitter at 60 Hz), which made the
  -- ship stair-step under a smoothly moving finger. Events are pumped before
  -- love.update, so one sub-step per frame means this frame's touchmoved is
  -- consumed by this frame's simulation.
  accumulator = accumulator + dt
  local steps = 0
  while accumulator >= MIN_STEP and steps < MAX_STEPS do
    local s = accumulator < STEP and accumulator or STEP
    StateM.update(s)
    accumulator = accumulator - s
    steps = steps + 1
  end
  -- Hitch or sustained overload: drop the backlog instead of spiraling. Change
  -- below MIN_STEP is kept, so a very fast display never loses time.
  if accumulator >= MIN_STEP then accumulator = 0 end
end

function love.draw()
  Viewport.apply()
  StateM.draw()
  Viewport.unapply()
end

-- Persist the in-progress run (a no-op unless a saveable run is active). Never
-- lets a failed save keep the app from backgrounding or closing.
local function saveRun()
  local ok, err = pcall(function() require("src.states.game").saveRun() end)
  if not ok then print("[save] run save failed: " .. tostring(err)) end
end

-- Android backgrounding (and desktop alt-tab) arrive here; the process may be
-- killed without love.quit ever running, so this is the save that matters there.
function love.focus(focused)
  if not focused then saveRun() end
end

function love.quit()
  saveRun()
  if smoke and not smoke.finalized then
    smokeFinalize("OK (run ended)")
  end
  return false
end

function love.resize(w, h)
  Viewport.resize(w, h)
  StateM.resize()
end

function love.keypressed(key)
  StateM.keypressed(key)
end

function love.mousepressed(x, y, button, istouch)
  if istouch then return end -- touches arrive via love.touchpressed
  local vx, vy = Viewport.toVirtual(x, y)
  StateM.mousepressed(vx, vy, button)
end

function love.mousemoved(x, y, dx, dy, istouch)
  if istouch then return end
  local vx, vy = Viewport.toVirtual(x, y)
  local s = Viewport.scale()
  StateM.mousemoved(vx, vy, dx / s, dy / s)
end

function love.mousereleased(x, y, button, istouch)
  if istouch then return end
  local vx, vy = Viewport.toVirtual(x, y)
  StateM.mousereleased(vx, vy, button)
end

function love.touchpressed(id, x, y)
  local vx, vy = Viewport.toVirtual(x, y)
  StateM.touchpressed(id, vx, vy)
end

function love.touchmoved(id, x, y)
  local vx, vy = Viewport.toVirtual(x, y)
  StateM.touchmoved(id, vx, vy)
end

function love.touchreleased(id, x, y)
  local vx, vy = Viewport.toVirtual(x, y)
  StateM.touchreleased(id, vx, vy)
end
