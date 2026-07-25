-- tests/test_spawner.lua — wave-timeline counts, seeded determinism, elite gating.
local Spawner = require("src.systems.spawner")
local Pool = require("src.core.pool")
local Events = require("src.core.events")
local RNG = require("src.core.rng")
local Zones = require("src.content.zones")

local T = {}

local function fakeWorld(seed)
  return {
    events = Events.new(),
    rng = { spawn = RNG.new(seed or 1) },
    zone = Zones[1], zoneIndex = 1, zoneTime = 0,
    phase = "waves",
    enemies = {},
    ebullets = {},
    pools = { enemies = Pool.new(), ebullets = Pool.new() },
    player = { x = 240, y = 600 },
    boss = nil,
  }
end

local function simulate(world, seconds)
  local dt = 1 / 60
  local steps = math.floor(seconds / dt + 0.5)
  for _ = 1, steps do
    world.zoneTime = world.zoneTime + dt
    Spawner.update(world, dt)
  end
end

function T.spawn_counts_match_timeline(t)
  local w = fakeWorld(1)
  simulate(w, 30)
  -- active streams in [0,30]: drifter t=0 interval=1.5 count=1, shard t=15 interval=2.2 count=2
  -- drifter: spawns at 0,1.5,...,<=30 -> floor(30/1.5)+1 = 21
  -- shard: opens at 15, spawns at 15,17.2,...  floor(15/2.2)+1 = 7 volleys of 2 = 14
  local drifters, shards = 0, 0
  for i = 1, #w.enemies do
    local id = w.enemies[i].def.id
    if id == "drifter" then drifters = drifters + 1 end
    if id == "shard" then shards = shards + 1 end
  end
  t.ok(drifters >= 20 and drifters <= 22, "drifter count ~21, got " .. drifters)
  t.ok(shards >= 12 and shards <= 16, "shard count ~14, got " .. shards)
end

function T.seeded_determinism(t)
  local a = fakeWorld(777)
  local b = fakeWorld(777)
  simulate(a, 20)
  simulate(b, 20)
  t.eq(#a.enemies, #b.enemies, "same spawn count")
  for i = 1, #a.enemies do
    t.eq(a.enemies[i].x, b.enemies[i].x, "same x at " .. i)
    t.eq(a.enemies[i].def.id, b.enemies[i].def.id, "same enemy at " .. i)
  end
end

function T.no_elites_before_45s(t)
  local w = fakeWorld(5)
  simulate(w, 44)
  for i = 1, #w.enemies do
    t.ok(not w.enemies[i].elite, "no elites before 45s")
  end
end

function T.spawn_positions_in_margins(t)
  local w = fakeWorld(3)
  simulate(w, 30)
  for i = 1, #w.enemies do
    local e = w.enemies[i]
    t.ok(e.x >= 30 and e.x <= 450, "x within margins, got " .. e.x)
    t.eq(e.y, -30, "spawns above the top edge")
  end
end

function T.hp_scales_with_zone_time(t)
  local w = fakeWorld(1)
  local early = Spawner.spawnEnemy(w, "drifter", 100, -30)
  w.zoneTime = 120
  local late = Spawner.spawnEnemy(w, "drifter", 100, -30)
  t.eq(early.maxhp, 18, "no scaling at t=0")
  t.eq(late.maxhp, 36, "hp doubles at 120s (1 + 0.5*2)")
end

function T.elite_stats(t)
  local w = fakeWorld(1)
  local e = Spawner.spawnEnemy(w, "drifter", 100, -30, { elite = true })
  t.eq(e.maxhp, 18 * 4, "elite hp x4")
  t.eq(e.touchDamage, 12, "elite touch damage x1.5")
  t.eq(e.xp, 5, "elite xp x5")
  t.near(e.scale, 1.4, 1e-9, "elite scale")
end

function T.boss_transition_when_clear(t)
  local w = fakeWorld(1)
  w.zoneTime = Zones[1].duration + 0.1
  -- field is empty -> boss phase begins immediately
  local bossSpawned = nil
  w.events:on("boss_spawned", function(b) bossSpawned = b end)
  Spawner.update(w, 1 / 60)
  t.eq(w.phase, "boss", "phase flips to boss")
  t.ok(bossSpawned ~= nil, "boss_spawned emitted")
  t.ok(w.boss ~= nil, "world.boss set")
  t.eq(w.boss.entering, true, "boss enters invulnerable")
end

function T.boss_waits_for_field_to_clear(t)
  local w = fakeWorld(1)
  -- 10 live enemies block the boss
  for i = 1, 10 do
    Spawner.spawnEnemy(w, "drifter", 50 + i * 20, 100)
  end
  w.zoneTime = Zones[1].duration + 0.1
  Spawner.update(w, 1 / 60)
  t.eq(w.phase, "waves", "boss waits while the field is crowded")
  -- kill most of them
  for i = 1, 7 do w.enemies[i].dead = true end
  Spawner.update(w, 1 / 60)
  t.eq(w.phase, "boss", "boss arrives once the field clears")
end

return T
