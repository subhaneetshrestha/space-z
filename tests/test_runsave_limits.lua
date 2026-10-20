-- tests/test_runsave_limits.lua — the size limits of a run save, and the guarantee that
-- the game never writes a save its own validation rejects.
--
-- The numbers come from `luajit tests/measure_runsave.lua` (a sweep of stress builds
-- through every zone and boss fight); see docs/enemy-state-save/measurements.md. Re-run
-- it and update MEASURED when the content changes.
local json = require("lib.json")
local RunSave = require("src.meta.runsave")
local Entities = require("src.meta.runsave_entities")
local Weapons = require("src.content.weapons")
local Zones = require("src.content.zones")
local Spawner = require("src.systems.spawner")
local Damage = require("src.systems.damage")
local Leveling = require("src.systems.leveling")
local Upgrades = require("src.content.upgrades")
local H = require("tests.game_harness")

local T = {}
local test = H.guarded(T)

local STEP = H.STEP

-- ------------------------------------------------------------------ the caps

-- the most of each kind alive at once in the measured sweep
local MEASURED = { enemies = 172, bullets = 131, ebullets = 93, pickups = 129 }
-- A cap only rejects corrupt files, so being generous costs nothing, but being tight
-- would throw away a real run: it must stay well above anything the game produces.
local HEADROOM = 4

for kind, peak in pairs(MEASURED) do
  local cap = ({ enemies = "MAX_ENEMIES", bullets = "MAX_BULLETS",
    ebullets = "MAX_EBULLETS", pickups = "MAX_PICKUPS" })[kind]
  T["cap_for_" .. kind .. "_keeps_headroom_over_the_measured_peak"] = function(t)
    t.ok(Entities[cap] >= HEADROOM * peak,
      string.format("%s = %d, but the game reached %d alive at once: want at least %dx", cap, Entities[cap], peak, HEADROOM))
  end
end

function T.cap_for_drones_covers_the_biggest_weapon_level_twice(t)
  local most = 0
  for _, def in pairs(Weapons) do
    if def.behavior == "orbital" then
      for _, lv in ipairs(def.levels) do most = math.max(most, lv.count) end
    end
  end
  t.ok(most >= 6, "fixture: the weapon data has an orbital weapon with 6 drones")
  t.ok(Entities.MAX_DRONES >= 2 * most, "MAX_DRONES = " .. Entities.MAX_DRONES)
end

-- ---------------------------------------------------------- real runs validate

-- Boundary bugs hide in values a hand-made fixture never holds: a bullet whose life is
-- 1e-16, a countdown a hair below zero. So play real runs and require EVERY sampled
-- autosave to validate, in the waves, through a boss fight, the warp, and the next zone.

local function updateGame(n)
  for _ = 1, n do H.Game:update(STEP) end
end

-- snapshot, send through json, validate: what an autosave then a Continue would do
local function checkSave(t, w, where)
  local run = RunSave.snapshot(w)
  if not run then return end
  local back = json.decode(json.encode(run))
  if not RunSave.validate(back) then
    t.ok(false, "the game wrote a save its own validation rejects: " .. where)
  end
  return #json.encode(run)
end

local function samplePlay(t, w, frames, tag, every)
  local biggest = 0
  for f = 1, frames do
    H.Game:update(STEP)
    if f % (every or 7) == 0 then
      biggest = math.max(biggest, checkSave(t, w, tag .. " frame " .. f) or 0)
    end
  end
  return biggest
end

-- a strong build: six weapons and the fire-rate and bullet-count passives
local function strongRun(seed)
  local w = H.start({ seed = seed })
  for _, id in ipairs({ "missiles", "flak", "cryo", "ion_arc", "drones" }) do
    Leveling.addWeapon(w, Weapons[id])
  end
  for i = 1, #w.weapons do w.weapons[i].level = w.weapons[i].def.maxLevel end
  for _, id in ipairs({ "ammo_feed", "overclock" }) do
    Leveling.addPassive(w, Upgrades[id])
    w.passives[#w.passives].level = Upgrades[id].maxLevel
  end
  Leveling.recomputeStats(w)
  return w
end

test("every_autosave_of_a_real_run_is_valid_through_waves_boss_and_warp", function(t)
  local w = strongRun(77)
  samplePlay(t, w, 60 * 40, "zone 1 waves")
  -- straight to the end of the timeline: the boss comes in, fights, is killed, warp, zone 2
  w.zoneTime = w.zone.duration
  w.spawnerState = { timers = {} }
  for i = 1, #w.weapons do w.weapons[i].cooldown = 3000 end -- a strong build would end it in seconds
  samplePlay(t, w, 60 * 8, "zone 1 boss entrance")
  t.eq(w.phase, "boss", "fixture: the boss fight began")
  samplePlay(t, w, 60 * 12, "zone 1 boss fight")
  Damage.direct(w, w.boss, 1e9, false)
  t.eq(w.phase, "warp", "fixture: the boss died")
  samplePlay(t, w, 60 * 4, "zone 1 warp", 3)
  t.eq(w.zoneIndex, 2, "fixture: the next zone began")
  samplePlay(t, w, 60 * 20, "zone 2 waves")
end)

test("every_autosave_of_a_crowded_late_zone_is_valid_and_far_under_the_size_budget", function(t)
  local w = strongRun(88)
  w.zoneIndex, w.zone, w.zoneTime = 7, Zones[7], 0
  w.spawnerState = { timers = {} }
  local biggest = samplePlay(t, w, 60 * 60, "zone 7 waves", 11)
  t.ok(biggest > 0, "fixture: saves were written")
  t.ok(biggest < 256 * 1024, "run.json reached " .. biggest .. " bytes; the budget is 256 KB")
end)

test("every_autosave_of_a_boss_barrage_is_valid", function(t)
  for _, zoneIndex in ipairs({ 2, 3, 5, 7 }) do
    local w = H.start({ seed = 900 + zoneIndex })
    for i = 1, #w.weapons do w.weapons[i].cooldown = 3000 end -- the boss keeps its full barrage
    w.zoneIndex, w.zone, w.zoneTime = zoneIndex, Zones[zoneIndex], Zones[zoneIndex].duration
    w.spawnerState = { timers = {} }
    samplePlay(t, w, 60 * 40, "boss of zone " .. zoneIndex, 9)
    t.eq(w.phase, "boss", "fixture: still fighting the boss of zone " .. zoneIndex)
  end
end)

return T
