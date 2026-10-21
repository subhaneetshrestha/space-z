-- tests/measure_runsave.lua — how big and how slow a run save gets in the worst case.
-- Not part of the suite (it is slow and prints numbers instead of asserting); run it
-- from the repo root when the game's content or the save format changes:
--
--   luajit tests/measure_runsave.lua            -- full sweep (a few minutes)
--   luajit tests/measure_runsave.lua quick      -- one zone per build, for a sanity check
--
-- It plays stress builds through the REAL game state, every zone and its boss fight,
-- and records (a) the most entities of each kind alive at once and (b) the cost and
-- size of an actual autosave (snapshot, JSON encode, decode, validate) sampled
-- through the run and at every new peak of total entities. The caps in
-- src/meta/runsave_entities.lua and the checks in tests/test_runsave_limits.lua come
-- from this output; the results are written up in docs/enemy-state-save/measurements.md.
package.path = "./?.lua;./?/init.lua;" .. package.path

local H = require("tests.game_harness")
local RunSave = require("src.meta.runsave")
local Leveling = require("src.systems.leveling")
local Weapons = require("src.content.weapons")
local Upgrades = require("src.content.upgrades")
local Zones = require("src.content.zones")
local json = require("lib.json")

local quick = arg and arg[1] == "quick"
local STEP = H.STEP
local clock = os.clock

-- ----------------------------------------------------------------- the builds

-- six weapons at their top level, and the passives that make the most bullets
local BUILDS = {
  maxed_base = {
    weapons = { "missiles", "flak", "cryo", "ion_arc", "drones" },
  },
  all_evolved = {
    weapons = { "nuclear_barrage", "buckshot_nova", "absolute_zero", "ion_storm", "battle_constellation" },
    replaceStarter = "plasma_storm",
  },
}
local PASSIVES = { "ammo_feed", "overclock", "reactor_core", "tractor_beam", "hull_plating", "coolant" }

local function newRun(buildName, mode, seed)
  local build = BUILDS[buildName]
  local w = H.start({ seed = seed, mode = mode })
  for _, id in ipairs(build.weapons) do Leveling.addWeapon(w, Weapons[id]) end
  if build.replaceStarter then w.weapons[1].def = Weapons[build.replaceStarter] end
  for i = 1, #w.weapons do w.weapons[i].level = w.weapons[i].def.maxLevel end
  for _, id in ipairs(PASSIVES) do
    Leveling.addPassive(w, Upgrades[id])
    w.passives[#w.passives].level = Upgrades[id].maxLevel
  end
  Leveling.recomputeStats(w)
  return w
end

-- ----------------------------------------------------------------- recording

local peaks = { enemies = 0, bullets = 0, ebullets = 0, pickups = 0, drones = 0, total = 0 }
local where = {}
local worst = { snapshot = 0, encode = 0, decode = 0, validate = 0, total = 0, bytes = 0 }
local worstWhere = {}
local samples = {}
local label = ""

local function note(map, key, value, scenario)
  if value > map[key] then
    map[key] = value
    where[key] = scenario
  end
end

local function counts(w)
  return #w.enemies, #w.bullets, #w.ebullets, #w.pickups, #w.drones
end

-- os.clock only ticks about once a millisecond on Windows, so each piece is timed over
-- REPS repeats and divided
local REPS = 20

local function timed(fn)
  local result
  local t0 = clock()
  for _ = 1, REPS do result = fn() end
  return result, (clock() - t0) / REPS
end

-- One real autosave's worth of work, timed in pieces (CPU seconds per call).
local function sampleSave(w)
  local run, tSnapshot = timed(function() return RunSave.snapshot(w) end)
  if not run then return end
  local text, tEncode = timed(function() return json.encode(run) end)
  local back, tDecode = timed(function() return json.decode(text) end)
  local ok, tValidate = timed(function() return RunSave.validate(back) end)
  local t1, t2, t3, t4 = tSnapshot, tSnapshot + tEncode, tSnapshot + tEncode + tDecode,
    tSnapshot + tEncode + tDecode + tValidate
  local t0 = 0
  if not ok then
    -- a real run must always be a valid save: name the first list and entry that is not
    local Entities = require("src.meta.runsave_entities")
    local function blame(name, list, check)
      for i = 1, #list do
        if not check({ list[i] }) then
          return string.format("%s[%d] = %s", name, i, json.encode(list[i]))
        end
      end
    end
    local culprit = blame("enemies", back.enemies, Entities.validEnemies)
      or blame("ebullets", back.ebullets, Entities.validEbullets)
      or blame("pickups", back.pickups, Entities.validPickups)
      or blame("bullets", back.bullets, function(l) return Entities.validBullets(l, #back.enemies + 1e9) end)
      or ("(not an entity list) player=" .. json.encode(back.player) .. " timers=" .. json.encode(back.timers)
        .. " phase=" .. tostring(back.phase) .. " zoneTime=" .. tostring(back.zoneTime))
    error("a snapshot of a real run failed validation: " .. label .. "\n  " .. culprit, 0)
  end
  local m = { snapshot = t1 - t0, encode = t2 - t1, decode = t3 - t2, validate = t4 - t3, bytes = #text }
  m.total = m.snapshot + m.encode -- what an autosave pays on the game thread
  samples[#samples + 1] = m.total
  for k, v in pairs(m) do
    if v > worst[k] then worst[k], worstWhere[k] = v, label end
  end
end

local function watch(w, frames, silence)
  local lastSample, lastPeakSample = 0, -1e9
  for f = 1, frames do
    if silence then
      for i = 1, #w.weapons do w.weapons[i].cooldown = 3000 end
    end
    H.Game:update(STEP)
    local e, b, eb, p, d = counts(w)
    local total = e + b + eb + p + d
    note(peaks, "enemies", e, label); note(peaks, "bullets", b, label)
    note(peaks, "ebullets", eb, label); note(peaks, "pickups", p, label)
    note(peaks, "drones", d, label); note(peaks, "total", total, label)
    if f - lastSample >= 180 or (total >= peaks.total and f - lastPeakSample >= 30) then
      if f - lastSample >= 180 then lastSample = f end
      if total >= peaks.total then lastPeakSample = f end
      sampleSave(w)
    end
  end
end

-- ------------------------------------------------------------------ scenarios

local function enterZone(w, z)
  w.zoneIndex, w.zone, w.zoneTime = z, Zones[z], 0
  w.phase, w.warpT, w.boss = "waves", 0, nil
  w.spawnerState = { timers = {} }
end

-- the whole zone (waves), then its boss fight
local function playZone(w, z, tag, silence)
  enterZone(w, z)
  label = tag .. " zone " .. z .. " waves"
  watch(w, math.floor(Zones[z].duration / STEP), silence)
  label = tag .. " zone " .. z .. " boss"
  watch(w, 60 * 90, true) -- the boss is left alone to keep up its full barrage
end

local started = clock()
H.setup()

local zones = quick and { 7 } or { 1, 2, 3, 4, 5, 6, 7 }
for buildName in pairs(BUILDS) do
  for _, z in ipairs(zones) do
    local w = newRun(buildName, "standard", 1000 + z)
    w.stats.magnetRadius = 0 -- gems pile up instead of being collected
    playZone(w, z, buildName .. "/standard/uncollected", false)
  end
  local bw = newRun(buildName, "blackhole", 2000) -- enemies have 1.5x health: they live longer
  playZone(bw, 7, buildName .. "/blackhole", false)
end

-- the enemy flood: nothing shoots, so every wave stays alive until it flies off screen
for _, z in ipairs(zones) do
  local w = newRun("maxed_base", "standard", 3000 + z)
  playZone(w, z, "flood/standard", true)
end

-- ------------------------------------------------------------------- report

table.sort(samples)
local function pct(p) return samples[math.max(1, math.ceil(#samples * p))] or 0 end

print(string.format("measured in %.0f s of CPU, %d autosave samples", clock() - started, #samples))
print("")
print("| most alive at once | count | where |")
print("|---|---|---|")
for _, k in ipairs({ "enemies", "bullets", "ebullets", "pickups", "drones", "total" }) do
  print(string.format("| %s | %d | %s |", k, peaks[k], where[k] or "-"))
end
print("")
print("| one autosave on the game thread (ms, LuaJIT, this machine) | worst | where |")
print("|---|---|---|")
print(string.format("| snapshot | %.3f | %s |", worst.snapshot * 1000, worstWhere.snapshot or "-"))
print(string.format("| json.encode | %.3f | %s |", worst.encode * 1000, worstWhere.encode or "-"))
print(string.format("| snapshot + encode | %.3f | %s |", worst.total * 1000, worstWhere.total or "-"))
print(string.format("| (at resume only) decode | %.3f | %s |", worst.decode * 1000, worstWhere.decode or "-"))
print(string.format("| (at resume only) validate | %.3f | %s |", worst.validate * 1000, worstWhere.validate or "-"))
print(string.format("| snapshot + encode, median / 95th percentile | %.3f / %.3f | all samples |",
  pct(0.5) * 1000, pct(0.95) * 1000))
print(string.format("| run.json size (bytes) | %d | %s |", worst.bytes, worstWhere.bytes or "-"))
