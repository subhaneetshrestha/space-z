-- tests/game_harness.lua — shared setup for tests that drive the REAL game state
-- over the real state stack (test_game_resume, test_pause_save, test_app_lifecycle).
-- Only rendering and audio modules are stubbed (they need a window / sound
-- device); every system and save module is real. Not a test file: it is not in
-- tests/run.lua's FILES list.
local StateM = require("src.core.state")
local Save = require("src.meta.save")
local Leveling = require("src.systems.leveling")
local Weapons = require("src.content.weapons")
local Upgrades = require("src.content.upgrades")
local Support = require("tests.support")

local H = {}

local STEP = 1 / 60
H.STEP = STEP

-- Music has no sound device here, but a test can still ask what the game told it to
-- do: H.music is the list of { "play", key, zone } / { "stop" } calls since setup().
H.music = {}
local musicStub = setmetatable({}, {
  __index = function(_, name)
    return function(...) H.music[#H.music + 1] = { name, ... } end
  end,
})

local STUBS = {
  ["src.render.sprites"] = { batch = function() return Support.catchAll() end, add = Support.noop },
  ["src.render.starfield"] = { new = function() return Support.catchAll() end },
  ["src.render.particles"] = true,
  ["src.render.hud"] = true,
  ["src.audio.audio"] = true,
  ["src.audio.music"] = musicStub,
}

local gameoverParams
local hadLove

function H.gameoverParams() return gameoverParams end

function H.setup()
  hadLove = love ~= nil
  if not hadLove then
    love = { math = { random = math.random } } -- event handlers jitter pitch with it
  end
  H.Game = H.Game or Support.loadWithStubs("src.states.game", STUBS)
  H.Countdown = require("src.states.countdown")
  H.Pause = require("src.states.pause")
  while StateM.current() do StateM.pop() end
  StateM.register("game", H.Game)
  StateM.register("countdown", H.Countdown)
  StateM.register("pause", H.Pause)
  StateM.register("levelup", { translucent = true })
  StateM.register("gameover", { enter = function(_, p) gameoverParams = p end })
  StateM.register("menu", {})
  gameoverParams = nil
  H.music = {}
  Save.reset()
end

function H.teardown()
  while StateM.current() do StateM.pop() end
  if not hadLove then love = nil end
end

-- test(name, fn) registrar with setup/teardown guaranteed (see Support.guarded)
function H.guarded(T)
  return Support.guarded(T, H.setup, H.teardown)
end

-- Start a new run; the ship can't be killed by wandering enemies mid-test.
function H.start(params)
  params = params or {}
  params.seed = params.seed or 4242
  StateM.switch("game", params)
  H.Game.world.player.invulnT = 1e9
  return H.Game.world
end

function H.step(n)
  for _ = 1, n or 1 do StateM.update(STEP) end
end

function H.seconds(s)
  H.step(math.floor(s / STEP + 0.5))
end

-- A world that has been played a while: bigger build, damaged, spawner running.
function H.played(ship)
  Save.data().settings.ship = ship or "aegis"
  local w = H.start({ seed = 77 })
  Leveling.addWeapon(w, Weapons.missiles)
  w.weapons[2].level = 3
  Leveling.addPassive(w, Upgrades.hull_plating)
  w.passives[1].level = 2
  Leveling.recomputeStats(w)
  H.seconds(12)
  w.level, w.xp, w.xpNext, w.kills, w.noDamage = 6, 14.5, 40, 40, false
  w.player.hp = 37.5
  return w
end

-- name of the state on top of the stack
function H.top()
  local top = StateM.current()
  return top and top.__name
end

return H
