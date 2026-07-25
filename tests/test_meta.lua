-- tests/test_meta.lua — tech tree, ships, achievements, Black Hole scaling.
local Save = require("src.meta.save")
local Tech = require("src.meta.tech")
local Progress = require("src.meta.progress")
local Achievements = require("src.meta.achievements")
local Leveling = require("src.systems.leveling")
local Spawner = require("src.systems.spawner")
local Ships = require("src.content.ships")
local Weapons = require("src.content.weapons")
local Events = require("src.core.events")
local Pool = require("src.core.pool")
local RNG = require("src.core.rng")

local T = {}

function T.tech_costs_escalate(t)
  local node = Tech.node("hull")
  local prev = 0
  for rank = 1, node.maxRank do
    local c = Tech.cost(node, rank)
    t.ok(c > prev, "cost grows at rank " .. rank)
    prev = c
  end
end

function T.tech_buy_deducts_and_ranks(t)
  local data = Save.reset()
  data.stardust = 1000
  t.eq(Tech.buy(data, "hull"), true, "affordable buy succeeds")
  t.eq(Tech.rank(data, "hull"), 1)
  t.eq(data.stardust, 1000 - Tech.cost(Tech.node("hull"), 1), "stardust deducted")
  data.stardust = 0
  t.eq(Tech.buy(data, "hull"), false, "broke buy fails")
  t.eq(Tech.blocked(data, "hull"), "poor")
end

function T.tech_bonuses_fold_into_stats(t)
  local data = Save.reset()
  data.stardust = 100000
  Tech.buy(data, "hull")
  Tech.buy(data, "hull") -- +24 maxhp
  Tech.buy(data, "cannons") -- +4% damage
  local w = {
    player = { hp = 100, maxhp = 100, shipDef = Ships.pathfinder },
    weapons = {}, passives = {}, stats = nil,
  }
  Leveling.recomputeStats(w)
  t.eq(w.stats.maxhp, 124, "hull tech adds maxhp")
  t.near(w.stats.damageMult, 1.04, 1e-9, "cannon tech adds damage")
  Save.reset()
end

function T.ships_schema(t)
  t.eq(#Ships.order, 8, "eight ships")
  for _, id in ipairs(Ships.order) do
    local s = Ships[id]
    t.ok(s, id .. " exists")
    t.ok(s.maxhp and s.maxhp > 0, id .. " maxhp")
    t.ok(s.speed and s.speed > 0, id .. " speed")
    t.ok(Weapons[s.startingWeapon], id .. " starting weapon exists")
    t.ok(not Weapons[s.startingWeapon].evolution, id .. " does not start evolved")
    t.ok(s.price ~= nil, id .. " has a price")
    t.ok(s.sprite, id .. " sprite name")
  end
  t.eq(Ships.pathfinder.price, 0, "pathfinder is free")
end

function T.ship_bonuses_fold(t)
  Save.reset()
  local w = {
    player = { hp = 60, maxhp = 60, shipDef = Ships.nova },
    weapons = {}, passives = {}, stats = nil,
  }
  Leveling.recomputeStats(w)
  t.near(w.stats.damageMult, 1.30, 1e-9, "nova's +30% damage")
  t.eq(w.stats.maxhp, 60, "nova hull")
end

local function fakeRunWorld(over)
  local w = {
    mode = "standard",
    kills = 50, bossKills = 1, distance = 2000, stardustEarned = 0,
    level = 10, zoneIndex = 2, time = 200, noDamage = false,
    stats = { stardustMult = 1 },
  }
  for k, v in pairs(over or {}) do w[k] = v end
  return w
end

function T.blackhole_doubles_stardust(t)
  Save.reset()
  local base = Progress.endRun(fakeRunWorld(), false).stardust
  Save.reset()
  local bh = Progress.endRun(fakeRunWorld({ mode = "blackhole" }), false).stardust
  t.eq(bh, base * 2, "black hole pays double")
  t.eq(Save.data().bestDistanceBH, 2000, "BH best distance tracked separately")
  t.eq(Save.data().bestDistance, 0, "standard best untouched by a BH run")
  Save.reset()
end

function T.refinery_multiplies_stardust(t)
  Save.reset()
  local base = Progress.endRun(fakeRunWorld(), false).stardust
  Save.reset()
  local boosted = Progress.endRun(
    fakeRunWorld({ stats = { stardustMult = 1.30 } }), false).stardust
  t.eq(boosted, math.floor(base * 1.3), "refinery bonus applies")
  Save.reset()
end

function T.blackhole_spawner_scaling(t)
  local w = {
    events = Events.new(),
    rng = { spawn = RNG.new(1) },
    zone = require("src.content.zones")[1], zoneIndex = 1, zoneTime = 0,
    phase = "waves", mode = "blackhole",
    enemies = {}, ebullets = {},
    pools = { enemies = Pool.new(), ebullets = Pool.new() },
    player = { x = 240, y = 600 },
  }
  local e = Spawner.spawnEnemy(w, "drifter", 100, -30)
  t.eq(e.maxhp, 27, "18 hp x 1.5 in black hole mode")
end

function T.achievements_end_run(t)
  Save.reset()
  local w = fakeRunWorld({ noDamage = true })
  local summary = Progress.endRun(w, true)
  local ids = {}
  for _, def in ipairs(summary.newAchievements) do ids[def.id] = true end
  t.ok(ids.first_blood, "first kill achievement")
  t.ok(ids.savior, "win achievement")
  t.ok(ids.untouchable, "flawless win achievement")
  t.eq(summary.unlockedBlackhole, true, "flawless standard win reveals black hole")
  -- repeat run: no re-unlocks
  local again = Progress.endRun(fakeRunWorld(), true)
  for _, def in ipairs(again.newAchievements) do
    t.ok(def.id ~= "savior" and def.id ~= "first_blood", "no repeat unlocks")
  end
  Save.reset()
end

function T.daily_bests_track_and_persist(t)
  Save.reset()
  local today = os.date("%Y%m%d")
  local s1 = Progress.endRun(fakeRunWorld({ daily = true }), false)
  t.ok(s1.dailyBest, "daily summary present")
  t.eq(s1.dailyBest.date, today, "dated today")
  t.eq(s1.dailyBest.runs, 1)
  local first = s1.dailyBest.bestStardust
  t.ok(first > 0, "best recorded")
  -- worse run: best stands
  local s2 = Progress.endRun(fakeRunWorld({ daily = true, kills = 1, bossKills = 0,
    distance = 100, stardustEarned = 0 }), false)
  t.eq(s2.dailyBest.bestStardust, first, "worse run does not lower the best")
  t.eq(s2.dailyBest.runs, 2)
  -- stale daily from another date resets
  Save.data().daily = { date = "19990101", bestStardust = 9999, bestDistance = 1, runs = 5 }
  local s3 = Progress.endRun(fakeRunWorld({ daily = true }), false)
  t.eq(s3.dailyBest.date, today, "stale date rolls over")
  t.eq(s3.dailyBest.runs, 1, "run count reset with the new day")
  t.ok(s3.dailyBest.bestStardust < 9999, "old best cleared")
  -- non-daily runs never touch it
  local before = Save.data().daily.runs
  local s4 = Progress.endRun(fakeRunWorld(), false)
  t.eq(s4.dailyBest, nil, "non-daily run has no daily summary")
  t.eq(Save.data().daily.runs, before, "non-daily run does not count")
  Save.reset()
end

function T.new_settings_defaults(t)
  local d = Save.reset()
  t.eq(d.settings.quality, "high", "quality defaults high")
  t.eq(d.tutorialDone, false, "tutorial pending by default")
end

function T.achievements_live_events(t)
  Save.reset()
  local w = {
    events = Events.new(),
    toasts = {},
    mode = "standard",
  }
  Achievements.live(w)
  w.events:emit("level_up", 20)
  t.ok(Save.data().achievements.veteran, "veteran unlocks at level 20")
  t.eq(#w.toasts, 1, "toast queued")
  w.events:emit("weapon_evolved", Weapons.nuclear_barrage)
  t.ok(Save.data().achievements.evolved, "evolution achievement")
  w.events:emit("zone_completed", 2) -- reached zone 3
  t.ok(Save.data().achievements.scout, "zone 3 reach")
  t.ok(not Save.data().achievements.pathbreaker, "zone 5 not yet")
  w.events:emit("zone_completed", 6) -- reached zone 7
  t.ok(Save.data().achievements.pathbreaker, "zone 5 backfilled")
  t.ok(Save.data().achievements.edge_of_void, "zone 7 reach")
  Save.reset()
end

return T
